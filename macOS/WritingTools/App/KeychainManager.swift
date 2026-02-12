//
//  KeychainManager.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    // MARK: - Access Control
    
    /// Creates an Access Control List (ACL) that trusts only this app.
    /// This prevents keychain password prompts by explicitly allowing our app to access items.
    private func createAccessControl() throws -> SecAccess {
        var access: SecAccess?
        
        // Create trusted application for this app (nil = current application)
        var trustedApp: SecTrustedApplication?
        let appStatus = SecTrustedApplicationCreateFromPath(nil, &trustedApp)
        guard appStatus == errSecSuccess, let trustedApp = trustedApp else {
            throw KeychainError.failedToCreateAccess(appStatus)
        }
        
        // Create access control with the trusted app
        let trustedAppList = [trustedApp] as CFArray
        let status = SecAccessCreate(
            "WritingTools OAuth Tokens" as CFString,
            trustedAppList,
            &access
        )
        
        guard status == errSecSuccess, let access = access else {
            throw KeychainError.failedToCreateAccess(status)
        }
        
        return access
    }
    
    enum KeychainError: LocalizedError {
        case failedToSave(OSStatus)
        case failedToRead(OSStatus)
        case failedToDelete(OSStatus)
        case noDataFound
        case failedToCreateAccess(OSStatus)
        
        var errorDescription: String? {
            switch self {
            case .failedToSave(let status):
                return "Failed to save to Keychain: \(status)"
            case .failedToRead(let status):
                return "Failed to read from Keychain: \(status)"
            case .failedToDelete(let status):
                return "Failed to delete from Keychain: \(status)"
            case .noDataFound:
                return "No data found in Keychain"
            case .failedToCreateAccess(let status):
                return "Failed to create access control: \(status)"
            }
        }
    }
    
    // MARK: - Save
    
    func save(_ value: String, forKey key: String) throws {
        guard !value.isEmpty else {
            try delete(forKey: key)
            return
        }
        
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.failedToSave(-1)
        }
        
        // Create access control that trusts this app (eliminates password prompts)
        let access = try createAccessControl()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.aryamirsepasi.writing-tools",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrAccess as String: access  // ACL that allows our app without prompts
        ]
        
        // Try to delete existing first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.failedToSave(status)
        }
    }
    
    // MARK: - Read
    
    func retrieve(forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.aryamirsepasi.writing-tools",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.failedToRead(status)
        }
        
        guard let data = result as? Data else {
            throw KeychainError.noDataFound
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Delete
    
    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.aryamirsepasi.writing-tools"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.failedToDelete(status)
        }
    }
    
    // MARK: - Clear All
    
    func clearAllApiKeys() throws {
        let apiKeyNames = [
            "gemini_api_key",
            "openai_api_key",
            "mistral_api_key",
            "anthropic_api_key",
            "openrouter_api_key"
        ]
        
        for keyName in apiKeyNames {
            try? delete(forKey: keyName)
        }
        
        // Also clear OAuth tokens
        try? deleteOAuthTokens()
    }
    
    // MARK: - Migration
    
    /// Migrates keychain items to include Access Control List (ACL).
    /// This is a one-time migration for existing users that eliminates password prompts.
    /// New items are automatically created with ACL.
    func migrateKeychainItemsToACL() {
        let keysToMigrate = [
            // API Keys
            "gemini_api_key",
            "openai_api_key",
            "mistral_api_key",
            "anthropic_api_key",
            "openrouter_api_key",
            // OAuth Tokens
            "openai_oauth_access_token",
            "openai_oauth_refresh_token",
            "openai_oauth_expires_at",
            "openai_oauth_account_id"
        ]
        
        for key in keysToMigrate {
            // Try to read existing value
            guard let value = try? retrieve(forKey: key), !value.isEmpty else {
                continue  // Item doesn't exist or is empty, skip it
            }
            
            // Check if item already has ACL by attempting to access without prompt
            // (We can't directly check for ACL, so we re-save to ensure it has one)
            
            // Re-save with ACL (save() method now includes ACL)
            // This will delete the old item and create a new one with ACL
            do {
                try save(value, forKey: key)
                print("Migrated keychain item: \(key)")
            } catch {
                print("Failed to migrate keychain item \(key): \(error)")
            }
        }
        
        // Mark migration as complete
        UserDefaults.standard.set(true, forKey: "keychain_acl_migration_completed")
        print("Keychain ACL migration completed")
    }
    
    /// Checks if migration has been completed
    var needsACLMigration: Bool {
        !UserDefaults.standard.bool(forKey: "keychain_acl_migration_completed")
    }
    
    // MARK: - OAuth Token Management
    
    func saveOAuthTokens(_ tokens: OAuthTokens) throws {
        try save(tokens.accessToken, forKey: "openai_oauth_access_token")
        try save(tokens.refreshToken, forKey: "openai_oauth_refresh_token")
        
        let expiresAtString = String(tokens.expiresAt.timeIntervalSince1970)
        try save(expiresAtString, forKey: "openai_oauth_expires_at")
        
        if let accountId = tokens.accountId {
            try save(accountId, forKey: "openai_oauth_account_id")
        }
    }
    
    func retrieveOAuthTokens() throws -> OAuthTokens? {
        guard let accessToken = try retrieve(forKey: "openai_oauth_access_token"),
              let refreshToken = try retrieve(forKey: "openai_oauth_refresh_token"),
              let expiresAtString = try retrieve(forKey: "openai_oauth_expires_at"),
              let expiresAtTimestamp = TimeInterval(expiresAtString) else {
            return nil
        }
        
        let expiresAt = Date(timeIntervalSince1970: expiresAtTimestamp)
        let accountId = try? retrieve(forKey: "openai_oauth_account_id")
        
        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            accountId: accountId
        )
    }
    
    func deleteOAuthTokens() throws {
        try? delete(forKey: "openai_oauth_access_token")
        try? delete(forKey: "openai_oauth_refresh_token")
        try? delete(forKey: "openai_oauth_expires_at")
        try? delete(forKey: "openai_oauth_account_id")
    }
    
    func hasMigratedKey(forKey key: String) -> Bool {
        do {
            let value = try retrieve(forKey: key)
            return value != nil
        } catch {
            return false
        }
    }

    func verifyMigration() -> [String: Bool] {
        let keysToCheck = [
            "gemini_api_key",
            "openai_api_key",
            "mistral_api_key",
            "anthropic_api_key",
            "openrouter_api_key"
        ]
        
        var results: [String: Bool] = [:]
        for key in keysToCheck {
            results[key] = hasMigratedKey(forKey: key)
        }
        return results
    }
}
