// Copyright (c) 2017 Mystic Pants Pty Ltd
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

class CurrentSensor{
    DEBUG = false;
    WINDING_RATIO = 60;
    GAUGE_FILTER = 100;
    GAUGE_RATIO = 20.0;
    ZERO_OFFSET = 120;
    MAX_ADC = 65535.0;
    POLL_FREQ = 0.5;
    _currentSensorPin = null;
    
    constructor(currentSensorPin) {
        _currentSensorPin = currentSensorPin;
        _currentSensorPin.configure(ANALOG_IN);
    }
    
    // function that reads the current
    // 
    // @params none
    // @returns none
    // 
    function readCurrent(cb = null) {
        local maxReading = 0;
        local minReading = 0;
        local currentGauge = 0; 
        local previousReading = 0;
        
        // Take 1000 samples
        for (local i = 0; i < 1000; i++) {
            // Average every 3 readings
            local currentReading = (_currentSensorPin.read() + _currentSensorPin.read() + _currentSensorPin.read())/3.0;
            previousReading = currentReading;

            // If the reading is larger, save as maxReading.
            if (currentReading > maxReading) {
                maxReading = currentReading;
                // Apply a Lowpass Filter
                currentGauge = currentGauge + (currentReading - currentGauge)/GAUGE_FILTER;
            }

            // If the reading is smaller,save as minReading
            if (currentReading < minReading) {
                minReading = currentReading;
                
            }
        }

        // Calculate the voltage amplitude and current
        local voltageDiff = (maxReading - minReading - ZERO_OFFSET)/ MAX_ADC * hardware.voltage();
        local calcCurrent = voltageDiff*WINDING_RATIO;
        currentGauge = (currentGauge/GAUGE_RATIO);
        
        local result = {
            "current" : calcCurrent, 
            "currentgauge": currentGauge.tointeger(),
        }
        
        if (DEBUG){
            server.log("Our Current Gauge Shows:" + currentGauge);
            server.log("Our Sensor Voltage Reading is:" + voltageDiff);
            server.log("Our Current Reading is:" + calcCurrent);
        }
        
        // Return table if no callback was passed
        if (cb == null) { return result; }

        // Invoke the callback if one was passed
        imp.wakeup(0, function() { cb(result); });
    }
    
}