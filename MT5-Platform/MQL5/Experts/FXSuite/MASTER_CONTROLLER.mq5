// MT5-Platform/MQL5/Experts/FXSuite/MASTER_CONTROLLER.mq5
#property strict
#property description "FXSuite Master Controller — thin-slice integration EA."

#include <FXSuite/ML/FeatureExtractor.mqh>
#include <FXSuite/ML/InferenceBridge.mqh>
#include <FXSuite/Filters/NewsCalendar.mqh>
#include <FXSuite/Core/OrderManager.mqh>
#include <FXSuite/Core/RiskManager.mqh>

input ENUM_TIMEFRAMES InpTF = PERIOD_M15;
input double InpRiskPct     = 0.005;     // 0.5% per trade
input double InpMinPW       = 0.58;      // min p_win to trade
input int    InpSL_Pips     = 15;
input int    InpTP_Pips     = 30;
input bool   InpEnableTrades= false;     // start as paper mode
input string InpInferURL    = "http://127.0.0.1:8081/infer";

CFeatureExtractor *g_feat;
CInferenceBridge  *g_infer;
CNewsCalendar     *g_news;
COrderManager     *g_om;
CRiskManager      *g_risk;

int       g_ema50h = INVALID_HANDLE;
int       g_ema200h= INVALID_HANDLE;
datetime  g_lastBar=0;

int OnInit()
{
   g_feat  = new CFeatureExtractor(_Symbol, InpTF);
   g_infer = new CInferenceBridge();
   g_infer.SetURL(InpInferURL);
   g_news  = new CNewsCalendar("calendar.csv", 2, 45, 45);
   g_om    = new COrderManager();
   g_risk  = new CRiskManager(InpRiskPct);

   if(!g_feat.Init()){
      Print("FeatureExtractor init failed."); return(INIT_FAILED);
   }

   // EMA handles (MQL5 uses handles + CopyBuffer)
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
   delete g_feat; delete g_infer; delete g_news; delete g_om; delete g_risk;
}

void OnTimer()
{
   // New closed bar check on chosen TF
   datetime bt = iTime(_Symbol, InpTF, 0);
   if(bt==0 || bt==g_lastBar) return;
   g_lastBar = bt;

   // News blackout
   if(g_news.IsBlackout(_Symbol, TimeGMT())){
      Comment("News blackout; skipping bar.");
      return;
   }

   double f[64]; ArrayInitialize(f, 0.0);
   int intent_breakout=0, intent_trend=1, intent_squeeze=0;

   if(!g_feat.Build(f, intent_breakout, intent_trend, intent_squeeze)){
      Comment("Feature build failed; skipping.");
      return;
   }

   // Inference
   string corr = StringFormat("%s-%I64d", _Symbol, (long)bt);
   double pwin=0.0; int lms=0;
   if(!g_infer.Predict(f, corr, pwin, lms)){
      Comment("Inference failed; skipping."); return;
   }

   // EMA values from handles (closed bar = shift 1)
   double ema50buf[]; ArraySetAsSeries(ema50buf, true);
   double ema200buf[]; ArraySetAsSeries(ema200buf, true);
   if(CopyBuffer(g_ema50h,  0, 1, 1, ema50buf)<=0) return;
   if(CopyBuffer(g_ema200h, 0, 1, 1, ema200buf)<=0) return;
   double ema50  = ema50buf[0];
   double ema200 = ema200buf[0];

   Comment(StringFormat("p_win=%.3f  model=%s  feat_ver=%s  lat=%dms  EMA50=%.5f  EMA200=%.5f",
            pwin, g_infer.ModelId(), g_infer.FeaturesVersion(), lms, ema50, ema200));

   if(!InpEnableTrades) return;
   if(pwin < InpMinPW)  return;

   // risk sizing
   double lots = g_risk.CalcLotBySL(_Symbol, (double)InpSL_Pips);
   if(lots <= 0.0){ Print("Lot calc <=0; skip."); return; }

   if(ema50 > ema200){
      // BUY
      double sl = SLPriceFromPips(ORDER_TYPE_BUY,  (double)InpSL_Pips);
      double tp = TPPriceFromPips(ORDER_TYPE_BUY,  (double)InpTP_Pips);
      OrderRecord rec;
      bool ok = g_om.SendMarket(_Symbol, ORDER_TYPE_BUY, lots, sl, tp, corr, rec);
      if(ok) PrintFormat("BUY lot=%.2f pwin=%.3f ticket=%I64u", lots, pwin, rec.ticket);
   } else if(ema50 < ema200){
      // SELL
      double sl = SLPriceFromPips(ORDER_TYPE_SELL, (double)InpSL_Pips);
      double tp = TPPriceFromPips(ORDER_TYPE_SELL, (double)InpTP_Pips);
      OrderRecord rec;
      bool ok = g_om.SendMarket(_Symbol, ORDER_TYPE_SELL, lots, sl, tp, corr, rec);
      if(ok) PrintFormat("SELL lot=%.2f pwin=%.3f ticket=%I64u", lots, pwin, rec.ticket);
   }
}

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
