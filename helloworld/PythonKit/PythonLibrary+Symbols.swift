//===-- PythonLibrary+Symbols.swift ---------------------------*- swift -*-===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
// This file defines the Python symbols required for the interoperability layer.
//
//===----------------------------------------------------------------------===//

import Python

//===----------------------------------------------------------------------===//
// Required Python typealias and constants.
//===----------------------------------------------------------------------===//

typealias PyObjectPointer = UnsafeMutablePointer<PyObject>
typealias PyCCharPointer = UnsafePointer<Int8>
typealias PyBinaryOperation =
  @convention(c) (PyObjectPointer?, PyObjectPointer?) -> PyObjectPointer?

let Py_LT: Int32 = 0
let Py_LE: Int32 = 1
let Py_EQ: Int32 = 2
let Py_NE: Int32 = 3
let Py_GT: Int32 = 4
let Py_GE: Int32 = 5

//===----------------------------------------------------------------------===//
// Python library symbols lazily loaded at runtime.
//===----------------------------------------------------------------------===//

//let PyRun_SimpleString: @convention(c) (PyCCharPointer) -> Void =
//    PythonLibrary.loadSymbol(name: "PyRun_SimpleString")

func PyRun_SimpleString(_ string: PyCCharPointer) -> Void {
    PyRun_SimpleStringFlags(string, nil)
}

//let PyInt_AsLong: @convention(c) (PyObjectPointer) -> Int =
//  PythonLibrary.loadSymbol(
//    name: "PyLong_AsLong",
//    legacyName: "PyInt_AsLong")

let PyInt_AsLong = PyLong_AsLong

//let PyInt_FromLong: @convention(c) (Int) -> PyObjectPointer =
//  PythonLibrary.loadSymbol(
//    name: "PyLong_FromLong",
//    legacyName: "PyInt_FromLong")

let PyInt_FromLong = PyLong_FromLong

//let PyInt_AsUnsignedLongMask: @convention(c) (PyObjectPointer) -> UInt =
//  PythonLibrary.loadSymbol(
//    name: "PyLong_AsUnsignedLongMask",
//    legacyName: "PyInt_AsUnsignedLongMask")

let PyInt_AsUnsignedLongMask = PyLong_AsUnsignedLongMask

//let PyInt_FromSize_t: @convention(c) (UInt) -> PyObjectPointer =
//  PythonLibrary.loadSymbol(
//    name: "PyLong_FromUnsignedLong",
//    legacyName: "PyInt_FromSize_t")

let PyInt_FromSize_t = PyLong_FromUnsignedLong

//let PyString_AsString: @convention(c) (PyObjectPointer) -> PyCCharPointer? =
//  PythonLibrary.loadSymbol(
//    name: "PyUnicode_AsUTF8",
//    legacyName: "PyString_AsString")

let PyString_AsString = PyUnicode_AsUTF8

//let PyString_FromStringAndSize: @convention(c) (
//  PyCCharPointer?, Int) -> (PyObjectPointer?) =
//  PythonLibrary.loadSymbol(
//    name: "PyUnicode_DecodeUTF8",
//    legacyName: "PyString_FromStringAndSize")

func PyString_FromStringAndSize(_ string: PyCCharPointer?, _ size: Int) -> (PyObjectPointer?) { PyUnicode_DecodeUTF8(string, size, nil) }
