import XCTest
import ExternalAccessory
@testable import AsyncExternalAccessory

extension String: Error {}

final class AsyncExternalAccessoryTests: XCTestCase {
    var manager: ExternalAccessoryManager!
    var mock: AccessoryMock!
    var accessory: MockableAccessory!
    var shouldOpenCompletion: ((MockableAccessory)->Bool)?
    var didOpenCompletion: ((MockableAccessory, AsyncThrowingStream<Bool, Error>)->())?
    var timeoutTask: Task<(), Never>!
    
    func makeMock() throws -> AccessoryMock {
        let streamBufferSize = 4096
        var optionalInputStream: InputStream?
        var optionalOutputStream: OutputStream?
        Stream.getBoundStreams(withBufferSize: streamBufferSize, inputStream: &optionalInputStream, outputStream: &optionalOutputStream)
        guard let inputStream = optionalInputStream, let outputStream = optionalOutputStream else {
            throw "can't initialize bound streams"
        }
        return AccessoryMock(name: "EMAN", modelNumber: "LEDOM", serialNumber: "001", manufacturer: "GFM", hardwareRevision: "1.0", protocolStrings: ["com.example.eap"], connectionID: Int.random(in: 0..<Int.max), inputStream: inputStream, outputStream: outputStream)
    }
    
    func makeAccessory(_ mock: AccessoryMock) throws -> MockableAccessory {
        return MockableAccessory(mock)
    }
    
    override func setUp() async throws {
        continueAfterFailure = false
        mock = try makeMock()
        accessory = try makeAccessory(mock)
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
    
    func testMultiAccessoryColdPlug() async throws {
        let accessoryA = try makeAccessory(makeMock())
        let accessoryB = try makeAccessory(makeMock())
        let accessories = [accessoryA, accessoryB]
        await withTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask {
                var shouldOpenAccessories = [MockableAccessory]()
                let shouldOpenStream = AsyncStream<Void> { cont in
                    self.shouldOpenCompletion = { accessory in
                        shouldOpenAccessories.append(accessory)
                        if shouldOpenAccessories.count == accessories.count {
                            cont.finish()
                        }
                        return true
                    }
                }
                for await _ in shouldOpenStream {}
                XCTAssert(Set(shouldOpenAccessories) == Set(accessories))
            }
            taskGroup.addTask {
                var didOpenAccessories = [MockableAccessory]()
                let didOpenStream = AsyncStream<Void> { cont in
                    self.didOpenCompletion = { accessory, _ in
                        didOpenAccessories.append(accessory)
                        if didOpenAccessories.count == accessories.count {
                            cont.finish()
                        }
                    }
                }
                for await _ in didOpenStream {}
                XCTAssert(Set(didOpenAccessories) == Set(accessories))
            }
            taskGroup.addTask {
                await self.manager.connectToPresentAccessories(accessories)
            }
            await taskGroup.waitForAll()
        }
    }
    
    func testColdPlugUnplug() async {
        var writeReadyStream: AsyncThrowingStream<Bool, Error>?
        self.shouldOpenCompletion = { accessory in
            return true
        }
        self.didOpenCompletion = { _, writeReady in
            writeReadyStream = writeReady
        }
        await self.manager.connectToPresentAccessories([self.accessory])
        await self.manager.listen()
        do {
            let notification = NSNotification(name: .EAAccessoryDidConnect, object: nil, userInfo: [EAAccessoryKey: self.mock as Any])
            await self.manager.accessoryDisconnect(notification)
            for try await ready in writeReadyStream! {
                XCTAssert(ready == true)
            }
        } catch {
            XCTFail()
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
                let notification = NSNotification(name: .EAAccessoryDidConnect, object: nil, userInfo: [EAAccessoryKey: self.mock as Any])
                await self.manager.accessoryConnect(notification)
                return self.accessory
            }
            if await taskGroup.allSatisfy({ $0 == self.accessory }) != true {
                XCTFail()
            }
        }
    }
    
    func testHotPlugUnplug() async {
        await self.manager.listen()
        await withTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask {
                await withUnsafeContinuation { cont in
                    self.shouldOpenCompletion = { accessory in
                        cont.resume()
                        return true
                    }
                }
            }
            taskGroup.addTask {
                let notification = NSNotification(name: .EAAccessoryDidConnect, object: nil, userInfo: [EAAccessoryKey: self.mock as Any])
                await self.manager.accessoryConnect(notification)
            }
            taskGroup.addTask {
                let writeReadyStream = await withUnsafeContinuation { cont in
                    self.didOpenCompletion = { _, writeReady in
                        cont.resume(returning: writeReady)
                    }
                }
                do {
                    let notification = NSNotification(name: .EAAccessoryDidConnect, object: nil, userInfo: [EAAccessoryKey: self.mock as Any])
                    await self.manager.accessoryDisconnect(notification)
                    for try await _ in writeReadyStream {}
                } catch {
                    XCTFail()
                }
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
