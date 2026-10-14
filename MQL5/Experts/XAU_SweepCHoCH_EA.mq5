//+------------------------------------------------------------------+
//|                                           XAU_SweepCHoCH_EA.mq5  |
//|   XAUUSD "ท่าเดิม ต้นทุนต่ำ" : Liquidity Sweep + CHoCH + FVG       |
//|   State Machine 6 สถานะ ตามพิมพ์เขียว EA (ส่วนที่ 3)               |
//+------------------------------------------------------------------+
#property copyright "OK-J.E"
#property version   "1.00"
#property description "XAUUSD Liquidity Sweep + CHoCH (FVG) EA with killzone, spread, news filters,"
#property description "ATR-based SL, risk-% lot sizing, partial close 50% @1.5R, BE, M15 swing trailing,"
#property description "daily circuit breaker. All session times are Thai time (GMT+7)."

#include <Trade/Trade.mqh>

//--- enums
enum ENUM_EA_STATE
  {
   ST_IDLE = 1,       // STATE 1: IDLE & FILTER
   ST_SWEEP = 2,      // STATE 2: LIQUIDITY SWEEP (detected, wait CHoCH)
   ST_CHOCH = 3,      // STATE 3: CHoCH CONFIRM
   ST_RISK = 4,       // STATE 4: RISK & LIMIT ORDER
   ST_ORDER = 5,      // STATE 5: ORDER ACTIVE (pending)
   ST_TRADE = 6       // STATE 6: TRADE MANAGEMENT
  };

//--- inputs
input group "=== ความเสี่ยง (Risk) ==="
input double InpRiskPercent      = 1.0;    // Risk % ต่อไม้ (0.5 - 1.0)
input double InpTP_R             = 3.0;    // TP หลัก (R)
input double InpPartialR         = 1.5;    // แบ่งปิดกำไรที่ (R)
input double InpPartialRatio     = 0.5;    // สัดส่วนแบ่งปิด (0.5 = 50%)
input int    InpBEBufferPoints   = 20;     // บังทุน: Entry + จุดเผื่อค่าคอม/สเปรด (points)
input bool   InpUseSwingTrail    = true;   // เลื่อน SL ตาม Swing M15 หลังแบ่งปิด
input int    InpMinSLPoints      = 180;    // ระยะ SL ขั้นต่ำ (points)
input int    InpMaxSLPoints      = 600;    // ระยะ SL สูงสุด (points)
input double InpSLBufferATR      = 0.2;    // ระยะเผื่อ SL = x * ATR(M5)

input group "=== Circuit Breaker รายวัน ==="
input int    InpMaxConsecLosses  = 2;      // แพ้ติดต่อกันกี่ไม้ให้หยุดวันนั้น
input double InpMaxDailyLossPct  = 2.0;    // ขาดทุนรวมสูงสุดต่อวัน (%)

input group "=== โครงสร้างตลาด (Structure) ==="
input int    InpATRPeriod        = 14;     // ATR period
input int    InpFractalBars      = 3;      // Fractal ซ้าย/ขวา (แท่ง)
input double InpSwingLegATR      = 1.0;    // ขา Swing ต้องยาว >= x * ATR (1.0 - 1.5)
input double InpSweepMaxATR      = 1.5;    // Sweep ทะลุได้ไม่เกิน x * ATR(M15)
input int    InpChochMaxBars     = 15;     // รอ CHoCH บน M5 ไม่เกิน (แท่ง)
input double InpFVGEntryLevel    = 0.5;    // จุดเข้าใน FVG (0=ขอบใกล้, 0.5=กึ่งกลาง, 1=ขอบไกล)
input int    InpOrderExpiryBars  = 12;     // ลบ Limit ถ้าไม่ถูกเกี่ยวภายใน (แท่ง M5)
input double InpCancelAtR        = 2.0;    // ลบ Limit ถ้าราคาวิ่งไปถึง xR ก่อนมารับ
input bool   InpUseAsianLevels   = true;   // ใช้ Asian High/Low เป็นจุดสภาพคล่อง
input bool   InpUsePrevDayLevels = true;   // ใช้ High/Low วันก่อนหน้า
input bool   InpUseH1SwingLevels = true;   // ใช้ Swing High/Low H1
input bool   InpUseEquilibrium   = false;  // Buy เฉพาะ Discount / Sell เฉพาะ Premium (กรอบ H1)

