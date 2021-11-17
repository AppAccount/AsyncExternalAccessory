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
    var accessory: AccessoryMock!
    var shouldOpenCompletion: ((AccessoryMock)->Bool)?
    var didOpenCompletion: ((AccessoryMock, DuplexAsyncStream?)->())?
    var duplexAsyncStream: DuplexAsyncStream?
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
        self.shouldOpenCompletion = { accessory in
            return true
        }
        Task {
            await self.manager.connectToPresentAccessories([self.accessory])
        }
        self.duplexAsyncStream = await withCheckedContinuation { cont in
            self.didOpenCompletion = { _, duplex in
                cont.resume(returning: duplex)
            }
        }
    }
    
    override func tearDown() {
        shouldOpenCompletion = nil
        didOpenCompletion = nil
        duplexAsyncStream = nil
        timeoutTask.cancel()
    }
    
    func testShortWriteAndRead() async throws {
        let size = 16
        guard let duplex = self.duplexAsyncStream else {
            XCTFail()
            return
        }
        try await withThrowingTaskGroup(of: Bool.self) { taskGroup in
            taskGroup.addTask {
                let readDataStream = await duplex.input.getReadDataStream()
                for try await data in readDataStream {
                    let bytesRead = data.count
                    return(bytesRead == size)
                }
                return false
            }
            taskGroup.addTask {
                let writeDataStream = AsyncStream<Data> { continuation in
                    let data = Data.init(count: size)
                    continuation.yield(data)
                }
                await duplex.output.setWriteDataStream(writeDataStream)
                return true
            }
            if try await taskGroup.allSatisfy({ $0 }) != true {
                XCTFail()
            }
        }
    }
}

extension ReadWriteTests: AccessoryConnectionDelegate {
    func shouldOpenSession(for accessory: AccessoryProtocol) -> Bool {
        shouldOpenCompletion?(accessory as! AccessoryMock) ?? false
    }
    func sessionDidOpen(for accessory: AccessoryProtocol, session: DuplexAsyncStream?) {
        didOpenCompletion?(accessory as! AccessoryMock, session)
    }
}
