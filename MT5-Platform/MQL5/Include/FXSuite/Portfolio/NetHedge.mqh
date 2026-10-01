#property strict

class CNetHedge
{
public:
   static double ClampRatio(const double raw,const double max_ratio)
   {
      return MathMax(-MathAbs(max_ratio),MathMin(MathAbs(max_ratio),raw));
   }

   static double HedgeRatioFromBeta(const double beta,const double corr,const double max_ratio)
   {
      if(!MathIsValidNumber(beta) || !MathIsValidNumber(corr)) return 0.0;
      // Signed correlation keeps hedge direction explicit.
      return ClampRatio(-beta*corr,max_ratio);
   }

   static double SnapVolume(const string symbol,const double raw_volume)
   {
      double minv=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      double maxv=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      if(step<=0.0 || MathAbs(raw_volume)<minv) return 0.0;
      double sign=(raw_volume>=0.0?1.0:-1.0);
      double v=MathMin(MathAbs(raw_volume),maxv);
      v=MathFloor((v+1e-12)/step)*step;
      return sign*v;
   }
};
