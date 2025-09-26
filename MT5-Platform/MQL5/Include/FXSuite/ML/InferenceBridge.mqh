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
      uchar data[];
      string body = BuildJSON(corr_id, features);
      StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);

      uchar result[];
      string resp_headers="";

      // 9-param overload: method, url, cookie, headers, timeout, post[], post_size, result[], resp_headers
      int bytes = WebRequest("POST", m_url, "", "Content-Type: application/json\r\n",
                             m_timeout_ms, data, ArraySize(data), result, resp_headers);
      if(bytes < 0){
         PrintFormat("[InferenceBridge] WebRequest failed. err=%d", GetLastError());
         return false;
      }
      if(StringFind(resp_headers, " 200") < 0 && StringFind(resp_headers, " 201") < 0){
         Print("[InferenceBridge] Non-200 response: ", resp_headers);
         return false;
      }

      string j = CharArrayToString(result, 0, -1, CP_UTF8);
      p_win_out          = ExtractJsonNumber(j, "\"p_win\":");
      latency_ms_out     = (int)ExtractJsonNumber(j, "\"latency_ms\":");
      m_model_id         = ExtractJsonString(j, "\"model_id\":\"");
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
      int start = p + StringLen(key), end = start;
      while(end<StringLen(src)){
         int ch = StringGetCharacter(src,end);
         if((ch>='0' && ch<='9') || ch=='.' || ch=='-' || ch=='e' || ch=='E') end++;
         else break;
      }
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
