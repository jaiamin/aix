import Foundation

public struct Captured: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
}

/// Runs a program to completion with no terminal attached and returns its output.
public func capture(_ argv: [String], in directory: String? = nil) -> Captured {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: argv[0])
    p.arguments = Array(argv.dropFirst())
    if let directory { p.currentDirectoryURL = URL(fileURLWithPath: directory) }
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    p.standardInput = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return Captured(status: 127, stdout: "", stderr: "could not start \(argv[0])") }
    let o = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return Captured(status: p.terminationStatus, stdout: String(decoding: o, as: UTF8.self), stderr: String(decoding: e, as: UTF8.self))
}
