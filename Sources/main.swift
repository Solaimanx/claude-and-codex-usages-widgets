import AppKit

private struct UsageWindow {
    let usedPercent: Int
    let resetsAt: Date
}

private enum UsageReadError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

private struct WidgetTheme {
    let id: String
    let name: String
    let background: NSColor
    let border: NSColor
    let primaryText: NSColor
    let secondaryText: NSColor
    let accent: NSColor
    let dark: Bool

    static let all: [WidgetTheme] = [
        WidgetTheme(id: "classic", name: "Classic (black)", background: NSColor(srgbRed: 0.025, green: 0.03, blue: 0.04, alpha: 0.98), border: NSColor(white: 0.24, alpha: 0.55), primaryText: .white, secondaryText: NSColor(white: 0.6, alpha: 1), accent: .systemTeal, dark: true),
        WidgetTheme(id: "light", name: "Light", background: NSColor(white: 0.97, alpha: 0.98), border: NSColor(white: 0.75, alpha: 0.6), primaryText: .black, secondaryText: NSColor(white: 0.4, alpha: 1), accent: NSColor(srgbRed: 0.0, green: 0.45, blue: 0.55, alpha: 1), dark: false),
        WidgetTheme(id: "midnight", name: "Midnight blue", background: NSColor(srgbRed: 0.05, green: 0.08, blue: 0.2, alpha: 0.98), border: NSColor(srgbRed: 0.25, green: 0.3, blue: 0.5, alpha: 0.6), primaryText: .white, secondaryText: NSColor(srgbRed: 0.65, green: 0.7, blue: 0.85, alpha: 1), accent: NSColor(srgbRed: 0.45, green: 0.7, blue: 1, alpha: 1), dark: true),
        WidgetTheme(id: "forest", name: "Forest", background: NSColor(srgbRed: 0.04, green: 0.13, blue: 0.08, alpha: 0.98), border: NSColor(srgbRed: 0.2, green: 0.35, blue: 0.25, alpha: 0.6), primaryText: .white, secondaryText: NSColor(srgbRed: 0.6, green: 0.75, blue: 0.65, alpha: 1), accent: NSColor(srgbRed: 0.45, green: 0.9, blue: 0.55, alpha: 1), dark: true),
        WidgetTheme(id: "sunset", name: "Sunset", background: NSColor(srgbRed: 0.2, green: 0.06, blue: 0.08, alpha: 0.98), border: NSColor(srgbRed: 0.45, green: 0.2, blue: 0.2, alpha: 0.6), primaryText: .white, secondaryText: NSColor(srgbRed: 0.85, green: 0.65, blue: 0.6, alpha: 1), accent: NSColor(srgbRed: 1, green: 0.65, blue: 0.3, alpha: 1), dark: true),
    ]
    static func named(_ id: String?) -> WidgetTheme { all.first { $0.id == id } ?? all[0] }
}

@MainActor
final class AIUsageMeterAppDelegate: NSObject, NSApplicationDelegate {
    private var codexFiveHour: UsageWindow?
    private var codexWeekly: UsageWindow?
    private var claudeFiveHour: UsageWindow?
    private var claudeWeekly: UsageWindow?
    private var snapshotUpdated: Date?
    private var claudeStatus = "Connecting…"
    private var refreshMessage = "Checking usage…"
    private var isRefreshing = false

