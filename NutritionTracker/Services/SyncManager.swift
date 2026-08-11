import Foundation
import SwiftUI

// Data sync between devices (see sync-architecture).
// PULL: full on login (busy indicator) + 1/day silent on open.
// PUSH: delta 1/day silent on open (only what changed since last_push_at).
@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()
    private init() {}

    // Published to LoginScreen/ContentView to show the "Loading data..." indicator.
    @Published var isInitialSyncing = false

    private let lastPushKey = "sync.lastPushAt"
    private let lastPullKey = "sync.lastPullAt"
    private let lastDailyKey = "sync.lastDailySyncDay"
    private let migratedKey = "sync.initialMigrationDone"

    private var lastPushAt: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: lastPushKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: lastPushKey) }
    }
    private var lastPullAt: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: lastPullKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: lastPullKey) }
    }

    // MARK: - Full pull on login (with busy indicator)

    func pullOnLogin() async {
        isInitialSyncing = true
        defer {
            // Mark today's sync as done so the scenePhase.active dailySyncIfNeeded right
            // after login doesn't fire a duplicate pull/push.
            UserDefaults.standard.set(Self.dayString(Date()), forKey: lastDailyKey)
            isInitialSyncing = false
        }
        do {
            // 1) Pull everything from the server and merge (LWW).
            let resp = try await NetworkService.shared.syncPull(since: nil)
            DatabaseManager.shared.applyPulled(resp)
            lastPullAt = resp.serverTime
            // 2) Push local data. On the FIRST login on this install we push everything
            //    (since=0) once — to migrate legacy pre-account local data. On later
            //    logins we push only the delta, so we don't re-upload the whole history
            //    (can be thousands of rows) on every sign-in.
            let migrated = UserDefaults.standard.bool(forKey: migratedKey)
            let pushSince: Int64 = migrated ? lastPushAt : 0
            let local = DatabaseManager.shared.collectChanges(since: pushSince)
            if local.profile != nil || local.norms != nil
                || !local.entries.isEmpty || !local.foodCache.isEmpty {
                let pushResp = try await NetworkService.shared.syncPush(local)
                lastPushAt = pushResp.serverTime
            } else {
                lastPushAt = resp.serverTime
            }
            UserDefaults.standard.set(true, forKey: migratedKey)
        } catch {
            print("[sync] pullOnLogin failed: \(error)")
        }
    }

    // MARK: - Daily background sync (silent)

    /// Called when the app opens. Runs push+pull at most once per day.
    func dailySyncIfNeeded() async {
        guard AuthManager.shared.isSignedIn else { return }
        let today = Self.dayString(Date())
        if UserDefaults.standard.string(forKey: lastDailyKey) == today { return }
        await backgroundSync()
        UserDefaults.standard.set(today, forKey: lastDailyKey)
    }

    /// Push the delta, then pull the delta. Silent, no indicator.
    func backgroundSync() async {
        await sync(pushSince: lastPushAt)
    }

    /// Forced full sync (button in the profile): push EVERYTHING (since=0),
    /// then pull the delta. Guarantees upload of data created before accounts existed.
    func forceSyncNow() async {
        await sync(pushSince: 0)
    }

    private func sync(pushSince: Int64) async {
        guard AuthManager.shared.isSignedIn else { return }
        // 1) PUSH
        do {
            let changes = DatabaseManager.shared.collectChanges(since: pushSince)
            if changes.profile != nil || changes.norms != nil
                || !changes.entries.isEmpty || !changes.foodCache.isEmpty {
                let resp = try await NetworkService.shared.syncPush(changes)
                lastPushAt = resp.serverTime
            }
        } catch {
            print("[sync] push failed: \(error)")
        }
        // 2) PULL — delta since the last pull.
        do {
            let since = lastPullAt > 0 ? lastPullAt : nil
            let resp = try await NetworkService.shared.syncPull(since: since)
            DatabaseManager.shared.applyPulled(resp)
            lastPullAt = resp.serverTime
        } catch {
            print("[sync] pull failed: \(error)")
        }
    }

    // Reset markers on sign-out — a new user on this device syncs from scratch.
    func resetOnSignOut() {
        UserDefaults.standard.removeObject(forKey: lastPushKey)
        UserDefaults.standard.removeObject(forKey: lastPullKey)
        UserDefaults.standard.removeObject(forKey: lastDailyKey)
    }

    private static func dayString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
}
