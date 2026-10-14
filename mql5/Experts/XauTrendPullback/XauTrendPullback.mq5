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
//|  Attach to any XAUUSD chart (M15 recommended). Timeframes used   |
//|  are fixed (H4/H1/M15) regardless of the chart timeframe.        |
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

input group "=== Execution ==="
input double InpMaxSpreadPrice    = 0.35;    // Max spread in price (0.35 = 35 cents)
input double InpMaxSpreadPctSL    = 10.0;    // Max spread as % of SL distance
input ulong  InpMagic             = 20261014; // Magic number
input int    InpSlippagePoints    = 30;      // Max slippage (points)
input bool   InpDebugLog          = true;    // Print decisions to the Experts log

#include "Common.mqh"

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

#include "Structure.mqh"
#include "Regime.mqh"
#include "Filters.mqh"
#include "Risk.mqh"
#include "Execution.mqh"
#include "Signal.mqh"

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

   if(InpUseNews)
   {
      int n = NewsLoadCsv();
      PrintFormat("[XTP] News CSV: %d high-impact %s events loaded", n, InpNewsCurrency);
      if(MQLInfoInteger(MQL_TESTER) && n == 0)
         Print("[XTP] WARNING: no news CSV in the tester - the news filter is OFF for this backtest. "
               "Run Scripts\\XauExportNewsCalendar on a live chart first.");
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
