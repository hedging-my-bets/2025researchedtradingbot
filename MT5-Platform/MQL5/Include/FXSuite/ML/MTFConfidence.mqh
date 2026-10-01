#property strict

struct FXS_MTFWeightRow
{
   int    regime;
   int    news_bucket;
   double w_m15;
   double w_h1;
   double w_h4;
   double w_d1;
};

class CMTFConfidence
{
private:
   FXS_MTFWeightRow m_rows[];

   int NewsBucket(const double minutes_to_news) const
   {
      if(minutes_to_news<30.0) return 0;
      if(minutes_to_news<120.0) return 1;
      return 2;
   }

public:
   bool LoadWeights(const string path)
   {
      int h=FileOpen(path,FILE_READ|FILE_CSV|FILE_ANSI,',');
      if(h==INVALID_HANDLE) return false;

      for(int i=0;i<6 && !FileIsEnding(h);++i) FileReadString(h);
      ArrayResize(m_rows,0);

      while(!FileIsEnding(h))
      {
         string a=FileReadString(h);
         if(a=="") break;

         FXS_MTFWeightRow r;
         r.regime=(int)StringToInteger(a);
         r.news_bucket=(int)StringToInteger(FileReadString(h));
         r.w_m15=StringToDouble(FileReadString(h));
         r.w_h1=StringToDouble(FileReadString(h));
         r.w_h4=StringToDouble(FileReadString(h));
         r.w_d1=StringToDouble(FileReadString(h));

         double sum=r.w_m15+r.w_h1+r.w_h4+r.w_d1;
         if(sum<=0.0) continue;

         r.w_m15/=sum;
         r.w_h1/=sum;
         r.w_h4/=sum;
         r.w_d1/=sum;

         int n=ArraySize(m_rows);
         ArrayResize(m_rows,n+1);
         m_rows[n]=r;
      }

      FileClose(h);
      return (ArraySize(m_rows)>0);
   }

   void Blend(const double p_m15,
              const double p_h1,
              const double p_h4,
              const double p_d1,
              const int regime,
              const double minutes_to_news,
              double &p_blend,
              double &coherence,
              double &threshold_add) const
   {
      double w0=0.55,w1=0.20,w2=0.15,w3=0.10;
      int bucket=NewsBucket(minutes_to_news);

      for(int i=0;i<ArraySize(m_rows);++i)
      {
         if(m_rows[i].regime==regime && m_rows[i].news_bucket==bucket)
         {
            w0=m_rows[i].w_m15;
            w1=m_rows[i].w_h1;
            w2=m_rows[i].w_h4;
            w3=m_rows[i].w_d1;
            break;
         }
      }

      double sum=w0+w1+w2+w3;
      if(sum<=0.0) sum=1.0;
      p_blend=(w0*p_m15+w1*p_h1+w2*p_h4+w3*p_d1)/sum;

      int d0=(p_m15>=0.5?1:-1);
      int d1=(p_h1>=0.5?1:-1);
      int d2=(p_h4>=0.5?1:-1);
      int d3=(p_d1>=0.5?1:-1);

      double agree=0.0;
      if(d0==d1) agree+=w1;
      if(d0==d2) agree+=w2;
      if(d0==d3) agree+=w3;

      coherence=agree/MathMax(1e-9,w1+w2+w3);
      threshold_add=(coherence<0.34 ? 0.08 : (coherence<0.67 ? 0.03 : 0.0));
   }

   bool ShouldBlock(const double p_m15,
                    const double p_h4,
                    const double p_d1,
                    const double coherence) const
   {
      int d0=(p_m15>=0.5?1:-1);
      int d2=(p_h4>=0.5?1:-1);
      int d3=(p_d1>=0.5?1:-1);
      return (coherence<0.34 && d2!=d0 && d3!=d0);
   }
};
