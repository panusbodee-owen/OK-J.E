//+------------------------------------------------------------------+
//|                                       XauExportNewsCalendar.mq5 |
//|                                                                  |
//| Exports high-impact events from the MetaTrader 5 economic        |
//| calendar to Terminal\Common\Files\<file> so XauTrendPullback can |
//| apply its news filter in the Strategy Tester (the calendar API   |
//| is not available inside the tester).                             |
//|                                                                  |
//| Run once on any LIVE/DEMO chart (needs a broker connection).     |
//| Times are written in broker SERVER time, same as the EA uses.    |
//+------------------------------------------------------------------+
#property copyright   "OK-J.E"
#property version     "1.00"
#property script_show_inputs

input datetime InpFrom     = D'2020.01.01';       // From (server time)
input datetime InpTo       = D'2026.12.31';       // To (server time)
input string   InpCurrency = "USD";               // Currency
input bool     InpHighOnly = true;                // High importance only
input string   InpFileName = "xau_news_usd.csv";  // File in Common\Files

string ImportanceName(const ENUM_CALENDAR_EVENT_IMPORTANCE imp)
{
   switch(imp)
   {
      case CALENDAR_IMPORTANCE_HIGH:     return "HIGH";
      case CALENDAR_IMPORTANCE_MODERATE: return "MEDIUM";
      case CALENDAR_IMPORTANCE_LOW:      return "LOW";
   }
   return "NONE";
}

void OnStart()
{
   MqlCalendarValue vals[];
   if(!CalendarValueHistory(vals, InpFrom, InpTo, NULL, InpCurrency))
   {
      PrintFormat("CalendarValueHistory failed, error %d (is the terminal connected?)", GetLastError());
      return;
   }

   int h = FileOpen(InpFileName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      PrintFormat("Cannot create %s, error %d", InpFileName, GetLastError());
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
      if(InpHighOnly && ev.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      string name = ev.name;
      StringReplace(name, ",", " ");
      FileWriteString(h, StringFormat("%s,%s,%s,%s\r\n",
                                      TimeToString(vals[i].time, TIME_DATE | TIME_MINUTES),
                                      InpCurrency, ImportanceName(ev.importance), name));
      written++;
   }
   FileClose(h);
   PrintFormat("Exported %d %s events to Common\\Files\\%s", written, InpCurrency, InpFileName);
}
//+------------------------------------------------------------------+