input group "=== เวลา (เวลาไทย GMT+7) ==="
input int    InpServerGMTOffset  = 3;      // GMT offset ของเซิร์ฟเวอร์ (ใช้ใน Tester / ถ้าปิด Auto)
input bool   InpAutoServerOffset = true;   // คำนวณ GMT offset อัตโนมัติ (Live เท่านั้น)
input bool   InpWinterShift      = true;   // หน้าหนาว (พ.ย.-มี.ค.) เลื่อนเวลาตลาดช้าลง 1 ชม.
input string InpAsianStart       = "06:00";// ตลาดเอเชีย เริ่ม
input string InpAsianEnd         = "14:00";// ตลาดเอเชีย สิ้นสุด
input string InpLondonStart      = "14:00";// London Killzone เริ่ม
input string InpLondonEnd        = "17:00";// London Killzone สิ้นสุด
input string InpNYStart          = "19:00";// NY Killzone เริ่ม
input string InpNYEnd            = "22:30";// NY Killzone สิ้นสุด
input bool   InpWeekendFilter    = true;   // ห้ามเทรด ศุกร์หลัง 22:00 / จันทร์ก่อน 14:00

input group "=== ตัวกรอง (Filters) ==="
input int    InpMaxSpreadPoints  = 40;     // Spread สูงสุด (points)
input bool   InpUseNewsFilter    = true;   // กรองข่าวแดง USD (MQL5 Calendar)
input int    InpNewsMinutesBefore= 30;     // หยุดก่อนข่าว (นาที)
input int    InpNewsMinutesAfter = 30;     // หยุดหลังข่าว (นาที)

input group "=== อื่น ๆ ==="
input ulong  InpMagic            = 260101; // Magic Number
input int    InpSlippagePoints   = 30;     // Slippage (points)
input bool   InpShowPanel        = true;   // แสดงข้อมูลบนกราฟ
input bool   InpDrawLevels       = true;   // วาดเส้น Asian / PDH / PDL

//--- globals
CTrade         trade;
ENUM_EA_STATE  g_state = ST_IDLE;
int            hATR_M5 = INVALID_HANDLE, hATR_M15 = INVALID_HANDLE, hATR_H1 = INVALID_HANDLE;

// session minutes (Thai time)
int            mAsianS, mAsianE, mLonS, mLonE, mNYS, mNYE;

// daily
datetime       g_dayKey = 0;
double         g_dayStartBalance = 0;
int            g_consecLosses = 0;
int            g_dailyLossCount = 0;
bool           g_dayLocked = false;
double         g_asianHigh = 0, g_asianLow = 0;
bool           g_asianReady = false;
double         g_pdh = 0, g_pdl = 0;
double         g_sweptLevels[];          // levels already swept today

// setup
int            g_dir = 0;                // +1 buy, -1 sell
double         g_sweepLevel = 0;
string         g_sweepName = "";
double         g_extreme = 0;
double         g_internalSwing = 0;
datetime       g_sweepBarTime = 0;
double         g_fvgUpper = 0, g_fvgLower = 0;

// order / trade
ulong          g_orderTicket = 0;
ulong          g_posId = 0;
datetime       g_orderBarTime = 0;
double         g_entry = 0, g_sl = 0, g_tp = 0, g_riskDist = 0, g_lot = 0;
bool           g_partialDone = false;

// misc
datetime       g_lastM5Bar = 0;
datetime       g_newsCheckTime = 0;
bool           g_newsBlocked = false;
string         g_newsInfo = "";
string         g_lastMsg = "";

//+------------------------------------------------------------------+
//| Helpers: time                                                    |
//+------------------------------------------------------------------+
int ParseHHMM(const string s)
  {
   string parts[];
   if(StringSplit(s, ':', parts) != 2) return 0;
   return (int)StringToInteger(parts[0]) * 60 + (int)StringToInteger(parts[1]);
  }

