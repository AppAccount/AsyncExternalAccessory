//  MockableAccessory.swift
//
//  Created by Yuval Koren on 10/29/21.
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

public struct MockableAccessory: Hashable {
    #if targetEnvironment(simulator)
    let accessory: AccessoryMock
    let inputStream: InputStream
    let outputStream: OutputStream
    init(_ accessory: AccessoryMock, inputStream: InputStream, outputStream: OutputStream) {
        self.accessory = accessory
        self.inputStream = inputStream
        self.outputStream = outputStream
    }
    init?(from notification: NSNotification) {
        guard let accessory = notification.userInfo![EAAccessoryKey] as? MockableAccessory else {
            return nil
        }
        self = accessory
    }
    func getStreams()-> (InputStream, OutputStream)? {
        return (inputStream, outputStream)
    }
    #else
    let accessory: EAAccessory
    init(_ accessory: EAAccessory) {
        self.accessory = accessory
    }
    init?(from notification: NSNotification) {
        guard let accessory = notification.userInfo![EAAccessoryKey] as? EAAccessory else {
            return nil
        }
        self.accessory = accessory
    }
    func getStreams()-> (InputStream, OutputStream)? {
        for protocolString in accessory.protocolStrings {
            if let session = EASession(accessory: accessory, forProtocol: protocolString),
               let inputStream = session.inputStream,
               let outputStream = session.outputStream {
                return (inputStream, outputStream)
            }
        }
        return nil
    }
    #endif
}
