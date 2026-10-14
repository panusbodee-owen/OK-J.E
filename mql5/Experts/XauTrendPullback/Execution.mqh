//+------------------------------------------------------------------+
//| Execution.mqh - open-position management                         |
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
