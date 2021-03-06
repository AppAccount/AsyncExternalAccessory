//  AccessoryMock.swift
//
//  Created by Yuval Koren on 12/1/21.
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

import Foundation

public struct AccessoryMock: AccessoryProtocol {
    public let name: String
    public let modelNumber: String
    public let serialNumber: String
    public let manufacturer: String
    public let firmwareRevision: String
    public let hardwareRevision: String
    public let protocolStrings: [String]
    public let connectionID: Int
    let inputStream: InputStream
    let outputStream: OutputStream
    
    public init(name: String, modelNumber: String, serialNumber: String, manufacturer: String, firmwareRevision: String, hardwareRevision: String, protocolStrings: [String], connectionID: Int, inputStream: InputStream, outputStream: OutputStream) {
        self.name = name
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.manufacturer = manufacturer
        self.firmwareRevision = firmwareRevision
        self.hardwareRevision = hardwareRevision
        self.protocolStrings = protocolStrings
        self.connectionID = connectionID
        self.inputStream = inputStream
        self.outputStream = outputStream
    }
    
    public func getStreams() -> DuplexStream? {
        DuplexStream(input: inputStream, output: outputStream)
    }
}

extension AccessoryMock {
    public func same(_ other: AccessoryProtocol) -> Bool {
        return self.serialNumber == other.serialNumber && self.name == other.name
    }
}

extension AccessoryMock: Equatable {
    public static func == (lhs: AccessoryMock, rhs: AccessoryMock) -> Bool {
        return lhs.serialNumber == rhs.serialNumber && lhs.name == rhs.name && lhs.connectionID == rhs.connectionID
    }
}

extension AccessoryMock: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(serialNumber)
        hasher.combine(name)
    }
}
