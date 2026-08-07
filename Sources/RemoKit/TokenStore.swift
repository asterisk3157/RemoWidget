import Foundation
import Security

/// アクセストークンの保管（FR-1 / NFR-4）。
/// UserDefaults や平文ファイルには決して書かない。
/// アプリとウィジェット拡張の両方から読むため Keychain Access Group を使う。
public enum TokenStore {

    public static let service = "com.shironoir.remowidget.token"
    private static let account = "nature-remo"

    /// Keychain Access Group。両ターゲットの entitlements と一致させること。
    /// 不一致だとウィジェット側だけが「未設定」表示になる（要件書 R-5）。
    public static let accessGroup = AppGroup.identifier

    public enum StoreError: LocalizedError {
        case notFound
        case unexpectedStatus(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .notFound: return "アクセストークンが保存されていません"
            case .unexpectedStatus(let s): return "Keychain エラー (\(s))"
            }
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }

    public static func save(_ token: String) throws {
        let data = Data(token.utf8)
        var query = baseQuery()

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // ウィジェット拡張はロック解除後に動くため AfterFirstUnlock で足りる。
            // ThisDeviceOnly を付けて、iCloud キーチェーン同期や
            // バックアップ経由で他の端末へトークンが渡らないようにする。
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            query.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.unexpectedStatus(addStatus) }
        default:
            throw StoreError.unexpectedStatus(status)
        }
    }

    public static func load() throws -> String {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw StoreError.notFound }
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw StoreError.notFound
        }
        return token
    }

    public static func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(status)
        }
    }

    public static var exists: Bool { (try? load()) != nil }
}
