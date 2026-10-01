#property strict

class CNewsCalendar
{
private:
   string m_path;
   string m_status_path;
   int m_min_impact;
   int m_before_min;
   int m_after_min;
   bool m_fail_closed;

   int ImpactLevel(string impact) const
   {
      StringToUpper(impact);
      if(StringFind(impact,"HIGH")>=0) return 2;
      if(StringFind(impact,"MED")>=0) return 1;
      if(StringFind(impact,"LOW")>=0) return 0;
      return -1;
   }

   bool CurrencyMatches(const string symbol,string event_ccy) const
   {
      StringToUpper(event_ccy);
      string base=StringSubstr(symbol,0,3);
      string quote=StringSubstr(symbol,StringLen(symbol)-3,3);
      StringToUpper(base);
      StringToUpper(quote);
      return (event_ccy=="ALL" || event_ccy==base || event_ccy==quote);
   }

public:
   CNewsCalendar(const string csv_path="calendar.csv",const int min_impact=2,
                 const int before_min=45,const int after_min=45,const bool fail_closed=false,
                 const string status_path="news_status.csv"):
      m_path(csv_path),m_status_path(status_path),m_min_impact(min_impact),
      m_before_min(before_min),m_after_min(after_min),m_fail_closed(fail_closed){}

   bool HealthOK(const datetime now_utc,const int max_age_sec,string &reason) const
   {
      int h=FileOpen(m_status_path,FILE_READ|FILE_CSV|FILE_ANSI);
      if(h==INVALID_HANDLE){reason="news_status_missing";return false;}

      for(int i=0;i<3 && !FileIsEnding(h);++i) FileReadString(h);
      string generated_s=FileReadString(h);
      string latest_s=FileReadString(h);
      string count_s=FileReadString(h);
      FileClose(h);

      datetime generated=(datetime)StringToInteger(generated_s);
      datetime latest=(datetime)StringToInteger(latest_s);
      int count=(int)StringToInteger(count_s);

      if(count<=0){reason="news_calendar_empty";return false;}
      if(generated<=0){reason="news_status_invalid";return false;}
      long age=(long)(now_utc-generated);
      if(age<0) age=-age;
      if(age>max_age_sec){reason="news_status_stale";return false;}
      if(latest<now_utc){reason="news_calendar_no_future_coverage";return false;}

      reason="ok";
      return true;
   }

   bool IsBlackout(const string symbol,const datetime now_utc) const
   {
      int h=FileOpen(m_path,FILE_READ|FILE_CSV|FILE_ANSI);
      if(h==INVALID_HANDLE) return m_fail_closed;

      for(int i=0;i<4 && !FileIsEnding(h);++i) FileReadString(h);
      bool blocked=false;
      while(!FileIsEnding(h))
      {
         string ts_s=FileReadString(h);
         string impact=FileReadString(h);
         string ccy=FileReadString(h);
         string title=FileReadString(h);
         if(ts_s=="" || impact=="" || ccy=="") continue;
         int level=ImpactLevel(impact);
         if(level<m_min_impact || !CurrencyMatches(symbol,ccy)) continue;
         datetime ts=(datetime)StringToInteger(ts_s);
         if(now_utc>=ts-m_before_min*60 && now_utc<=ts+m_after_min*60)
         { blocked=true; break; }
      }
      FileClose(h);
      return blocked;
   }
};
