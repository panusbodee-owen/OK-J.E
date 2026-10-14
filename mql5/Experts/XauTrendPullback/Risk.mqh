//+------------------------------------------------------------------+
//| Risk.mqh - position sizing, loss locks, loss-streak adaptation   |
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
