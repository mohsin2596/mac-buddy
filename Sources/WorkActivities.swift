import SwiftUI

// MARK: - What the buddy does while Claude works

enum WorkActivity {
    case typing, coffee, reading, thinking, juggling
}

struct WorkState {
    let activity: WorkActivity
    /// Seconds into the current activity.
    let local: Double
    /// 0 → 1 as the activity starts, back to 0 as it ends, so poses and props ease between activities.
    let presence: Double
}

enum WorkSchedule {
    static let slot = 6.5
    /// Typing is the main job; the rest are little breaks in between.
    static let sequence: [WorkActivity] = [.typing, .coffee, .typing, .reading, .typing, .thinking, .typing, .juggling]

    static func state(at t: Double) -> WorkState {
        let n = floor(t / slot)
        let local = t - n * slot
        let count = Double(sequence.count)
        let index = Int(n - floor(n / count) * count)
        return WorkState(activity: sequence[index], local: local,
                         presence: smoothstep(min(local, slot - local) / 0.45))
    }

    /// How far the mug is raised: two sips per coffee break, with eased lifts.
    static func sip(_ local: Double) -> Double {
        func window(_ a: Double, _ b: Double) -> Double { smoothstep((local - a) / 0.35) * smoothstep((b - local) / 0.35) }
        return max(window(0.7, 2.4), window(3.4, 4.9))
    }

    static let ideaAt = 4.3
}

func smoothstep(_ x: Double) -> Double {
    let c = min(max(x, 0), 1)
    return c * c * (3 - 2 * c)
}

extension CharacterView {
    // MARK: Poses

    func workPose(_ base: Pose, _ w: WorkState) -> Pose {
        var p = base
        p.mouth = .focus
        switch w.activity {
        case .typing:
            let beat = t * 7
            p.lift = abs(sin(beat)) * 4
            p.squash = 1 - 0.035 * abs(cos(beat))
            p.leftArm = -38 + sin(t * 22) * 12
            p.rightArm = 38 + sin(t * 22 + .pi) * 12
            p.leftFoot = max(0, sin(t * 5)) * 3
            p.rightFoot = max(0, -sin(t * 5)) * 3
            p.look = CGSize(width: sin(t * 2.5) * 3.5, height: 3)
        case .coffee:
            let s = WorkSchedule.sip(w.local)
            let ahh = w.local > 2.5 && w.local < 3.3
            p.rightArm = 40 + 44 * s
            p.leftArm = 12
            p.tilt = -7 * s
            p.lift = s > 0.9 ? abs(sin(t * 9)) * 1.5 : 0     // gulp, gulp
            p.look = CGSize(width: 1, height: -2 * s)
            if s > 0.55 { p.eyes = .closed; p.mouth = .oh } else if ahh { p.eyes = .happy; p.mouth = .grin } else { p.mouth = .smile }
        case .reading:
            p.leftArm = -52
            p.rightArm = 52
            p.tilt = 2
            p.look = CGSize(width: sin(t * 1.6) * 3.5, height: 3.5)
            p.mouth = .smile
        case .thinking:
            let idea = w.local > WorkSchedule.ideaAt
            p.leftArm = 10
            if idea {
                let x = w.local - WorkSchedule.ideaAt
                p.rightArm = 150 - 20 * exp(-x * 6)          // finger up: eureka
                p.lift = abs(sin(x * 8)) * 5 * max(0, 1 - x / 1.2)
                p.eyes = .happy
                p.mouth = .grin
                p.look = .zero
            } else {
                p.rightArm = 72 + sin(t * 7) * 5            // hand on chin, tapping
                p.tilt = -3
                p.look = CGSize(width: -3, height: -3)
            }
        case .juggling:
            p.leftArm = 150 + sin(t * 8) * 18
            p.rightArm = -150 + sin(t * 8) * 18
            p.lift = abs(sin(t * 8)) * 2
            p.look = CGSize(width: cos(t * 4) * 3, height: -3)
            p.mouth = .oh
        }
        return p
    }

