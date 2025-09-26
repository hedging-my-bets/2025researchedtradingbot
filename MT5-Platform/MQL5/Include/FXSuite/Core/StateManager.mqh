// FXSuite/Core/StateManager.mqh
#property strict

struct SignalState {
   string   corr_id;
   string   symbol;
   int      direction;   // +1 buy, -1 sell, 0 unknown
   datetime ts_sent;
   ulong    order_ticket; // 0 until known
   bool     filled;
};

class CStateManager {
private:
   CArrayObj m_states;

public:
   CStateManager(){}

   void RegisterSignal(const string corr_id, const string symbol, const int dir)
   {
      SignalState *st = new SignalState;
      st.corr_id = corr_id; st.symbol = symbol; st.direction = dir;
      st.ts_sent = TimeGMT(); st.order_ticket=0; st.filled=false;
      m_states.Add(st);
   }

   void OnOrderPlaced(const string corr_id, const ulong ticket)
   {
      for(int i=0;i<m_states.Total();i++){
         SignalState *st = (SignalState*)m_states.At(i);
         if(st.corr_id==corr_id){
            st.order_ticket = ticket;
            break;
         }
      }
   }

   void OnFill(const ulong ticket)
   {
      for(int i=0;i<m_states.Total();i++){
         SignalState *st = (SignalState*)m_states.At(i);
         if(st.order_ticket==ticket){ st->filled=true; break; }
      }
   }

   // basic reconciliation on startup: ensure we track live positions
   void Reconcile()
   {
      for(int i=0;i<PositionsTotal();i++){
         if(PositionGetSymbol(i)){
            ulong pos_ticket = (ulong)PositionGetInteger(POSITION_TICKET);
            string sym       = PositionGetString(POSITION_SYMBOL);
            bool known=false;
            for(int j=0;j<m_states.Total();j++){
               SignalState *st = (SignalState*)m_states.At(j);
               if(st.order_ticket==pos_ticket){ known=true; break; }
            }
            if(!known){
               SignalState *st = new SignalState;
               st.corr_id = StringFormat("RECOV-%s-%I64u", sym, pos_ticket);
               st.symbol  = sym;
               st.direction = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
               st.ts_sent = TimeGMT();
               st.order_ticket = pos_ticket;
               st.filled = true;
               m_states.Add(st);
            }
         }
      }
   }
};