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
   double   m_max_margin_to_equity;
   int      m_max_positions;
   bool     m_omega_policy;

   datetime m_day;
   datetime m_week;
   double   m_day_start_eq;
   double   m_week_start_eq;
   double   m_peak_eq;

   string   m_state_path;
   datetime m_last_persist;

   static datetime DayStart(const datetime t)
   {
      MqlDateTime dt;
      TimeToStruct(t,dt);
      dt.hour=0;
      dt.min=0;
      dt.sec=0;
      return StructToTime(dt);
   }

   static datetime WeekStart(const datetime t)
   {
      MqlDateTime dt;
      TimeToStruct(t,dt);
      int back=(dt.day_of_week==0 ? 6 : dt.day_of_week-1);
      return DayStart(t)-back*86400;
   }

   bool LoadState()
   {
      int h=FileOpen(m_state_path,FILE_READ|FILE_CSV|FILE_ANSI);
      if(h==INVALID_HANDLE) return false;

      for(int i=0;i<5 && !FileIsEnding(h);++i) FileReadString(h);
      string day_s=FileReadString(h);
      string week_s=FileReadString(h);
      string day_eq_s=FileReadString(h);
      string week_eq_s=FileReadString(h);
      string peak_s=FileReadString(h);
      FileClose(h);

      if(day_s=="" || week_s=="" || day_eq_s=="" || week_eq_s=="" || peak_s=="")
         return false;

      m_day=(datetime)StringToInteger(day_s);
      m_week=(datetime)StringToInteger(week_s);
      m_day_start_eq=StringToDouble(day_eq_s);
      m_week_start_eq=StringToDouble(week_eq_s);
      m_peak_eq=StringToDouble(peak_s);

      return (m_day_start_eq>0.0 && m_week_start_eq>0.0 && m_peak_eq>0.0);
   }

   bool PersistState()
   {
      int h=FileOpen(m_state_path,FILE_WRITE|FILE_CSV|FILE_ANSI);
      if(h==INVALID_HANDLE) return false;

      FileWrite(h,"day","week","day_start_eq","week_start_eq","peak_eq");
      FileWrite(h,
                (long)m_day,
                (long)m_week,
                DoubleToString(m_day_start_eq,8),
                DoubleToString(m_week_start_eq,8),
                DoubleToString(m_peak_eq,8));
      FileFlush(h);
      FileClose(h);
      m_last_persist=TimeCurrent();
      return true;
   }

   static double PositionRiskPct(const string symbol,
                                 const double entry,
                                 const double sl,
                                 const double lots)
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
      m_max_heat(0.06),
      m_daily_limit(0.03),
      m_weekly_limit(0.07),
      m_peak_limit(0.12),
      m_soft_fraction(0.70),
      m_max_margin_to_equity(0.06),
      m_max_positions(12),
      m_omega_policy(false),
      m_day(0),
      m_week(0),
      m_day_start_eq(0.0),
      m_week_start_eq(0.0),
      m_peak_eq(0.0),
      m_state_path("FXSuite\\portfolio_risk_state.csv"),
      m_last_persist(0)
   {}

   void ConfigureStatePath(const string path)
   {
      if(path!="") m_state_path=path;
   }

   void ConfigureMarginHeat(const double max_margin_to_equity)
   {
      if(max_margin_to_equity>0.0)
         m_max_margin_to_equity=max_margin_to_equity;
   }

   double MaxMarginToEquity() const
   {
      return m_max_margin_to_equity;
   }

   // LEGACY_BEHAVIOR: daily breaker + position/heat caps only.
   void Configure(const double heat,const double daily_loss,const int max_positions)
   {
      m_max_heat=heat;
      m_daily_limit=daily_loss;
      m_max_positions=max_positions;
      m_omega_policy=false;
   }

   // NEW_BEHAVIOR: optional day/week/peak state machine.
   void ConfigureOmega(const double heat,
                       const double daily_loss,
                       const double weekly_loss,
                       const double peak_loss,
                       const int max_positions,
                       const double soft_fraction)
   {
      m_max_heat=heat;
      m_daily_limit=daily_loss;
      m_weekly_limit=weekly_loss;
      m_peak_limit=peak_loss;
      m_max_positions=max_positions;
      m_soft_fraction=MathMax(0.10,MathMin(0.95,soft_fraction));
      m_omega_policy=true;
   }

   void OnStartup()
   {
      datetime now=TimeCurrent();
      datetime today=DayStart(now);
      datetime this_week=WeekStart(now);
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);

      bool loaded=LoadState();
      if(!loaded)
      {
         m_day=today;
         m_week=this_week;
         m_day_start_eq=eq;
         m_week_start_eq=eq;
         m_peak_eq=eq;
      }
      else
      {
         if(m_day!=today)
         {
            m_day=today;
            m_day_start_eq=eq;
         }
         if(m_week!=this_week)
         {
            m_week=this_week;
            m_week_start_eq=eq;
         }
         if(m_peak_eq<=0.0) m_peak_eq=eq;
         if(eq>m_peak_eq) m_peak_eq=eq;
      }

      PersistState();
   }

   void OnHeartbeat()
   {
      datetime now=TimeCurrent();
      datetime today=DayStart(now);
      datetime this_week=WeekStart(now);
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      bool changed=false;

      if(today!=m_day)
      {
         m_day=today;
         m_day_start_eq=eq;
         changed=true;
      }

      if(this_week!=m_week)
      {
         m_week=this_week;
         m_week_start_eq=eq;
         changed=true;
      }

      if(eq>m_peak_eq)
      {
         m_peak_eq=eq;
         changed=true;
      }

      if(changed || m_last_persist==0 || now-m_last_persist>=60)
         PersistState();
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
      double d,w,p;
      Drawdowns(d,w,p);

      if(d>=m_daily_limit)
      {
         reason=StringFormat("daily_dd %.2f%% >= %.2f%%",d*100.0,m_daily_limit*100.0);
         return FXS_RISK_HARD_HALT;
      }

      if(m_omega_policy)
      {
         if(w>=m_weekly_limit)
         {
            reason=StringFormat("weekly_dd %.2f%% >= %.2f%%",w*100.0,m_weekly_limit*100.0);
            return FXS_RISK_HARD_HALT;
         }

         if(p>=m_peak_limit)
         {
            reason=StringFormat("peak_dd %.2f%% >= %.2f%%",p*100.0,m_peak_limit*100.0);
            return FXS_RISK_HARD_HALT;
         }

         if(d>=m_daily_limit*m_soft_fraction ||
            w>=m_weekly_limit*m_soft_fraction ||
            p>=m_peak_limit*m_soft_fraction)
         {
            reason="drawdown soft-halt threshold reached";
            return FXS_RISK_SOFT_HALT;
         }
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

         total+=PositionRiskPct(
            sym,
            PositionGetDouble(POSITION_PRICE_OPEN),
            PositionGetDouble(POSITION_SL),
            PositionGetDouble(POSITION_VOLUME)
         );
      }
      return total;
   }

   bool CanOpenNewPosition(const string symbol,
                           const double proposed_risk_pct,
                           string &reason_out) const
   {
      if(PositionsTotal()>=m_max_positions)
      {
         reason_out="max positions reached";
         return false;
      }

      string state_reason;
      if(State(state_reason)==FXS_RISK_HARD_HALT)
      {
         reason_out=state_reason;
         return false;
      }

      double after=CurrentOpenRiskPct()+MathMax(0.0,proposed_risk_pct);
      if(after>m_max_heat)
      {
         reason_out=StringFormat("risk heat %.2f%% > cap %.2f%%",
                                 after*100.0,m_max_heat*100.0);
         return false;
      }

      return true;
   }

   bool CanOpenNewPositionProjected(const string symbol,
                                    const ENUM_ORDER_TYPE side,
                                    const double lots,
                                    const double price,
                                    const double proposed_risk_pct,
                                    string &reason_out) const
   {
      if(!CanOpenNewPosition(symbol,proposed_risk_pct,reason_out))
         return false;

      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      double margin=0.0;
      if(eq<=0.0 || !OrderCalcMargin(side,symbol,lots,price,margin))
      {
         reason_out="unable to calculate projected margin";
         return false;
      }

      double after_margin=(AccountInfoDouble(ACCOUNT_MARGIN)+margin)/eq;
      if(after_margin>m_max_margin_to_equity)
      {
         reason_out=StringFormat("projected margin/equity %.2f%% > cap %.2f%%",
                                 after_margin*100.0,m_max_margin_to_equity*100.0);
         return false;
      }

      return true;
   }
};
