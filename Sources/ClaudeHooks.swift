import Foundation

/// Connects Mac Buddy to Claude Code.
///
/// Claude Code runs `~/.mac-buddy/hook.sh` on each hook event; that tiny shim forwards the event's JSON
/// to this app's binary (`MacBuddy --hook`), which records the latest event per session in
/// `~/.mac-buddy/sessions/<id>.json` for the running app to poll. No jq, no Swift toolchain needed.
enum ClaudeHooks {
    static let events = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                         "PermissionRequest", "Stop", "SessionStart", "SessionEnd"]

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    static let stateDir = home.appendingPathComponent(".mac-buddy")
    static let sessionsDir = stateDir.appendingPathComponent("sessions")
    static let shimURL = stateDir.appendingPathComponent("hook.sh")
    static let settingsURL = home.appendingPathComponent(".claude/settings.json")
    private static var backupURL: URL { settingsURL.appendingPathExtension("bak-macbuddy") }

    /// The command registered in Claude Code's settings.
    static var command: String { "/bin/sh \"\(shimURL.path)\"" }

    enum HookError: LocalizedError {
        case unreadableSettings

        var errorDescription: String? {
            "Couldn't read \(ClaudeHooks.settingsURL.path). Make sure it's valid JSON, then try again."
        }
    }

    // MARK: Hook mode

    /// Handles one hook event (JSON on stdin). Never prints, never fails loudly: Claude must not be blocked.
    static func handleEvent(_ data: Data) {
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = event["hook_event_name"] as? String else { return }
        let input = event["tool_input"] as? [String: Any] ?? [:]
        let target = ["file_path", "path", "command", "pattern", "url", "query", "description"]
            .lazy.compactMap { input[$0] as? String }.first ?? ""
        let rawID = event["session_id"] as? String ?? "default"
        let sid = String(rawID.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })

        let file = sessionsDir.appendingPathComponent("\(sid).json")
        if name == "SessionEnd" {
            try? FileManager.default.removeItem(at: file)
            return
        }
        let record: [String: String] = [
            "event": name,
            "tool": event["tool_name"] as? String ?? "",
            "target": String(target.prefix(120)),
            "desc": String((input["description"] as? String ?? "").prefix(80)),
            "cwd": event["cwd"] as? String ?? "",
            "sid": sid,
        ]
        guard let out = try? JSONSerialization.data(withJSONObject: record) else { return }
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        try? out.write(to: file, options: .atomic)
    }

    // MARK: Install / uninstall

    static var isConnected: Bool {
        guard let root = try? loadSettings(), let hooks = root["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == command }
            }
        }
    }

    /// Points the shim at this copy of the app. Called on every launch so moving the app doesn't break hooks.
    static func writeShim() throws {
        guard let binary = Bundle.main.executablePath else { return }
        let script = """
        #!/bin/sh
        # Forwards Claude Code hook events to Mac Buddy. Rewritten each time Mac Buddy launches.
        BIN="\(binary)"
        [ -x "$BIN" ] && exec "$BIN" --hook
        cat >/dev/null
        exit 0

        """
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        try script.write(to: shimURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimURL.path)
    }

    /// Adds Mac Buddy's hooks to ~/.claude/settings.json, keeping everything else.
    static func connect() throws {
        try writeShim()
        var root = try loadSettings()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for name in events {
            var groups = hooks[name] as? [[String: Any]] ?? []
            let present = groups.contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == command }
            }
            if !present {
                groups.append(["matcher": "", "hooks": [["type": "command", "command": command, "timeout": 5]]])
            }
            hooks[name] = groups
        }
        root["hooks"] = hooks
        try saveSettings(root)
    }

    /// Removes only Mac Buddy's hooks from ~/.claude/settings.json.
    static func disconnect() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        var root = try loadSettings()
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for (name, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let cleaned = groups.compactMap { group -> [String: Any]? in
                let entries = group["hooks"] as? [[String: Any]] ?? []
                let kept = entries.filter { $0["command"] as? String != command }
                if kept.isEmpty && !entries.isEmpty { return nil }
                var group = group
                group["hooks"] = kept
                return group
            }
            hooks[name] = cleaned.isEmpty ? nil : cleaned
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try saveSettings(root)
    }

    private static func loadSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookError.unreadableSettings
        }
        return root
    }

    private static func saveSettings(_ root: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: settingsURL.path) {
            try? fm.removeItem(at: backupURL)
            try fm.copyItem(at: settingsURL, to: backupURL)
        }
        let data = try JSONSerialization.data(withJSONObject: root,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }
}