int ServerOffsetSec()
  {
   if(InpAutoServerOffset && !MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
     {
      long diff = (long)(TimeTradeServer() - TimeGMT());
      return (int)(MathRound(diff / 1800.0) * 1800);
     }
   return InpServerGMTOffset * 3600;
  }

datetime ToThai(const datetime server)   { return server - ServerOffsetSec() + 7 * 3600; }
datetime ToServer(const datetime thai)   { return thai + ServerOffsetSec() - 7 * 3600; }

int MinuteOfDay(const datetime t)
  {
   MqlDateTime d; TimeToStruct(t, d);
   return d.hour * 60 + d.min;
  }

datetime DayStart(const datetime t) { return t - (t % 86400); }

int SessionShift(const datetime thai)
  {
   if(!InpWinterShift) return 0;
   MqlDateTime d; TimeToStruct(thai, d);
   return (d.mon >= 11 || d.mon <= 3) ? 60 : 0;
  }

bool InWindow(const int m, const int s, const int e) { return (s <= e) ? (m >= s && m < e) : (m >= s || m < e); }

bool InKillzone(const datetime thai)
  {
   int sh = SessionShift(thai);
   int m  = MinuteOfDay(thai);
   return InWindow(m, mLonS + sh, mLonE + sh) || InWindow(m, mNYS + sh, mNYE + sh);
  }

bool WeekendBlocked(const datetime thai)
  {
   if(!InpWeekendFilter) return false;
   MqlDateTime d; TimeToStruct(thai, d);
   int m = d.hour * 60 + d.min;
   if(d.day_of_week == 5 && m >= 22 * 60) return true;
   if(d.day_of_week == 1 && m < 14 * 60) return true;
   if(d.day_of_week == 6 || d.day_of_week == 0) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Helpers: data                                                    |
//+------------------------------------------------------------------+
double ATR(const int handle, const int shift)
  {
   double b[];
   if(CopyBuffer(handle, 0, shift, 1, b) != 1) return 0;
   return b[0];
  }

bool IsFractalHigh(const ENUM_TIMEFRAMES tf, const int s, const int n)
  {
   double h = iHigh(_Symbol, tf, s);
   for(int i = 1; i <= n; i++)
      if(iHigh(_Symbol, tf, s - i) >= h || iHigh(_Symbol, tf, s + i) > h) return false;
   return true;
  }

bool IsFractalLow(const ENUM_TIMEFRAMES tf, const int s, const int n)
  {
   double l = iLow(_Symbol, tf, s);
   for(int i = 1; i <= n; i++)
      if(iLow(_Symbol, tf, s - i) <= l || iLow(_Symbol, tf, s + i) < l) return false;
   return true;
  }

// Latest confirmed swing high/low. legATR>0 => ขา swing ต้องยาว >= legATR*ATR
double LastSwing(const ENUM_TIMEFRAMES tf, const bool high, const int atrHandle, const double legATR,
                 const int lookback, int &shiftOut)
  {
   int n = InpFractalBars;
   for(int s = n + 1; s < lookback; s++)
     {
      bool ok = high ? IsFractalHigh(tf, s, n) : IsFractalLow(tf, s, n);
      if(!ok) continue;
      if(legATR > 0 && atrHandle != INVALID_HANDLE)
        {
         double atr = ATR(atrHandle, s);
         int cnt = 10;
         double leg;
         if(high)
           {
            int li = iLowest(_Symbol, tf, MODE_LOW, cnt, s + 1);
            leg = iHigh(_Symbol, tf, s) - iLow(_Symbol, tf, li);
           }
         else
           {
            int hi = iHighest(_Symbol, tf, MODE_HIGH, cnt, s + 1);
            leg = iHigh(_Symbol, tf, hi) - iLow(_Symbol, tf, s);
           }
         if(atr <= 0 || leg < legATR * atr) continue;
        }
      shiftOut = s;
      return high ? iHigh(_Symbol, tf, s) : iLow(_Symbol, tf, s);
     }
   shiftOut = -1;
   return 0;
  }

double SpreadPoints()
  {
   return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
  }

//+------------------------------------------------------------------+
//| News filter (MQL5 Economic Calendar, USD high impact)            |
//+------------------------------------------------------------------+
bool NewsBlocked()
  {
   if(!InpUseNewsFilter) return false;
   if(MQLInfoInteger(MQL_TESTER)) return false; // Calendar ใช้ไม่ได้ใน Strategy Tester
   datetime now = TimeTradeServer();
   if(now - g_newsCheckTime < 60) return g_newsBlocked;
   g_newsCheckTime = now;
   g_newsBlocked = false;
   g_newsInfo = "";

   MqlCalendarValue values[];
   datetime from = now - InpNewsMinutesAfter * 60;
   datetime to   = now + InpNewsMinutesBefore * 60;
   if(CalendarValueHistory(values, from, to, NULL, "USD") <= 0) return false;
   for(int i = 0; i < ArraySize(values); i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      g_newsBlocked = true;
      g_newsInfo = ev.name + " @ " + TimeToString(ToThai(values[i].time), TIME_MINUTES) + " TH";
      break;
     }
   return g_newsBlocked;
  }

//+------------------------------------------------------------------+
//| Daily reset & levels                                             |
//+------------------------------------------------------------------+
void DailyUpdate()
  {
   datetime thai = ToThai(TimeCurrent());
   datetime key  = DayStart(thai);
   if(key != g_dayKey)
     {
      g_dayKey = key;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_consecLosses = 0;
      g_dailyLossCount = 0;
      g_dayLocked = false;
      g_asianReady = false;
      g_asianHigh = g_asianLow = 0;
      ArrayResize(g_sweptLevels, 0);
      g_pdh = iHigh(_Symbol, PERIOD_D1, 1);
      g_pdl = iLow(_Symbol, PERIOD_D1, 1);
      Print("New trading day (TH) ", TimeToString(key, TIME_DATE), " start balance ", DoubleToString(g_dayStartBalance, 2));
     }

   // Asian range: 06:00-14:00 TH (เลื่อนตามหน้าหนาว)
   if(!g_asianReady)
     {
      int sh = SessionShift(thai);
      int aS = mAsianS + sh, aE = mAsianE + sh;
      if(MinuteOfDay(thai) >= aE)
        {
         datetime sStart = ToServer(key + aS * 60);
         datetime sEnd   = ToServer(key + aE * 60) - 1;
         double hi[], lo[];
         int c1 = CopyHigh(_Symbol, PERIOD_M5, sStart, sEnd, hi);
         int c2 = CopyLow(_Symbol, PERIOD_M5, sStart, sEnd, lo);
         if(c1 > 0 && c2 > 0)
           {
            g_asianHigh = hi[ArrayMaximum(hi)];
            g_asianLow  = lo[ArrayMinimum(lo)];
            g_asianReady = true;
            if(InpDrawLevels)
              {
               DrawLevel("XSC_AsianHigh", g_asianHigh, clrDodgerBlue);
               DrawLevel("XSC_AsianLow", g_asianLow, clrDodgerBlue);
              }
           }
        }
     }
   if(InpDrawLevels)
     {
      DrawLevel("XSC_PDH", g_pdh, clrOrange);
      DrawLevel("XSC_PDL", g_pdl, clrOrange);
     }

   // Circuit breaker
   if(!g_dayLocked && g_dayStartBalance > 0)
     {
      double ddPct = (AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartBalance) / g_dayStartBalance * 100.0;
      if(g_consecLosses >= InpMaxConsecLosses || ddPct <= -InpMaxDailyLossPct)
        {
         g_dayLocked = true;
         Print("Daily circuit breaker: consecLosses=", g_consecLosses, " DD%=", DoubleToString(ddPct, 2));
        }
     }
  }

void DrawLevel(const string name, const double price, const color clr)
  {
   if(price <= 0) return;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, name, OBJPROP_TEXT, name);
     }
   else
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
  }

