#property strict

class CCVaRTracker
{
private:
   double m_r[];
   int    m_max;

public:
   CCVaRTracker(const int max_samples=500):m_max(MathMax(50,max_samples)){}

   void AddR(const double r)
   {
      int n=ArraySize(m_r);
      if(n<m_max){ ArrayResize(m_r,n+1); m_r[n]=r; return; }
      for(int i=1;i<n;++i) m_r[i-1]=m_r[i];
      m_r[n-1]=r;
   }

   int Samples() const { return ArraySize(m_r); }

   double CVaR95() const
   {
      int n=ArraySize(m_r);
      if(n<20) return 0.0;
      double losses[]; ArrayResize(losses,n);
      for(int i=0;i<n;++i) losses[i]=MathMax(0.0,-m_r[i]);
      ArraySort(losses);
      int start=(int)MathFloor(0.95*n);
      if(start>=n) start=n-1;
      double s=0.0; int k=0;
      for(int i=start;i<n;++i){ s+=losses[i]; ++k; }
      return (k>0 ? s/k : 0.0);
   }

   double SizeScaler(const double cvar_limit_r) const
   {
      double c=CVaR95();
      if(c<=0.0 || cvar_limit_r<=0.0) return 1.0;
      return MathMax(0.10,MathMin(1.0,cvar_limit_r/c));
   }
};
