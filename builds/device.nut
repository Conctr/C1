// Copyright (c) 2017 Mystic Pants Pty Ltd
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

// Import Libraries
#require "ConnectionManager.lib.nut:2.0.0"
#require "conctr.device.class.nut:2.0.0"
#require "WS2812.class.nut:2.0.2"
#require "HTS221.class.nut:1.0.0"
#require "LPS22HB.class.nut:1.0.0"
#require "LIS3DH.class.nut:1.3.0"
#require "Button.class.nut:1.2.0"

// Copyright (c) 2017 Mystic Pants Pty Ltd
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

// Default configuration of the sleep pollers
const DEFAULT_POLLFREQ1 = 172800;
const DEFAULT_POLLFREQ2 = 86400;
const DEFAULT_POLLFREQ3 = 18000;
const DEFAULT_POLLFREQ4 = 3600;
const DEFAULT_POLLFREQ5 = 900;

// Constants
const LPS22HB_ADDR_IE = 0xB8; // Imp explorer
const LPS22HB_ADDR_ES = 0xBE; // Sensor node
const LIS3DH_ADDR = 0x32;
const NO_WIFI_SLEEP_PERIOD = 30;
const DEBUG = 1;

// Hardware type enumeration
enum HardwareType {
    environmentSensor,
    impExplorer
}

class ImpExplorer {

    reading = null;
    config = null;

    _pollRunning = false;
    _sleepTime = 0;
    _buttonPressed = false;

    constructor() {

        reading = {
            "pressure": null,
            "temperature": null,
            "humidity": null,
            "battery": null,
            "acceleration_x": null,
            "acceleration_y": null,
            "acceleration_z": null,
            "light": null,
            "rssi": null
        };


        config = {
            "pollFreq1": DEFAULT_POLLFREQ1,
            "pollFreq2": DEFAULT_POLLFREQ2,
            "pollFreq3": DEFAULT_POLLFREQ3,
            "pollFreq4": DEFAULT_POLLFREQ4,
            "pollFreq5": DEFAULT_POLLFREQ5,
            "tapSensitivity": 2,
            "tapEnabled": true,
            "stayAwake": false,
            "measurementCycles": 1,
            "C1mode": 0,
            "remoteTrigger": null,
            "sendTrigger": null
        };


        agent.on("config", setConfig.bindenv(this));
    }


    // function that requests agent for configs
    // 
    // @params none
    // @returns none
    // 
    function init() {
        
        // Read the config from nv
        foreach (k,v in ::nv.config) {
            if (k in config) {
                config[k] <- v;
            }
        }
        
        // Write back to nv
        ::nv.config <- config;
        
        // Set button callback function
        if (config.C1mode == 4) {
            ::button <- Button(hardware.pinM, DIGITAL_IN_PULLDOWN, Button.NORMALLY_LOW, function() {
                cm.log("Button pressed");
                _buttonPressed = true;
                reading.button <- 1;    
            }.bindenv(this));
        }
        
    }
    

    // function that sets the configs
    //  
    // @param  newconfig - object containing the new configurations
    // @returns none
    // 
    function setConfig(newconfig) {
        if (typeof newconfig == "table") {

            local dbg = "Setting config: ";
            foreach (k, v in newconfig) {
                config[k] <- v;
                dbg += k + " = " + v + ", ";
            }
            if (DEBUG) cm.log(dbg);
            
            if (config.tapEnabled) {
                accel.configureClickInterrupt(true, LIS3DH.DOUBLE_CLICK, config.tapSensitivity, 15, 10, 300);
            } else {
                accel.configureClickInterrupt(false);
            }
            
            // Write back to nv
            ::nv.config <- config;
            
        }
    }
    

