#property strict

class CNDJSONLogger
{
private:
   string m_path;

   static string Esc(string s)
   {
      StringReplace(s,"\\","\\\\");
      StringReplace(s,"\"","\\\"");
      StringReplace(s,"\r","\\r");
      StringReplace(s,"\n","\\n");
      return s;
   }

   bool Append(const string line) const
   {
      int h=FileOpen(m_path,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
      if(h==INVALID_HANDLE) return false;
      FileSeek(h,0,SEEK_END);
      FileWriteString(h,line+"\r\n");
      FileFlush(h);
      FileClose(h);
      return true;
   }

public:
   CNDJSONLogger(const string path="FXSuite\\events.ndjson"):m_path(path){}

   bool Event(const string event_type,const string payload_json) const
   {
      string row=StringFormat("{\"ts\":%I64d,\"event\":\"%s\",%s}",
                              (long)TimeGMT(),Esc(event_type),payload_json);
      return Append(row);
   }

   bool TradeIntent(const string corr,const string symbol,const string side,
                    const double lots,const double p_eff,const double sl,const double tp) const
   {
      return Event("trade_intent",StringFormat(
         "\"corr_id\":\"%s\",\"symbol\":\"%s\",\"side\":\"%s\",\"lots\":%.8f,\"p_eff\":%.8f,\"sl\":%.10f,\"tp\":%.10f",
         Esc(corr),Esc(symbol),Esc(side),lots,p_eff,sl,tp));
   }

   bool BrokerAck(const string corr,const string symbol,const ulong retcode,
                  const ulong ticket,const double intended,const double fill,
                  const long latency_ms,const int attempt) const
   {
      return Event("broker_ack",StringFormat(
         "\"corr_id\":\"%s\",\"symbol\":\"%s\",\"retcode\":%I64u,\"ticket\":%I64u,\"intended_price\":%.10f,\"fill_price\":%.10f,\"latency_ms\":%d,\"attempt\":%d",
         Esc(corr),Esc(symbol),retcode,ticket,intended,fill,latency_ms,attempt));
   }

   bool SLChange(const string reason,const string symbol,const ulong ticket,
                 const double old_sl,const double new_sl,const double market_price,
                 const double tick_size,const double min_distance) const
   {
      return Event("sl_change",StringFormat(
         "\"reason\":\"%s\",\"symbol\":\"%s\",\"ticket\":%I64u,\"old_sl\":%.10f,\"new_sl\":%.10f,\"price\":%.10f,\"tick_snap\":%.10f,\"stops_freeze_margin\":%.10f",
         Esc(reason),Esc(symbol),ticket,old_sl,new_sl,market_price,tick_size,min_distance));
   }

   bool RiskState(const string state,const double day_dd,const double week_dd,
                  const double peak_dd,const double size_mult,const string reason) const
   {
      return Event("risk_state",StringFormat(
         "\"state\":\"%s\",\"day_dd\":%.8f,\"week_dd\":%.8f,\"peak_dd\":%.8f,\"size_mult\":%.8f,\"reason\":\"%s\"",
         Esc(state),day_dd,week_dd,peak_dd,size_mult,Esc(reason)));
   }

   bool HedgeState(const string primary,const string hedge,const double ratio,
                   const double primary_pnl,const double hedge_pnl,const double basis_pnl) const
   {
      return Event("hedge_state",StringFormat(
         "\"primary\":\"%s\",\"hedge\":\"%s\",\"ratio\":%.8f,\"primary_pnl\":%.8f,\"hedge_pnl\":%.8f,\"basis_pnl\":%.8f",
         Esc(primary),Esc(hedge),ratio,primary_pnl,hedge_pnl,basis_pnl));
   }

   bool Calibration(const string symbol,const string tf,const double ece,
                    const double brier,const double mce,const double width) const
   {
      return Event("calibration_metrics",StringFormat(
         "\"symbol\":\"%s\",\"tf\":\"%s\",\"ece\":%.8f,\"brier\":%.8f,\"mce\":%.8f,\"conformal_width\":%.8f",
         Esc(symbol),Esc(tf),ece,brier,mce,width));
   }
   bool NewsGuard(const string symbol,const bool blocked,const string reason,const double minutes_to_event) const
   {
      return Event("news_guard",StringFormat(
         "\"symbol\":\"%s\",\"blocked\":%s,\"reason\":\"%s\",\"minutes_to_event\":%.4f",
         Esc(symbol),blocked?"true":"false",Esc(reason),minutes_to_event));
   }

   bool RolloverGuard(const string symbol,const bool blocked,const datetime broker_time) const
   {
      return Event("rollover_guard",StringFormat(
         "\"symbol\":\"%s\",\"blocked\":%s,\"broker_time\":%I64d",
         Esc(symbol),blocked?"true":"false",(long)broker_time));
   }

   bool MTFVector(const string symbol,const double p_m15,const double p_h1,
                  const double p_h4,const double p_d1,const double blend,
                  const double coherence) const
   {
      return Event("mtf_vector",StringFormat(
         "\"symbol\":\"%s\",\"p_m15\":%.8f,\"p_h1\":%.8f,\"p_h4\":%.8f,\"p_d1\":%.8f,\"blend\":%.8f,\"coherence_score\":%.8f",
         Esc(symbol),p_m15,p_h1,p_h4,p_d1,blend,coherence));
   }

   bool ParityMetric(const string bucket,const double modeled,const double live_value,
                     const double error_pct) const
   {
      return Event("parity_metric",StringFormat(
         "\"bucket\":\"%s\",\"modeled\":%.8f,\"live\":%.8f,\"error_pct\":%.8f",
         Esc(bucket),modeled,live_value,error_pct));
   }

   bool CalibrationDecision(const string symbol,const double p_raw,const double p_cal,
                            const double width,const double max_width,const bool blocked) const
   {
      return Event("calibration_decision",StringFormat(
         "\"symbol\":\"%s\",\"p_raw\":%.8f,\"p_cal\":%.8f,\"conformal_width\":%.8f,\"max_width\":%.8f,\"blocked\":%s",
         Esc(symbol),p_raw,p_cal,width,max_width,blocked?"true":"false"));
   }

   bool TradeClose(const string symbol,const ulong deal,const ulong position_id,
                   const double price,const double volume,const double gross_profit,
                   const double commission,const double swap,const double net_pnl) const
   {
      return Event("trade_close",StringFormat(
         "\"symbol\":\"%s\",\"deal\":%I64u,\"position_id\":%I64u,\"price\":%.10f,\"volume\":%.8f,\"gross_profit\":%.8f,\"commission\":%.8f,\"swap\":%.8f,\"net_pnl\":%.8f",
         Esc(symbol),deal,position_id,price,volume,gross_profit,commission,swap,net_pnl));
   }
};
