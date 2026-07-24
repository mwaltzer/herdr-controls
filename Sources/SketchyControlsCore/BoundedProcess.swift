import Darwin
import Foundation

public struct BoundedProcessResult: Sendable {
    public let output: Data
    public let terminationStatus: Int32
    public let timedOut: Bool
}

public enum BoundedProcess {
    public static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int = 1_048_576,
        environment: [String: String]? = nil
    ) -> BoundedProcessResult? {
        let process = Process()
        let pipe = Pipe()
        let termination = DispatchSemaphore(value: 0)
        let reader = DispatchGroup()
        let lock = NSLock()
        var output = Data()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
        }
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in termination.signal() }

        reader.enter()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = pipe.fileHandleForReading.readData(ofLength: 16_384)
                if chunk.isEmpty { break }
                lock.lock()
                let remaining = max(0, outputLimit - output.count)
                if remaining > 0 { output.append(chunk.prefix(remaining)) }
                lock.unlock()
            }
            reader.leave()
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForWriting.closeFile()
            _ = reader.wait(timeout: .now() + 1)
            return nil
        }

        let deadline = DispatchTime.now() + max(0, timeout)
        let timedOut = termination.wait(timeout: deadline) == .timedOut
        if timedOut {
            process.terminate()
            if termination.wait(timeout: .now() + 0.2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = termination.wait(timeout: .now() + 1)
            }
        }

        pipe.fileHandleForWriting.closeFile()
        _ = reader.wait(timeout: .now() + 1)
        lock.lock()
        let captured = output
        lock.unlock()
        return BoundedProcessResult(
            output: captured,
            terminationStatus: process.terminationStatus,
            timedOut: timedOut
        )
    }
}
