// Production-ready HTTP bridge using WebRequest -> FastAPI inference server.
// Requires adding http://127.0.0.1:8081 to Terminal: Tools > Options > Expert Advisors > "Allow WebRequest for listed URL".
#property strict

class CInferenceBridge {
private:
   string m_url;
   string m_model_id;
   string m_features_version;
   int    m_timeout_ms;
public:
   CInferenceBridge(): m_url("http://127.0.0.1:8081/infer"), m_timeout_ms(900) {}

   void SetURL(const string url) { m_url = url; }
   void SetTimeout(const int ms) { m_timeout_ms = ms; }

   // Minimal JSON builder to avoid external libs
   string BuildJSON(const string corr_id, const double &features[])
   {
      string s="{\"correlation_id\":\""+corr_id+"\",\"features\":[";
      int n=ArraySize(features);
      for(int i=0;i<n;i++){
         s += DoubleToString(features[i], 10);
         if(i<n-1) s+=",";
      }
      s += "]}";
      return s;
   }

   bool Predict(const double &features[], const string corr_id, double &p_win_out, int &latency_ms_out)
   {
      char data[];
      string body = BuildJSON(corr_id, features);
      StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);

      char result[];
      string headers = "Content-Type: application/json\r\n";
      int status = 0;
      uint timeout = (uint)m_timeout_ms;

      int res = WebRequest("POST", m_url, NULL, timeout, data, ArraySize(data), result, headers, status);
      if(res==-1 || status!=200){
         PrintFormat("[InferenceBridge] WebRequest failed (res=%d, http=%d).", res, status);
         return false;
      }

      string j = CharArrayToString(result, 0, -1, CP_UTF8);
      // Simple value extraction (robust enough for our fixed schema)
      p_win_out = ExtractJsonNumber(j, "\"p_win\":");
      latency_ms_out = (int)ExtractJsonNumber(j, "\"latency_ms\":");
      m_model_id = ExtractJsonString(j, "\"model_id\":\"");
      m_features_version = ExtractJsonString(j, "\"features_version\":\"");
      return (p_win_out>=0.0 && p_win_out<=1.0);
   }

   string ModelId() const { return m_model_id; }
   string FeaturesVersion() const { return m_features_version; }

private:
   double ExtractJsonNumber(const string src, const string key)
   {
      int p = StringFind(src, key);
      if(p<0) return -1.0;
      int start = p + StringLen(key);
      int end = start;
      while(end<StringLen(src) && (StringGetCharacter(src, end)=='.' || (StringGetCharacter(src,end)>= '0' && StringGetCharacter(src,end)<='9') || StringGetCharacter(src,end)=='-')) end++;
      string num = StringSubstr(src, start, end-start);
      return StringToDouble(num);
   }

   string ExtractJsonString(const string src, const string key)
   {
      int p = StringFind(src, key);
      if(p<0) return "";
      int start = p + StringLen(key);
      int end = StringFind(src, "\"", start);
      if(end<0) return "";
      return StringSubstr(src, start, end-start);
   }
};