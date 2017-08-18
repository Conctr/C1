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
const POLL_TIME = 900;
const VOLTAGE_VARIATION = 0.1;
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

    _processesRunning = 0;
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
        }


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
            "sendTrigger": null,
        }


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
        if (config.C1mode ==4) {
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
        _processesRunning = 5;


        // Get the accelerometer data
        accel.getAccel(function(val) {
            reading.acceleration_x = val.x;
            reading.acceleration_y = val.y;
            reading.acceleration_z = val.z;
            // if (DEBUG) server.log(format("Acceleration (G): (%0.2f, %0.2f, %0.2f)", val.x, val.y, val.z));
            decrementProcesses();
        }.bindenv(this));

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

            decrementProcesses();
        }.bindenv(this));

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
            decrementProcesses();
        }.bindenv(this));
        
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

            decrementProcesses();
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
                decrementProcesses();
                break;
            case 1: // Current Sensor
                ::cs <- CurrentSensor(hardware.pinF);
                cs.readCurrent(function(result) {
                    reading.current <- result.current;
                    reading.currentgauge <- result.currentgauge;
                    decrementProcesses();
                }.bindenv(this));
                break;
            case 2: // LoRaWAN
                ::lora <- LoRa(hardware.uartFG, hardware.pinS);
                decrementProcesses();
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
                        decrementProcesses();
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
                decrementProcesses();
                break;
            case 5: // Remote
                if (config.remoteTrigger != null) {
                    local rp = RemotePin(config.remoteTrigger.pin);
                    rp.configure(DIGITAL_OUT, config.remoteTrigger.state);
                    rp.write(config.remoteTrigger.state, config.remoteTrigger.duration, decrementProcesses.bindenv(this));
                }
                break;
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
        local firstRead = batt.read() / 65535.0 * hardware.voltage();
        local battVoltage = batt.read() / 65535.0 * hardware.voltage();
        local pollArray = [];
        if (math.abs(firstRead - battVoltage) < VOLTAGE_VARIATION) {
            return battVoltage;
        } else {
            for (local i = 0; i < 10; i++) {
                pollArray.append(batt.read() / 65535.0 * hardware.voltage());
            }
            return array_avg(pollArray);
        }
    }


    // function posts readings if no more processes are running
    // 
    // @param     none
    // @returns   none
    // 
    function decrementProcesses() {
        if (--_processesRunning == 0) {
            if (cm.isConnected()) {
                postReadings();   
            } else {
                globalDebug.log("Connecting ...");
                cm.onNextConnect(postReadings.bindenv(this));
                cm.onTimeout(connectFailure.bindenv(this));
                cm.connect();
            }
        }

        // Execute mode dependent behaviour last
        if (--_processesRunning == 1) {
            modeBehaviour();
        }
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
        
        ::nv.sleepTime = ::nv.sleepTime * 2;
    	if (::nv.sleepTime > 86400) { 
    	    ::nv.sleepTime = 86400;
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
        local average = 0
        for (local i = 0; i < array.len(); i++) {
            sum += array[i];
        }
        average = sum / (array.len());
        return average
    }

}