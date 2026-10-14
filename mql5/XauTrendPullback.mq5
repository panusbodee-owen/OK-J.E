//+------------------------------------------------------------------+
//|                                            XauTrendPullback.mq5 |
//|                                                                  |
//|  XAUUSD Trend-Pullback EA                                        |
//|   - H4 market structure + EMA + ADX + ATR ratio  -> regime/side  |
//|   - H1 impulse leg, pullback into Fib 38.2-61.8 -> zone          |
//|   - M15 close breaks the pullback's internal swing -> entry      |
//|   - ATR-based SL, TP1 at 1R (50%) + break-even, trailed runner   |
//|   - session / news / spread filters, daily/weekly/max-DD locks   |
//|                                                                  |
//|  Single-file EA: copy to MQL5\Experts\ and compile (F7).         |
//|  Attach to any XAUUSD chart (M15 recommended). Timeframes used   |
//|  are fixed (H4/H1/M15) regardless of the chart timeframe.        |
//|  Backtest news filter: attach once to a live/demo chart with     |
//|  InpExportNewsCsv=true to write Common\Files\xau_news_usd.csv.   |
//|  Educational code - backtest and demo-test before live use.      |
//+------------------------------------------------------------------+
#property copyright   "OK-J.E"
#property version     "1.00"
#property description "XAUUSD trend-pullback EA: H4 regime -> H1 Fib pullback -> M15 CHoCH trigger."
#property description "ATR-based risk, partial TP + break-even + trailing, session/news/spread filters."

#include <Trade\Trade.mqh>

enum ENUM_XTP_TRAIL
{
   XTP_TRAIL_SWING      = 0,   // Swing M15
   XTP_TRAIL_CHANDELIER = 1    // Chandelier (ATR M15)
};

input group "=== Risk ==="
input double InpRiskPercent       = 0.5;    // Risk per trade (% of equity)
input int    InpMaxTradesPerDay   = 2;      // Max new trades per day
input double InpMaxDailyLossPct   = 2.0;    // Daily loss lock (%)
input double InpMaxWeeklyLossPct  = 4.0;    // Weekly loss lock (%)
input double InpMaxDrawdownPct    = 10.0;   // Max drawdown from peak -> EA disabled (%)
input bool   InpResetDDLock       = false;  // Reset drawdown lock at start
input int    InpLossStreakReduce  = 3;      // Losses in a row -> half risk
input int    InpWinsToRestore     = 2;      // Wins in a row -> full risk again

input group "=== Market structure ==="
input int    InpStructureBars     = 300;    // Closed bars analysed per timeframe
input int    InpFractalH4         = 3;      // H4 fractal depth (bars each side)
input int    InpFractalH1         = 3;      // H1 fractal depth
input int    InpFractalM15        = 2;      // M15 fractal depth
input double InpMinLegATR_H4      = 1.5;    // H4 min swing leg (x ATR)
input double InpMinLegATR_H1      = 1.0;    // H1 min swing leg (x ATR)
input double InpMinLegATR_M15     = 0.5;    // M15 min swing leg (x ATR)

input group "=== Regime ==="
input int    InpEmaFast           = 50;     // H4 EMA fast
input int    InpEmaSlow           = 200;    // H4 EMA slow
input int    InpAdxPeriod         = 14;     // H1 ADX period
input double InpAdxMin            = 22.0;   // Min H1 ADX for a trend
input int    InpAtrPeriod         = 14;     // ATR period (all timeframes)
input int    InpAtrAvgBars        = 100;    // H1 bars for the ATR average
input double InpVRMax             = 1.8;    // ATR ratio above -> HIGH_VOL
input double InpVRMin             = 0.6;    // ATR ratio below -> DEAD
input bool   InpTradeHighVol      = false;  // HIGH_VOL: trade at half risk (false = skip)

input group "=== Entry ==="
input double InpFibMin            = 0.382;  // Pullback zone: shallow edge
input double InpFibMax            = 0.618;  // Pullback zone: deep edge (H1 close beyond = invalid)
input double InpMinRRRoom         = 2.0;    // Min room to the H1 impulse extreme (R)
input int    InpMaxPullbackBarsH1 = 48;     // Max H1 bars since impulse extreme (0 = off)
input bool   InpRequireSweep      = false;  // Require an M15 liquidity sweep in the pullback

input group "=== Stop loss / exits ==="
input double InpSLBufferATR       = 0.2;    // SL buffer beyond pullback (x ATR M15)
input double InpMinSL_ATR_M15     = 1.0;    // Min SL distance (x ATR M15)
input double InpMaxSL_ATR_H1      = 2.5;    // Max SL distance (x ATR H1), wider = skip
input double InpTP1_R             = 1.0;    // TP1 distance (R)
input double InpTP1ClosePct       = 50.0;   // % of volume closed at TP1
input double InpBEOffset          = 0.10;   // Break-even offset (price, covers commission)
input double InpTP2_R             = 3.0;    // Final TP (R)
input bool   InpCapTP2AtSwing     = true;   // Cap final TP at the H1 impulse extreme
input ENUM_XTP_TRAIL InpTrailMode = XTP_TRAIL_SWING; // Runner trailing mode
input double InpChandelierATR     = 2.5;    // Chandelier distance (x ATR M15)
input bool   InpStructureExit     = true;   // Close on H1 CHoCH against the position
input int    InpTimeStopBars      = 12;     // Time stop after N M15 bars (0 = off)
input double InpTimeStopMinR      = 0.5;    // ...if best excursion is below this (R)

input group "=== Sessions (broker SERVER time) ==="
input string InpLondonStart       = "10:30"; // London window start
input string InpLondonEnd         = "13:00"; // London window end
input string InpNYStart           = "15:45"; // New York window start (after 15:30 data)
input string InpNYEnd             = "19:00"; // New York window end
input string InpFridayNoNewAfter  = "19:00"; // Friday: no new trades after
input string InpFridayCloseTime   = "22:00"; // Friday: close everything at
input bool   InpCloseBeforeRollover = true;  // Close positions in the rollover window
input string InpRolloverStart     = "23:30"; // Rollover window start
input string InpRolloverEnd       = "01:30"; // Rollover window end

input group "=== News filter ==="
input bool   InpUseNews           = true;    // Use high-impact news filter
input string InpNewsCurrency      = "USD";   // Currency ("ALL" = every currency)
input string InpNewsCsvFile       = "xau_news_usd.csv"; // CSV in Terminal\Common\Files (server time)
input int    InpNewsBeforeMin     = 30;      // No entries N min before news
input int    InpNewsAfterMin      = 15;      // No entries N min after news
input int    InpNewsExitBeforeMin = 15;      // N min before news: BE if >= 0.5R, else close
input bool   InpExportNewsCsv     = false;   // LIVE chart: export MT5 calendar to the CSV on start
input datetime InpExportFrom      = D'2020.01.01'; // Export range start (server time)

input group "=== Execution ==="
input double InpMaxSpreadPrice    = 0.35;    // Max spread in price (0.35 = 35 cents)
input double InpMaxSpreadPctSL    = 10.0;    // Max spread as % of SL distance
input ulong  InpMagic             = 20261014; // Magic number
input int    InpSlippagePoints    = 30;      // Max slippage (points)
input bool   InpDebugLog          = true;    // Print decisions to the Experts log

//+==================================================================+
//| SECTION: COMMON                                                  |
//+==================================================================+
//+------------------------------------------------------------------+
//| Common - shared types and small helpers                          |
//+------------------------------------------------------------------+

#define STRUCT_BEAR    -1
#define STRUCT_NEUTRAL  0
#define STRUCT_BULL     1

enum ENUM_XTP_REGIME
{
   XTP_REGIME_NONE = 0,
   XTP_REGIME_TREND_UP,
   XTP_REGIME_TREND_DOWN,
   XTP_REGIME_RANGE,
   XTP_REGIME_HIGH_VOL,
   XTP_REGIME_DEAD
};

//--- result of a market-structure pass on one timeframe (closed bars only)
struct StructureInfo
{
   bool     valid;
   int      state;            // STRUCT_BULL / STRUCT_NEUTRAL / STRUCT_BEAR

   bool     hasHigh;          // latest confirmed swing high
   double   lastHigh;
   datetime lastHighTime;
   bool     hasLow;           // latest confirmed swing low
   double   lastLow;
   datetime lastLowTime;

   double   protectedLow;     // BULL: close below => CHoCH (0 = none)
   double   protectedHigh;    // BEAR: close above => CHoCH (0 = none)

