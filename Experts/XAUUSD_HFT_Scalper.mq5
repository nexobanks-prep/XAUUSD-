//+------------------------------------------------------------------+
//|                                          XAUUSD_HFT_Scalper.mq5 |
//|                         XAUUSD HFT Scalping Bot for MetaTrader 5 |
//|                                                                  |
//| High-Frequency Trading scalper designed for XAUUSD (Gold).       |
//| Targets ~50 trades/minute with sub-second hold times.            |
//| Uses tick momentum, micro-trend detection, and spread filtering  |
//| for high win-rate scalping.                                      |
//+------------------------------------------------------------------+
#property copyright   "XAUUSD HFT Scalper"
#property version     "1.00"
#property description "HFT Scalping Bot for XAUUSD - 50 trades/min target"
#property description "Sub-second execution with 70-80% win rate target"
#property strict

#include "../Include/HFT_Utils.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Trade Execution ==="
input double   InpLotSize            = 0.01;    // Lot Size per trade
input int      InpSlippagePoints     = 30;      // Max Slippage (points)
input ulong    InpMagicNumber        = 777555;  // Magic Number
input int      InpMaxOpenPositions   = 5;       // Max Concurrent Positions

input group "=== Scalping Parameters ==="
input double   InpTakeProfitPoints   = 50;      // Take Profit (points)
input double   InpStopLossPoints     = 70;      // Stop Loss (points)
input int      InpTickBufferSize     = 30;      // Tick Buffer Size (# ticks for analysis)
input int      InpMomentumTicks      = 10;      // Momentum Window (# ticks)
input double   InpMomentumThreshold  = 0.03;    // Momentum Threshold (price units)
input int      InpConsecTicksMin     = 3;       // Min Consecutive Ticks for signal

input group "=== Spread & Timing ==="
input double   InpMaxSpreadPoints    = 40;      // Max Spread to Trade (points)
input int      InpTimerMilliseconds  = 50;      // Timer Interval (ms) for monitoring
input int      InpMinTimeBetweenMs   = 500;     // Min Time Between Trades (ms)
input int      InpMaxHoldTimeMs      = 900;     // Max Position Hold Time (ms)

input group "=== Risk Management ==="
input double   InpMaxDailyLoss       = 100.0;   // Max Daily Loss ($) - stops trading
input int      InpMaxDailyTrades     = 5000;    // Max Daily Trades
input int      InpStartHour          = 0;       // Trading Start Hour (server time)
input int      InpEndHour            = 24;      // Trading End Hour (server time)

input group "=== Signal Filters ==="
input bool     InpUseWeightedMom     = true;    // Use Weighted Momentum
input double   InpWeightedMomThresh  = 0.02;    // Weighted Momentum Threshold
input bool     InpUseMAFilter        = true;    // Use Moving Average Filter
input int      InpMATickPeriod       = 20;      // MA Period (# ticks)

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade         g_trade;
CTickBuffer    g_bid_buffer;
CTickBuffer    g_ask_buffer;
CSpreadMonitor g_spread_mon;
CTradeStats    g_stats;

ulong          g_last_trade_time_ms = 0;
bool           g_trading_allowed    = true;
string         g_symbol;
double         g_point;
int            g_digits;
int            g_tick_count = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_symbol = Symbol();

   //--- Validate symbol
   if(StringFind(g_symbol, "XAU") < 0 && StringFind(g_symbol, "GOLD") < 0)
     {
      Print("WARNING: This EA is optimized for XAUUSD/Gold. Current symbol: ", g_symbol);
     }

   //--- Initialize tick buffers
   if(!g_bid_buffer.Init(InpTickBufferSize) ||
      !g_ask_buffer.Init(InpTickBufferSize) ||
      !g_spread_mon.Init(100))
     {
      Print("ERROR: Failed to initialize tick buffers");
      return INIT_FAILED;
     }

   //--- Configure trade object
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   g_trade.SetAsyncMode(true);  // Async for fastest execution

   //--- Cache symbol properties
   g_point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);

   //--- Start millisecond timer for position monitoring
   if(!EventSetMillisecondTimer(InpTimerMilliseconds))
     {
      Print("ERROR: Failed to set millisecond timer. Falling back to 1-second timer.");
      EventSetTimer(1);
     }

   //--- Initialize stats
   g_stats.Reset();

   Print("=== XAUUSD HFT Scalper Initialized ===");
   Print("Lot Size: ", InpLotSize);
   Print("TP: ", InpTakeProfitPoints, " pts | SL: ", InpStopLossPoints, " pts");
   Print("Max Spread: ", InpMaxSpreadPoints, " pts");
   Print("Timer: ", InpTimerMilliseconds, " ms");
   Print("Max Hold: ", InpMaxHoldTimeMs, " ms");
   Print("Point: ", g_point, " | Digits: ", g_digits);

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Print("=== XAUUSD HFT Scalper Stopped ===");
   Print("Total Trades: ", g_stats.TotalTrades(),
         " | Win Rate: ", DoubleToString(g_stats.WinRate(), 1), "%",
         " | Daily PnL: $", DoubleToString(g_stats.DailyPnL(), 2));
  }

