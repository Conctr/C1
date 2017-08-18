# Conctr C1 Reference Code #

##Requirements##
To run this code on your C1, you will first need to **unbless** your device. To do so, contact us at [support@conctr.com].

Wrench
Just compile and upload to your electric imp account.
[https://github.com/nightrune/wrench]

##Introduction##
This example code reads the following sensors on the impExplorer:
* temperature
* pressure
* humidity
* acceleration (x, y and z)
* light level
* signal stength (rssi)

The values are send to Conctr. You will need to configure the Conctr application, including the API Key, Application ID and Model Id in the Agent code.

Note: The C1 code is configured to send data to a different model depending on the model created

##No wifi connection##
When a wifi connection cannot be established, it sleeps for an exponentially increasing amount of time before trying to connect again. 

##Remote Trigger##
https://agent.electricimp.com/<>/remotePin
