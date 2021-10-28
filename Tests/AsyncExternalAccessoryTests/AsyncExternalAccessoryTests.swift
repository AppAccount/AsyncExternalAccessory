import XCTest
import ExternalAccessory
@testable import AsyncExternalAccessory

final class AsyncExternalAccessoryTests: XCTestCase {
    static var streamBufferSize = 4096
    var inputStream: InputStream!
    var outputStream: OutputStream!
    var runLoopTask: Task<(), Error>?
    var expectation: XCTestExpectation?
    let mock = AccessoryMock(name: "EMAN", modelNumber: "LEDOM", serialNumber: "001", manufacturer: "GFM", hardwareRevision: "1.0", protocolStrings: ["com.example.eap"], connectionID: Int.random(in: 0..<Int.max))
    
    override func setUp() {
        var optionalInputStream: InputStream?
        var optionalOutputStream: OutputStream?
        Stream.getBoundStreams(withBufferSize: Self.streamBufferSize, inputStream: &optionalInputStream, outputStream: &optionalOutputStream)
        self.inputStream = optionalInputStream!
        self.outputStream = optionalOutputStream!
        runLoopTask = Task {
            while true {
                try Task.checkCancellation()
                RunLoop.current.run(until: Date())
                await Task.yield()
            }
        }
    }
    
    override func tearDown() {
        runLoopTask?.cancel()
    }
    
    func testActorColdPlug() async {
        expectation = self.expectation(description: "open session")
        let manager = ExternalAccessoryManager()
        await manager.set(self)
        let accessory = MockableAccessory(mock, inputStream: self.inputStream, outputStream: self.outputStream)
        await manager.connectToPresentAccessories([accessory])
        await waitForExpectations(timeout: 2.0) { error in
            if let error = error {
                print(error)
            }
        }
    }
    
    func testActorHotPlug() async {
        expectation = self.expectation(description: "open session")
        let manager = ExternalAccessoryManager()
        await manager.set(self)
        await manager.listen()
        let accessory = MockableAccessory(mock, inputStream: self.inputStream, outputStream: self.outputStream)
        let notification = NSNotification(name: .EAAccessoryDidConnect, object: nil, userInfo: [EAAccessoryKey: accessory])
        await manager.accessoryConnect(notification)
        await waitForExpectations(timeout: 2.0) { error in
            if let error = error {
                print(error)
            }
        }
    }
}

extension AsyncExternalAccessoryTests: AccessoryConnectionDelegate {
    func shouldOpenSession(for accessory: MockableAccessory) -> Bool {
        print(#function)
        expectation?.fulfill()
        return true
    }
    func sessionDidOpen(for accessory: MockableAccessory, writeReady: AsyncThrowingStream<Bool, Error>) {
        print(#function)
        Task {
            do {
                for try await ready in writeReady {
                    print("ready \(ready)")
                }
            } catch {
                
            }
            print("writeReady stream finished")
        }
        return
    }
}