    func blended(from a: Pose, to b: Pose, by k: Double) -> Pose {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * k }
        var p = k > 0.5 ? b : a
        p.lift = mix(a.lift, b.lift)
        p.squash = mix(a.squash, b.squash)
        p.tilt = mix(a.tilt, b.tilt)
        p.leftArm = mix(a.leftArm, b.leftArm)
        p.rightArm = mix(a.rightArm, b.rightArm)
        p.leftFoot = mix(a.leftFoot, b.leftFoot)
        p.rightFoot = mix(a.rightFoot, b.rightFoot)
        p.look = CGSize(width: mix(a.look.width, b.look.width), height: mix(a.look.height, b.look.height))
        p.antenna = b.antenna
        p.antennaGlow = b.antennaGlow
        return p
    }

    /// Where an arm's hand ends up, in figure coordinates (an arm hangs down at 0°, clockwise is positive).
    func hand(angle: Double, shoulderX: Double) -> CGPoint {
        let r = angle * .pi / 180
        let length = 24.0
        return CGPoint(x: shoulderX - length * sin(r), y: 4 + length * cos(r))
    }

    // MARK: Props (drawn with the body, so they move with it)

    @ViewBuilder
    func workProps(_ w: WorkState, pose p: Pose) -> some View {
        let a = w.presence
        switch w.activity {
        case .typing:
            laptop
                .scaleEffect(0.6 + 0.4 * a, anchor: .bottom)
                .opacity(a)
                .offset(y: 34)
        case .coffee:
            let s = WorkSchedule.sip(w.local)
            let h = hand(angle: p.rightArm, shoulderX: 44)
            mug(steam: 1 - s)
                .rotationEffect(.degrees(-10 - 52 * s))
                .scaleEffect(0.5 + 0.5 * a)
                .opacity(a)
                .offset(x: h.x - 8, y: h.y + 4)
        case .reading:
            book(w)
                .scaleEffect(0.6 + 0.4 * a, anchor: .bottom)
                .opacity(a)
                .offset(y: 24)
        case .thinking:
            if w.local > WorkSchedule.ideaAt {
                let x = w.local - WorkSchedule.ideaAt
                let pop = 1 - exp(-x * 9) * cos(x * 16)
                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.2))
                    .shadow(color: Color(red: 1, green: 0.85, blue: 0.3).opacity(0.9), radius: 8)
                    .scaleEffect(pop)
                    .opacity(a)
                    .offset(x: 22, y: -74)
            }
        case .juggling:
            let colors = [Palette.accent, Color(red: 0.35, green: 0.7, blue: 1), Color(red: 1, green: 0.8, blue: 0.25)]
            let glyphs = ["{}", "</>", "()"]
            ForEach(0..<3, id: \.self) { i in
                let angle = t * 4 + Double(i) * 2 * .pi / 3
                ZStack {
                    Circle().fill(colors[i])
                    Text(glyphs[i])
                        .font(.system(size: 6.5, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .frame(width: 15, height: 15)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                .scaleEffect(a)
                .offset(x: cos(angle) * 34 * a, y: -66 + sin(angle) * 15)
            }
        }
    }

    private func mug(steam: Double) -> some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                let phase = (t * 0.9 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                Capsule()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 2, height: 7)
                    .rotationEffect(.degrees(sin(phase * 6 + Double(i)) * 20))
                    .opacity(sin(phase * .pi) * steam)
                    .offset(x: Double(i) * 5 - 2.5, y: -14 - phase * 12)
            }
            Circle()
                .stroke(Color(white: 0.92), lineWidth: 2.5)
                .frame(width: 8, height: 8)
                .offset(x: 8)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [Color.white, Color(white: 0.84)], startPoint: .top, endPoint: .bottom))
                .frame(width: 15, height: 17)
            Rectangle().fill(style.body.color).frame(width: 15, height: 3).offset(y: 2)
            Capsule().fill(Color(red: 0.42, green: 0.26, blue: 0.16)).frame(width: 11, height: 3).offset(y: -6.5)
        }
    }

    private func book(_ w: WorkState) -> some View {
        let flip = w.local.truncatingRemainder(dividingBy: 2.2) / 0.5
        return ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(style.limb.color)
                .frame(width: 62, height: 34)
            HStack(spacing: 1) { page; page }
                .frame(width: 58, height: 30)
            if flip < 1 {
                // Turning the page: it folds over the spine from right to left.
                page
                    .frame(width: 28.5, height: 30)
                    .scaleEffect(x: cos(flip * .pi), anchor: .leading)
                    .offset(x: 14.75)
            }
        }
    }

    private var page: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color(white: 0.97))
            .overlay(
                VStack(alignment: .leading, spacing: 3.5) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule().fill(Color(white: 0.72)).frame(width: i == 3 ? 10 : 18, height: 1.5)
                    }
                }
            )
    }

    // MARK: Effects (not tied to the body)

    @ViewBuilder
    func workEffects(_ w: WorkState) -> some View {
        switch w.activity {
        case .coffee where WorkSchedule.sip(w.local) > 0.9:
            let phase = (t * 1.4).truncatingRemainder(dividingBy: 1)
            Text("glug")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink.opacity(0.65))
                .opacity(sin(phase * .pi))
                .offset(x: 46 + phase * 6, y: -30 - phase * 18)
        case .thinking where w.local < WorkSchedule.ideaAt:
            ForEach(0..<2, id: \.self) { i in
                let phase = (t * 0.55 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                Text("?")
                    .font(.system(size: 12 + phase * 6, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.7))
                    .opacity(sin(phase * .pi) * w.presence)
                    .offset(x: -30 - Double(i) * 12, y: -48 - phase * 24)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    func reactionEffects(_ reaction: Reaction) -> some View {
        let r = reaction.elapsed
        switch reaction.kind {
        case .backflip where r > 0.85:
            let k = min((r - 0.85) / 0.25, 1)
            ForEach(0..<6, id: \.self) { i in
                let angle = Double(i) / 6 * 2 * .pi
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.2))
                    .opacity(1 - k)
                    .offset(x: cos(angle) * (30 + 30 * k), y: 30 + sin(angle) * (10 + 16 * k))
            }
        case .boing:
            Text("boing!")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Palette.accent)
                .rotationEffect(.degrees(-10 + sin(r * 17) * 6))
                .scaleEffect(min(r / 0.15, 1))
                .opacity(1 - r / reaction.kind.duration)
                .offset(x: 48, y: -44)
        case .giggle:
            ForEach(0..<3, id: \.self) { i in
                let phase = min(max((r - Double(i) * 0.25) / 0.8, 0), 1)
                Text("ha")
                    .font(.system(size: 10 + Double(i) * 2, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.accent)
                    .opacity(sin(phase * .pi))
                    .offset(x: (i % 2 == 0 ? 46 : -46) + phase * (i % 2 == 0 ? 8 : -8), y: -20 - phase * 30)
            }
        case .wave:
            ForEach(0..<2, id: \.self) { i in
                Capsule()
                    .fill(Palette.ink.opacity(0.35))
                    .frame(width: 2, height: 8)
                    .rotationEffect(.degrees(-30 + Double(i) * 30))
                    .opacity(abs(sin(r * 14)))
                    .offset(x: 72 + Double(i) * 6, y: -48 + Double(i) * 4)
            }
        default:
            EmptyView()
        }
    }
}
