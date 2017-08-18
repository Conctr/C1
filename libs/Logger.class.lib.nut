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