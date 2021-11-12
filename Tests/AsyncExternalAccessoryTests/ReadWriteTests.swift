//  ReadWriteTests.swift
//
//  Created by Yuval Koren on 11/9/21.
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

final class ReadWriteTests: XCTestCase {
    static let testTimeout: UInt64 = 2_000_000_000
    var manager: ExternalAccessoryManager!
    var mock: AccessoryMock!
    var accessory: MockableAccessory!
    var shouldOpenCompletion: ((MockableAccessory)->Bool)?
    var didOpenCompletion: ((MockableAccessory, AsyncThrowingStream<Bool, Error>?, AsyncThrowingStream<Data, Error>?)->())?
    var writeReadyStream: AsyncThrowingStream<Bool, Error>?
    var readDataStream: AsyncThrowingStream<Data, Error>?
    var timeoutTask: Task<(), Never>!
    
    override func setUp() async throws {
        continueAfterFailure = false
        mock = try makeMock()
        accessory = try makeAccessory(mock)
        self.manager = ExternalAccessoryManager()
        await manager.set(self)
        timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: Self.testTimeout)
            } catch {
                return
            }
            XCTFail("timed out")
        }
        self.shouldOpenCompletion = { accessory in
            return true
        }
        self.didOpenCompletion = { _, writeReady, readData in
            self.writeReadyStream = writeReady
            self.readDataStream = readData
        }
    }
    
    override func tearDown() {
        shouldOpenCompletion = nil
        didOpenCompletion = nil
        timeoutTask.cancel()
    }
    
    func testShortWrite() async throws {
        let size = 16
        await self.manager.connectToPresentAccessories([self.accessory])
        try await withThrowingTaskGroup(of: Bool.self) { taskGroup in
            taskGroup.addTask {
                for try await data in self.readDataStream! {
                    let bytesRead = data.count
                    return(bytesRead == size)
                }
                return false
            }
            taskGroup.addTask {
                for try await ready in self.writeReadyStream! {
                    XCTAssert(ready == true)
                    let bytesWritten = try await self.manager.write(Data.init(count: size), to: self.accessory)
                    return(bytesWritten == size)
                }
                return false
            }
            if try await taskGroup.allSatisfy({ $0 }) != true {
                XCTFail()
            }
        }
    }
    
    func testWriteToInvalidAccessory() async throws {
        let size = 16
        let invalidAccessory = try makeAccessory(makeMock())
        await self.manager.connectToPresentAccessories([self.accessory])
        do {
            for try await ready in writeReadyStream! {
                XCTAssert(ready == true)
                let _ = try await manager.write(Data.init(count: size), to: invalidAccessory)
                XCTFail("Expecting exception")
            }
        } catch (let error) {
            guard let e = error as? ExternalAccessoryManagerError, e == .UnknownAccessory else {
                XCTFail("Unexpected exception \(error)")
                return
            }
        }
    }
}

extension ReadWriteTests: AccessoryConnectionDelegate {
    func shouldOpenSession(for accessory: MockableAccessory) -> Bool {
        shouldOpenCompletion?(accessory) ?? false
    }
    func sessionDidOpen(with accessory: MockableAccessory, writeReadyStream: AsyncThrowingStream<Bool, Error>?, readDataStream: AsyncThrowingStream<Data, Error>?) {
        didOpenCompletion?(accessory, writeReadyStream, readDataStream)
    }
}
