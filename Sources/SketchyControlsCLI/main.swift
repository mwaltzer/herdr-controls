import Foundation
import SketchyControlsCore

do {
    let command = try PanelCommand.parse(arguments: Array(CommandLine.arguments.dropFirst()))
    try IPCClient.send(command)
    if command.action == .status { print("running") }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
