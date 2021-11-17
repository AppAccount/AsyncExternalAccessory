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

public struct DuplexAsyncStream {
    public let input: InputStreamActor
    public let output: OutputStreamActor
}

/// A delegate to listen for accessory connection events.
public protocol AccessoryConnectionDelegate: AnyObject {
    /// Inspect the arriving accessory and determine whether to open read and write sessions for it.
    /// - Return `true` to request that session be opened, `false` to ignore.
    /// - If `true` is returned,`sessionDidOpen` will be called next.
    func shouldOpenSession(for accessory: AccessoryProtocol) -> Bool
    /// Receive input (read) and output (write) AsyncStreams for access to the underlying EA sessions
    func sessionDidOpen(for accessory: AccessoryProtocol, session: DuplexAsyncStream?)
    /// additional close/disconnect method?
}

public actor ExternalAccessoryManager: NSObject {
    private weak var delegate: AccessoryConnectionDelegate?
    
    @MainActor
    @objc dynamic public func accessoryConnect(_ notificaton: NSNotification) {
        print(#function)
        if let accessory = notificaton.findAccessory() {
            Task.detached {
                await self.connect(accessory)
            }
        }
    }
    
    public func set(_ delegate: AccessoryConnectionDelegate) {
        self.delegate = delegate
    }
    
    public func connectToPresentAccessories(_ list: [AccessoryProtocol]) async {
        for accessory in list {
            await connect(accessory)
        }
    }
    
    public func connectToPresentAccessories() async {
        let list = EAAccessoryManager.shared().connectedAccessories
        for accessory in list {
            await connect(accessory)
        }
    }
    
    public func listen() async {
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryConnect(_:)), name: .EAAccessoryDidConnect, object: nil)
        EAAccessoryManager.shared().registerForLocalNotifications()
    }
    
    @MainActor
    private func openSession(_ accessory: AccessoryProtocol) -> DuplexAsyncStream? {
        guard let duplexStream = accessory.getStreams() else {
            return nil
        }
        guard let inputStream = duplexStream.input, let outputStream = duplexStream.output else {
            return nil
        }
        let inputStreamActor = InputStreamActor(inputStream)
        let outputStreamActor = OutputStreamActor(outputStream)
        return DuplexAsyncStream(input: inputStreamActor, output: outputStreamActor)
    }
    
    private func connect(_ accessory: AccessoryProtocol) async {
        guard delegate?.shouldOpenSession(for: accessory) == true else {
            return
        }
        let session = await openSession(accessory)
        delegate?.sessionDidOpen(for: accessory, session: session)
    }
}
