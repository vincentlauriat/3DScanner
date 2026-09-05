import XCTest
import UniformTypeIdentifiers
@testable import RoomScanner

/// Paquet `.housescan` (v2 phase 2) : écriture/lecture, pièces imbriquées, bibliothèque, import, exports.
@MainActor
final class HousePackageTests: XCTestCase {
    var location: StorageLocation!
    var store: RoomStore!

    override func setUp() async throws {
        location = .temporary()
        store = RoomStore(location: location)
        store.reload()
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: location.documentsURL)
    }

    /// Maison à deux niveaux construite depuis la structure synthétique, avec ses paquets de pièces.
    private func housePackage(name: String = "Maison", createdAt: Date = Date()) -> HousePackage {
        let structure = SyntheticRooms.twoStoryHouse()
        let house = HouseBuilder().build(from: structure, name: name)
        let rooms = house.allRooms.map { plan in RoomPackage(record: RoomRecord(plan: plan, createdAt: createdAt), plan: plan, scan: structure.rooms.first { $0.id == plan.id }) }
        return HousePackage(record: HouseRecord(house: house, createdAt: createdAt), house: house, structure: structure, capturedStructureData: Data("apple".utf8),
                            rooms: rooms, usdzData: Data([0, 1, 2]), thumbnailPNG: PlanRenderer.thumbnailPNG(for: house))
    }

    func testWriteReadRoundTrip() throws {
        let pkg = housePackage()
        let url = location.housePackageURL(for: pkg.record.id)
        try pkg.write(to: url)
        XCTAssertEqual(url.pathExtension, "housescan")
        XCTAssertEqual(try HousePackage.readRecord(from: url), pkg.record)
        XCTAssertEqual(try HousePackage.readHouse(from: url), pkg.house)
        XCTAssertEqual(try HousePackage.readStructure(from: url), pkg.structure)
        XCTAssertEqual(HousePackage.roomPackageURLs(in: url).count, pkg.rooms.count, "une pièce imbriquée par plan")
        for roomURL in HousePackage.roomPackageURLs(in: url) {
            XCTAssertEqual(roomURL.pathExtension, "roomscan")
            let room = try RoomPackage.read(from: roomURL)
            XCTAssertTrue(pkg.house.allRooms.contains(room.plan))
        }
        XCTAssertNotNil(HousePackage.usdzURL(in: url)); XCTAssertNotNil(HousePackage.thumbnailURL(in: url))
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent(FileLayout.HousePackageFile.capturedStructure)), Data("apple".utf8))
    }

    func testRecordSummarisesHouse() {
        let pkg = housePackage()
        XCTAssertEqual(pkg.record.roomCount, pkg.house.allRooms.count)
        XCTAssertEqual(pkg.record.storyCount, 2)
        XCTAssertEqual(pkg.record.areaM2, HouseMeasurements(house: pkg.house).floorArea, accuracy: 1e-6)
        XCTAssertEqual(pkg.record.id, pkg.house.id)
    }

    func testStoreListsSavesRenamesDeletes() throws {
        XCTAssertTrue(store.houseRecords.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.housesURL.path))
        let older = housePackage(name: "Ancienne", createdAt: Date(timeIntervalSinceNow: -3600))
        let newer = housePackage(name: "Récente")
        try store.saveHouse(older); try store.saveHouse(newer)
        XCTAssertEqual(store.houseRecords.map(\.name), ["Récente", "Ancienne"], "du plus récent au plus ancien")
        let fresh = RoomStore(location: location); fresh.reload()
        XCTAssertEqual(fresh.houseRecords.map(\.name), ["Récente", "Ancienne"])
        XCTAssertTrue(fresh.records.isEmpty, "les pièces imbriquées n'apparaissent pas comme pièces libres")

        try store.rename(older.record, to: "  Chalet ")
        XCTAssertEqual(store.houseRecords.last?.name, "Chalet")
        XCTAssertEqual(try HousePackage.readHouse(from: store.packageURL(for: older.record)).name, "Chalet")
        XCTAssertEqual(try store.house(for: store.houseRecords.last!).name, "Chalet")

        try store.delete(LibraryItem.house(newer.record))
        XCTAssertEqual(store.houseRecords.map(\.name), ["Chalet"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.packageURL(for: newer.record).path))
        XCTAssertEqual(store.proposedHouseName(), String(localized: "house.defaultName"))
    }

    func testHouseIsRebuiltFromStructureKeepingRoomNames() throws {
        var pkg = housePackage()
        // Le `house.json` stocké est volontairement obsolète (noms personnalisés, plan vide).
        pkg.house.stories[0].rooms[0].name = "Séjour"
        var stale = pkg.house; stale.stories[0].rooms[0].walls = []
        pkg.house = stale
        pkg.record = HouseRecord(house: stale, createdAt: pkg.record.createdAt)
        try store.saveHouse(pkg)
        let rebuilt = try store.house(for: pkg.record)
        XCTAssertFalse(rebuilt.stories[0].rooms[0].walls.isEmpty, "recalculé depuis structure.json")
        XCTAssertEqual(rebuilt.stories[0].rooms[0].name, "Séjour", "nom conservé")
        XCTAssertEqual(try HousePackage.readHouse(from: store.packageURL(for: pkg.record)), rebuilt, "paquet rafraîchi")
        XCTAssertEqual(store.houseRecords.first?.roomCount, rebuilt.allRooms.count)
    }

    /// Montée de version de schéma : une maison enregistrée avant la v2 phase 5 porte des noms
    /// automatiques issus de la première section seulement, et une surface qui somme les pièces.
    /// À la relecture, les deux sont recalculés et le paquet réécrit — c'est ce qui rend le
    /// correctif visible sur une maison déjà scannée, sans nouveau scan.
    func testSchemaMigrationRecomputesAutomaticNamesAndArea() throws {
        var pkg = housePackage()
        pkg.house.stories[0].rooms[0].name = "Ancien nom automatique"
        pkg.record = HouseRecord(house: pkg.house, createdAt: pkg.record.createdAt)
        pkg.record.schemaVersion = 1
        pkg.record.areaM2 = 999
        try store.saveHouse(pkg)

        let rebuilt = try store.house(for: pkg.record)
        XCTAssertNotEqual(rebuilt.stories[0].rooms[0].name, "Ancien nom automatique", "noms automatiques recalculés à la montée de schéma")
        let record = try XCTUnwrap(store.houseRecords.first { $0.id == pkg.record.id })
        XCTAssertEqual(record.schemaVersion, FloorPlan.schemaVersion, "le paquet adopte le schéma courant")
        XCTAssertEqual(record.areaM2, HouseMeasurements(house: rebuilt).floorArea, accuracy: 1e-9)
        XCTAssertNotEqual(record.areaM2, 999, "la surface stockée est rafraîchie")
        XCTAssertEqual(try HousePackage.readRecord(from: store.packageURL(for: pkg.record)), record, "meta.json réécrit")
    }

    func testImportDuplicateGetsNewIdentity() throws {
        let pkg = housePackage()
        try store.saveHouse(pkg)
        let external = FileManager.default.temporaryDirectory.appendingPathComponent("ext-\(UUID().uuidString).housescan")
        defer { try? FileManager.default.removeItem(at: external) }
        try pkg.write(to: external)
        let imported = try store.importAny(from: external)
        guard case .house(let record) = imported else { return XCTFail("un .housescan importe une maison") }
        XCTAssertNotEqual(record.id, pkg.record.id)
        XCTAssertTrue(record.name.hasPrefix("Maison"))
        XCTAssertEqual(store.houseRecords.count, 2)
        let house = try HousePackage.readHouse(from: store.packageURL(for: record))
        XCTAssertEqual(house.id, record.id)
        XCTAssertEqual(HousePackage.roomPackageURLs(in: store.packageURL(for: record)).count, pkg.rooms.count)
    }

    func testUTTypeAndLibraryItem() {
        XCTAssertEqual(UTType.houseScan.identifier, "fr.vincentlauriat.roomscanner.house")
        XCTAssertTrue(UTType.houseScan.conforms(to: .package))
        let pkg = housePackage()
        let item = LibraryItem.house(pkg.record)
        XCTAssertEqual(item.id, pkg.record.id); XCTAssertEqual(item.name, "Maison")
        XCTAssertEqual(store.packageURL(for: item), location.housePackageURL(for: pkg.record.id))
    }

    func testExportSubjectForHouse() throws {
        let pkg = housePackage(name: "Villa/Test")
        try store.saveHouse(pkg)
        let url = store.packageURL(for: pkg.record)
        let subject = ExportSubject(record: pkg.record, house: pkg.house, packageURL: url)
        XCTAssertEqual(subject.kind, .house)
        XCTAssertEqual(ExportService.folderName(for: subject), "Villa-Test")
        XCTAssertEqual(ExportService.fileName(for: subject, format: .pdf), "Villa-Test.pdf")
        let formats = ExportService.availableFormats(for: subject)
        XCTAssertTrue(formats.contains(.usdzParametric), "house.usdz présent")
        XCTAssertFalse(formats.contains(.usdzMesh), "pas de maillage brut pour une maison")

        let service = ExportService()
        let json = try service.export(subject, format: .json)
        let decoded = try RoomPackage.decoder.decode(House.self, from: Data(contentsOf: json))
        XCTAssertEqual(decoded, pkg.house, "le JSON d'une maison est la maison entière")
        let pdf = try service.export(subject, format: .pdf)
        XCTAssertTrue(try Data(contentsOf: pdf).starts(with: Array("%PDF".utf8)))
        let usdz = try service.export(subject, format: .usdzParametric)
        XCTAssertEqual(try Data(contentsOf: usdz), Data([0, 1, 2]))

        let readme = ArchiveExporter.readme(subject: subject, files: [("Villa-Test.pdf", .pdf)], locale: Locale(identifier: "fr_FR"))
        XCTAssertTrue(readme.contains("Villa/Test"))
        XCTAssertTrue(readme.contains(String(localized: "story.ground")), "un niveau par ligne")
        let zip = try service.export(subject, format: .zip)
        XCTAssertGreaterThan(try Data(contentsOf: zip).count, 1000)

        let saved = try store.saveExport(pdf, for: subject)
        XCTAssertEqual(saved.deletingLastPathComponent().lastPathComponent, "Villa-Test")
    }

    func testAssembleBuildsHouseAndNestedRoomsWithCaptures() throws {
        let structure = SyntheticRooms.twoRoomApartment()
        let firstID = structure.rooms[0].id
        let extras = [firstID: HousePackage.RoomExtras(capturedRoomData: Data("room".utf8), usdzData: Data([7]), usdzMeshData: nil)]
        let pkg = HousePackage.assemble(structure: structure, name: "Appartement", capturedStructureData: Data("structure".utf8), usdzData: Data([1]), roomExtras: extras)
        XCTAssertEqual(pkg.house.name, "Appartement")
        XCTAssertEqual(pkg.rooms.count, 2)
        XCTAssertEqual(pkg.rooms.map(\.plan), pkg.house.allRooms, "un .roomscan par plan, même ordre")
        let first = try XCTUnwrap(pkg.rooms.first { $0.record.id == firstID })
        XCTAssertEqual(first.capturedRoomData, Data("room".utf8)); XCTAssertEqual(first.usdzData, Data([7]))
        XCTAssertEqual(first.scan?.id, firstID, "scan.json de la pièce")
        XCTAssertNotNil(first.thumbnailPNG)
        let second = try XCTUnwrap(pkg.rooms.first { $0.record.id != firstID })
        XCTAssertNil(second.capturedRoomData, "pas de capture fournie → nil")
        XCTAssertEqual(pkg.capturedStructureData, Data("structure".utf8)); XCTAssertEqual(pkg.usdzData, Data([1]))
        XCTAssertNotNil(pkg.thumbnailPNG)
        XCTAssertEqual(pkg.record.roomCount, 2); XCTAssertEqual(pkg.record.storyCount, 1)
        try store.saveHouse(pkg)
        XCTAssertEqual(try store.house(for: pkg.record), pkg.house, "rien à recalculer juste après l'assemblage")
    }

    func testRoomJSONStaysAFloorPlan() throws {
        let plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon")
        let subject = ExportSubject(record: RoomRecord(plan: plan), plan: plan, packageURL: nil)
        let data = try ExportService().data(for: subject.house, format: .json, title: "Salon")
        XCTAssertEqual(try RoomPackage.decoder.decode(FloorPlan.self, from: data), plan)
        XCTAssertEqual(ExportService.folderName(for: subject), "Salon")
    }
}
