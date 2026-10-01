#property strict
#property description "FXSuite Omega controller — legacy-safe institutional upgrade branch."

#include <FXSuite/ML/FeatureExtractor.mqh>
#include <FXSuite/ML/InferenceBridge.mqh>
#include <FXSuite/ML/MTFConfidence.mqh>
#include <FXSuite/Filters/NewsCalendar.mqh>
#include <FXSuite/Filters/RegimeDetector.mqh>
#include <FXSuite/Filters/RolloverGuard.mqh>
#include <FXSuite/Core/BuildFingerprint.mqh>
#include <FXSuite/Core/OrderManager.mqh>
#include <FXSuite/Core/RiskManager.mqh>
#include <FXSuite/Core/PortfolioControl.mqh>
#include <FXSuite/Core/StateManager.mqh>
#include <FXSuite/Core/ConfigReloader.mqh>
#include <FXSuite/Risk/ConfidenceSizer.mqh>
#include <FXSuite/Risk/CVaRTracker.mqh>
#include <FXSuite/Risk/DynamicSizer.mqh>
#include <FXSuite/Position/ProfitProtector.mqh>
#include <FXSuite/Treasury/CostModel.mqh>
#include <FXSuite/Telemetry/NDJSONLogger.mqh>

input ENUM_TIMEFRAMES InpTF=PERIOD_M15;
input double InpRiskPct=0.005;
input double InpMinPW=0.58;
input int InpSL_Pips=15;
input int InpTP_Pips=30;
input bool InpEnableTrades=false;

// Execution retry/budget controls. Legacy retry defaults are preserved.
input int InpExecMaxRetries=2;
input int InpExecBackoffMs=75;
input bool InpEnableExecutionBudget=false;
input double InpMaxSpreadPips=2.0;
input double InpSlippageBudgetPips=0.50;
input string InpInferURL="http://127.0.0.1:8081/infer";
input int InpFeaturesVer=1;

input bool InpEnableOmegaRiskPolicy=false;
input double InpMaxPortfolioHeat=0.06;
input double InpDailyLossLimit=0.03;
input double InpWeeklyLossLimit=0.07;
input double InpPeakLossLimit=0.12;
input double InpSoftHaltFraction=0.70;
input int InpMaxPositions=12;
// 0 preserves the current legacy-conservative behavior of reusing portfolio heat.
input double InpMaxMarginToEquity=0.0;

input bool InpEnableOmegaSizer=false;
input double InpKellyMax=0.15;
input double InpCVaRLimitR=1.50;

// NEW_BEHAVIOR treasury/cost gate. Default off.
input bool InpEnableCostGate=false;
input double InpMaxAllInCostR=0.15;
input double InpExpectedSlippagePips=0.20;
input double InpRoundTripCommissionPerLot=0.0;
input int InpExpectedHoldNights=0;
input bool InpCostRequireKnownSwap=false;

input double InpBE_TriggerPctEquity=0.0;
input double InpBE_TriggerR=1.0;
input double InpBE_OffsetPips=0.2;
input bool InpBE_UseOR=true;

input bool InpEnableATRTrail=false;
input double InpTrailStartR=1.5;
input double InpTrailATRMult=2.0;

input bool InpEnableConformalGate=false;
input double InpConformalMaxWidth=0.25;

// NEW_BEHAVIOR: explicit M15/H1/H4/D1 fusion. Default off.
input bool InpEnableMTF=false;
input bool InpMTFBlockHigherTFDisagreement=true;
input string InpMTFWeightsPath="mtf_weights.csv";
input bool InpEnableRolloverGuard=false;
input bool InpStrictNewsGuard=false;
input int InpNewsStatusMaxAgeSec=600;

// NEW_BEHAVIOR. Default false preserves legacy local operation.
input bool InpRequireLiveApproval=false;

input string InpConfigPath="Files\\FXSuite_Config.json";

