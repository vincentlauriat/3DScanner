import Foundation
import UniformTypeIdentifiers

/// Formats d'export proposés à l'utilisateur (spec §5.5).
enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case pdf, png, svg, dxf
    case usdzParametric, usdzMesh, obj, stl, ply
    case json, zip

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case twoD, threeD, data
        var id: String { rawValue }
        var titleKey: String { switch self { case .twoD: "export.group.2d"; case .threeD: "export.group.3d"; case .data: "export.group.data" } }
    }

    var group: Group {
        switch self {
        case .pdf, .png, .svg, .dxf: .twoD
        case .usdzParametric, .usdzMesh, .obj, .stl, .ply: .threeD
        case .json, .zip: .data
        }
    }

    var fileExtension: String {
        switch self {
        case .usdzParametric, .usdzMesh: "usdz"
        default: rawValue
        }
    }

    var utType: UTType {
        switch self {
        case .pdf: .pdf
        case .png: .png
        case .svg: .svg
        case .dxf: UTType(importedAs: "com.autodesk.dxf", conformingTo: .data)
        case .usdzParametric, .usdzMesh: .usdz
        case .obj: UTType(importedAs: "public.geometry-definition-format", conformingTo: .data)
        case .stl: UTType(importedAs: "public.standard-tesselated-geometry-format", conformingTo: .data)
        case .ply: UTType(importedAs: "public.polygon-file-format", conformingTo: .data)
        case .json: .json
        case .zip: .zip
        }
    }

    var titleKey: String { "export.format.\(rawValue)" }
    var descriptionKey: String { "export.format.\(rawValue).description" }
    var systemImage: String {
        switch self {
        case .pdf: "doc.richtext"; case .png: "photo"; case .svg: "pencil.and.outline"; case .dxf: "ruler"
        case .usdzParametric: "cube"; case .usdzMesh: "cube.transparent"; case .obj: "square.stack.3d.up"; case .stl: "printer"; case .ply: "circle.grid.3x3"
        case .json: "curlybraces"; case .zip: "archivebox"
        }
    }

    /// Suffixe ajouté au nom de fichier quand deux formats partagent une extension.
    var fileSuffix: String { self == .usdzMesh ? "-mesh" : "" }
}
