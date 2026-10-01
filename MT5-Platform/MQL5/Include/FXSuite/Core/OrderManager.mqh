#property strict
#include <Trade/Trade.mqh>
#include <FXSuite/Telemetry/NDJSONLogger.mqh>

struct OrderRecord
{
   ulong    ticket;
   ulong    deal;
   ulong    retcode;
   double   intended_price;
   double   fill_price;
   double   sl;
   double   tp;
   datetime time;
   long     latency_ms;
   int      attempts;
   string   corr_id;
};

class COrderManager
{
private:
   CTrade         m_trade;
   CNDJSONLogger  m_log;
   int            m_max_retries;
   int            m_backoff_ms;
   int            m_deviation_points;
   string         m_ids[];
   ulong          m_tickets[];

   bool Seen(const string corr_id,ulong &ticket) const
   {
      for(int i=0;i<ArraySize(m_ids);++i)
      {
         if(m_ids[i]==corr_id){ ticket=m_tickets[i]; return true; }
      }
      return false;
   }

   void Remember(const string corr_id,const ulong ticket)
   {
      int n=ArraySize(m_ids);
      ArrayResize(m_ids,n+1);
      ArrayResize(m_tickets,n+1);
      m_ids[n]=corr_id;
      m_tickets[n]=ticket;
   }

   static bool SuccessCode(const ulong rc)
   {
      return (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL ||
              rc==TRADE_RETCODE_PLACED || rc==TRADE_RETCODE_NO_CHANGES);
   }

   static bool RetryableCode(const ulong rc)
   {
      return (rc==TRADE_RETCODE_REQUOTE || rc==TRADE_RETCODE_PRICE_CHANGED ||
              rc==TRADE_RETCODE_PRICE_OFF || rc==TRADE_RETCODE_TIMEOUT ||
              rc==TRADE_RETCODE_CONNECTION || rc==TRADE_RETCODE_TOO_MANY_REQUESTS ||
              rc==TRADE_RETCODE_LOCKED);
   }

public:
   COrderManager():m_log("FXSuite\\events.ndjson"),
                   m_max_retries(2),m_backoff_ms(75),m_deviation_points(15)
   {
      m_trade.SetAsyncMode(false);
   }

   void ConfigureRetry(const int max_retries,const int base_backoff_ms,const int deviation_points)
   {
      m_max_retries=MathMax(0,max_retries);
      m_backoff_ms=MathMax(1,base_backoff_ms);
      m_deviation_points=MathMax(0,deviation_points);
   }

   bool NormalizeVolumeDown(const string symbol,double &lots) const
   {
      double minv=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      double maxv=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      if(step<=0.0) return false;
      if(lots<minv) return false; // never increase risk to reach broker minimum
      lots=MathMin(lots,maxv);
      lots=MathFloor((lots+1e-12)/step)*step;
      int digits=0;
      if(step<1.0) digits=(int)MathCeil(-MathLog10(step));
      lots=NormalizeDouble(lots,digits);
      return (lots>=minv && lots<=maxv);
   }

   bool SendWithRetry(const string symbol,const ENUM_ORDER_TYPE side,double lots,
                      const double sl,const double tp,const string corr_id,OrderRecord &out)
   {
      ZeroMemory(out);
      ulong prior=0;
      if(Seen(corr_id,prior))
      {
         out.ticket=prior; out.corr_id=corr_id; out.retcode=TRADE_RETCODE_DONE;
         return true;
      }

      if(!SymbolInfoInteger(symbol,SYMBOL_TRADING_ALLOWED)) return false;
      if(!NormalizeVolumeDown(symbol,lots)) return false;

      m_trade.SetDeviationInPoints(m_deviation_points);
      int max_attempts=m_max_retries+1;

      for(int attempt=1;attempt<=max_attempts;++attempt)
      {
         MqlTick tick;
         if(!SymbolInfoTick(symbol,tick)) return false;
         double intended=(side==ORDER_TYPE_BUY ? tick.ask : tick.bid);
         ulong t0=GetTickCount64();

         bool call_ok=false;
         if(side==ORDER_TYPE_BUY)  call_ok=m_trade.Buy(lots,symbol,0.0,sl,tp,corr_id);
         if(side==ORDER_TYPE_SELL) call_ok=m_trade.Sell(lots,symbol,0.0,sl,tp,corr_id);

         ulong rc=m_trade.ResultRetcode();
         long latency=(long)(GetTickCount64()-t0);
         ulong ticket=m_trade.ResultOrder();
         ulong deal=m_trade.ResultDeal();
         double fill=m_trade.ResultPrice();

         m_log.BrokerAck(corr_id,symbol,rc,ticket,intended,fill,latency,attempt);

         out.ticket=ticket;
         out.deal=deal;
         out.retcode=rc;
         out.intended_price=intended;
         out.fill_price=fill;
         out.sl=sl;
         out.tp=tp;
         out.time=TimeCurrent();
         out.latency_ms=latency;
         out.attempts=attempt;
         out.corr_id=corr_id;

         if(call_ok && SuccessCode(rc))
         {
            Remember(corr_id,ticket);
            return true;
         }
         if(!RetryableCode(rc) || attempt>=max_attempts) return false;
         Sleep(m_backoff_ms*(1<<(attempt-1)));
      }
      return false;
   }

   bool SendMarket(const string symbol,const ENUM_ORDER_TYPE side,double lots,
                   const double sl,const double tp,const string corr_id,OrderRecord &out)
   {
      return SendWithRetry(symbol,side,lots,sl,tp,corr_id,out);
   }

   bool ModifyPositionStops(const ulong position_ticket,const string symbol,
                            const double new_sl,const double tp,ulong &retcode)
   {
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action=TRADE_ACTION_SLTP;
      req.position=position_ticket;
      req.symbol=symbol;
      req.sl=new_sl;
      req.tp=tp;
      bool ok=OrderSend(req,res);
      retcode=res.retcode;
      return (ok && SuccessCode(res.retcode));
   }
};
