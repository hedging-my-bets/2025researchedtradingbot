#property strict

class CCVaRTracker
{
private:
   double m_r[];
   int    m_max;

public:
   CCVaRTracker(const int max_samples=500):m_max(max_samples<50 ? 50 : max_samples){}

   void AddR(const double r)
   {
      if(!MathIsValidNumber(r)) return;
      int n=ArraySize(m_r);
      if(n<m_max)
      {
         ArrayResize(m_r,n+1);
         m_r[n]=r;
         return;
      }
      for(int i=1;i<n;++i) m_r[i-1]=m_r[i];
      m_r[n-1]=r;
   }

   bool Load(const string path)
   {
      int h=FileOpen(path,FILE_READ|FILE_CSV|FILE_ANSI);
      if(h==INVALID_HANDLE) return false;

      ArrayResize(m_r,0);
      if(!FileIsEnding(h)) FileReadString(h); // header

      while(!FileIsEnding(h))
      {
         string s=FileReadString(h);
         if(s=="") continue;
         double r=StringToDouble(s);
         AddR(r);
      }
      FileClose(h);
      return true;
   }

   bool Save(const string path) const
   {
      int h=FileOpen(path,FILE_WRITE|FILE_CSV|FILE_ANSI);
      if(h==INVALID_HANDLE) return false;

      FileWrite(h,"r");
      for(int i=0;i<ArraySize(m_r);++i)
         FileWrite(h,DoubleToString(m_r[i],8));

      FileFlush(h);
      FileClose(h);
      return true;
   }

   int Samples() const
   {
      return ArraySize(m_r);
   }

   double CVaR95() const
   {
      int n=ArraySize(m_r);
      if(n<20) return 0.0;

      double losses[];
      ArrayResize(losses,n);
      for(int i=0;i<n;++i)
         losses[i]=MathMax(0.0,-m_r[i]);

      ArraySort(losses);

      int start=(int)MathFloor(0.95*n);
      if(start>=n) start=n-1;

      double sum=0.0;
      int count=0;
      for(int i=start;i<n;++i)
      {
         sum+=losses[i];
         ++count;
      }

      return (count>0 ? sum/count : 0.0);
   }

   double SizeScaler(const double cvar_limit_r) const
   {
      double c=CVaR95();
      if(c<=0.0 || cvar_limit_r<=0.0) return 1.0;
      return MathMax(0.10,MathMin(1.0,cvar_limit_r/c));
   }
};
