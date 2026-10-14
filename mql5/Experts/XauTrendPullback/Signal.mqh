//+------------------------------------------------------------------+
//| Signal.mqh - Trend-Pullback entry                                |
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