bool AlreadySwept(const double lvl)
  {
   for(int i = 0; i < ArraySize(g_sweptLevels); i++)
      if(MathAbs(g_sweptLevels[i] - lvl) < _Point) return true;
   return false;
  }

void MarkSwept(const double lvl)
  {
   int n = ArraySize(g_sweptLevels);
   ArrayResize(g_sweptLevels, n + 1);
   g_sweptLevels[n] = lvl;
  }

//+------------------------------------------------------------------+
//| State helpers                                                    |
//+------------------------------------------------------------------+
void ResetSetup(const string why)
  {
   if(why != "") { g_lastMsg = why; Print("Reset -> IDLE: ", why); }
   g_state = ST_IDLE;
   g_dir = 0;
   g_sweepLevel = g_extreme = g_internalSwing = 0;
   g_fvgUpper = g_fvgLower = 0;
   g_sweepName = "";
   g_orderTicket = 0;
   g_posId = 0;
   g_partialDone = false;
  }

bool FiltersOK(string &why)
  {
   datetime thai = ToThai(TimeCurrent());
   if(g_dayLocked)                         { why = "Daily locked (circuit breaker)"; return false; }
   if(WeekendBlocked(thai))                { why = "Weekend/Monday filter"; return false; }
   if(!InKillzone(thai))                   { why = "Outside killzone"; return false; }
   if(SpreadPoints() > InpMaxSpreadPoints) { why = "Spread too high"; return false; }
   if(NewsBlocked())                       { why = "News: " + g_newsInfo; return false; }
   why = "OK";
   return true;
  }

