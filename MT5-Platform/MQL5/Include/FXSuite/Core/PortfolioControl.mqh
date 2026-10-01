#property strict

enum ENUM_FXS_RISK_STATE
{
   FXS_RISK_NORMAL=0,
   FXS_RISK_SOFT_HALT=1,
   FXS_RISK_HARD_HALT=2
};

class CPortfolioControl
{
private:
   double   m_max_heat;
   double   m_daily_limit;
   double   m_weekly_limit;
   double   m_peak_limit;
   double   m_soft_fraction;
   int      m_max_positions;
   bool     m_omega_policy;

   datetime m_day;
   datetime m_week;
   double   m_day_start_eq;
   double   m_week_start_eq;
   double   m_peak_eq;

   static datetime DayStart(const datetime t)
   {
      MqlDateTime dt; TimeToStruct(t,dt);
      dt.hour=0; dt.min=0; dt.sec=0;
      return StructToTime(dt);
   }

   static datetime WeekStart(const datetime t)
   {
      MqlDateTime dt; TimeToStruct(t,dt);
      int back=(dt.day_of_week==0 ? 6 : dt.day_of_week-1);
      datetime d=DayStart(t)-back*86400;
      return d;
   }

   static double PositionRiskPct(const string symbol,const double entry,const double sl,const double lots)
   {
      if(sl<=0.0 || lots<=0.0) return 0.0;
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      double tick_value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
      double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      if(eq<=0.0 || tick_value<=0.0 || tick_size<=0.0) return 0.0;
      double risk_money=(MathAbs(entry-sl)/tick_size)*tick_value*lots;
      return risk_money/eq;
   }

public:
   CPortfolioControl():
      m_max_heat(0.06),m_daily_limit(0.03),m_weekly_limit(0.07),m_peak_limit(0.12),
      m_soft_fraction(0.70),m_max_positions(12),m_omega_policy(false),
      m_day(0),m_week(0),m_day_start_eq(0.0),m_week_start_eq(0.0),m_peak_eq(0.0){}

   // LEGACY_BEHAVIOR: daily breaker + position/heat caps only.
   void Configure(const double heat,const double daily_loss,const int max_positions)
   {
      m_max_heat=heat; m_daily_limit=daily_loss; m_max_positions=max_positions;
      m_omega_policy=false;
   }

   // NEW_BEHAVIOR: optional 3/7/12-style day/week/peak state machine.
   void ConfigureOmega(const double heat,const double daily_loss,const double weekly_loss,
                       const double peak_loss,const int max_positions,const double soft_fraction)
   {
      m_max_heat=heat; m_daily_limit=daily_loss; m_weekly_limit=weekly_loss;
      m_peak_limit=peak_loss; m_max_positions=max_positions;
      m_soft_fraction=MathMax(0.10,MathMin(0.95,soft_fraction));
      m_omega_policy=true;
   }

   void OnStartup()
   {
      datetime now=TimeCurrent();
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      m_day=DayStart(now); m_week=WeekStart(now);
      m_day_start_eq=eq; m_week_start_eq=eq; m_peak_eq=eq;
   }

   void OnHeartbeat()
   {
      datetime now=TimeCurrent();
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      datetime d=DayStart(now), w=WeekStart(now);
      if(d!=m_day){ m_day=d; m_day_start_eq=eq; }
      if(w!=m_week){ m_week=w; m_week_start_eq=eq; }
      if(eq>m_peak_eq) m_peak_eq=eq;
   }

   void Drawdowns(double &day_dd,double &week_dd,double &peak_dd) const
   {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      day_dd=(m_day_start_eq>0.0 ? MathMax(0.0,(m_day_start_eq-eq)/m_day_start_eq) : 0.0);
      week_dd=(m_week_start_eq>0.0 ? MathMax(0.0,(m_week_start_eq-eq)/m_week_start_eq) : 0.0);
      peak_dd=(m_peak_eq>0.0 ? MathMax(0.0,(m_peak_eq-eq)/m_peak_eq) : 0.0);
   }

   ENUM_FXS_RISK_STATE State(string &reason) const
   {
      double d,w,p; Drawdowns(d,w,p);
      if(d>=m_daily_limit)
      { reason=StringFormat("daily_dd %.2f%% >= %.2f%%",d*100.0,m_daily_limit*100.0); return FXS_RISK_HARD_HALT; }

      if(m_omega_policy)
      {
         if(w>=m_weekly_limit)
         { reason=StringFormat("weekly_dd %.2f%% >= %.2f%%",w*100.0,m_weekly_limit*100.0); return FXS_RISK_HARD_HALT; }
         if(p>=m_peak_limit)
         { reason=StringFormat("peak_dd %.2f%% >= %.2f%%",p*100.0,m_peak_limit*100.0); return FXS_RISK_HARD_HALT; }

         if(d>=m_daily_limit*m_soft_fraction || w>=m_weekly_limit*m_soft_fraction || p>=m_peak_limit*m_soft_fraction)
         { reason="drawdown soft-halt threshold reached"; return FXS_RISK_SOFT_HALT; }
      }
      reason="normal";
      return FXS_RISK_NORMAL;
   }

   double SizeMultiplier() const
   {
      string reason;
      ENUM_FXS_RISK_STATE s=State(reason);
      if(s==FXS_RISK_HARD_HALT) return 0.0;
      if(s==FXS_RISK_SOFT_HALT) return 0.50;
      return 1.0;
   }

   bool CircuitBreakerTriggered(string &reason_out) const
   {
      return (State(reason_out)==FXS_RISK_HARD_HALT);
   }

   double CurrentOpenRiskPct() const
   {
      double total=0.0;
      for(int i=0;i<PositionsTotal();++i)
      {
         string sym=PositionGetSymbol(i);
         if(sym=="") continue;
         total+=PositionRiskPct(sym,PositionGetDouble(POSITION_PRICE_OPEN),
                               PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_VOLUME));
      }
      return total;
   }

   bool CanOpenNewPosition(const string symbol,const double proposed_risk_pct,string &reason_out) const
   {
      if(PositionsTotal()>=m_max_positions){ reason_out="max positions reached"; return false; }
      string state_reason;
      if(State(state_reason)==FXS_RISK_HARD_HALT){ reason_out=state_reason; return false; }
      double after=CurrentOpenRiskPct()+MathMax(0.0,proposed_risk_pct);
      if(after>m_max_heat)
      {
         reason_out=StringFormat("risk heat %.2f%% > cap %.2f%%",after*100.0,m_max_heat*100.0);
         return false;
      }
      return true;
   }

   bool CanOpenNewPositionProjected(const string symbol,const ENUM_ORDER_TYPE side,const double lots,
                                    const double price,const double proposed_risk_pct,string &reason_out) const
   {
      if(!CanOpenNewPosition(symbol,proposed_risk_pct,reason_out)) return false;
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      double margin=0.0;
      if(eq<=0.0 || !OrderCalcMargin(side,symbol,lots,price,margin))
      { reason_out="unable to calculate projected margin"; return false; }
      double after_margin=(AccountInfoDouble(ACCOUNT_MARGIN)+margin)/eq;
      if(after_margin>m_max_heat)
      {
         reason_out=StringFormat("projected margin heat %.2f%% > cap %.2f%%",after_margin*100.0,m_max_heat*100.0);
         return false;
      }
      return true;
   }
};
