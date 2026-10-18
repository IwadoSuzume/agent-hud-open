import AgentHUDSupport
import Foundation
@testable import AgentHUDCore

/// Reading Agent HUD's handlers back from a client's file the same way on every platform. On macOS a handler's command
/// is the line `HookCommand.make` wrote; on Windows a client may be given the program and its arguments apart, or another
/// shell's quoting (docs/windows-port/DECISIONS.md D-037), and this joins them into that same line.
enum TestHooks {
    /// The command line of `handler`: its `command` (or `key`) as written, or on Windows the line `HookCommand.make` makes
    /// for an exec-form handler's program and arguments, or for a Git Bash or PowerShell line of Agent HUD's.
    static func commandLine(of handler: ProviderJSON, key: String = "command") -> String? {
        #if os(Windows)
        // Whichever client's form the handler is in, read back the way HookInstaller reads it (HookCommand+Windows).
        for flag in ["--permission-hook", "--completion-hook", "--attention-hook", "--session-origin-hook"] {
            for client in ["claude", "qoder", "copilot", "codex", "codebuddy", "qwen"] {
                let arguments = "\(flag) \(client)", lineKey = HookCommand.lineKey(arguments: arguments)
                guard let fields = handler.objectValue,
                      let read = HookCommand.commandLines(["handler": .object(fields)], arguments: arguments)["handler"],
                      let line = read[lineKey].stringValue, HookCommand.runs(line, arguments: arguments) else { continue }
                return line
            }
        }
        return handler[key].stringValue ?? handler["bash"].stringValue
        #else
        return handler[key].stringValue
        #endif
    }

    /// `configuration` as `HookInstaller.read` hands it to the shared code after it was written: the same on macOS; on
    /// Windows the handlers in their client's form (D-037), with exec-form ones joined back into a line.
    static func asRead(_ configuration: [String: ProviderJSON], arguments: String) -> [String: ProviderJSON] {
        #if os(Windows)
        HookCommand.commandLines(HookCommand.clientForms(configuration, arguments: arguments), arguments: arguments)
        #else
        configuration
        #endif
    }

    /// Whether this platform gives the client a hook's `arguments` end with a handler: on Windows only the clients whose
    /// hook shell a source gives (D-037).
    static func installs(arguments: String) -> Bool {
        #if os(Windows)
        HookCommand.windowsForm(arguments: arguments) != nil
        #else
        true
        #endif
    }
}
