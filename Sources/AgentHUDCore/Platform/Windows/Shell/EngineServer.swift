#if os(Windows)
import AgentHUDSupport
import Foundation
import Observation

/// What `agenthud-engine --serve` runs for the Windows shell (PROTOCOL.md, D-041): the part of the macOS
/// `DesktopApplication` that is not a window — the settings and the store, the approval channel, the client hooks and
/// the observers — with what it would draw sent to the shell as protocol messages instead, and what the user does
/// taken back from it. Commands arrive through `receive(_:)`, one line each; lines go out through `send`. Each thing
/// it reacts to is watched on its own, as `DesktopApplication` watches it: a setting acts only when it changes.
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
    private let send: @Sendable (Data, String) -> Void
    private let finish: @MainActor (Int32) -> Void
    private var instanceLock: InstanceLock?
    private(set) var settings: SettingsStore?
    private(set) var store: UsageStore?
    private var tracker = IslandEventTracker()
    private var observedClients: Set<String> = []
    private var stateScheduled = false
    /// The displays the shell draws on (1.4), placed in each state.
    private var displays: [ShellProtocol.Display] = []
    private var started = false
    private var stopped = false
    private let deepseekQuestions = DeepSeekQuestionObserver()

    /// `send` writes one line to the shell, with its message's type (a newer `state` or `hello` may replace one not
    /// yet written); `finish` ends the process with a status, after everything has stopped.
    public init(options: Options, send: @escaping @Sendable (Data, String) -> Void,
                finish: @escaping @MainActor (Int32) -> Void) {
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
        case .displays(let listed):
            displays = listed
            if store != nil { scheduleState() }
        case .sources:
            guard let store else { return write(ShellProtocol.error("no hello yet")) }
            // The demo lists the demo's clients, as its first-launch screen does, never what this machine has installed.
            write(options.demo ? ShellSources.message(sources: DemoData.sources) : ShellSources.message(store: store))
        case .statistics:
            guard let store else { return write(ShellProtocol.error("no hello yet")) }
            write(ShellStatistics.message(store: store))
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

    /// A line over the protocol's limit was dropped unread.
    public func lineTooLong() { write(ShellProtocol.error("line longer than \(ShellProtocol.lineLimit) bytes")) }

    /// The shell's input ended: it quit or went away.
    public func inputEnded() { end(0) }

    private func start() {
        started = true
        // A `lock-held` is said in the language asked for, as everything after it would be.
        if let language = options.language { L10n.setLanguage(language) }
        if !options.demo {
            switch InstanceLock.claim(at: options.lock, executable: options.executable) {
            case .acquired(let lock): instanceLock = lock
            case .held(let holder):
                write(helloMessage())
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
        write(helloMessage())

        // The first start's live-status defaults, as the Desktop's start gives them (DesktopApplication.start): each
        // client's live status on where it is found and supports it, and kept as the user set it afterwards.
        let sources = options.demo ? DemoData.sources : ShellSources.resolve(ShellSources.detect(), report: store.report)
        settings.update { $0.applyLiveStatusDefaults(sources: sources) }

        PermissionRequests.shared.holdTime = TimeInterval(settings.settings.approvalWaitMinutes * 60)
        if options.demo {
            // The macOS demo's requests, then a question and a plan, so the shell's every card can be seen.
            PermissionRequests.shared.showDemo(DemoData.windowsDemoRequests(now: Date()))
        } else {
            if let executable = options.executable { SessionObservers.configure(executable: executable, enabled: settings.settings.clientHooks) }
            observedClients = SessionObservers.observedClients()
            PermissionRequests.shared.start()
            deepseekQuestions.setEnabled(settings.settings.clientHooks)
        }
        watch()
        store.start()
        sendState()
    }

    /// The watches `DesktopApplication.start` sets, each re-armed after every change and acting on its own value only.
    private func watch() {
        guard let store, let settings else { return }
        // What the state shows: the view (report, agents, settings, approvals, waiting sessions, failures, time).
        track({ _ = store.view; _ = store.isPaused }) { [weak self] in self?.scheduleState() }
        track({ settings.settings.approvalWaitMinutes }) {
            PermissionRequests.shared.holdTime = TimeInterval(settings.settings.approvalWaitMinutes * 60)
        }
        track({ settings.settings.language }) { [weak self] in
            guard let self else { return }
            L10n.setLanguage(settings.settings.language)
            self.write(self.helloMessage())
            Task { await self.store?.refresh() }
        }
        track({ settings.settings.clientHooks }) { [weak self] in
            guard let self, !self.options.demo else { return }
            if let executable = self.options.executable { SessionObservers.configure(executable: executable, enabled: settings.settings.clientHooks) }
            self.deepseekQuestions.setEnabled(settings.settings.clientHooks)
        }
        // A client run for the first time creates its directory, and its observer goes in with the next report.
        track({ _ = store.report }) { [weak self] in self?.installObserversForNewClients() }
        // The island's events, on a new report or a change of the agents or of which clients' live status is on.
        track({ _ = store.report; _ = settings.agents; _ = settings.settings.disabledLiveStatusSources }) { [weak self] in
            self?.sendEvents()
        }
    }

    private func installObserversForNewClients() {
        guard !options.demo, let settings else { return }
        let present = SessionObservers.observedClients()
        if settings.settings.clientHooks, !present.subtracting(observedClients).isEmpty { SessionObservers.installObservers() }
        observedClients = present
    }

    /// Calls `onChange` after each change of what `read` reads, re-arming every time.
    private func track(_ read: @escaping @MainActor () -> Void, onChange: @escaping @MainActor () -> Void) {
        guard !stopped else { return }
        withObservationTracking(read) { [weak self] in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                onChange()
                self.track(read, onChange: onChange)
            }
        }
    }

    /// Calls `onChange` only when the value `read` returns changed, as macOS's `trackChanges` does.
    private func track<Value: Equatable>(_ read: @escaping @MainActor () -> Value, onChange: @escaping @MainActor () -> Void) {
        var previous = read()
        track({ _ = read() }) {
            let next = read()
            guard next != previous else { return }
            previous = next
            onChange()
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
        guard let store, !stopped else { return }
        do {
            write(try ShellProtocol.state(store: store, approvals: PermissionRequests.shared.pending, displays: displays))
        } catch {
            write(ShellProtocol.error("state: \(error)"))
        }
    }

    /// As on macOS, a paused store or a failed pass presents nothing; the baselines wait for the next good report.
    private func sendEvents() {
        guard let store, let settings, !stopped, !store.isPaused, store.lastError == nil, let report = store.report else { return }
        let now = store.clock()
        let update = tracker.update(report: report, agents: settings.agents, now: now, settings: settings.settings)
        for event in ShellProtocol.events(update, now: now) { write(event) }
    }

    private func helloMessage() -> JSONValue {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return ShellProtocol.hello(engineVersion: version, demo: options.demo,
                                   language: L10n.resolved == .zhHans ? "zh" : "en", strings: ShellStrings.current)
    }

    private func write(_ message: JSONValue) {
        guard let line = try? ShellProtocol.line(message) else { return }
        send(line, message["type"].stringValue ?? "")
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
