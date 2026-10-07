// Renders the README images in docs/ straight from the app's drawing code.
// Run via scripts/render-assets.sh.

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

private let card = Color(red: 0.96, green: 0.94, blue: 0.91)
private let cardInk = Color(red: 0.33, green: 0.29, blue: 0.27)
private let defaultStyle = BuddyStyle()

@MainActor
private func render(_ view: some View, scale: CGFloat = 2) -> CGImage {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    return renderer.cgImage!
}

private func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.lastPathComponent)")
}

private func writeGIF(_ frames: [CGImage], fps: Double, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
    let fileProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
    let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
    CGImageDestinationSetProperties(dest, fileProps)
    for frame in frames { CGImageDestinationAddImage(dest, frame, frameProps) }
    CGImageDestinationFinalize(dest)
    print("wrote \(url.lastPathComponent) (\(frames.count) frames)")
}

/// Classic macOS arrow pointer.
private struct Pointer: View {
    var body: some View {
        let arrow = Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 17))
            p.addLine(to: CGPoint(x: 4.5, y: 13))
            p.addLine(to: CGPoint(x: 7.5, y: 20))
            p.addLine(to: CGPoint(x: 10, y: 19))
            p.addLine(to: CGPoint(x: 7, y: 12))
            p.addLine(to: CGPoint(x: 12.5, y: 12))
            p.closeSubpath()
        }
        ZStack {
            arrow.stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            arrow.fill(Color.black)
        }
        .frame(width: 13, height: 20, alignment: .topLeading)
        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
    }
}

// MARK: - Hero GIF: a tour of the states

@MainActor
private func heroGIF(_ out: URL) {
    struct Segment { let mood: Mood; let seconds: Double; let bubble: BubbleInfo?; let click: Bool }
    let segments = [
        Segment(mood: .idle, seconds: 1.6, bubble: nil, click: false),
        Segment(mood: .working, seconds: 3.4,
                bubble: BubbleInfo(text: "my-app · Editing App.swift", spinner: true), click: false),
        Segment(mood: .attention, seconds: 2.2,
                bubble: BubbleInfo(text: "Claude needs your OK!", icon: "exclamationmark.circle.fill", tint: .red),
                click: false),
        Segment(mood: .done, seconds: 2.4,
                bubble: BubbleInfo(text: "All done!", icon: "checkmark.circle.fill", tint: .green), click: false),
        Segment(mood: .idle, seconds: 1.8, bubble: BubbleInfo(text: "Boop!"), click: true),
    ]
    let fps = 15.0
    var frames: [CGImage] = []
    var clock = 0.0
    for seg in segments {
        let count = Int(seg.seconds * fps)
        for i in 0..<count {
            let local = Double(i) / fps
            let t = clock + local
            let reaction = seg.click && local < 1.2 ? Reaction(kind: .spin, elapsed: local) : nil
            let view = BuddyStack(bubble: seg.bubble, mood: seg.mood, t: t, reaction: reaction, style: defaultStyle)
                .frame(width: 300, height: 240)
                .background(card)
            frames.append(render(view, scale: 1.6))
        }
        clock += seg.seconds
    }
    writeGIF(frames, fps: fps, to: out)
}

// MARK: - Eyes following the pointer

@MainActor
private func followGIF(_ out: URL) {
    let fps = 15.0
    let size = CGSize(width: 300, height: 220)
    let stackOrigin = CGPoint(x: (size.width - BuddyLayout.window.width) / 2, y: size.height - BuddyLayout.window.height)
    let eye = CGPoint(x: stackOrigin.x + BuddyLayout.eyeCenter.x,
                      y: stackOrigin.y + BuddyLayout.window.height - BuddyLayout.eyeCenter.y)
    var frames: [CGImage] = []
    for i in 0..<Int(4 * fps) {
        let t = Double(i) / fps
        let a = .pi + (0.5 - 0.5 * cos(t / 4 * 2 * .pi)) * .pi // sweep over the top, left ↔ right
        let pointer = CGPoint(x: eye.x + cos(a) * 125, y: eye.y + sin(a) * 92)
        var style = defaultStyle
        style.look = lookOffset(dx: pointer.x - eye.x, dy: pointer.y - eye.y, reach: 150)
        let view = ZStack(alignment: .topLeading) {
            BuddyStack(bubble: nil, mood: .idle, t: t, reaction: nil, style: style)
                .offset(x: stackOrigin.x, y: stackOrigin.y)
            Pointer().offset(x: pointer.x, y: pointer.y)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(card)
        frames.append(render(view, scale: 1.6))
    }
    writeGIF(frames, fps: fps, to: out)
}

// MARK: - Still images

private struct Tile<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 2) {
            content
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(cardInk)
        }
    }
}

@MainActor
private func statesPNG(_ out: URL) {
    let tiles: [(String, Mood, Reaction?, BubbleInfo?)] = [
        ("Idle", .idle, nil, nil),
        ("Working", .working, nil, BubbleInfo(text: "Running tests", spinner: true)),
        ("Needs you", .attention, nil, BubbleInfo(text: "Needs your OK!", icon: "exclamationmark.circle.fill", tint: .red)),
        ("Done", .done, nil, BubbleInfo(text: "All done!", icon: "checkmark.circle.fill", tint: .green)),
        ("Asleep", .sleeping, nil, nil),
        ("Clicked", .idle, Reaction(kind: .spin, elapsed: 0.32), BubbleInfo(text: "Boop!")),
    ]
    let view = HStack(spacing: -40) {
        ForEach(tiles.indices, id: \.self) { i in
            let tile = tiles[i]
            Tile(label: tile.0) {
                BuddyStack(bubble: tile.3, mood: tile.1, t: 1.3, reaction: tile.2, style: defaultStyle)
            }
        }
    }
    .padding(.vertical, 20).padding(.horizontal, 10)
    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(card))
    writePNG(render(view), to: out)
}

@MainActor
private func customizePNG(_ out: URL) {
    let looks: [(Accessory, String, Mood)] = [
        (.none, "Claude", .idle), (.partyHat, "Bubblegum", .done), (.topHat, "Sky", .idle),
        (.crown, "Grape", .done), (.headphones, "Mint", .working), (.glasses, "Snow", .idle),
        (.flower, "Lemon", .idle), (.bow, "Midnight", .idle),
    ]
    let view = LazyVGrid(columns: Array(repeating: GridItem(.fixed(150), spacing: 4), count: 4), spacing: 22) {
        ForEach(looks.indices, id: \.self) { i in
            let look = looks[i]
            let preset = ColorPreset.all.first { $0.name == look.1 }!
            let style = BuddyStyle(body: RGB(hex: preset.body)!, limb: RGB(hex: preset.limb)!, accessory: look.0)
            Tile(label: "\(preset.name) · \(look.0.title)") {
                CharacterView(mood: look.2, t: 2.1 + Double(i) * 0.37, reaction: nil, style: style)
            }
        }
    }
    .padding(24)
    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(card))
    writePNG(render(view), to: out)
}

// MARK: - Main

@main
enum RenderAssets {
    @MainActor static func main() {
        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        heroGIF(dir.appendingPathComponent("hero.gif"))
        followGIF(dir.appendingPathComponent("follow-cursor.gif"))
        statesPNG(dir.appendingPathComponent("states.png"))
        customizePNG(dir.appendingPathComponent("customize.png"))
    }
}
