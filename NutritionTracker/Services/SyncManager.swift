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
        let synced = await backgroundSync()
        if synced { UserDefaults.standard.set(today, forKey: lastDailyKey) }
    }

    /// Push the delta, then pull the delta. Silent, no indicator. Returns true if at least one succeeded.
    @discardableResult
    func backgroundSync() async -> Bool {
        return await sync(pushSince: lastPushAt)
    }

    /// Forced full sync (button in the profile): push EVERYTHING (since=0),
    /// then pull the delta. Guarantees upload of data created before accounts existed.
    func forceSyncNow() async {
        await sync(pushSince: 0)
    }

    @discardableResult
    private func sync(pushSince: Int64) async -> Bool {
        guard AuthManager.shared.isSignedIn else { return false }
        var ok = false
        // 1) PULL first — must run BEFORE push. If we pushed first, the pull that
        // immediately follows would return our OWN just-pushed rows (stamped with the
        // latest server time), inflating lastPullAt to ~now and skipping over another
        // device's older rows that were uploaded but not yet covered by our cursor —
        // stranding them behind the cursor forever. pullOnLogin already pulls-then-pushes.
        do {
            let since = lastPullAt > 0 ? lastPullAt : nil
            let resp = try await NetworkService.shared.syncPull(since: since)
            DatabaseManager.shared.applyPulled(resp)
            lastPullAt = resp.serverTime
            ok = true
        } catch {
            print("[sync] pull failed: \(error)")
        }
        // 2) PUSH
        do {
            let changes = DatabaseManager.shared.collectChanges(since: pushSince)
            if changes.profile != nil || changes.norms != nil
                || !changes.entries.isEmpty || !changes.foodCache.isEmpty {
                let resp = try await NetworkService.shared.syncPush(changes)
                lastPushAt = resp.serverTime
                ok = true
            }
        } catch {
            print("[sync] push failed: \(error)")
        }
        return ok
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