//+------------------------------------------------------------------+
//| STATE 2: Liquidity sweep detection on closed M15 bars            |
//+------------------------------------------------------------------+
bool CheckSweepAt(const double lvl, const bool upper, const string name, const double atr15)
  {
   if(lvl <= 0 || AlreadySwept(lvl)) return false;
   double h1 = iHigh(_Symbol, PERIOD_M15, 1), l1 = iLow(_Symbol, PERIOD_M15, 1), c1 = iClose(_Symbol, PERIOD_M15, 1);
   double h2 = iHigh(_Symbol, PERIOD_M15, 2), l2 = iLow(_Symbol, PERIOD_M15, 2), c2 = iClose(_Symbol, PERIOD_M15, 2);
   double c3 = iClose(_Symbol, PERIOD_M15, 3);
   double maxPen = InpSweepMaxATR * atr15;

   if(upper)
     {
      if(c3 >= lvl) return false;                 // ต้องมาจากในกรอบ
      double ext = MathMax(h1, h2);
      if(ext <= lvl || c1 >= lvl) return false;    // ทะลุแล้วปิดกลับเข้ากรอบภายใน 1-2 แท่ง
      if(ext - lvl > maxPen) { MarkSwept(lvl); return false; } // Breakout จริง
      if(c2 - lvl > maxPen) return false;
      g_dir = -1; g_extreme = ext;
     }
   else
     {
      if(c3 <= lvl) return false;
      double ext = MathMin(l1, l2);
      if(ext >= lvl || c1 <= lvl) return false;
      if(lvl - ext > maxPen) { MarkSwept(lvl); return false; }
      if(lvl - c2 > maxPen) return false;
      g_dir = 1; g_extreme = ext;
     }

   // Equilibrium filter (H1 dealing range)
   if(InpUseEquilibrium)
     {
      int sH, sL;
      double rh = LastSwing(PERIOD_H1, true, hATR_H1, InpSwingLegATR, 200, sH);
      double rl = LastSwing(PERIOD_H1, false, hATR_H1, InpSwingLegATR, 200, sL);
      if(rh > 0 && rl > 0 && rh > rl)
        {
         double eq = (rh + rl) / 2.0;
         double px = iClose(_Symbol, PERIOD_M15, 1);
         if((g_dir > 0 && px > eq) || (g_dir < 0 && px < eq))
           { g_dir = 0; MarkSwept(lvl); return false; }
        }
     }

   // internal M5 swing (ฝั่งตรงข้าม) ที่ต้องปิดทะลุเพื่อยืนยัน CHoCH
   int s;
   g_internalSwing = LastSwing(PERIOD_M5, g_dir < 0 ? false : true, INVALID_HANDLE, 0, 60, s);
   if(g_internalSwing <= 0) { g_dir = 0; return false; }
   if((g_dir < 0 && g_internalSwing >= lvl) || (g_dir > 0 && g_internalSwing <= lvl)) { g_dir = 0; return false; }

   g_sweepLevel = lvl;
   g_sweepName = name;
   g_sweepBarTime = iTime(_Symbol, PERIOD_M5, 0);
   MarkSwept(lvl);
   g_state = ST_SWEEP;
   g_lastMsg = StringFormat("Sweep %s %s @%.2f ext=%.2f internal=%.2f", name, g_dir > 0 ? "LOW->BUY" : "HIGH->SELL",
                            lvl, g_extreme, g_internalSwing);
   Print(g_lastMsg);
   return true;
  }

void DetectSweep()
  {
   double atr15 = ATR(hATR_M15, 1);
   if(atr15 <= 0) return;

   if(InpUseAsianLevels && g_asianReady)
     {
      if(CheckSweepAt(g_asianHigh, true, "AsianHigh", atr15)) return;
      if(CheckSweepAt(g_asianLow, false, "AsianLow", atr15)) return;
     }
   if(InpUsePrevDayLevels)
     {
      if(CheckSweepAt(g_pdh, true, "PDH", atr15)) return;
      if(CheckSweepAt(g_pdl, false, "PDL", atr15)) return;
     }
   if(InpUseH1SwingLevels)
     {
      int s;
      double sh = LastSwing(PERIOD_H1, true, hATR_H1, InpSwingLegATR, 200, s);
      if(CheckSweepAt(sh, true, "H1SwingHigh", atr15)) return;
      double sl = LastSwing(PERIOD_H1, false, hATR_H1, InpSwingLegATR, 200, s);
      if(CheckSweepAt(sl, false, "H1SwingLow", atr15)) return;
     }
  }

//+------------------------------------------------------------------+
//| STATE 3: CHoCH + FVG on M5                                       |
//+------------------------------------------------------------------+
bool FindFVG(const int dir, double &upper, double &lower)
  {
   // ตรวจ 2 ชุดล่าสุด: แท่ง (1,2,3) และ (2,3,4)
   for(int k = 1; k <= 2; k++)
     {
      if(dir > 0)
        {
         double hiOld = iHigh(_Symbol, PERIOD_M5, k + 2);
         double loNew = iLow(_Symbol, PERIOD_M5, k);
         if(loNew > hiOld) { upper = loNew; lower = hiOld; return true; }
        }
      else
        {
         double loOld = iLow(_Symbol, PERIOD_M5, k + 2);
         double hiNew = iHigh(_Symbol, PERIOD_M5, k);
         if(hiNew < loOld) { upper = loOld; lower = hiNew; return true; }
        }
     }
   return false;
  }

