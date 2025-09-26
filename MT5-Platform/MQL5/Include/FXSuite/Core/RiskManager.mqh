// FXSuite/Core/RiskManager.mqh
#property strict

class CRiskManager
{
private:
   double m_risk_pct; // e.g., 0.005 = 0.5% equity

   static double PipSize(const string sym)
   {
      double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
      int dg=(int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      return (dg==3 || dg==5) ? pt*10.0 : pt;
   }

public:
   CRiskManager(const double risk_pct): m_risk_pct(risk_pct) {}
   void   SetRiskPct(const double r){ m_risk_pct=r; }
   double GetRiskPct() const { return m_risk_pct; }

   // Calculate volume so that loss at SL_pips ~= equity * risk_pct
   double CalcLotBySL(const string sym, const double SL_pips) const
   {
      if(SL_pips<=0.0) return 0.0;
      double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq<=0.0) return 0.0;

      // pip value per 1.0 lot (approx, FX)
      double tick_val = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double tick_sz  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      double pip      = PipSize(sym);
      double value_per_pip_per_lot = (tick_sz>0.0 ? (tick_val/tick_sz)*pip : 0.0);
      if(value_per_pip_per_lot<=0.0) return 0.0;

      double risk_money = eq * m_risk_pct;
      double lots = risk_money / (value_per_pip_per_lot * SL_pips);

      // clamp to broker limits
      double minv = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double maxv = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      if(step<=0.0) step=0.01;
      if(lots<minv) lots=minv;
      if(lots>maxv) lots=maxv;
      lots = MathFloor(lots/step)*step;
      return lots;
   }
};