//+------------------------------------------------------------------+
//| Common.mqh - shared types and small helpers                      |
//| Part of XauTrendPullback EA. Compile XauTrendPullback.mq5 only.  |
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
