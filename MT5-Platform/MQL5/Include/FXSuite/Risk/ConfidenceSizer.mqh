#property strict

class CConfidenceSizer
{
public:
   static double Clamp(const double x,const double lo,const double hi)
   { return MathMax(lo,MathMin(hi,x)); }

   static double KellyRaw(const double p,const double rr)
   {
      if(rr<=0.0) return 0.0;
      double q=1.0-p;
      return (rr*p-q)/rr;
   }

   static double KellyEff(const double p_eff,const double rr,const double k_max)
   {
      double raw=KellyRaw(Clamp(p_eff,0.0,1.0),rr);
      return Clamp(raw*(p_eff-0.5)*2.0,0.0,k_max);
   }

   static double Multiplier(const double p_eff,const double rr,const double k_max)
   {
      if(k_max<=0.0) return 0.0;
      return Clamp(KellyEff(p_eff,rr,k_max)/k_max,0.0,1.0);
   }
};
