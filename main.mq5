#include <Trade/Trade.mqh>
CTrade Trade;

int barsTotal;

input double risk2reward = 3.5;
input double Lots = 0.01;
input int START_HOUR = 2;    // Start time to find price range
input int END_HOUR = 9;      // End time to find price range
input int LINE_END_HOUR = 12; // End time for drawing the lines
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_H1;  // Timeframe

void SetChartAppearance() {
    ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);     // Background
    ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrBlack);     // Text & scales
    ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrWhite); // Bullish candles
    ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrBlack); // Bearish candles
    ChartSetInteger(0, CHART_COLOR_CHART_UP, clrBlack);         // Bar up color
    ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrBlack);     // Bar down color
    ChartSetInteger(0, CHART_SHOW_GRID, false);                     // Hide grid
    ChartSetInteger(0, CHART_MODE, CHART_CANDLES);                 // Candlestick mode
    ChartSetInteger(0, CHART_COLOR_CHART_LINE, clrBlack);           // Line chart color
}

enum TimeState {
    STATE_OUTSIDE_TIME = 0,     // Outside trading time window
    STATE_IN_TIME = 1,          // Within trading time window
    STATE_TRADE_TIME = 2        // Within trade execution time window
};

enum MarketActionState {
    STATE_TAKE_LIQUIDITY_A = 0, // Taking liquidity at level A
    STATE_TAKE_LIQUIDITY_B = 1, // Taking liquidity at level B 
    STATE_CHOCH_BULLISH = 2,    // Bullish Change of Character detected
    STATE_CHOCH_BEARISH = 3,    // Bearish Change of Character detected
    STATE_ORDERBLOCK_BULLISH = 4, // Bullish Order Block detected
    STATE_ORDERBLOCK_BEARISH = 5,  // Bearish Order Block detected
    STATE_NOTHING = 6             // No significant market action detected
};

string GetTimeStateText(TimeState state) {
    string stateText;
    switch(state) {
        case STATE_IN_TIME:
            stateText = "Scanning for Setup";
            break;
        case STATE_OUTSIDE_TIME:
            stateText = "Outside Trading Window"; 
            break;
        case STATE_TRADE_TIME:
            stateText = "Ready to Execute";
            break;
        default:
            stateText = "Unknown Time State";
    }
    return stateText;
}

string GetMarketActionStateText(MarketActionState state) {
    string stateText;
    switch(state) {
        case STATE_TAKE_LIQUIDITY_A:
            stateText = "Taking Liquidity at Level A";
            break;
        case STATE_TAKE_LIQUIDITY_B:
            stateText = "Taking Liquidity at Level B";
            break;            
        case STATE_CHOCH_BULLISH:
            stateText = "Bullish CHoCH Detected";
            break;
        case STATE_CHOCH_BEARISH:
            stateText = "Bearish CHoCH Detected";
            break;
        case STATE_ORDERBLOCK_BULLISH:
            stateText = "Bullish OB Detected";
            break;
        case STATE_ORDERBLOCK_BEARISH:
            stateText = "Bearish OB Detected";
            break;
        default:
            stateText = "Unknown Market Action State";
    }
    return stateText;
}

// Current time state
TimeState currentTimeState = STATE_OUTSIDE_TIME;
// Current market action state
MarketActionState currentState = STATE_NOTHING;

double ASIA_High = 0;
double ASIA_Low = DBL_MAX;

// Swings
double Highs[];
double Lows[];
datetime HighsTime[];
datetime LowsTime[];

double A_value = DBL_MAX;
double B_value  = 0;
datetime A_time;
datetime B_time;

datetime lastBuTime = 0;
datetime lastBeTime = 0;
double buValue = 0;
double beValue = 0;

double bullishOrderBlockHigh[];
double bullishOrderBlockLow[];
datetime bullishOrderBlockTime[];

double bearishOrderBlockHigh[];
double bearishOrderBlockLow[];
datetime bearishOrderBlockTime[];

double untouchedHighs[];
double untouchedLows[];
datetime untouchedHighsTime[];
datetime untouchedLowsTime[];

MqlDateTime previousDateStruct;

string Mode = "None";

void DrawLine(string name, datetime time1, double price1, datetime time2, double price2) {
   ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price2);

   if (price2 > price1)
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);  // Line color
   else if (price1 > price2)
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);  // Line color
   else
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);  // Line color

   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);       // Line thickness
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false); // No infinite extension
}

