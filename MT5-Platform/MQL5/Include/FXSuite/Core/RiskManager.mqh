#property strict

class CRiskManager
{
private:
   double m_risk_pct;

   static double PipSize(const string symbol)
   {
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      return ((digits==3 || digits==5) ? point*10.0 : point);
   }

   static double SnapVolumeDown(const string symbol,const double raw)
   {
      double minv=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      double maxv=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      if(step<=0.0 || raw<minv) return 0.0;
      double v=MathMin(raw,maxv);
      v=MathFloor((v+1e-12)/step)*step;
      return (v>=minv ? v : 0.0);
   }

public:
   CRiskManager(const double risk_pct=0.005):m_risk_pct(risk_pct){}

   void SetRiskPct(const double r){ m_risk_pct=MathMax(0.0,r); }
   double GetRiskPct() const { return m_risk_pct; }

   double CalcLotBySL(const string symbol,const double stop_pips) const
   {
      if(stop_pips<=0.0) return 0.0;
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      double tick_value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
      double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      double pip=PipSize(symbol);
      if(eq<=0.0 || tick_value<=0.0 || tick_size<=0.0 || pip<=0.0) return 0.0;

      double stop_distance=stop_pips*pip;
      double risk_per_lot=(stop_distance/tick_size)*tick_value;
      if(risk_per_lot<=0.0) return 0.0;
      return SnapVolumeDown(symbol,(eq*m_risk_pct)/risk_per_lot);
   }

   double CalcLotByStopPrice(const string symbol,const double entry,const double stop) const
   {
      double distance=MathAbs(entry-stop);
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      double tick_value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
      double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      if(distance<=0.0 || eq<=0.0 || tick_value<=0.0 || tick_size<=0.0) return 0.0;
      double risk_per_lot=(distance/tick_size)*tick_value;
      return SnapVolumeDown(symbol,(eq*m_risk_pct)/risk_per_lot);
   }
};
