#property strict
#include <FXSuite/Core/OrderManager.mqh>
#include <FXSuite/Telemetry/NDJSONLogger.mqh>

struct FXSProfitState
{
   ulong  ticket;
   double initial_risk_distance;
   bool   be_done;
};

class CProfitProtector
{
private:
   COrderManager  *m_om;
   CNDJSONLogger   m_log;
   double          m_be_pct_equity;
   double          m_be_r;
   double          m_be_offset_pips;
   bool            m_use_or;
   bool            m_atr_enabled;
   double          m_trail_start_r;
   double          m_trail_atr_mult;
   ENUM_TIMEFRAMES m_tf;
   FXSProfitState  m_states[];

   static double PipSize(const string symbol)
   {
      double p=SymbolInfoDouble(symbol,SYMBOL_POINT);
      int d=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      return ((d==3 || d==5) ? p*10.0 : p);
   }

   static double SnapForSide(const string symbol,const double price,const ENUM_POSITION_TYPE side)
   {
      double tick=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tick<=0.0) return price;
      if(side==POSITION_TYPE_BUY) return MathFloor(price/tick)*tick;
      return MathCeil(price/tick)*tick;
   }

   int StateIndex(const ulong ticket,const double entry,const double sl)
   {
      for(int i=0;i<ArraySize(m_states);++i) if(m_states[i].ticket==ticket) return i;
      int n=ArraySize(m_states); ArrayResize(m_states,n+1);
      m_states[n].ticket=ticket;
      m_states[n].initial_risk_distance=(sl>0.0 ? MathAbs(entry-sl) : 0.0);
      m_states[n].be_done=false;
      return n;
   }

   bool BrokerSafeSL(const string symbol,const ENUM_POSITION_TYPE side,const double candidate,
                     const MqlTick &tick,double &snapped,double &min_distance) const
   {
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      long stops=SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
      long freeze=SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      min_distance=MathMax((double)stops,(double)freeze)*point+tick_size;
      snapped=SnapForSide(symbol,candidate,side);
      if(side==POSITION_TYPE_BUY)  return (snapped<=tick.bid-min_distance);
      if(side==POSITION_TYPE_SELL) return (snapped>=tick.ask+min_distance);
      return false;
   }

   bool ImproveOnly(const ENUM_POSITION_TYPE side,const double old_sl,const double new_sl,const double tick_size) const
   {
      if(old_sl<=0.0) return true;
      if(side==POSITION_TYPE_BUY)  return (new_sl>old_sl+tick_size*0.5);
      if(side==POSITION_TYPE_SELL) return (new_sl<old_sl-tick_size*0.5);
      return false;
   }

   double ATR(const string symbol) const
   {
      int h=iATR(symbol,m_tf,14);
      if(h==INVALID_HANDLE) return 0.0;
      double b[]; ArraySetAsSeries(b,true);
      double out=(CopyBuffer(h,0,1,1,b)>0 ? b[0] : 0.0);
      IndicatorRelease(h);
      return out;
   }

public:
   CProfitProtector(COrderManager *om):
      m_om(om),m_log("FXSuite\\events.ndjson"),
      m_be_pct_equity(0.0),m_be_r(0.0),m_be_offset_pips(0.2),m_use_or(true),
      m_atr_enabled(false),m_trail_start_r(1.5),m_trail_atr_mult(2.0),m_tf(PERIOD_M15){}

   void ConfigureBE(const double pct_equity,const double trigger_r,const double offset_pips,const bool use_or)
   {
      m_be_pct_equity=MathMax(0.0,pct_equity);
      m_be_r=MathMax(0.0,trigger_r);
      m_be_offset_pips=MathMax(0.0,offset_pips);
      m_use_or=use_or;
   }

   void ConfigureATR(const bool enabled,const ENUM_TIMEFRAMES tf,const double start_r,const double atr_mult)
   {
      m_atr_enabled=enabled; m_tf=tf;
      m_trail_start_r=MathMax(0.0,start_r); m_trail_atr_mult=MathMax(0.1,atr_mult);
   }

   void UpdateForSymbol(const string symbol)
   {
      MqlTick tick; if(!SymbolInfoTick(symbol,tick)) return;
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      double pip=PipSize(symbol);

      for(int i=PositionsTotal()-1;i>=0;--i)
      {
         string s=PositionGetSymbol(i); if(s!=symbol) continue;
         ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
         ENUM_POSITION_TYPE side=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double entry=PositionGetDouble(POSITION_PRICE_OPEN);
         double old_sl=PositionGetDouble(POSITION_SL);
         double tp=PositionGetDouble(POSITION_TP);
         double profit=PositionGetDouble(POSITION_PROFIT);
         int si=StateIndex(ticket,entry,old_sl);
         double risk_dist=m_states[si].initial_risk_distance;
         double market=(side==POSITION_TYPE_BUY ? tick.bid : tick.ask);
         double favorable=(side==POSITION_TYPE_BUY ? market-entry : entry-market);
         double r_now=(risk_dist>0.0 ? favorable/risk_dist : 0.0);

         bool pct_enabled=(m_be_pct_equity>0.0), r_enabled=(m_be_r>0.0);
         bool pct_hit=(pct_enabled && equity>0.0 && profit/equity>=m_be_pct_equity);
         bool r_hit=(r_enabled && r_now>=m_be_r);
         bool trigger=false;
         if(m_use_or) trigger=(pct_hit || r_hit);
         else if(pct_enabled && r_enabled) trigger=(pct_hit && r_hit);
         else trigger=(pct_hit || r_hit);

         if(trigger && !m_states[si].be_done)
         {
            double spread=MathMax(0.0,tick.ask-tick.bid);
            double offset=MathMax(m_be_offset_pips*pip,spread+tick_size);
            double candidate=(side==POSITION_TYPE_BUY ? entry+offset : entry-offset);
            double snapped=0.0,min_distance=0.0;
            if(BrokerSafeSL(symbol,side,candidate,tick,snapped,min_distance) &&
               ImproveOnly(side,old_sl,snapped,tick_size))
            {
               ulong rc=0;
               if(m_om.ModifyPositionStops(ticket,symbol,snapped,tp,rc))
               {
                  m_log.SLChange("BE",symbol,ticket,old_sl,snapped,market,tick_size,min_distance);
                  m_states[si].be_done=true;
                  old_sl=snapped;
               }
            }
         }

         if(m_atr_enabled && risk_dist>0.0 && r_now>=m_trail_start_r)
         {
            double atr=ATR(symbol);
            if(atr>0.0)
            {
               double candidate=(side==POSITION_TYPE_BUY ? tick.bid-atr*m_trail_atr_mult
                                                         : tick.ask+atr*m_trail_atr_mult);
               double snapped=0.0,min_distance=0.0;
               if(BrokerSafeSL(symbol,side,candidate,tick,snapped,min_distance) &&
                  ImproveOnly(side,old_sl,snapped,tick_size))
               {
                  ulong rc=0;
                  if(m_om.ModifyPositionStops(ticket,symbol,snapped,tp,rc))
                     m_log.SLChange("ATR",symbol,ticket,old_sl,snapped,market,tick_size,min_distance);
               }
            }
         }
      }
   }
};
