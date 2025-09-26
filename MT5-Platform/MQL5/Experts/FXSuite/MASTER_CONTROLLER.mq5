// MQL5/Experts/FXSuite/MASTER_CONTROLLER.mq5
#property strict
#property description "FXSuite Master Controller — orchestrator with regime, portfolio, state."

#include <FXSuite/ML/FeatureExtractor.mqh>
#include <FXSuite/ML/InferenceBridge.mqh>
#include <FXSuite/Filters/NewsCalendar.mqh>
#include <FXSuite/Filters/RegimeDetector.mqh>
#include <FXSuite/Core/OrderManager.mqh>
#include <FXSuite/Core/RiskManager.mqh>
#include <FXSuite/Core/PortfolioControl.mqh>
#include <FXSuite/Core/StateManager.mqh>
#include <FXSuite/Core/ConfigReloader.mqh>

input ENUM_TIMEFRAMES InpTF = PERIOD_M15;
input double InpRiskPct       = 0.005;  // 0.5% base risk/trade
input double InpMinPW         = 0.58;   // base p_win threshold
input int    InpSL_Pips       = 15;
input int    InpTP_Pips       = 30;
input bool   InpEnableTrades  = false;
input string InpInferURL      = "http://127.0.0.1:8081/infer";

// portfolio guardrails
input double InpMaxPortfolioHeat = 0.06;  // 6%
input double InpDailyLossLimit   = 0.03;  // 3%
input int    InpMaxPositions     = 12;

// config hot reload (optional)
input string InpConfigPath       = "Files\\FXSuite_Config.json";

CFeatureExtractor *g_feat;
CInferenceBridge  *g_infer;
CNewsCalendar     *g_news;
CRegimeDetector   *g_regime;
COrderManager     *g_om;
CRiskManager      *g_risk;
CPortfolioControl *g_port;
CStateManager     *g_state;
CConfigReloader   *g_cfg;

int       g_ema50h = INVALID_HANDLE;
int       g_ema200h= INVALID_HANDLE;
datetime  g_lastBar=0;

// ---------- helpers ----------
double PipValue()
{
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (dg==3 || dg==5) ? pt*10.0 : pt;
}
double SLPriceFromPips(ENUM_ORDER_TYPE side, double pips)
{
   MqlTick t; SymbolInfoTick(_Symbol, t);
   double pip = PipValue();
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(side==ORDER_TYPE_BUY)  return NormalizeDouble(t.bid - pips*pip, dg);
   if(side==ORDER_TYPE_SELL) return NormalizeDouble(t.ask + pips*pip, dg);
   return 0.0;
}
double TPPriceFromPips(ENUM_ORDER_TYPE side, double pips)
{
   MqlTick t; SymbolInfoTick(_Symbol, t);
   double pip = PipValue();
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(side==ORDER_TYPE_BUY)  return NormalizeDouble(t.bid + pips*pip, dg);
   if(side==ORDER_TYPE_SELL) return NormalizeDouble(t.ask - pips*pip, dg);
   return 0.0;
}

// Compute minutes to next HIGH-impact event from a simple CSV:
// expected columns: utc_ts,impact,currency,title,...
double MinutesToNextHighCSV(const string path, const datetime now_utc, const string symbol)
{
   string ccy = StringSubstr(symbol,0,3);
   int h = FileOpen(path, FILE_READ|FILE_CSV|FILE_ANSI);
   if(h==INVALID_HANDLE) return 9999.0;
   // skip header (assume first 4 cells)
   for(int i=0;i<4 && !FileIsEnding(h); ++i) FileReadString(h);

   double best_min = 9999.0;
   while(!FileIsEnding(h)){
      string ts_s   = FileReadString(h);
      string impact = FileReadString(h);
      string cur    = FileReadString(h);
      string title  = FileReadString(h);
      if(ts_s=="" || impact=="" || cur==""){ continue; }
      datetime ts = (datetime)StringToInteger(ts_s);
      if(ts >= now_utc && StringFind(StringToUpper(impact), "HIGH")>=0 && (cur==ccy || cur=="ALL")){
         double mins = (double)((long)(ts - now_utc))/60.0;
         if(mins < best_min) best_min = mins;
      }
   }
   FileClose(h);
   if(best_min<0.0) best_min=0.0;
   return best_min;
}

// ---------- EA lifecycle ----------
int OnInit()
{
   g_feat  = new CFeatureExtractor(_Symbol, InpTF);
   g_infer = new CInferenceBridge();
   g_infer.SetURL(InpInferURL);
   g_news  = new CNewsCalendar("calendar.csv", 2, 45, 45);
   g_regime= new CRegimeDetector(_Symbol, InpTF);
   g_om    = new COrderManager();
   g_risk  = new CRiskManager(InpRiskPct);
   g_port  = new CPortfolioControl();
   g_state = new CStateManager();
   g_cfg   = new CConfigReloader(InpConfigPath);

   if(!g_feat.Init()){ Print("FeatureExtractor init failed."); return(INIT_FAILED); }
   if(!g_regime.Init()){ Print("RegimeDetector init failed."); return(INIT_FAILED); }

   g_port.Configure(InpMaxPortfolioHeat, InpDailyLossLimit, InpMaxPositions);
   g_port.OnStartup();
   g_state.Reconcile();

   g_ema50h  = iMA(_Symbol, InpTF, 50, 0, MODE_EMA, PRICE_CLOSE);
   g_ema200h = iMA(_Symbol, InpTF, 200,0, MODE_EMA, PRICE_CLOSE);
   if(g_ema50h==INVALID_HANDLE || g_ema200h==INVALID_HANDLE){
      Print("iMA handle(s) failed."); return(INIT_FAILED);
   }

   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   delete g_feat; delete g_infer; delete g_news; delete g_regime;
   delete g_om; delete g_risk; delete g_port; delete g_state; delete g_cfg;
}

