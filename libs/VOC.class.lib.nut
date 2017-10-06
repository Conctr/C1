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