CFeatureExtractor *g_feat=NULL;
CFeatureExtractor *g_feat_h1=NULL;
CFeatureExtractor *g_feat_h4=NULL;
CFeatureExtractor *g_feat_d1=NULL;
CInferenceBridge *g_infer=NULL;
CMTFConfidence *g_mtf=NULL;
CNewsCalendar *g_news=NULL;
CRegimeDetector *g_regime=NULL;
CRolloverGuard *g_roll=NULL;
COrderManager *g_om=NULL;
CRiskManager *g_risk=NULL;
CPortfolioControl *g_port=NULL;
CStateManager *g_state=NULL;
CConfigReloader *g_cfg=NULL;
CCVaRTracker *g_cvar=NULL;
CProfitProtector *g_profit=NULL;
CNDJSONLogger *g_log=NULL;

int g_ema50h=INVALID_HANDLE;
int g_ema200h=INVALID_HANDLE;
datetime g_last_bar=0;
int g_last_risk_state=-1;
datetime g_last_risk_log=0;
string g_bar_key="";
string g_cvar_path="FXSuite\\cvar_history.csv";

double PipValue()
{
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int dg=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   return ((dg==3 || dg==5)?pt*10.0:pt);
}

double CurrentSpreadPips()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return 9999.0;
   double pip=PipValue();
   if(pip<=0.0) return 9999.0;
   return MathMax(0.0,(tick.ask-tick.bid)/pip);
}

int SlippageBudgetPoints()
{
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double pip=PipValue();
   if(point<=0.0 || pip<=0.0) return 0;
   return (int)MathCeil(MathMax(0.0,InpSlippageBudgetPips)*pip/point);
}

double SLPriceFromPips(const ENUM_ORDER_TYPE side,const double pips)
{
   MqlTick t;
   if(!SymbolInfoTick(_Symbol,t)) return 0.0;
   double pip=PipValue();
   int dg=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   if(side==ORDER_TYPE_BUY) return NormalizeDouble(t.ask-pips*pip,dg);
   if(side==ORDER_TYPE_SELL) return NormalizeDouble(t.bid+pips*pip,dg);
   return 0.0;
}

double TPPriceFromPips(const ENUM_ORDER_TYPE side,const double pips)
{
   MqlTick t;
   if(!SymbolInfoTick(_Symbol,t)) return 0.0;
   double pip=PipValue();
   int dg=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   if(side==ORDER_TYPE_BUY) return NormalizeDouble(t.ask+pips*pip,dg);
   if(side==ORDER_TYPE_SELL) return NormalizeDouble(t.bid-pips*pip,dg);
   return 0.0;
}

double MinutesToNextHighCSV(const string path,const datetime now_utc,const string symbol)
{
   string base=StringSubstr(symbol,0,3);
   string quote=StringSubstr(symbol,StringLen(symbol)-3,3);
   StringToUpper(base);
   StringToUpper(quote);

   int h=FileOpen(path,FILE_READ|FILE_CSV|FILE_ANSI,',');
   if(h==INVALID_HANDLE) return 9999.0;

   for(int i=0;i<4 && !FileIsEnding(h);++i) FileReadString(h);

   double best=9999.0;
   while(!FileIsEnding(h))
   {
      string ts_s=FileReadString(h);
      string impact=FileReadString(h);
      string ccy=FileReadString(h);
      string title=FileReadString(h);

      string imp=impact;
      StringToUpper(imp);
      StringToUpper(ccy);
      if(ts_s=="" || StringFind(imp,"HIGH")<0) continue;

      datetime ts=(datetime)StringToInteger(ts_s);
      if(ts>=now_utc && (ccy==base || ccy==quote || ccy=="ALL"))
         best=MathMin(best,(double)(ts-now_utc)/60.0);
   }
   FileClose(h);
   return MathMax(0.0,best);
}

bool LiveApprovalOK(string &reason)
{
   if(FXSUITE_BUILD_FINGERPRINT=="UNARMED")
   {
      reason="build fingerprint is UNARMED";
      return false;
   }

   int h=FileOpen("FXSuite\\live_approval.csv",FILE_READ|FILE_CSV|FILE_ANSI,',');
   if(h==INVALID_HANDLE)
   {
      reason="live_approval.csv missing";
      return false;
   }

   for(int i=0;i<3 && !FileIsEnding(h);++i) FileReadString(h);

   string approved=FileReadString(h);
   string fingerprint=FileReadString(h);
   string created_utc=FileReadString(h);
   FileClose(h);

   if(approved!="1")
   {
      reason="live approval flag is not 1";
      return false;
   }

   if(fingerprint!=FXSUITE_BUILD_FINGERPRINT)
   {
      reason="live approval fingerprint mismatch";
      return false;
   }

   reason="approved";
   return true;
}

