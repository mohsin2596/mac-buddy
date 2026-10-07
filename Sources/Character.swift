import SwiftUI

// MARK: - Layout

enum BuddyLayout {
    /// Unscaled window size; the real window is this times the size setting.
    static let window = CGSize(width: 240, height: 220)
    static let bubbleHeight: CGFloat = 80
    static let character = CGSize(width: 160, height: 140)
    /// Clickable area in unscaled window coordinates (origin bottom-left). The rest lets clicks through.
    static let hitRect = NSRect(x: 68, y: 18, width: 104, height: 116)
    /// Where the eyes sit in unscaled window coordinates (origin bottom-left).
    static let eyeCenter = CGPoint(x: 120, y: 76)
}

enum Palette {
    static let ink = Color(red: 0.18, green: 0.13, blue: 0.12)
    static let cheek = Color(red: 1.0, green: 0.55, blue: 0.6)
    static let accent = Color(red: 0.87, green: 0.49, blue: 0.36)
}

// MARK: - Speech bubble

struct BubbleInfo: Equatable {
    var text: String
    var icon: String?
    var tint: Color = .primary
    var spinner = false
}

struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tail: CGFloat = 6
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tail)
        var p = Path(roundedRect: body, cornerRadius: min(12, body.height / 2), style: .continuous)
        p.move(to: CGPoint(x: rect.midX - 7, y: body.maxY - 0.5))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX + 7, y: body.maxY - 0.5))
        p.closeSubpath()
        return p
    }
}

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

@MainActor
struct TypingDots: View {
    let t: Double
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 5, height: 5)
                    .opacity(0.3 + 0.7 * max(0, sin(t * 6 - Double(i) * 0.9)))
            }
        }
        .foregroundStyle(color)
    }
}

@MainActor
struct BubbleView: View {
    let info: BubbleInfo
    let t: Double
    var accent: Color = Palette.accent

