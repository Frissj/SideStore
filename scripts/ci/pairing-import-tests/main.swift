import Foundation
import MinimuxerCommon

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

func xml(_ plist: [String: Any]) throws -> String {
    String(data: try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0), encoding: .utf8)!
}

let manager = PairingFileManager.shared
let folder = FileManager.default.documentsDirectory
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
manager.resetAllPairingFiles()
manager.preferredProtocol = nil

// Synthetic keys only; no real device records enter CI.
let remote: [String: Any] = [
    "private_key": Data(repeating: 1, count: 32),
    "public_key": Data(repeating: 2, count: 32),
    "identifier": "00000000-0000-0000-0000-000000000001",
    "alt_irk": Data(repeating: 3, count: 16)
]
let lockdown: [String: Any] = [
    "WiFiMACAddress": "00:00:00:00:00:00", "SystemBUID": "test-system", "HostID": "test-host",
    "UDID": "test-device", "RootPrivateKey": Data([4]), "HostPrivateKey": Data([5]),
    "RootCertificate": Data([6]), "HostCertificate": Data([7]), "DeviceCertificate": Data([8]), "EscrowBag": Data([9])
]
let combined = remote.merging(lockdown) { first, _ in first }
let source = folder.appendingPathComponent("original.plist")
let original = try xml(combined)
try original.write(to: source, atomically: true, encoding: .utf8)
let inspected = try manager.inspectPairingFile(from: source)
check(inspected.file.mode == .rppairing, "Default to Remote Pairing for combined files")
try manager.importPairingFile(from: source)
check(manager.preferredProtocol == .rppairing, "Persist the automatic preference")
check(manager.persistedActiveProtocol == .rppairing && manager.hasPairingFile(), "Make import available at next boot")
let savedRemote = try PairingFileParser.parse(content: manager.fetchPairingFile(for: .rppairing)!)
let savedLockdown = try PairingFileParser.parse(content: manager.fetchPairingFile(for: .lockdown)!)
check(savedRemote.mode == .rppairing && savedLockdown.mode == .lockdown, "Both files parse without a preference")
check((savedRemote.plist["alt_irk"] as? Data) == (remote["alt_irk"] as? Data), "Preserve optional Remote Pairing metadata")
check(savedRemote.plist["EscrowBag"] == nil && savedLockdown.plist["private_key"] == nil, "Split the two credential sets")
let savedSource = try String(contentsOf: source, encoding: .utf8)
check(savedSource == original, "Do not modify the imported source")
let forBoot = try PairingFileParser.parse(content: manager.fetchPairingFile()!)
check(forBoot.mode == .rppairing, "Boot receives an unambiguous record")

manager.preferredProtocol = .lockdown
try manager.importPairingFile(from: source)
check(manager.preferredProtocol == .lockdown, "Preserve an existing valid preference")
try manager.importPairingFile(from: source, preferred: .rppairing)
check(manager.preferredProtocol == .rppairing, "Honor an explicit import preference")
let requestedLockdown = try manager.inspectPairingFile(from: source, preferred: .lockdown)
check(requestedLockdown.file.mode == .lockdown, "Honor the selected import row for combined files")

let beforeRemote = manager.fetchPairingFile(for: .rppairing)
let beforeLockdown = manager.fetchPairingFile(for: .lockdown)
do {
    _ = try manager.savePairingFile(contents: try xml(["identifier": "incomplete"]))
    fatalError("Incomplete records must be rejected")
} catch is PairingError {}
check(manager.fetchPairingFile(for: .rppairing) == beforeRemote, "Invalid imports leave Remote Pairing intact")
check(manager.fetchPairingFile(for: .lockdown) == beforeLockdown, "Invalid imports leave Lockdown intact")

manager.resetAllPairingFiles()
manager.preferredProtocol = nil
_ = try manager.savePairingFile(contents: try xml(lockdown))
check(manager.preferredProtocol == .lockdown && !manager.hasPairingFile(for: .rppairing), "Single-protocol files retain their format")
let binary = try PropertyListSerialization.data(fromPropertyList: combined, format: .binary, options: 0)
try binary.write(to: source)
manager.preferredProtocol = nil
try manager.importPairingFile(from: source)
check(manager.preferredProtocol == .rppairing && manager.hasPairingFile(for: .lockdown), "Binary combined plists import both protocols")
print("Pairing import checks passed: combined XML/binary, preference selection, metadata, boot parsing, single-protocol files, and invalid-input preservation.")
