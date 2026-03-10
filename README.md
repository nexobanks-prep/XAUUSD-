# XAUUSD HFT Scalping Bot

High-Frequency Trading (HFT) scalping Expert Advisor for **XAUUSD (Gold)** on **MetaTrader 5**, written in MQL5.

## Features

- **High-Frequency Execution**: Targets ~50 trades per minute with sub-second hold times
- **Multi-Signal Confirmation**: Uses tick momentum, consecutive tick direction, weighted momentum, and micro moving averages for 70–80% win-rate targeting
- **Async Order Execution**: Uses `OrderSendAsync()` for non-blocking, ultra-fast trade placement
- **Millisecond Timer Monitoring**: Monitors and closes positions every 50ms (configurable)
- **Spread Filter**: Only trades when the spread is below a configurable threshold
- **Risk Management**: Daily loss limit, max daily trades, max concurrent positions, and configurable trading hours
- **Live Dashboard**: Displays real-time stats (win rate, PnL, spread, trade count) on the chart

## File Structure

```
├── Experts/
│   └── XAUUSD_HFT_Scalper.mq5    # Main Expert Advisor
├── Include/
│   └── HFT_Utils.mqh              # Utility classes (tick buffer, stats, spread monitor)
└── README.md
```

## Installation

1. **Copy files to your MetaTrader 5 data folder**:
   - Copy `Experts/XAUUSD_HFT_Scalper.mq5` → `<MT5 Data Folder>/MQL5/Experts/`
   - Copy `Include/HFT_Utils.mqh` → `<MT5 Data Folder>/MQL5/Include/`

   To find your MT5 data folder, open MetaTrader 5 → **File** → **Open Data Folder**.

2. **Compile the EA**:
   - Open MetaEditor (F4 in MT5)
   - Open `Experts/XAUUSD_HFT_Scalper.mq5`
   - Press **Compile** (F7)
   - Ensure there are no errors

3. **Attach to Chart**:
   - Open a **XAUUSD** chart (any timeframe — the EA operates on ticks)
   - Drag `XAUUSD_HFT_Scalper` from the Navigator onto the chart
   - Enable **Algo Trading** in the MT5 toolbar
   - Configure input parameters in the EA dialog

## Configuration Parameters

### Trade Execution
| Parameter | Default | Description |
|-----------|---------|-------------|
| Lot Size | 0.01 | Volume per trade |
| Max Slippage | 30 pts | Maximum allowed slippage |
| Magic Number | 777555 | Unique EA identifier |
| Max Concurrent Positions | 5 | Limits open positions |

### Scalping Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| Take Profit | 50 pts | Profit target per trade |
| Stop Loss | 70 pts | Maximum loss per trade |
| Tick Buffer Size | 30 | Number of ticks stored for analysis |
| Momentum Window | 10 ticks | Ticks used for momentum calculation |
| Momentum Threshold | 0.03 | Minimum momentum to trigger signal |
| Min Consecutive Ticks | 3 | Consecutive same-direction ticks needed |

### Spread & Timing
| Parameter | Default | Description |
|-----------|---------|-------------|
| Max Spread | 40 pts | Maximum spread for trade entry |
| Timer Interval | 50 ms | Position monitoring frequency |
| Min Time Between Trades | 500 ms | Cooldown between trades |
| Max Hold Time | 900 ms | Force-close after this duration |

### Risk Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| Max Daily Loss | $100 | Stops trading if daily loss exceeds this |
| Max Daily Trades | 5000 | Maximum trades per day |
| Trading Start Hour | 0 | Server time hour to start trading |
| Trading End Hour | 24 | Server time hour to stop trading |

### Signal Filters
| Parameter | Default | Description |
|-----------|---------|-------------|
| Use Weighted Momentum | true | Enable weighted momentum confirmation |
| Weighted Momentum Threshold | 0.02 | Minimum weighted momentum |
| Use MA Filter | true | Enable moving average crossover filter |
| MA Tick Period | 20 | Moving average lookback in ticks |

## How It Works

### Signal Generation
The EA analyzes raw tick data to detect micro-trends:

1. **Tick Momentum**: Measures the net price change over the last N ticks. A buy signal is generated when momentum exceeds the threshold upward, and a sell signal when it exceeds downward.
2. **Consecutive Direction**: Counts consecutive ticks moving in the same direction. Requires a minimum number of same-direction ticks to confirm the signal.
3. **Weighted Momentum**: Gives more weight to recent ticks in the momentum calculation for faster signal response.
4. **Moving Average Filter**: Compares a fast tick-based MA against a slow tick-based MA for trend confirmation.

A trade is only executed when at least 2 confirmations agree on the direction.

### Execution Flow
1. `OnTick()` fires on every price update — pushes tick data to buffers
2. Checks spread, cooldown timer, open position count, and trading permissions
3. Generates signal using multi-confirmation system
4. Executes trade asynchronously via `OrderSendAsync()` with preset TP/SL
5. `OnTimer()` fires every 50ms — monitors positions for profit or max hold time
6. Positions are closed as soon as profit is detected or hold time exceeds the limit

## Broker Requirements

- **ECN/STP broker** recommended for tightest spreads on XAUUSD
- **Low-latency VPS** near your broker's server for optimal execution
- **No restrictions on scalping or HFT** — verify with your broker
- **IOC (Immediate-or-Cancel) fill mode** support
- **Hedging account type** for simultaneous positions

## Risk Warning

> **This EA engages in high-frequency trading which carries significant financial risk.** Past performance does not guarantee future results. The multi-signal confirmation system is designed to improve trade quality, but no specific win rate is guaranteed — actual results depend on market conditions, broker execution, spread, and latency. Always test thoroughly in a demo account before using real funds. Use appropriate position sizing and never risk more than you can afford to lose.

## Testing

1. Open the **Strategy Tester** in MT5 (Ctrl+R)
2. Select `XAUUSD_HFT_Scalper`
3. Set symbol to **XAUUSD**, period to **M1** (though the EA uses ticks)
4. Select **Every tick based on real ticks** modeling mode for accurate results
5. Run a backtest and review the results before live deployment