bool InferForTF(CFeatureExtractor *extractor,
                const ENUM_TIMEFRAMES tf,
                const string corr_id,
                const double minutes_news,
                double &p_cal,
                double &p_raw,
                double &width,
                int &latency_ms)
{
   if(extractor==NULL) return false;

   double features[64];
   int intent_breakout=0;
   int intent_trend=1;
   int intent_squeeze=0;

   if(!extractor.Build(features,intent_breakout,intent_trend,intent_squeeze))
      return false;

   int news_index=(InpFeaturesVer<=1 ? 21 : 22);
   features[news_index]=minutes_news;

   if(!g_infer.Predict(features,corr_id,p_cal,latency_ms,_Symbol,tf,InpFeaturesVer))
      return false;

   p_raw=g_infer.RawP();
   width=g_infer.ConformalWidth();
   return true;
}

int OnInit()
{
   FolderCreate("FXSuite");

   g_bar_key=StringFormat("FXSuite.lastbar.%I64d.%s.%d",
                          (long)AccountInfoInteger(ACCOUNT_LOGIN),_Symbol,(int)InpTF);
   if(GlobalVariableCheck(g_bar_key))
      g_last_bar=(datetime)GlobalVariableGet(g_bar_key);

   if(InpEnableTrades && InpRequireLiveApproval)
   {
      string approval_reason;
      if(!LiveApprovalOK(approval_reason))
      {
         Print("Live approval blocked initialization: ",approval_reason);
         return INIT_FAILED;
      }
   }

   if(InpEnableMTF && InpTF!=PERIOD_M15)
   {
      Print("MTF mode requires InpTF=PERIOD_M15.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_feat=new CFeatureExtractor(_Symbol,InpTF,InpFeaturesVer);
   g_infer=new CInferenceBridge();
   g_infer.SetURL(InpInferURL);
   g_news=new CNewsCalendar("calendar.csv",2,45,45,false);
   g_regime=new CRegimeDetector(_Symbol,InpTF);
   g_roll=new CRolloverGuard();
   g_om=new COrderManager();
   int deviation_points=(InpEnableExecutionBudget ? SlippageBudgetPoints() : 15);
   g_om.ConfigureRetry(InpExecMaxRetries,InpExecBackoffMs,deviation_points);
   g_risk=new CRiskManager(InpRiskPct);
   g_port=new CPortfolioControl();
   g_state=new CStateManager();
   g_cfg=new CConfigReloader(InpConfigPath);
   g_cvar=new CCVaRTracker(500);
   g_log=new CNDJSONLogger("FXSuite\\events.ndjson");
   g_profit=new CProfitProtector(g_om);

   if(!g_feat.Init() || !g_regime.Init()) return INIT_FAILED;

   if(InpEnableMTF)
   {
      g_feat_h1=new CFeatureExtractor(_Symbol,PERIOD_H1,InpFeaturesVer);
      g_feat_h4=new CFeatureExtractor(_Symbol,PERIOD_H4,InpFeaturesVer);
      g_feat_d1=new CFeatureExtractor(_Symbol,PERIOD_D1,InpFeaturesVer);
      g_mtf=new CMTFConfidence();

      if(!g_feat_h1.Init() || !g_feat_h4.Init() || !g_feat_d1.Init())
      {
         Print("MTF feature extractor initialization failed.");
         return INIT_FAILED;
      }

      g_mtf.LoadWeights(InpMTFWeightsPath);
   }

   if(InpEnableOmegaRiskPolicy)
      g_port.ConfigureOmega(InpMaxPortfolioHeat,InpDailyLossLimit,InpWeeklyLossLimit,
                            InpPeakLossLimit,InpMaxPositions,InpSoftHaltFraction);
   else
      g_port.Configure(InpMaxPortfolioHeat,InpDailyLossLimit,InpMaxPositions);

   if(InpMaxMarginToEquity>0.0)
      g_port.ConfigureMarginHeat(InpMaxMarginToEquity);

   g_port.OnStartup();
   g_state.Reconcile();
   g_cvar.Load(g_cvar_path);

   g_profit.ConfigureBE(InpBE_TriggerPctEquity,InpBE_TriggerR,InpBE_OffsetPips,InpBE_UseOR);
   g_profit.ConfigureATR(InpEnableATRTrail,InpTF,InpTrailStartR,InpTrailATRMult);

   g_ema50h=iMA(_Symbol,InpTF,50,0,MODE_EMA,PRICE_CLOSE);
   g_ema200h=iMA(_Symbol,InpTF,200,0,MODE_EMA,PRICE_CLOSE);
   if(g_ema50h==INVALID_HANDLE || g_ema200h==INVALID_HANDLE) return INIT_FAILED;

   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();

   if(g_cvar!=NULL)
      g_cvar.Save(g_cvar_path);

   if(g_ema50h!=INVALID_HANDLE) IndicatorRelease(g_ema50h);
   if(g_ema200h!=INVALID_HANDLE) IndicatorRelease(g_ema200h);

   delete g_profit;
   delete g_log;
   delete g_cvar;
   delete g_cfg;
   delete g_state;
   delete g_port;
   delete g_risk;
   delete g_om;
   delete g_roll;
   delete g_regime;
   delete g_news;
   delete g_mtf;
   delete g_feat_d1;
   delete g_feat_h4;
   delete g_feat_h1;
   delete g_infer;
   delete g_feat;
}

void LogRiskStateIfNeeded()
{
   double d,w,p;
   g_port.Drawdowns(d,w,p);
   string reason;
   ENUM_FXS_RISK_STATE state=g_port.State(reason);
   datetime now=TimeCurrent();

   if((int)state!=g_last_risk_state || g_last_risk_log==0 || now-g_last_risk_log>=60)
   {
      string label=(state==FXS_RISK_NORMAL?"NORMAL":
                   (state==FXS_RISK_SOFT_HALT?"SOFT_HALT":"HARD_HALT"));
      g_log.RiskState(label,d,w,p,g_port.SizeMultiplier(),reason);
      g_last_risk_state=(int)state;
      g_last_risk_log=now;
   }
}

void OnTimer()
{
   g_port.OnHeartbeat();
   g_cfg.Poll();
   g_profit.UpdateForSymbol(_Symbol);
   LogRiskStateIfNeeded();

   datetime bt=iTime(_Symbol,InpTF,0);
   if(bt==0 || bt==g_last_bar) return;

   g_last_bar=bt;
   GlobalVariableSet(g_bar_key,(double)g_last_bar);

   string cb;
   if(g_port.CircuitBreakerTriggered(cb))
   {
      Comment("CIRCUIT BREAKER: ",cb);
      return;
   }

   if(InpEnableExecutionBudget)
   {
      double spread_pips=CurrentSpreadPips();
      if(spread_pips>InpMaxSpreadPips)
      {
         g_log.ExecutionGuard(_Symbol,true,"spread_guard",
                              spread_pips,InpMaxSpreadPips,InpSlippageBudgetPips);
         Comment(StringFormat("Spread guard: %.2f > %.2f pips",
                              spread_pips,InpMaxSpreadPips));
         return;
      }
   }

   if(InpEnableRolloverGuard && g_roll.IsGuarded(TimeCurrent()))
   {
      g_log.RolloverGuard(_Symbol,true,TimeCurrent());
      Comment("Rollover guard");
      return;
   }

   if(InpStrictNewsGuard)
   {
      string news_health_reason;
      if(!g_news.HealthOK(TimeGMT(),InpNewsStatusMaxAgeSec,news_health_reason))
      {
         g_log.NewsGuard(_Symbol,true,news_health_reason,9999.0);
         Comment("News feed health gate: ",news_health_reason);
         return;
      }
   }

   double minutes_news=MinutesToNextHighCSV("calendar.csv",TimeGMT(),_Symbol);
   if(g_news.IsBlackout(_Symbol,TimeGMT()))
   {
      g_log.NewsGuard(_Symbol,true,"calendar_blackout",minutes_news);
      Comment("News blackout");
      return;
   }

   RegimeProfile rp;
   if(!g_regime.Evaluate(rp)) return;

   string corr=StringFormat("%s-%I64d",_Symbol,(long)bt);
   double p_eff=0.0;
   double p_raw_for_log=0.0;
   double conformal_width=0.0;
   double mtf_threshold_add=0.0;
   int latency_ms=0;

   if(!InpEnableMTF)
   {
      if(!InferForTF(g_feat,InpTF,corr,minutes_news,
                     p_eff,p_raw_for_log,conformal_width,latency_ms))
         return;
   }
   else
   {
      double p_m15=0.0,p_h1=0.0,p_h4=0.0,p_d1=0.0;
      double raw_m15=0.0,raw_h1=0.0,raw_h4=0.0,raw_d1=0.0;
      double width_m15=0.0,width_h1=0.0,width_h4=0.0,width_d1=0.0;
      int lat_m15=0,lat_h1=0,lat_h4=0,lat_d1=0;

      if(!InferForTF(g_feat,PERIOD_M15,corr+"-M15",minutes_news,
                     p_m15,raw_m15,width_m15,lat_m15)) return;
      if(!InferForTF(g_feat_h1,PERIOD_H1,corr+"-H1",minutes_news,
                     p_h1,raw_h1,width_h1,lat_h1)) return;
      if(!InferForTF(g_feat_h4,PERIOD_H4,corr+"-H4",minutes_news,
                     p_h4,raw_h4,width_h4,lat_h4)) return;
      if(!InferForTF(g_feat_d1,PERIOD_D1,corr+"-D1",minutes_news,
                     p_d1,raw_d1,width_d1,lat_d1)) return;

      double coherence=0.0;
      g_mtf.Blend(p_m15,p_h1,p_h4,p_d1,(int)rp.regime,minutes_news,
                  p_eff,coherence,mtf_threshold_add);

      g_log.MTFVector(_Symbol,p_m15,p_h1,p_h4,p_d1,p_eff,coherence);

      if(InpMTFBlockHigherTFDisagreement &&
         g_mtf.ShouldBlock(p_m15,p_h4,p_d1,coherence))
      {
         Comment("MTF higher-timeframe disagreement block");
         return;
      }

      p_raw_for_log=raw_m15;
      conformal_width=MathMax(MathMax(width_m15,width_h1),
                              MathMax(width_h4,width_d1));
      latency_ms=lat_m15+lat_h1+lat_h4+lat_d1;
   }

   double threshold=InpMinPW*rp.pwin_threshold_mult+mtf_threshold_add;
   bool conformal_block=(InpEnableConformalGate &&
                         conformal_width>InpConformalMaxWidth);

   g_log.CalibrationDecision(_Symbol,p_raw_for_log,p_eff,
                             conformal_width,InpConformalMaxWidth,
                             conformal_block);

   if(conformal_block)
   {
      Comment("Conformal width gate");
      return;
   }

   double ema50[],ema200[];
   ArraySetAsSeries(ema50,true);
   ArraySetAsSeries(ema200,true);
   if(CopyBuffer(g_ema50h,0,1,1,ema50)<=0 ||
      CopyBuffer(g_ema200h,0,1,1,ema200)<=0) return;

   Comment(StringFormat("p_eff=%.3f raw=%.3f thr=%.3f regime=%d model=%s fv=%s lat=%dms",
           p_eff,p_raw_for_log,threshold,(int)rp.regime,
           g_infer.ModelId(),g_infer.FeaturesVersion(),latency_ms));

   if(!InpEnableTrades || p_eff<threshold) return;

   if(InpRequireLiveApproval)
   {
      string approval_reason;
      if(!LiveApprovalOK(approval_reason))
      {
         Comment("Live approval invalid: ",approval_reason);
         return;
      }
   }

   ENUM_ORDER_TYPE side;
   if(ema50[0]>ema200[0]) side=ORDER_TYPE_BUY;
   else if(ema50[0]<ema200[0]) side=ORDER_TYPE_SELL;
   else return;

   double sl=SLPriceFromPips(side,(double)InpSL_Pips);
   double tp=TPPriceFromPips(side,(double)InpTP_Pips);
   if(sl<=0.0 || tp<=0.0) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   double entry=(side==ORDER_TYPE_BUY?tick.ask:tick.bid);

   double base_lots=g_risk.CalcLotByStopPrice(_Symbol,entry,sl);
   if(base_lots<=0.0) return;

   double rr=(double)InpTP_Pips/MathMax(1.0,(double)InpSL_Pips);
   double legacy_edge=p_eff-(1.0-p_eff)/rr;
   double legacy_mult=MathMax(0.50,MathMin(1.50,0.25+0.5*legacy_edge/0.10));
   double size_mult=legacy_mult;

   if(InpEnableOmegaSizer)
   {
      double conf=CConfidenceSizer::Multiplier(p_eff,rr,InpKellyMax);
      double cvar=g_cvar.SizeScaler(InpCVaRLimitR);
      double dd=g_port.SizeMultiplier();
      size_mult=CDynamicSizer::Combine(conf,cvar,dd,1.0);
   }

   double lots=base_lots*rp.lot_mult*size_mult;
   if(!g_om.NormalizeVolumeDown(_Symbol,lots)) return;

   FXSCostEstimate cost_estimate;
   if(CCostModel::Estimate(_Symbol,side,lots,
                           InpExpectedSlippagePips,
                           InpRoundTripCommissionPerLot,
                           InpExpectedHoldNights,
                           cost_estimate))
   {
      double actual_risk_money=CCostModel::RiskMoney(_Symbol,entry,sl,lots);
      double cost_r=(actual_risk_money>0.0 ?
                     cost_estimate.total_cost_money/actual_risk_money : 0.0);

      g_log.CostEstimate(_Symbol,
                         cost_estimate.spread_money,
                         cost_estimate.commission_money,
                         cost_estimate.slippage_money,
                         cost_estimate.swap_money,
                         cost_estimate.total_cost_money,
                         cost_r,
                         cost_estimate.swap_supported);

      if(InpEnableCostGate)
      {
         if(InpCostRequireKnownSwap &&
            InpExpectedHoldNights>0 &&
            !cost_estimate.swap_supported)
         {
            Comment("Cost gate: unsupported broker swap mode");
            return;
         }

         if(cost_r>InpMaxAllInCostR)
         {
            Comment(StringFormat("Cost gate: %.3fR > %.3fR",
                                 cost_r,InpMaxAllInCostR));
            return;
         }

         double cost_breakeven=(1.0+cost_r)/(1.0+rr);
         if(p_eff<MathMax(threshold,cost_breakeven))
         {
            Comment(StringFormat("Cost-adjusted EV gate: p=%.3f breakeven=%.3f",
                                 p_eff,cost_breakeven));
            return;
         }
      }
   }
   else if(InpEnableCostGate)
   {
      Comment("Cost gate: unable to estimate transaction costs");
      return;
   }

   string block_reason;
   if(!g_port.CanOpenNewPositionProjected(_Symbol,side,lots,entry,
                                          InpRiskPct*size_mult,block_reason))
   {
      Print("Portfolio blocked: ",block_reason);
      return;
   }

   string side_text=(side==ORDER_TYPE_BUY?"BUY":"SELL");
   g_log.TradeIntent(corr,_Symbol,side_text,lots,p_eff,sl,tp);
   g_state.RegisterSignal(corr,_Symbol,side==ORDER_TYPE_BUY?1:-1);

   OrderRecord rec;
   if(g_om.SendMarket(_Symbol,side,lots,sl,tp,corr,rec))
   {
      g_state.OnOrderPlaced(corr,rec.ticket);
      PrintFormat("ORDER %s lots=%.2f p=%.3f ticket=%I64u",
                  side_text,lots,p_eff,rec.ticket);
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0) return;
   if(!HistoryDealSelect(trans.deal)) return;

   ENUM_DEAL_ENTRY entry_type=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry_type!=DEAL_ENTRY_OUT && entry_type!=DEAL_ENTRY_OUT_BY) return;

   double gross=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
   double swap=HistoryDealGetDouble(trans.deal,DEAL_SWAP);
   double commission=HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   double pnl=gross+swap+commission;
   string symbol=HistoryDealGetString(trans.deal,DEAL_SYMBOL);
   ulong position_id=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   double deal_price=HistoryDealGetDouble(trans.deal,DEAL_PRICE);
   double deal_volume=HistoryDealGetDouble(trans.deal,DEAL_VOLUME);

   g_log.TradeClose(symbol,trans.deal,position_id,deal_price,deal_volume,
                    gross,commission,swap,pnl);

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_money=MathMax(1e-9,eq*InpRiskPct);
   g_cvar.AddR(pnl/risk_money);
   g_cvar.Save(g_cvar_path);
}
