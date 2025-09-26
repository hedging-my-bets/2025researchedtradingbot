// FXSuite/Core/OrderManager.mqh
#property strict
#include <Trade/Trade.mqh>

struct OrderRecord {
   ulong   ticket;
   double  price;
   double  sl;
   double  tp;
   datetime time;
   string  corr_id;
   string  comment;
};

class COrderManager
{
private:
   CTrade m_tr;

   bool NormalizeVolume(const string sym, double &vol) const
   {
      double minv = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double maxv = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      if(step<=0.0) step=0.01;
      if(vol<minv) vol=minv;
      if(vol>maxv) vol=maxv;
      vol = MathFloor(vol/step)*step;
      return (vol>=minv && vol<=maxv);
   }

public:
   COrderManager(){ m_tr.SetAsyncMode(false); }

   bool SendMarket(const string symbol, const ENUM_ORDER_TYPE side, double lots,
                   const double sl, const double tp, const string corr_id, OrderRecord &out)
   {
      if(!SymbolInfoInteger(symbol, SYMBOL_TRADING_ALLOWED)) { Print("Trading not allowed: ",symbol); return false; }
      if(!NormalizeVolume(symbol, lots)) { Print("Invalid/normalized lots failed"); return false; }

      bool ok=false;
      string cmt = corr_id;
      if(side==ORDER_TYPE_BUY)  ok = m_tr.Buy(lots, symbol, 0.0, sl, tp, cmt);
      if(side==ORDER_TYPE_SELL) ok = m_tr.Sell(lots, symbol, 0.0, sl, tp, cmt);
      if(!ok){
         PrintFormat("Order send failed: ret=%d, reason=%d", (int)ok, GetLastError());
         return false;
      }
      out.ticket = m_tr.ResultOrder();
      out.price  = m_tr.ResultPrice();
      out.sl     = sl;
      out.tp     = tp;
      out.time   = TimeCurrent();
      out.corr_id= corr_id;
      out.comment= cmt;
      return (out.ticket>0);
   }
};