//+------------------------------------------------------------------+
//| Tick function - primary signal generation                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- Get latest tick
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return;

   //--- Update tick buffers
   g_bid_buffer.Push(tick.bid);
   g_ask_buffer.Push(tick.ask);
   g_spread_mon.Push((tick.ask - tick.bid) / g_point);
   g_tick_count++;

   //--- Check if trading is allowed
   if(!IsTradingAllowed())
      return;

   //--- Need minimum ticks before generating signals
   if(g_bid_buffer.Count() < InpMomentumTicks)
      return;

   //--- Check spread
   if(!g_spread_mon.IsTight(InpMaxSpreadPoints))
      return;

   //--- Check time between trades
   ulong now_ms = GetTickCount64();
   if(now_ms - g_last_trade_time_ms < (ulong)InpMinTimeBetweenMs)
      return;

   //--- Check max open positions
   if(CountOpenPositions() >= InpMaxOpenPositions)
      return;

   //--- Generate signal
   int signal = GetTradeSignal();
   if(signal == 0)
      return;

   //--- Execute trade
   ExecuteTrade(signal, tick);
  }

//+------------------------------------------------------------------+
//| Timer function - position monitoring and fast close              |
//+------------------------------------------------------------------+
void OnTimer()
  {
   //--- Check for new day (reset daily stats)
   g_stats.CheckNewDay();

   //--- Monitor and close positions based on time and profit
   MonitorPositions();

   //--- Update chart dashboard
   DisplayDashboard();
  }

