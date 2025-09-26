// Builds EXACT meta feature vector (t-1) per features.yaml.
// Self-contained (uses built-ins) + file snapshots for slow/cross metrics.
#property strict

class CFeatureExtractor {
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;

   // indicator handles
   int m_ema20, m_ema50, m_ema200, m_atr14, m_bb;

public:
   CFeatureExtractor(const string symbol, ENUM_TIMEFRAMES tf): m_symbol(symbol), m_tf(tf) {}

   bool Init()
   {
      m_ema20  = iMA(m_symbol, m_tf, 20, 0, MODE_EMA, PRICE_CLOSE);
      m_ema50  = iMA(m_symbol, m_tf, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_ema200 = iMA(m_symbol, m_tf, 200,0, MODE_EMA, PRICE_CLOSE);
      m_atr14  = iATR(m_symbol, m_tf, 14);
      m_bb     = iBands(m_symbol, m_tf, 20, 0, 2.0, PRICE_CLOSE);
      return (m_ema20!=INVALID_HANDLE && m_ema50!=INVALID_HANDLE && m_ema200!=INVALID_HANDLE && m_atr14!=INVALID_HANDLE && m_bb!=INVALID_HANDLE);
   }

   // Fill features[] exactly in features.yaml order; intent flags provided by caller.
   bool Build(double &features[], const int intent_breakout, const int intent_trend, const int intent_squeeze)
   {
      ArrayInitialize(features, 0.0);
      // Use shift 1 (closed bar)
      double c1 = iClose(m_symbol, m_tf, 1);
      double c2 = iClose(m_symbol, m_tf, 2);
      double c4 = iClose(m_symbol, m_tf, 4);
      double c6 = iClose(m_symbol, m_tf, 6);
      double h1 = iHigh(m_symbol, m_tf, 1);
      double l1 = iLow(m_symbol,  m_tf, 1);

      // buffers
      double ema20[], ema50[], ema200[], atr14[], bup[], bmd[], blw[];
      ArraySetAsSeries(ema20,true); ArraySetAsSeries(ema50,true); ArraySetAsSeries(ema200,true);
      ArraySetAsSeries(atr14,true); ArraySetAsSeries(bup,true);  ArraySetAsSeries(bmd,true); ArraySetAsSeries(blw,true);

      if(CopyBuffer(m_ema20,0,0,3,ema20)<=0) return false;
      if(CopyBuffer(m_ema50,0,0,4,ema50)<=0) return false;
      if(CopyBuffer(m_ema200,0,0,3,ema200)<=0) return false;
      if(CopyBuffer(m_atr14,0,0,3,atr14)<=0) return false;
      if(CopyBuffer(m_bb,0,0,3,bup)<=0 || CopyBuffer(m_bb,1,0,3,bmd)<=0 || CopyBuffer(m_bb,2,0,3,blw)<=0) return false;

      int k=0;
      // --- returns
      features[k++] = (c2>0.0 ? MathLog(c1/c2) : 0.0);  // ret_1
      features[k++] = (c4>0.0 ? MathLog(c1/c4) : 0.0);  // ret_3
      features[k++] = (c6>0.0 ? MathLog(c1/c6) : 0.0);  // ret_5

      // --- Parkinson RV (20)
      features[k++] = RVParkinson(20);                  // rv_parkinson_20

      // --- ATR(14) pips & pct
      double atrp = atr14[1]*PipFactor();
      features[k++] = atrp;                              // atr_14_pips
      features[k++] = (c1>0.0 ? (atrp/10000.0) / c1 * 1e4 : 0.0); // atr_pct

      // --- EMAs & slope
      features[k++] = ema20[1];
      features[k++] = ema50[1];
      features[k++] = ema200[1];
      features[k++] = ema50[1] - ema50[2];              // ema_slope_50

      // --- Donchian 20 distance
      features[k++] = DonchianDist(20);                 // donchian_20_dist

      // --- BB width normalized by ATR value (points)
      double bbw = (bup[1]-blw[1]);
      features[k++] = (atr14[1]>0.0 ? bbw/atr14[1] : 0.0); // bb_width_norm

      // --- microstructure proxies
      features[k++] = CurrentSpreadPips();              // spread_now_pips
      features[k++] = LoadSpreadPercentile();           // spread_pctile_60d
      features[k++] = TickImbalance(50);                // tick_imbalance_50
      features[k++] = QuoteChangeRate(20);              // quote_change_rate
      features[k++] = OFIProxy(20);                     // ofi_proxy_20
      features[k++] = VPINProxy(50);                    // vpin_proxy_50
      features[k++] = KyleLambdaProxy(20);              // kyle_lambda_proxy

      // --- session & calendar
      datetime now_utc = TimeGMT();
      features[k++] = (double)SessionId(now_utc);       // session_id
      features[k++] = MinutesToLondonOpen(now_utc);     // mins_to_london_open
      features[k++] = MinutesToNextHighImpact(now_utc); // mins_to_news_high
      features[k++] = AsiaRangeWidthAtLondon();         // asia_range_width_at_lon
      features[k++] = ADR14Norm();                      // adr_14_norm

      // --- cross-asset snapshot
      double dxy, spx, xau, oil, ust2y;
      LoadCrossSnapshot(dxy, spx, xau, oil, ust2y);
      features[k++] = dxy;  // dxy_ret_60m
      features[k++] = spx;  // spx_ret_60m
      features[k++] = xau;  // gold_ret_60m
      features[k++] = oil;  // oil_ret_60m
      features[k++] = ust2y;// ust2y_change_bps_60m

      // --- slow factors
      double cot, carry, ppp, mom;
      LoadSlowFactors(cot, carry, ppp, mom);
      features[k++] = cot;
      features[k++] = carry;
      features[k++] = ppp;
      features[k++] = mom;

      // --- your indicators via iCustom (ensure buffers exist)
      features[k++] = ReadSRDistancePips();
      features[k++] = (double)ReadCandleRejectFlag();
      features[k++] = (double)ReadDivergenceFlag();
      features[k++] = ReadHarmonicPRZProximity();

      // --- intent flags
      features[k++] = (double)intent_breakout;
      features[k++] = (double)intent_trend;
      features[k++] = (double)intent_squeeze;

      return true;
   }

private:
   double PipFactor()
   {
      double pt = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int dg = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      return (dg==3 || dg==5) ? pt*10.0 : pt;
   }

   double CurrentSpreadPips()
   {
      MqlTick t; if(!SymbolInfoTick(m_symbol, t)) return 0.0;
      return (t.ask - t.bid)/PipFactor();
   }

   double RVParkinson(const int w)
   {
      double sum=0.0; int cnt=0;
      for(int i=1;i<=w;i++){
         double hi=iHigh(m_symbol, m_tf, i);
         double lo=iLow(m_symbol,  m_tf, i);
         if(hi>0 && lo>0){
            double val = MathPow(MathLog(hi/lo),2.0);
            sum += val; cnt++;
         }
      }
      if(cnt==0) return 0.0;
      return (1.0/(4.0*MathLog(2.0))) * (sum/cnt);
   }

   double DonchianDist(const int n)
   {
      int hi_idx = iHighest(m_symbol, m_tf, MODE_HIGH, n, 1);
      int lo_idx = iLowest(m_symbol,  m_tf, MODE_LOW,  n, 1);
      double hi = iHigh(m_symbol, m_tf, hi_idx);
      double lo = iLow(m_symbol,  m_tf, lo_idx);
      double mid = (hi+lo)/2.0, range = MathMax(1e-10, hi-lo);
      double c1 = iClose(m_symbol, m_tf, 1);
      return (c1 - mid) / range;
   }

   double TickImbalance(const int w)
   {
      double sum=0; int cnt=0;
      for(int i=1;i<=w;i++){
         double c0=iClose(m_symbol, m_tf, i);
         double c1=iClose(m_symbol, m_tf, i+1);
         double s = (c0>c1 ? 1.0 : (c0<c1 ? -1.0 : 0.0));
         sum += s; cnt++;
      }
      return (cnt>0 ? sum/cnt : 0.0);
   }

   double QuoteChangeRate(const int w)
   {
      // proxy using tick volume per bar normalized by window
      double sum=0; for(int i=1;i<=w;i++) sum += iVolume(m_symbol, m_tf, i);
      return (w>0 ? sum / (double)w : 0.0);
   }

   double OFIProxy(const int w)
   {
      // sum(sign(ret) * tick_volume)
      double acc=0;
      for(int i=1;i<=w;i++){
         double c0=iClose(m_symbol, m_tf, i);
         double c1=iClose(m_symbol, m_tf, i+1);
         double s=(c0>c1?1.0:(c0<c1?-1.0:0.0));
         acc += s * (double)iVolume(m_symbol, m_tf, i);
      }
      return acc / (double)MathMax(1, w);
   }

   double VPINProxy(const int w)
   {
      double num=0, den=0;
      for(int i=1;i<=w;i++){
         double c0=iClose(m_symbol, m_tf, i);
         double c1=iClose(m_symbol, m_tf, i+1);
         num += MathAbs(MathLog(c0/c1));
         den += (double)iVolume(m_symbol, m_tf, i);
      }
      return (den>0 ? num/den : 0.0);
   }

   double KyleLambdaProxy(const int w)
   {
      double num=0, den=0;
      for(int i=1;i<=w;i++){
         double c0=iClose(m_symbol, m_tf, i);
         double c1=iClose(m_symbol, m_tf, i+1);
         num += MathAbs(MathLog(c0/c1));
         den += (double)iVolume(m_symbol, m_tf, i);
      }
      return (den>0 ? num/den : 0.0);
   }

   int SessionId(const datetime utc_now)
   {
      // 0=Asia,1=London,2=NY,3=Overlap based on Europe/London local time
      int offset = LondonOffsetMinutes(utc_now);
      datetime london = utc_now + offset*60;
      MqlDateTime dt; TimeToStruct(london, dt);
      int h = dt.hour;
      if(h>=7 && h<12) return 1;
      if(h>=12 && h<16) return 3;
      if(h>=16 && h<21) return 2;
      return 0;
   }

   int LondonOffsetMinutes(datetime utc_now)
   {
      // DST: last Sunday of March 01:00 UTC -> last Sunday of October 01:00 UTC
      MqlDateTime dt; TimeToStruct(utc_now, dt);
      int year = dt.year;
      datetime dst_start = LastSundayOfMonth(year, 3, 1); // 01:00 UTC
      datetime dst_end   = LastSundayOfMonth(year, 10,1);
      return ((utc_now >= dst_start) && (utc_now < dst_end)) ? 60 : 0;
   }

   datetime LastSundayOfMonth(const int year, const int month, const int hourUTC)
   {
      // Find last day of month
      int mdays[12] = {31,28,31,30,31,30,31,31,30,31,30,31};
      bool leap = ((year%4==0 && year%100!=0) || (year%400==0));
      if(leap) mdays[1]=29;
      int day = mdays[month-1];
      MqlDateTime dt; dt.year=year; dt.mon=month; dt.hour=hourUTC; dt.min=0; dt.sec=0;
      for(; day>=25; day--){ dt.day=day; datetime t=StructToTime(dt); if(TimeDayOfWeek(t)==0) return t; }
      dt.day=mdays[month-1]; return StructToTime(dt);
   }

   double MinutesToLondonOpen(const datetime utc_now)
   {
      int offset = LondonOffsetMinutes(utc_now);
      datetime london = utc_now + offset*60;
      MqlDateTime d; TimeToStruct(london, d);
      MqlDateTime open = d; open.hour=7; open.min=0; open.sec=0;
      datetime t_open = StructToTime(open);
      return (double)((t_open - london)/60);
   }

   double MinutesToNextHighImpact(const datetime utc_now)
   {
      // Optional: read from calendar.csv via CNewsCalendar class within EA.
      return 9999.0;
   }

   double AsiaRangeWidthAtLondon()
   {
      // Measure 00:00–06:59 London range using M15 bars of prior session
      int offset = LondonOffsetMinutes(TimeGMT());
      datetime now_london = TimeGMT() + offset*60;
      MqlDateTime d; TimeToStruct(now_london, d);
      // compute last session date 00:00 to 06:59
      MqlDateTime s = d; s.hour=0; s.min=0; s.sec=0; datetime start = StructToTime(s) - 24*60*60;
      MqlDateTime e = s; e.hour=6; e.min=59; e.sec=0; datetime end = StructToTime(e) - 24*60*60;

      // Iterate H1/M15 bars across [start,end]
      double hi= -DBL_MAX, lo= DBL_MAX;
      for(int i=1;i<=200;i++){
         datetime t = iTime(m_symbol, PERIOD_M15, i);
         if(t==0) break;
         datetime t_london = t + offset*60;
         if(t_london>=start && t_london<=end){
            double h = iHigh(m_symbol, PERIOD_M15, i);
            double l = iLow(m_symbol,  PERIOD_M15, i);
            if(h>hi) hi=h;
            if(l<lo) lo=l;
         }
      }
      if(hi<=0 || lo<=0 || hi<=lo) return 0.0;
      return (hi - lo) / PipFactor();
   }

   double ADR14Norm()
   {
      // ADR14 / median ADR60 (D1)
      double adr14=0.0;
      for(int i=1;i<=14;i++){
         double hi=iHigh(m_symbol, PERIOD_D1, i);
         double lo=iLow(m_symbol,  PERIOD_D1, i);
         adr14 += (hi-lo);
      }
      adr14 /= 14.0;

      double adr60[60]; int n=0;
      for(int i=1;i<=60;i++){
         double hi=iHigh(m_symbol, PERIOD_D1, i);
         double lo=iLow(m_symbol,  PERIOD_D1, i);
         adr60[n++] = (hi-lo);
      }
      ArraySort(adr60, WHOLE_ARRAY, 0, MODE_ASCEND);
      double median = (n>0 ? (n%2 ? adr60[n/2] : 0.5*(adr60[n/2-1]+adr60[n/2])) : 1.0);
      return (median>0.0 ? (adr14/median) : 1.0);
   }

   double LoadSpreadPercentile()
   {
      // Optional: Python writes Files/spread_percentiles.csv with last calc (pctl for symbol)
      int h = FileOpen("Files\\spread_percentiles.csv", FILE_READ|FILE_CSV|FILE_ANSI);
      if(h==INVALID_HANDLE) return 50.0;
      // header: symbol,pctl
      string sym, p; FileReadString(h); // header
      while(!FileIsEnding(h)){
         sym = FileReadString(h); p = FileReadString(h); FileReadString(h);
         if(sym==m_symbol){ double v = StringToDouble(p); FileClose(h); return v; }
      }
      FileClose(h);
      return 50.0;
   }

   void LoadCrossSnapshot(double &dxy, double &spx, double &xau, double &oil, double &ust2y)
   {
      dxy=spx=xau=oil=ust2y=0.0;
      int h = FileOpen("Files\\cross_snapshot.csv", FILE_READ|FILE_CSV|FILE_ANSI);
      if(h==INVALID_HANDLE) return;
      // header: dxy_ret_60m,spx_ret_60m,gold_ret_60m,oil_ret_60m,ust2y_change_bps_60m
      string hdr=FileReadString(h);
      string a=FileReadString(h); string b=FileReadString(h); string c=FileReadString(h);
      string d=FileReadString(h); string e=FileReadString(h);
      dxy = StringToDouble(a); spx = StringToDouble(b); xau = StringToDouble(c);
      oil = StringToDouble(d); ust2y = StringToDouble(e);
      FileClose(h);
   }

   void LoadSlowFactors(double &cot, double &carry, double &ppp, double &mom)
   {
      cot=carry=ppp=mom=0.0;
      int h = FileOpen("Files\\slow_factors.csv", FILE_READ|FILE_CSV|FILE_ANSI);
      if(h==INVALID_HANDLE) return;
      // header: symbol,cot_net_spec_z,carry_3m_pa,ppp_deviation_z,mom_6m_voladj
      string hdr=FileReadString(h);
      while(!FileIsEnding(h)){
         string s=FileReadString(h);
         string c1=FileReadString(h);
         string c2=FileReadString(h);
         string c3=FileReadString(h);
         string c4=FileReadString(h);
         FileReadString(h);
         if(s==m_symbol){
            cot   = StringToDouble(c1);
            carry = StringToDouble(c2);
            ppp   = StringToDouble(c3);
            mom   = StringToDouble(c4);
            break;
         }
      }
      FileClose(h);
   }

   // ---- Custom indicator readers (adapt buffer indices to your builds) ----
   double ReadSRDistancePips()
   {
      int h = iCustom(m_symbol, m_tf, "FXSuite/AutoSR_Levels.ex5");
      if(h==INVALID_HANDLE) return 0.0;
      double buf[]; ArraySetAsSeries(buf,true);
      if(CopyBuffer(h,0,0,2,buf)<=0) return 0.0;
      return buf[1];
   }

   int ReadCandleRejectFlag()
   {
      int h = iCustom(m_symbol, m_tf, "FXSuite/CandlePatterns.ex5");
      if(h==INVALID_HANDLE) return 0;
      double buf[]; ArraySetAsSeries(buf,true);
      if(CopyBuffer(h,0,0,2,buf)<=0) return 0;
      return (int)buf[1];
   }

   int ReadDivergenceFlag()
   {
      int h = iCustom(m_symbol, m_tf, "FXSuite/DivergenceDetector.ex5");
      if(h==INVALID_HANDLE) return 0;
      double buf[]; ArraySetAsSeries(buf,true);
      if(CopyBuffer(h,0,0,2,buf)<=0) return 0;
      return (int)buf[1];
   }

   double ReadHarmonicPRZProximity()
   {
      int h = iCustom(m_symbol, m_tf, "FXSuite/HarmonicScanner.ex5");
      if(h==INVALID_HANDLE) return 0.0;
      double buf[]; ArraySetAsSeries(buf,true);
      if(CopyBuffer(h,0,0,2,buf)<=0) return 0.0;
      return buf[1];
   }
};