// FXSuite/Filters/RegimeDetector.mqh
#property strict

enum ENUM_REGIME {
   REGIME_TREND_STRONG=0,
   REGIME_TREND_WEAK  =1,
   REGIME_RANGE_TIGHT =2,
   REGIME_RANGE_WIDE  =3,
   REGIME_BREAKOUT_PRE=4,
   REGIME_HIGH_VOL    =5
};

struct RegimeProfile {
   ENUM_REGIME regime;
   double      pwin_threshold_mult; // multiply your base p_win threshold
   double      lot_mult;            // multiply your base lot size
};

class CRegimeDetector {
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_tf;
   int              m_adx_h;
   int              m_atr_h;
   int              m_bb_h;

   // thresholds (sane defaults; override via setters if you want)
   double m_adx_strong;     // >= strong trend
   double m_adx_weak;       // >= weak trend
   double m_atr_hi_pct;     // ATR high percentile proxy
   double m_atr_lo_pct;     // ATR low percentile proxy
   double m_bb_tight;       // BB width / ATR tight
   double m_bb_wide;        // BB width / ATR wide

public:
   CRegimeDetector(const string symbol, const ENUM_TIMEFRAMES tf)
   : m_symbol(symbol), m_tf(tf),
     m_adx_h(INVALID_HANDLE), m_atr_h(INVALID_HANDLE), m_bb_h(INVALID_HANDLE),
     m_adx_strong(25.0), m_adx_weak(15.0),
     m_atr_hi_pct(1.40), m_atr_lo_pct(0.80),
     m_bb_tight(1.00), m_bb_wide(2.00)
   {}

   bool Init()
   {
      m_adx_h = iADX(m_symbol, m_tf, 14);
      m_atr_h = iATR(m_symbol, m_tf, 14);
      m_bb_h  = iBands(m_symbol, m_tf, 20, 0, 2.0, PRICE_CLOSE);
      return (m_adx_h!=INVALID_HANDLE && m_atr_h!=INVALID_HANDLE && m_bb_h!=INVALID_HANDLE);
   }

   // optional tuners
   void SetADXThresholds(const double weak, const double strong){ m_adx_weak=weak; m_adx_strong=strong; }
   void SetBBThresholds(const double tight, const double wide)  { m_bb_tight=tight; m_bb_wide=wide; }
   void SetATRRelativeBands(const double lo, const double hi)   { m_atr_lo_pct=lo; m_atr_hi_pct=hi; }

   bool Evaluate(RegimeProfile &out)
   {
      double adx[]; ArraySetAsSeries(adx,true);
      double atr[]; ArraySetAsSeries(atr,true);
      double bup[], bmd[], blw[]; ArraySetAsSeries(bup,true); ArraySetAsSeries(bmd,true); ArraySetAsSeries(blw,true);

      if(CopyBuffer(m_adx_h,0,1,3,adx)<=0) return false;       // DI+/DI- not needed, use ADX main line
      if(CopyBuffer(m_atr_h,0,1,2,atr)<=0) return false;
      if(CopyBuffer(m_bb_h,0,1,2,bup)<=0) return false;
      if(CopyBuffer(m_bb_h,1,1,2,bmd)<=0) return false;
      if(CopyBuffer(m_bb_h,2,1,2,blw)<=0) return false;

      const double adx_now = adx[0];
      const double atr_now = atr[0];

      double bbw = (bup[0]-blw[0]);
      double bbw_over_atr = (atr_now>0.0 ? bbw/atr_now : 0.0);

      // very light ATR "percentile proxy": compare to a 60-bar avg
      double atr60=0.0; int cnt=0;
      for(int i=1;i<=60;i++){ double v=iATR(m_symbol,m_tf,14,i); if(v>0){ atr60+=v; cnt++; } }
      if(cnt>0) atr60/=cnt; else atr60=atr_now;
      double atr_rel = (atr60>0.0 ? atr_now/atr60 : 1.0);

      // classify
      ENUM_REGIME tag = REGIME_RANGE_TIGHT;
      if(adx_now>=m_adx_strong && atr_rel>=m_atr_lo_pct)      tag=REGIME_TREND_STRONG;
      else if(adx_now>=m_adx_weak && atr_rel>=m_atr_lo_pct)   tag=REGIME_TREND_WEAK;
      else if(bbw_over_atr<=m_bb_tight)                       tag=REGIME_RANGE_TIGHT;
      else if(bbw_over_atr>=m_bb_wide && adx_now<m_adx_weak)  tag=REGIME_RANGE_WIDE;
      if(atr_rel>=m_atr_hi_pct)                               tag=REGIME_HIGH_VOL;
      if(bbw_over_atr<=m_bb_tight && adx_now>=m_adx_weak && adx_now<m_adx_strong)
         tag=REGIME_BREAKOUT_PRE;

      // multipliers (conservative defaults)
      double th_mult=1.00, lot_mult=1.00;
      switch(tag){
         case REGIME_TREND_STRONG: th_mult=0.95; lot_mult=1.20; break;
         case REGIME_TREND_WEAK:   th_mult=1.00; lot_mult=1.00; break;
         case REGIME_RANGE_TIGHT:  th_mult=1.05; lot_mult=0.80; break;
         case REGIME_RANGE_WIDE:   th_mult=1.02; lot_mult=0.90; break;
         case REGIME_BREAKOUT_PRE: th_mult=0.98; lot_mult=1.10; break;
         case REGIME_HIGH_VOL:     th_mult=1.05; lot_mult=0.75; break;
      }
      out.regime=tag; out.pwin_threshold_mult=th_mult; out.lot_mult=lot_mult;
      return true;
   }
};