// FXSuite/Core/PortfolioControl.mqh
#property strict

class CPortfolioControl {
private:
   double m_max_portfolio_heat_pct;   // e.g., 0.06 = 6% total risk
   double m_daily_loss_limit_pct;     // e.g., 0.03 = 3% equity daily
   int    m_max_positions;            // e.g., 12
   datetime m_trading_day;

   double m_equity_day_start;

public:
   CPortfolioControl()
   : m_max_portfolio_heat_pct(0.06),
     m_daily_loss_limit_pct(0.03),
     m_max_positions(12),
     m_trading_day(0),
     m_equity_day_start(0.0)
   {}

   void Configure(const double heat, const double daily_loss, const int max_pos)
   {
      m_max_portfolio_heat_pct = heat;
      m_daily_loss_limit_pct   = daily_loss;
      m_max_positions          = max_pos;
   }

   void OnStartup()
   {
      m_trading_day = DateOfDay(TimeCurrent());
      m_equity_day_start = AccountInfoDouble(ACCOUNT_EQUITY);
   }

   void OnHeartbeat()
   {
      datetime d = DateOfDay(TimeCurrent());
      if(d != m_trading_day){
         m_trading_day = d;
         m_equity_day_start = AccountInfoDouble(ACCOUNT_EQUITY);
      }
   }

   bool CircuitBreakerTriggered(string &reason_out)
   {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_equity_day_start<=0.0) return false;
      double dd = (m_equity_day_start - eq) / m_equity_day_start;
      if(dd >= m_daily_loss_limit_pct){
         reason_out = StringFormat("Daily loss %.2f%% >= limit %.2f%%",
                        dd*100.0, m_daily_loss_limit_pct*100.0);
         return true;
      }
      return false;
   }

   bool CanOpenNewPosition(const string symbol, const double risk_pct_per_trade, string &reason_out)
   {
      // 1) position count
      if(PositionsTotal() >= m_max_positions){
         reason_out="Max positions reached";
         return false;
      }
      // 2) current portfolio heat (approximate: open positions * their initial risk)
      double current_heat=0.0;
      for(int i=0;i<PositionsTotal();i++){
         if(PositionGetSymbol(i)){
            string s = PositionGetString(POSITION_SYMBOL);
            double sl = PositionGetDouble(POSITION_SL);
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            double vol = PositionGetDouble(POSITION_VOLUME);
            int type = (int)PositionGetInteger(POSITION_TYPE);
            if(sl>0.0){
               double risk = RiskOfPositionPct(s, (ENUM_POSITION_TYPE)type, price, sl, vol);
               current_heat += risk;
            }
         }
      }
      double after = current_heat + risk_pct_per_trade;
      if(after > m_max_portfolio_heat_pct){
         reason_out = StringFormat("Portfolio heat %.2f%% > max %.2f%%",
                        after*100.0, m_max_portfolio_heat_pct*100.0);
         return false;
      }
      return true;
   }

private:
   static datetime DateOfDay(const datetime t)
   {
      MqlDateTime dt; TimeToStruct(t, dt);
      dt.hour=0; dt.min=0; dt.sec=0;
      return StructToTime(dt);
   }

   static double PipFactor(const string sym)
   {
      double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
      int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      return (dg==3 || dg==5) ? pt*10.0 : pt;
   }

   static double RiskOfPositionPct(const string sym, ENUM_POSITION_TYPE type, double price, double sl, double lots)
   {
      double pip = PipFactor(sym);
      double contract = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      double pips = 0.0;
      if(type==POSITION_TYPE_BUY)  pips = (price - sl)/pip;
      if(type==POSITION_TYPE_SELL) pips = (sl - price)/pip;
      if(pips<0.0) pips=0.0;
      double value_per_pip = lots * contract;
      double risk_money = value_per_pip * pips;
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return (eq>0.0 ? risk_money/eq : 0.0);
   }
};