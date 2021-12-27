//  PlugUnplugTests.swift
//
//  Created by Yuval Koren on 11/3/21.
//  Copyright © 2021 Appcessori Corporation.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import XCTest
import ExternalAccessory
@testable import AsyncExternalAccessory

extension String: Error {}

func makeMock(serialNumber: String="001") throws -> AccessoryMock {
    let streamBufferSize = 4096
    var optionalInputStream: InputStream?
    var optionalOutputStream: OutputStream?
    Stream.getBoundStreams(withBufferSize: streamBufferSize, inputStream: &optionalInputStream, outputStream: &optionalOutputStream)
    guard let inputStream = optionalInputStream, let outputStream = optionalOutputStream else {
        throw "can't initialize bound streams"
    }
    return AccessoryMock(name: "EMAN", modelNumber: "LEDOM", serialNumber: serialNumber, manufacturer: "GFM", hardwareRevision: "1.0", protocolStrings: ["com.example.eap"], connectionID: Int.random(in: 0..<Int.max), inputStream: inputStream, outputStream: outputStream)
}

final class PlugUnplugTests: XCTestCase {
#if os(macOS)
    /// on macOS Monterey, `getBoundStreams` derived streams sometimes incur a 5s-15s startup delay
    static let testTimeout: UInt64 = 30_000_000_000
#else
    static let testTimeout: UInt64 = 3_000_000_000
#endif
    var manager: ExternalAccessoryManager!
    var accessory: AccessoryMock!
    var shouldOpenCompletion: ((AccessoryMock)->Bool)?
    var didOpenCompletion: ((AccessoryMock, DuplexAsyncStream?)->())?
    var timeoutTask: Task<(), Never>!
    
    override func setUp() async throws {
        continueAfterFailure = false
        accessory = try makeMock()
        self.manager = ExternalAccessoryManager()
        await manager.set(self)
        timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: Self.testTimeout)
            } catch {
                guard error is CancellationError else {
                    XCTFail("can't start timer")
                    return
                }
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
        await withTaskGroup(of: AccessoryMock.self) { taskGroup in
            taskGroup.addTask {
                await withCheckedContinuation { cont in
                    self.shouldOpenCompletion = { accessory in
                        cont.resume(returning: accessory)
                        return true
                    }
                }
            }
            taskGroup.addTask {
                await withCheckedContinuation { cont in
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
        await withTaskGroup(of: AccessoryMock.self) { taskGroup in
            taskGroup.addTask {
                await withCheckedContinuation { cont in
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
        let accessoryA = try makeMock()
        let accessoryB = try makeMock()
        let accessories = [accessoryA, accessoryB]
        let accessoryStreams = await withTaskGroup(of: [AsyncStream<AccessoryMock>].self) { taskGroup -> [AsyncStream<AccessoryMock>] in
            taskGroup.addTask {
                [AsyncStream<AccessoryMock> { cont in
                    self.shouldOpenCompletion = { accessory in
                        cont.yield(accessory)
                        return true
                    }
                }]
            }
            taskGroup.addTask {
                [AsyncStream<AccessoryMock> { cont in
                    self.didOpenCompletion = { accessory, _ in
                        cont.yield(accessory)
                    }
                }]
            }
            var accessoryStreams = [AsyncStream<AccessoryMock>]()
            for await streamArray in taskGroup {
                accessoryStreams.append(contentsOf: streamArray)
            }
            return accessoryStreams
        }
        await self.manager.connectToPresentAccessories(accessories)
        await withTaskGroup(of: Void.self) { taskGroup in
            for accessoryStream in accessoryStreams {
                taskGroup.addTask {
                    var foundAccessories = [AccessoryMock]()
                    for await accessory in accessoryStream {
                        foundAccessories.append(accessory)
                        if foundAccessories.count == accessories.count {
                            break
                        }
                    }
                    print("found \(foundAccessories.count) accessories")
                    XCTAssert(Set(foundAccessories) == Set(accessories))
                }
            }
            await taskGroup.waitForAll()
        }
    }
    
    func testColdPlugUnplug() async throws {
        var duplexStream: DuplexAsyncStream?
        self.shouldOpenCompletion = { accessory in
            return true
        }
        self.didOpenCompletion = { _, duplex in
            duplexStream = duplex
        }
        await self.manager.connectToPresentAccessories([self.accessory])
        await self.manager.listen()
        guard let duplex = duplexStream else {
            XCTFail()
            return
        }
        let readDataStream = await duplex.input.getReadDataStream()
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask {
                for try await _ in readDataStream {}
            }
            taskGroup.addTask {
                duplex.input.stream(self.accessory.inputStream, handle: Stream.Event.endEncountered)
            }
            try await taskGroup.waitForAll()
        }
    }
    
    func testHotPlug() async {
        await withTaskGroup(of: AccessoryMock.self) { taskGroup in
            taskGroup.addTask {
                await withCheckedContinuation { cont in
                    self.shouldOpenCompletion = { accessory in
                        cont.resume(returning: accessory)
                        return true
                    }
                }
            }
            taskGroup.addTask {
                await withCheckedContinuation { cont in
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
    
    func testHotPlugUnplug() async throws {
        let optionalDuplexStream = await withTaskGroup(of: Optional<DuplexAsyncStream>.self) { taskGroup -> Optional<DuplexAsyncStream> in
            taskGroup.addTask {
                await withCheckedContinuation { cont in
                    self.shouldOpenCompletion = { accessory in
                        cont.resume(returning: nil)
                        return true
                    }
                }
            }
            taskGroup.addTask {
                await withCheckedContinuation { cont in
                    self.didOpenCompletion = { accessory, duplex in
                        cont.resume(returning: duplex)
                    }
                }
            }
            taskGroup.addTask {
                await self.manager.listen()
                let notification = NSNotification(name: .EAAccessoryDidConnect, object: nil, userInfo: [EAAccessoryKey: self.accessory as Any])
                await self.manager.accessoryConnect(notification)
                return nil
            }
            var duplex: DuplexAsyncStream?
            for await stream in taskGroup.compactMap({ $0 }) {
                duplex = stream
            }
            return duplex
        }
        guard let duplex = optionalDuplexStream else {
            XCTFail()
            return
        }
        let readDataStream = await duplex.input.getReadDataStream()
        try await withThrowingTaskGroup(of: Void.self, body: { taskGroup in
            taskGroup.addTask {
                //let notification = NSNotification(name: .EAAccessoryDidConnect, object: nil, userInfo: [EAAccessoryKey: self.accessory as Any])
                //await self.manager.accessoryDisconnect(notification)
                duplex.input.stream(self.accessory.inputStream, handle: Stream.Event.endEncountered)
            }
            taskGroup.addTask {
                for try await _ in readDataStream {}
            }
            try await taskGroup.waitForAll()
        })
    }
    
    func testSameAccessory() async throws {
        let accessoryA = try makeMock()
        let accessoryB = try makeMock()
        XCTAssert(accessoryA.same(accessoryB))
        XCTAssert(accessoryB.same(accessoryA))
        let accessoryC = try makeMock(serialNumber: "101")
        XCTAssert(accessoryA.same(accessoryC) == false)
    }
}

extension PlugUnplugTests: AccessoryConnectionDelegate {
    func shouldOpenSession(for accessory: AccessoryProtocol) -> Bool {
        shouldOpenCompletion?(accessory as! AccessoryMock) ?? false
    }
    func sessionDidOpen(for accessory: AccessoryProtocol, session: DuplexAsyncStream?) {
        didOpenCompletion?(accessory as! AccessoryMock, session)
    }
}
