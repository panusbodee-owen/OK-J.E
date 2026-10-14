//+------------------------------------------------------------------+
//| Filters.mqh - session windows and high-impact news filter        |
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
