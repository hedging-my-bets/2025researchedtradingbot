#property strict

class CConfigReloader {
private:
   string m_file;
   long   m_last_hash;
public:
   CConfigReloader(const string file): m_file(file), m_last_hash(0) {}

   long HashFile() {
      int h = FileOpen(m_file, FILE_READ|FILE_BIN);
      if(h==INVALID_HANDLE) return 0;
      uchar buf[]; ArrayResize(buf, (int)FileSize(h));
      FileReadArray(h, buf, 0, ArraySize(buf)); FileClose(h);
      long hash=0; for(int i=0;i<ArraySize(buf);i++) hash = (hash*131) + buf[i];
      return hash;
   }

   bool Changed() {
      long now = HashFile();
      if(now!=0 && now!=m_last_hash) { m_last_hash=now; return true; }
      return false;
   }
};