   bool     hasLeg;           // impulse leg of the current trend
   int      legDir;           // +1 bull leg, -1 bear leg
   double   legStart;         // bull: HL the impulse started from / bear: LH
   datetime legStartTime;
   double   legEnd;           // bull: impulse high / bear: impulse low
   datetime legEndTime;       // open time of the bar holding legEnd
   bool     hasPullback;      // at least one closed bar after legEnd
   double   pbExtreme;        // bull: lowest low after legEnd / bear: highest high
   double   pbExtremeClose;   // bull: lowest close after legEnd / bear: highest close

   bool     bullBreakNow;     // last closed bar closed above the latest swing high
   double   brokenHigh;
   datetime brokenHighTime;
   bool     bearBreakNow;     // last closed bar closed below the latest swing low
   double   brokenLow;
   datetime brokenLowTime;

   datetime lastSweepLowTime;  // bar that wicked below a live swing low and closed back above
   datetime lastSweepHighTime; // bar that wicked above a live swing high and closed back below
};

struct RegimeInfo
{
   ENUM_XTP_REGIME regime;
   int    dir;        // +1 buy only, -1 sell only, 0 no new trades
   double riskMult;   // multiplier applied to InpRiskPercent
   double adx;
   double vr;         // ATR(H1) / average ATR(H1)
};

//+------------------------------------------------------------------+
void XtpLog(const string msg)
{
   if(InpDebugLog)
      Print("[XTP] ", msg);
}

string XtpRegimeName(const ENUM_XTP_REGIME r)
{
   switch(r)
   {
      case XTP_REGIME_TREND_UP:   return "TREND_UP";
      case XTP_REGIME_TREND_DOWN: return "TREND_DOWN";
      case XTP_REGIME_RANGE:      return "RANGE";
      case XTP_REGIME_HIGH_VOL:   return "HIGH_VOL";
      case XTP_REGIME_DEAD:       return "DEAD";
   }
   return "NONE";
}

string XtpStateName(const int s)
{
   if(s == STRUCT_BULL) return "BULL";
   if(s == STRUCT_BEAR) return "BEAR";
   return "NEUTRAL";
}

//--- prices / volumes -----------------------------------------------
double XtpTickSize()
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return (ts > 0) ? ts : _Point;
}

double XtpNormPrice(const double price)
{
   double ts = XtpTickSize();
   return NormalizeDouble(MathRound(price / ts) * ts, _Digits);
}

double XtpNormVolumeDown(const double volume)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0)
      step = 0.01;
   double v = MathFloor(volume / step + 1e-9) * step;
   int digits = (int)MathMax(0.0, MathCeil(-MathLog10(step) - 1e-9));
   return NormalizeDouble(v, digits);
}

double XtpSpread()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
}

double XtpMinStopDistance()
{
   double lvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   return MathMax(lvl, XtpTickSize());
}

bool XtpReadBuffer(const int handle, const int buffer, const int shift, double &value)
{
   double b[];
   if(CopyBuffer(handle, buffer, shift, 1, b) != 1)
      return false;
   value = b[0];
   return (value != EMPTY_VALUE);
}

//--- time (broker server time) -------------------------------------
int XtpMinuteOfDay(const datetime t)
{
   MqlDateTime d;
   TimeToStruct(t, d);
   return d.hour * 60 + d.min;
}

int XtpDayOfWeek(const datetime t)
{
   MqlDateTime d;
   TimeToStruct(t, d);
   return d.day_of_week;   // 0 = Sunday
}

datetime XtpDayStart(const datetime t)
{
   long s = (long)t;
   return (datetime)(s - s % 86400);
}

//--- global-variable keys (persist state across terminal restarts) -
string XtpGvPrefix()
{
   return "XTP_" + IntegerToString((long)InpMagic) + "_";
}

string XtpGvKey(const string key)
{
   return XtpGvPrefix() + _Symbol + "_" + key;
}

string XtpPosKey(const long positionId, const string key)
{
   return XtpGvPrefix() + IntegerToString(positionId) + "_" + key;
}

double XtpGvGet(const string name, const double def)
{
   return GlobalVariableCheck(name) ? GlobalVariableGet(name) : def;
}
//+------------------------------------------------------------------+

//--- shared state (used by the modules below)
CTrade        g_trade;
int           g_hAtrH4      = INVALID_HANDLE;
int           g_hAtrH1      = INVALID_HANDLE;
int           g_hAtrM15     = INVALID_HANDLE;
int           g_hEmaFastH4  = INVALID_HANDLE;
int           g_hEmaSlowH4  = INVALID_HANDLE;
int           g_hAdxH1      = INVALID_HANDLE;
StructureInfo g_h4;
StructureInfo g_h1;
StructureInfo g_m15;
RegimeInfo    g_regime;
datetime      g_lastBar = 0;

//+==================================================================+
//| SECTION: STRUCTURE                                               |
//+==================================================================+
//+------------------------------------------------------------------+
//| Structure - swing / BOS / CHoCH / impulse-leg detection          |
//|                                                                  |
//| Replays the last N CLOSED bars of one timeframe, bar by bar:     |
//|  1. a fractal at bar j is only used once bar j+depth has closed  |
//|     (no repaint, no look-ahead)                                  |
//|  2. swings form an alternating zigzag; opposite legs smaller     |
//|     than minLegAtr x ATR are ignored as noise                    |
//|  3. breaks are confirmed by CLOSE; a wick-only break is a sweep  |
//|  4. BULL -> NEUTRAL -> BEAR state machine driven by protected    |
//|     levels, so one CHoCH never flips the trend straight away     |
//+------------------------------------------------------------------+

class CStructureEngine
{
private:
   MqlRates m_r[];
   double   m_atr[];
   int      m_n;
   int      m_depth;
   double   m_minLegAtr;

   //--- zigzag of confirmed swings
   int      m_lastType;          // +1 high, -1 low, 0 none yet
   double   m_lastPrice;
   bool     m_hasH;
   bool     m_hasL;
   double   m_hPrice;
   double   m_lPrice;
   int      m_hIdx;
   int      m_lIdx;
   bool     m_hBroken;
   bool     m_lBroken;
   bool     m_hasLowBeforeHigh;  // swing low that preceded the latest high (HL test)
   double   m_lowBeforeHigh;
   bool     m_hasHighBeforeLow;  // swing high that preceded the latest low (LH test)
   double   m_highBeforeLow;

   //--- trend state
   int      m_state;
   double   m_protLow;
   double   m_protHigh;

   //--- impulse leg + pullback
   bool     m_hasLeg;
   int      m_legDir;
   double   m_legStart;
   double   m_legEnd;
   int      m_legStartIdx;
   int      m_legEndIdx;
   bool     m_hasPb;
   double   m_pbExt;
   double   m_pbExtClose;

   void     Reset();
   bool     IsFractalHigh(const int j) const;
   bool     IsFractalLow(const int j) const;
   int      LowestIdx(const int from, const int to) const;
   int      HighestIdx(const int from, const int to) const;
   void     OnSwing(const int idx, const int type);
   void     StepLeg(const int k);
   void     StartLeg(const int dir, const int startIdx, const int i);

public:
   bool     Analyze(const string sym, const ENUM_TIMEFRAMES tf, const int depth,
                    const double minLegAtr, const int atrHandle, const int bars,
                    StructureInfo &s);
};

//+------------------------------------------------------------------+
void CStructureEngine::Reset()
{
   m_lastType = 0;
   m_lastPrice = 0;
   m_hasH = false;
   m_hasL = false;
   m_hPrice = 0;
   m_lPrice = 0;
   m_hIdx = -1;
   m_lIdx = -1;
   m_hBroken = true;
   m_lBroken = true;
   m_hasLowBeforeHigh = false;
   m_lowBeforeHigh = 0;
   m_hasHighBeforeLow = false;
   m_highBeforeLow = 0;

   m_state = STRUCT_NEUTRAL;
   m_protLow = 0;
   m_protHigh = 0;

   m_hasLeg = false;
   m_legDir = 0;
   m_legStart = 0;
   m_legEnd = 0;
   m_legStartIdx = -1;
   m_legEndIdx = -1;
   m_hasPb = false;
   m_pbExt = 0;
   m_pbExtClose = 0;
}

bool CStructureEngine::IsFractalHigh(const int j) const
{
   for(int k = 1; k <= m_depth; k++)
      if(!(m_r[j].high > m_r[j - k].high && m_r[j].high >= m_r[j + k].high))
         return false;
   return true;
}

