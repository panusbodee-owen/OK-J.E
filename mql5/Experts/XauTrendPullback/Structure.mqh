//+------------------------------------------------------------------+
//| Structure.mqh - swing / BOS / CHoCH / impulse-leg detection      |
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
