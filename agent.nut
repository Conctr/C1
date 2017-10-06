// Copyright (c) 2017 Mystic Pants Pty Ltd
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

#require "Rocky.class.nut:1.3.0"
#require "IFTTT.class.nut:1.0.0"
#require "JSONEncoder.class.nut:1.0.0"
#require "PrettyPrinter.class.nut:1.0.1"

@include "./libs/conctr.agent.lib.nut"

const APP_ID = "<PLACE YOUR APP_ID HERE>";
const API_KEY = "<PLACE YOUR API_KEY HERE>";

const DEFAULT_POLLFREQ1 = 172800;
const DEFAULT_POLLFREQ2 = 86400
const DEFAULT_POLLFREQ3 = 18000;
const DEFAULT_POLLFREQ4 = 3600;
const DEFAULT_POLLFREQ5 = 900;
const MAX_ALERT_ITEMS = 10;

class ImpExplorer {
    _conctr = null;
    _rocky = null;
    _savedData = null;
    _configChanged = true;
    model = null;

    constructor(conctr, rocky) {

        _conctr = conctr;
        _rocky = rocky;

        local initialData = server.load();
        if (!("config" in initialData)) {

            // Set the default values and save them to persistant storage
            _savedData = {
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
                },

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
                },
                alerts = null, 
                alertFlag = false
            }
            server.save(_savedData);

        } else {

            _savedData = initialData;
            _savedData.config.remoteTrigger <- null;
            server.save(_savedData);

        }

        
        _rocky.get("/", function(context) {
            context.send(200, format(HTML_ROOT, http.agenturl()));
        }.bindenv(this));

        
        _rocky.get("/config", function(context) {
            context.send(200, _savedData);
        }.bindenv(this));

        
        _rocky.post("/config", function(context) {       
            setConfig(context.req.body)
            sendConfig();
            context.send(200, "OK");
        }.bindenv(this));

        // Setup an API endpoint for alerts
        _rocky.post("/alerts", function(context) {   
            if (validateAlerts(context.req.body)) {
                setAlerts(context.req.body);
                context.send(200, "OK");
            } else {
                context.send(400, "Invalid Parameters")
            }
        }.bindenv(this));

        
        device.on("config", sendConfig.bindenv(this)); 
        
        
        server.log(_savedData.config.C1mode)
        switch(_savedData.config.C1mode) {
            case 0: 
                model = "environment_sensor:v3";
                break;
            case 1: 
                model = "currentsensor:v1";
                break;
            case 2: 
                model = "currentsensor:v1";
                break;
            case 3: 
                server.log("VOC MODE ACTIVE");
                model = "vocsensor:v1";
                break;
            case 4: 
                device.on("buttonPressed", sendHTTP.bindenv(this)); 
                model = "c1button:v1";                
                break;
            case 5: 
                model = "environment_sensor:v3";
                _rocky.post("/remotePin", function(context) {       
                    server.log("RECEIVED");
                    pp.print(http.jsondecode(context.req.rawbody));
                    setRemotePin(http.jsondecode(context.req.rawbody));
                    context.send(200, "OK");
                }.bindenv(this));
                break;
                
        }
    }

    function init() {
        device.on("reading", function(reading) {
            // Check Alerts
            if (_savedData.alerts != null) checkAlerts(reading);

            conctr.sendData(reading, function (err, result) {
                if (err) {
                    pp.print(err)
                   pp.print(result);
                }
            });
        }.bindenv(this))
    }

    // Validates Alerts
    // 
    // @param     alertConfig - Table containing the config for alerts
    // @returns   validation status- True if successful, false if it failed
    // 
    function validateAlerts(alertConfig) {
        if (typeof alertConfig == "table") {
            local itemCount = 0;
            foreach (k, v in alertConfig) {
                itemCount++;

                // Check that it's a sensor field or table of numbers
                if (!(k in _savedData.reading) && (k != "alertSettings")) {
                    server.log(k);
                    server.log("Key not in readings or alertSettings");
                    return false;
                }

                if (k != "alertSettings") {
                    // Value alway needs to be a table
                    if (typeof v != "table") {
                        server.log("Value not table");
                        return false
                    }

                    foreach (key, value in v) {
                        key.toupper();
                        if (key != "LT" && key != "EQ" && key != "NEQ" && key != "GT") {
                            server.log("Comparison Value Wrong");
                            return false;
                        }
                        if (typeof value != "integer" && typeof value != "float" ) return false;
                    }
                } else {
                    server.log("alertSettings set");
                }
                
            }
            if (itemCount < MAX_ALERT_ITEMS) {
                server.log("Valid Alert Config");
                return true;
            } else {
                return false;
            }

        } else {
            server.log("Config not table");
            return false;
        } 
    }

    // function that checks if any values fall outside of range and an alert is needed
    // 
    // @param     none
    // @returns   none
    function checkAlerts(reading) {
        local alertValues = {};
        local localAlertFlag = false;

        // Iterate over each reading field
        foreach (k,v in _savedData.alerts) {
            if ("LT" in v) {
                if (reading[k] < v.LT) {
                    localAlertFlag = true;
                    alertValues[k] <- reading[k]; 
                }
            }
            if ("GT" in v) {
                if (reading[k] > v.GT) { 
                    localAlertFlag = true;
                    alertValues[k] <- reading[k]; 
                }
            }
            if ("EQ" in v) {
                if (reading[k] = v.GT) { 
                    localAlertFlag = true;
                    alertValues[k] <- reading[k]; 
                }
            }
            if ("NEQ" in v) {
                if (reading[k] != v.GT) { 
                    localAlertFlag = true;
                    alertValues[k] <- reading[k]; 
                }
                
            }
        }

        // if one alarm went off, raise global flag
        if (localAlertFlag) {
            if (!_savedData.alertFlag) {
                // Do Notification Once
                local alertSettings = _savedData.alerts.alertSettings;
                sendSMS(alertSettings.to, alertSettings.from, alertSettings.message)
                server.log("Sending SMS");
                //pp.print(alertValues);
                //pp.print(alertSettings)
            }
            _savedData.alertFlag = true;
        } else {
            // Reset alarm flag.
            _savedData.alertFlag = false;
        }
        server.save(_savedData);
    }

    // Sets Alerts Configuration
    // 
    // @param     alertConfig - table containing parameters for the alert
    //            e.g       {"temperature": {"LT": 40.2, "GT": 10.1}}
    // @returns   none
    // 
    function setAlerts(alertConfig) {
        _savedData.alerts <- alertConfig;
        _savedData.alertFlag <- false;
        server.save(_savedData);
    }
    
    // Sends a HTTP post to a remote triggerable C1
    // 
    // @param     err - any error
    // @returns   none
    // 
    function sendHTTP(err) {
        
        local config = _savedData.config;
        local url =  "https://agent.electricimp.com/" + config.sendTrigger.apiURL + "/remotePin";
        local headers = {"ContentType": "application/json"};
        local body = ({"pin": config.sendTrigger.pinLetter, "duration": config.sendTrigger.pinDuration, "state": config.sendTrigger.pinState});
        local request = http.post(url, headers, http.jsonencode(body));
        local response = request.sendsync();
        server.log(response.statuscode);
    }
     
    // Sets remote pin to trigger
    // 
    // @param     remoteTriggerConfig - a table with the pin triggering values
    // @returns   none
    // 
    // TODO: Split into validate and set
    function setRemotePin(remoteTriggerConfig) {
        _savedData.config.remoteTrigger <- {};
        if (typeof remoteTriggerConfig == "table") {
            if (remoteTriggerConfig.pin == null || remoteTriggerConfig.state == null) return false;
            local expression = regexp(@"^[A-X]$");            
            if (!(expression.match(remoteTriggerConfig.pin.toupper()))) {
                server.log("Not Matching [A-X]");
                return false;
            }
            _savedData.config.remoteTrigger.pin <- remoteTriggerConfig.pin;
            _savedData.config.remoteTrigger.duration <- remoteTriggerConfig.duration;
            _savedData.config.remoteTrigger.state <- remoteTriggerConfig.state;
            _configChanged = true;
            return server.save(_savedData);
        } else {
            return false;
        }    
        
    }

    // Updates the in-memory and persistant data table
    // 
    // @param     newconfig - a table with the new configuration values
    // @returns   none
    // 
    function setConfig(newconfig) {
        //pp.print(newconfig);
        if (typeof newconfig == "table") {
            foreach (k, v in newconfig) {
                if (typeof v == "string") {
                    if (v.tolower() == "true") {
                        v = true;
                    } else if (v.tolower() == "false") {
                        v = false;
                    } else {
                        v = v.tointeger();
                    }
                }
                _savedData.config[k] <- v;
            }
            _configChanged = true;
            return server.save(_savedData);
        } else {
            return false;
        }
    }


    // function that sends the config to device
    // 
    // @param     none
    // @returns   none
    // 
    function sendConfig(d = null) {
        // Send back the config to the device
        //if (_configChanged == true) {
            device.send("config", _savedData.config); 
            // Clear Remote Trigger
            _savedData.config.remoteTrigger <- null;   
            server.save(_savedData);    
            _configChanged = false;
        //}
    }


}