bool CStructureEngine::IsFractalLow(const int j) const
{
   for(int k = 1; k <= m_depth; k++)
      if(!(m_r[j].low < m_r[j - k].low && m_r[j].low <= m_r[j + k].low))
         return false;
   return true;
}

int CStructureEngine::LowestIdx(const int from, const int to) const
{
   int best = from;
   for(int k = from + 1; k <= to; k++)
      if(m_r[k].low < m_r[best].low)
         best = k;
   return best;
}

int CStructureEngine::HighestIdx(const int from, const int to) const
{
   int best = from;
   for(int k = from + 1; k <= to; k++)
      if(m_r[k].high > m_r[best].high)
         best = k;
   return best;
}

//--- register a confirmed fractal in the alternating zigzag
void CStructureEngine::OnSwing(const int idx, const int type)
{
   double price = (type > 0) ? m_r[idx].high : m_r[idx].low;

   if(m_lastType == type)
   {
      // same side again: keep only the more extreme point
      if((type > 0 && price <= m_lastPrice) || (type < 0 && price >= m_lastPrice))
         return;
   }
   else if(m_lastType != 0)
   {
      // opposite side: legs smaller than the ATR threshold are noise
      if(MathAbs(price - m_lastPrice) < m_minLegAtr * m_atr[idx])
         return;
      if(type > 0)
      {
         m_hasLowBeforeHigh = m_hasL;
         m_lowBeforeHigh    = m_lPrice;
      }
      else
      {
         m_hasHighBeforeLow = m_hasH;
         m_highBeforeLow    = m_hPrice;
      }
   }

   m_lastType  = type;
   m_lastPrice = price;
   if(type > 0)
   {
      m_hasH = true;
      m_hPrice = price;
      m_hIdx = idx;
      m_hBroken = false;
   }
   else
   {
      m_hasL = true;
      m_lPrice = price;
      m_lIdx = idx;
      m_lBroken = false;
   }
}

//--- extend the impulse with bar k, or track the pullback after it
void CStructureEngine::StepLeg(const int k)
{
   if(m_legDir > 0)
   {
      if(m_r[k].high > m_legEnd)
      {
         m_legEnd = m_r[k].high;
         m_legEndIdx = k;
         m_hasPb = false;
      }
      else if(!m_hasPb)
      {
         m_hasPb = true;
         m_pbExt = m_r[k].low;
         m_pbExtClose = m_r[k].close;
      }
      else
      {
         m_pbExt = MathMin(m_pbExt, m_r[k].low);
         m_pbExtClose = MathMin(m_pbExtClose, m_r[k].close);
      }
   }
   else
   {
      if(m_r[k].low < m_legEnd)
      {
         m_legEnd = m_r[k].low;
         m_legEndIdx = k;
         m_hasPb = false;
      }
      else if(!m_hasPb)
      {
         m_hasPb = true;
         m_pbExt = m_r[k].high;
         m_pbExtClose = m_r[k].close;
      }
      else
      {
         m_pbExt = MathMax(m_pbExt, m_r[k].high);
         m_pbExtClose = MathMax(m_pbExtClose, m_r[k].close);
      }
   }
}

void CStructureEngine::StartLeg(const int dir, const int startIdx, const int i)
{
   m_hasLeg = true;
   m_legDir = dir;
   m_legStartIdx = startIdx;
   m_legStart = (dir > 0) ? m_r[startIdx].low : m_r[startIdx].high;
   m_legEnd = m_legStart;
   m_legEndIdx = startIdx;
   m_hasPb = false;
   for(int k = startIdx; k <= i; k++)
      StepLeg(k);
}

//+------------------------------------------------------------------+
bool CStructureEngine::Analyze(const string sym, const ENUM_TIMEFRAMES tf, const int depth,
                               const double minLegAtr, const int atrHandle, const int bars,
                               StructureInfo &s)
{
   ZeroMemory(s);
   s.valid = false;
   m_depth = MathMax(1, depth);
   m_minLegAtr = minLegAtr;

   ArraySetAsSeries(m_r, false);
   ArraySetAsSeries(m_atr, false);
   m_n = CopyRates(sym, tf, 1, bars, m_r);          // closed bars, oldest first
   if(m_n < m_depth * 2 + 10)
      return false;
   if(CopyBuffer(atrHandle, 0, 1, m_n, m_atr) != m_n)
      return false;

   Reset();

   for(int i = 2 * m_depth; i < m_n; i++)
   {
      //--- 1) fractal at bar j is confirmed now that bar i = j + depth has closed
      int  j  = i - m_depth;
      bool fh = IsFractalHigh(j);
      bool fl = IsFractalLow(j);
      if(fh && fl && m_lastType > 0)
      {
         OnSwing(j, -1);
         OnSwing(j, 1);
      }
      else
      {
         if(fh) OnSwing(j, 1);
         if(fl) OnSwing(j, -1);
      }

      const double c = m_r[i].close;
      const bool   isLast = (i == m_n - 1);
      bool legStarted = false;

      //--- 2) liquidity sweeps: wick through a live swing, close back inside
      if(m_hasL && !m_lBroken && m_r[i].low < m_lPrice && c >= m_lPrice)
         s.lastSweepLowTime = m_r[i].time;
      if(m_hasH && !m_hBroken && m_r[i].high > m_hPrice && c <= m_hPrice)
         s.lastSweepHighTime = m_r[i].time;

      //--- 3) bullish break (close) of the latest swing high
      if(m_hasH && !m_hBroken && c > m_hPrice)
      {
         m_hBroken = true;
         if(isLast)
         {
            s.bullBreakNow   = true;
            s.brokenHigh     = m_hPrice;
            s.brokenHighTime = m_r[m_hIdx].time;
         }
         int    li     = LowestIdx(m_hIdx, i);
         double legLow = m_r[li].low;
         bool   deepPullback = (m_hPrice - legLow) >= m_minLegAtr * m_atr[i];

         if(m_state == STRUCT_BULL)
         {
            // BOS: a real pullback starts a new impulse; a shallow pause just extends it
            if(deepPullback || !m_hasLeg)
            {
               m_protLow = legLow;
               StartLeg(1, li, i);
               legStarted = true;
            }
         }
         else if(m_state == STRUCT_NEUTRAL)
         {
            // NEUTRAL -> BULL only if this impulse started from a higher low
            if(!m_hasLowBeforeHigh || legLow > m_lowBeforeHigh)
            {
               m_state = STRUCT_BULL;
               m_protHigh = 0;
               m_protLow = legLow;
               StartLeg(1, li, i);
               legStarted = true;
            }
         }
         // in BEAR an internal high was broken: only protectedHigh can end the trend
      }

      //--- 4) bearish break (close) of the latest swing low
      if(m_hasL && !m_lBroken && c < m_lPrice)
      {
         m_lBroken = true;
         if(isLast)
         {
            s.bearBreakNow  = true;
            s.brokenLow     = m_lPrice;
            s.brokenLowTime = m_r[m_lIdx].time;
         }
         int    hi      = HighestIdx(m_lIdx, i);
         double legHigh = m_r[hi].high;
         bool   deepPullback = (legHigh - m_lPrice) >= m_minLegAtr * m_atr[i];

         if(m_state == STRUCT_BEAR)
         {
            if(deepPullback || !m_hasLeg)
            {
               m_protHigh = legHigh;
               StartLeg(-1, hi, i);
               legStarted = true;
            }
         }
         else if(m_state == STRUCT_NEUTRAL)
         {
            // NEUTRAL -> BEAR only if this impulse started from a lower high
            if(!m_hasHighBeforeLow || legHigh < m_highBeforeLow)
            {
               m_state = STRUCT_BEAR;
               m_protLow = 0;
               m_protHigh = legHigh;
               StartLeg(-1, hi, i);
               legStarted = true;
            }
         }
      }

      //--- 5) CHoCH: close beyond the protected level ends the trend
      if(m_state == STRUCT_BULL && m_protLow > 0 && c < m_protLow)
      {
         m_state = STRUCT_NEUTRAL;
         m_protLow = 0;
         m_hasLeg = false;
      }
      else if(m_state == STRUCT_BEAR && m_protHigh > 0 && c > m_protHigh)
      {
         m_state = STRUCT_NEUTRAL;
         m_protHigh = 0;
         m_hasLeg = false;
      }

      //--- 6) extend the impulse / track the pullback
      if(m_hasLeg && !legStarted)
         StepLeg(i);
   }

   s.valid         = true;
   s.state         = m_state;
   s.hasHigh       = m_hasH;
   s.lastHigh      = m_hPrice;
   s.lastHighTime  = m_hasH ? m_r[m_hIdx].time : 0;
   s.hasLow        = m_hasL;
   s.lastLow       = m_lPrice;
   s.lastLowTime   = m_hasL ? m_r[m_lIdx].time : 0;
   s.protectedLow  = m_protLow;
   s.protectedHigh = m_protHigh;
   s.hasLeg        = m_hasLeg;
   if(m_hasLeg)
   {
      s.legDir         = m_legDir;
      s.legStart       = m_legStart;
      s.legStartTime   = m_r[m_legStartIdx].time;
      s.legEnd         = m_legEnd;
      s.legEndTime     = m_r[m_legEndIdx].time;
      s.hasPullback    = m_hasPb;
      s.pbExtreme      = m_pbExt;
      s.pbExtremeClose = m_pbExtClose;
   }
   return true;
}

