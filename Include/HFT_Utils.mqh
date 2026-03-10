//+------------------------------------------------------------------+
//|                                                    HFT_Utils.mqh |
//|                         XAUUSD HFT Scalping Bot - Utility Module |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "XAUUSD HFT Scalper"
#property strict

//+------------------------------------------------------------------+
//| Tick ring buffer for micro-trend analysis                        |
//+------------------------------------------------------------------+
class CTickBuffer
  {
private:
   double            m_prices[];
   int               m_size;
   int               m_count;
   int               m_head;

public:
                     CTickBuffer(void) : m_size(0), m_count(0), m_head(0) {}
                    ~CTickBuffer(void) {}

   bool              Init(int size)
     {
      m_size = size;
      m_count = 0;
      m_head = 0;
      return ArrayResize(m_prices, m_size) == m_size;
     }

   void              Push(double price)
     {
      m_prices[m_head] = price;
      m_head = (m_head + 1) % m_size;
      if(m_count < m_size)
         m_count++;
     }

   int               Count(void) const { return m_count; }

   double            Get(int index) const
     {
      if(index < 0 || index >= m_count)
         return 0.0;
      int pos = (m_head - m_count + index + m_size) % m_size;
      return m_prices[pos];
     }

   double            Latest(void) const
     {
      if(m_count == 0)
         return 0.0;
      return Get(m_count - 1);
     }

   double            Previous(void) const
     {
      if(m_count < 2)
         return 0.0;
      return Get(m_count - 2);
     }

   //--- Calculate average of last N ticks
   double            Average(int n) const
     {
      if(n <= 0 || m_count == 0)
         return 0.0;
      int cnt = MathMin(n, m_count);
      double sum = 0.0;
      for(int i = m_count - cnt; i < m_count; i++)
         sum += Get(i);
      return sum / cnt;
     }

   //--- Calculate tick momentum (net direction over last N ticks)
   double            Momentum(int n) const
     {
      if(n <= 1 || m_count < 2)
         return 0.0;
      int cnt = MathMin(n, m_count);
      int start = m_count - cnt;
      return Get(m_count - 1) - Get(start);
     }

   //--- Count consecutive ticks in the same direction
   int               ConsecutiveDirection(void) const
     {
      if(m_count < 2)
         return 0;
      int dir = 0;
      int count = 0;
      for(int i = m_count - 1; i > 0; i--)
        {
         double diff = Get(i) - Get(i - 1);
         if(diff == 0.0)
            continue;
         int d = (diff > 0) ? 1 : -1;
         if(dir == 0)
           {
            dir = d;
            count = 1;
           }
         else if(d == dir)
            count++;
         else
            break;
        }
      return count * dir;
     }

   //--- Weighted momentum (recent ticks have more weight)
   double            WeightedMomentum(int n) const
     {
      if(n <= 1 || m_count < 2)
         return 0.0;
      int cnt = MathMin(n, m_count);
      double wmom = 0.0;
      double wsum = 0.0;
      for(int i = 1; i < cnt; i++)
        {
         int idx = m_count - cnt + i;
         double diff = Get(idx) - Get(idx - 1);
         double weight = (double)i;
         wmom += diff * weight;
         wsum += weight;
        }
      return (wsum > 0.0) ? wmom / wsum : 0.0;
     }
  };

//+------------------------------------------------------------------+
//| Trade statistics tracker                                         |
//+------------------------------------------------------------------+
class CTradeStats
  {
private:
   int               m_total_trades;
   int               m_winning_trades;
   int               m_losing_trades;
   double            m_total_profit;
   double            m_total_loss;
   datetime          m_day_start;
   int               m_daily_trades;
   double            m_daily_pnl;

public:
                     CTradeStats(void)
     {
      Reset();
     }

   void              Reset(void)
     {
      m_total_trades = 0;
      m_winning_trades = 0;
      m_losing_trades = 0;
      m_total_profit = 0.0;
      m_total_loss = 0.0;
      m_daily_trades = 0;
      m_daily_pnl = 0.0;
      MqlDateTime dt;
      TimeCurrent(dt);
      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;
      m_day_start = StructToTime(dt);
     }

   void              CheckNewDay(void)
     {
      MqlDateTime dt;
      TimeCurrent(dt);
      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;
      datetime today = StructToTime(dt);
      if(today != m_day_start)
        {
         m_day_start = today;
         m_daily_trades = 0;
         m_daily_pnl = 0.0;
        }
     }

   void              RecordTrade(double profit)
     {
      m_total_trades++;
      m_daily_trades++;
      m_daily_pnl += profit;
      if(profit >= 0.0)
        {
         m_winning_trades++;
         m_total_profit += profit;
        }
      else
        {
         m_losing_trades++;
         m_total_loss += MathAbs(profit);
        }
     }

   int               TotalTrades(void) const { return m_total_trades; }
   int               DailyTrades(void) const { return m_daily_trades; }
   double            DailyPnL(void) const { return m_daily_pnl; }
   double            WinRate(void) const
     {
      return (m_total_trades > 0) ? (double)m_winning_trades / m_total_trades * 100.0 : 0.0;
     }
   double            ProfitFactor(void) const
     {
      if(m_total_loss == 0.0)
         return (m_total_profit > 0.0) ? DBL_MAX : 0.0;  // Infinite if wins with no losses
      return m_total_profit / m_total_loss;
     }
  };

//+------------------------------------------------------------------+
//| Spread monitor for optimal entry timing                          |
//+------------------------------------------------------------------+
class CSpreadMonitor
  {
private:
   double            m_spreads[];
   int               m_size;
   int               m_count;
   int               m_head;

public:
                     CSpreadMonitor(void) : m_size(0), m_count(0), m_head(0) {}

   bool              Init(int size)
     {
      m_size = size;
      m_count = 0;
      m_head = 0;
      return ArrayResize(m_spreads, m_size) == m_size;
     }

   void              Push(double spread)
     {
      m_spreads[m_head] = spread;
      m_head = (m_head + 1) % m_size;
      if(m_count < m_size)
         m_count++;
     }

   double            Average(void) const
     {
      if(m_count == 0)
         return 0.0;
      double sum = 0.0;
      for(int i = 0; i < m_count; i++)
         sum += m_spreads[i];
      return sum / m_count;
     }

   double            Current(void) const
     {
      if(m_count == 0)
         return 0.0;
      int idx = (m_head - 1 + m_size) % m_size;
      return m_spreads[idx];
     }

   bool              IsTight(double max_spread) const
     {
      return (m_count > 0 && Current() <= max_spread);
     }
  };
