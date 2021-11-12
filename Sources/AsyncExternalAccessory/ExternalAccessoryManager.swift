//  ExternalAccessoryManager.swift
//
//  Created by Yuval Koren on 10/28/21.
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

import ExternalAccessory
import AsyncStream

public enum ExternalAccessoryManagerError: Error {
    case UnknownAccessory
    case StreamNotOpen
}

/// A delegate to listen for accessory connection events.
public protocol AccessoryConnectionDelegate: AnyObject {
    /// Inspect the arriving accessory and determine whether to open read and write sessions for it.
    /// - Return `true` to request that session be opened, `false` to ignore.
    /// - If `true` is returned,`sessionDidOpen` will be called next.
    func shouldOpenSession(for accessory: MockableAccessory) -> Bool
    /// Receive write backpressure stream and read data stream. Both are optional, reflecting the behavior of the underlying EASession.
    /// - writeReadyStream will finish when the accessory has disconnected.
    func sessionDidOpen(with accessory: MockableAccessory, writeReadyStream: AsyncThrowingStream<Bool, Error>?, readDataStream: AsyncThrowingStream<Data, Error>?)
}

public actor ExternalAccessoryManager: NSObject {
    struct AsyncStreamPair {
        let input: InputStreamActor?
        let output: OutputStreamActor?
    }
    private weak var delegate: AccessoryConnectionDelegate?
    private var map = [MockableAccessory: AsyncStreamPair]()
    
    @MainActor
    @objc dynamic public func accessoryConnect(_ notificaton: NSNotification) {
        print(#function)
        if let accessory = MockableAccessory.init(from: notificaton) {
            Task.detached {
                await self.connect(accessory)
            }
        }
    }
    
    @MainActor
    @objc dynamic public func accessoryDisconnect(_ notificaton: NSNotification) {
        print(#function)
        if let accessory = MockableAccessory.init(from: notificaton) {
            Task.detached {
                await self.disconnect(accessory)
            }
        }
    }
    
    public func set(_ delegate: AccessoryConnectionDelegate) {
        self.delegate = delegate
    }
    
    public func connectToPresentAccessories(_ list: [MockableAccessory]) async {
        for accessory in list {
            await connect(accessory)
        }
    }
    
    public func connectToPresentAccessories() async {
        let list = EAAccessoryManager.shared().connectedAccessories
        for accessory in list {
            await connect(MockableAccessory(accessory))
        }
    }
    
    public func listen() async {
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryConnect(_:)), name: .EAAccessoryDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryDisconnect(_:)), name: .EAAccessoryDidDisconnect, object: nil)
        EAAccessoryManager.shared().registerForLocalNotifications()
    }
    
    public func write(_ data: Data, to accessory: MockableAccessory) async throws -> Int {
        guard let streamPair = map[accessory] else {
            throw ExternalAccessoryManagerError.UnknownAccessory
        }
        guard let output = streamPair.output else {
            throw ExternalAccessoryManagerError.StreamNotOpen
        }
        return try await output.write(data)
    }
    
    @MainActor
    private func openSession(_ accessory: MockableAccessory) -> AsyncStreamPair? {
        guard let streamPair = accessory.getStreams() else {
            return nil
        }
        var inputStreamActor: InputStreamActor?
        var outputStreamActor: OutputStreamActor?
        if let inputStream = streamPair.input {
            inputStreamActor = InputStreamActor(inputStream)
        }
        if let outputStream = streamPair.output {
            outputStreamActor = OutputStreamActor(outputStream)
        }
        return AsyncStreamPair(input: inputStreamActor, output: outputStreamActor)
    }
    
    private func connect(_ accessory: MockableAccessory) async {
        guard delegate?.shouldOpenSession(for: accessory) == true else {
            return
        }
        var readDataAsyncStream: AsyncThrowingStream<Data, Error>?
        var writeReadyAsyncStream: AsyncThrowingStream<Bool, Error>?
        let session = await openSession(accessory)
        if let input = session?.input {
            readDataAsyncStream = await input.getReadDataStream()
        }
        if let output = session?.output {
            writeReadyAsyncStream = await output.getSpaceAvailableStream()
        }
        map[accessory] = session
        delegate?.sessionDidOpen(with: accessory, writeReadyStream: writeReadyAsyncStream, readDataStream: readDataAsyncStream)
    }
    
    private func disconnect(_ accessory: MockableAccessory) {
        map[accessory] = nil
    }
}
