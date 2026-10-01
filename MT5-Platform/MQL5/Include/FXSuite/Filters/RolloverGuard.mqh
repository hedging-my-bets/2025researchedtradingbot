#property strict

class CRolloverGuard
{
private:
   int m_start_hour;
   int m_start_minute;
   int m_end_hour;
   int m_end_minute;

   static int MinuteOfDay(const datetime t)
   {
      MqlDateTime d; TimeToStruct(t,d);
      return d.hour*60+d.min;
   }

public:
   CRolloverGuard(const int start_hour=21,const int start_minute=55,
                  const int end_hour=22,const int end_minute=10):
      m_start_hour(start_hour),m_start_minute(start_minute),
      m_end_hour(end_hour),m_end_minute(end_minute){}

   bool IsGuarded(const datetime broker_time) const
   {
      int now=MinuteOfDay(broker_time);
      int start=m_start_hour*60+m_start_minute;
      int end=m_end_hour*60+m_end_minute;
      if(start<=end) return (now>=start && now<=end);
      return (now>=start || now<=end);
   }
};
