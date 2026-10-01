#property strict

struct SignalState
{
   string   corr_id;
   string   symbol;
   int      direction;
   datetime ts_sent;
   ulong    order_ticket;
   bool     filled;
};

class CStateManager
{
private:
   SignalState m_states[];

   int FindByCorr(const string corr_id) const
   {
      for(int i=0;i<ArraySize(m_states);++i) if(m_states[i].corr_id==corr_id) return i;
      return -1;
   }

public:
   void RegisterSignal(const string corr_id,const string symbol,const int dir)
   {
      if(FindByCorr(corr_id)>=0) return;
      int n=ArraySize(m_states); ArrayResize(m_states,n+1);
      m_states[n].corr_id=corr_id; m_states[n].symbol=symbol; m_states[n].direction=dir;
      m_states[n].ts_sent=TimeGMT(); m_states[n].order_ticket=0; m_states[n].filled=false;
   }

   void OnOrderPlaced(const string corr_id,const ulong ticket)
   {
      int i=FindByCorr(corr_id);
      if(i>=0) m_states[i].order_ticket=ticket;
   }

   void OnFill(const ulong ticket)
   {
      for(int i=0;i<ArraySize(m_states);++i)
         if(m_states[i].order_ticket==ticket){ m_states[i].filled=true; return; }
   }

   void Reconcile()
   {
      for(int i=0;i<PositionsTotal();++i)
      {
         string sym=PositionGetSymbol(i); if(sym=="") continue;
         ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
         bool known=false;
         for(int j=0;j<ArraySize(m_states);++j)
            if(m_states[j].order_ticket==ticket){ known=true; break; }
         if(known) continue;

         int n=ArraySize(m_states); ArrayResize(m_states,n+1);
         m_states[n].corr_id=StringFormat("RECOV-%s-%I64u",sym,ticket);
         m_states[n].symbol=sym;
         m_states[n].direction=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
         m_states[n].ts_sent=TimeGMT();
         m_states[n].order_ticket=ticket;
         m_states[n].filled=true;
      }
   }
};
