#property strict
#include <Trade/Trade.mqh>

enum SlippageReason { SLIP_MARKET=0, SLIP_LATENCY=1, SLIP_REJECT=2 };

struct OrderRecord {
   string python_signal_id;
   long   ticket;
   string symbol;
   ENUM_ORDER_TYPE type;
   double intended_price;
   double fill_price;
   SlippageReason reason;
   datetime ts_utc;
};

class COrderManager {
private:
   CTrade m_trade;
public:
   bool SendMarket(const string symbol, ENUM_ORDER_TYPE type, double lots, double sl, double tp,
                   const string signal_id, OrderRecord &rec)
   {
      MqlTick t; if(!SymbolInfoTick(symbol, t)) return false;
      rec.symbol = symbol; rec.type = type; rec.python_signal_id=signal_id;
      rec.ts_utc = TimeGMT();
      rec.intended_price = (type==ORDER_TYPE_BUY ? t.ask : t.bid);

      bool ok = (type==ORDER_TYPE_BUY) ? m_trade.Buy(lots, symbol, 0, sl, tp, signal_id)
                                       : m_trade.Sell(lots, symbol, 0, sl, tp, signal_id);
      rec.ticket = m_trade.ResultOrder();
      rec.fill_price = m_trade.ResultPrice();
      rec.reason = ok ? SLIP_MARKET : SLIP_REJECT;
      return ok;
   }

   bool SendStop(const string symbol, ENUM_ORDER_TYPE type, double lots, double price, double sl, double tp,
                 const string signal_id, OrderRecord &rec)
   {
      rec.symbol=symbol; rec.type=type; rec.python_signal_id=signal_id; rec.ts_utc=TimeGMT(); rec.intended_price=price;
      bool ok=false;
      if(type==ORDER_TYPE_BUY_STOP)  ok = m_trade.BuyStop(lots, symbol, price, 0, sl, tp, ORDER_TIME_GTC, 0, signal_id);
      if(type==ORDER_TYPE_SELL_STOP) ok = m_trade.SellStop(lots, symbol, price, 0, sl, tp, ORDER_TIME_GTC, 0, signal_id);
      rec.ticket = m_trade.ResultOrder(); rec.fill_price = 0.0; rec.reason = ok?SLIP_MARKET:SLIP_REJECT;
      return ok;
   }

   bool ModifySLTP(const long position_ticket, const double sl, const double tp)
   {
      string sym = PositionGetString(POSITION_SYMBOL);
      if(!PositionSelectByTicket(position_ticket)) return false;
      return m_trade.PositionModify(sym, sl, tp);
   }

   bool CancelOrder(const long order_ticket)
   {
      return m_trade.OrderDelete(order_ticket);
   }
};