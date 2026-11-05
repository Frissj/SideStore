//
//  PairingFileManager.swift
//  SideStore
//
//  Created by Magesh K on 17/06/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import UniformTypeIdentifiers
import MinimuxerCommon

public struct PairingFileMetadata: Sendable {
    public let exists: Bool
    public let size: Int64
    public let creationDate: Date?
    public let modificationDate: Date?
}

final class PairingFileManager: NSObject {
    static let shared = PairingFileManager()

    static var supportedContentTypes: [UTType] {
        var types = AppConstants.Pairing.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        types.append(contentsOf: [.propertyList, .xml])
        return types
    }

    var activeProtocol: PairingProtocol {
        minimuxerPairingProtocol()
    }

    var persistedActiveProtocol: PairingProtocol? {
        get { UserDefaults.standard.activePairingProtocol }
        set { UserDefaults.standard.activePairingProtocol = newValue }
    }

    var preferredProtocol: PairingProtocol? {
        get { UserDefaults.standard.preferredPairingProtocol }
        set { UserDefaults.standard.preferredPairingProtocol = newValue }
    }

    nonisolated func pairingFileURL(for mode: PairingProtocol) -> URL {
        let fileName: String
        switch mode {
        case .rppairing:
            fileName = AppConstants.Pairing.remotePairingFileName
        case .lockdown:
            fileName = AppConstants.Pairing.lockdownPairingFileName
        default:
            fileName = AppConstants.Pairing.legacyPairingFileName
        }
        return FileManager.default.documentsDirectory.appendingPathComponent(fileName)
    }

    nonisolated func hasPairingFile(for mode: PairingProtocol) -> Bool {
        return FileManager.default.fileExists(atPath: pairingFileURL(for: mode).path)
    }

    nonisolated func hasPairingFile() -> Bool {
        guard !UserDefaults.standard.isPairingReset else { return false }
        if let target = preferredProtocol, hasPairingFile(for: target) {
            return true
        }
        if let mode = persistedActiveProtocol, hasPairingFile(for: mode) {
            return true
        }
        return false
    }

    nonisolated func metadata(for mode: PairingProtocol) -> PairingFileMetadata {
        let fileURL = pairingFileURL(for: mode)
        let path = fileURL.path
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return PairingFileMetadata(exists: false, size: 0, creationDate: nil, modificationDate: nil)
        }
        let attrs = (try? fm.attributesOfItem(atPath: path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let creation = (attrs[.creationDate] as? Date) ?? (attrs[.modificationDate] as? Date)
        let mod = attrs[.modificationDate] as? Date
        return PairingFileMetadata(exists: true, size: size, creationDate: creation, modificationDate: mod)
    }

    nonisolated func fetchPairingFile(for mode: PairingProtocol) -> String? {
        let fileURL = pairingFileURL(for: mode)
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path),
           let contents = try? String(contentsOf: fileURL), !contents.isEmpty 
        {
            return contents
        }
        return nil
    }
    
    nonisolated func sanitizePairingFileFor(contents: String, pprotocol: PairingProtocol) -> String {
        guard (try? PairingFileParser.parse(content: contents, preferred: pprotocol)) != nil,
              let data = contents.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return contents
        }

