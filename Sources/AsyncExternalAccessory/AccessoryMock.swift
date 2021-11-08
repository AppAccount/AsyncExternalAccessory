//  AccessoryIdentity.swift
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

struct AccessoryMock {
    let name: String
    let modelNumber: String
    let serialNumber: String
    let manufacturer: String
    let hardwareRevision: String
    let protocolStrings: [String]
    let connectionID: Int
    let inputStream: InputStream
    let outputStream: OutputStream
    
    init(name: String, modelNumber: String, serialNumber: String, manufacturer: String, hardwareRevision: String, protocolStrings: [String], connectionID: Int, inputStream: InputStream, outputStream: OutputStream) {
        self.name = name
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.manufacturer = manufacturer
        self.hardwareRevision = hardwareRevision
        self.protocolStrings = protocolStrings
        self.connectionID = connectionID
        self.inputStream = inputStream
        self.outputStream = outputStream
    }
}

extension AccessoryMock {
    func same(_ other: AccessoryMock) -> Bool {
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
