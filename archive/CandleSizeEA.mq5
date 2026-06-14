//+------------------------------------------------------------------+
//|                                             CandlestickSizeEA.mq5 |
//|                                     Copyright 2025, Teenodi Ltd. |
//|                                         https://www.jukwaese.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Teenodi Ltd."
#property link      "https://www.jukwaese.com"
#property version   "1.00"
#property strict
#property indicator_chart_window
#define EAMagic 754321

//============================ inputs ===============================
input group "Candle Size Settings"
enum CandleSizeType {
   HIGH_LOW,    // High-Low (Total Height)
   OPEN_CLOSE   // Open-Close (Body Height)
};
input CandleSizeType CandleSizeOption = HIGH_LOW;       // Candle Size Option to Use
input double CandleSizeThreshold = 50;                 // Candle Size Threshold (points)

input group "Trade Direction Settings"
enum TradeDirection {
   FOLLOW,      // Follow Candle Direction
   OPPOSITE     // Opposite Candle Direction
};
input TradeDirection TradeDirectionOption = OPPOSITE;    // Trade Direction Option

input group "Trade Settings"
input double TakeProfit = 250;                         // Take Profit (points)
input double StopLoss = 100;                           // Stop Loss (points)
input bool TrailingStop = false;                       // Use Trailing Stop
input int AutoCloseMinutes = 60;                       // Auto Close Time (minutes)
input double LotSize = 0.1;                            // Volume (lots)

input group "Indicator Settings"
input int HistoricalSignals = 1000;                      // Number of historical bars to check for signals
//input int ArrowSize = 5;                               // Size of arrow (1-5)
input int ArrowOffset = 1;                             // Arrow offset in points from the candle

//=========================== globals ===============================
// Constants
double candleSize, takeProfitPoints, stopLossPoints;
bool newBar = false;
datetime prevBarTime = 0;
int timerID = 0;
string arrowPrefix = "Arrow_";
int arrowCount = 0;

// Arrays to store trade tickets and their auto-close times
ulong tradeTickets[];
datetime tradeCloseTimes[];

//============================ functions =============================
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
   candleSize = NormalizeDouble(CandleSizeThreshold * point, _Digits);
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
   
   // Initialize previous bar time
   prevBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // Create a timer for checking auto-close trades
   if(AutoCloseMinutes > 0) {
      timerID = EventSetTimer(60); // Check every minute
   }
   
   // Draw historical signals
   DrawHistoricalSignals();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Delete all chart objects created by EA
   ObjectsDeleteAll(0, arrowPrefix);
   
   // Kill timer
   if(timerID != 0) {
      EventKillTimer();
   }
}

//+------------------------------------------------------------------+
//| Draw historical signals                                          |
//+------------------------------------------------------------------+
void DrawHistoricalSignals()
{
   // Limit the number of historical bars to check
   int barsToCheck = MathMin(HistoricalSignals, Bars(_Symbol, PERIOD_CURRENT) - 1);
   
   // Process historical bars from oldest to newest
   for(int i = barsToCheck; i > 0; i--) {
      // Get data from the historical bar
      double open = iOpen(_Symbol, PERIOD_CURRENT, i);
      double close = iClose(_Symbol, PERIOD_CURRENT, i);
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      datetime barTime = iTime(_Symbol, PERIOD_CURRENT, i);
      
      // Calculate candle size based on selected option
      double size = 0;
      bool isBullishCandle = (close > open);
      
      switch(CandleSizeOption) {
         case HIGH_LOW:
            size = high - low;
            break;
         case OPEN_CLOSE:
            size = MathAbs(close - open);
            break;
      }
      
      // Check if candle size meets threshold
      if(size >= candleSize) {
         // Determine trade direction based on candle and user option
         bool goLong;
         
         if(TradeDirectionOption == FOLLOW) {
            goLong = isBullishCandle;
         } else { // OPPOSITE
            goLong = !isBullishCandle;
         }
         
         // Draw the arrow for the signal
         DrawSignalArrow(goLong, high, low, barTime);
      }
   }
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
      CheckCandleSize();
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
//| Check candle size and generate signals                           |
//+------------------------------------------------------------------+
void CheckCandleSize()
{
   // Get data from the last completed bar (index 1)
   double open = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low = iLow(_Symbol, PERIOD_CURRENT, 1);
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 1);
   
   // Calculate candle size based on selected option
   double size = 0;
   bool isBullishCandle = (close > open);
   
   switch(CandleSizeOption) {
      case HIGH_LOW:
         size = high - low;
         break;
      case OPEN_CLOSE:
         size = MathAbs(close - open);
         break;
   }
   
   // Check if candle size meets threshold
   if(size >= candleSize) {
      // Determine trade direction based on candle and user option
      bool goLong;
      
      if(TradeDirectionOption == FOLLOW) {
         goLong = isBullishCandle;
      } else { // OPPOSITE
         goLong = !isBullishCandle;
      }
      
      // Draw arrow based on trade direction
      DrawSignalArrow(goLong, high, low, barTime);
      
      // Execute trade
      ExecuteTrade(goLong);
   }
}

//+------------------------------------------------------------------+
//| Draw signal arrow on chart                                       |
//+------------------------------------------------------------------+
void DrawSignalArrow(bool isLong, double high, double low, datetime time)
{
   string arrowName = arrowPrefix + IntegerToString(arrowCount++);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double offset = ArrowOffset * point;
   
   if(isLong) {
      // Create buy arrow (up arrow) below the candle
      ObjectCreate(0, arrowName, OBJ_ARROW_BUY, 0, time, low - offset);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, arrowName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR, ANCHOR_TOP);
   } else {
      // Create sell arrow (down arrow) above the candle
      ObjectCreate(0, arrowName, OBJ_ARROW_SELL, 0, time, high + offset);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, arrowName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
   }
   
   // Set arrow size and other properties
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, isLong ? 233 : 234); // Standard MT5 up/down arrows
   //ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, ArrowSize);
   ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
   ChartRedraw(0);
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
   
   return OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE;
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
   
   return OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE;
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