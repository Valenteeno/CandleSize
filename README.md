# CandleSize

Candle-size strategy: an indicator that measures candle body/range size and an EA that trades off it.

> **Proprietary software** — © Teenodi Ltd. All rights reserved. Private repository; not for distribution. See [LICENSE](LICENSE).

## CandleSizeEA02.mq5

_EA that trades off the CandlestickSizeIndicator_

### Inputs


*Indicator Settings*

| Input | Type | Default | Description |
|---|---|---|---|
| `IndicatorName` | string | `"CandleSizeIndicator02"` | Name of the indicator |
| `CandleSizeOption` | CandleSizeType | `HIGH_LOW` | Candle Size Option to Use |
| `CandleSizeThreshold` | double | `50` | Candle Size Threshold (points) |
| `TradeDirectionOption` | TradeDirection | `OPPOSITE` | Trade Direction Option |
| `ArrowOffset` | int | `1` |  |

*Position Limits*

| Input | Type | Default | Description |
|---|---|---|---|
| `MaxTrades` | int | `1` | Maximum trades at a time |

*Trade Settings*

| Input | Type | Default | Description |
|---|---|---|---|
| `TakeProfit` | double | `250` | Take Profit (points) |
| `StopLoss` | double | `100` | Stop Loss (points) |
| `TrailingStop` | bool | `false` | Use Trailing Stop |
| `AutoCloseMinutes` | int | `60` | Auto Close Time (minutes) |
| `LotSize` | double | `0.1` | Volume (lots) |

## CandleSizeIndicator02.mq5

### Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `CandleSizeOption` | CandleSizeType | `HIGH_LOW` | Candle Size Option to Use |
| `CandleSizeThreshold` | double | `50` | Candle Size Threshold (points) |
| `TradeDirectionOption` | TradeDirection | `OPPOSITE` | Trade Direction Option |
| `ArrowOffset` | int | `1` | Arrow offset in points from the candle |

## Archive

Earlier versions / forks are preserved under [`archive/`](archive/) for reference.

## Install

1. Copy the source file(s) into your MetaTrader 5 `MQL5/` tree (`Experts/`, `Indicators/`, or `Scripts/` as appropriate).
2. In MetaEditor, open the file and compile (**F7**).
3. Attach the compiled program to a chart from the terminal Navigator.

## License

Proprietary and confidential. © Teenodi Ltd. All rights reserved. See [LICENSE](LICENSE).
