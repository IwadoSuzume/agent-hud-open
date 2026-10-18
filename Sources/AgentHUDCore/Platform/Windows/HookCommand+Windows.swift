#if os(Windows)
import AgentHUDSupport
import Foundation
import WinSDK

/// How each client runs a hook's command on Windows, and the handler Agent HUD writes for it there
/// (docs/windows-port/DECISIONS.md D-037, sources in SUPPORT_MATRIX.md).
///
/// The shared hook code keeps working on one command line per handler, `"<engine>" <arguments>` here
/// (`HookCommand.make`), and finds Agent HUD's handlers by the arguments it ends with. A client that starts a program
/// without a shell is given that form instead: `HookInstaller` hands the shared code the file with those handlers as
/// command lines (`commandLines`), and writes back the shared code's result in each client's own form (`clientForms`).
extension HookCommand {
    /// The ways the clients that keep hooks on Windows run a handler.
    enum WindowsForm: Equatable {
        /// `command` is the program and `args` its arguments, started without a shell (Claude Code and Qoder;
        /// Copilot CLI names the program `exec`).
        case exec(programKey: String)
        /// The command line as it is: Codex runs it with `%ComSpec% /C`.
        case commandProcessor
        /// Bash syntax: CodeBuddy Code runs every hook in Git Bash. The path is written with forward slashes in double
        /// quotes, `$`, `` ` ``, `"` and `\` escaped: Git Bash's runtime reads the Windows command line it is started
        /// with itself and takes a single quote in an argument for its own quoting, so `'…'\''…'` comes apart there.
        case gitBash
        /// `"shell": "powershell"`: Qwen Code runs it with `powershell -Command`.
        case powerShell
    }

    /// The form for the client a hook's arguments end with (`--permission-hook claude`), or nil for a client whose
    /// Windows hook shell no source gives: Cursor, Qoder CN and QoderWork document none, and Antigravity, ZCode and
    /// WorkBuddy are not supported on Windows (D-036).
    static func windowsForm(arguments: String) -> WindowsForm? {
        switch arguments.split(separator: " ").last.map(String.init) {
        // Qoder CLI documents its exec form with Windows caveats; Qoder CN's and QoderWork's docs say nothing of Windows.
        case "claude", PermissionHooks.Source.qoder.rawValue:
            .exec(programKey: "command")
        case "copilot": .exec(programKey: "exec")
        case "codex": .commandProcessor
        case "codebuddy": .gitBash
        case "qwen": .powerShell
        default: nil
        }
    }

    /// Why a client without a Windows hook form is given no handler.
    static var unsupportedOnWindows: UsageProviderError {
        UsageProviderError(L10n.text("这个客户端在 Windows 上没有可用的回调方式", "This client has no supported way to run hooks on Windows"))
    }

    /// The key that holds the command line in a handler written for `arguments`: `bash` in Copilot CLI's file, whose
    /// format the shared code reads by that key, `command` everywhere else.
    static func lineKey(arguments: String) -> String {
        windowsForm(arguments: arguments) == .exec(programKey: "exec") ? "bash" : "command"
    }

    /// Characters an engine path may not hold on Windows: `%` and `!` would be expanded by the command processor even
    /// inside quotes, `"` ends a quoted path, the typographic single quotes are quotes to PowerShell, and control
    /// characters have no place in a command line.
    static func refusesWindowsPath(_ path: String) -> Bool {
        path.unicodeScalars.contains {
            "%!\"\u{2018}\u{2019}\u{201A}\u{201B}".unicodeScalars.contains($0) || $0.value < 0x20 || $0.value == 0x7F
        }
    }

    /// `"<path>"`, the path quoted for the command processor and for Windows' own argument parsing.
    static func quotedWindowsPath(_ executable: URL) -> String {
        "\"" + executable.path.replacingOccurrences(of: "/", with: "\\") + "\""
    }

    /// The program of a command line `make` wrote, `"<path>" <arguments>`, or nil for another command line.
    static func program(ofLine line: String, arguments: String) -> String? {
        guard line.hasPrefix("\""), line.hasSuffix("\" " + arguments) else { return nil }
        let quoted = line.dropLast(arguments.count + 1)
        guard quoted.count >= 2 else { return nil }
        let path = String(quoted.dropFirst().dropLast())
        return path.contains("\"") ? nil : path
    }

