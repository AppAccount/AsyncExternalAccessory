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
    enum ExternalAccessoryOrMock: Equatable, Hashable {
        case ea(EAAccessory), mock(AccessoryMock)
    }
    let accessory: ExternalAccessoryOrMock
    init(_ accessory: EAAccessory) {
        self.accessory = .ea(accessory)
    }
    public init(_ accessory: AccessoryMock) {
        self.accessory = .mock(accessory)
    }
    public init?(from notification: NSNotification) {
        if let accessory = notification.userInfo![EAAccessoryKey] as? AccessoryMock {
            self.accessory = .mock(accessory)
        }
        else if let accessory = notification.userInfo![EAAccessoryKey] as? EAAccessory {
            self.accessory = .ea(accessory)
        } else {
            return nil
        }
    }
    func getStreams()-> (InputStream, OutputStream)? {
        switch accessory {
        case .ea(let accessory): return getEAStreams(accessory)
        case .mock(let accessory): return (accessory.inputStream, accessory.outputStream)
        }
    }
    
    func getEAStreams(_ accessory: EAAccessory)-> (InputStream, OutputStream)? {
        for protocolString in accessory.protocolStrings {
            if let session = EASession(accessory: accessory, forProtocol: protocolString),
               let inputStream = session.inputStream,
               let outputStream = session.outputStream {
                return (inputStream, outputStream)
            }
        }
        return nil
    }
}
