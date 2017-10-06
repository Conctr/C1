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

@include "./libs/ImpExplorer.class.lib.nut"
@include "./libs/RemotePin.class.lib.nut"
@include "./libs/Logger.class.lib.nut"
@include "./libs/VOC.class.lib.nut"
@include "./libs/CurrentSensor.class.lib.nut"
@include "./libs/LoRa.class.lib.nut"




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





