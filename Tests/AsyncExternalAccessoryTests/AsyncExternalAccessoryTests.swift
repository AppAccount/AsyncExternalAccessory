import XCTest
import ExternalAccessory
@testable import AsyncExternalAccessory

extension String: Error {}

final class AsyncExternalAccessoryTests: XCTestCase {
    var manager: ExternalAccessoryManager!
    var accessory: MockableAccessory!
    var shouldOpenCompletion: ((MockableAccessory)->Bool)?
    var didOpenCompletion: ((MockableAccessory, AsyncThrowingStream<Bool, Error>)->())?
    var timeoutTask: Task<(), Never>!
    
    func makeMock() -> AccessoryMock {
        AccessoryMock(name: "EMAN", modelNumber: "LEDOM", serialNumber: "001", manufacturer: "GFM", hardwareRevision: "1.0", protocolStrings: ["com.example.eap"], connectionID: Int.random(in: 0..<Int.max))
    }
    
    func makeAccessory(_ mock: AccessoryMock) throws -> MockableAccessory {
        let streamBufferSize = 4096
        var optionalInputStream: InputStream?
        var optionalOutputStream: OutputStream?
        Stream.getBoundStreams(withBufferSize: streamBufferSize, inputStream: &optionalInputStream, outputStream: &optionalOutputStream)
        guard let inputStream = optionalInputStream, let outputStream = optionalOutputStream else {
            throw "can't initialize bound streams"
        }
        return MockableAccessory(makeMock(), inputStream: inputStream, outputStream: outputStream)
    }
    
    override func setUp() async throws {
        continueAfterFailure = false
        accessory = try makeAccessory(makeMock())
        self.manager = ExternalAccessoryManager()
        await manager.set(self)
        timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }
            XCTFail("timed out")
        }
    }
    
    override func tearDown() {
        shouldOpenCompletion = nil
        didOpenCompletion = nil
        timeoutTask.cancel()
    }
    
    func testColdPlug() async {
        await withTaskGroup(of: MockableAccessory.self) { taskGroup in
            taskGroup.addTask {
                await withUnsafeContinuation { cont in
                    self.shouldOpenCompletion = { accessory in
                        cont.resume(returning: accessory)
                        return true
                    }
                }
            }
            taskGroup.addTask {
                await withUnsafeContinuation { cont in
                    self.didOpenCompletion = { accessory, _ in
                        cont.resume(returning: accessory)
                    }
                }
            }
            taskGroup.addTask {
                await self.manager.connectToPresentAccessories([self.accessory])
                return self.accessory
            }
            if await taskGroup.allSatisfy({ $0 == self.accessory }) != true {
                XCTFail()
            }
        }
    }
    
    func testColdPlugShouldntOpen() async {
        self.didOpenCompletion = { _, _ in
            XCTFail("shouldn't be called")
        }
        await withTaskGroup(of: MockableAccessory.self) { taskGroup in
            taskGroup.addTask {
                await withUnsafeContinuation { cont in
                    self.shouldOpenCompletion = { accessory in
                        cont.resume(returning: accessory)
                        return false
                    }
                }
            }
            taskGroup.addTask {
                await self.manager.connectToPresentAccessories([self.accessory])
                return self.accessory
            }
            if await taskGroup.allSatisfy({ $0 == self.accessory }) != true {
                XCTFail()
            }
        }
    }
    
    func testHotPlug() async {
        await withTaskGroup(of: MockableAccessory.self) { taskGroup in
            taskGroup.addTask {
                await withUnsafeContinuation { cont in
                    self.shouldOpenCompletion = { accessory in
                        cont.resume(returning: accessory)
                        return true
                    }
                }
            }
            taskGroup.addTask {
                await withUnsafeContinuation { cont in
                    self.didOpenCompletion = { accessory, _ in
                        cont.resume(returning: accessory)
                    }
                }
            }
            taskGroup.addTask {
                await self.manager.listen()
                let notification = NSNotification(name: .EAAccessoryDidConnect, object: nil, userInfo: [EAAccessoryKey: self.accessory as Any])
                await self.manager.accessoryConnect(notification)
                return self.accessory
            }
            if await taskGroup.allSatisfy({ $0 == self.accessory }) != true {
                XCTFail()
            }
        }
    }
}

extension AsyncExternalAccessoryTests: AccessoryConnectionDelegate {
    func shouldOpenSession(for accessory: MockableAccessory) -> Bool {
        shouldOpenCompletion?(accessory) ?? false
    }
    func sessionDidOpen(for accessory: MockableAccessory, writeReady: AsyncThrowingStream<Bool, Error>) {
        didOpenCompletion?(accessory, writeReady)
    }
}
