# AsyncExternalAccessory

Proxy the External Accessory framework's `EAAccessoryManager`, returning a full duplex [AsyncStream](https://github.com/AppAccount/AsyncStream) for each accessory. EASessions are opened on the main thread, ensuring that underlying streams are on the main run loop. 