    // function that takes the sensor readings
    // 
    // @param     none
    // @returns   none
    // 
    function poll() {
        //if (_pollRunning) return;
        _pollRunning = true;
        

        // Get the accelerometer data
        accel.getAccel(function(val) {
            reading.acceleration_x = val.x;
            reading.acceleration_y = val.y;
            reading.acceleration_z = val.z;
            // if (DEBUG) server.log(format("Acceleration (G): (%0.2f, %0.2f, %0.2f)", val.x, val.y, val.z));

            // Get the temp and humid data
            tempHumid.read(function(result) {
                if ("error" in result) {
                    if (DEBUG) cm.log("tempHumid ERROR: ");
                    reading.temperature = 0;
                    reading.humidity = 0;
                } else {
                    // This temp sensor has 0.5 accuracy so it is used for 0-40 degrees.
                    if ((result.temperature == null)||(result.humidity == null)) {
                        cm.log("Getting Null Readings");
                        reading.temperature = 0;
                        reading.humidity = 0;

                    }  
                    reading.temperature = result.temperature;
                    reading.humidity = result.humidity;
                    if (DEBUG) cm.log(format("Current Humidity: %0.2f %s, Current Temperature: %0.2f °C", result.humidity, "%", result.temperature));
                }

                // Get the pressure data
                pressureSensor.read(function(result) {
                    if ("err" in result) {
                        if (DEBUG) cm.log("pressureSensor: " + result.err);
                    } else {
                        // Note the temp sensor in the LPS22HB is only accurate to +-1.5 degrees. 
                        // But it has an range of up to 65 degrees.
                        // Hence it is used if temp is greater than 40.
                        if (result.temperature > 40) reading.temperature = result.temperature;
                        reading.pressure = result.pressure;
                        if (DEBUG) cm.log(format("Current Pressure: %0.2f hPa, Current Temperature: %0.2f °C", result.pressure, result.temperature));
                    }

                    // Poll Sync 
                    syncPoll();

                }.bindenv(this));
            }.bindenv(this));
        }.bindenv(this));
        


    }

    // function that does the synchronous poll cycle
    // @param     none
    // @returns   none
    function syncPoll() {
        // Read the light level
        reading.light = hardware.lightlevel();
        if (DEBUG) server.log("Ambient Light: " + reading.light);

        // Read the signal strength
        reading.rssi = imp.getrssi();
        if (DEBUG) server.log("Signal strength: " + reading.rssi);

        // Read the battery voltage
        if (hardwareType == HardwareType.environmentSensor) {
            reading.battery = getBattVoltage();
        } else {
            reading.battery = 0;
        }

        // Toggle the LEDs on
        if (hardwareType == HardwareType.environmentSensor) {
            ledgreen.write(0);
            //ledblue.write(0);
        } else {
            hardware.pin1.configure(DIGITAL_OUT, 1);
            rgbLED.set(0, [0, 100, 100]).draw();
        }

        imp.wakeup(0.05, function() {
            // Toggle the LEDs off
            if (hardwareType == HardwareType.environmentSensor) {
                ledgreen.write(1);
                //ledblue.write(1);
            } else {
                hardware.pin1.configure(DIGITAL_OUT, 0);
            }
            modeBehaviour();
        }.bindenv(this));
    }


    // function that performs mode dependant behaviour
    // 
    // @param     none
    // @returns   none
    // 
    function modeBehaviour() {
        // Mode Dependent Functionality
        if (DEBUG) cm.log("Current Mode is:" + config.C1mode)

        switch(config.C1mode) {
            case 0: // Default
                checkConnection();
                break;
            case 1: // Current Sensor
                ::cs <- CurrentSensor(hardware.pinF);
                cs.readCurrent(function(result) {
                    reading.current <- result.current;
                    reading.currentgauge <- result.currentgauge;
                    checkConnection();
                }.bindenv(this));
                break;
            case 2: // LoRaWAN
                ::lora <- LoRa(hardware.uartFG, hardware.pinS);
                checkConnection();
                break;
            case 3: // VOC Sensor
                ::voc <- VOCSensor(i2cFG, hardware.pinS);
                imp.sleep(1);
                
                // Get the VOC/CO2 data
                try {
                    voc.readStatus(function(result) {
                        cm.log(result.co2);
                        reading.co2 <- result.co2;
                        reading.voc <- result.voc;
                        checkConnection();
                    }.bindenv(this));
                } catch (err) {
                    cm.log(err);
                }
                break;
            case 4: // Button  
                              
                if (_buttonPressed) {
                    agent.send("buttonPressed", true);                  
                    _buttonPressed = false;
                } else {
                    reading.button <- 0;
                }
                checkConnection();
                break;
            case 5: // Remote
                if (config.remoteTrigger != null) {
                    local rp = RemotePin(config.remoteTrigger.pin);
                    rp.configure(DIGITAL_OUT, config.remoteTrigger.state);
                    rp.write(config.remoteTrigger.state, config.remoteTrigger.duration, checkConnection.bindenv(this));
                }
                break;
        }
    }