CStructureEngine g_engine;
//+------------------------------------------------------------------+
//+==================================================================+
//| SECTION: REGIME                                                  |
//+==================================================================+
//+------------------------------------------------------------------+
//| Regime - decide which side (if any) the EA may trade             |
//|                                                                  |
//|  TREND_UP   : H4 BULL, close > EMA slow, EMA fast > slow, ADX ok |
//|  TREND_DOWN : mirror                                             |
//|  RANGE      : anything else                -> no trades          |
//|  HIGH_VOL   : ATR ratio > VRMax             -> skip / half risk  |
//|  DEAD       : ATR ratio < VRMin             -> no trades          |
//+------------------------------------------------------------------+

bool EvaluateRegime(const StructureInfo &h4, RegimeInfo &rg)
{
   rg.regime   = XTP_REGIME_NONE;
   rg.dir      = 0;
   rg.riskMult = 0;
   rg.adx      = 0;
   rg.vr       = 0;
   if(!h4.valid)
      return false;

   double emaFast, emaSlow, adx;
   if(!XtpReadBuffer(g_hEmaFastH4, 0, 1, emaFast) ||
      !XtpReadBuffer(g_hEmaSlowH4, 0, 1, emaSlow) ||
      !XtpReadBuffer(g_hAdxH1, 0, 1, adx))
      return false;
   double closeH4 = iClose(_Symbol, PERIOD_H4, 1);
   if(closeH4 <= 0)
      return false;

   //--- volatility ratio: current H1 ATR vs its recent average
   double atr[];
   ArraySetAsSeries(atr, false);
   int got = CopyBuffer(g_hAtrH1, 0, 1, InpAtrAvgBars, atr);
   if(got < InpAtrAvgBars || got < 2)
      return false;
   double sum = 0;
   for(int i = 0; i < got; i++)
      sum += atr[i];
   double avg = sum / got;
   if(avg <= 0)
      return false;

   rg.adx = adx;
   rg.vr  = atr[got - 1] / avg;

   bool up = (h4.state == STRUCT_BULL && closeH4 > emaSlow && emaFast > emaSlow && adx >= InpAdxMin);
   bool dn = (h4.state == STRUCT_BEAR && closeH4 < emaSlow && emaFast < emaSlow && adx >= InpAdxMin);

   if(rg.vr > InpVRMax)
   {
      rg.regime = XTP_REGIME_HIGH_VOL;
      if(InpTradeHighVol && (up || dn))
      {
         rg.dir = up ? 1 : -1;
         rg.riskMult = 0.5;
      }
      return true;
   }
   if(rg.vr < InpVRMin)
   {
      rg.regime = XTP_REGIME_DEAD;
      return true;
   }
   if(up)
   {
      rg.regime = XTP_REGIME_TREND_UP;
      rg.dir = 1;
      rg.riskMult = 1.0;
   }
   else if(dn)
   {
      rg.regime = XTP_REGIME_TREND_DOWN;
      rg.dir = -1;
      rg.riskMult = 1.0;
   }
   else
      rg.regime = XTP_REGIME_RANGE;
   return true;
}
//+------------------------------------------------------------------+
//+==================================================================+
//| SECTION: FILTERS                                                 |
//+==================================================================+
//+------------------------------------------------------------------+
//| Filters - session windows and high-impact news filter            |
//|                                                                  |
//| All times are BROKER SERVER time. On NY-close servers            |
//| (GMT+2 winter / GMT+3 summer) the defaults stay valid all year.  |
//+------------------------------------------------------------------+

int g_lonStart  = -1;
int g_lonEnd    = -1;
int g_nyStart   = -1;
int g_nyEnd     = -1;
int g_friNoNew  = -1;
int g_friClose  = -1;
int g_rollStart = -1;
int g_rollEnd   = -1;

long     g_newsCsv[];          // event times loaded from CSV (tester + live fallback)
long     g_newsCal[];          // event times from the MQL5 calendar (live only)
datetime g_newsCalLoadedAt = 0;

//--- "HH:MM" -> minutes after midnight, -1 if malformed
int XtpParseHHMM(const string text)
{
   string p[];
   if(StringSplit(text, ':', p) != 2)
      return -1;
   int h = (int)StringToInteger(p[0]);
   int m = (int)StringToInteger(p[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59)
      return -1;
   return h * 60 + m;
}

bool SessionInit()
{
   g_lonStart  = XtpParseHHMM(InpLondonStart);
   g_lonEnd    = XtpParseHHMM(InpLondonEnd);
   g_nyStart   = XtpParseHHMM(InpNYStart);
   g_nyEnd     = XtpParseHHMM(InpNYEnd);
   g_friNoNew  = XtpParseHHMM(InpFridayNoNewAfter);
   g_friClose  = XtpParseHHMM(InpFridayCloseTime);
   g_rollStart = XtpParseHHMM(InpRolloverStart);
   g_rollEnd   = XtpParseHHMM(InpRolloverEnd);
   return (g_lonStart >= 0 && g_lonEnd >= 0 && g_nyStart >= 0 && g_nyEnd >= 0 &&
           g_friNoNew >= 0 && g_friClose >= 0 && g_rollStart >= 0 && g_rollEnd >= 0);
}

//--- [start, end) window that may wrap past midnight
bool XtpInWindow(const int now, const int start, const int end)
{
   if(start <= end)
      return (now >= start && now < end);
   return (now >= start || now < end);
}

bool SessionAllowsEntry(const datetime now)
{
   int dow = XtpDayOfWeek(now);
   if(dow == 0 || dow == 6)
      return false;
   int m = XtpMinuteOfDay(now);
   if(dow == 5 && m >= g_friNoNew)
      return false;
   if(XtpInWindow(m, g_rollStart, g_rollEnd))
      return false;
   return XtpInWindow(m, g_lonStart, g_lonEnd) || XtpInWindow(m, g_nyStart, g_nyEnd);
}

bool SessionForceClose(const datetime now)
{
   int m = XtpMinuteOfDay(now);
   if(InpCloseBeforeRollover && XtpInWindow(m, g_rollStart, g_rollEnd))
      return true;
   if(XtpDayOfWeek(now) == 5 && m >= g_friClose)
      return true;
   return false;
}

string SessionLabel(const datetime now)
{
   int m = XtpMinuteOfDay(now);
   if(XtpInWindow(m, g_lonStart, g_lonEnd)) return "LONDON window";
   if(XtpInWindow(m, g_nyStart, g_nyEnd))   return "NEW YORK window";
   if(XtpInWindow(m, g_rollStart, g_rollEnd)) return "ROLLOVER (no trade)";
   return "outside windows";
}

//+------------------------------------------------------------------+
//| News                                                             |
//+------------------------------------------------------------------+
void XtpPushTime(long &arr[], const long value)
{
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1, 256);
   arr[n] = value;
}

