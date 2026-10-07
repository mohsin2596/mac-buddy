import Foundation
import SwiftUI

struct SessionEvent: Decodable {
    let event: String
    let tool: String?
    let target: String?
    let desc: String?
    let cwd: String?
}

enum Mood: String, CaseIterable, Hashable {
    case idle, working, attention, done, sleeping
}

enum ReactionKind: CaseIterable {
    case spin, backflip, boing, wave, giggle, dizzy

    var duration: Double {
        switch self {
        case .spin: 1.2
        case .backflip: 1.1
        case .boing: 1.1
        case .wave: 1.5
        case .giggle: 1.3
        case .dizzy: 2.0
        }
    }

    /// A different tap reaction than last time; dizzy is saved for rapid-fire clicking.
    static func random(excluding last: ReactionKind?) -> ReactionKind {
        allCases.filter { $0 != .dizzy && $0 != last }.randomElement() ?? .spin
    }
}

struct Reaction {
    let kind: ReactionKind
    let elapsed: Double
}

@MainActor
final class BuddyModel: ObservableObject {
    @Published private(set) var mood: Mood = .idle
    /// Projects Claude is working in right now, most recent first.
    @Published private(set) var projects: [String] = []

    /// Pupil offset toward the cursor, updated by the app delegate.
    var cursorLook = CGSize.zero

    private let settings: BuddySettings
    private var phrase: String?
    private var phraseUntil = Date.distantPast
    private var reactionStart = Date.distantPast
    private var reactionKind = ReactionKind.spin
    private var clickTimes: [Date] = []

    private var lastActivity = Date()
    private var newestStopSeen = Date.distantPast
    private var doneUntil = Date.distantPast

    private let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".mac-buddy/sessions")

    init(settings: BuddySettings) {
        self.settings = settings
    }

    /// Reads the per-session state files written by the Claude Code hook.
    func refresh() {
        let now = Date()
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(
            at: sessionsDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let filter = settings.projectFilter.trimmingCharacters(in: .whitespaces)

        var working: [(Date, SessionEvent)] = []
        var waiting = false
        var newestStop = Date.distantPast

        for url in files where url.pathExtension == "json" {
            guard let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate else { continue }
            let age = now.timeIntervalSince(mtime)
            if age > 86_400 {
                try? fm.removeItem(at: url)
                continue
            }
            guard let data = try? Data(contentsOf: url),
                  let ev = try? JSONDecoder().decode(SessionEvent.self, from: data) else { continue }
            if !filter.isEmpty, !(ev.cwd ?? "").localizedCaseInsensitiveContains(filter) { continue }

            lastActivity = max(lastActivity, mtime)

            // Stop doesn't fire when a turn is interrupted, so "working" goes stale after a while.
            let staleAfter: TimeInterval? = switch ev.event {
            case "PreToolUse": 900
            case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure": 300
            default: nil
            }
            if let staleAfter, age < staleAfter {
                working.append((mtime, ev))
            } else if ev.event == "PermissionRequest", age < 900 {
                waiting = true
            } else if ev.event == "Stop" {
                newestStop = max(newestStop, mtime)
            }
        }

        if newestStop > newestStopSeen {
            if settings.celebrate, now.timeIntervalSince(newestStop) < 5 {
                doneUntil = now.addingTimeInterval(3.5)
            }
            newestStopSeen = newestStop
        }

        let newMood: Mood
        if waiting {
            newMood = .attention
        } else if !working.isEmpty {
            newMood = .working
        } else if now < doneUntil {
            newMood = .done
        } else if settings.sleepEnabled, now.timeIntervalSince(lastActivity) > settings.sleepMinutes * 60 {
            newMood = .sleeping
        } else {
            newMood = .idle
        }

        var newProjects: [String] = []
        for (_, ev) in working.sorted(by: { $0.0 > $1.0 }) {
            let name = ((ev.cwd ?? "") as NSString).lastPathComponent
            if !name.isEmpty, !newProjects.contains(name) { newProjects.append(name) }
        }
        if mood != newMood { mood = newMood }
        if projects != newProjects { projects = newProjects }
    }

    /// Called when the buddy is clicked.
    func poke() {
        let now = Date()
        let wasSleeping = mood == .sleeping
        lastActivity = now
        if wasSleeping { mood = .idle }
        guard settings.clickReactions else { return }

        clickTimes = clickTimes.filter { now.timeIntervalSince($0) < 2 } + [now]
        reactionKind = clickTimes.count >= 5 ? .dizzy : .random(excluding: reactionKind)
        reactionStart = now

        let lines: [String]
        if reactionKind == .dizzy {
            lines = ["Whoa, too many boops!", "The room is spinning…", "Okay okay, I'm awake!"]
        } else if wasSleeping {
            lines = ["Huh? I'm up! I'm up!", "Five more minutes…", "*yawn* Hi!"]
        } else if mood == .working {
            lines = ["Shh, Claude's cooking!", "Working on it…", "Almost there, probably!", "Watching every keystroke 👀"]
        } else if mood == .attention {
            lines = ["Claude needs your OK!", "Check the terminal 👉"]
        } else if !settings.phrases.isEmpty {
            lines = settings.phrases
        } else {
            lines = ["Hi there! 👋", "Boop!", "Hehe, that tickles", "Ship it! 🚀", "Need a break? ☕️",
                     "I believe in you!", "*happy wiggle*", "What are we building?"]
        }
        phrase = lines.randomElement()
        phraseUntil = now.addingTimeInterval(2.5)
    }

    func reaction(at date: Date) -> Reaction? {
        let elapsed = date.timeIntervalSince(reactionStart)
        return elapsed < reactionKind.duration ? Reaction(kind: reactionKind, elapsed: elapsed) : nil
    }

    func activePhrase(at date: Date) -> String? {
        date < phraseUntil ? phrase : nil
    }
}
