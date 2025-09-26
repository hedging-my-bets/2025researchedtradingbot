// File-driven real-time calendar gating (no external DLL).
// Expects: MQL5/Files/calendar.csv with columns: event_time_iso,currency,importance
// Example row: 2025-09-26T11:00:00Z,USD,3
#property strict

class CNewsCalendar {
private:
   string m_path;
   datetime m_last_load;
   int m_threshold;   // 2=med, 3=high
   int m_pre_minutes, m_post_minutes;
   // cache
   datetime events_time[];
   string   events_ccy[];
   int      events_imp[];
public:
   CNewsCalendar(const string filename="calendar.csv", const int importance_threshold=2, const int pre=45, const int post=45)
   {
      m_path = "Files\\" + filename;
      m_threshold = importance_threshold;
      m_pre_minutes = pre;
      m_post_minutes= post;
      m_last_load   = 0;
      ArrayResize(events_time, 0);
      ArrayResize(events_ccy,  0);
      ArrayResize(events_imp,  0);
      Refresh();
   }

   void Refresh()
   {
      int h = FileOpen(m_path, FILE_READ|FILE_CSV|FILE_ANSI, ';');
      if(h==INVALID_HANDLE) return;
      ArrayResize(events_time, 0);
      ArrayResize(events_ccy,  0);
      ArrayResize(events_imp,  0);
      // Skip header if present
      string c0=FileReadString(h);
      if(StringFind(c0, "event_time_iso")>=0) { FileReadString(h); } // move to next line

      FileSeek(h, 0, SEEK_SET);
      // Robust CSV parse (comma separated)
      while(!FileIsEnding(h))
      {
         string t_iso = FileReadString(h);
         if(t_iso=="") { FileReadString(h); continue; } // eol
         string ccy   = FileReadString(h);
         string imp_s = FileReadString(h);
         // normalize
         StringTrimLeft(t_iso); StringTrimRight(t_iso);
         StringTrimLeft(ccy);   StringTrimRight(ccy);
         StringTrimLeft(imp_s); StringTrimRight(imp_s);
         datetime t = StringToTime(t_iso);
         int imp = (int)StringToInteger(imp_s);
         int n = ArraySize(events_time);
         ArrayResize(events_time, n+1);
         ArrayResize(events_ccy,  n+1);
         ArrayResize(events_imp,  n+1);
         events_time[n] = t;
         events_ccy[n]  = ccy;
         events_imp[n]  = imp;
         // eat EOL
         FileReadString(h);
      }
      FileClose(h);
      m_last_load = TimeCurrent();
   }

   bool IsBlackout(const string symbol, const datetime now_utc)
   {
      string base = StringSubstr(symbol, 0, 3);
      string quote= StringSubstr(symbol, 3, 3);
      for(int i=0;i<ArraySize(events_time);i++)
      {
         if(events_imp[i] < m_threshold) continue;
         if(events_ccy[i]!=base && events_ccy[i]!=quote) continue;
         int dtm = (int)MathRound((double)(now_utc - events_time[i]) / 60.0);
         if(dtm <= m_post_minutes && dtm >= -m_pre_minutes) return true;
      }
      return false;
   }
};