//--- live terminal only: write high-impact calendar events to the CSV so the
//--- Strategy Tester (where the calendar API is unavailable) can use them
void NewsExportCsv()
{
   MqlCalendarValue vals[];
   datetime to = TimeCurrent() + 30 * 86400;
   bool ok;
   if(InpNewsCurrency == "ALL")
      ok = CalendarValueHistory(vals, InpExportFrom, to);
   else
      ok = CalendarValueHistory(vals, InpExportFrom, to, NULL, InpNewsCurrency);
   if(!ok)
   {
      PrintFormat("[XTP] News export failed: calendar error %d (is the terminal connected?)", GetLastError());
      return;
   }
   int h = FileOpen(InpNewsCsvFile, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      PrintFormat("[XTP] News export: cannot create %s, error %d", InpNewsCsvFile, GetLastError());
      return;
   }
   FileWriteString(h, "# time(server),currency,importance,event\r\n");
   int written = 0;
   int n = ArraySize(vals);
   for(int i = 0; i < n; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev))
         continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      MqlCalendarCountry country;
      string cur = InpNewsCurrency;
      if(CalendarCountryById(ev.country_id, country))
         cur = country.currency;
      string name = ev.name;
      StringReplace(name, ",", " ");
      FileWriteString(h, StringFormat("%s,%s,HIGH,%s\r\n",
                                      TimeToString(vals[i].time, TIME_DATE | TIME_MINUTES), cur, name));
      written++;
   }
   FileClose(h);
   PrintFormat("[XTP] Exported %d high-impact events to Common\\Files\\%s", written, InpNewsCsvFile);
}

//--- CSV lines: "YYYY.MM.DD HH:MM,USD,HIGH,Event name"  (server time, '#' = comment)
int NewsLoadCsv()
{
   ArrayFree(g_newsCsv);
   int h = FileOpen(InpNewsCsvFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      PrintFormat("[XTP] News CSV '%s' not found in Common\\Files (error %d)", InpNewsCsvFile, GetLastError());
      return 0;
   }
   string want = InpNewsCurrency;
   StringToUpper(want);
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringLen(line) == 0)
         continue;
      ushort c0 = StringGetCharacter(line, 0);
      if(c0 < '0' || c0 > '9')          // comment or header
         continue;
      string f[];
      if(StringSplit(line, ',', f) < 3)
         continue;
      datetime t = StringToTime(f[0]);
      if(t <= 0)
         continue;
      string cur = f[1];
      string imp = f[2];
      StringTrimLeft(cur);
      StringTrimRight(cur);
      StringTrimLeft(imp);
      StringTrimRight(imp);
      StringToUpper(cur);
      StringToUpper(imp);
      if(want != "ALL" && cur != want)
         continue;
      if(imp != "HIGH")
         continue;
      XtpPushTime(g_newsCsv, (long)t);
   }
   FileClose(h);
   ArraySort(g_newsCsv);
   return ArraySize(g_newsCsv);
}

//--- live terminal: pull high-impact events from the built-in calendar every hour
void NewsRefreshCalendar(const datetime now)
{
   if(!InpUseNews || MQLInfoInteger(MQL_TESTER))
      return;
   if(g_newsCalLoadedAt != 0 && (long)now - (long)g_newsCalLoadedAt < 3600)
      return;
   g_newsCalLoadedAt = now;

   MqlCalendarValue vals[];
   datetime from = now - 86400;
   datetime to   = now + 7 * 86400;
   bool ok;
   if(InpNewsCurrency == "ALL")
      ok = CalendarValueHistory(vals, from, to);
   else
      ok = CalendarValueHistory(vals, from, to, NULL, InpNewsCurrency);
   if(!ok)
   {
      XtpLog(StringFormat("Calendar unavailable (error %d), using CSV only", GetLastError()));
      return;
   }
   ArrayFree(g_newsCal);
   int n = ArraySize(vals);
   for(int i = 0; i < n; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev))
         continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      XtpPushTime(g_newsCal, (long)vals[i].time);
   }
}

bool XtpNewsHit(const long &arr[], const long now, const long before, const long after)
{
   int n = ArraySize(arr);
   for(int i = 0; i < n; i++)
      if(now >= arr[i] - before && now <= arr[i] + after)
         return true;
   return false;
}

bool NewsIsBlocked(const datetime now)
{
   if(!InpUseNews)
      return false;
   long b = (long)InpNewsBeforeMin * 60;
   long a = (long)InpNewsAfterMin * 60;
   return XtpNewsHit(g_newsCsv, (long)now, b, a) || XtpNewsHit(g_newsCal, (long)now, b, a);
}

long XtpSecondsToNext(const long &arr[], const long now)
{
   long best = LONG_MAX;
   int n = ArraySize(arr);
   for(int i = 0; i < n; i++)
   {
      long d = arr[i] - now;
      if(d >= 0 && d < best)
         best = d;
   }
   return best;
}

//--- minutes until the next high-impact event, INT_MAX if none known
int NewsMinutesToNext(const datetime now)
{
   if(!InpUseNews)
      return INT_MAX;
   long best = XtpSecondsToNext(g_newsCsv, (long)now);
   long cal  = XtpSecondsToNext(g_newsCal, (long)now);
   if(cal < best)
      best = cal;
   if(best == LONG_MAX)
      return INT_MAX;
   return (int)(best / 60);
}
//+------------------------------------------------------------------+
//+==================================================================+
//| SECTION: RISK                                                    |
//+==================================================================+
//+------------------------------------------------------------------+
//| Risk - position sizing, loss locks, loss-streak adaptation       |
//+------------------------------------------------------------------+

double g_dayStartEq  = 0;
double g_weekStartEq = 0;
double g_peakEq      = 0;
long   g_dayKey      = 0;
long   g_weekKey     = 0;
bool   g_dayLocked   = false;
bool   g_weekLocked  = false;
bool   g_ddLocked    = false;
double g_streakMult  = 1.0;
int    g_streakDealsSeen = -1;

void RiskSave(const string key, const double value)
{
   GlobalVariableSet(XtpGvKey(key), value);
}

//--- called every tick: roll day/week anchors, update locks
void RiskUpdate(const datetime now)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   long dayKey = (long)XtpDayStart(now);
   if(dayKey != g_dayKey)
   {
      g_dayKey = dayKey;
      g_dayStartEq = eq;
      g_dayLocked = false;
      RiskSave("dayKey", (double)g_dayKey);
      RiskSave("dayEq", g_dayStartEq);
      RiskSave("dayLock", 0);
   }

   long weekKey = dayKey - (long)((XtpDayOfWeek(now) + 6) % 7) * 86400;   // Monday 00:00
   if(weekKey != g_weekKey)
   {
      g_weekKey = weekKey;
      g_weekStartEq = eq;
      g_weekLocked = false;
      RiskSave("weekKey", (double)g_weekKey);
      RiskSave("weekEq", g_weekStartEq);
      RiskSave("weekLock", 0);
   }

   if(eq > g_peakEq)
   {
      g_peakEq = eq;
      RiskSave("peak", g_peakEq);
   }

   if(!g_dayLocked && g_dayStartEq > 0 &&
      (g_dayStartEq - eq) / g_dayStartEq * 100.0 >= InpMaxDailyLossPct)
   {
      g_dayLocked = true;
      RiskSave("dayLock", 1);
      XtpLog("Daily loss limit hit - no new trades today");
   }
   if(!g_weekLocked && g_weekStartEq > 0 &&
      (g_weekStartEq - eq) / g_weekStartEq * 100.0 >= InpMaxWeeklyLossPct)
   {
      g_weekLocked = true;
      RiskSave("weekLock", 1);
      XtpLog("Weekly loss limit hit - no new trades this week");
   }
   if(!g_ddLocked && g_peakEq > 0 &&
      (g_peakEq - eq) / g_peakEq * 100.0 >= InpMaxDrawdownPct)
   {
      g_ddLocked = true;
      RiskSave("ddLock", 1);
      string msg = StringFormat("XTP: max drawdown %.1f%% reached - EA disabled. Review the system, then restart with InpResetDDLock=true.",
                                InpMaxDrawdownPct);
      Print(msg);
      if(!MQLInfoInteger(MQL_TESTER))
         Alert(msg);
   }
}

void RiskInit()
{
   // the tester keeps global variables between runs: start every test clean
   if(MQLInfoInteger(MQL_TESTER))
      GlobalVariablesDeleteAll(XtpGvPrefix());

   g_dayKey      = (long)XtpGvGet(XtpGvKey("dayKey"), 0);
   g_dayStartEq  = XtpGvGet(XtpGvKey("dayEq"), 0);
   g_dayLocked   = XtpGvGet(XtpGvKey("dayLock"), 0) > 0.5;
   g_weekKey     = (long)XtpGvGet(XtpGvKey("weekKey"), 0);
   g_weekStartEq = XtpGvGet(XtpGvKey("weekEq"), 0);
   g_weekLocked  = XtpGvGet(XtpGvKey("weekLock"), 0) > 0.5;
   g_peakEq      = XtpGvGet(XtpGvKey("peak"), 0);
   g_ddLocked    = XtpGvGet(XtpGvKey("ddLock"), 0) > 0.5;

   if(InpResetDDLock)
   {
      g_ddLocked = false;
      g_peakEq = AccountInfoDouble(ACCOUNT_EQUITY);
      RiskSave("ddLock", 0);
      RiskSave("peak", g_peakEq);
      Print("[XTP] Drawdown lock reset, new peak = ", DoubleToString(g_peakEq, 2));
   }
   g_streakDealsSeen = -1;
   RiskUpdate(TimeCurrent());
}

