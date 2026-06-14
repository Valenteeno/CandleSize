//+------------------------------------------------------------------+
//|                                     CandlestickSizeIndicator.mq5 |
//|                                     Copyright 2025, Teenodi Ltd. |
//|                                         https://www.jukwaese.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Teenodi Ltd."
#property link      "https://www.jukwaese.com"
#property version   "1.04"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- plot BuySignal
#property indicator_label1  "BuySignal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- plot SellSignal
#property indicator_label2  "SellSignal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

//============================ inputs ===============================
enum CandleSizeType {
   HIGH_LOW,    // High-Low (Total Height)
   OPEN_CLOSE   // Open-Close (Body Height)
};
enum TradeDirection {
   FOLLOW,      // Follow Candle Direction
   OPPOSITE     // Opposite Candle Direction
};
input CandleSizeType CandleSizeOption = HIGH_LOW;       // Candle Size Option to Use
input double CandleSizeThreshold = 50;                  // Candle Size Threshold (points)
input TradeDirection TradeDirectionOption = OPPOSITE;    // Trade Direction Option
input int ArrowOffset = 1;                             // Arrow offset in points from the candle

//--- indicator buffers
double   BuyBuffer[];
double   SellBuffer[];

//=========================== globals ===============================
double candleSize;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize point values
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   candleSize = NormalizeDouble(CandleSizeThreshold * point, _Digits);
   
   // Set up indicator buffers
   SetIndexBuffer(0, BuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);
   
   // Set arrow code
   PlotIndexSetInteger(0, PLOT_ARROW, 233); // Up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 234); // Down arrow
   
   // Initialize buffers with EMPTY_VALUE
   ArrayInitialize(BuyBuffer, EMPTY_VALUE);
   ArrayInitialize(SellBuffer, EMPTY_VALUE);
   
   // Set indicator name
   string shortName = "CandlestickSize(" + 
                     (CandleSizeOption == HIGH_LOW ? "H-L" : "O-C") + 
                     ", " + DoubleToString(CandleSizeThreshold, 0) + "pts, " +
                     (TradeDirectionOption == FOLLOW ? "Follow" : "Opposite") + ")";
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // Ensure we have enough data
   if(rates_total < 1) return 0;
   
   // Calculate start position
   int start;
   
   // If this is the first call or recalculation
   if(prev_calculated == 0) {
      start = 0; // Calculate all bars
   } else {
      start = prev_calculated - 1; // Start from the last calculated bar
      
      // Ensure we don't go out of range
      if(start < 0) start = 0;
      if(start >= rates_total) start = rates_total - 1;
   }
   
   // Main calculation loop
   for(int i = start; i < rates_total; i++) {
      // Calculate candle size based on selected option
      double size = 0;
      bool isBullishCandle = (close[i] > open[i]);
      
      switch(CandleSizeOption) {
         case HIGH_LOW:
            size = high[i] - low[i];
            break;
         case OPEN_CLOSE:
            size = MathAbs(close[i] - open[i]);
            break;
      }
      
      // Clear existing values for the current bar
      BuyBuffer[i] = EMPTY_VALUE;
      SellBuffer[i] = EMPTY_VALUE;
      
      // Check if candle size meets threshold
      if(size >= candleSize) {
         // Determine signal direction based on candle and user option
         bool buySignal;
         
         if(TradeDirectionOption == FOLLOW) {
            buySignal = isBullishCandle;
         } else { // OPPOSITE
            buySignal = !isBullishCandle;
         }
         
         // Set appropriate buffer
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double offset = ArrowOffset * point;
         
         if(buySignal) {
            // Buy signal - place arrow below the candle
            BuyBuffer[i] = low[i] - offset;
         } else {
            // Sell signal - place arrow above the candle
            SellBuffer[i] = high[i] + offset;
         }
      }
   }
   
   // Return value of prev_calculated for next call
   return(rates_total);
}
//+------------------------------------------------------------------+