    // function that checks connection status
    // 
    // @param     none
    // @returns   none
    // 
    function checkConnection() {
        if (cm.isConnected()) {
            postReadings();   
        } else {
            globalDebug.log("Connecting ...");
            cm.onNextConnect(postReadings.bindenv(this));
            cm.onTimeout(connectFailure.bindenv(this));
            cm.connect();
        }
    }
    

    // function that posts the readings and sends the device to sleep
    // 
    // @param     none
    // @returns   none
    // 
    function postReadings() {
        globalDebug.log("postingReadings");
        // RSSI doesn't get a value when offline, add it now if required
        if (reading.rssi == 0) reading.rssi = imp.getrssi();
        // Add the location after a blinkup or new squirrel
        if (hardware.wakereason() == WAKEREASON_BLINKUP || hardware.wakereason() == WAKEREASON_NEW_SQUIRREL) {
            reading._location <- imp.scanwifinetworks();
        }

        // Send the reading
        if (config.C1mode == 2) {
            lora.sendMessage(buildLoRaPacket());
        } else {
            //conctr.sendData(reading);
            agent.send("reading", reading);
        }

        sleep();      
    }

    // function that puts device in deep sleep
    // 
    // @param     none
    // @returns   none
    // 
    function sleep() {
        // Reset and save timeout counter
        ::nv.sleepTime = NO_WIFI_SLEEP_PERIOD;

        
        // Determine how long to wait before sleeping
        local sleepdelay = 20;
        if (hardware.wakereason() == WAKEREASON_TIMER) {
            sleepdelay = 0.5;
        } else if (hardware.wakereason() == WAKEREASON_PIN) {
            sleepdelay = 5;
            agent.send("config", true);
        }

        // Checks if stayAwake is enabled.
        if (config.stayAwake) {
            imp.setpowersave(true);
            //wakepin.configure(DIGITAL_IN, poll.bindenv(this));
            if (config.measurementCycles == null) {
                imp.wakeup(2, poll.bindenv(this));
            } else {
                imp.wakeup(config.measurementCycles, poll.bindenv(this));    
            }
        } else {
            // Wait the specified time
            server.flush(10);
            imp.wakeup(sleepdelay, function() {

                // Determine how long to sleep for
                local sleepTime = calcSleepTime(reading.battery, hardwareType);

                // Now actually sleep
                wakepin.configure(DIGITAL_IN_WAKEUP);
                server.sleepfor(sleepTime); 
                
            }.bindenv(this));
        }
    }
    
    // function that builds a packet to be sent via LoRaWAN
    // 
    // @param     none
    // @returns   messageBlob - 11 byte packet containing the sensor readings
    // 
    function buildLoRaPacket() {
        local messageBlob = blob(11);
        local tempBlob = blob(2);
        local presBlob = blob(4);
        local humidBlob = blob(4);
        
        tempBlob.writen((reading.temperature*100.0),'s');
        presBlob.writen((reading.pressure*100.0).tointeger(),'i');
        humidBlob.writen((reading.humidity).tointeger(),'i' );

        // Swap Endian-ness
        tempBlob.swap2();
        presBlob.swap4();
        
        // Write Temperature
        messageBlob.writeblob(tempBlob);

        // Write 3 bytes for pressure
        messageBlob.writen(presBlob[1], 'c');
        messageBlob.writen(presBlob[2], 'c');
        messageBlob.writen(presBlob[3], 'c');

        // Write 1 byte for humidity
        messageBlob.writen(humidBlob[0], 'c');
        
        // Write acceleration
        messageBlob.writen((reading.acceleration_x*10.0), 'c');
        messageBlob.writen((reading.acceleration_y*10.0), 'c');
        messageBlob.writen((reading.acceleration_z*10.0), 'c');

        // Write Battery Voltage
        messageBlob.writen(reading.battery*10.0, 'c');

        // Write Light Level Percentage
        messageBlob.writen((reading.light/65535.0*100.0).tointeger(), 'c');

        return messageBlob;
    }


    // function that reads the battery voltage
    // 
    // @param     none
    // @returns   battVoltage - the detected battery voltage
    // 
    function getBattVoltage() {
        local pollArray = [];
        for (local i = 0; i < 10; i++) {
                pollArray.append(batt.read() / 65535.0 * hardware.voltage());
        }
        
        return array_avg(pollArray);
    }

