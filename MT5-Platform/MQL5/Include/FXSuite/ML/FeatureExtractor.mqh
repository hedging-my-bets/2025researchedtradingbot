#property strict

class CFeatureExtractor {
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;
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

   bool Build(double &features[], const int intent_breakout, const int intent_trend, const int intent_squeeze)
   {
      ArrayInitialize(features, 0.0);

      // Closed bars
      double c1 = iClose(m_symbol, m_tf, 1);
      double c2 = iClose(m_symbol, m_tf, 2);
      double c4 = iClose(m_symbol, m_tf, 4);
      double c6 = iClose(m_symbol, m_tf, 6);

      // Indicator buffers (closed bar = shift 1)
      double ema20[], ema50[], ema200[], atr14[], bup[], bmd[], blw[];
      ArraySetAsSeries(ema20,true); ArraySetAsSeries(ema50,true); ArraySetAsSeries(ema200,true);
      ArraySetAsSeries(atr14,true); ArraySetAsSeries(bup,true);  ArraySetAsSeries(bmd,true); ArraySetAsSeries(blw,true);

      if(CopyBuffer(m_ema20,0,1,2,ema20)<=0) return false;
      if(CopyBuffer(m_ema50,0,1,3,ema50)<=0) return false;
      if(CopyBuffer(m_ema200,0,1,2,ema200)<=0) return false;
      if(CopyBuffer(m_atr14,0,1,2,atr14)<=0) return false;
      if(CopyBuffer(m_bb,0,1,2,bup)<=0 || CopyBuffer(m_bb,1,1,2,bmd)<=0 || CopyBuffer(m_bb,2,1,2,blw)<=0) return false;

      int k=0;
      // returns
      features[k++] = (c2>0.0 ? MathLog(c1/c2) : 0.0);
      features[k++] = (c4>0.0 ? MathLog(c1/c4) : 0.0);
      features[k++] = (c6>0.0 ? MathLog(c1/c6) : 0.0);

      // RV (Parkinson 20)
      features[k++] = RVParkinson(20);

      // ATR metrics
      double atrv = atr14[0];
      double atrp = atrv * PipFactor();
      features[k++] = atrp;
      features[k++] = (c1>0.0 ? (atrp/10000.0) / c1 * 1e4 : 0.0);

      // EMAs & slope
      features[k++] = ema20[0];
      features[k++] = ema50[0];
      features[k++] = ema200[0];
      features[k++] = ema50[0] - ema50[1];

      // Donchian distance
      features[k++] = DonchianDist(20);

      // BB width / ATR
      double bbw = (bup[0]-blw[0]);
      features[k++] = (atrv>0.0 ? bbw/atrv : 0.0);

      // microstructure proxies
      features[k++] = CurrentSpreadPips();
      features[k++] = LoadSpreadPercentile();
      features[k++] = TickImbalance(50);
      features[k++] = QuoteChangeRate(20);
      features[k++] = OFIProxy(20);
      features[k++] = VPINProxy(50);
      features[k++] = KyleLambdaProxy(20);

      // session & calendar
      datetime now_utc = TimeGMT();
      features[k++] = (double)SessionId(now_utc);
      features[k++] = MinutesToLondonOpen(now_utc);
      features[k++] = 9999.0;                // mins_to_news_high (gated separately)
      features[k++] = AsiaRangeWidthAtLondon();
      features[k++] = ADR14Norm();

      // cross-asset snapshot
      double dxy, spx, xau, oil, ust2y;
      LoadCrossSnapshot(dxy, spx, xau, oil, ust2y);
      features[k++] = dxy;
      features[k++] = spx;
      features[k++] = xau;
      features[k++] = oil;
      features[k++] = ust2y;

      // slow factors
      double cot, carry, ppp, mom;
      LoadSlowFactors(cot, carry, ppp, mom);
      features[k++] = cot;
      features[k++] = carry;
      features[k++] = ppp;
      features[k++] = mom;

      // custom indicators (optional)
      features[k++] = ReadSRDistancePips();
      features[k++] = (double)ReadCandleRejectFlag();
      features[k++] = (double)ReadDivergenceFlag();
      features[k++] = ReadHarmonicPRZProximity();

      // intents
      features[k++] = (double)intent_breakout;
      features[k++] = (double)intent_trend;
      features[k++] = (double)intent_squeeze;

      return true;
   }

private:
   // -------- helpers
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
         if(hi>0 && lo>0){ sum += MathPow(MathLog(hi/lo),2.0); cnt++; }
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
      if(hi<=lo || hi<=0 || lo<=0) return 0.0;
      double mid = (hi+lo)/2.0, range = hi-lo;
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
      double sum=0; for(int i=1;i<=w;i++) sum += (double)iVolume(m_symbol, m_tf, i);
      return (w>0 ? sum / (double)w : 0.0);
   }

   double OFIProxy(const int w)
   {
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
      // 0=Asia,1=London,2=NY,3=Overlap
      int off = LondonOffsetMinutes(utc_now);
      datetime london = utc_now + (datetime)(off*60);
      MqlDateTime dt; TimeToStruct(london, dt);
      int h = dt.hour;
      if(h>=7 && h<12) return 1;
      if(h>=12 && h<16) return 3;
      if(h>=16 && h<21) return 2;
      return 0;
   }

   int LondonOffsetMinutes(datetime utc_now)
   {
      // BST: last Sun Mar → last Sun Oct
      MqlDateTime dt; TimeToStruct(utc_now, dt);
      int year = dt.year;
      datetime dst_start = LastSundayOfMonth(year, 3, 1);
      datetime dst_end   = LastSundayOfMonth(year,10, 1);
      return ((utc_now >= dst_start) && (utc_now < dst_end)) ? 60 : 0;
   }

   datetime LastSundayOfMonth(const int year, const int month, const int hourUTC)
   {
      int mdays[12] = {31,28,31,30,31,30,31,31,30,31,30,31};
      bool leap = ((year%4==0 && year%100!=0) || (year%400==0));
      if(leap) mdays[1]=29;
      MqlDateTime dt; dt.year=year; dt.mon=month; dt.hour=hourUTC; dt.min=0; dt.sec=0;
      for(int day=mdays[month-1]; day>=25; day--){
         dt.day=day; datetime tt=StructToTime(dt);
         if(TimeDayOfWeek(tt)==0) return tt;
      }
      dt.day=mdays[month-1]; return StructToTime(dt);
   }

   double MinutesToLondonOpen(const datetime utc_now)
   {
      int off = LondonOffsetMinutes(utc_now);
      datetime london = utc_now + (datetime)(off*60);
      MqlDateTime d; TimeToStruct(london, d);
      MqlDateTime open = d; open.hour=7; open.min=0; open.sec=0;
      datetime t_open = StructToTime(open);
      // explicit cast eliminates warning
      return (double)((long)(t_open - london))/60.0;
   }

   double AsiaRangeWidthAtLondon()
   {
      int off = LondonOffsetMinutes(TimeGMT());
      datetime now_london = TimeGMT() + (datetime)(off*60);
      MqlDateTime d; TimeToStruct(now_london, d);
      MqlDateTime s = d; s.hour=0; s.min=0; s.sec=0; datetime start = StructToTime(s) - 24*60*60;
      MqlDateTime e = d; e.hour=6; e.min=59; e.sec=0; datetime end   = StructToTime(e) - 24*60*60;

      double hi= -DBL_MAX, lo= DBL_MAX;
      for(int i=1;i<=200;i++){
         datetime t = iTime(m_symbol, PERIOD_M15, i);
         if(t==0) break;
         datetime t_london = t + (datetime)(off*60);
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
      // simple ADR14 / ADR60 ratio (means)
      double sum14=0.0, sum60=0.0; int c14=0, c60=0;
      for(int i=1;i<=14;i++){ double hi=iHigh(m_symbol, PERIOD_D1, i), lo=iLow(m_symbol, PERIOD_D1, i); if(hi>0 && lo>0){ sum14+=(hi-lo); c14++; } }
      for(int i=1;i<=60;i++){ double hi=iHigh(m_symbol, PERIOD_D1, i), lo=iLow(m_symbol, PERIOD_D1, i); if(hi>0 && lo>0){ sum60+=(hi-lo); c60++; } }
      double adr14 = (c14>0? sum14/(double)c14 : 0.0);
      double adr60 = (c60>0? sum60/(double)c60 : 1.0);
      if(adr60<=0.0) adr60=1.0;
      return adr14/adr60;
   }

   // ---- CSV helpers (robust: read line & StringSplit) ----
   bool ReadFirstDataRow(const string file, string &line_out)
   {
      int h = FileOpen(file, FILE_READ|FILE_TXT|FILE_ANSI);
      if(h==INVALID_HANDLE) return false;
      string header = FileReadString(h);  // header line
      if(FileIsEnding(h)){ FileClose(h); return false; }
      line_out = FileReadString(h);
      FileClose(h);
      return (line_out!="");
   }

   static double ToDoubleSafe(const string s){ return StringToDouble(StringTrim(s)); }

   void LoadCrossSnapshot(double &dxy, double &spx, double &xau, double &oil, double &ust2y)
   {
      dxy=spx=xau=oil=ust2y=0.0;
      string line;
      if(!ReadFirstDataRow("Files\\cross_snapshot.csv", line)) return;
      string parts[]; int n = StringSplit(line, ',', parts);
      if(n>=5){
         dxy  = ToDoubleSafe(parts[0]);
         spx  = ToDoubleSafe(parts[1]);
         xau  = ToDoubleSafe(parts[2]);
         oil  = ToDoubleSafe(parts[3]);
         ust2y= ToDoubleSafe(parts[4]);
      }
   }

   double LoadSpreadPercentile()
   {
      int h = FileOpen("Files\\spread_percentiles.csv", FILE_READ|FILE_TXT|FILE_ANSI);
      if(h==INVALID_HANDLE) return 50.0;
      string header = FileReadString(h);
      while(!FileIsEnding(h)){
         string row = FileReadString(h);
         if(row=="") continue;
         string parts[]; int n = StringSplit(row, ',', parts);
         if(n<2) continue;
         if(parts[0]==m_symbol){ double v = ToDoubleSafe(parts[1]); FileClose(h); return v; }
      }
      FileClose(h);
      return 50.0;
   }

   void LoadSlowFactors(double &cot, double &carry, double &ppp, double &mom)
   {
      cot=carry=ppp=mom=0.0;
      int h = FileOpen("Files\\slow_factors.csv", FILE_READ|FILE_TXT|FILE_ANSI);
      if(h==INVALID_HANDLE) return;
      string header = FileReadString(h);
      while(!FileIsEnding(h)){
         string row = FileReadString(h);
         if(row=="") continue;
         string parts[]; int n = StringSplit(row, ',', parts);
         if(n<5) continue;
         if(parts[0]==m_symbol){
            cot   = ToDoubleSafe(parts[1]);
            carry = ToDoubleSafe(parts[2]);
            ppp   = ToDoubleSafe(parts[3]);
            mom   = ToDoubleSafe(parts[4]);
            break;
         }
      }
      FileClose(h);
   }

   // ---- optional custom indicators (safe fallbacks) ----
   double ReadSRDistancePips()
   {
      int h = iCustom(m_symbol, m_tf, "FXSuite/AutoSR_Levels.ex5");
      if(h==INVALID_HANDLE) return 0.0;
      double buf[]; ArraySetAsSeries(buf,true);
      if(CopyBuffer(h,0,1,1,buf)<=0) return 0.0;
      return buf[0];
   }
   int ReadCandleRejectFlag()
   {
      int h = iCustom(m_symbol, m_tf, "FXSuite/CandlePatterns.ex5");
      if(h==INVALID_HANDLE) return 0;
      double buf[]; ArraySetAsSeries(buf,true);
      if(CopyBuffer(h,0,1,1,buf)<=0) return 0;
      return (int)buf[0];
   }
   int ReadDivergenceFlag()
   {
      int h = iCustom(m_symbol, m_tf, "FXSuite/DivergenceDetector.ex5");
      if(h==INVALID_HANDLE) return 0;
      double buf[]; ArraySetAsSeries(buf,true);
      if(CopyBuffer(h,0,1,1,buf)<=0) return 0;
      return (int)buf[0];
   }
   double ReadHarmonicPRZProximity()
   {
      int h = iCustom(m_symbol, m_tf, "FXSuite/HarmonicScanner.ex5");
      if(h==INVALID_HANDLE) return 0.0;
      double buf[]; ArraySetAsSeries(buf,true);
      if(CopyBuffer(h,0,1,1,buf)<=0) return 0.0;
      return buf[0];
   }
};