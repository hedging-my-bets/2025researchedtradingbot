// FXSuite/ML/FeatureExtractor.mqh
#property strict

class CFeatureExtractor
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;

   int m_atr_h, m_bb_h, m_ma20_h, m_ma50_h, m_ma200_h, m_adx_h, m_rsi_h, m_cci_h, m_macd_h, m_sto_h;

   bool Copy1(const int handle, const int buff, double &out) const
   {
      double tmp[]; ArraySetAsSeries(tmp,true);
      if(CopyBuffer(handle, buff, 1, 1, tmp)<=0) return false;
      out = tmp[0]; return true;
   }

   bool CopyCloseN(const string sym, const ENUM_TIMEFRAMES tf, const int n, double &c0, double &c1, double &c5, double &c20) const
   {
      double cl[]; ArraySetAsSeries(cl,true);
      if(CopyClose(sym, tf, 0, MathMax(21,n+1), cl)<=0) return false;
      c0 = cl[0];
      c1 = (ArraySize(cl)>1 ? cl[1] : c0);
      c5 = (ArraySize(cl)>5 ? cl[5] : c1);
      c20= (ArraySize(cl)>20? cl[20]: c5);
      return true;
   }

public:
   CFeatureExtractor(const string sym, const ENUM_TIMEFRAMES tf)
   : m_symbol(sym), m_tf(tf),
     m_atr_h(INVALID_HANDLE), m_bb_h(INVALID_HANDLE), m_ma20_h(INVALID_HANDLE),
     m_ma50_h(INVALID_HANDLE), m_ma200_h(INVALID_HANDLE),
     m_adx_h(INVALID_HANDLE), m_rsi_h(INVALID_HANDLE), m_cci_h(INVALID_HANDLE),
     m_macd_h(INVALID_HANDLE), m_sto_h(INVALID_HANDLE)
   {}

   bool Init()
   {
      m_atr_h   = iATR(m_symbol, m_tf, 14);
      m_bb_h    = iBands(m_symbol, m_tf, 20, 0, 2.0, PRICE_CLOSE);
      m_ma20_h  = iMA(m_symbol, m_tf, 20, 0, MODE_EMA, PRICE_CLOSE);
      m_ma50_h  = iMA(m_symbol, m_tf, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_ma200_h = iMA(m_symbol, m_tf, 200,0, MODE_EMA, PRICE_CLOSE);
      m_adx_h   = iADX(m_symbol, m_tf, 14);
      m_rsi_h   = iRSI(m_symbol, m_tf, 14, PRICE_CLOSE);
      m_cci_h   = iCCI(m_symbol, m_tf, 14, PRICE_TYPICAL);
      m_macd_h  = iMACD(m_symbol, m_tf, 12,26,9, PRICE_CLOSE);
      m_sto_h   = iStochastic(m_symbol, m_tf, 5,3,3, MODE_SMA);

      return (m_atr_h!=INVALID_HANDLE && m_bb_h!=INVALID_HANDLE && m_ma20_h!=INVALID_HANDLE &&
              m_ma50_h!=INVALID_HANDLE && m_ma200_h!=INVALID_HANDLE && m_adx_h!=INVALID_HANDLE &&
              m_rsi_h!=INVALID_HANDLE && m_cci_h!=INVALID_HANDLE && m_macd_h!=INVALID_HANDLE &&
              m_sto_h!=INVALID_HANDLE);
   }

   // intent_* flags can be 0/1 if you want to hint the model; currently just included as features
   bool Build(double &f[], const int intent_breakout, const int intent_trend, const int intent_squeeze) const
   {
      ArrayInitialize(f,0.0);

      // Prices & returns
      double c0,c1,c5,c20;
      if(!CopyCloseN(m_symbol,m_tf,20,c0,c1,c5,c20)) return false;
      f[0] = (c0>0.0 && c1>0.0 ? (c0/c1 - 1.0) : 0.0);  // ret_1
      f[1] = (c0>0.0 && c5>0.0 ? (c0/c5 - 1.0) : 0.0);  // ret_5
      f[2] = (c0>0.0 && c20>0.0? (c0/c20- 1.0) : 0.0);  // ret_20

      // ATR & BB
      double atr=0.0; if(!Copy1(m_atr_h,0,atr)) atr=0.0;
      double bup=0.0,bmd=0.0,blw=0.0;
      if(!Copy1(m_bb_h,0,bup)) bup=0.0;
      if(!Copy1(m_bb_h,1,bmd)) bmd=0.0;
      if(!Copy1(m_bb_h,2,blw)) blw=0.0;

      double bbw = MathMax(0.0, bup-blw);
      f[2]  = atr;                 // overwrite: raw ATR
      f[3]  = (atr>0.0 ? bbw/atr : 0.0); // BB width over ATR
      f[4]  = bbw;                 // raw BB width

      // EMAs & trend
      double ma20=0.0,ma50=0.0,ma200=0.0;
      Copy1(m_ma20_h,0,ma20); Copy1(m_ma50_h,0,ma50); Copy1(m_ma200_h,0,ma200);
      f[5]  = (ma50>ma200 ? 1.0 : (ma50<ma200 ? -1.0 : 0.0));  // regime via EMA
      f[6]  = 0.0; double adx=0.0; if(Copy1(m_adx_h,0,adx)) f[6]=adx;
      f[7]  = 0.0; double rsi=0.0; if(Copy1(m_rsi_h,0,rsi)) f[7]=rsi;
      f[8]  = 0.0; double cci=0.0; if(Copy1(m_cci_h,0,cci)) f[8]=cci;

      // MACD main/signal/hist
      double macd_main=0.0, macd_sig=0.0, macd_hist=0.0;
      double m0[]; ArraySetAsSeries(m0,true);
      if(CopyBuffer(m_macd_h,0,1,1,m0)>0) macd_main=m0[0];
      if(CopyBuffer(m_macd_h,1,1,1,m0)>0) macd_sig =m0[0];
      if(CopyBuffer(m_macd_h,2,1,1,m0)>0) macd_hist=m0[0];
      f[9]=macd_main; f[10]=macd_sig; f[11]=macd_hist;

      // Stochastic %K / %D
      double sto_k=0.0, sto_d=0.0;
      double sbuf[]; ArraySetAsSeries(sbuf,true);
      if(CopyBuffer(m_sto_h,0,1,1,sbuf)>0) sto_k=sbuf[0];
      if(CopyBuffer(m_sto_h,1,1,1,sbuf)>0) sto_d=sbuf[0];
      f[12]=sto_k; f[13]=sto_d;

      // Spread & tick proxies
      double spread_pts = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      double point      = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      f[14] = (spread_pts>0 ? spread_pts*point : 0.0);

      // Session/time features
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      f[15] = (double)dt.hour;       // hour
      f[16] = (double)dt.day_of_week;// dow
      // very light session id: 0=Asia,1=London,2=NY
      int sess = (dt.hour<7 ? 0 : (dt.hour<13 ? 1 : 2));
      f[17] = (double)sess;

      // Price vs bands/sma
      f[18] = (bup>blw && c0>0.0 ? (c0 - bmd) / (MathMax(1e-8, (bup-blw)*0.5)) : 0.0); // z inside bands
      f[19] = (ma20>0.0 ? (c0/ma20 - 1.0) : 0.0);

      // Intent flags
      f[20] = (double)intent_breakout;
      f[21] = 9999.0;            // minutes_to_high_NEWS (will be overwritten by EA)
      f[22] = (double)intent_trend;
      f[23] = (double)intent_squeeze;

      // Vol proxy: ATR vs 60-bar mean
      double atr60buf[]; ArraySetAsSeries(atr60buf,true);
      if(CopyBuffer(m_atr_h,0,1,60,atr60buf)>0){
         double s=0.0; int n=0;
         for(int i=0;i<ArraySize(atr60buf);++i){ if(atr60buf[i]>0.0){ s+=atr60buf[i]; ++n; } }
         double mean = (n>0 ? s/n : atr);
         f[24] = (mean>0.0 ? atr/mean : 1.0); // ATR relative
      } else f[24]=1.0;

      // Fill remaining indices with zeros if needed
      for(int i=25;i<64;i++) f[i]=0.0;

      return true;
   }
};