void createObj(datetime time, double price, int arrowCode, int direction, color clr, string txt) {
    string objName ="";
    StringConcatenate(objName, "Signal@", time, "at", DoubleToString(price, _Digits), "(", arrowCode, ")");

    double ask=SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid=SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double spread=ask-bid;

    if(direction > 0)
        price += 2*spread * _Point;
    else if(direction < 0)
        price -= 2*spread * _Point;

    if(ObjectCreate(0, objName, OBJ_ARROW, 0, time, price)) {
        ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, arrowCode);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
        if(direction > 0)
            ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_TOP);
        if(direction < 0)
            ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
    }

    string objNameDesc = objName + txt;
    if(ObjectCreate(0, objNameDesc, OBJ_TEXT, 0, time, price)) {
        ObjectSetString(0, objNameDesc, OBJPROP_TEXT, "  " + txt);
        ObjectSetInteger(0, objNameDesc, OBJPROP_COLOR, clr);
        if(direction > 0)
            ObjectSetInteger(0, objNameDesc, OBJPROP_ANCHOR, ANCHOR_TOP);
        if(direction < 0)
            ObjectSetInteger(0, objNameDesc, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
    }
}

int OnInit() {
    SetChartAppearance();

    ArraySetAsSeries(Highs, true);
    ArraySetAsSeries(Lows, true);
    ArraySetAsSeries(HighsTime, true);
    ArraySetAsSeries(LowsTime, true);

    ArraySetAsSeries(bullishOrderBlockHigh,true);
    ArraySetAsSeries(bullishOrderBlockLow,true);
    ArraySetAsSeries(bullishOrderBlockTime,true);

    ArraySetAsSeries(bearishOrderBlockHigh,true);
    ArraySetAsSeries(bearishOrderBlockLow,true);
    ArraySetAsSeries(bearishOrderBlockTime,true);

    ArraySetAsSeries(untouchedHighs, true);
    ArraySetAsSeries(untouchedLows, true);
    ArraySetAsSeries(untouchedHighsTime, true);
    ArraySetAsSeries(untouchedLowsTime, true);

    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

// Function to get the highest price within a time range
double GetHighestPriceInRange(datetime startTime, datetime endTime) {
    double highestPrice = 0;

    int startShift = iBarShift(_Symbol, InpTimeframe, startTime);
    int endShift = iBarShift(_Symbol, InpTimeframe, endTime);
    
    if(startShift == -1 || endShift == -1)
    {
        Print("Bars not found for the specified time range.");
        return -1;
    }
    
    for(int i = endShift; i <= startShift; i++)
    {
        double high = iHigh(_Symbol, InpTimeframe, i);
        if(high > highestPrice)
            highestPrice = high;
    }
    
    return highestPrice;
}

// Function to get the lowest price within a time range
double GetLowestPriceInRange(datetime startTime, datetime endTime) {
    double lowestPrice = DBL_MAX;
    
    int startShift = iBarShift(_Symbol, InpTimeframe, startTime);
    int endShift = iBarShift(_Symbol, InpTimeframe, endTime);
    
    if(startShift == -1 || endShift == -1)
    {
        Print("Bars not found for the specified time range.");
        return -1;
    }
    
    for(int i = endShift; i <= startShift; i++)
    {
        double low = iLow(_Symbol, InpTimeframe, i);
        if(low < lowestPrice)
            lowestPrice = low;
    }
    
    return lowestPrice;
}

// Function to highlight the time range
void HighlightTimeRange() {
    MqlDateTime tempTime;
    TimeToStruct(TimeCurrent(), tempTime);

    tempTime.hour = END_HOUR;
    tempTime.min = 0;
    tempTime.sec = 0;
    datetime startTime = StructToTime(tempTime);

    tempTime.hour = END_HOUR;
    tempTime.min = 22;
    datetime start1Time = StructToTime(tempTime);

    tempTime.hour = END_HOUR + 1;
    tempTime.min = 7;
    datetime end1Time = StructToTime(tempTime);

    tempTime.hour = END_HOUR + 1;
    tempTime.min = 52;
    datetime start2Time = StructToTime(tempTime);

    tempTime.hour = END_HOUR + 2;
    tempTime.min = 37;
    datetime end2Time = StructToTime(tempTime);

    tempTime.hour = LINE_END_HOUR;
    tempTime.min = 0;
    datetime endTime = StructToTime(tempTime);

    // Update market state based on time ranges using timeState
    if(TimeCurrent() >= start1Time && TimeCurrent() <= end1Time)
        currentTimeState = STATE_TRADE_TIME;
    else if(TimeCurrent() >= start2Time && TimeCurrent() <= end2Time)
        currentTimeState = STATE_TRADE_TIME;
    else if(TimeCurrent() >= startTime && TimeCurrent() <= endTime)
        currentTimeState = STATE_IN_TIME;
    else
        currentTimeState = STATE_OUTSIDE_TIME;

    string highlightName = "TimeHighlight_main" + "_" + IntegerToString(tempTime.day);  
    if(ObjectCreate(0, highlightName, OBJ_RECTANGLE, 0, startTime, 1.9, endTime, 0.5)) {
        ObjectSetInteger(0, highlightName, OBJPROP_COLOR, C'225,225,141');
        ObjectSetInteger(0, highlightName, OBJPROP_FILL, true);
        ObjectSetInteger(0, highlightName, OBJPROP_BACK, true);
        ObjectSetInteger(0, highlightName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, highlightName, OBJPROP_SELECTED, false);
        ObjectSetInteger(0, highlightName, OBJPROP_HIDDEN, true);
    }
    string highlightName1 = "TimeHighlight_1" + "_" + IntegerToString(tempTime.day);  
    if(ObjectCreate(0, highlightName1, OBJ_RECTANGLE, 0, start1Time, 1.9, end1Time, 0.5)) {
        ObjectSetInteger(0, highlightName1, OBJPROP_COLOR, C'163,177,240');
        ObjectSetInteger(0, highlightName1, OBJPROP_FILL, true);
        ObjectSetInteger(0, highlightName1, OBJPROP_BACK, true);
        ObjectSetInteger(0, highlightName1, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, highlightName1, OBJPROP_SELECTED, false);
        ObjectSetInteger(0, highlightName1, OBJPROP_HIDDEN, true);
    }
    string highlightName2 = "TimeHighlight_2" + "_" + IntegerToString(tempTime.day);  
    if(ObjectCreate(0, highlightName2, OBJ_RECTANGLE, 0, start2Time, 1.9, end2Time, 0.5)) {
        ObjectSetInteger(0, highlightName2, OBJPROP_COLOR, C'163,177,240');
        ObjectSetInteger(0, highlightName2, OBJPROP_FILL, true);
        ObjectSetInteger(0, highlightName2, OBJPROP_BACK, true);
        ObjectSetInteger(0, highlightName2, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, highlightName2, OBJPROP_SELECTED, false);
        ObjectSetInteger(0, highlightName2, OBJPROP_HIDDEN, true);
    }
}

// Get current server time
void CheckAndDrawDailyRange(MqlDateTime &currentDateStruct) {
    // Check if the date has changed
    if(currentDateStruct.year != previousDateStruct.year || currentDateStruct.mon != previousDateStruct.mon || currentDateStruct.day != previousDateStruct.day) {
        // Create start and end times for the analysis period
        MqlDateTime tempTime = currentDateStruct;
        tempTime.hour = START_HOUR;
        tempTime.min = 0;
        tempTime.sec = 0;
        datetime startTime = StructToTime(tempTime);
        
        tempTime.hour = END_HOUR;
        datetime endTime = StructToTime(tempTime);

        ASIA_High = GetHighestPriceInRange(startTime, endTime);
        ASIA_Low = GetLowestPriceInRange(startTime, endTime);

        if(ASIA_High != -1 && ASIA_Low != -1) {
            tempTime.hour = LINE_END_HOUR;
            datetime lineEndTime = StructToTime(tempTime);

            // Create high line
            string highObjName = "DailyHigh_" + IntegerToString(currentDateStruct.year) + IntegerToString(currentDateStruct.mon) + IntegerToString(currentDateStruct.day);
            string highObjNameDesc = highObjName + "txt";
            if(ObjectCreate(0, highObjName, OBJ_TREND, 0, endTime, ASIA_High, lineEndTime, ASIA_High)) {
                ObjectSetInteger(0, highObjName, OBJPROP_COLOR, clrBlack);
                ObjectSetInteger(0, highObjName, OBJPROP_WIDTH, 2);
                ObjectSetInteger(0, highObjName, OBJPROP_STYLE, STYLE_SOLID);
                if(ObjectCreate(0, highObjNameDesc, OBJ_TEXT, 0, endTime, ASIA_High)){
                    ObjectSetString(0, highObjNameDesc, OBJPROP_TEXT, "Asia High");
                    ObjectSetInteger(0, highObjNameDesc, OBJPROP_COLOR, clrBlack);
                }
            }
            
            // Create low line
            string lowObjName = "DailyLow_" + IntegerToString(currentDateStruct.year) + IntegerToString(currentDateStruct.mon) + IntegerToString(currentDateStruct.day);
            string lowObjNameDesc = lowObjName + "txt";
            if(ObjectCreate(0, lowObjName, OBJ_TREND, 0, endTime, ASIA_Low, lineEndTime, ASIA_Low)) {
                ObjectSetInteger(0, lowObjName, OBJPROP_COLOR, clrBlack);
                ObjectSetInteger(0, lowObjName, OBJPROP_WIDTH, 2);
                ObjectSetInteger(0, lowObjName, OBJPROP_STYLE, STYLE_SOLID);
                if(ObjectCreate(0, lowObjNameDesc, OBJ_TEXT, 0, endTime, ASIA_Low)){
                    ObjectSetString(0, lowObjNameDesc, OBJPROP_TEXT, "Asia Low");
                    ObjectSetInteger(0, lowObjNameDesc, OBJPROP_COLOR, clrBlack);
                }
            }
            
            Print("Price range between ", START_HOUR, ":00 and ", END_HOUR, ":00 - High: ", ASIA_High, " Low: ", ASIA_Low);
        }
        // Update the previous date
        previousDateStruct = currentDateStruct;
    }
}

void DrawAndStoreUntouchedHighLowLines() {
    datetime finishTime = TimeCurrent() + 86400; // Add 24 hours (86400 seconds) to get the time of tomorrow
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    CopyRates(_Symbol, PERIOD_D1, 0, 14, rates);

    for(int i = 1; i < ArraySize(rates); i++) {
        bool highTouched = false;
        bool lowTouched = false;
        for(int j = 1; j <= ArraySize(rates); j++) {
            if(j >= i) break; // Only check new candles after the day of interest
            double dayHigh = iHigh(_Symbol, PERIOD_D1, j);
            double dayLow = iLow(_Symbol, PERIOD_D1, j);
            if(dayHigh >= rates[i].high) highTouched = true;
            if(dayLow <= rates[i].low) lowTouched = true;
        }
        if(!highTouched) {
            string highLineName = "HighLine_" + IntegerToString(i);
            string highLineDesc = "High_" + TimeToString(rates[i].time);
            ObjectCreate(0, highLineName, OBJ_TREND, 0, rates[i].time, rates[i].high, finishTime, rates[i].high);
            if(ObjectCreate(0, highLineDesc, OBJ_TEXT, 0, rates[i].time, rates[i].high)){
                ObjectSetString(0, highLineDesc, OBJPROP_TEXT, highLineDesc);
                ObjectSetInteger(0, highLineDesc, OBJPROP_COLOR, clrBlack);
            }
            ArrayResize(untouchedHighs, ArraySize(untouchedHighs) + 1);
            ArrayResize(untouchedHighsTime, ArraySize(untouchedHighsTime) + 1);
            untouchedHighs[ArraySize(untouchedHighs) - 1] = rates[i].high;
            untouchedHighsTime[ArraySize(untouchedHighsTime) - 1] = rates[i].time;
        }
        if(!lowTouched) {
            Print(i, "   Low");
            string lowLineName = "LowLine_" + IntegerToString(i);
            string lowLineDesc = "Low_" + TimeToString(rates[i].time);
            ObjectCreate(0, lowLineName, OBJ_TREND, 0, rates[i].time, rates[i].low, finishTime, rates[i].low);
            if(ObjectCreate(0, lowLineDesc, OBJ_TEXT, 0, rates[i].time, rates[i].low)){
                ObjectSetString(0, lowLineDesc, OBJPROP_TEXT, lowLineDesc);
                ObjectSetInteger(0, lowLineDesc, OBJPROP_COLOR, clrBlack);
            }
            ArrayResize(untouchedLows, ArraySize(untouchedLows) + 1);
            ArrayResize(untouchedLowsTime, ArraySize(untouchedLowsTime) + 1);
            untouchedLows[ArraySize(untouchedLows) - 1] = rates[i].low;
            untouchedLowsTime[ArraySize(untouchedLowsTime) - 1] = rates[i].time;
        }
    }
}

void OnTick() {
    int bars = iBars(_Symbol, PERIOD_CURRENT);

    if(barsTotal == bars) return;
    else   barsTotal = bars;

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    CopyRates(_Symbol, PERIOD_CURRENT, 0, 50, rates);
    
    datetime currentTime = TimeCurrent();
    MqlDateTime currentDateStruct;
    TimeToStruct(currentTime, currentDateStruct);

    //if(currentDateStruct.hour == 0 && currentDateStruct.min == 0)
    //    DrawAndStoreUntouchedHighLowLines();

    if(currentDateStruct.hour == END_HOUR && currentDateStruct.min == 0 )
        CheckAndDrawDailyRange(currentDateStruct);

    HighlightTimeRange();
    swingPoints();

    int isOrderBlock = orderBlock();

    if(currentTimeState != STATE_OUTSIDE_TIME && currentState == STATE_NOTHING) {
        if (A_value < ASIA_Low){
            currentState = STATE_TAKE_LIQUIDITY_A;
            Mode = "BUY";
        }
        if (B_value > ASIA_High){
            currentState = STATE_TAKE_LIQUIDITY_B;
            Mode = "SELL";
        }
    }
    if (currentTimeState == STATE_OUTSIDE_TIME){
        currentState = STATE_NOTHING;
        Mode = "None";
        A_value = DBL_MAX;
        B_value = 0;
    }
    
    if (ArraySize(HighsTime) > 0 && ArraySize(LowsTime) > 0 && ArraySize(Highs) > 0 && ArraySize(Lows) > 0 && ArraySize(bullishOrderBlockTime) > 0 && ArraySize(bearishOrderBlockTime) > 0) {
        if (Mode != "BUY"){
            //CHoch Bullish
            if(rates[1].high > B_value && rates[2].close < B_value && B_time != lastBuTime) {
                if (currentState == STATE_CHOCH_BEARISH)
                    currentState = STATE_CHOCH_BULLISH;
                lastBuTime = B_time;
                buValue = B_value;
            }
            //CHoch Bearish  
            if(rates[1].low < A_value && rates[2].close > A_value && A_time != lastBeTime) {
                if (currentState == STATE_TAKE_LIQUIDITY_B || currentState == STATE_CHOCH_BULLISH)
                    currentState = STATE_CHOCH_BEARISH;
                lastBeTime = A_time;
                beValue = A_value;
            }

            if (currentTimeState != STATE_OUTSIDE_TIME && Highs[0] > B_value){
                A_time = LowsTime[0];
                A_value = Lows[0];
                // DrawLine("HighLowLine" + TimeToString(B_time), A_time, A_value, B_time, B_value);
                B_time = HighsTime[0];
                B_value = Highs[0];
                // DrawLine("HighLowLine" + TimeToString(A_time), B_time, B_value, A_time, A_value);
            }
        }

        if (Mode != "SELL"){
            //CHoch Bullish
            if(rates[1].high > B_value && rates[2].close < B_value && B_time != lastBuTime) {
                if (currentState == STATE_TAKE_LIQUIDITY_A || currentState == STATE_CHOCH_BEARISH)
                    currentState = STATE_CHOCH_BULLISH;
                lastBuTime = B_time;
                buValue = B_value;
            }
            //CHoch Bearish  
            if(rates[1].low < A_value && rates[2].close > A_value && A_time != lastBeTime) {
                if (currentState == STATE_CHOCH_BULLISH)
                    currentState = STATE_CHOCH_BEARISH;
                lastBeTime = A_time;
                beValue = A_value;
            }

            if (currentTimeState != STATE_OUTSIDE_TIME && Lows[0] < A_value){
                B_time = HighsTime[0];
                B_value = Highs[0];
                // DrawLine("HighLowLine" + TimeToString(A_time), B_time, B_value, A_time, A_value);
                A_time = LowsTime[0];
                A_value = Lows[0];
                // DrawLine("HighLowLine" + TimeToString(B_time), A_time, A_value, B_time, B_value);
            }
        }

        string BObjName = "B";
        if(ObjectCreate(0, BObjName, OBJ_TEXT, 0, B_time, B_value)) {
            ObjectSetString(0, BObjName, OBJPROP_TEXT, BObjName);
            ObjectSetInteger(0, BObjName, OBJPROP_COLOR, C'64,0,255');
        }
        string AObjName = "A";
        if(ObjectCreate(0, AObjName, OBJ_TEXT, 0, A_time, A_value)) {
            ObjectSetString(0, AObjName, OBJPROP_TEXT, AObjName);
            ObjectSetInteger(0, AObjName, OBJPROP_COLOR, C'64,0,255');
        }
        string bChoch = "B choch" + TimeToString(rates[0].time);
        if(ObjectCreate(0, bChoch, OBJ_TREND, 0, B_time, B_value, rates[0].time, B_value)) {
            ObjectSetInteger(0, bChoch, OBJPROP_COLOR, clrGreen);
            ObjectSetInteger(0, bChoch, OBJPROP_WIDTH, 4);
        }

        string achoch = "A choch" + TimeToString(rates[0].time);
        if(ObjectCreate(0, achoch, OBJ_TREND, 0, A_time, A_value, rates[0].time, A_value)) {
            ObjectSetInteger(0, achoch, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, achoch, OBJPROP_WIDTH, 4);
        }
       
       bool sellOB = (bullishOrderBlockTime[0] - B_time <= 120) && (bullishOrderBlockTime[0] >= B_time) && (isOrderBlock == 1);
       if (Mode == "SELL" && currentState == STATE_CHOCH_BULLISH && currentTimeState == STATE_TRADE_TIME  && sellOB) {
            Print(bullishOrderBlockTime[0], "    " ,B_time, "  ", bullishOrderBlockTime[0] - B_time);
           double entryprice = rates[0].open;
           entryprice = NormalizeDouble(entryprice,_Digits);
   
           double stoploss = B_value;
           stoploss = NormalizeDouble(stoploss,_Digits);
   
           double riskvalue = stoploss - entryprice;
           riskvalue = NormalizeDouble(riskvalue,_Digits);
   
           double takeprofit = entryprice - (risk2reward * riskvalue);
           takeprofit = NormalizeDouble(takeprofit,_Digits);
   
           // Attempt to open position
           if (Trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, Lots, entryprice, stoploss, takeprofit, "Sell Test")) {
               Print("Position opened successfully.");
               currentState = STATE_TAKE_LIQUIDITY_B;
           } else
               Print("Failed to open position. Error code: ", GetLastError());
       }
   
       bool buyOB = (bearishOrderBlockTime[0] - A_time >= 120) && (bearishOrderBlockTime[0] <= A_time) && (isOrderBlock == -1);
       if (Mode == "BUY" && currentState == STATE_CHOCH_BEARISH && currentTimeState == STATE_TRADE_TIME && buyOB) {
           double entryprice = rates[0].open;
           entryprice = NormalizeDouble(entryprice,_Digits);
   
           double stoploss = MathMin(bearishOrderBlockLow[0], A_value);
           stoploss = NormalizeDouble(stoploss,_Digits);
   
           double riskvalue = entryprice - stoploss;
           riskvalue = NormalizeDouble(riskvalue,_Digits);
   
           double takeprofit = entryprice + (risk2reward * riskvalue);
           takeprofit = NormalizeDouble(takeprofit,_Digits);
   
           // Attempt to open position
           if (Trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, Lots, entryprice, stoploss, takeprofit, "Buy Test")) {
               Print("Position opened successfully.");
               currentState = STATE_TAKE_LIQUIDITY_A;
           } else
               Print("Failed to open position. Error code: ", GetLastError());
           
       }
   
       Comment("Current State: " + GetMarketActionStateText(currentState) + ", Time: " + GetTimeStateText(currentTimeState) + ", Mode: " + Mode);
    }
}