bool XtpIsPositionOpen(const long positionId)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0)
         continue;
      if(PositionGetInteger(POSITION_IDENTIFIER) == positionId)
         return true;
   }
   return false;
}

//--- half risk after N losses in a row, full risk again after M wins
void RiskUpdateStreak()
{
   datetime now = TimeCurrent();
   if(!HistorySelect(now - 120 * 86400, now + 86400))
      return;
   int total = HistoryDealsTotal();
   if(total == g_streakDealsSeen)
      return;
   g_streakDealsSeen = total;

   long     ids[];
   double   pnl[];
   datetime closed[];
   int      m = 0;
   for(int i = 0; i < total; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic)
         continue;
      long pid = HistoryDealGetInteger(d, DEAL_POSITION_ID);
      int k = -1;
      for(int q = 0; q < m; q++)
         if(ids[q] == pid)
         {
            k = q;
            break;
         }
      if(k < 0)
      {
         ArrayResize(ids, m + 1, 64);
         ArrayResize(pnl, m + 1, 64);
         ArrayResize(closed, m + 1, 64);
         ids[m] = pid;
         pnl[m] = 0;
         closed[m] = 0;
         k = m;
         m++;
      }
      pnl[k] += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
                HistoryDealGetDouble(d, DEAL_COMMISSION);
      long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
         closed[k] = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
   }

   //--- deals are chronological; positions are processed in first-deal order,
   //--- which equals close order because the EA holds one position at a time
   int  losses = 0, wins = 0;
   bool reduced = false;
   for(int k = 0; k < m; k++)
   {
      if(closed[k] == 0 || XtpIsPositionOpen(ids[k]))
         continue;
      if(pnl[k] < 0)
      {
         losses++;
         wins = 0;
         if(losses >= InpLossStreakReduce)
            reduced = true;
      }
      else
      {
         wins++;
         losses = 0;
         if(reduced && wins >= InpWinsToRestore)
            reduced = false;
      }
   }
   double mult = reduced ? 0.5 : 1.0;
   if(mult != g_streakMult)
      XtpLog(StringFormat("Loss-streak risk multiplier -> %.2f", mult));
   g_streakMult = mult;
}

int RiskTradesToday(const datetime now)
{
   if(!HistorySelect(XtpDayStart(now), now + 60))
      return 0;
   int count = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic)
         continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
         count++;
   }
   return count;
}

//--- lots so that a stop-out at `sl` loses riskPct of equity; 0 = cannot size
double RiskCalcLots(const int dir, const double entry, const double sl, const double riskPct)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * riskPct / 100.0;
   if(riskMoney <= 0)
      return 0;

   // contract size differs per broker (100 / 10 / 1 oz): ask the server
   double lossPerLot = 0;
   double profit = 0;
   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcProfit(type, _Symbol, 1.0, entry, sl, profit))
      lossPerLot = -profit;
   if(lossPerLot <= 0)
   {
      double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tv <= 0)
         tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      lossPerLot = MathAbs(entry - sl) / XtpTickSize() * tv;
   }
   if(lossPerLot <= 0)
      return 0;

   double lots = XtpNormVolumeDown(riskMoney / lossPerLot);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lots < vmin)
      return 0;                       // never round UP past the risk budget
   if(vmax > 0 && lots > vmax)
      lots = XtpNormVolumeDown(vmax);

   double margin = 0;
   if(OrderCalcMargin(type, _Symbol, lots, entry, margin) &&
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9)
   {
      XtpLog(StringFormat("Not enough free margin for %.2f lots", lots));
      return 0;
   }
   return lots;
}
//+------------------------------------------------------------------+
//+==================================================================+
//| SECTION: EXECUTION                                               |
//+==================================================================+
//+------------------------------------------------------------------+
//| Execution - open-position management                             |
//|                                                                  |
//|  every tick : TP1 partial close at +1R, then stop to break-even  |
//|  every bar  : session/rollover exit, H1 CHoCH exit, time stop,   |
//|               news exit, trailing stop on the runner             |
//+------------------------------------------------------------------+

bool XtpIsMine()
{
   return PositionGetString(POSITION_SYMBOL) == _Symbol &&
          (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic;
}

int CountMyPositions()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0)
         continue;
      if(XtpIsMine())
         c++;
   }
   return c;
}

void XtpClosePosition(const ulong ticket, const string reason)
{
   if(g_trade.PositionClose(ticket))
      XtpLog(StringFormat("Closed #%I64u: %s", ticket, reason));
   else
      XtpLog(StringFormat("Close #%I64u failed (%s): retcode %u", ticket, reason, g_trade.ResultRetcode()));
}

void CloseAllMine(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !XtpIsMine())
         continue;
      XtpClosePosition(t, reason);
   }
}

//--- initial risk distance (entry -> original SL) of the SELECTED position
double PosRiskDist()
{
   long   pid = PositionGetInteger(POSITION_IDENTIFIER);
   string key = XtpPosKey(pid, "R");
   if(GlobalVariableCheck(key))
      return GlobalVariableGet(key);
   // fallback (e.g. EA attached to an existing position): derive from the current SL
   double sl = PositionGetDouble(POSITION_SL);
   if(sl <= 0)
      return 0;
   double r = MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - sl);
   if(r < XtpTickSize() * 10)      // SL already near entry: R unknown, leave it alone
      return 0;
   GlobalVariableSet(key, r);
   return r;
}

bool PosTp1Done()
{
   return XtpGvGet(XtpPosKey(PositionGetInteger(POSITION_IDENTIFIER), "T1"), 0) > 0.5;
}

//--- move SL only in the protective direction and only if the server accepts the distance
bool XtpMoveSL(const ulong ticket, const int dir, double newSL)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   double cur = PositionGetDouble(POSITION_SL);
   double tp  = PositionGetDouble(POSITION_TP);
   newSL = XtpNormPrice(newSL);
   if(cur > 0 && dir * (newSL - cur) < XtpTickSize() * 0.5)
      return false;
   double minDist = XtpMinStopDistance();
   if(dir > 0 && newSL > SymbolInfoDouble(_Symbol, SYMBOL_BID) - minDist)
      return false;
   if(dir < 0 && newSL < SymbolInfoDouble(_Symbol, SYMBOL_ASK) + minDist)
      return false;
   if(!g_trade.PositionModify(ticket, newSL, tp))
   {
      XtpLog(StringFormat("Modify SL #%I64u failed: retcode %u", ticket, g_trade.ResultRetcode()));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void ManageTick()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !XtpIsMine())
         continue;
      int    dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      long   pid = PositionGetInteger(POSITION_IDENTIFIER);
      double op  = PositionGetDouble(POSITION_PRICE_OPEN);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double r   = PosRiskDist();
      if(r <= 0)
         continue;
      bool tp1 = PosTp1Done();

      double px = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(!tp1 && dir * (px - op) >= InpTP1_R * r)
      {
         double closeVol = XtpNormVolumeDown(vol * InpTP1ClosePct / 100.0);
         double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(closeVol >= vmin && vol - closeVol >= vmin - 1e-9)
         {
            if(!g_trade.PositionClosePartial(t, closeVol))
            {
               XtpLog(StringFormat("TP1 partial close #%I64u failed: retcode %u", t, g_trade.ResultRetcode()));
               continue;               // retry on next tick
            }
         }
         GlobalVariableSet(XtpPosKey(pid, "T1"), 1);
         tp1 = true;
         XtpLog(StringFormat("TP1 hit #%I64u: closed %.2f lots, stop to break-even", t, closeVol));
      }
      if(tp1)
         XtpMoveSL(t, dir, op + dir * InpBEOffset);   // no-op once SL is at/after BE
   }
}

