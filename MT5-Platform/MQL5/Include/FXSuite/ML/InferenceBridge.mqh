// FXSuite/ML/InferenceBridge.mqh
#property strict

class CInferenceBridge
{
private:
   string m_url;
   string m_model_id;
   string m_features_version;

   bool ParseJsonKV(const string json, const string key, string &out) const
   {
      int k = StringFind(json, "\""+key+"\"");
      if(k<0) return false;
      int c = StringFind(json, ":", k);
      if(c<0) return false;
      // detect quoted or numeric
      int q1 = StringFind(json, "\"", c);
      if(q1==c+1){ // quoted
         int q2 = StringFind(json, "\"", q1+1);
         if(q2<0) return false;
         out = StringSubstr(json, q1+1, q2-(q1+1));
         return true;
      } else {
         // numeric till comma or }
         int end = StringFind(json, ",", c+1);
         if(end<0) end = StringFind(json, "}", c+1);
         if(end<0) return false;
         out = StringTrim(StringSubstr(json, c+1, end-(c+1)));
         return true;
      }
   }

public:
   CInferenceBridge(): m_url(""), m_model_id(""), m_features_version("") {}
   void SetURL(const string url){ m_url=url; }
   string ModelId() const { return m_model_id; }
   string FeaturesVersion() const { return m_features_version; }

   bool Predict(const double &features[], const string corr_id, double &p_win, int &latency_ms)
   {
      if(m_url=="") return false;

      // Build minimal JSON payload
      string json = "{\"corr_id\":\""+corr_id+"\",\"features\":[";
      for(int i=0;i<64;i++){
         json += DoubleToString(features[i], 8);
         if(i<63) json += ",";
      }
      json += "]}";

      uchar body[]; StringToCharArray(json, body);
      uchar resp[]; string headers="";
      string req_headers = "Content-Type: application/json\r\n";

      int code = WebRequest("POST", m_url, req_headers, 5000, body, resp, headers);
      if(code<200 || code>=300) { Print("WebRequest failed, code=",code); return false; }

      string r = CharArrayToString(resp);
      // extract keys: p_win (numeric), latency_ms (numeric), model_id (string), features_version (string)
      string s_p, s_ms, s_mid, s_fv;
      if(ParseJsonKV(r,"p_win", s_p))    p_win = StringToDouble(s_p); else p_win=0.0;
      if(ParseJsonKV(r,"latency_ms",s_ms)) latency_ms = (int)StringToInteger(s_ms); else latency_ms=0;
      if(ParseJsonKV(r,"model_id", s_mid)) m_model_id=s_mid;
      if(ParseJsonKV(r,"features_version", s_fv)) m_features_version=s_fv;

      return (p_win>0.0 && p_win<1.0);
   }
};