void CheckChoch()
  {
   int bars = iBarShift(_Symbol, PERIOD_M5, g_sweepBarTime);
   double h1 = iHigh(_Symbol, PERIOD_M5, 1), l1 = iLow(_Symbol, PERIOD_M5, 1), c1 = iClose(_Symbol, PERIOD_M5, 1);

   // invalidation: ทำ extreme ใหม่เกินปลายไส้
   if((g_dir < 0 && h1 > g_extreme) || (g_dir > 0 && l1 < g_extreme))
     { ResetSetup("New extreme beyond sweep wick"); return; }
   if(bars > InpChochMaxBars)
     { ResetSetup("No CHoCH within " + IntegerToString(InpChochMaxBars) + " M5 bars"); return; }

   bool broke = (g_dir < 0) ? (c1 < g_internalSwing) : (c1 > g_internalSwing);
   if(!broke) return;
   double up, lo;
   if(!FindFVG(g_dir, up, lo)) return;
   g_fvgUpper = up; g_fvgLower = lo;
   g_state = ST_CHOCH;
   g_lastMsg = StringFormat("CHoCH confirmed, FVG %.2f - %.2f", lo, up);
   Print(g_lastMsg);
  }

//+------------------------------------------------------------------+
//| STATE 4: risk calc + place limit order                           |
//+------------------------------------------------------------------+
double CalcLot(const double slDist)
  {
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickVal <= 0) tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSize <= 0 || slDist <= 0) return 0;
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double lossPerLot = slDist / tickSize * tickVal;
   double lot = riskMoney / lossPerLot;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathFloor(lot / step) * step;
   if(lot < minL) return 0;               // ความเสี่ยงไม่พอสำหรับ lot ขั้นต่ำ -> ข้าม
   return NormalizeDouble(MathMin(lot, maxL), 2);
  }

void PlaceOrder()
  {
   g_state = ST_RISK;
   double atr5 = ATR(hATR_M5, 1);
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   double entry, sl, tp;
   if(g_dir > 0)
     {
      entry = g_fvgUpper - (g_fvgUpper - g_fvgLower) * InpFVGEntryLevel;
      sl    = g_extreme - InpSLBufferATR * atr5;
     }
   else
     {
      entry = g_fvgLower + (g_fvgUpper - g_fvgLower) * InpFVGEntryLevel;
      sl    = g_extreme + InpSLBufferATR * atr5 + spread;
     }
   entry = NormalizeDouble(entry, digits);
   sl    = NormalizeDouble(sl, digits);
   double dist = MathAbs(entry - sl);
   double distPts = dist / _Point;
   if(distPts < InpMinSLPoints || distPts > InpMaxSLPoints)
     { ResetSetup(StringFormat("SL distance %.0f pts out of range", distPts)); return; }

   tp = NormalizeDouble(g_dir > 0 ? entry + InpTP_R * dist : entry - InpTP_R * dist, digits);
   double lot = CalcLot(dist);
   if(lot <= 0) { ResetSetup("Lot below minimum for risk"); return; }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool ok;
   string cmt = "XSC " + g_sweepName;
   if(g_dir > 0)
     {
      if(entry >= ask - stopsLvl) { ResetSetup("Price already inside entry (buy)"); return; }
      ok = trade.BuyLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
     }
   else
     {
      if(entry <= bid + stopsLvl) { ResetSetup("Price already inside entry (sell)"); return; }
      ok = trade.SellLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
     }
   if(!ok || trade.ResultOrder() == 0)
     { ResetSetup("Order send failed: " + IntegerToString(trade.ResultRetcode())); return; }

   g_orderTicket = trade.ResultOrder();
   g_orderBarTime = iTime(_Symbol, PERIOD_M5, 0);
   g_entry = entry; g_sl = sl; g_tp = tp; g_riskDist = dist; g_lot = lot;
   g_state = ST_ORDER;
   g_lastMsg = StringFormat("%s LIMIT %.2f lot @%.2f SL %.2f TP %.2f (%.0f pts)",
                            g_dir > 0 ? "BUY" : "SELL", lot, entry, sl, tp, distPts);
   Print(g_lastMsg);
  }

//+------------------------------------------------------------------+
//| STATE 5: pending order                                           |
//+------------------------------------------------------------------+
bool FindOurPosition(ulong &ticket)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
        { ticket = t; return true; }
     }
   return false;
  }

