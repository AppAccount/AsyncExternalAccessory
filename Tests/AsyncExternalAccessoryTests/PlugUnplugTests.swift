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
        self.shouldOpenCompletion = { _ in
            XCTFail("unhandled shouldOpen callback")
            return false
        }
        self.didOpenCompletion = { _, _ in
            XCTFail("unhandled didOpen callback")
        }
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
        let accessoryShouldOpenStream = AsyncStream<AccessoryMock> { cont in
            self.shouldOpenCompletion = { accessory in
                cont.yield(accessory)
                return true
            }
        }
        let accessoryDidOpenStream = AsyncStream<AccessoryMock> { cont in
            self.didOpenCompletion = { accessory, _ in
                cont.yield(accessory)
            }
        }
        await self.manager.connectToPresentAccessories([self.accessory])
        for await accessory in accessoryShouldOpenStream {
            XCTAssert(accessory == self.accessory)
            break
        }
        for await accessory in accessoryDidOpenStream {
            XCTAssert(accessory == self.accessory)
            break
        }
    }
    
    func testColdPlugShouldntOpen() async {
        self.didOpenCompletion = { _, _ in
            XCTFail("shouldn't be called")
        }
        let accessoryShouldOpenStream = AsyncStream<AccessoryMock> { cont in
            self.shouldOpenCompletion = { accessory in
                cont.yield(accessory)
                return false
            }
        }
        await self.manager.connectToPresentAccessories([self.accessory])
        for await accessory in accessoryShouldOpenStream {
            XCTAssert(accessory == self.accessory)
            break
        }
    }
    
    func testMultiAccessoryColdPlug() async throws {
        let accessoryA = try makeMock()
        let accessoryB = try makeMock()
        let accessories = [accessoryA, accessoryB]
        let accessoryShouldOpenStream = AsyncStream<AccessoryMock> { cont in
            self.shouldOpenCompletion = { accessory in
                cont.yield(accessory)
                return true
            }
        }
        let accessoryDidOpenStream = AsyncStream<AccessoryMock> { cont in
            self.didOpenCompletion = { accessory, _ in
                cont.yield(accessory)
            }
        }
        await self.manager.connectToPresentAccessories(accessories)
        
        var shouldOpenAccessories = [AccessoryMock]()
        for await accessory in accessoryShouldOpenStream {
            shouldOpenAccessories.append(accessory)
            if shouldOpenAccessories.count == accessories.count {
                break
            }
        }
        XCTAssert(Set(shouldOpenAccessories) == Set(accessories))
        
        var didOpenAccessories = [AccessoryMock]()
        for await accessory in accessoryDidOpenStream {
            didOpenAccessories.append(accessory)
            if didOpenAccessories.count == accessories.count {
                break
            }
        }
        XCTAssert(Set(didOpenAccessories) == Set(accessories))
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
        let accessoryShouldOpenStream = AsyncStream<AccessoryMock> { cont in
            self.shouldOpenCompletion = { accessory in
                cont.yield(accessory)
                return true
            }
        }
        let accessoryDidOpenStream = AsyncStream<AccessoryMock> { cont in
            self.didOpenCompletion = { accessory, _ in
                cont.yield(accessory)
            }
        }
        await self.manager.listen()
        let notification = NSNotification(name: .EAAccessoryDidConnect, object: nil, userInfo: [EAAccessoryKey: self.accessory as Any])
        await self.manager.accessoryConnect(notification)
        for await accessory in accessoryShouldOpenStream {
            XCTAssert(accessory == self.accessory)
            break
        }
        for await accessory in accessoryDidOpenStream {
            XCTAssert(accessory == self.accessory)
            break
        }
    }
    
    func testHotPlugUnplug() async throws {
        let accessoryShouldOpenStream = AsyncStream<AccessoryMock> { cont in
            self.shouldOpenCompletion = { accessory in
                cont.yield(accessory)
                return true
            }
        }
        let accessoryDidOpenStream = AsyncThrowingStream<DuplexAsyncStream, Error> { cont in
            self.didOpenCompletion = { _, duplex in
                guard let duplex = duplex else {
                    cont.finish(throwing: "missing duplex stream")
                    return
                }
                cont.yield(duplex)
            }
        }
        await self.manager.listen()
        let notification = NSNotification(name: .EAAccessoryDidConnect, object: nil, userInfo: [EAAccessoryKey: self.accessory as Any])
        await self.manager.accessoryConnect(notification)
        for await accessory in accessoryShouldOpenStream {
            XCTAssert(accessory == self.accessory)
            break
        }
        let firstDuplex = try await accessoryDidOpenStream.first(where: { _ in true })
        guard let duplex = firstDuplex else {
            XCTFail()
            return
        }
        let readDataStream = await duplex.input.getReadDataStream()
        duplex.input.stream(self.accessory.inputStream, handle: Stream.Event.endEncountered)
        for try await _ in readDataStream {}
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
