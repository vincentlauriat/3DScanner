import XCTest
@testable import RoomScanner

/// Test de fumée de la phase 0 : la cible de tests se compile et s'exécute
/// sur les deux plateformes avec `@testable import RoomScanner`.
final class SmokeTests: XCTestCase {
    func testModuleIsLinked() {
        XCTAssertNotNil(RootView.self)
    }
}
