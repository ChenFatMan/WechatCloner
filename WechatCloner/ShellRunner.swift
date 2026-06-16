import Foundation

struct ShellRunner: Sendable {
    func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            let command = ([executable] + arguments).joined(separator: " ")
            throw CloneError.shellFailed(
                command: command,
                status: process.terminationStatus,
                output: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
