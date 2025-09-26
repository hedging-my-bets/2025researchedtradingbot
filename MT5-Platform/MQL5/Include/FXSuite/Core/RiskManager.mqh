#property strict

class CRiskManager {
private:
   double m_risk_pct;   // per-trade risk % of equity (e.g., 0.5% -> 0.005)
public:
   CRiskManager(const double risk_pct=0.005): m_risk_pct(risk_pct) {}

   void SetRiskPct(const double r){ m_risk_pct=r; }

   double CalcLotBySL(const string symbol, const double stop_pips)
   {
      if(stop_pips<=0.0) return 0.0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double risk   = equity * m_risk_pct;

      double pt = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int    dg = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double pip = (dg==3 || dg==5) ? pt*10.0 : pt;

      double tick_val  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

      // value per pip for 1 lot ≈ (pip / tick_size) * tick_val
      double pip_value_per_lot = (pip / tick_size) * tick_val;

      double lots = risk / (stop_pips * pip_value_per_lot);
      // clamp to broker limits
      double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double step    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      lots = MathMax(min_lot, MathMin(max_lot, lots));
      // round to step
      lots = MathFloor(lots/step)*step;
      return lots;
   }
};