    var body: some View {
        HStack(spacing: 6) {
            if info.spinner { TypingDots(t: t, color: accent) }
            if let icon = info.icon {
                Image(systemName: icon).foregroundStyle(info.tint)
            }
            Text(info.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(Color(white: 0.15))
        .padding(.horizontal, 11)
        .padding(.top, 7)
        .padding(.bottom, 13)
        .background(
            BubbleShape()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
        )
        .frame(maxWidth: BuddyLayout.window.width - 12)
    }
}

// MARK: - Character

enum EyeStyle { case open(Double), happy, closed, dizzy }
enum MouthStyle { case smile, grin, oh, focus, snore }

struct Pose {
    var lift = 0.0
    var squash = 1.0
    var tilt = 0.0
    var spin = 0.0
    /// Rotation around the middle of the body (backflips), unlike `tilt` which pivots on the feet.
    var flip = 0.0
    var shakeX = 0.0
    var leftArm = 15.0
    var rightArm = -15.0
    var leftFoot = 0.0
    var rightFoot = 0.0
    var look = CGSize.zero
    var eyeScale = 1.0
    var eyes = EyeStyle.open(1)
    var mouth = MouthStyle.smile
    var antenna: Color?
    var antennaGlow = 0.0
}

@MainActor
struct CharacterView: View {
    let mood: Mood
    let t: Double
    let reaction: Reaction?
    let style: BuddyStyle

    private var limb: Color { style.limb.color }

    /// What the buddy is busy with while Claude works; nil otherwise (a tap reaction takes over).
    private var work: WorkState? {
        mood == .working && reaction == nil ? WorkSchedule.state(at: t) : nil
    }

    var body: some View {
        let pose = makePose()
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.16))
                .frame(width: 74 * (1 - min(pose.lift, 40) / 80), height: 10)
                .offset(y: 52)

            effectsBehind

            figure(pose)
                .scaleEffect(x: 2 - pose.squash, y: pose.squash, anchor: .bottom)
                .rotation3DEffect(.degrees(pose.spin), axis: (x: 0, y: 1, z: 0))
                .rotationEffect(.degrees(pose.tilt), anchor: .bottom)
                .rotationEffect(.degrees(pose.flip))
                .offset(x: pose.shakeX, y: -pose.lift)

            effectsInFront
        }
        .frame(width: BuddyLayout.character.width, height: BuddyLayout.character.height)
    }

    // MARK: Pose

    private func makePose() -> Pose {
        var p = Pose()
        let breathe = sin(t * 2)
        p.squash = 1 + 0.025 * breathe
        p.leftArm = 15 + 4 * breathe
        p.rightArm = -p.leftArm

        // Glance somewhere new every few seconds.
        let slot = floor(t / 3.1)
        p.look = CGSize(width: cos(slot * 1.7) * 3, height: sin(slot * 2.3) * 1.5)
        let blinking = t.truncatingRemainder(dividingBy: 3.7) < 0.13
        p.eyes = .open(blinking ? 0.1 : 1)

        switch mood {
        case .idle:
            break
        case .working:
            p.antenna = Color(red: 0.3, green: 0.8, blue: 1.0)
            p.antennaGlow = 0.5 + 0.5 * sin(t * 8)
            if let work { p = blended(from: p, to: workPose(p, work), by: work.presence) }
        case .done:
            p.lift = abs(sin(t * 6)) * 14
            p.squash = 1 + 0.05 * sin(t * 12)
            p.leftArm = 150 + sin(t * 12) * 12
            p.rightArm = -150 - sin(t * 12) * 12
            p.eyes = .happy
            p.mouth = .grin
            p.antenna = Color(red: 1.0, green: 0.82, blue: 0.2)
            p.antennaGlow = 1
        case .attention:
            p.shakeX = t.truncatingRemainder(dividingBy: 1.6) < 0.45 ? sin(t * 45) * 2.5 : 0
            p.rightArm = -145 + sin(t * 10) * 25
            p.look = CGSize(width: 0, height: -1)
            p.eyeScale = 1.12
            p.mouth = .oh
            p.antenna = Color(red: 1.0, green: 0.3, blue: 0.3)
            p.antennaGlow = sin(t * 9) > 0 ? 1 : 0.2
        case .sleeping:
            p.squash = 1 + 0.04 * sin(t * 1.2)
            p.tilt = 6
            p.leftArm = 8
            p.rightArm = -8
            p.eyes = .closed
            p.mouth = .snore
        }

        if let look = style.look { p.look = look }

        if let reaction {
            let r = reaction.elapsed
            let k = min(r / reaction.kind.duration, 1)
            switch reaction.kind {
            case .spin:
                let jump = min(r / 0.6, 1)
                p.lift += sin(jump * .pi) * 24
                p.spin = (1 - pow(1 - jump, 3)) * 360
                p.leftArm = 140
                p.rightArm = -140
                p.eyes = .happy
                p.mouth = .grin
            case .backflip:
                let crouch = min(r / 0.18, 1)
                let air = max(0, min((r - 0.18) / 0.7, 1))
                p.squash = air == 0 ? 1 - 0.12 * crouch : 1 + 0.06 * sin(air * .pi)
                p.lift += sin(air * .pi) * 38
                p.flip = -(1 - pow(1 - air, 2.4)) * 360
                p.leftArm = 160 * sin(air * .pi)
                p.rightArm = -160 * sin(air * .pi)
                p.leftFoot = 4 * sin(air * .pi)
                p.rightFoot = p.leftFoot
                p.eyes = air > 0 && air < 1 ? .closed : .happy
                p.mouth = .grin
            case .boing:
                // Squashed flat, then a wobbling spring back.
                let spring = exp(-r * 3.6) * cos(r * 17)
                p.squash = 1 - 0.28 * spring
                p.lift += max(0, -spring) * 10
                p.leftArm = 15 + 40 * max(0, spring)
                p.rightArm = -p.leftArm
                p.eyes = spring > 0.4 ? .closed : .open(1)
                p.eyeScale = 1 + 0.15 * max(0, -spring)
                p.mouth = spring > 0.4 ? .oh : .grin
            case .wave:
                p.rightArm = -150 + sin(r * 14) * 26
                p.tilt = sin(r * 7) * 4
                p.lift += abs(sin(r * 7)) * 3
                p.look = CGSize(width: 2, height: 0)
                p.eyes = .happy
                p.mouth = .grin
            case .giggle:
                p.shakeX = sin(r * 42) * 2.4 * (1 - k)
                p.squash = 1 + 0.04 * sin(r * 30)
                p.leftArm = -35 + sin(r * 30) * 6
                p.rightArm = 35 - sin(r * 30) * 6
                p.eyes = .happy
                p.mouth = .grin
            case .dizzy:
                p.tilt = sin(r * 14) * 12 * (1 - r / 2)
                p.eyes = .dizzy
                p.mouth = .oh
            }
        }
        return p
    }

    // MARK: Figure

    private func figure(_ p: Pose) -> some View {
        let radius = min(style.roundness, 41)
        return ZStack {
            if style.antenna {
                antenna(p)
            }

            foot.offset(x: -20, y: 41 - p.leftFoot)
            foot.offset(x: 20, y: 41 - p.rightFoot)

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [style.bodyLight, style.body.color],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 92, height: 82)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(limb.opacity(0.35), lineWidth: 1.5)
                )

            face(p)

            accessory

            arm(angle: p.leftArm).offset(x: -44, y: 4)
            arm(angle: p.rightArm).offset(x: 44, y: 4)

            if let work { workProps(work, pose: p) }
        }
    }

    private func antenna(_ p: Pose) -> some View {
        let bulb = p.antenna ?? limb
        return ZStack(alignment: .top) {
            Capsule().fill(limb).frame(width: 3, height: 16).offset(y: 6)
            Circle()
                .fill(bulb)
                .frame(width: 9, height: 9)
                .shadow(color: bulb.opacity(p.antennaGlow), radius: 6)
        }
        .frame(width: 10, height: 24, alignment: .top)
        .rotationEffect(.degrees(sin(t * 3) * 10), anchor: .bottom)
        .offset(y: -50)
    }

    private func face(_ p: Pose) -> some View {
        ZStack {
            eye(p).offset(x: -17, y: -6)
            eye(p).offset(x: 17, y: -6)
            if style.cheeks {
                Ellipse().fill(Palette.cheek.opacity(0.45)).frame(width: 12, height: 7).offset(x: -30, y: 9)
                Ellipse().fill(Palette.cheek.opacity(0.45)).frame(width: 12, height: 7).offset(x: 30, y: 9)
            }
            mouth(p.mouth).offset(y: 15)
            if style.accessory == .glasses {
                Circle().stroke(Palette.ink, lineWidth: 2.5).frame(width: 25, height: 25).offset(x: -17, y: -6)
                Circle().stroke(Palette.ink, lineWidth: 2.5).frame(width: 25, height: 25).offset(x: 17, y: -6)
                Capsule().fill(Palette.ink).frame(width: 9, height: 2.5).offset(y: -9)
            }
        }
    }

    private var foot: some View {
        Capsule().fill(limb).frame(width: 24, height: 12)
    }

    private func arm(angle: Double) -> some View {
        Capsule()
            .fill(limb)
            .frame(width: 13, height: 28)
            .offset(y: 11)
            .rotationEffect(.degrees(angle))
    }

    @ViewBuilder
    private func eye(_ p: Pose) -> some View {
        switch p.eyes {
        case .open(let openness):
            let pupil = 10 * style.pupilScale
            ZStack {
                Ellipse().fill(Color.white).frame(width: 18, height: 22)
                Circle().fill(Palette.ink).frame(width: pupil, height: pupil)
                    .offset(x: p.look.width, y: p.look.height + 2)
                Circle().fill(Color.white).frame(width: pupil * 0.35, height: pupil * 0.35)
                    .offset(x: p.look.width + pupil * 0.2, y: p.look.height + 2 - pupil * 0.3)
            }
            .scaleEffect(x: p.eyeScale, y: p.eyeScale * openness)
        case .happy:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 8))
                path.addQuadCurve(to: CGPoint(x: 16, y: 8), control: CGPoint(x: 8, y: -4))
            }
            .stroke(Palette.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 16, height: 10)
        case .closed:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 2))
                path.addQuadCurve(to: CGPoint(x: 16, y: 2), control: CGPoint(x: 8, y: 9))
            }
            .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 16, height: 8)
        case .dizzy:
            Text("@")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink)
                .rotationEffect(.degrees(t * 400))
        }
    }

    @ViewBuilder
    private func mouth(_ style: MouthStyle) -> some View {
        switch style {
        case .smile:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: 12, y: 0), control: CGPoint(x: 6, y: 7))
            }
            .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 12, height: 5)
        case .grin:
            ZStack(alignment: .bottom) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addQuadCurve(to: CGPoint(x: 18, y: 0), control: CGPoint(x: 9, y: 20))
                    path.closeSubpath()
                }
                .fill(Palette.ink)
                Ellipse().fill(Palette.cheek).frame(width: 8, height: 4).offset(y: -1.5)
            }
            .frame(width: 18, height: 10)
            .offset(y: 2)
        case .oh:
            Ellipse().fill(Palette.ink).frame(width: 8, height: 10)
        case .focus:
            ZStack {
                Capsule().fill(Palette.ink).frame(width: 10, height: 2.5)
                Circle().fill(Palette.cheek).frame(width: 5, height: 5).offset(x: 4, y: 2.5)
            }
        case .snore:
            Ellipse().fill(Palette.ink).frame(width: 5 + 2 * sin(t * 1.2), height: 5 + 2 * sin(t * 1.2))
        }
    }

    @ViewBuilder
    private var accessory: some View {
        let hatInk = Color(white: 0.16)
        switch style.accessory {
        case .none, .glasses:
            EmptyView()
        case .partyHat:
            ZStack(alignment: .top) {
                TriangleShape()
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.45, blue: 0.7), Color(red: 0.55, green: 0.4, blue: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 30, height: 34)
                Circle().fill(Color.white.opacity(0.85)).frame(width: 4, height: 4).offset(x: -3, y: 16)
                Circle().fill(Color.white.opacity(0.85)).frame(width: 4, height: 4).offset(x: 5, y: 25)
                Circle().fill(Color(red: 1, green: 0.85, blue: 0.25)).frame(width: 10, height: 10).offset(y: -5)
            }
            .frame(width: 30, height: 34)
            .rotationEffect(.degrees(-14))
            .offset(x: 14, y: -54)
        case .topHat:
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(hatInk).frame(width: 34, height: 30).offset(y: -57)
                Rectangle().fill(Color(red: 0.85, green: 0.2, blue: 0.25)).frame(width: 34, height: 6).offset(y: -47)
                Capsule().fill(hatInk).frame(width: 56, height: 8).offset(y: -41)
            }
            .rotationEffect(.degrees(-6))
        case .crown:
            Image(systemName: "crown.fill")
                .font(.system(size: 30))
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.87, blue: 0.3), Color(red: 0.95, green: 0.6, blue: 0.1)],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                .offset(y: -52)
        case .bow:
            let pink = Color(red: 1, green: 0.4, blue: 0.6)
            ZStack {
                Ellipse().fill(pink).frame(width: 17, height: 12).rotationEffect(.degrees(20)).offset(x: -8)
                Ellipse().fill(pink).frame(width: 17, height: 12).rotationEffect(.degrees(-20)).offset(x: 8)
                Circle().fill(Color(red: 0.85, green: 0.25, blue: 0.45)).frame(width: 8, height: 8)
            }
            .rotationEffect(.degrees(15))
            .offset(x: 26, y: -38)
        case .flower:
            ZStack {
                ForEach(0..<5, id: \.self) { i in
                    let a = Double(i) / 5 * 2 * .pi
                    Circle().fill(Color.white).frame(width: 10, height: 10)
                        .offset(x: cos(a) * 6, y: sin(a) * 6)
                }
                Circle().fill(Color(red: 1, green: 0.8, blue: 0.2)).frame(width: 8, height: 8)
            }
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            .rotationEffect(.degrees(t * 10))
            .offset(x: -26, y: -37)
        case .headphones:
            ZStack {
                Circle().trim(from: 0.5, to: 1)
                    .stroke(hatInk, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 104, height: 104)
                    .offset(y: 6)
                RoundedRectangle(cornerRadius: 6).fill(hatInk).frame(width: 14, height: 26).offset(x: -50, y: 4)
                RoundedRectangle(cornerRadius: 6).fill(hatInk).frame(width: 14, height: 26).offset(x: 50, y: 4)
                Circle().fill(Palette.accent).frame(width: 5, height: 5).offset(x: -50, y: 4)
                Circle().fill(Palette.accent).frame(width: 5, height: 5).offset(x: 50, y: 4)
            }
        }
    }

    var laptop: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.88), Color(white: 0.74)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 56, height: 34)
                .overlay(
                    Image(systemName: "asterisk")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(style.body.color)
                        .rotationEffect(.degrees(t * 90))
                )
            Capsule().fill(Color(white: 0.62)).frame(width: 68, height: 5)
        }
    }

    // MARK: Effects

    @ViewBuilder
    private var effectsBehind: some View {
        if mood == .done {
            ForEach(0..<5, id: \.self) { i in
                let angle = Double(i) / 5 * 2 * .pi + t * 0.8
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.2))
                    .scaleEffect(0.5 + 0.6 * abs(sin(t * 4 + Double(i))))
                    .offset(x: cos(angle) * 66, y: sin(angle) * 44 - 8)
            }
        }
    }

    @ViewBuilder
    private var effectsInFront: some View {
        if let work { workEffects(work) }
        if let work, work.activity == .typing {
            let glyphs = ["{ }", "</>", "01", "fn", "=>"]
            ForEach(0..<3, id: \.self) { i in
                let phase = (t * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let slot = Int(floor(t * 0.6 + Double(i) / 3))
                Text(glyphs[(slot + i * 2) % glyphs.count])
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.3, green: 0.75, blue: 1.0))
                    .opacity(sin(phase * .pi) * work.presence)
                    .offset(x: (i == 1 ? 48 : -48) + sin(phase * 6) * 4, y: 20 - phase * 70)
            }
        }
        if mood == .sleeping {
            ForEach(0..<3, id: \.self) { i in
                let phase = (t * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: 10 + phase * 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.5, green: 0.6, blue: 0.95))
                    .opacity(sin(phase * .pi))
                    .offset(x: 30 + phase * 30, y: -40 - phase * 30)
            }
        }
        if let reaction { reactionEffects(reaction) }
        if let reaction, reaction.kind == .spin {
            ForEach(0..<3, id: \.self) { i in
                let r = reaction.elapsed / 1.2
                Image(systemName: "heart.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.55))
                    .opacity(1 - r)
                    .scaleEffect(0.6 + r)
                    .offset(x: Double(i - 1) * 28, y: -50 - r * 50 - Double(i % 2) * 10)
            }
        }
    }
}

