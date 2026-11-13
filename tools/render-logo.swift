// Genera il logo / l'icona di Lyricar.
// Uso:  swift tools/render-logo.swift
// Output: App/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024×1024, a tutta superficie)
//         docs/images/logo.png (512×512, con angoli arrotondati per il README)

import SwiftUI
import AppKit

let green = Color(red: 0.12, green: 0.84, blue: 0.38)
let night = Color(red: 0.04, green: 0.06, blue: 0.14)
let deep = Color(red: 0.05, green: 0.16, blue: 0.22)

struct Road: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX - r.width * 0.06, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.06, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Linea di mezzeria tratteggiata in prospettiva (trattini che si allungano verso chi guarda)
struct CenterLine: View {
    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            ForEach(0..<4) { i in
                let t0 = [0.0, 0.22, 0.47, 0.76][i]
                let len = [0.10, 0.14, 0.18, 0.24][i]
                let w = 6 + CGFloat(i) * 5
                Capsule()
                    .fill(.white.opacity(0.55 + Double(i) * 0.1))
                    .frame(width: w, height: h * len)
                    .position(x: g.size.width / 2, y: h * (t0 + len / 2))
            }
        }
    }
}

struct LyricBar: View {
    let width: CGFloat
    let color: Color
    var glow = false
    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: 64)
            .shadow(color: glow ? green.opacity(0.75) : .clear, radius: 36)
    }
}

struct Logo: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [night, deep], startPoint: .top, endPoint: .bottom)

            // Bagliore verde dietro la riga corrente
            RadialGradient(colors: [green.opacity(0.28), .clear], center: UnitPoint(x: 0.42, y: 0.42),
                           startRadius: 0, endRadius: 520)

            // Strada in prospettiva
            ZStack {
                Road().fill(
                    LinearGradient(colors: [.white.opacity(0.02), .white.opacity(0.14)],
                                   startPoint: .top, endPoint: .bottom))
                CenterLine()
            }
            .frame(width: 1024, height: 330)
            .offset(y: 1024 / 2 - 165)

            // Righe del testo: sopra già cantata, al centro quella corrente, sotto la prossima
            VStack(alignment: .leading, spacing: 46) {
                LyricBar(width: 330, color: .white.opacity(0.28))
                LyricBar(width: 560, color: green, glow: true)
                LyricBar(width: 430, color: .white.opacity(0.42))
            }
            .padding(.leading, 175)
            .frame(width: 1024, alignment: .leading)
            .offset(y: -105)

            // Nota musicale
            Image(systemName: "music.note")
                .font(.system(size: 200, weight: .bold))
                .foregroundStyle(green)
                .shadow(color: green.opacity(0.6), radius: 30)
                .offset(x: 240, y: -290)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func save(_ view: some View, size: CGFloat, to path: String) {
    let renderer = ImageRenderer(content: view.frame(width: size, height: size))
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render fallito") }
    let rep = NSBitmapImageRep(cgImage: cg)
    let url = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("✓ \(path) (\(cg.width)×\(cg.height))")
}

MainActor.assumeIsolated {
    // Icona: a tutta superficie e senza trasparenza (iOS applica da solo gli angoli)
    save(Logo(), size: 1024, to: "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    // Logo per il README: ridotto e con gli angoli arrotondati
    save(Logo().scaleEffect(0.5).frame(width: 512, height: 512)
            .clipShape(RoundedRectangle(cornerRadius: 115, style: .continuous)),
         size: 512, to: "docs/images/logo.png")
}