    private var statusItem: NSStatusItem!
    private var updateItem: NSMenuItem!
    private var refreshActionItem: NSMenuItem!
    private var widgetVisibilityItem: NSMenuItem!
    private var claudeConnectItem: NSMenuItem!
    private var timer: Timer?
    private var tickTimer: Timer?
    private var widgetPanel: NSPanel!
    private var codexFiveHourTime: NSTextField!
    private var codexFiveHourPercent: NSTextField!
    private var codexWeeklyTime: NSTextField!
    private var codexWeeklyPercent: NSTextField!
    private var claudeFiveHourTime: NSTextField!
    private var claudeFiveHourPercent: NSTextField!
    private var claudeWeeklyTime: NSTextField!
    private var claudeWeeklyPercent: NSTextField!
    private var widgetUpdatedLabel: NSTextField!
    private var widgetBackground: NSView!
    private var codexSectionView: NSView!
    private var claudeSectionView: NSView!
    private var sectionSeparator: NSBox!
    private var headingLabels: [NSTextField] = []
    private var subheadingLabels: [NSTextField] = []
    private var showCodexItem: NSMenuItem!
    private var showClaudeItem: NSMenuItem!
    private var themeItems: [NSMenuItem] = []
    private let defaults = UserDefaults.standard
    private var showCodex: Bool { defaults.object(forKey: "showCodex") as? Bool ?? true }
    private var showClaude: Bool { defaults.object(forKey: "showClaude") as? Bool ?? true }
    private var theme: WidgetTheme { WidgetTheme.named(defaults.string(forKey: "theme")) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let menu = NSMenu()
        let heading = NSMenuItem(title: "AI Usage Meter", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        widgetVisibilityItem = NSMenuItem(title: "Hide floating widget", action: #selector(toggleFloatingWidget(_:)), keyEquivalent: "w")
        widgetVisibilityItem.target = self
        menu.addItem(widgetVisibilityItem)
        refreshActionItem = NSMenuItem(title: "↻  Check for latest usage", action: #selector(refreshNow(_:)), keyEquivalent: "r")
        refreshActionItem.target = self
        menu.addItem(refreshActionItem)
        claudeConnectItem = NSMenuItem(title: "Connect Claude usage…", action: #selector(requestClaudeAccess(_:)), keyEquivalent: "")
        claudeConnectItem.target = self
        menu.addItem(claudeConnectItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settings = NSMenu()
        showCodexItem = NSMenuItem(title: "Show Codex", action: #selector(toggleCodex(_:)), keyEquivalent: "")
        showCodexItem.target = self
        settings.addItem(showCodexItem)
        showClaudeItem = NSMenuItem(title: "Show Claude Code", action: #selector(toggleClaude(_:)), keyEquivalent: "")
        showClaudeItem.target = self
        settings.addItem(showClaudeItem)
        settings.addItem(.separator())
        let themeHeading = NSMenuItem(title: "Widget colour", action: nil, keyEquivalent: "")
        themeHeading.isEnabled = false
        settings.addItem(themeHeading)
        for t in WidgetTheme.all {
            let item = NSMenuItem(title: t.name, action: #selector(chooseTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = t.id
            settings.addItem(item)
            themeItems.append(item)
        }
        settingsItem.submenu = settings
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        updateItem = NSMenuItem(title: refreshMessage, action: nil, keyEquivalent: "")
        updateItem.isEnabled = false
        menu.addItem(updateItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        statusItem.button?.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "AI Usage Meter")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.toolTip = "AI Usage Meter · refreshes every 5 minutes"

        createFloatingWidget()
        tickTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer = Timer.scheduledTimer(timeInterval: 300, target: self, selector: #selector(periodicRefresh(_:)), userInfo: nil, repeats: true)
        showFloatingWidget()
        refreshUsage()
    }

    private func createFloatingWidget() {
        let panelSize = NSSize(width: 200, height: 360)
        widgetPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        widgetPanel.isFloatingPanel = true
        widgetPanel.level = .floating
        widgetPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        widgetPanel.isOpaque = false
        widgetPanel.backgroundColor = .clear
        widgetPanel.appearance = NSAppearance(named: .darkAqua)
        widgetPanel.hasShadow = true
        widgetPanel.isMovableByWindowBackground = true
        widgetPanel.becomesKeyOnlyIfNeeded = true

        let background = NSView(frame: NSRect(origin: .zero, size: panelSize))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(srgbRed: 0.025, green: 0.03, blue: 0.04, alpha: 0.98).cgColor
        background.layer?.cornerRadius = 27
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor(white: 0.24, alpha: 0.55).cgColor
        background.layer?.masksToBounds = true
        widgetPanel.contentView = background
        widgetBackground = background

        codexFiveHourTime = makeWidgetValue()
        codexFiveHourPercent = makeWidgetPercent()
        codexWeeklyTime = makeWidgetValue(secondary: true)
        codexWeeklyPercent = makeWidgetPercent(secondary: true)
        claudeFiveHourTime = makeWidgetValue()
        claudeFiveHourPercent = makeWidgetPercent()
        claudeWeeklyTime = makeWidgetValue(secondary: true)
        claudeWeeklyPercent = makeWidgetPercent(secondary: true)
        widgetUpdatedLabel = NSTextField(labelWithString: "Checking usage…")
        widgetUpdatedLabel.font = .systemFont(ofSize: 8, weight: .regular)
        widgetUpdatedLabel.textColor = NSColor(white: 0.5, alpha: 1)

        let codexSection = makeProviderSection(
            title: "CODEX",
            fiveHourTime: codexFiveHourTime,
            fiveHourPercent: codexFiveHourPercent,
            weeklyTime: codexWeeklyTime,
            weeklyPercent: codexWeeklyPercent
        )
        let claudeSection = makeProviderSection(
            title: "CLAUDE CODE",
            fiveHourTime: claudeFiveHourTime,
            fiveHourPercent: claudeFiveHourPercent,
            weeklyTime: claudeWeeklyTime,
            weeklyPercent: claudeWeeklyPercent
        )
        let separator = NSBox()
        separator.boxType = .separator
        codexSectionView = codexSection
        claudeSectionView = claudeSection
        sectionSeparator = separator
        let stack = NSStackView(views: [codexSection, separator, claudeSection, widgetUpdatedLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10),
            codexSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            claudeSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            widgetUpdatedLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        applySettings()
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            widgetPanel.setFrameOrigin(NSPoint(x: visible.maxX - panelSize.width - 20, y: visible.maxY - panelSize.height - 18))
        } else {
            widgetPanel.setFrameOrigin(NSPoint(x: 700, y: 700))
        }
    }

    private func makeProviderSection(title: String, fiveHourTime: NSTextField, fiveHourPercent: NSTextField, weeklyTime: NSTextField, weeklyPercent: NSTextField) -> NSStackView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 9, weight: .bold)
        heading.textColor = NSColor(white: 0.58, alpha: 1)
        headingLabels.append(heading)
        let fiveHour = makeWidgetSection(title: "5-HOUR RESET", time: fiveHourTime, percent: fiveHourPercent)
        let weekly = makeWidgetSection(title: "WEEKLY RESET", time: weeklyTime, percent: weeklyPercent, isSecondary: true)
        let section = NSStackView(views: [heading, fiveHour, weekly])
        section.orientation = .vertical
        section.alignment = .leading
        section.distribution = .fill
        section.spacing = 2
        for view in [heading, fiveHour, weekly] { view.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true }
        return section
    }

    private func makeWidgetSection(title: String, time: NSTextField, percent: NSTextField, isSecondary: Bool = false) -> NSStackView {
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: isSecondary ? 7 : 9, weight: .bold)
        name.textColor = NSColor(white: 0.64, alpha: 1)
        subheadingLabels.append(name)
        percent.font = .systemFont(ofSize: isSecondary ? 13 : 24, weight: .semibold)
        percent.textColor = .white
        time.font = .systemFont(ofSize: isSecondary ? 9 : 12, weight: .medium)
        time.textColor = .systemTeal
        let section = NSStackView(views: [name, percent, time])
        section.orientation = .vertical
        section.alignment = .leading
        section.distribution = .fill
        section.spacing = 0
        name.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        time.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        percent.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    private func makeWidgetValue(secondary: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: "Checking…")
        label.font = .systemFont(ofSize: secondary ? 10 : 18, weight: .semibold)
        label.textColor = .systemTeal
        label.alignment = .left
        return label
    }

    private func makeWidgetPercent(secondary: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: "—")
        label.font = .systemFont(ofSize: secondary ? 13 : 24, weight: .semibold)
        label.textColor = .white
        label.alignment = .left
        return label
    }

    @objc private func toggleFloatingWidget(_ sender: Any?) {
        if widgetPanel.isVisible {
            hideFloatingWidget(sender)
        } else {
            showFloatingWidget()
        }
    }

    @objc private func hideFloatingWidget(_ sender: Any?) {
        widgetPanel.orderOut(sender)
        widgetVisibilityItem.title = "Show floating widget"
    }

    private func showFloatingWidget() {
        widgetPanel.orderFrontRegardless()
        widgetVisibilityItem.title = "Hide floating widget"
    }

    @objc private func toggleCodex(_ sender: Any?) {
        // Never allow both sections to be hidden.
        if showCodex && !showClaude { defaults.set(true, forKey: "showClaude") }
        defaults.set(!showCodex, forKey: "showCodex")
        applySettings()
    }

    @objc private func toggleClaude(_ sender: Any?) {
        if showClaude && !showCodex { defaults.set(true, forKey: "showCodex") }
        defaults.set(!showClaude, forKey: "showClaude")
        applySettings()
    }

    @objc private func chooseTheme(_ sender: NSMenuItem) {
        defaults.set(sender.representedObject as? String, forKey: "theme")
        applySettings()
    }

    private func applySettings() {
        showCodexItem.state = showCodex ? .on : .off
        showClaudeItem.state = showClaude ? .on : .off
        let t = theme
        for item in themeItems { item.state = (item.representedObject as? String) == t.id ? .on : .off }

        codexSectionView.isHidden = !showCodex
        claudeSectionView.isHidden = !showClaude
        sectionSeparator.isHidden = !(showCodex && showClaude)

        widgetPanel.appearance = NSAppearance(named: t.dark ? .darkAqua : .aqua)
        widgetBackground.layer?.backgroundColor = t.background.cgColor
        widgetBackground.layer?.borderColor = t.border.cgColor
        for label in headingLabels + subheadingLabels { label.textColor = t.secondaryText }
        for label in [codexFiveHourPercent, codexWeeklyPercent, claudeFiveHourPercent, claudeWeeklyPercent] { label?.textColor = t.primaryText }
        for label in [codexFiveHourTime, codexWeeklyTime, claudeFiveHourTime, claudeWeeklyTime] { label?.textColor = t.accent }
        widgetUpdatedLabel.textColor = t.secondaryText

        // Resize the panel to fit visible sections, keeping its top edge in place.
        widgetBackground.layoutSubtreeIfNeeded()
        let height = (showCodex && showClaude) ? 360.0 : 190.0
        var frame = widgetPanel.frame
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        widgetPanel.setFrame(frame, display: true)
        widgetBackground.frame = NSRect(origin: .zero, size: frame.size)
    }

    @objc private func refreshNow(_ sender: Any?) {
        refreshUsage()
    }

    @objc private func requestClaudeAccess(_ sender: Any?) {
        claudeStatus = "Connecting…"
        refreshUsage()
    }

    @objc private func periodicRefresh(_ timer: Timer) {
        refreshUsage()
    }

    @objc private func tick() {
        updateLabels()
    }

    private func refreshUsage() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshMessage = "Checking Codex and Claude…"
        refreshActionItem.title = "↻  Checking latest usage…"
        refreshActionItem.isEnabled = false
        updateLabels()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let codex = Self.fetchCodexUsage()
            let claude = Self.fetchClaudeUsage()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                self.snapshotUpdated = Date()
                switch codex {
                case .success(let result):
                    self.codexFiveHour = result.0
                    self.codexWeekly = result.1
                case .failure:
                    self.codexFiveHour = nil
                    self.codexWeekly = nil
                }
                switch claude {
                case .success(let result):
                    self.claudeFiveHour = result.0
                    self.claudeWeekly = result.1
                    self.claudeStatus = "Live Claude usage"
                case .failure(let error):
                    self.claudeFiveHour = nil
                    self.claudeWeekly = nil
                    self.claudeStatus = error.localizedDescription
                }
                self.refreshMessage = "Updated \(self.localTime(self.snapshotUpdated!))"
                self.refreshActionItem.title = "↻  Check for latest usage"
                self.refreshActionItem.isEnabled = true
                self.claudeConnectItem.title = self.claudeStatus == "Live Claude usage" ? "Claude connected · live usage" : "Connect Claude usage…"
                self.updateLabels()
            }
        }
    }

    nonisolated private static func fetchCodexUsage() -> Result<(UsageWindow, UsageWindow), UsageReadError> {
        guard let executable = findCodex() else {
            return .failure(.message("Codex CLI not found"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        var environment = ProcessInfo.processInfo.environment
        let codexDir = (executable as NSString).deletingLastPathComponent
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "\(codexDir):/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do { try process.run() }
        catch { return .failure(.message("Could not start Codex app-server")) }
        defer {
            if process.isRunning { process.terminate() }
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            try? errors.fileHandleForReading.close()
        }

        do {
            try writeJSON(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["clientInfo": ["name": "ai-usage-meter", "version": "1.0"]]], to: input.fileHandleForWriting)
            guard let initialize = readResponse(id: 1, from: output.fileHandleForReading), initialize["error"] == nil else {
                return .failure(.message("Codex did not initialize"))
            }
            try writeJSON(["jsonrpc": "2.0", "method": "initialized", "params": [:]], to: input.fileHandleForWriting)
            try writeJSON(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read", "params": ["excludeResetCreditDetails": true]], to: input.fileHandleForWriting)
            guard let response = readResponse(id: 2, from: output.fileHandleForReading), response["error"] == nil,
                  let result = response["result"] as? [String: Any] else {
                return .failure(.message("Codex usage read failed"))
            }
            let buckets = result["rateLimitsByLimitId"] as? [String: Any]
            let codex = buckets?["codex"] as? [String: Any]
            let legacy = result["rateLimits"] as? [String: Any]
            guard let snapshot = codex ?? legacy,
                  let primary = snapshot["primary"] as? [String: Any],
                  let secondary = snapshot["secondary"] as? [String: Any],
                  let fiveHour = makeWindow(primary), let weekly = makeWindow(secondary) else {
                return .failure(.message("Codex did not return both limits"))
            }
            return .success((fiveHour, weekly))
        } catch {
            return .failure(.message("Could not read Codex usage"))
        }
    }

    nonisolated private static func findCodex() -> String? {
        let fm = FileManager.default
        if let custom = ProcessInfo.processInfo.environment["CODEX_PATH"], fm.isExecutableFile(atPath: custom) { return custom }
        // Ask the user's login shell, which knows about nvm, Homebrew, etc.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lic", "command -v codex"]
        let out = Pipe()
        shell.standardOutput = out
        shell.standardError = Pipe()
        if (try? shell.run()) != nil {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            shell.waitUntilExit()
            if let line = String(data: data, encoding: .utf8)?.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces),
               line.hasPrefix("/"), fm.isExecutableFile(atPath: line) { return line }
        }
        var candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        let nvm = NSHomeDirectory() + "/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvm) {
            candidates += versions.sorted().reversed().map { "\(nvm)/\($0)/bin/codex" }
        }
        return candidates.first(where: { fm.isExecutableFile(atPath: $0) })
    }

    nonisolated private static func fetchClaudeUsage() -> Result<(UsageWindow, UsageWindow), UsageReadError> {
        // Read the Claude Code OAuth token from the login Keychain (written by `claude login`).
        let security = Process()
        security.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        security.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        security.standardOutput = out
        security.standardError = Pipe()
        do { try security.run() } catch { return .failure(.message("Could not read Keychain")) }
        let credData = out.fileHandleForReading.readDataToEndOfFile()
        security.waitUntilExit()
        guard security.terminationStatus == 0,
              let creds = try? JSONSerialization.jsonObject(with: credData) as? [String: Any],
              let oauth = creds["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return .failure(.message("Sign in with `claude` in Terminal first"))
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        var body: Data?
        var status = 0
        URLSession.shared.dataTask(with: request) { data, response, _ in
            body = data
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 20)

        if status == 401 { return .failure(.message("Claude token expired, run `claude` once")) }
        guard status == 200, let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let five = claudeWindow(json["five_hour"]),
              let weekly = claudeWindow(json["seven_day"]) else {
            return .failure(.message("Claude usage read failed (HTTP \(status))"))
        }
        return .success((five, weekly))
    }

    nonisolated private static func claudeWindow(_ raw: Any?) -> UsageWindow? {
        guard let object = raw as? [String: Any],
              let utilization = (object["utilization"] as? NSNumber)?.doubleValue,
              let resetString = object["resets_at"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let reset = formatter.date(from: resetString)
                ?? ISO8601DateFormatter().date(from: resetString) else { return nil }
        let used = Int(utilization.rounded())
        return UsageWindow(usedPercent: min(100, max(0, used)), resetsAt: reset)
    }

    nonisolated private static func makeWindow(_ object: [String: Any]) -> UsageWindow? {
        guard let used = object["usedPercent"] as? Int,
              let reset = object["resetsAt"] as? Double else { return nil }
        return UsageWindow(usedPercent: min(100, max(0, used)), resetsAt: Date(timeIntervalSince1970: reset))
    }

    nonisolated private static func writeJSON(_ value: [String: Any], to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        handle.write(data)
        handle.write(Data([0x0A]))
    }

    nonisolated private static func readResponse(id: Int, from handle: FileHandle) -> [String: Any]? {
        var buffer = Data()
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let byte = handle.readData(ofLength: 1)
            if byte.isEmpty { return nil }
            if byte[0] == 0x0A {
                guard let json = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any] else {
                    buffer.removeAll()
                    continue
                }
                if (json["id"] as? Int) == id { return json }
                buffer.removeAll()
            } else { buffer.append(byte[0]) }
        }
        return nil
    }

    private static func updateSection(time: NSTextField, percent: NSTextField, window: UsageWindow?, isRefreshing: Bool, isSecondary: Bool) {
        guard let window else {
            percent.stringValue = isRefreshing ? "Checking…" : "Unavailable"
            time.stringValue = ""
            return
        }
        percent.stringValue = "\(100 - window.usedPercent)% left"
        time.stringValue = "\(Self.compactTimeLeft(window.resetsAt)) left"
    }

    private func updateLabels() {
        Self.updateSection(time: codexFiveHourTime, percent: codexFiveHourPercent, window: codexFiveHour, isRefreshing: isRefreshing, isSecondary: false)
        Self.updateSection(time: codexWeeklyTime, percent: codexWeeklyPercent, window: codexWeekly, isRefreshing: isRefreshing, isSecondary: true)
        Self.updateSection(time: claudeFiveHourTime, percent: claudeFiveHourPercent, window: claudeFiveHour, isRefreshing: isRefreshing, isSecondary: false)
        Self.updateSection(time: claudeWeeklyTime, percent: claudeWeeklyPercent, window: claudeWeekly, isRefreshing: isRefreshing, isSecondary: true)
        if let codexFiveHour {
            statusItem.button?.title = Self.compactTimeLeft(codexFiveHour.resetsAt)
        } else {
            statusItem.button?.title = "AI usage"
        }
        updateItem.title = "\(refreshMessage) · Claude: \(claudeStatus)"
        widgetUpdatedLabel.stringValue = snapshotUpdated.map { "Updated \(localTime($0))" } ?? refreshMessage
    }

    nonisolated private static func compactTimeLeft(_ date: Date) -> String {
        var seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds == 0 { return "Reset due" }
        let days = seconds / 86_400
        seconds %= 86_400
        let hours = seconds / 3_600
        seconds %= 3_600
        let minutes = seconds / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    private func localTime(_ date: Date) -> String {
        let formatter = DateFormatter()
                formatter.timeZone = .current
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

@main
struct AIUsageMeterMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AIUsageMeterAppDelegate()
        application.delegate = appDelegate
        application.run()
    }
}