void swingPoints() {
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, 50, rates);
    //SwingHigh
    if(rates[2].high >= rates[3].high && rates[2].high >= rates[1].high) {
        ArrayResize(Highs, MathMin(ArraySize(Highs) + 1, 10));
        for(int i = ArraySize(Highs) - 1;i > 0;--i)
            Highs[i] = Highs[i - 1];
        Highs[0] = rates[2].high;

        ArrayResize(HighsTime, MathMin(ArraySize(HighsTime) + 1, 10));
        for(int i= ArraySize(HighsTime) - 1;i>0;--i)
            HighsTime[i] = HighsTime[i - 1];
        HighsTime[0] = rates[2].time;

        createObj(rates[2].time, rates[2].high, 234, -1, clrOrangeRed, "");
    }
    //SwingLow
    if(rates[2].low <= rates[3].low && rates[2].low <= rates[1].low) {
        ArrayResize(Lows, MathMin(ArraySize(Lows) + 1, 10));
        for(int i= ArraySize(Lows) - 1;i>0;--i)
            Lows[i] = Lows[i - 1];
        Lows[0] = rates[2].low;

        ArrayResize(LowsTime, MathMin(ArraySize(LowsTime) + 1, 10));
        for(int i= ArraySize(LowsTime) - 1;i>0;--i)
            LowsTime[i] = LowsTime[i - 1];
        LowsTime[0] = rates[2].time;

        createObj(rates[2].time, rates[2].low, 233, 1, clrGreen, "");
    }
}

