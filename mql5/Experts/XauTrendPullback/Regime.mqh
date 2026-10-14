//+------------------------------------------------------------------+
//| Regime.mqh - decide which side (if any) the EA may trade         |
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