    // function handles connection failure
    // 
    // @param     none
    // @returns   none
    // 
    function connectFailure() {
        globalDebug.log("connectFailure");

        // Get saved sleepTime if it exists
        local sleepTime = ::nv.sleepTime;
    
    	if (::nv.sleepTime > 86400) { 
    	    ::nv.sleepTime = 86400;
    	} else {
            ::nv.sleepTime = ::nv.sleepTime * 2; 
        }
    	
        // Go to sleep for exponentially increasing duration if the device fails to connect            
        globalDebug.log("sleepTime: " + sleepTime);
        wakepin.configure(DIGITAL_IN_WAKEUP);
        imp.deepsleepfor(sleepTime); 
    }    
    

    // function that calculates sleep time
    // 
    // @param     battVoltage - the read battery voltage
    // @returns   sleepTime - duration for the imp to sleep
    // 
    function calcSleepTime(battVoltage, hardwareType = HardwareType.impExplorer) {
        local sleepTime;
        if (hardwareType == HardwareType.impExplorer) {
            // The impExplorer doesn't have a battery reading so always use pollFreq5
            sleepTime = config.pollFreq5;
            if (DEBUG) server.log("Battery not readable so assuming full");
        } else if (battVoltage < 0.8) {
            // Poll only once every two days
            sleepTime = config.pollFreq1;
            if (DEBUG) server.log("Battery voltage critical: " + battVoltage);
        } else if (battVoltage < 1.5) {
            // Poll only once every day
            sleepTime = config.pollFreq2;
            if (DEBUG) server.log("Battery voltage low: " + battVoltage);
        } else if (battVoltage < 2.0) {
            // Poll only once every 5 hours
            sleepTime = config.pollFreq3;
            if (DEBUG) server.log("Battery voltage medium: " + battVoltage);
        } else if (battVoltage < 2.5) {
            // Poll only once an hour
            sleepTime = config.pollFreq4;
            if (DEBUG) server.log("Battery voltage high: " + battVoltage);
        } else {
            // Poll every 15 min
            sleepTime = config.pollFreq5;
            if (DEBUG) server.log("Battery voltage full: " + battVoltage);
        }

        return sleepTime;
    }


    // function that returns an average of an array
    // 
    // @param     array - input array of numbers
    // @returns average - average of array
    // 
    function array_avg(array) {
        local sum = 0;
        local average = 0;
        for (local i = 0; i < array.len(); i++) {
            sum += array[i];
        }
        average = sum / (array.len());
        return average
    }

}
// MIT License

// Copyright (c) 2017 Mystic Pants Pty Ltd

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

class RemotePin {
    DEBUG = false;
    _pinLetter = null;
    _pin = null;
    constructor(pinLetter) {
        _pinLetter = pinLetter;
        _pin = hardware["pin"+ pinLetter];
    }
    
    // function that configures the pin
    // 
    // @param     pinType     - Pin type same as default imp configurations
    // @param     startState  - initial state of the pin.
    // @returns   none
    // 
    function configure(pinType, startState = 0) {
        if (pinType == DIGITAL_IN || pinType == DIGITAL_IN_PULLDOWN || pinType == DIGITAL_IN_PULLUP||pinType == ANALOG_IN) {
            _pin.configure(pinType);
        } else {
            _pin.configure(pinType, startState);
        }        
    }
    
    // function that sets the pin to a state
    // 
    // @param     state     - state to set pin to (0/1)
    // @param     holdtime  - how long to hold for
    // @param     cb        - callback to be called when complete
    // @returns   none
    // 
    function write(state, holdtime = null, cb = null) {
        if (DEBUG) cm.log("Setting pin" + _pinLetter + " to :" + state);
        _pin.write(state);       

        if (holdtime != null) {
            imp.wakeup(holdtime, function() {
                local inv_state = (!state).tointeger();
                cm.log(inv_state);
                _pin.write(inv_state); 
                if (cb) cb();
            }.bindenv(this));
        }
    }
    
}



class Logger {
    
    _uart = null;
    _debug = null;

    // Pass the UART object, eg. hardware.uart6E, Baud rate, and Offline Enable True/False
    // UART is enabled by default

    constructor(uart = null, baud = 9600, enable = true) {
        if (uart == null) {
            server.error("Logger requires a valid imp UART object");
            return null;
        }
        
        _uart = uart;
        _debug = enable;
    }