void ManageOrder()
  {
   ulong pt;
   if(FindOurPosition(pt))
     {
      g_posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      g_entry = PositionGetDouble(POSITION_PRICE_OPEN);
      g_partialDone = false;
      g_state = ST_TRADE;
      g_lastMsg = "Order filled -> managing trade";
      Print(g_lastMsg);
      return;
     }
   if(!OrderSelect(g_orderTicket))
     { ResetSetup("Pending order disappeared"); return; }

   int bars = iBarShift(_Symbol, PERIOD_M5, g_orderBarTime);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool ranAway = (g_dir > 0) ? (bid >= g_entry + InpCancelAtR * g_riskDist)
                              : (ask <= g_entry - InpCancelAtR * g_riskDist);
   if(bars >= InpOrderExpiryBars || ranAway)
     {
      if(trade.OrderDelete(g_orderTicket))
         ResetSetup(ranAway ? "Price reached cancel R before fill" : "Limit order expired");
     }
  }

//+------------------------------------------------------------------+
//| STATE 6: trade management                                        |
//+------------------------------------------------------------------+
void FinalizeTrade()
  {
   double pnl = 0;
   if(HistorySelectByPosition(g_posId))
     {
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong d = HistoryDealGetTicket(i);
         pnl += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
        }
     }
   if(!g_partialDone && pnl < 0)
     {
      g_consecLosses++;
      g_dailyLossCount++;
     }
   else if(pnl > 0)
      g_consecLosses = 0;
   PrintFormat("Trade closed. PnL=%.2f consecLosses=%d dailyLosses=%d", pnl, g_consecLosses, g_dailyLossCount);
   ResetSetup("Trade closed");
  }

void ManageTrade()
  {
   ulong pt;
   if(!FindOurPosition(pt)) { FinalizeTrade(); return; }

   long   type  = PositionGetInteger(POSITION_TYPE);
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);
   double vol   = PositionGetDouble(POSITION_VOLUME);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(g_riskDist <= 0) g_riskDist = MathAbs(open - sl);
   if(g_riskDist <= 0) return;

   double profitR = (type == POSITION_TYPE_BUY) ? (bid - open) / g_riskDist : (open - ask) / g_riskDist;

   // Partial close + Break-even
   if(!g_partialDone && profitR >= InpPartialR)
     {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double closeVol = MathFloor(vol * InpPartialRatio / step) * step;
      if(closeVol >= minL && vol - closeVol >= minL)
         trade.PositionClosePartial(pt, closeVol);
      double be = (type == POSITION_TYPE_BUY) ? open + InpBEBufferPoints * _Point : open - InpBEBufferPoints * _Point;
      be = NormalizeDouble(be, digits);
      if(PositionSelectByTicket(pt))
         trade.PositionModify(pt, be, tp);
      g_partialDone = true;
      g_lastMsg = StringFormat("Partial close @%.2fR, SL -> BE %.2f", profitR, be);
      Print(g_lastMsg);
      return;
     }

   // Structural trailing stop on M15 swings
   if(InpUseSwingTrail && g_partialDone)
     {
      int s;
      double atr5 = ATR(hATR_M5, 1);
      double stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      if(type == POSITION_TYPE_BUY)
        {
         double sw = LastSwing(PERIOD_M15, false, INVALID_HANDLE, 0, 50, s);
         double nsl = NormalizeDouble(sw - InpSLBufferATR * atr5, digits);
         if(sw > 0 && nsl > sl + _Point && nsl < bid - stopsLvl)
            trade.PositionModify(pt, nsl, tp);
        }
      else
        {
         double sw = LastSwing(PERIOD_M15, true, INVALID_HANDLE, 0, 50, s);
         double spread = ask - bid;
         double nsl = NormalizeDouble(sw + InpSLBufferATR * atr5 + spread, digits);
         if(sw > 0 && (sl == 0 || nsl < sl - _Point) && nsl > ask + stopsLvl)
            trade.PositionModify(pt, nsl, tp);
        }
     }
  }

