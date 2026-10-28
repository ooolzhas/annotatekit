// `annotate` executable: parses arguments and hands off to AnnotateAgent.Command.

import AnnotateAgent
import Foundation

do {
    let invocation = try Command.parse(Array(CommandLine.arguments.dropFirst()))
    exit(await Command.execute(invocation))
} catch {
    FileHandle.standardError.write(Data("annotate: \(error)\n\n\(Command.usage)\n".utf8))
    exit(2)
}