//+------------------------------------------------------------------+
//| Trade transaction handler for async order results                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      //--- A deal was executed
      if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
        {
         if(trans.order_state == ORDER_STATE_FILLED)
           {
            // Order filled successfully - logged for tracking
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check if trading is currently allowed                            |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
  {
   //--- Check terminal trading permission
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;

   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;

   //--- Check daily loss limit
   if(g_stats.DailyPnL() <= -InpMaxDailyLoss)
     {
      if(g_trading_allowed)
        {
         Print("Daily loss limit reached: $", DoubleToString(MathAbs(g_stats.DailyPnL()), 2));
         g_trading_allowed = false;
        }
      return false;
     }

   //--- Check daily trade count
   if(g_stats.DailyTrades() >= InpMaxDailyTrades)
      return false;

   //--- Check trading hours
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour)
      return false;

   g_trading_allowed = true;
   return true;
  }

//+------------------------------------------------------------------+
//| Count positions opened by this EA                                |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 &&
         PositionGetString(POSITION_SYMBOL) == g_symbol &&
         PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber)
        {
         count++;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Generate trade signal based on tick analysis                     |
//+------------------------------------------------------------------+
int GetTradeSignal()
  {
   int signal = 0;
   int confirmations = 0;
   int required_confirmations = 2;

   //--- 1. Tick Momentum Signal
   double momentum = g_bid_buffer.Momentum(InpMomentumTicks);
   if(MathAbs(momentum) >= InpMomentumThreshold)
     {
      signal = (momentum > 0) ? 1 : -1;
      confirmations++;
     }
   else
      return 0;  // No momentum = no trade

   //--- 2. Consecutive Tick Direction
   int consec = g_bid_buffer.ConsecutiveDirection();
   if(MathAbs(consec) >= InpConsecTicksMin)
     {
      int consec_dir = (consec > 0) ? 1 : -1;
      if(consec_dir == signal)
         confirmations++;
      else
         return 0;  // Conflicting signal
     }

   //--- 3. Weighted Momentum (optional filter)
   if(InpUseWeightedMom)
     {
      double wmom = g_bid_buffer.WeightedMomentum(InpMomentumTicks);
      if(MathAbs(wmom) >= InpWeightedMomThresh)
        {
         int wmom_dir = (wmom > 0) ? 1 : -1;
         if(wmom_dir == signal)
            confirmations++;
         else
            return 0;  // Conflicting weighted momentum
        }
     }

   //--- 4. Moving Average Filter (optional)
   if(InpUseMAFilter)
     {
      double ma_fast = g_bid_buffer.Average(InpMomentumTicks / 2);
      double ma_slow = g_bid_buffer.Average(InpMATickPeriod);
      if(ma_fast > 0 && ma_slow > 0)
        {
         int ma_dir = (ma_fast > ma_slow) ? 1 : -1;
         if(ma_dir == signal)
            confirmations++;
         else if(ma_dir != signal)
            return 0;  // MA disagrees - skip trade
        }
     }

   //--- Need at least required confirmations
   if(confirmations < required_confirmations)
      return 0;

   return signal;
  }

//+------------------------------------------------------------------+
//| Execute a trade with the given signal direction                  |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal, const MqlTick &tick)
  {
   double price, sl, tp;

   if(signal > 0)  // BUY
     {
      price = tick.ask;
      sl = NormalizeDouble(price - InpStopLossPoints * g_point, g_digits);
      tp = NormalizeDouble(price + InpTakeProfitPoints * g_point, g_digits);

      if(g_trade.Buy(InpLotSize, g_symbol, price, sl, tp, "HFT_BUY"))
        {
         g_last_trade_time_ms = GetTickCount64();
        }
     }
   else if(signal < 0)  // SELL
     {
      price = tick.bid;
      sl = NormalizeDouble(price + InpStopLossPoints * g_point, g_digits);
      tp = NormalizeDouble(price - InpTakeProfitPoints * g_point, g_digits);

      if(g_trade.Sell(InpLotSize, g_symbol, price, sl, tp, "HFT_SELL"))
        {
         g_last_trade_time_ms = GetTickCount64();
        }
     }
  }

//+------------------------------------------------------------------+
//| Monitor open positions and close based on time/profit            |
//+------------------------------------------------------------------+
void MonitorPositions()
  {
   ulong now_ms = GetTickCount64();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      //--- Only manage our positions
      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber)
         continue;

      double profit = PositionGetDouble(POSITION_PROFIT);
      double swap   = PositionGetDouble(POSITION_SWAP);
      double net_profit = profit + swap;
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      ulong open_time_msc = (ulong)PositionGetInteger(POSITION_TIME_MSC);

      //--- Calculate hold time in milliseconds
      //--- Use server time approximation since GetTickCount64 is local
      ulong current_msc = (ulong)TimeCurrent() * 1000;
      ulong hold_time_ms = 0;
      if(current_msc > open_time_msc)
         hold_time_ms = current_msc - open_time_msc;

      bool should_close = false;
      string close_reason = "";

      //--- Close if profit target reached (any profit in scalping mode)
      if(net_profit > 0.0 && hold_time_ms >= 100)
        {
         should_close = true;
         close_reason = "PROFIT";
        }

      //--- Close if max hold time exceeded
      if(hold_time_ms >= (ulong)InpMaxHoldTimeMs)
        {
         should_close = true;
         close_reason = "MAX_HOLD_TIME";
        }

      //--- Execute close
      if(should_close)
        {
         if(g_trade.PositionClose(ticket))
           {
            g_stats.RecordTrade(net_profit);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Chart event handler - display stats on chart                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
  {
   //--- No custom chart event handling needed
  }

//+------------------------------------------------------------------+
//| Display dashboard on chart                                       |
//+------------------------------------------------------------------+
void DisplayDashboard()
  {
   string dashboard = "";
   dashboard += "=== HFT SCALPER DASHBOARD ===\n";
   dashboard += "Symbol: " + g_symbol + "\n";
   dashboard += "Spread: " + DoubleToString(g_spread_mon.Current(), 1) + " pts\n";
   dashboard += "Avg Spread: " + DoubleToString(g_spread_mon.Average(), 1) + " pts\n";
   dashboard += "---\n";
   dashboard += "Daily Trades: " + IntegerToString(g_stats.DailyTrades()) + "\n";
   dashboard += "Win Rate: " + DoubleToString(g_stats.WinRate(), 1) + "%\n";
   dashboard += "Daily PnL: $" + DoubleToString(g_stats.DailyPnL(), 2) + "\n";
   dashboard += "Open Positions: " + IntegerToString(CountOpenPositions()) + "\n";
   dashboard += "Trading: " + (g_trading_allowed ? "ACTIVE" : "PAUSED") + "\n";
   dashboard += "Ticks Processed: " + IntegerToString(g_tick_count) + "\n";

   Comment(dashboard);
  }