//+------------------------------------------------------------------+
void ManageBar(const datetime now)
{
   bool   force  = SessionForceClose(now);
   int    toNews = NewsMinutesToNext(now);
   double atrM15 = 0;
   XtpReadBuffer(g_hAtrM15, 0, 1, atrM15);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !XtpIsMine())
         continue;
      int      dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double   op  = PositionGetDouble(POSITION_PRICE_OPEN);
      datetime ot  = (datetime)PositionGetInteger(POSITION_TIME);
      double   r   = PosRiskDist();
      bool     tp1 = PosTp1Done();
      double   px  = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      //--- 1) rollover / Friday close
      if(force)
      {
         XtpClosePosition(t, "session end / rollover");
         continue;
      }

      //--- 2) H1 structure turned against the position
      if(InpStructureExit && g_h1.valid && g_h1.state != dir)
      {
         XtpClosePosition(t, "H1 CHoCH against position");
         continue;
      }

      int barsOpen = iBarShift(_Symbol, PERIOD_M15, ot);

      //--- 3) time stop: trade never moved InpTimeStopMinR in our favour
      if(!tp1 && InpTimeStopBars > 0 && r > 0 && barsOpen >= InpTimeStopBars)
      {
         double mfe = -1;
         if(dir > 0)
         {
            int hi = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, barsOpen + 1, 0);
            if(hi >= 0)
               mfe = iHigh(_Symbol, PERIOD_M15, hi) - op;
         }
         else
         {
            int lo = iLowest(_Symbol, PERIOD_M15, MODE_LOW, barsOpen + 1, 0);
            if(lo >= 0)
               mfe = op - iLow(_Symbol, PERIOD_M15, lo);
         }
         if(mfe >= 0 && mfe < InpTimeStopMinR * r)
         {
            XtpClosePosition(t, "time stop");
            continue;
         }
      }

      //--- 4) high-impact news ahead: protect a winner, cut anything else
      if(toNews <= InpNewsExitBeforeMin && r > 0)
      {
         if(dir * (px - op) >= 0.5 * r)
            XtpMoveSL(t, dir, op + dir * InpBEOffset);
         else
         {
            XtpClosePosition(t, StringFormat("high-impact news in %d min", toNews));
            continue;
         }
      }

      //--- 5) trail the runner after TP1
      if(tp1 && atrM15 > 0)
      {
         double newSL = 0;
         if(InpTrailMode == XTP_TRAIL_SWING)
         {
            if(g_m15.valid && dir > 0 && g_m15.hasLow)
               newSL = g_m15.lastLow - InpSLBufferATR * atrM15;
            if(g_m15.valid && dir < 0 && g_m15.hasHigh)
               newSL = g_m15.lastHigh + InpSLBufferATR * atrM15 + XtpSpread();
         }
         else if(barsOpen >= 0)
         {
            if(dir > 0)
            {
               int hi = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, MathMax(1, barsOpen), 1);
               if(hi >= 0)
                  newSL = iHigh(_Symbol, PERIOD_M15, hi) - InpChandelierATR * atrM15;
            }
            else
            {
               int lo = iLowest(_Symbol, PERIOD_M15, MODE_LOW, MathMax(1, barsOpen), 1);
               if(lo >= 0)
                  newSL = iLow(_Symbol, PERIOD_M15, lo) + InpChandelierATR * atrM15 + XtpSpread();
            }
         }
         if(newSL > 0)
            XtpMoveSL(t, dir, newSL);
      }
   }
}
//+------------------------------------------------------------------+
//+==================================================================+
//| SECTION: SIGNAL                                                  |
//+==================================================================+
//+------------------------------------------------------------------+
//| Signal - Trend-Pullback entry                                    |
//|                                                                  |
//|  H4 regime gives the side -> H1 impulse leg + Fib pullback zone  |
//|  -> M15 close breaks the pullback's internal swing (CHoCH)       |
//|  -> SL beyond pullback extreme, room >= MinRR, spread filter     |
//+------------------------------------------------------------------+

//--- find the M15 bar holding the H1 impulse extreme, then the pullback
//--- extreme on closed M15 bars after it (sees moves inside the open H1 bar)
bool PullbackOnM15(const int dir, const datetime legEndTime, double &pbExt, datetime &extremeBarTime)
{
   MqlRates r[];
   ArraySetAsSeries(r, false);
   datetime lastClosed = iTime(_Symbol, PERIOD_M15, 1);
   if(lastClosed <= legEndTime)
      return false;
   int n = CopyRates(_Symbol, PERIOD_M15, legEndTime, lastClosed, r);
   if(n < 2)
      return false;

   datetime h1End = legEndTime + PeriodSeconds(PERIOD_H1);
   int k0 = -1;
   for(int k = 0; k < n && r[k].time < h1End; k++)
      if(k0 < 0 || (dir > 0 ? r[k].high > r[k0].high : r[k].low < r[k0].low))
         k0 = k;
   if(k0 < 0 || k0 >= n - 1)
      return false;

   extremeBarTime = r[k0].time;
   pbExt = (dir > 0) ? DBL_MAX : -DBL_MAX;
   for(int k = k0 + 1; k < n; k++)
      pbExt = (dir > 0) ? MathMin(pbExt, r[k].low) : MathMax(pbExt, r[k].high);
   return true;
}

