#!/usr/bin/env swift
// Génère l'icône « 3D Scanner » : fond dégradé bleu plan d'architecte, pièce en
// isométrie (sol + deux murs) tracée en blanc, avec une cote et un faisceau LiDAR.
// Usage : swift Scripts/make-app-icon.swift [dossier AppIcon.appiconset]
import AppKit

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let defaultOut = scriptDir.deletingLastPathComponent().appendingPathComponent("RoomScanner/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let out = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true) : defaultOut

func render(_ size: Int, macStyle: Bool) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    // macOS : icône « squircle » avec marge (10 %) et ombre ; iOS : plein cadre (le système masque).
    let inset: CGFloat = macStyle ? s * 0.10 : 0
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    // iOS masque lui-même l’icône : carré plein, sans transparence (exigence App Store).
    let radius = macStyle ? rect.width * 0.225 : 0
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    if macStyle {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.70, alpha: 1).setFill(); path.fill()
        cg.restoreGState()
    }
    NSGradient(colors: [NSColor(calibratedRed: 0.34, green: 0.66, blue: 1.00, alpha: 1),
                        NSColor(calibratedRed: 0.07, green: 0.31, blue: 0.78, alpha: 1)])!.draw(in: path, angle: -70)

    // Quadrillage discret « papier millimétré ».
    cg.saveGState(); path.addClip()
    cg.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor); cg.setLineWidth(max(1, s * 0.004))
    let step = rect.width / 12
    var g = rect.minX; while g <= rect.maxX { cg.move(to: CGPoint(x: g, y: rect.minY)); cg.addLine(to: CGPoint(x: g, y: rect.maxY)); g += step }
    g = rect.minY; while g <= rect.maxY { cg.move(to: CGPoint(x: rect.minX, y: g)); cg.addLine(to: CGPoint(x: rect.maxX, y: g)); g += step }
    cg.strokePath()
    cg.restoreGState()

    // Pièce isométrique : coin arrière au centre, sol en losange, deux murs.
    let w = rect.width
    let c = CGPoint(x: rect.midX, y: rect.midY - w * 0.04)
    let dx = w * 0.30, dy = w * 0.16, h = w * 0.30
    let back = CGPoint(x: c.x, y: c.y + dy)               // coin arrière du sol
    let left = CGPoint(x: c.x - dx, y: c.y)
    let right = CGPoint(x: c.x + dx, y: c.y)
    let front = CGPoint(x: c.x, y: c.y - dy)
    func up(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: p.y + h) }

    let lw = max(1.5, w * 0.045)
    cg.setLineJoin(.round); cg.setLineCap(.round)

    // Faces (murs) semi-transparentes.
    cg.setFillColor(NSColor.white.withAlphaComponent(0.16).cgColor)
    cg.move(to: left); cg.addLine(to: back); cg.addLine(to: up(back)); cg.addLine(to: up(left)); cg.closePath(); cg.fillPath()
    cg.setFillColor(NSColor.white.withAlphaComponent(0.26).cgColor)
    cg.move(to: back); cg.addLine(to: right); cg.addLine(to: up(right)); cg.addLine(to: up(back)); cg.closePath(); cg.fillPath()
    cg.setFillColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    cg.move(to: left); cg.addLine(to: back); cg.addLine(to: right); cg.addLine(to: front); cg.closePath(); cg.fillPath()

    // Arêtes.
    cg.setStrokeColor(NSColor.white.cgColor); cg.setLineWidth(lw)
    cg.move(to: left); cg.addLine(to: back); cg.addLine(to: right)          // fond du sol
    cg.move(to: left); cg.addLine(to: front); cg.addLine(to: right)         // avant du sol
    cg.move(to: left); cg.addLine(to: up(left)); cg.addLine(to: up(back)); cg.addLine(to: up(right)); cg.addLine(to: right)
    cg.move(to: back); cg.addLine(to: up(back))
    cg.strokePath()

    // Porte sur le mur droit.
    cg.setLineWidth(lw * 0.6)
    let d0 = CGPoint(x: back.x + dx * 0.42, y: back.y - dy * 0.42), d1 = CGPoint(x: back.x + dx * 0.72, y: back.y - dy * 0.72)
    cg.move(to: d0); cg.addLine(to: CGPoint(x: d0.x, y: d0.y + h * 0.62)); cg.addLine(to: CGPoint(x: d1.x, y: d1.y + h * 0.62)); cg.addLine(to: d1)
    cg.strokePath()

    // Cote sous le sol (ligne + deux traits d'extrémité), couleur accent clair.
    cg.setStrokeColor(NSColor(calibratedRed: 0.85, green: 0.95, blue: 1.0, alpha: 1).cgColor)
    cg.setLineWidth(lw * 0.5)
    let y = front.y - w * 0.10
    cg.move(to: CGPoint(x: left.x, y: y)); cg.addLine(to: CGPoint(x: right.x, y: y))
    for x in [left.x, right.x] { cg.move(to: CGPoint(x: x, y: y - w * 0.03)); cg.addLine(to: CGPoint(x: x, y: y + w * 0.03)) }
    cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try! render(1024, macStyle: false).write(to: out.appendingPathComponent("ios-1024.png"))
for (pt, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    try! render(pt * scale, macStyle: true).write(to: out.appendingPathComponent("mac-\(pt)@\(scale)x.png"))
}
print("✅ icônes générées dans \(out.path)")
