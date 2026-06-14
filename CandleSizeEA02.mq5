//+------------------------------------------------------------------+
//|                                             CandlestickSizeEA.mq5 |
//|                                     Copyright 2025, Teenodi Ltd. |
//|                                         https://www.jukwaese.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Teenodi Ltd."
#property link      "https://www.jukwaese.com"
#property version   "1.04"
#property description "EA that trades off the CandlestickSizeIndicator"
#property strict
#define EAMagic 754321
#property tester_indicator "CandleSizeIndicator.ex5"
#property indicator_chart_window


enum CandleSizeType {
   HIGH_LOW,    // High-Low (Total Height)
   OPEN_CLOSE   // Open-Close (Body Height)
};
enum TradeDirection {
   FOLLOW,      // Follow Candle Direction
   OPPOSITE     // Opposite Candle Direction
};
//============================ inputs ===============================
input group "Indicator Settings"
input string IndicatorName = "CandleSizeIndicator02";  // Name of the indicator
input CandleSizeType CandleSizeOption = HIGH_LOW;       // Candle Size Option to Use
input double CandleSizeThreshold = 50;                  // Candle Size Threshold (points)
input TradeDirection TradeDirectionOption = OPPOSITE;    // Trade Direction Option
input int ArrowOffset = 1;  
input group "Position Limits"
input int MaxTrades = 1;                          // Maximum trades at a time

input group "Trade Settings"
input double TakeProfit = 250;                          // Take Profit (points)
input double StopLoss = 100;                            // Stop Loss (points)
input bool TrailingStop = false;                        // Use Trailing Stop
input int AutoCloseMinutes = 60;                        // Auto Close Time (minutes)
input double LotSize = 0.1;                             // Volume (lots)

//=========================== globals ===============================
double takeProfitPoints, stopLossPoints;
bool newBar = false;
datetime prevBarTime = 0;
int timerID = 0;
int indicatorHandle = INVALID_HANDLE;

// Arrays to store trade tickets and their auto-close times
ulong tradeTickets[];
datetime tradeCloseTimes[];

