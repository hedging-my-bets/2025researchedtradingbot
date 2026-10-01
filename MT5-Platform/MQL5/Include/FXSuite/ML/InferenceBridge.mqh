#property strict

class CInferenceBridge
{
private:
   string m_url,m_model_id,m_features_version;
   double m_raw,m_cal,m_width;

   bool Value(const string json,const string key,string &out) const
   {
      int k=StringFind(json,"\""+key+"\""); if(k<0) return false;
      int c=StringFind(json,":",k); if(c<0) return false;
      int i=c+1;
      while(i<StringLen(json) && (StringGetCharacter(json,i)==32 || StringGetCharacter(json,i)==9)) ++i;
      if(i>=StringLen(json)) return false;
      if(StringGetCharacter(json,i)==34)
      {
         int q2=StringFind(json,"\"",i+1); if(q2<0) return false;
         out=StringSubstr(json,i+1,q2-i-1); return true;
      }
      int comma=StringFind(json,",",i), brace=StringFind(json,"}",i);
      int e=(comma<0?brace:(brace<0?comma:MathMin(comma,brace)));
      if(e<0) return false;
      out=StringSubstr(json,i,e-i); return true;
   }

public:
   CInferenceBridge():m_url(""),m_model_id(""),m_features_version(""),m_raw(0),m_cal(0),m_width(0){}
   void SetURL(const string url){m_url=url;}
   string ModelId() const{return m_model_id;}
   string FeaturesVersion() const{return m_features_version;}
   double RawP() const{return m_raw;}
   double CalibratedP() const{return m_cal;}
   double ConformalWidth() const{return m_width;}

   bool Predict(const double &features[],const string corr_id,double &p_eff,int &latency_ms,
                const string symbol="",const ENUM_TIMEFRAMES tf=PERIOD_CURRENT,const int features_ver=1)
   {
      if(m_url=="" || ArraySize(features)<64) return false;
      string json=StringFormat("{\"correlation_id\":\"%s\",\"symbol\":\"%s\",\"timeframe\":%d,\"client_features_version\":%d,\"features\":[",
                               corr_id,symbol,(int)tf,features_ver);
      for(int i=0;i<64;++i){json+=DoubleToString(features[i],10);if(i<63)json+=",";}
      json+="]}";

      char body[]; StringToCharArray(json,body,0,WHOLE_ARRAY,CP_UTF8);
      char resp[]; string headers="";
      string req_headers="Content-Type: application/json\r\n";
      int code=WebRequest("POST",m_url,req_headers,5000,body,resp,headers);
      if(code<200 || code>=300) return false;
      string r=CharArrayToString(resp,0,-1,CP_UTF8);

      string s;
      if(Value(r,"p_win",s)) m_raw=StringToDouble(s); else m_raw=0.0;
      if(Value(r,"p_cal",s)) m_cal=StringToDouble(s); else m_cal=m_raw;
      if(Value(r,"conformal_width",s)) m_width=StringToDouble(s); else m_width=0.0;
      if(Value(r,"latency_ms",s)) latency_ms=(int)StringToInteger(s); else latency_ms=0;
      if(Value(r,"model_id",s)) m_model_id=s;
      if(Value(r,"features_version",s)) m_features_version=s;
      p_eff=m_cal;
      return (p_eff>0.0 && p_eff<1.0);
   }
};
