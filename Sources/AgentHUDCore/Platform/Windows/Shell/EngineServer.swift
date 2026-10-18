#if os(Windows)
import AgentHUDSupport
import Foundation
import Observation

/// What `agenthud-engine --serve` runs for the Windows shell (PROTOCOL.md, D-041): the part of the macOS
/// `DesktopApplication` that is not a window — the settings and the store, the approval channel, the client hooks and
/// the observers — with what it would draw sent to the shell as protocol messages instead, and what the user does
/// taken back from it. Commands arrive through `receive(_:)`, one line each; lines go out through `send`.
@MainActor
public final class EngineServer {
    public struct Options: Sendable {
        public var demo = false
        public var language: AppLanguage?
        /// The program the clients' hooks run (`agenthud-engine.exe`); nil installs no hook.
        public var executable: URL?
        /// Where the single-instance lock is (`InstanceLock.sharedURL`); a test gives its own.
        public var lock: URL = InstanceLock.sharedURL
        /// The settings file (`SettingsFile`); nil is the standard one, `settings.json` or the demo's.
        public var settingsURL: URL?
        public init() {}
    }

    private let options: Options
    private let send: @Sendable (Data) -> Void
    private let finish: @MainActor (Int32) -> Void
    private var instanceLock: InstanceLock?
    private(set) var settings: SettingsStore?
    private(set) var store: UsageStore?
    private var tracker = IslandEventTracker()
    private var stateScheduled = false
    private var started = false
    private var stopped = false
    private var language: AppLanguage?
    private let deepseekQuestions = DeepSeekQuestionObserver()

    /// `send` writes one line to the shell; `finish` ends the process with a status, after `stop()`.
    public init(options: Options, send: @escaping @Sendable (Data) -> Void, finish: @escaping @MainActor (Int32) -> Void) {
        self.options = options
        self.send = send
        self.finish = finish
    }

    /// One line from the shell.
    public func receive(_ line: Data) {
        let command: ShellProtocol.Command
        do { command = try ShellProtocol.command(line) } catch {
            write(ShellProtocol.error(String(describing: error)))
            return
        }
        switch command {
        case .hello:
            guard !started else { return write(ShellProtocol.error("hello was already given")) }
            start()
        case .refresh:
            guard let store else { return write(ShellProtocol.error("no hello yet")) }
            Task { await store.refresh() }
        case .answer(let id, let answer):
            guard let request = PermissionRequests.shared.pending.first(where: { $0.id == id }) else { return }
            guard let decision = answer.decision(for: request) else {
                return write(ShellProtocol.error("request \(id) offers no rule to always allow"))
            }
            PermissionRequests.shared.resolve(id, decision)
        case .updateSettings(let patch):
            guard let settings else { return write(ShellProtocol.error("no hello yet")) }
            do {
                let updated = try ShellProtocol.settings(settings.settings, applying: patch)
                settings.update { $0 = updated }
            } catch {
                write(ShellProtocol.error(String(describing: error)))
            }
        case .quit:
            end(0)
        }
    }

    /// The shell's input ended: it quit or went away.
    public func inputEnded() { end(0) }

    private func start() {
        started = true
        if !options.demo {
            switch InstanceLock.claim(at: options.lock, executable: options.executable) {
            case .acquired(let lock): instanceLock = lock
            case .held(let holder):
                write(helloMessage(language: L10n.language))
                write(ShellProtocol.lockHeld(holder: holder))
                return end(3)
            case .unavailable: break // as on macOS, the engine runs without one rather than not at all
            }
        }
        let file = options.settingsURL.flatMap { SettingsFile(url: $0) } ?? SettingsFile.standard(demo: options.demo)
        let settings = UsageAssembly.settings(defaults: file, defaultAgents: options.demo ? DemoData.everyAgent : [],
                                              language: options.language)
        if options.demo, !settings.agents.contains(where: { row in DemoData.agents.contains { $0.id == row.id } }) {
            settings.updateAgents { _ in DemoData.everyAgent }
        }
        let store = UsageAssembly.store(settings: settings, ledger: options.demo ? nil : .open())
        self.settings = settings
        self.store = store
        tracker = IslandEventTracker(startedAt: store.clock())
        language = settings.settings.language
        write(helloMessage(language: settings.settings.language))

        PermissionRequests.shared.holdTime = TimeInterval(settings.settings.approvalWaitMinutes * 60)
        if options.demo {
            PermissionRequests.shared.seedDemo()
        } else {
            if let executable = options.executable {
                SessionObservers.configure(executable: executable, enabled: settings.settings.clientHooks)
            }
            PermissionRequests.shared.start()
            deepseekQuestions.setEnabled(settings.settings.clientHooks)
        }
        observe()
        store.start()
        sendState()
    }

    /// Re-arms after each change of anything the state shows, and of the settings the engine itself acts on.
    private func observe() {
        guard let store, let settings, !stopped else { return }
        withObservationTracking {
            _ = store.view
            _ = store.isPaused
            _ = settings.settings
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.settingsChanged()
                self.scheduleState()
                self.observe()
            }
        }
    }

    private func settingsChanged() {
        guard let settings else { return }
        PermissionRequests.shared.holdTime = TimeInterval(settings.settings.approvalWaitMinutes * 60)
        if settings.settings.language != language {
            language = settings.settings.language
            L10n.setLanguage(settings.settings.language)
            write(helloMessage(language: settings.settings.language))
            Task { await self.store?.refresh() }
        }
        if !options.demo {
            if let executable = options.executable {
                SessionObservers.configure(executable: executable, enabled: settings.settings.clientHooks)
            }
            deepseekQuestions.setEnabled(settings.settings.clientHooks)
        }
    }

    /// At most one state per 100 ms, however many changes come in between.
    private func scheduleState() {
        guard !stateScheduled, !stopped else { return }
        stateScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self else { return }
            self.stateScheduled = false
            self.sendState()
        }
    }

    private func sendState() {
        guard let store, let settings, !stopped else { return }
        let view = store.view
        do {
            write(try ShellProtocol.state(view: view, generatedAt: store.report?.generatedAt, settings: settings.settings,
                                          paused: store.isPaused, error: store.lastError,
                                          approvals: PermissionRequests.shared.pending))
        } catch {
            write(ShellProtocol.error("state: \(error)"))
        }
        // As on macOS, a paused store or a failed pass presents nothing; the baselines wait for the next good report.
        guard !store.isPaused, store.lastError == nil, let report = store.report else { return }
        let now = store.clock()
        let update = tracker.update(report: report, agents: settings.agents, now: now, settings: settings.settings)
        for event in ShellProtocol.events(update, now: now) { write(event) }
    }

    private func helloMessage(language _: AppLanguage) -> JSONValue {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return ShellProtocol.hello(engineVersion: version, demo: options.demo,
                                   language: L10n.resolved == .zhHans ? "zh" : "en", strings: ShellStrings.current)
    }

    private func write(_ message: JSONValue) {
        guard let line = try? ShellProtocol.line(message) else { return }
        send(line)
    }

    /// Lets every waiting approval go back to its client, stops collecting and ends with `status`.
    private func end(_ status: Int32) {
        guard !stopped else { return }
        stopped = true
        deepseekQuestions.stop()
        if !options.demo { PermissionRequests.shared.stop() }
        store?.stop()
        instanceLock = nil
        finish(status)
    }
}
#endif
