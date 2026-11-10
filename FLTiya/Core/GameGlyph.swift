import SwiftUI

/// Original, resolution-independent marks for the gaming interface.
/// Utility symbols outside this set retain their familiar system fallback.
struct GameGlyph: View {
    let symbol: String
    var size: CGFloat = 24

    private var kind: GamingMark.Kind? {
        if symbol.contains("house") { return .home }
        if symbol.contains("gamecontroller") { return .controller }
        if symbol.contains("person.2") || symbol.contains("person.3") { return .players }
        if symbol.contains("person") && symbol.contains("plus") { return .addFriend }
        if symbol.contains("person") { return .helmet }
        if symbol.contains("bubble") { return .chat }
        if symbol.contains("magnifyingglass") { return .radar }
        if symbol.contains("play") || symbol.contains("film") { return .play }
        if symbol.contains("video") || symbol.contains("camera") { return .camera }
        if symbol.contains("iphone") { return .device }
        if symbol.contains("phone") { return .call }
        if symbol.contains("mic") || symbol.contains("waveform") { return .voice }
        if symbol.contains("spark") || symbol.contains("diamond") || symbol.contains("star") { return .spark }
        if symbol.contains("gear") { return .gear }
        if symbol.contains("book") || symbol.contains("doc.text") { return .guide }
        if symbol.contains("shield") || symbol.contains("lock") { return .shield }
        if symbol.contains("trophy") || symbol.contains("medal") { return .trophy }
        return nil
    }

    var body: some View {
        Group {
            if let kind {
                GamingMark(kind: kind)
                    .stroke(style: StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round))
            } else {
                Image(systemName: symbol).resizable().scaledToFit().padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if symbol.contains("slash") {
                Rectangle().frame(width: size * 1.12, height: 1.8).rotationEffect(.degrees(-45))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct GamingMark: Shape {
    enum Kind { case home, controller, players, addFriend, helmet, chat, radar, play, camera, call, voice, spark, gear, guide, shield, device, trophy }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func line(_ points: [CGPoint], close: Bool = false) {
            guard let first = points.first else { return }
            p.move(to: first)
            for point in points.dropFirst() { p.addLine(to: point) }
            if close { p.closeSubpath() }
        }
        func points(_ values: [(CGFloat, CGFloat)], close: Bool = false) {
            line(values.map { CGPoint(x: $0.0, y: $0.1) }, close: close)
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
            p.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        switch kind {
        case .home:
            points([(2,10),(12,2),(22,10)])
            points([(5,9),(5,21),(10,21),(10,15),(14,15),(14,21),(19,21),(19,9)])
            points([(10,9),(12,7),(14,9)])
        case .controller:
            points([(5,6),(9,5),(15,5),(19,6),(22,17),(20,20),(15,16),(9,16),(4,20),(2,17)], close: true)
            points([(6,10),(10,10)]); points([(8,8),(8,12)])
            circle(16,9,0.75); circle(18.5,11.5,0.75)
            points([(10,3),(14,3)])
        case .players, .addFriend:
            circle(8,7,3); circle(17,9,2.3)
            points([(2,20),(3,15),(6,13),(10,13),(13,15),(14,20)], close: true)
            if kind == .players {
                points([(15,15),(18,14),(21,16),(22,20),(17,20)])
            } else {
                points([(18,15),(18,21)]); points([(15,18),(21,18)])
            }
        case .helmet:
            points([(5,20),(3,12),(5,5),(12,2),(19,5),(21,12),(19,20),(15,22),(9,22)], close: true)
            points([(5,10),(19,10),(17,15),(7,15)], close: true)
            points([(9,18),(15,18)])
        case .chat:
            points([(3,4),(18,4),(21,7),(21,15),(17,18),(10,18),(5,22),(5,17),(2,14),(2,7)], close: true)
            points([(7,9),(16,9)]); points([(7,13),(13,13)])
        case .radar:
            circle(10,10,7); circle(10,10,3)
            points([(15,15),(22,22)]); points([(10,1),(10,4)]); points([(1,10),(4,10)])
            points([(10,10),(15,5)])
        case .play:
            points([(6,3),(21,12),(6,21)], close: true)
            points([(2,7),(2,17)])
        case .camera:
            points([(2,6),(14,6),(16,8),(16,18),(2,18)], close: true)
            points([(16,10),(22,7),(22,20),(16,16)])
            circle(8,12,3)
        case .call:
            points([(3,2),(7,2),(10,7),(7,10),(10,14),(14,17),(17,14),(22,17),(22,21),(19,23),(12,20),(5,13),(1,6)], close: true)
        case .voice:
            p.addRoundedRect(in: CGRect(x: 8,y: 2,width: 8,height: 13),cornerSize: CGSize(width: 4,height: 4))
            p.addArc(center: CGPoint(x: 12,y: 12), radius: 7, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            points([(12,19),(12,23)]); points([(8,23),(16,23)])
        case .spark:
            points([(12,1),(15,8),(23,12),(15,15),(12,23),(9,15),(1,12),(9,9)], close: true)
            points([(18,2),(20,4)]); points([(3,20),(5,22)])
        case .gear:
            points([(9,2),(15,2),(16,6),(20,5),(23,10),(20,13),(22,17),(18,21),(14,19),(11,22),(6,20),(6,16),(2,14),(3,8),(7,8)], close: true)
            circle(12,12,4)
        case .guide:
            points([(2,4),(7,3),(12,6),(17,3),(22,4),(22,20),(17,19),(12,22),(7,19),(2,20)], close: true)
            points([(12,6),(12,22)]); points([(5,8),(8,9)]); points([(16,9),(19,8)])
        case .shield:
            points([(12,2),(21,5),(20,15),(16,20),(12,23),(8,20),(4,15),(3,5)], close: true)
            points([(7,12),(11,16),(17,9)])
        case .device:
            points([(7,2),(17,2),(19,4),(19,20),(17,22),(7,22),(5,20),(5,4)], close: true)
            points([(10,5),(14,5)]); points([(10,19),(14,19)])
        case .trophy:
            points([(6,3),(18,3),(17,13),(12,17),(7,13)], close: true)
            points([(6,5),(2,5),(3,11),(7,12)]); points([(18,5),(22,5),(21,11),(17,12)])
            points([(12,17),(12,21)]); points([(7,22),(17,22)])
        }
        return p.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