// MARK: - Buddy (bubble + character)

/// The bubble-over-character stack at unscaled size. Shared by the desktop window and the settings preview.
@MainActor
struct BuddyStack: View {
    let bubble: BubbleInfo?
    let mood: Mood
    let t: Double
    let reaction: Reaction?
    let style: BuddyStyle

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if let bubble {
                    BubbleView(info: bubble, t: t, accent: style.body.color)
                        .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: BuddyLayout.window.width, height: BuddyLayout.bubbleHeight, alignment: .bottom)
            .animation(.spring(duration: 0.3, bounce: 0.4), value: bubble)

            CharacterView(mood: mood, t: t, reaction: reaction, style: style)
        }
        .frame(width: BuddyLayout.window.width, height: BuddyLayout.window.height, alignment: .bottom)
    }

    static func bubble(for mood: Mood, projects: [String], settings: BuddySettings) -> BubbleInfo? {
        guard settings.showBubble else { return nil }
        switch mood {
        case .attention:
            return BubbleInfo(text: "Claude needs your OK!", icon: "exclamationmark.circle.fill", tint: .red)
        case .working:
            guard settings.showProject, let first = projects.first else { return BubbleInfo(text: "Working…", spinner: true) }
            var text = first
            if projects.count > 1 { text += " + \(projects[1])" }
            if projects.count > 2 { text += " +\(projects.count - 2)" }
            return BubbleInfo(text: text, icon: "folder.fill", tint: Palette.accent, spinner: true)
        case .done:
            return BubbleInfo(text: "All done!", icon: "checkmark.circle.fill", tint: .green)
        case .idle, .sleeping:
            return nil
        }
    }
}

/// Root view of the desktop window.
@MainActor
struct BuddyView: View {
    @ObservedObject var model: BuddyModel
    @ObservedObject var settings: BuddySettings

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 40)) { timeline in
            let now = timeline.date
            let t = now.timeIntervalSinceReferenceDate * settings.animationSpeed
            let bubble = model.activePhrase(at: now).map { BubbleInfo(text: $0) }
                ?? BuddyStack.bubble(for: model.mood, projects: model.projects, settings: settings)
            BuddyStack(bubble: bubble, mood: model.mood, t: t, reaction: model.reaction(at: now),
                       style: settings.style(look: model.cursorLook))
                .opacity(settings.opacity)
                .scaleEffect(settings.scale)
                .frame(width: BuddyLayout.window.width * settings.scale,
                       height: BuddyLayout.window.height * settings.scale)
        }
    }
}
