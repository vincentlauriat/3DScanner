#if os(macOS)
import XCTest
import UniformTypeIdentifiers
@testable import RoomScanner

final class MacUITests: XCTestCase {
    private let plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon")

    func testOpenWithListsApplicationsForPDF() {
        let apps = OpenWithMenu.applications(for: .pdf)
        XCTAssertTrue(apps.contains { $0.lastPathComponent == "Preview.app" }, "\(apps.map(\.lastPathComponent))")
    }

    func testDragProviderRegistersTypeAndName() {
        let record = RoomRecord(plan: plan)
        let p = DragExportProvider.provider(subject: ExportSubject(record: record, plan: plan, packageURL: nil), format: .dxf)
        XCTAssertEqual(p.suggestedName, "Salon.dxf")
        XCTAssertTrue(p.registeredTypeIdentifiers.contains(ExportFormat.dxf.utType.identifier))
    }

    func testDragProviderProducesFileOnDemand() {
        let record = RoomRecord(plan: plan)
        let p = DragExportProvider.provider(subject: ExportSubject(record: record, plan: plan, packageURL: nil), format: .svg)
        let exp = expectation(description: "file")
        p.loadFileRepresentation(forTypeIdentifier: UTType.svg.identifier) { url, error in
            XCTAssertNil(error)
            if let url { XCTAssertTrue(String(decoding: try! Data(contentsOf: url).prefix(20), as: UTF8.self).contains("<?xml")) } else { XCTFail("pas de fichier") }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }

    @MainActor
    func testMenuActionsRequireSelection() {
        let state = MacAppState()
        XCTAssertFalse(state.hasSelection)
        state.request(.print)
        XCTAssertEqual(state.pendingAction, .print)
        state.selected = .room(RoomRecord(plan: plan))
        XCTAssertTrue(state.hasSelection)
    }

    @MainActor
    func testExportMenuFormatsFollowSelection() {
        let state = MacAppState()
        XCTAssertTrue(state.availableFormats.isEmpty, "pas de sélection → sous-menu vide")
        state.availableFormats = ExportService.availableFormats(packageURL: nil)
        XCTAssertFalse(state.availableFormats.contains(.usdzMesh), "pas de maillage de scan → pas proposé")
        XCTAssertTrue(state.availableFormats.contains(.zip))
    }
}
#endif
