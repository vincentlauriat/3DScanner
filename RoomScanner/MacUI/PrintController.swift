import AppKit
import CoreGraphics

/// Impression du plan : le PDF vectoriel de `PlanRenderer` (A4 paysage) est dessiné
/// par une `NSView` dédiée et confié à `NSPrintOperation` — même rendu qu'à l'export.
@MainActor
enum PrintController {
    static func printPlan(_ house: House, title: String, locale: Locale = .current, window: NSWindow?) {
        var renderer = PlanRenderer(); renderer.options.locale = locale
        let pageSize = CGSize(width: 842, height: 595)
        let data = renderer.pdfData(house, size: pageSize, title: title)
        guard let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider) else { return }
        let view = PDFPageView(document: pdf, frame: NSRect(origin: .zero, size: pageSize))
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.orientation = .landscape
        info.paperSize = NSSize(width: 842, height: 595)
        info.horizontalPagination = .fit; info.verticalPagination = .fit
        info.isHorizontallyCentered = true; info.isVerticallyCentered = true
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = title
        op.showsPrintPanel = true; op.showsProgressPanel = true
        if let window { op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil) } else { op.run() }
    }

    /// Vue d'une page PDF, à l'échelle 1 pt = 1 pt.
    final class PDFPageView: NSView {
        let document: CGPDFDocument
        init(document: CGPDFDocument, frame: NSRect) { self.document = document; super.init(frame: frame) }
        required init?(coder: NSCoder) { nil }
        override var isFlipped: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext, let page = document.page(at: 1) else { return }
            ctx.saveGState()
            ctx.concatenate(page.getDrawingTransform(.mediaBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
            ctx.drawPDFPage(page)
            ctx.restoreGState()
        }
        override func knowsPageRange(_ range: NSRangePointer) -> Bool { range.pointee = NSRange(location: 1, length: 1); return true }
        override func rectForPage(_ page: Int) -> NSRect { bounds }
    }
}