void createOrderBlock(int index, color clr, MqlRates &rates[], double &blockHigh[], double &blockLow[], datetime &blockTime[]) {
    double blockHighValue = rates[1].open;
    double blockLowValue = rates[1].low;
    datetime blockTimeValue = rates[1].time;

    // Shift existing elements in blockHigh[] to make space for the new value
    ArrayResize(blockHigh, ArraySize(blockHigh) + 1);
    for(int i = ArraySize(blockHigh) - 1; i > 0; --i)
        blockHigh[i] = blockHigh[i - 1];
    blockHigh[0] = blockHighValue;

    // Shift existing elements in blockLow[] to make space for the new value
    ArrayResize(blockLow, ArraySize(blockLow) + 1);
    for(int i = ArraySize(blockLow) - 1; i > 0; --i)
        blockLow[i] = blockLow[i - 1];
    blockLow[0] = blockLowValue;

    // Shift existing elements in blockTime[] to make space for the new value
    ArrayResize(blockTime, ArraySize(blockTime) + 1);
    for(int i = ArraySize(blockTime) - 1; i > 0; --i)
        blockTime[i] = blockTime[i - 1];
    blockTime[0] = blockTimeValue;

    string objName = " Bu.OB " + IntegerToString(index - 1) + TimeToString(rates[index].time);
    if(ObjectCreate(0, objName, OBJ_RECTANGLE, 0, rates[index].time, rates[index].high, rates[1].time, rates[1].close)){
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
    }
}

