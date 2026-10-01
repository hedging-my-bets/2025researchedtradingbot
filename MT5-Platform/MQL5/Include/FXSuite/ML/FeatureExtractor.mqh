#property strict

class CFeatureExtractor
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int m_features_ver;
   int m_atr_h,m_bb_h,m_ma20_h,m_ma50_h,m_ma200_h,m_adx_h,m_rsi_h,m_cci_h,m_macd_h,m_sto_h;

   bool Copy1(const int handle,const int buffer,double &out) const
   {
      double x[]; ArraySetAsSeries(x,true);
      if(CopyBuffer(handle,buffer,1,1,x)<=0) return false;
      out=x[0]; return true;
   }

public:
   CFeatureExtractor(const string symbol,const ENUM_TIMEFRAMES tf,const int features_ver=1):
      m_symbol(symbol),m_tf(tf),m_features_ver(features_ver),
      m_atr_h(INVALID_HANDLE),m_bb_h(INVALID_HANDLE),m_ma20_h(INVALID_HANDLE),
      m_ma50_h(INVALID_HANDLE),m_ma200_h(INVALID_HANDLE),m_adx_h(INVALID_HANDLE),
      m_rsi_h(INVALID_HANDLE),m_cci_h(INVALID_HANDLE),m_macd_h(INVALID_HANDLE),m_sto_h(INVALID_HANDLE){}

   ~CFeatureExtractor()
   {
      if(m_atr_h!=INVALID_HANDLE)   IndicatorRelease(m_atr_h);
      if(m_bb_h!=INVALID_HANDLE)    IndicatorRelease(m_bb_h);
      if(m_ma20_h!=INVALID_HANDLE)  IndicatorRelease(m_ma20_h);
      if(m_ma50_h!=INVALID_HANDLE)  IndicatorRelease(m_ma50_h);
      if(m_ma200_h!=INVALID_HANDLE) IndicatorRelease(m_ma200_h);
      if(m_adx_h!=INVALID_HANDLE)   IndicatorRelease(m_adx_h);
      if(m_rsi_h!=INVALID_HANDLE)   IndicatorRelease(m_rsi_h);
      if(m_cci_h!=INVALID_HANDLE)   IndicatorRelease(m_cci_h);
      if(m_macd_h!=INVALID_HANDLE)  IndicatorRelease(m_macd_h);
      if(m_sto_h!=INVALID_HANDLE)   IndicatorRelease(m_sto_h);
   }

   bool Init()
   {
      m_atr_h=iATR(m_symbol,m_tf,14);
      m_bb_h=iBands(m_symbol,m_tf,20,0,2.0,PRICE_CLOSE);
      m_ma20_h=iMA(m_symbol,m_tf,20,0,MODE_EMA,PRICE_CLOSE);
      m_ma50_h=iMA(m_symbol,m_tf,50,0,MODE_EMA,PRICE_CLOSE);
      m_ma200_h=iMA(m_symbol,m_tf,200,0,MODE_EMA,PRICE_CLOSE);
      m_adx_h=iADX(m_symbol,m_tf,14);
      m_rsi_h=iRSI(m_symbol,m_tf,14,PRICE_CLOSE);
      m_cci_h=iCCI(m_symbol,m_tf,14,PRICE_TYPICAL);
      m_macd_h=iMACD(m_symbol,m_tf,12,26,9,PRICE_CLOSE);
      m_sto_h=iStochastic(m_symbol,m_tf,5,3,3,MODE_SMA,STO_LOWHIGH);
      return (m_atr_h!=INVALID_HANDLE && m_bb_h!=INVALID_HANDLE && m_ma20_h!=INVALID_HANDLE &&
              m_ma50_h!=INVALID_HANDLE && m_ma200_h!=INVALID_HANDLE && m_adx_h!=INVALID_HANDLE &&
              m_rsi_h!=INVALID_HANDLE && m_cci_h!=INVALID_HANDLE && m_macd_h!=INVALID_HANDLE &&
              m_sto_h!=INVALID_HANDLE);
   }

   int Version() const { return m_features_ver; }

   bool Build(double &f[],const int intent_breakout,const int intent_trend,const int intent_squeeze) const
   {
      if(ArraySize(f)<64) return false;
      ArrayInitialize(f,0.0);
      double close[]; ArraySetAsSeries(close,true);
      if(CopyClose(m_symbol,m_tf,0,21,close)<21) return false;
      double c0=close[0],c1=close[1],c5=close[5],c20=close[20];
      double ret1=(c1>0?c0/c1-1.0:0.0),ret5=(c5>0?c0/c5-1.0:0.0),ret20=(c20>0?c0/c20-1.0:0.0);

      double atr=0,base=0,upper=0,lower=0;
      Copy1(m_atr_h,0,atr); Copy1(m_bb_h,0,base); Copy1(m_bb_h,1,upper); Copy1(m_bb_h,2,lower);
      double bbw=MathMax(0.0,upper-lower);

      // LEGACY_BEHAVIOR keeps v1 index contract; v2 restores ret_20 explicitly.
      if(m_features_ver<=1)
      { f[0]=ret1; f[1]=ret5; f[2]=atr; f[3]=(atr>0?bbw/atr:0.0); f[4]=bbw; }
      else
      { f[0]=ret1; f[1]=ret5; f[2]=ret20; f[3]=atr; f[4]=(atr>0?bbw/atr:0.0); f[5]=bbw; }

      int shift=(m_features_ver<=1 ? 0 : 1);
      double ma20=0,ma50=0,ma200=0,adx=0,rsi=0,cci=0;
      Copy1(m_ma20_h,0,ma20); Copy1(m_ma50_h,0,ma50); Copy1(m_ma200_h,0,ma200);
      Copy1(m_adx_h,0,adx); Copy1(m_rsi_h,0,rsi); Copy1(m_cci_h,0,cci);
      f[5+shift]=(ma50>ma200?1.0:(ma50<ma200?-1.0:0.0));
      f[6+shift]=adx; f[7+shift]=rsi; f[8+shift]=cci;

      double macd_main=0,macd_signal=0;
      Copy1(m_macd_h,0,macd_main); Copy1(m_macd_h,1,macd_signal);
      f[9+shift]=macd_main; f[10+shift]=macd_signal; f[11+shift]=macd_main-macd_signal;

      double k=0,d=0; Copy1(m_sto_h,0,k); Copy1(m_sto_h,1,d);
      f[12+shift]=k; f[13+shift]=d;

      double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      f[14+shift]=(double)SymbolInfoInteger(m_symbol,SYMBOL_SPREAD)*point;
      MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
      f[15+shift]=(double)dt.hour; f[16+shift]=(double)dt.day_of_week;
      f[17+shift]=(dt.hour<7?0.0:(dt.hour<13?1.0:2.0));
      f[18+shift]=(upper>lower?(c0-base)/MathMax(1e-8,(upper-lower)*0.5):0.0);
      f[19+shift]=(ma20>0?c0/ma20-1.0:0.0);
      f[20+shift]=(double)intent_breakout;
      f[21+shift]=9999.0;
      f[22+shift]=(double)intent_trend;
      f[23+shift]=(double)intent_squeeze;

      double atrs[]; ArraySetAsSeries(atrs,true);
      double mean=atr; int n=0;
      if(CopyBuffer(m_atr_h,0,1,60,atrs)>0)
      {
         mean=0.0;
         for(int i=0;i<ArraySize(atrs);++i) if(atrs[i]>0){mean+=atrs[i];++n;}
         mean=(n>0?mean/n:atr);
      }
      f[24+shift]=(mean>0?atr/mean:1.0);
      return true;
   }
};
