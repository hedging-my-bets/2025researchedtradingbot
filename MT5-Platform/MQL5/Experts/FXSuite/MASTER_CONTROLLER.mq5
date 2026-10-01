#property strict
#property description "FXSuite Omega controller — legacy-safe institutional upgrade branch."

#include <FXSuite/ML/FeatureExtractor.mqh>
#include <FXSuite/ML/InferenceBridge.mqh>
#include <FXSuite/ML/MTFConfidence.mqh>
#include <FXSuite/Filters/NewsCalendar.mqh>
#include <FXSuite/Filters/RegimeDetector.mqh>
#include <FXSuite/Filters/RolloverGuard.mqh>
#include <FXSuite/Core/OrderManager.mqh>
#include <FXSuite/Core/RiskManager.mqh>
#include <FXSuite/Core/PortfolioControl.mqh>
#include <FXSuite/Core/StateManager.mqh>
#include <FXSuite/Core/ConfigReloader.mqh>
#include <FXSuite/Risk/ConfidenceSizer.mqh>
#include <FXSuite/Risk/CVaRTracker.mqh>
#include <FXSuite/Risk/DynamicSizer.mqh>
#include <FXSuite/Position/ProfitProtector.mqh>
#include <FXSuite/Telemetry/NDJSONLogger.mqh>

input ENUM_TIMEFRAMES InpTF=PERIOD_M15;
input double InpRiskPct=0.005;
input double InpMinPW=0.58;
input int InpSL_Pips=15;
input int InpTP_Pips=30;
input bool InpEnableTrades=false;
input string InpInferURL="http://127.0.0.1:8081/infer";
input int InpFeaturesVer=1;

// LEGACY_BEHAVIOR by default.
input bool InpEnableOmegaRiskPolicy=false;
input double InpMaxPortfolioHeat=0.06;
input double InpDailyLossLimit=0.03;
input double InpWeeklyLossLimit=0.07;
input double InpPeakLossLimit=0.12;
input double InpSoftHaltFraction=0.70;
input int InpMaxPositions=12;

// NEW_BEHAVIOR sizing remains opt-in.
input bool InpEnableOmegaSizer=false;
input double InpKellyMax=0.15;
input double InpCVaRLimitR=1.50;

// BE+.
input double InpBE_TriggerPctEquity=0.0;
input double InpBE_TriggerR=1.0;
input double InpBE_OffsetPips=0.2;
input bool InpBE_UseOR=true;

// ATR trailing remains opt-in.
input bool InpEnableATRTrail=false;
input double InpTrailStartR=1.5;
input double InpTrailATRMult=2.0;

// Calibration / rollover gates remain opt-in.
input bool InpEnableConformalGate=false;
input double InpConformalMaxWidth=0.25;
input bool InpEnableRolloverGuard=false;

input string InpConfigPath="Files\\FXSuite_Config.json";

CFeatureExtractor *g_feat=NULL;
CInferenceBridge *g_infer=NULL;
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

double PipValue()
{
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int dg=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   return ((dg==3 || dg==5)?pt*10.0:pt);
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

   int h=FileOpen(path,FILE_READ|FILE_CSV|FILE_ANSI);
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

int OnInit()
{
   g_feat=new CFeatureExtractor(_Symbol,InpTF,InpFeaturesVer);
   g_infer=new CInferenceBridge();
   g_infer.SetURL(InpInferURL);
   g_news=new CNewsCalendar("calendar.csv",2,45,45,false);
   g_regime=new CRegimeDetector(_Symbol,InpTF);
   g_roll=new CRolloverGuard();
   g_om=new COrderManager();
   g_risk=new CRiskManager(InpRiskPct);
   g_port=new CPortfolioControl();
   g_state=new CStateManager();
   g_cfg=new CConfigReloader(InpConfigPath);
   g_cvar=new CCVaRTracker(500);
   g_log=new CNDJSONLogger("FXSuite\\events.ndjson");
   g_profit=new CProfitProtector(g_om);

   if(!g_feat.Init() || !g_regime.Init()) return INIT_FAILED;

   if(InpEnableOmegaRiskPolicy)
      g_port.ConfigureOmega(InpMaxPortfolioHeat,InpDailyLossLimit,InpWeeklyLossLimit,
                            InpPeakLossLimit,InpMaxPositions,InpSoftHaltFraction);
   else
      g_port.Configure(InpMaxPortfolioHeat,InpDailyLossLimit,InpMaxPositions);

   g_port.OnStartup();
   g_state.Reconcile();
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

   string cb;
   if(g_port.CircuitBreakerTriggered(cb))
   {
      Comment("CIRCUIT BREAKER: ",cb);
      return;
   }

   if(InpEnableRolloverGuard && g_roll.IsGuarded(TimeCurrent()))
   {
      g_log.RolloverGuard(_Symbol,true,TimeCurrent());
      Comment("Rollover guard");
      return;
   }

   double minutes_news=MinutesToNextHighCSV("calendar.csv",TimeGMT(),_Symbol);
   if(g_news.IsBlackout(_Symbol,TimeGMT()))
   {
      g_log.NewsGuard(_Symbol,true,"calendar_blackout",minutes_news);
      Comment("News blackout");
      return;
   }

   double f[64];
   int intent_breakout=0,intent_trend=1,intent_squeeze=0;
   if(!g_feat.Build(f,intent_breakout,intent_trend,intent_squeeze)) return;

   int news_index=(InpFeaturesVer<=1?21:22);
   f[news_index]=minutes_news;

   string corr=StringFormat("%s-%I64d",_Symbol,(long)bt);
   double p_eff=0.0;
   int latency_ms=0;
   if(!g_infer.Predict(f,corr,p_eff,latency_ms,_Symbol,InpTF,InpFeaturesVer)) return;

   RegimeProfile rp;
   if(!g_regime.Evaluate(rp)) return;

   double threshold=InpMinPW*rp.pwin_threshold_mult;
   bool conformal_block=(InpEnableConformalGate &&
                         g_infer.ConformalWidth()>InpConformalMaxWidth);

   g_log.CalibrationDecision(_Symbol,g_infer.RawP(),p_eff,
                             g_infer.ConformalWidth(),InpConformalMaxWidth,
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
           p_eff,g_infer.RawP(),threshold,(int)rp.regime,
           g_infer.ModelId(),g_infer.FeaturesVersion(),latency_ms));

   if(!InpEnableTrades || p_eff<threshold) return;

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
}
