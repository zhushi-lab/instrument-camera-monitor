import Foundation
import Security

let service = "com.yushaofen.imagesnap-timelapse.smtp"
guard CommandLine.arguments.count == 3 else {
    fputs("usage: MailSecret get|set|delete ACCOUNT\n", stderr)
    exit(2)
}
let mode = CommandLine.arguments[1]
let account = CommandLine.arguments[2]
let base: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
]
if mode == "set" {
    guard let secret = readLine(strippingNewline: true), !secret.isEmpty,
          let data = secret.data(using: .utf8) else {
        fputs("empty SMTP authorization code\n", stderr)
        exit(2)
    }
    var query = base
    query[kSecValueData as String] = data
    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem {
        let update = SecItemUpdate(base as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        guard update == errSecSuccess else {
            fputs("keychain update failed: \(update)\n", stderr)
            exit(1)
        }
    } else if status != errSecSuccess {
        fputs("keychain save failed: \(status)\n", stderr)
        exit(1)
    }
} else if mode == "delete" {
    let status = SecItemDelete(base as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
        fputs("keychain delete failed: \(status)\n", stderr)
        exit(1)
    }
} else if mode == "get" {
    var query = base
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = true
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data,
          let secret = String(data: data, encoding: .utf8) else {
        fputs("SMTP authorization code is missing from Keychain: \(status)\n", stderr)
        exit(1)
    }
    print(secret)
} else {
    fputs("usage: MailSecret get|set|delete ACCOUNT\n", stderr)
    exit(2)
}
