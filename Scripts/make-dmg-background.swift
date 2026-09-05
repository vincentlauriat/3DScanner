#!/usr/bin/env swift
// Fond de la fenêtre du DMG (540 × 380 pt, rendu @2x) : titre, flèche entre l'app et /Applications.
// Usage : ./Scripts/make-dmg-background.swift <sortie.png>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 540, height: 380), scale = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGradient(colors: [NSColor(calibratedWhite: 0.98, alpha: 1), NSColor(calibratedWhite: 0.92, alpha: 1)])!
    .draw(in: NSRect(origin: .zero, size: size), angle: -90)
let para = NSMutableParagraphStyle(); para.alignment = .center
("3D Scanner" as NSString).draw(in: NSRect(x: 0, y: 300, width: 540, height: 44), withAttributes: [
    .font: NSFont.systemFont(ofSize: 28, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1), .paragraphStyle: para])
("Glissez l’app dans Applications  ·  Drag the app into Applications" as NSString).draw(in: NSRect(x: 0, y: 40, width: 540, height: 24), withAttributes: [
    .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1), .paragraphStyle: para])
// Flèche entre (140, 200) et (400, 200) — les positions des icônes fixées par release.sh.
let arrow = NSBezierPath(); arrow.lineWidth = 6; arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 215, y: 180)); arrow.line(to: NSPoint(x: 325, y: 180))
arrow.move(to: NSPoint(x: 300, y: 200)); arrow.line(to: NSPoint(x: 325, y: 180)); arrow.line(to: NSPoint(x: 300, y: 160))
NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.86, alpha: 1).setStroke(); arrow.stroke()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
