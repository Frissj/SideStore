import Foundation
import MinimuxerCommon

// Isolate storage and app preferences while compiling the production manager.
extension FileManager {
    var documentsDirectory: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["PAIRING_TEST_DIR"]!) }
}

extension UserDefaults {
    var activePairingProtocol: PairingProtocol? {
        get { string(forKey: "test.active").flatMap(PairingProtocol.init(rawValue:)) }
        set { set(newValue?.rawValue, forKey: "test.active") }
    }
    var preferredPairingProtocol: PairingProtocol? {
        get { string(forKey: "test.preferred").flatMap(PairingProtocol.init(rawValue:)) }
        set { set(newValue?.rawValue, forKey: "test.preferred") }
    }
    var isPairingReset: Bool {
        get { bool(forKey: "test.reset") }
        set { set(newValue, forKey: "test.reset") }
    }
}

enum AppConstants {
    enum Pairing {
        static let supportedExtensions = ["plist", "mobiledevicepairing"]
        static let remotePairingFileName = "PairingFile_RemoteRP.plist"
        static let lockdownPairingFileName = "PairingFile_Lockdown.plist"
        static let legacyPairingFileName = "legacy.plist"
    }
}

func minimuxerPairingProtocol() -> PairingProtocol { .unknown }
func debugLog(_ message: String) {}