HTML_ROOT <- @"
<!DOCTYPE html>
<html>
<head>
    <title>C1 for Conctr</title>
    <link rel='stylesheet' href='https://netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap.min.css'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <style>
    .center {
        margin-left: auto;
        margin-right: auto;
        margin-bottom: auto;
        margin-top: auto;
    }
    </style>
</head>

<body>
    <div class='container'>
        <h2 class='text-center'>C1 Settings</h2>
        <br>
        <div class='controls'>
            <div class='update-button'>
                <form id='config-form'>
                    <div>
                        <label>Tap Sensitivity(Gs):</label>&nbsp;
                        <input id='tapSensitivity'></input>
                        <input type='checkbox' id='tapEnabled' name='tapEnabled' value='tapEnabled'>Tap Enabled</input>
                    </div>
                    <div>
                        <label>Poll frequency when battery critical:</label>&nbsp;
                        every <input id='pollFreq1'></input> seconds
                    </div>
                    <div>
                        <label>Poll frequency when battery low:</label>&nbsp;
                        every <input id='pollFreq2'></input> seconds
                    </div>
                    <div>
                        <label>Poll frequency when battery medium:</label>&nbsp;
                        every <input id='pollFreq3'></input> seconds
                    </div>
                    <div>
                        <label>Poll frequency when battery high:</label>&nbsp;
                        every <input id='pollFreq4'></input> seconds
                    </div>
                    <div>
                        <label>Poll frequency when battery full:</label>&nbsp;
                        every <input id='pollFreq5'></input> seconds
                    </div>
                    <div>
                        <input type='checkbox' id='stayAwake' value='stayAwakeEnabled'>Stay Awake</input>
                        <label>Measurement frequency for always awake:</label>&nbsp;
                        <input id='measurementCycles'></input>
                    </div>
                    <div>
                    <label>C1 Mode</label>
                        <select name = 'C1mode' id = 'C1mode'>
                            <option value = 0 selected >Standalone C1</option>
                            <option value = 1>Current Sensor</option>
                            <option value = 2>LoRaWAN Module</option>
                            <option value = 3>VOC Sensor</option>
                            <option value = 4>Button</option>
                            <option value = 5>Remote</option>
                        </select>
                    </div>
                    <div id = 'optional-fields'>
                        <label>API URL:</label>
                        <input id = 'apiURL' type = 'text'/>
                        <label>Pin Letter(A-X):</label>
                        <input id = 'pinLetter' type = 'text'/>
                        <label>Pin State:</label>
                        <input id = 'pinState' type = 'text'/>
                        <label>Duration:</label>
                        <input id = 'pinDuration' type = 'text'/>
                    </div>
                    <div>
                        <button type='submit' id='update-button'>Update Config</button>
                        <label id='submitResult' style='color:blue'></label>
                    </div>
                </form>
            </div>
        </div>
        <!-- controls -->
        <br>
        <small>From: <span id='agenturl'>Unknown</span></small>
    </div>
    <!-- container -->
    
    
    <script src='https://cdnjs.cloudflare.com/ajax/libs/jquery/3.2.1/jquery.min.js'></script>
    <script>
        
        $(function(){
            $('#optional-fields').hide();             
            var agenturl = '%s';

            function getConfigInput(e) {
                var config = {
                    'tapSensitivity': parseInt($('#tapSensitivity').val()),
                    'tapEnabled': $('#tapEnabled').is(':checked'),
                    'pollFreq1': parseInt($('#pollFreq1').val()),
                    'pollFreq2': parseInt($('#pollFreq2').val()),
                    'pollFreq3': parseInt($('#pollFreq3').val()),
                    'pollFreq4': parseInt($('#pollFreq4').val()),
                    'pollFreq5': parseInt($('#pollFreq5').val()),
                    'C1mode':  parseInt($('#C1mode').val()),
                    'measurementCycles':  parseInt($('#measurementCycles').val()),
                    'stayAwake':  $('#stayAwake').is(':checked'),
                    'sendTrigger': {'apiURL':  $('#apiURL').val(), 'pinLetter': $('#pinLetter').val(), 'pinState':parseInt($('#pinState').val()), 'pinDuration': parseInt($('#pinDuration').val())}
                };
                
                setConfig(config);
                $('#name-form').trigger('reset');
                return false;
            }

            $('#C1mode').change(function(){
                const value = $(this).val();
                if (value === '4') {
                    $('#optional-fields').show();
                } else {
                    $('#optional-fields').hide();
                }
            });

            function updateReadout(data) {
                $('#tapSensitivity').val(data.tapSensitivity);
                $('#tapEnabled').prop('checked', data.tapEnabled);
                $('#pollFreq1').val(data.pollFreq1);
                $('#pollFreq2').val(data.pollFreq2);
                $('#pollFreq3').val(data.pollFreq3);
                $('#pollFreq4').val(data.pollFreq4);
                $('#pollFreq5').val(data.pollFreq5);
                $('#measurementCycles').val(data.measurementCycles);
                $('#stayAwake').prop('checked', data.stayAwake);
                $('#C1mode').val(data.C1mode);
                $('#apiURL').val(data.apiURL);
                $('#pinState').val(data.pinState);                
                $('#pinDuration').val(data.pinDuration);
                if (data.C1mode == '4') {
                    $('#optional-fields').show();
                }   
                $('#name-form').trigger('reset');         
                setTimeout(function() {
                    getConfig(updateReadout);
                }, 120000);
            }


            function getConfig(callback) {
                $.ajax({
                    url: agenturl + '/config',
                    type: 'GET',
                    success: function(response) {
                        if (callback && ('config' in response)) {
                            console.log('Successfully loaded from agent');
                            callback(response.config);
                            $('#submitResult').text('Loaded');
                            setTimeout(function() {
                                $('#submitResult').text('');
                            }, 2000);
                        }
                    }
                });
            }


            function setConfig(config) {
                $.ajax({
                    url: agenturl + '/config',
                    contentType: 'application/json; charset=utf-8',
                    dataType: 'text',
                    type: 'POST',
                    data: JSON.stringify(config),
                    
                    error: function(jqXHR, textStatus, errorThrown) {
                        console.log('Failed to sent to agent: ' + errorThrown);
                        $('#submitResult').text(textStatus);
                        setTimeout(function() {
                            $('#submitResult').text('');
                        }, 4000);
                    },
                    
                    success: function(response) {
                        console.log('Successfully sent to agent');
                        $('#submitResult').text('Updated');
                        setTimeout(function() {
                            $('#submitResult').text('');
                        }, 2000);
                    }
                });
            }
            
            // Initialise the display
            $(function() {
                $('#agenturl').text(agenturl);
                getConfig(updateReadout);
                $('.update-button button').on('click', getConfigInput);
            })


        });





    </script>
</body>
</html>
"


//=============================================================================
// START OF PROGRAM




// Start the application
pp <- PrettyPrinter();
rocky <- Rocky();
model <- 0;
impExplorer <- ImpExplorer(null, rocky);
conctr <- Conctr(APP_ID, API_KEY, impExplorer.model);
impExplorer.init();