int orderBlock() {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, 50, rates);
   int direction = 0;

    // Bearish Order Block lvl 2
    if (rates[3].close > rates[3].open && rates[1].close < rates[3].low && rates[1].close < rates[2].low) {
        createOrderBlock(3, C'233,43,43', rates, bullishOrderBlockHigh, bullishOrderBlockLow, bullishOrderBlockTime);
        direction = 1;
    }

    // Bullish Order Block lvl 1
    if (rates[3].close < rates[3].open && rates[1].close > rates[3].high && rates[1].close > rates[2].high) {
        createOrderBlock(3, C'0,139,65', rates, bearishOrderBlockHigh, bearishOrderBlockLow, bearishOrderBlockTime);
        direction = -1;
    }

    // Bearish Order Block lvl 2 
    if (rates[2].close > rates[2].open && rates[1].close < rates[2].low) {
        createOrderBlock(2, C'223,134,32', rates, bullishOrderBlockHigh, bullishOrderBlockLow, bullishOrderBlockTime);
        direction = 1;
    }

    // Bullish Order Block lvl 1
    if (rates[2].close < rates[2].open && rates[1].close > rates[2].high) {
        createOrderBlock(2, C'0,65,139', rates, bearishOrderBlockHigh, bearishOrderBlockLow, bearishOrderBlockTime);
        direction = -1;
    }

    return direction;
}
