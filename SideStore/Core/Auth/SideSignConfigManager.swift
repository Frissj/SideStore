//
//  SideSignConfigManager.swift
//  SideStore
//
//  Created by Magesh K on 11/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

public actor SideSignConfigManager {
    public static let shared = SideSignConfigManager()

    /// Match the Mac ADI identity used by the default anisette server.
    public nonisolated static func defaultAuthHeaders() -> SideSignHeaders {
        var h = SideSignHeaders()
        h.grandSlam = .init(
            service: "iCloud",
            headerVersion: "1.0.1",
            authApp: "com.apple.gs.xcode.auth",
            userAgent: AppConstants.Anisette.Servers.macUserAgent
        )
        h.appleAuth = .init(
            appIDKey: h.appleAuth.appIDKey,
            userAgent: AppConstants.Anisette.Servers.macUserAgent
        )
        return h
    }

    /// Fill missing values without replacing the selected anisette identity.
    public nonisolated static func sanitizeForGrandSlam(_ config: SideSignHeaders) -> SideSignHeaders {
        var c = config
        if c.grandSlam.userAgent.isEmpty {
            c.grandSlam.userAgent = AppConstants.Anisette.Servers.macUserAgent
        }
        if c.appleAuth.userAgent.isEmpty {
            c.appleAuth.userAgent = AppConstants.Anisette.Servers.macUserAgent
        }
        return c
    }

    private nonisolated var configFileURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("sidesign-config.json")
    }

    public func loadConfig() -> SideSignHeaders {
        if let data = try? Data(contentsOf: configFileURL),
           var config = try? JSONDecoder().decode(SideSignHeaders.self, from: data) {
            config = Self.sanitizeForGrandSlam(config)
            DeveloperPortal.shared.customHeaders = config
            return config
        }
        let cfg = Self.defaultAuthHeaders()
        DeveloperPortal.shared.customHeaders = cfg
        return cfg
    }

    public nonisolated func applyConfigToDeveloperPortal() {
        if let data = try? Data(contentsOf: configFileURL),
           var config = try? JSONDecoder().decode(SideSignHeaders.self, from: data) {
            config = Self.sanitizeForGrandSlam(config)
            DeveloperPortal.shared.customHeaders = config
        } else {
            DeveloperPortal.shared.customHeaders = Self.defaultAuthHeaders()
        }
    }

    public func saveConfig(_ config: SideSignHeaders) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? enc.encode(config) {
            try? data.write(to: configFileURL, options: .atomic)
        }
        DeveloperPortal.shared.customHeaders = config
    }

    public func importFromFile(url: URL) throws -> SideSignHeaders {
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(SideSignHeaders.self, from: data)
        saveConfig(config)
        return config
    }

    public func exportConfigData() -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? enc.encode(loadConfig())
    }

    @discardableResult
    public nonisolated func resetToDefaults() -> SideSignHeaders {
        try? FileManager.default.removeItem(at: configFileURL)
        let cfg = Self.defaultAuthHeaders()
        DeveloperPortal.shared.customHeaders = cfg
        return cfg
    }

    public nonisolated func deleteConfigFile() {
        try? FileManager.default.removeItem(at: configFileURL)
    }

    public nonisolated func hasConfigFile() -> Bool {
        FileManager.default.fileExists(atPath: configFileURL.path)
    }
}
