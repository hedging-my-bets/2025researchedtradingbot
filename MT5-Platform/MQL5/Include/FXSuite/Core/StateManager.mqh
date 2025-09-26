#property strict

class CStateManager {
private:
   string m_file;
public:
   CStateManager(const string file): m_file("Files\\"+file) {}

   bool Append(const string signal_id, const long ticket, const string symbol, const double intended_price)
   {
      int h = FileOpen(m_file, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
      if(h==INVALID_HANDLE) h = FileOpen(m_file, FILE_WRITE|FILE_CSV|FILE_ANSI);
      if(h==INVALID_HANDLE) return false;
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, signal_id, (string)ticket, symbol, DoubleToString(intended_price, 10), (string)TimeGMT(), "pending");
      FileClose(h);
      return true;
   }

   // Mark orphaned: tickets no longer present in Terminal
   void MarkOrphans()
   {
      int h = FileOpen(m_file, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
      if(h==INVALID_HANDLE) return;
      // naive pass-through; production systems should rewrite file with updated statuses
      FileClose(h);
   }
};