//+------------------------------------------------------------------+
//| Recover state after restart                                      |
//+------------------------------------------------------------------+
void RecoverState()
  {
   ulong pt;
   if(FindOurPosition(pt))
     {
      g_posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      double open = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL);
      long type = PositionGetInteger(POSITION_TYPE);
      g_dir = (type == POSITION_TYPE_BUY) ? 1 : -1;
      g_entry = open;
      g_riskDist = MathAbs(open - sl);
      g_partialDone = (sl > 0) && ((type == POSITION_TYPE_BUY && sl >= open) || (type == POSITION_TYPE_SELL && sl <= open));
      if(g_partialDone) g_riskDist = 0; // ไม่ทราบ R เดิมแล้ว ใช้เฉพาะ trailing
      g_state = ST_TRADE;
      Print("Recovered open position #", pt);
      return;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic)
        {
         g_orderTicket = t;
         g_entry = OrderGetDouble(ORDER_PRICE_OPEN);
         g_sl = OrderGetDouble(ORDER_SL);
         g_riskDist = MathAbs(g_entry - g_sl);
         long ot = OrderGetInteger(ORDER_TYPE);
         g_dir = (ot == ORDER_TYPE_BUY_LIMIT) ? 1 : -1;
         g_orderBarTime = iTime(_Symbol, PERIOD_M5, 0);
         g_state = ST_ORDER;
         Print("Recovered pending order #", t);
         return;
        }
     }
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
string StateName(const ENUM_EA_STATE s)
  {
   switch(s)
     {
      case ST_IDLE:  return "1 IDLE & FILTER";
      case ST_SWEEP: return "2 LIQUIDITY SWEEP";
      case ST_CHOCH: return "3 CHoCH CONFIRM";
      case ST_RISK:  return "4 RISK & LIMIT";
      case ST_ORDER: return "5 ORDER ACTIVE";
      case ST_TRADE: return "6 TRADE MGMT";
     }
   return "?";
  }

void UpdatePanel(const string filterMsg)
  {
   if(!InpShowPanel) return;
   datetime thai = ToThai(TimeCurrent());
   string s = "XAU Sweep+CHoCH EA\n";
   s += "Thai time: " + TimeToString(thai, TIME_DATE | TIME_MINUTES) + "\n";
   s += "State: " + StateName(g_state) + "\n";
   s += "Filter: " + filterMsg + "\n";
   s += StringFormat("Spread: %.0f / %d pts\n", SpreadPoints(), InpMaxSpreadPoints);
   s += StringFormat("Asian H/L: %.2f / %.2f %s\n", g_asianHigh, g_asianLow, g_asianReady ? "" : "(pending)");
   s += StringFormat("PDH/PDL: %.2f / %.2f\n", g_pdh, g_pdl);
   s += StringFormat("Consec losses: %d/%d  Daily losses: %d  Locked: %s\n",
                     g_consecLosses, InpMaxConsecLosses, g_dailyLossCount, g_dayLocked ? "YES" : "no");
   s += "Last: " + g_lastMsg;
   Comment(s);
  }

//+------------------------------------------------------------------+
//| Expert events                                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("Warning: EA นี้ออกแบบสำหรับ XAUUSD แต่กำลังรันบน ", _Symbol);

   mAsianS = ParseHHMM(InpAsianStart); mAsianE = ParseHHMM(InpAsianEnd);
   mLonS   = ParseHHMM(InpLondonStart); mLonE  = ParseHHMM(InpLondonEnd);
   mNYS    = ParseHHMM(InpNYStart);     mNYE   = ParseHHMM(InpNYEnd);

   hATR_M5  = iATR(_Symbol, PERIOD_M5, InpATRPeriod);
   hATR_M15 = iATR(_Symbol, PERIOD_M15, InpATRPeriod);
   hATR_H1  = iATR(_Symbol, PERIOD_H1, InpATRPeriod);
   if(hATR_M5 == INVALID_HANDLE || hATR_M15 == INVALID_HANDLE || hATR_H1 == INVALID_HANDLE)
     { Print("ATR handle error"); return INIT_FAILED; }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   RecoverState();
   PrintFormat("Init OK. Server GMT offset = %.1f h", ServerOffsetSec() / 3600.0);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(hATR_M5);
   IndicatorRelease(hATR_M15);
   IndicatorRelease(hATR_H1);
   ObjectsDeleteAll(0, "XSC_");
   Comment("");
  }

void OnTick()
  {
   DailyUpdate();

   // งานที่ต้องทำทุก tick: บริหาร order / position
   if(g_state == ST_ORDER) ManageOrder();
   if(g_state == ST_TRADE) ManageTrade();

   string why = "";
   bool filtersOk = FiltersOK(why);

   // งานที่ทำเมื่อปิดแท่ง M5 ใหม่
   datetime m5 = iTime(_Symbol, PERIOD_M5, 0);
   if(m5 != g_lastM5Bar)
     {
      g_lastM5Bar = m5;
      if(g_state == ST_IDLE && filtersOk)
         DetectSweep();
      else if(g_state == ST_SWEEP)
        {
         CheckChoch();
         if(g_state == ST_CHOCH)
           {
            if(filtersOk) PlaceOrder();
            else ResetSetup("CHoCH but filter blocked: " + why);
           }
        }
     }
   UpdatePanel(why);
  }
//+------------------------------------------------------------------+