//+------------------------------------------------------------------+
void TryEntry()
{
   const int dir = g_regime.dir;
   if(dir == 0 || !g_h1.valid || !g_m15.valid)
      return;
   if(g_h1.state != dir || !g_h1.hasLeg || g_h1.legDir != dir)
      return;

   //--- 1) M15 trigger: last closed bar broke the latest M15 swing against the pullback
   bool trigger = (dir > 0) ? g_m15.bullBreakNow : g_m15.bearBreakNow;
   if(!trigger)
      return;
   double   brokenLevel = (dir > 0) ? g_m15.brokenHigh : g_m15.brokenLow;
   datetime brokenTime  = (dir > 0) ? g_m15.brokenHighTime : g_m15.brokenLowTime;
   string   side        = (dir > 0) ? "BUY" : "SELL";

   //--- 2) H1 impulse leg must be recent and the pullback inside the Fib zone
   if(InpMaxPullbackBarsH1 > 0 &&
      iBarShift(_Symbol, PERIOD_H1, g_h1.legEndTime) > InpMaxPullbackBarsH1)
   {
      XtpLog(side + " trigger skipped: H1 pullback older than InpMaxPullbackBarsH1");
      return;
   }
   double range = MathAbs(g_h1.legEnd - g_h1.legStart);
   if(range <= 0)
      return;
   double lvlShallow = g_h1.legEnd - dir * InpFibMin * range;
   double lvlDeep    = g_h1.legEnd - dir * InpFibMax * range;
   if(g_h1.hasPullback && dir * (g_h1.pbExtremeClose - lvlDeep) < 0)
   {
      XtpLog(side + " trigger skipped: an H1 close went beyond the deep Fib level");
      return;
   }

   double   pbExt;
   datetime extremeBar;
   if(!PullbackOnM15(dir, g_h1.legEndTime, pbExt, extremeBar))
      return;
   if(dir * (pbExt - lvlShallow) > 0)
   {
      XtpLog(side + " trigger skipped: pullback has not reached the Fib zone");
      return;
   }

   //--- the broken M15 swing must belong to THIS pullback (internal LH / HL)
   if(brokenTime <= extremeBar || dir * (g_h1.legEnd - brokenLevel) <= 0)
      return;
   if(InpRequireSweep)
   {
      datetime sweep = (dir > 0) ? g_m15.lastSweepLowTime : g_m15.lastSweepHighTime;
      if(sweep <= extremeBar)
      {
         XtpLog(side + " trigger skipped: no liquidity sweep inside the pullback");
         return;
      }
   }

   //--- 3) stop, room to target, spread
   double atrM15, atrH1;
   if(!XtpReadBuffer(g_hAtrM15, 0, 1, atrM15) || !XtpReadBuffer(g_hAtrH1, 0, 1, atrH1))
      return;
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   double entry  = (dir > 0) ? ask : bid;

   // buy SL triggers on bid; sell SL triggers on ask, so it needs the spread on top
   double sl = (dir > 0) ? pbExt - InpSLBufferATR * atrM15
                         : pbExt + InpSLBufferATR * atrM15 + spread;
   double dist = dir * (entry - sl);
   double minDist = MathMax(InpMinSL_ATR_M15 * atrM15, XtpMinStopDistance());
   if(dist < minDist)
   {
      dist = minDist;
      sl = entry - dir * dist;
   }
   if(dist > InpMaxSL_ATR_H1 * atrH1)
   {
      XtpLog(StringFormat("%s skipped: SL %.2f wider than %.1f x ATR(H1)", side, dist, InpMaxSL_ATR_H1));
      return;
   }
   double room = dir * (g_h1.legEnd - entry);
   if(room < InpMinRRRoom * dist)
   {
      XtpLog(StringFormat("%s skipped: room to H1 swing %.2fR < %.2fR", side, room / dist, InpMinRRRoom));
      return;
   }
   if(spread > InpMaxSpreadPrice || spread > dist * InpMaxSpreadPctSL / 100.0)
   {
      XtpLog(StringFormat("%s skipped: spread %.2f too wide", side, spread));
      return;
   }

   double tp = entry + dir * InpTP2_R * dist;
   if(InpCapTP2AtSwing)
      tp = (dir > 0) ? MathMin(tp, g_h1.legEnd) : MathMax(tp, g_h1.legEnd);
   sl = XtpNormPrice(sl);
   tp = XtpNormPrice(tp);

   //--- 4) size and send
   double riskPct = InpRiskPercent * g_regime.riskMult * g_streakMult;
   double lots = RiskCalcLots(dir, entry, sl, riskPct);
   if(lots <= 0)
   {
      XtpLog(side + " skipped: risk budget is below the minimum lot");
      return;
   }

   bool sent = (dir > 0) ? g_trade.Buy(lots, _Symbol, 0.0, sl, tp, "XTP pullback")
                         : g_trade.Sell(lots, _Symbol, 0.0, sl, tp, "XTP pullback");
   uint rc = g_trade.ResultRetcode();
   if(!sent || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED))
   {
      XtpLog(StringFormat("%s order failed: retcode %u %s", side, rc, g_trade.ResultRetcodeDescription()));
      return;
   }

   //--- remember the initial risk (R) by position id for TP1 / BE / time stop
   double fill = g_trade.ResultPrice();
   if(fill <= 0)
      fill = entry;
   ulong deal = g_trade.ResultDeal();
   if(deal > 0 && HistoryDealSelect(deal))
   {
      long pid = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      GlobalVariableSet(XtpPosKey(pid, "R"), MathAbs(fill - sl));
      GlobalVariableSet(XtpPosKey(pid, "T1"), 0);
   }
   XtpLog(StringFormat("%s %.2f lots @ %.2f  SL %.2f  TP %.2f  (R=%.2f, risk %.2f%%, regime %s, leg %.2f->%.2f)",
                       side, lots, fill, sl, tp, MathAbs(fill - sl), riskPct,
                       XtpRegimeName(g_regime.regime), g_h1.legStart, g_h1.legEnd));
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
void UpdateDashboard(const datetime now)
{
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   int    toNews  = NewsMinutesToNext(now);
   string newsTxt = (toNews == INT_MAX) ? "-" : IntegerToString(toNews) + " min";
   string side    = (g_regime.dir > 0) ? "BUY only" : (g_regime.dir < 0) ? "SELL only" : "no trade";
   Comment(StringFormat(
              "XAU Trend Pullback EA  (magic %I64u)\n"
              "Regime: %s -> %s   ADX(H1) %.1f   ATR ratio %.2f\n"
              "Structure  H4: %s   H1: %s   M15: %s\n"
              "Session: %s   Spread: %.2f\n"
              "Next high-impact news: %s\n"
              "Risk x%.2f   Locks: day=%s week=%s maxDD=%s",
              InpMagic,
              XtpRegimeName(g_regime.regime), side, g_regime.adx, g_regime.vr,
              XtpStateName(g_h4.state), XtpStateName(g_h1.state), XtpStateName(g_m15.state),
              SessionLabel(now), XtpSpread(),
              newsTxt,
              g_regime.riskMult * g_streakMult,
              g_dayLocked ? "ON" : "off", g_weekLocked ? "ON" : "off", g_ddLocked ? "ON" : "off"));
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(!SessionInit())
   {
      Print("[XTP] Invalid session time input - use HH:MM");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpFibMin <= 0 || InpFibMax >= 1 || InpFibMin >= InpFibMax ||
      InpRiskPercent <= 0 || InpRiskPercent > 5 || InpTP1_R <= 0 || InpTP2_R <= InpTP1_R)
   {
      Print("[XTP] Invalid Fib / risk / TP inputs");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_hAtrH4     = iATR(_Symbol, PERIOD_H4, InpAtrPeriod);
   g_hAtrH1     = iATR(_Symbol, PERIOD_H1, InpAtrPeriod);
   g_hAtrM15    = iATR(_Symbol, PERIOD_M15, InpAtrPeriod);
   g_hEmaFastH4 = iMA(_Symbol, PERIOD_H4, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_hEmaSlowH4 = iMA(_Symbol, PERIOD_H4, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   g_hAdxH1     = iADX(_Symbol, PERIOD_H1, InpAdxPeriod);
   if(g_hAtrH4 == INVALID_HANDLE || g_hAtrH1 == INVALID_HANDLE || g_hAtrM15 == INVALID_HANDLE ||
      g_hEmaFastH4 == INVALID_HANDLE || g_hEmaSlowH4 == INVALID_HANDLE || g_hAdxH1 == INVALID_HANDLE)
   {
      Print("[XTP] Failed to create indicator handles, error ", GetLastError());
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints((ulong)InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   RiskInit();

   if(InpExportNewsCsv && !MQLInfoInteger(MQL_TESTER))
      NewsExportCsv();

   if(InpUseNews)
   {
      int n = NewsLoadCsv();
      PrintFormat("[XTP] News CSV: %d high-impact %s events loaded", n, InpNewsCurrency);
      if(MQLInfoInteger(MQL_TESTER) && n == 0)
         Print("[XTP] WARNING: no news CSV in the tester - the news filter is OFF for this backtest. "
               "Attach the EA to a live/demo chart once with InpExportNewsCsv=true first.");
   }

   string sym = _Symbol;
   StringToUpper(sym);
   if(StringFind(sym, "XAU") < 0 && StringFind(sym, "GOLD") < 0)
      Print("[XTP] WARNING: this EA was designed for XAUUSD; current symbol is ", _Symbol);

   g_lastBar = 0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(g_hAtrH4);
   IndicatorRelease(g_hAtrH1);
   IndicatorRelease(g_hAtrM15);
   IndicatorRelease(g_hEmaFastH4);
   IndicatorRelease(g_hEmaSlowH4);
   IndicatorRelease(g_hAdxH1);
   Comment("");
}

//+------------------------------------------------------------------+
void OnNewBar(const datetime now)
{
   NewsRefreshCalendar(now);

   bool okH4  = g_engine.Analyze(_Symbol, PERIOD_H4,  InpFractalH4,  InpMinLegATR_H4,  g_hAtrH4,  InpStructureBars, g_h4);
   bool okH1  = g_engine.Analyze(_Symbol, PERIOD_H1,  InpFractalH1,  InpMinLegATR_H1,  g_hAtrH1,  InpStructureBars, g_h1);
   bool okM15 = g_engine.Analyze(_Symbol, PERIOD_M15, InpFractalM15, InpMinLegATR_M15, g_hAtrM15, InpStructureBars, g_m15);
   EvaluateRegime(g_h4, g_regime);
   RiskUpdateStreak();

   ManageBar(now);
   UpdateDashboard(now);

   if(!okH4 || !okH1 || !okM15)
      return;                                   // not enough history yet
   if(CountMyPositions() > 0)
      return;                                   // one position at a time
   if(g_dayLocked || g_weekLocked)
      return;
   if(!SessionAllowsEntry(now))
      return;
   if(NewsIsBlocked(now))
      return;
   if(RiskTradesToday(now) >= InpMaxTradesPerDay)
      return;
   TryEntry();
}

void OnTick()
{
   datetime now = TimeCurrent();
   RiskUpdate(now);
   if(g_ddLocked)
   {
      if(CountMyPositions() > 0)
         CloseAllMine("max drawdown lock");
      return;
   }

   ManageTick();

   datetime bar = iTime(_Symbol, PERIOD_M15, 0);
   if(bar == 0 || bar == g_lastBar)
      return;
   g_lastBar = bar;
   OnNewBar(now);
}

//--- clean up per-position state once a position is fully closed
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   long pid = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(!GlobalVariableCheck(XtpPosKey(pid, "R")))
      return;
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;
   if(!XtpIsPositionOpen(pid))
      GlobalVariablesDeleteAll(XtpGvPrefix() + IntegerToString(pid) + "_");
}

//--- custom optimisation criterion: profit factor, rewarded for sample size, penalised by drawdown
double OnTester()
{
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < 30)
      return 0;
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   return pf * MathSqrt(trades) * MathMax(0.0, 1.0 - dd / 100.0);
}
//+------------------------------------------------------------------+
