import Testing
import Foundation
@testable import whisp

struct KeychainStoreTests {
    // Unique account per invocation: tests run in parallel and keychain items
    // outlive the test process, so a fixed name would race a sibling test and
    // see residue from earlier crashed runs.

    @Test func roundTrip() {
        let account = "apikey.unittest.roundtrip.\(UUID().uuidString)"
        defer { KeychainStore.delete(account: account) }
        #expect(KeychainStore.get(account: account) == nil)
        KeychainStore.set("sk-test-123", account: account)
        #expect(KeychainStore.get(account: account) == "sk-test-123")
        KeychainStore.set("sk-test-456", account: account)  // update path
        #expect(KeychainStore.get(account: account) == "sk-test-456")
        KeychainStore.delete(account: account)
        #expect(KeychainStore.get(account: account) == nil)
    }

    @Test func settingEmptyStringDeletes() {
        let account = "apikey.unittest.emptydelete.\(UUID().uuidString)"
        defer { KeychainStore.delete(account: account) }
        KeychainStore.set("sk-test-123", account: account)
        KeychainStore.set("", account: account)
        #expect(KeychainStore.get(account: account) == nil)
    }
}
