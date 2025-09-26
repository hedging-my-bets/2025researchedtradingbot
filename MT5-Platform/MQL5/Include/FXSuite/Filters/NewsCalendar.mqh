// FXSuite/Filters/NewsCalendar.mqh
#property strict

class CNewsCalendar
{
private:
   string  m_path;
   int     m_minImpact;     // 0=LOW,1=MEDIUM,2=HIGH
   int     m_before_min;    // blackout minutes before event
   int     m_after_min;     // blackout minutes after event

   int ImpactLevel(const string impact) const
   {
      string u = StringUpper(impact);
      if(StringFind(u,"HIGH")>=0)   return 2;
      if(StringFind(u,"MED")>=0)    return 1;
      if(StringFind(u,"LOW")>=0)    return 0;
      return 0;
   }

   bool CcyMatches(const string symbol, const string event_ccy) const
   {
      if(event_ccy=="ALL") return true;
      string base = StringSubstr(symbol,0,3);
      string quote= StringSubstr(symbol,(int)StringLen(symbol)-3,3);
      return (event_ccy==base || event_ccy==quote);
   }

public:
   CNewsCalendar(const string csv_path, const int min_impact, const int before_min, const int after_min)
   : m_path(csv_path), m_minImpact(min_impact), m_before_min(before_min), m_after_min(after_min) {}

   bool IsBlackout(const string symbol, const datetime now_utc) const
   {
      int h = FileOpen(m_path, FILE_READ|FILE_CSV|FILE_ANSI);
      if(h==INVALID_HANDLE) return false;

      // Assume header: utc_ts,impact,currency,title,...
      for(int i=0;i<4 && !FileIsEnding(h); ++i) FileReadString(h);

      bool blocked=false;
      while(!FileIsEnding(h)){
         string ts_s   = FileReadString(h);
         string imp    = FileReadString(h);
         string ccy    = FileReadString(h);
         string title  = FileReadString(h);

         if(ts_s=="" || imp=="" || ccy==""){ continue; }
         datetime ts = (datetime)StringToInteger(ts_s);
         int lvl = ImpactLevel(imp);
         if(lvl < m_minImpact) continue;
         if(!CcyMatches(symbol, ccy)) continue;

         datetime start_blk = ts - m_before_min*60;
         datetime end_blk   = ts + m_after_min*60;
         if(now_utc>=start_blk && now_utc<=end_blk){ blocked=true; break; }
      }
      FileClose(h);
      return blocked;
   }
};