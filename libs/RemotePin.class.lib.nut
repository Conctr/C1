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