    function enable() {
        _uart.configure(baud, 8, PARITY_NONE, 1, NO_RX | NO_CTSRTS);
        _debug = true;
    }

    function disable() {
        _debug = false;
    }

    function log(message) {
        if (_debug) {
            _uart.write("[LOG] " + message + "\n");
            _uart.flush();
            if (server.isconnected()) server.log(message);
        }
    }
    
    function error(message) {
        if (_debug) {
            _uart.write("[ERR] " + message + "\n");
            _uart.flush();
            if (server.isconnected()) server.error(message);
        }
    }
}
// MIT License

// Copyright (c) 2017 Mystic Pants Pty Ltd

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


class VOCSensor{
    REG_READING = "";
    CMD_STATUS = "\x0C\x00\x00\x00\x00";
    _i2c = null;
    _addr = 0xE0;
    
    constructor(i2c, onewire_en) {
        _i2c = i2c;      
        _i2c.configure(CLOCK_SPEED_100_KHZ);  
        onewire_en.configure(DIGITAL_OUT, 1);
    }
    
    function readStatus(cb = null) {
        // Send Request
        local readingRequest = blob(6);
        readingRequest.writestring(CMD_STATUS);
        readingRequest.writen(_calcCRC(readingRequest), 'c');
        _send(readingRequest.tostring());
        cm.log("Request Sent");
        // Add slight delay
        imp.wakeup(0.1, function() {

            local result = _i2c.read(_addr, REG_READING, 7);
            if (result == null) {
                throw "I2C read error: " + _i2c.readerror();
            } else if (result == "") {
                // Empty string
            } else {
                local data = _parseFrame(result);
                if (data != null) {
                    local VOC = (data[0] - 13) * (1000.0 / 229); // ppb: 0 .. 1000
                    local CO2 = (data[1] - 13) * (1600.0 / 229) + 400; // ppm: 400 .. 2000

                    cm.log("VOC: " + VOC + " CO2: " + CO2);
                    
                    local result = {
                        "voc" : VOC,
                        "co2" : CO2,
                    };
                            
                    // Return table if no callback was passed
                    if (cb == null) { return result; }
            
                    // Invoke the callback if one was passed
                    imp.wakeup(0, function() { cb(result); });
                }
            }
        }.bindenv(this));
    }
    
    function _parseFrame(data) {
        local body = blob(6);
        body.writestring(data.tostring().slice(0,6))
        
        // Verify CRC
        if (_calcCRC(body) == data[6]) {
           return body; 
        } else {           
            return null;
        }
    }
    
    function _send(message) {
        _i2c.write(_addr, message);
    }
    
    function _calcCRC(inputBlob) {
        local crc = 0x00;
        local sum = 0x0000;
        
        // Loop over inputBlob
        for (local i = 0; i < inputBlob.len(); i++) {
            sum = crc + inputBlob[i];
            crc = 0x00FF & sum;
            crc += (sum / 0x100);
        }
        // complement
        crc = 0xFF - crc; 
        
        return crc; 
    }
    
}
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
// Copyright (c) 2017 Mystic Pants Pty Ltd
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

class LoRa {
    
    _uart = null;
    _receivedResponse = null;
    _queue = null;
    _currentCommand = null;
    
    
    static COMMANDS = {
        "AT+DTX" : regexp(@"OK$"),
    }
    
    constructor(uart, onewire_en, params = {}) {
        local baudRate = ("baudRate" in params) ? params.baudRate : 9600;
        local wordSize = ("wordSize" in params) ? params.wordSize : 8;
        local parity = ("parity" in params) ? params.parity : PARITY_NONE;
        local stopBits = ("stopBits" in params) ? params.stopBits : 1;
        local flags = ("flags" in params) ? params.flags : NO_CTSRTS;
        _receivedResponse = "";
        _queue = [];
        _uart = uart;
        _uart.configure(baudRate, wordSize, parity, stopBits, flags, _receiveData.bindenv(this));
        onewire_en.configure(DIGITAL_OUT, 1);
    }
    
    function sendMessage(message) {
        _enqueue(function(){
            if (typeof message == "blob") {
                message = _blobToHexString(message);   
                _sendCommand("AT+DTX", "=" + message.len() + "," +message); 
            } else {
                _sendCommand("AT+DTX", "=" + message.len() + "," + "\"" + message + "\"");
            }
        }.bindenv(this));
    }

