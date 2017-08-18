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