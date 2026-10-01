#property strict

struct FXSCostEstimate
{
   double spread_money;
   double commission_money;
   double slippage_money;
   double swap_money;
   double total_cost_money;
   bool   swap_supported;
};

class CCostModel
{
private:
   static double PipSize(const string symbol)
   {
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      return ((digits==3 || digits==5) ? point*10.0 : point);
   }

   static double TickValueLoss(const string symbol)
   {
      double v=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(v<=0.0) v=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
      return MathMax(0.0,v);
   }

public:
   static double RiskMoney(const string symbol,
                           const double entry,
                           const double stop,
                           const double lots)
   {
      double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      double tick_value=TickValueLoss(symbol);
      if(tick_size<=0.0 || tick_value<=0.0 || lots<=0.0) return 0.0;
      return (MathAbs(entry-stop)/tick_size)*tick_value*lots;
   }

   static bool Estimate(const string symbol,
                        const ENUM_ORDER_TYPE side,
                        const double lots,
                        const double expected_slippage_pips,
                        const double roundtrip_commission_per_lot,
                        const int expected_hold_nights,
                        FXSCostEstimate &out)
   {
      ZeroMemory(out);
      if(lots<=0.0) return false;

      MqlTick tick;
      if(!SymbolInfoTick(symbol,tick)) return false;

      double spread_pnl=0.0;
      bool spread_ok=false;
      if(side==ORDER_TYPE_BUY)
         spread_ok=OrderCalcProfit(ORDER_TYPE_BUY,symbol,lots,tick.ask,tick.bid,spread_pnl);
      else if(side==ORDER_TYPE_SELL)
         spread_ok=OrderCalcProfit(ORDER_TYPE_SELL,symbol,lots,tick.bid,tick.ask,spread_pnl);
      else
         return false;

      if(!spread_ok) return false;

      out.spread_money=MathMax(0.0,-spread_pnl);
      out.commission_money=MathMax(0.0,roundtrip_commission_per_lot)*lots;

      double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      double tick_value=TickValueLoss(symbol);
      double slip_distance=MathMax(0.0,expected_slippage_pips)*PipSize(symbol);
      out.slippage_money=(tick_size>0.0 && tick_value>0.0 ?
                          (slip_distance/tick_size)*tick_value*lots : 0.0);

      out.swap_supported=true;
      out.swap_money=0.0;

      if(expected_hold_nights>0)
      {
         ENUM_SYMBOL_SWAP_MODE mode=(ENUM_SYMBOL_SWAP_MODE)SymbolInfoInteger(symbol,SYMBOL_SWAP_MODE);
         if(mode==SYMBOL_SWAP_MODE_POINTS)
         {
            double swap_points=(side==ORDER_TYPE_BUY ?
                                SymbolInfoDouble(symbol,SYMBOL_SWAP_LONG) :
                                SymbolInfoDouble(symbol,SYMBOL_SWAP_SHORT));
            double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
            double swap_value=(tick_size>0.0 && tick_value>0.0 ?
                               (swap_points*point/tick_size)*tick_value*lots*expected_hold_nights :
                               0.0);
            out.swap_money=MathMax(0.0,-swap_value);
         }
         else if(mode!=SYMBOL_SWAP_MODE_DISABLED)
         {
            // Other broker swap modes require broker-specific currency conversion.
            out.swap_supported=false;
         }
      }

      out.total_cost_money=out.spread_money+
                           out.commission_money+
                           out.slippage_money+
                           out.swap_money;
      return true;
   }
};
