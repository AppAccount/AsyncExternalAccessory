# AsyncExternalAccessory

Concurrency safe session management for one or more compatible external accessories. Depends on [AsyncStream](https://github.com/AppAccount/AsyncStream) and the `ExternalAccessory` framework. EASessions are opened on the main thread, ensuring that underlying streams are on the main run loop. 