        let remoteKeys: Set<String> = ["private_key", "public_key", "identifier", "alt_irk"]
        let lockdownKeys: Set<String> = [
            "WiFiMACAddress", "SystemBUID", "RootPrivateKey", "HostPrivateKey", "HostID",
            "RootCertificate", "UDID", "EscrowBag", "HostCertificate", "DeviceCertificate"
        ]
        let excludedKeys: Set<String>
        switch pprotocol {
        case .rppairing: excludedKeys = lockdownKeys
        case .lockdown: excludedKeys = remoteKeys
        case .unknown: return contents
        }
        // Preserve optional protocol metadata, including Remote Pairing's alt_irk.
        let record = plist.filter { !excludedKeys.contains($0.key) }
        guard let sanitized = try? PropertyListSerialization.data(fromPropertyList: record, format: .xml, options: 0),
              let result = String(data: sanitized, encoding: .utf8) else {
            return contents
        }
        return result
    }

    nonisolated func fetchPairingFile(preferred: PairingProtocol? = nil) -> String? {
        let targetPreferred = preferred ?? preferredProtocol
        if let targetPreferred {
            if let contents = fetchPairingFile(for: targetPreferred) {
                return sanitizePairingFileFor(contents: contents, pprotocol: targetPreferred)
            }
        } else {
            if let contents = fetchPairingFile(for: .rppairing) {
                return sanitizePairingFileFor(contents: contents, pprotocol: .rppairing)
            } else if #available(iOS 26.4, *), let contents = fetchPairingFile(for: .lockdown) {
                return sanitizePairingFileFor(contents: contents, pprotocol: .lockdown)
            } else if let contents = fetchPairingFile(for: .unknown) {
                if let _ = try? parse(content: contents, preferred: .rppairing) {
                    return sanitizePairingFileFor(contents: contents, pprotocol: .rppairing)
                } else {
                    return sanitizePairingFileFor(contents: contents, pprotocol: .lockdown)
                }
            }
        }
        if let persisted = persistedActiveProtocol {
            return fetchPairingFile(for: persisted)
        }
        return nil
    }
    
    @discardableResult
    nonisolated func parse(content: String, preferred: PairingProtocol? = nil) throws -> any PairingFile {
        do {
            return try PairingFileParser.parse(content: content, preferred: preferred)
        } catch PairingError.ambiguous(_) {
            let saved = preferredProtocol
            let fallback: PairingProtocol
            if #available(iOS 17, tvOS 17, *) {
                fallback = .rppairing
            } else {
                fallback = .lockdown
            }
            let selected: PairingProtocol
            if let saved, saved == .rppairing || saved == .lockdown {
                selected = saved
            } else {
                selected = fallback
            }
            return try PairingFileParser.parse(content: content, preferred: selected)
        }
    }

    @discardableResult
    func savePairingFile(contents: String, preferred: PairingProtocol? = nil) throws -> any PairingFile {
        let parsed = try parse(content: contents, preferred: preferred)
        let hasRemote = (try? PairingFileParser.parse(content: contents, preferred: .rppairing)) != nil
        let hasLockdown = (try? PairingFileParser.parse(content: contents, preferred: .lockdown)) != nil
        let modes: [PairingProtocol] = hasRemote && hasLockdown ? [.rppairing, .lockdown] : [parsed.mode]
        // Validate every split record before replacing any existing file.
        let records = try modes.map { mode in
            let record = sanitizePairingFileFor(contents: contents, pprotocol: mode)
            _ = try PairingFileParser.parse(content: record)
            return (mode, record)
        }
        for (mode, record) in records {
            let destinationURL = pairingFileURL(for: mode)
            try record.write(to: destinationURL, atomically: true, encoding: .utf8)
            debugLog("[PairingFile] Saved \(mode.rawValue) pairing file.")
        }
        if hasRemote && hasLockdown || preferredProtocol == nil || preferredProtocol == .unknown {
            preferredProtocol = parsed.mode
        }
        UserDefaults.standard.isPairingReset = false
        return parsed
    }

    func inspectPairingFile(from url: URL, preferred: PairingProtocol? = nil) throws -> (content: String, file: any PairingFile) {
        let isSecured = url.startAccessingSecurityScopedResource()
        defer {
            if isSecured {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        guard let content = String(data: xml, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let parsed: any PairingFile
        do {
            parsed = try PairingFileParser.parse(content: content)
        } catch PairingError.ambiguous(_) {
            parsed = try parse(content: content, preferred: preferred)
        }
        return (content, parsed)
    }

    func importPairingFile(from url: URL, preferred: PairingProtocol? = nil) throws {
        let (content, _) = try inspectPairingFile(from: url)
        let parsed = try savePairingFile(contents: content, preferred: preferred)
        persistedActiveProtocol = parsed.mode
    }

    func deletePairingFile(for mode: PairingProtocol) {
        let fileURL = pairingFileURL(for: mode)
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try? fm.removeItem(at: fileURL)
            debugLog("[PairingFile] Deleted \(mode.rawValue) pairing file: \(fileURL.path)")
        }
        if mode == persistedActiveProtocol {
            persistedActiveProtocol = nil
        }
    }

    func resetAllPairingFiles() {
        let fm = FileManager.default
        let files = [
            AppConstants.Pairing.lockdownPairingFileName,
            AppConstants.Pairing.remotePairingFileName,
            AppConstants.Pairing.legacyPairingFileName
        ]
        for name in files {
            let path = fm.documentsDirectory.appendingPathComponent(name)
            if fm.fileExists(atPath: path.path) {
                try? fm.removeItem(at: path)
            }
        }
        UserDefaults.standard.isPairingReset = true
        persistedActiveProtocol = nil
        debugLog("[PairingFile] Reset all pairing files.")
    }
}
