#property strict

enum ENUM_REGIME
{
   REGIME_TREND_STRONG=0,
   REGIME_TREND_WEAK=1,
   REGIME_RANGE_TIGHT=2,
   REGIME_RANGE_WIDE=3,
   REGIME_BREAKOUT_PRE=4,
   REGIME_HIGH_VOL=5
};

struct RegimeProfile
{
   ENUM_REGIME regime;
   double pwin_threshold_mult;
   double lot_mult;
};

class CRegimeDetector
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int m_adx_h,m_atr_h,m_bb_h;
   double m_adx_strong,m_adx_weak,m_atr_hi_pct,m_atr_lo_pct,m_bb_tight,m_bb_wide;

public:
   CRegimeDetector(const string symbol,const ENUM_TIMEFRAMES tf):
      m_symbol(symbol),m_tf(tf),m_adx_h(INVALID_HANDLE),m_atr_h(INVALID_HANDLE),m_bb_h(INVALID_HANDLE),
      m_adx_strong(25.0),m_adx_weak(15.0),m_atr_hi_pct(1.40),m_atr_lo_pct(0.80),
      m_bb_tight(1.00),m_bb_wide(2.00){}

   bool Init()
   {
      m_adx_h=iADX(m_symbol,m_tf,14);
      m_atr_h=iATR(m_symbol,m_tf,14);
      m_bb_h=iBands(m_symbol,m_tf,20,0,2.0,PRICE_CLOSE);
      return (m_adx_h!=INVALID_HANDLE && m_atr_h!=INVALID_HANDLE && m_bb_h!=INVALID_HANDLE);
   }

   void SetADXThresholds(const double weak,const double strong){m_adx_weak=weak;m_adx_strong=strong;}
   void SetBBThresholds(const double tight,const double wide){m_bb_tight=tight;m_bb_wide=wide;}
   void SetATRRelativeBands(const double lo,const double hi){m_atr_lo_pct=lo;m_atr_hi_pct=hi;}

   bool Evaluate(RegimeProfile &out)
   {
      double adx[],atr[],base[],upper[],lower[];
      ArraySetAsSeries(adx,true); ArraySetAsSeries(atr,true);
      ArraySetAsSeries(base,true); ArraySetAsSeries(upper,true); ArraySetAsSeries(lower,true);
      if(CopyBuffer(m_adx_h,0,1,1,adx)<=0) return false;
      if(CopyBuffer(m_atr_h,0,1,60,atr)<=0) return false;
      if(CopyBuffer(m_bb_h,0,1,1,base)<=0) return false;
      if(CopyBuffer(m_bb_h,1,1,1,upper)<=0) return false;
      if(CopyBuffer(m_bb_h,2,1,1,lower)<=0) return false;

      double atr_now=atr[0], atr_mean=0.0; int n=0;
      for(int i=0;i<ArraySize(atr);++i) if(atr[i]>0.0){atr_mean+=atr[i];++n;}
      atr_mean=(n>0?atr_mean/n:atr_now);
      double atr_rel=(atr_mean>0.0?atr_now/atr_mean:1.0);
      double bbw=MathMax(0.0,upper[0]-lower[0]);
      double bbw_atr=(atr_now>0.0?bbw/atr_now:0.0);
      double adx_now=adx[0];

      ENUM_REGIME tag=REGIME_RANGE_TIGHT;
      if(adx_now>=m_adx_strong && atr_rel>=m_atr_lo_pct) tag=REGIME_TREND_STRONG;
      else if(adx_now>=m_adx_weak && atr_rel>=m_atr_lo_pct) tag=REGIME_TREND_WEAK;
      else if(bbw_atr<=m_bb_tight) tag=REGIME_RANGE_TIGHT;
      else if(bbw_atr>=m_bb_wide && adx_now<m_adx_weak) tag=REGIME_RANGE_WIDE;
      if(atr_rel>=m_atr_hi_pct) tag=REGIME_HIGH_VOL;
      if(bbw_atr<=m_bb_tight && adx_now>=m_adx_weak && adx_now<m_adx_strong) tag=REGIME_BREAKOUT_PRE;

      double th=1.0,lm=1.0;
      switch(tag)
      {
         case REGIME_TREND_STRONG: th=0.95; lm=1.20; break;
         case REGIME_TREND_WEAK: th=1.00; lm=1.00; break;
         case REGIME_RANGE_TIGHT: th=1.05; lm=0.80; break;
         case REGIME_RANGE_WIDE: th=1.02; lm=0.90; break;
         case REGIME_BREAKOUT_PRE: th=0.98; lm=1.10; break;
         case REGIME_HIGH_VOL: th=1.05; lm=0.75; break;
      }
      out.regime=tag; out.pwin_threshold_mult=th; out.lot_mult=lm;
      return true;
   }
};