void OnTimer()
{
   // daily rollover / config polling
   g_port.OnHeartbeat();
   g_cfg.Poll();

   // new bar on selected TF
   datetime bt = iTime(_Symbol, InpTF, 0);
   if(bt==0 || bt==g_lastBar) return;
   g_lastBar = bt;

   // circuit breaker
   string cb_msg;
   if(g_port.CircuitBreakerTriggered(cb_msg)){
      Comment("CIRCUIT BREAKER: ", cb_msg);
      return;
   }

   // news blackout
   if(g_news.IsBlackout(_Symbol, TimeGMT())){
      Comment("News blackout; skipping bar.");
      return;
   }

   // features
   double f[64]; ArrayInitialize(f,0.0);
   int intent_breakout=0, intent_trend=1, intent_squeeze=0;
   if(!g_feat.Build(f, intent_breakout, intent_trend, intent_squeeze)){
      Comment("Feature build failed; skipping."); return;
   }

   // minutes-to-next-high into feature[21]
   f[21] = MinutesToNextHighCSV("Files\\calendar.csv", TimeGMT(), _Symbol);

   // inference
   string corr = StringFormat("%s-%I64d", _Symbol, (long)bt);
   double pwin=0.0; int lms=0;
   if(!g_infer.Predict(f, corr, pwin, lms)){ Comment("Inference failed; skipping."); return; }

   // regime
   RegimeProfile rp; if(!g_regime.Evaluate(rp)){ Comment("Regime eval failed; skip"); return; }
   double thr = InpMinPW * rp.pwin_threshold_mult;

   // trend filter
   double ema50buf[]; ArraySetAsSeries(ema50buf, true);
   double ema200buf[]; ArraySetAsSeries(ema200buf, true);
   if(CopyBuffer(g_ema50h,0,1,1,ema50buf)<=0 || CopyBuffer(g_ema200h,0,1,1,ema200buf)<=0) return;
   double ema50=ema50buf[0], ema200=ema200buf[0];

   Comment(StringFormat("p_win=%.3f thr=%.3f regime=%d lot_mult=%.2f model=%s fv=%s lat=%dms",
           pwin,thr,(int)rp.regime,rp.lot_mult,g_infer.ModelId(),g_infer.FeaturesVersion(),lms));

   if(!InpEnableTrades) return;
   if(pwin < thr) return;

   // base lots from SL distance
   double base_lots = g_risk.CalcLotBySL(_Symbol, (double)InpSL_Pips);
   if(base_lots<=0.0){ Print("Lot calc <=0; skip"); return; }

   // probability → size (gentle)
   double rr = (double)InpTP_Pips / (double)InpSL_Pips; if(rr<=0.0) rr=1.0;
   double edge = pwin - (1.0-pwin)/rr;
   double prob_mult = MathMax(0.50, MathMin(1.50, 0.25 + 0.5*edge/0.10));

   double lots = base_lots * rp.lot_mult * prob_mult;

   // portfolio guardrails
   string reason;
   double assumed_risk_pct = InpRiskPct;
   if(!g_port.CanOpenNewPosition(_Symbol, assumed_risk_pct, reason)){
      Print("Portfolio blocked new trade: ", reason);
      return;
   }

   // side by EMA
   OrderRecord rec;
   if(ema50 > ema200){
      double sl = SLPriceFromPips(ORDER_TYPE_BUY,  (double)InpSL_Pips);
      double tp = TPPriceFromPips(ORDER_TYPE_BUY,  (double)InpTP_Pips);
      g_state.RegisterSignal(corr, _Symbol, +1);
      if(g_om.SendMarket(_Symbol, ORDER_TYPE_BUY, lots, sl, tp, corr, rec)){
         g_state.OnOrderPlaced(corr, rec.ticket);
         PrintFormat("BUY lots=%.2f pwin=%.3f ticket=%I64u", lots, pwin, rec.ticket);
      }
   } else if(ema50 < ema200){
      double sl = SLPriceFromPips(ORDER_TYPE_SELL, (double)InpSL_Pips);
      double tp = TPPriceFromPips(ORDER_TYPE_SELL, (double)InpTP_Pips);
      g_state.RegisterSignal(corr, _Symbol, -1);
      if(g_om.SendMarket(_Symbol, ORDER_TYPE_SELL, lots, sl, tp, corr, rec)){
         g_state.OnOrderPlaced(corr, rec.ticket);
         PrintFormat("SELL lots=%.2f pwin=%.3f ticket=%I64u", lots, pwin, rec.ticket);
      }
   }
}
