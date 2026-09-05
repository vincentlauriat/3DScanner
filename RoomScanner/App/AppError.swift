import Foundation

/// Erreurs métier affichées à l'utilisateur. Chaque cas a une cause identifiée
/// et un message localisé ; aucune erreur n'est masquée.
enum AppError: LocalizedError, Equatable {
    case unsupportedDevice
    case cameraDenied
    case scanFailed(String)
    case scanCancelled
    case exportFailed(format: String, reason: String)
    case storageFailed(String)
    case cloudUnavailable
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice: String(localized: "error.unsupportedDevice", bundle: .main)
        case .cameraDenied: String(localized: "error.cameraDenied", bundle: .main)
        case .scanFailed(let why): String(localized: "error.scanFailed \(why)", bundle: .main)
        case .scanCancelled: String(localized: "error.scanCancelled", bundle: .main)
        case .exportFailed(let f, let why): String(localized: "error.exportFailed \(f) \(why)", bundle: .main)
        case .storageFailed(let why): String(localized: "error.storageFailed \(why)", bundle: .main)
        case .cloudUnavailable: String(localized: "error.cloudUnavailable", bundle: .main)
        case .downloadFailed(let why): String(localized: "error.downloadFailed \(why)", bundle: .main)
        }
    }
}
