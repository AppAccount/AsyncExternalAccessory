//  AccessoryProtocol.swift
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

public struct DuplexStream {
    public let input: InputStream?
    public let output: OutputStream?
}

public struct AccessoryIdentity: Equatable {
    public let name: String
    public let modelNumber: String
    public let serialNumber: String
    public let manufacturer: String
    public let hardwareRevision: String
    public let protocolStrings: [String]
    public let connectionID: Int
}

public protocol AccessoryProtocol {
    var name: String { get }
    var modelNumber: String { get }
    var serialNumber: String { get }
    var manufacturer: String { get }
    var hardwareRevision: String { get }
    var protocolStrings: [String] { get }
    var connectionID: Int { get }
    func getStreams()-> DuplexStream?
}

extension NSNotification {
    func findAccessory()-> AccessoryProtocol? {
        guard let accessory = userInfo![EAAccessoryKey] as? AccessoryProtocol else {
            return nil
        }
        return accessory
    }
}

extension EAAccessory: AccessoryProtocol {
    public func getStreams()-> DuplexStream? {
        for protocolString in protocolStrings {
            if let session = EASession(accessory: self, forProtocol: protocolString) {
                return DuplexStream(input: session.inputStream, output: session.outputStream)
            }
        }
        return nil
    }
}