//--- Check filling policy
ENUM_ORDER_TYPE_FILLING orderFill;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Check that autotrading is enabled
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
      Alert("Please enable autotrading on terminal to take trades");
   }
   
   // Initialize point values
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   takeProfitPoints = NormalizeDouble(TakeProfit * point, _Digits);
   stopLossPoints = NormalizeDouble(StopLoss * point, _Digits);
   
   // Set up filling policy
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) {
      orderFill = ORDER_FILLING_FOK;
   }
   else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) {
      orderFill = ORDER_FILLING_IOC;
   }
   else {
      orderFill = ORDER_FILLING_RETURN; // Default fill type
   }
   
   // Initialize previous bar time
   prevBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // Create a timer for checking auto-close trades
   if(AutoCloseMinutes > 0) {
      timerID = EventSetTimer(60); // Check every minute
   }
   
   // Get handle to the indicator
   indicatorHandle = iCustom(_Symbol, PERIOD_CURRENT, IndicatorName, CandleSizeOption, CandleSizeThreshold, TradeDirectionOption, ArrowOffset);
   if(indicatorHandle == INVALID_HANDLE) {
      Print("Failed to get handle to indicator ", IndicatorName, ". Error: ", GetLastError());
      return(INIT_FAILED);
   }
   
   Print("Indicator handle acquired: ", indicatorHandle);
   ChartIndicatorAdd(0,0,indicatorHandle);
   ChartRedraw(0);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handle
   if(indicatorHandle != INVALID_HANDLE) {
      IndicatorRelease(indicatorHandle);
   }
   
   // Kill timer
   if(timerID != 0) {
      EventKillTimer();
   }
   
   Print("EA deinitialized, reason: ", reason);
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Check if any trades need to be closed due to time expiry
   datetime currentTime = TimeCurrent();
   
   for(int i = 0; i < ArraySize(tradeTickets); i++) {
      // Check if this trade should be closed
      if(currentTime >= tradeCloseTimes[i] && PositionSelectByTicket(tradeTickets[i])) {
         Print("Auto-closing trade #", tradeTickets[i], " due to time expiry");
         ClosePosition(tradeTickets[i]);
         
         // Remove this trade from the arrays
         ArrayRemove(tradeTickets, i, 1);
         ArrayRemove(tradeCloseTimes, i, 1);
         i--; // Adjust index since we removed an element
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   bool isNewBar = IsNewBar();
   
   // Handle trailing stop if enabled
   if(TrailingStop) {
      TrailStops();
   }

   // Process signals only on new bar
   if(isNewBar) {
      Print("New bar detected, checking for signals...");
      CheckIndicatorSignals();
   }
}

//+------------------------------------------------------------------+
//| Check if we have a new bar                                       |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime != prevBarTime) {
      prevBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check indicator signals and generate trades                      |
//+------------------------------------------------------------------+
void CheckIndicatorSignals()
{
   // Ensure indicator handle is valid
   if(indicatorHandle == INVALID_HANDLE) {
      Print("Invalid indicator handle in CheckIndicatorSignals()");
      return;
   }
   
   // Get indicator values from the completed bar (index 1)
   double buyBuffer[], sellBuffer[];
   
   // Copy the indicator buffers
   if(CopyBuffer(indicatorHandle, 0, 1, 1, buyBuffer) <= 0) {
      int error = GetLastError();
      Print("Failed to get buy buffer from indicator. Error: ", error);
      return;
   }
   
   if(CopyBuffer(indicatorHandle, 1, 1, 1, sellBuffer) <= 0) {
      int error = GetLastError();
      Print("Failed to get sell buffer from indicator. Error: ", error);
      return;
   }
   
   // Debugging
   Print("Buy buffer value: ", buyBuffer[0], " | Sell buffer value: ", sellBuffer[0]);
   
   // Check for buy signal - if value is not EMPTY_VALUE and not zero
   if(buyBuffer[0] != EMPTY_VALUE && buyBuffer[0] != 0) {
      Print("Buy signal detected");
      // Check if we can open a buy trade based on MaxTrades
      if(CountOpenPositions() < MaxTrades) {
         Print("Executing buy trade");
         ExecuteTrade(true); // Buy
      } else {
         Print("Max trades limit reached, not opening buy position");
      }
   }
   
   // Check for sell signal - if value is not EMPTY_VALUE and not zero
   if(sellBuffer[0] != EMPTY_VALUE && sellBuffer[0] != 0) {
      Print("Sell signal detected");
      // Check if we can open a sell trade based on MaxTrades
      if(CountOpenPositions() < MaxTrades) {
         Print("Executing sell trade");
         ExecuteTrade(false); // Sell
      } else {
         Print("Max trades limit reached, not opening sell position");
      }
   }
}

//+------------------------------------------------------------------+
//| Count open positions by type                                     |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == EAMagic) {
         count++;
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Execute trade based on signal                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(bool isLong)
{
   double price, stopLossLevel, takeProfitLevel;
   ENUM_ORDER_TYPE orderType;
   
   // Prepare order details
   if(isLong) {
      orderType = ORDER_TYPE_BUY;
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      stopLossLevel = price - stopLossPoints;
      takeProfitLevel = price + takeProfitPoints;
   } else {
      orderType = ORDER_TYPE_SELL;
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      stopLossLevel = price + stopLossPoints;
      takeProfitLevel = price - takeProfitPoints;
   }
   
   // Send order
   if(OpenPosition(orderType, LotSize, stopLossLevel, takeProfitLevel)) {
      Print("Trade executed successfully. Direction: ", (isLong ? "BUY" : "SELL"));
   } else {
      Print("Failed to execute trade. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Open a new position                                              |
//+------------------------------------------------------------------+
bool OpenPosition(ENUM_ORDER_TYPE type, double volume, double sl, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = NormalizeDouble(volume, 2);
   request.type = type;
   request.price = (type == ORDER_TYPE_BUY) ? 
                     SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                     SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   request.deviation = 10;
   request.type_filling = orderFill;
   request.magic = EAMagic;
   
   bool success = OrderSend(request, result);
   
   if(success && result.retcode == TRADE_RETCODE_DONE) {
      // Add to auto-close list if needed
      if(AutoCloseMinutes > 0) {
         int size = ArraySize(tradeTickets);
         ArrayResize(tradeTickets, size + 1);
         ArrayResize(tradeCloseTimes, size + 1);
         
         tradeTickets[size] = result.deal;
         tradeCloseTimes[size] = TimeCurrent() + AutoCloseMinutes * 60;
      }
      return true;
   } else {
      Print("Order send failed. Result code: ", result.retcode, " Comment: ", result.comment);
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Close position by ticket                                         |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = _Symbol;
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.type = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                     SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                     SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.deviation = 10;
   request.type_filling = orderFill;
   request.magic = EAMagic;
   
   bool success = OrderSend(request, result);
   if(!success || result.retcode != TRADE_RETCODE_DONE) {
      Print("Failed to close position. Error: ", GetLastError(), " Result code: ", result.retcode);
   }
   
   return success && result.retcode == TRADE_RETCODE_DONE;
}

//+------------------------------------------------------------------+
//| Trail stops for open positions                                   |
//+------------------------------------------------------------------+
void TrailStops()
{
   // Only apply trailing stop if enabled
   if(!TrailingStop) return;
   
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      
      // Check if this is our position
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EAMagic) {
         double currentSL = PositionGetDouble(POSITION_SL);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         // Calculate new stop loss based on position type
         double newSL = 0;
         bool modifyNeeded = false;
         
         if(posType == POSITION_TYPE_BUY) {
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            newSL = NormalizeDouble(currentPrice - stopLossPoints, _Digits);
            
            // Only move SL up, never down
            if(newSL > currentSL && newSL > openPrice) {
               modifyNeeded = true;
            }
         } else { // POSITION_TYPE_SELL
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            newSL = NormalizeDouble(currentPrice + stopLossPoints, _Digits);
            
            // Only move SL down, never up
            if((newSL < currentSL || currentSL == 0) && newSL < openPrice) {
               modifyNeeded = true;
            }
         }
         
         // Update stop loss if needed
         if(modifyNeeded) {
            ModifyPositionSL(ticket, newSL);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify position stop loss                                        |
//+------------------------------------------------------------------+
bool ModifyPositionSL(ulong ticket, double newSL)
{
   if(!PositionSelectByTicket(ticket)) return false;
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = _Symbol;
   request.sl = NormalizeDouble(newSL, _Digits);
   request.tp = PositionGetDouble(POSITION_TP);
   
   bool success = OrderSend(request, result);
   if(!success || result.retcode != TRADE_RETCODE_DONE) {
      Print("Failed to modify SL. Error: ", GetLastError(), " Result code: ", result.retcode);
   }
   
   return success && result.retcode == TRADE_RETCODE_DONE;
}

//+------------------------------------------------------------------+
//| Helper function to remove elements from array                    |
//+------------------------------------------------------------------+
void ArrayRemove(int &arr[], int start_pos, int count)
{
   int arr_size = ArraySize(arr);
   if(start_pos < 0 || start_pos >= arr_size) return;
   count = MathMin(count, arr_size - start_pos);
   
   for(int i = start_pos; i < arr_size - count; i++) {
      arr[i] = arr[i + count];
   }
   ArrayResize(arr, arr_size - count);
}

void ArrayRemove(ulong &arr[], int start_pos, int count)
{
   int arr_size = ArraySize(arr);
   if(start_pos < 0 || start_pos >= arr_size) return;
   count = MathMin(count, arr_size - start_pos);
   
   for(int i = start_pos; i < arr_size - count; i++) {
      arr[i] = arr[i + count];
   }
   ArrayResize(arr, arr_size - count);
}

void ArrayRemove(datetime &arr[], int start_pos, int count)
{
   int arr_size = ArraySize(arr);
   if(start_pos < 0 || start_pos >= arr_size) return;
   count = MathMin(count, arr_size - start_pos);
   
   for(int i = start_pos; i < arr_size - count; i++) {
      arr[i] = arr[i + count];
   }
   ArrayResize(arr, arr_size - count);
}
//+------------------------------------------------------------------+