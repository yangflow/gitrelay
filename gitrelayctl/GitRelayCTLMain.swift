import Foundation

@main
struct GitRelayCTLMain {
    static func main() async {
        let exitCode: GitRelayCLIExitCode
        do {
            switch GitRelayCLIParser.parse(CommandLine.arguments) {
            case .success(let command):
                exitCode = try await GitRelayCLIExecutor.run(command: command)
            case .failure(let error):
                fputs("error: \(error.localizedDescription)\n", stderr)
                fputs("\n\(GitRelayCLIParser.usage)\n", stderr)
                exitCode = .usage
            }
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exitCode = GitRelayCLIExecutor.exitCode(for: error)
        }
        exit(exitCode.rawValue)
    }
}
