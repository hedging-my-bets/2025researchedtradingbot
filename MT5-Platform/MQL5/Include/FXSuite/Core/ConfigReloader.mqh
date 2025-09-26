// FXSuite/Core/ConfigReloader.mqh
#property strict

class CConfigReloader {
private:
   string   m_path;
   datetime m_last_mtime;
   bool     m_changed;

public:
   CConfigReloader(const string path): m_path(path), m_last_mtime(0), m_changed(false) {}

   void Poll()
   {
      // get modification time via FileGetInteger on FILE_MODIFY_DATE by opening read-only
      int h = FileOpen(m_path, FILE_READ|FILE_BIN);
      if(h==INVALID_HANDLE) { m_changed=false; return; }
      datetime mt = (datetime)FileGetInteger(h, FILE_MODIFY_DATE);
      FileClose(h);
      if(m_last_mtime==0){ m_last_mtime=mt; m_changed=false; return; }
      if(mt>m_last_mtime){ m_last_mtime=mt; m_changed=true; } else m_changed=false;
   }

   bool Changed() const { return m_changed; }

   // You can parse inside your EA after detecting Changed()==true
   string Path() const { return m_path; }
};