    function _receiveData() {
        local data = _uart.readstring();
        _receivedResponse += data;
        server.log(data.tostring());
        
        // TODO: Read and interpret error messages
        /*
        local hasError = _receivedResponse.find("ERROR") != null;
        if (COMMANDS[_currentCommand].capture(_receivedResponse) || hasError) {
            server.log("receiving data : " + _receivedResponse);
            if (hasError) {
                throw "Error sending command : " + _currentCommand;
            } else {
                _processResponse(_receivedResponse);
            }
            _receivedResponse = "";
            _nextInQueue();
        }
        */
    }
    
    function _processResponse(response){
        
    }
    
    function _sendCommand(command, query = "") {
        _currentCommand = command;
        _uart.write(command);
        _uart.write(query);
        _uart.write("\n");
        server.log("sending command : " + command);
        server.log("query : " + query);
    }
    
    function _nextInQueue() {
        _queue.remove(0);
        if (_queue.len() > 0) {
            imp.wakeup(0, function(){
                _queue[0]();
            }.bindenv(this));
        }
    }
    
    function _enqueue(action) {
        _queue.push(action);
        if (_queue.len() == 1) {
            imp.wakeup(0, function(){
                action();
            }.bindenv(this));
        }
    }

    function _blobToHexString(blob) {
        local hexString = "";
        for (local i=0; i < blob.len(); i++) {
            hexString += format("%02X", blob[i]);
        }
        
        return hexString;
    }
    
}




//=============================================================================
// START OF PROGRAM

// Initialise nv ram
if (!("nv" in getroottable()) || !("sleepTime" in ::nv) || !("config" in ::nv)) {
    ::nv <- { "sleepTime" : NO_WIFI_SLEEP_PERIOD, "config": {} };
}

// Start the offline logger
onewire_en <- hardware.pinS;
onewire_en.configure(DIGITAL_OUT, 0); // DISABLED FOR NOW
uart <- hardware.uartFG;
globalDebug <- Logger(uart, 9600);
globalDebug.disable();
globalDebug.log(format("Started with wakereason %d and sleepTime %d", hardware.wakereason(), ::nv.sleepTime));


// Connection manager
cm <- ConnectionManager({ "blinkupBehavior": ConnectionManager.BLINK_ALWAYS, "retryOnTimeout": false});
imp.setsendbuffersize(8096);

// Checks hardware type
if ("pinW" in hardware) {
    hardwareType <- HardwareType.environmentSensor;
    // server.log("This is an Environmental Sensor")
} else {
    hardwareType <- HardwareType.impExplorer;
    // server.log("This is an impExplorer")
}

// Configures the pins depending on hardware type
if (hardwareType == HardwareType.environmentSensor) {
    batt <- hardware.pinH;
    batt.configure(ANALOG_IN);
    wakepin <- hardware.pinW;
    ledblue <- hardware.pinP;
    ledblue.configure(DIGITAL_OUT, 1);
    ledgreen <- hardware.pinU;
    ledgreen.configure(DIGITAL_OUT, 1);
    i2cpin <- hardware.i2cAB;
    i2cpin.configure(CLOCK_SPEED_400_KHZ);
} else {
    batt <- null;
    wakepin <- hardware.pin1;
    ledblue <- null;
    ledgreen <- null;
    i2cpin <- hardware.i2c89;
    i2cpin.configure(CLOCK_SPEED_400_KHZ);
    spi <- hardware.spi257;
    spi.configure(MSB_FIRST, 7500);
    rgbLED <- WS2812(spi, 1);
}

// Initialise accellerometer
accel <- LIS3DH(i2cpin, LIS3DH_ADDR);
accel.setDataRate(100);
accel.configureClickInterrupt(true, LIS3DH.DOUBLE_CLICK, 2, 15, 10, 300);
accel.configureInterruptLatching(true);

// Setup other sensors
pressureSensor <- LPS22HB(i2cpin, hardwareType == HardwareType.environmentSensor ? LPS22HB_ADDR_ES : LPS22HB_ADDR_IE);
pressureSensor.softReset();
tempHumid <- HTS221(i2cpin);
tempHumid.setMode(HTS221_MODE.ONE_SHOT, 7);

// Start the application
conctr <- Conctr({"sendLoc": false});
impExplorer <- ImpExplorer();

// Start polling after the imp is idle
imp.wakeup(0, function(){
    impExplorer.init();
    impExplorer.poll();
}.bindenv(this));





