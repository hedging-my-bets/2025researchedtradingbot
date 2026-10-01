#property strict

class CDynamicSizer
{
public:
   static double Combine(const double confidence_mult,const double cvar_mult,
                         const double drawdown_mult,const double spread_mult)
   {
      return MathMax(0.0,MathMin(1.0,
             MathMin(MathMin(confidence_mult,cvar_mult),MathMin(drawdown_mult,spread_mult))));
   }
};