    /// `"C:/…"`: a Windows path for Bash's double quotes, with forward slashes and Bash's four special characters escaped.
    static func gitBashPath(_ program: String) -> String {
        var escaped = ""
        for character in program.replacingOccurrences(of: "\\", with: "/") {
            if "$`\"\\".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return "\"" + escaped + "\""
    }

    /// `configuration` with every handler in a client form that runs Agent HUD with `arguments` turned into the command
    /// line `make` writes, under the key the shared code reads: an exec-form handler's program and arguments are joined,
    /// and a Git Bash or PowerShell line is spelled the command processor's way (its `"shell"` set aside, which
    /// `clientForms` writes again). Other handlers, and lines already in that form, are unchanged.
    static func commandLines(_ configuration: [String: JSONValue], arguments: String) -> [String: JSONValue] {
        guard let form = windowsForm(arguments: arguments), form != .commandProcessor else { return configuration }
        let key = lineKey(arguments: arguments)
        return mapObjects(configuration) { fields in
            var line = fields
            switch form {
            case .exec(let programKey):
                guard let program = fields[programKey]?.stringValue, let args = fields["args"]?.arrayValue else { return fields }
                let words = args.compactMap(\.stringValue)
                guard words.count == args.count, runs(([program] + words).joined(separator: " "), arguments: arguments) else { return fields }
                line[programKey] = nil
                line["args"] = nil
                line[key] = .string(quotedWindowsPath(URL(fileURLWithPath: program)) + " " + words.joined(separator: " "))
            case .gitBash, .powerShell:
                guard let text = fields[key]?.stringValue, let program = program(ofClientLine: text, form: form, arguments: arguments)
                else { return fields }
                line[key] = .string(quotedWindowsPath(URL(fileURLWithPath: program)) + " " + arguments)
                if form == .powerShell, line["shell"]?.stringValue == "powershell" { line["shell"] = nil }
            case .commandProcessor:
                return fields
            }
            return line
        }
    }

    /// The program of a Git Bash or PowerShell line `clientForms` wrote for `arguments`, or nil for another line.
    static func program(ofClientLine line: String, form: WindowsForm, arguments: String) -> String? {
        guard line.hasSuffix(" " + arguments) else { return nil }
        let quoted = String(line.dropLast(arguments.count + 1))
        switch form {
        case .gitBash:
            guard quoted.count >= 2, quoted.hasPrefix("\""), quoted.hasSuffix("\"") else { return nil }
            var path = "", escaped = false
            for character in quoted.dropFirst().dropLast() {
                // Only the escapes `gitBashPath` writes: a backslash before anything else is a Windows path's.
                if escaped { guard "$`\"\\".contains(character) else { return nil }; path.append(character); escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { return nil }
                else { path.append(character == "/" ? "\\" : character) }
            }
            return escaped ? nil : path
        case .powerShell:
            guard quoted.count >= 4, quoted.hasPrefix("& '"), quoted.hasSuffix("'") else { return nil }
            let inner = String(quoted.dropFirst(3).dropLast())
            // Every quote inside is doubled; a lone one would end the string early.
            guard inner.replacingOccurrences(of: "''", with: "").contains("'") == false else { return nil }
            return inner.replacingOccurrences(of: "''", with: "'")
        default:
            return nil
        }
    }

    /// `configuration` with every handler the shared code holds as a command line `make` wrote for `arguments` written
    /// in the client's form. A line Agent HUD did not write is left alone.
    static func clientForms(_ configuration: [String: JSONValue], arguments: String) -> [String: JSONValue] {
        guard let form = windowsForm(arguments: arguments), form != .commandProcessor else { return configuration }
        let key = lineKey(arguments: arguments)
        return mapObjects(configuration) { fields in
            // Only a line `make` wrote, whose path has backslashes: a client form already written is left as it is.
            guard let line = fields[key]?.stringValue, let program = program(ofLine: line, arguments: arguments),
                  !program.contains("/") else { return fields }
            var handler = fields
            switch form {
            case .exec(let programKey):
                handler[key] = nil
                handler[programKey] = .string(program)
                handler["args"] = .array(arguments.split(separator: " ").map { .string(String($0)) })
            case .gitBash:
                handler[key] = .string(gitBashPath(program) + " " + arguments)
            case .powerShell:
                handler[key] = .string("& '" + program.replacingOccurrences(of: "'", with: "''") + "' " + arguments)
                handler["shell"] = .string("powershell")
            case .commandProcessor:
                break
            }
            return handler
        }
    }

    /// `object` with `transform` applied to every object in it, innermost first.
    private static func mapObjects(_ object: [String: JSONValue],
                                   _ transform: ([String: JSONValue]) -> [String: JSONValue]) -> [String: JSONValue] {
        func map(_ value: JSONValue) -> JSONValue {
            switch value {
            case .object(let fields): .object(transform(fields.mapValues(map)))
            case .array(let items): .array(items.map(map))
            default: value
            }
        }
        return object.mapValues(map)
    }

    /// Windows' transient places, as `/Volumes` and App Translocation are macOS's: the copy Explorer makes of a zip's
    /// folder when a program is run from inside the zip (`Temp<n>_<name>.zip` in the temporary folder), a removable,
    /// optical or RAM drive, and a network share. A handler pointing there stops working once the copy is cleaned up or
    /// the drive goes. The temporary folder as such is not one, as `/tmp` is not on macOS.
    static func isTransientOnWindows(_ path: String) -> Bool {
        let native = path.replacingOccurrences(of: "/", with: "\\")
        if native.hasPrefix(#"\\"#) { return true }
        // Each spelled as given and in its long form: a temporary folder named in its 8.3 form (`C:\Users\9B63~1\…`, for
        // a long or non-ASCII user name) still holds an engine path spelled in full, and the other way round.
        let spellings = Set([native, Win32.longPath(native)].map(PathCase.folded))
        let temporary = Set([Win32.environment("TEMP"), Win32.environment("TMP"),
                             FileManager.default.temporaryDirectory.path].compactMap { $0 }
            .map { $0.replacingOccurrences(of: "/", with: "\\") }
            .flatMap { [$0, Win32.longPath($0)] }
            .map { PathCase.folded($0) }
            .map { $0.hasSuffix("\\") ? $0 : $0 + "\\" })
        for folded in spellings {
        for folder in temporary where folded.hasPrefix(folder) {
            let first = folded.dropFirst(folder.count).split(separator: "\\").first.map(String.init) ?? ""
            if first.hasPrefix("temp"), first.hasSuffix(".zip"), let underscore = first.firstIndex(of: "_"),
               first[first.index(first.startIndex, offsetBy: 4)..<underscore].allSatisfy(\.isNumber),
               underscore > first.index(first.startIndex, offsetBy: 4) { return true }
        }
        }
        guard native.count >= 2, native.dropFirst().first == ":" else { return false }
        let type = Win32.withWide(String(native.prefix(2)) + "\\") { GetDriveTypeW($0) }
        return [UINT(DRIVE_REMOVABLE), UINT(DRIVE_REMOTE), UINT(DRIVE_CDROM), UINT(DRIVE_RAMDISK)].contains(type)
    }
}
#endif
