import Foundation
import SwiftUI

// Синхронизация данных между устройствами (см. sync-architecture).
// PULL: full при логине (busy indicator) + 1/день silent при открытии.
// PUSH: delta 1/день silent при открытии (только изменённое с last_push_at).
@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()
    private init() {}

    // Публикуется на LoginScreen/ContentView для показа индикатора «Загружаем данные...».
    @Published var isInitialSyncing = false

    private let lastPushKey = "sync.lastPushAt"
    private let lastPullKey = "sync.lastPullAt"
    private let lastDailyKey = "sync.lastDailySyncDay"

    private var lastPushAt: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: lastPushKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: lastPushKey) }
    }
    private var lastPullAt: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: lastPullKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: lastPullKey) }
    }

    // MARK: - Full pull при логине (с busy indicator)

    func pullOnLogin() async {
        isInitialSyncing = true
        defer { isInitialSyncing = false }
        do {
            // 1) Тянем всё с сервера и мержим (LWW).
            let resp = try await NetworkService.shared.syncPull(since: nil)
            DatabaseManager.shared.applyPulled(resp)
            lastPullAt = resp.serverTime
            // 2) Заливаем ВСЕ локальные данные (since=0) — важно для апгрейда старых
            //    пользователей: их дологиновая история/продукты попадут на сервер.
            let allLocal = DatabaseManager.shared.collectChanges(since: 0)
            if allLocal.profile != nil || allLocal.norms != nil
                || !allLocal.entries.isEmpty || !allLocal.foodCache.isEmpty {
                let pushResp = try await NetworkService.shared.syncPush(allLocal)
                lastPushAt = pushResp.serverTime
            } else {
                lastPushAt = resp.serverTime
            }
        } catch {
            print("[sync] pullOnLogin failed: \(error)")
        }
    }

    // MARK: - Ежедневная фоновая синхронизация (silent)

    /// Вызывается при открытии приложения. Выполняет push+pull не чаще 1 раза в день.
    func dailySyncIfNeeded() async {
        guard AuthManager.shared.isSignedIn else { return }
        let today = Self.dayString(Date())
        if UserDefaults.standard.string(forKey: lastDailyKey) == today { return }
        await backgroundSync()
        UserDefaults.standard.set(today, forKey: lastDailyKey)
    }

    /// Push дельты, затем pull дельты. Тихо, без индикатора.
    func backgroundSync() async {
        await sync(pushSince: lastPushAt)
    }

    /// Принудительная полная синхронизация (кнопка в профиле): пушим ВСЁ (since=0),
    /// затем pull дельты. Гарантирует заливку данных, созданных до появления аккаунтов.
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
        // 2) PULL — дельта с прошлого pull.
        do {
            let since = lastPullAt > 0 ? lastPullAt : nil
            let resp = try await NetworkService.shared.syncPull(since: since)
            DatabaseManager.shared.applyPulled(resp)
            lastPullAt = resp.serverTime
        } catch {
            print("[sync] pull failed: \(error)")
        }
    }

    // Сброс маркеров при выходе — новый юзер на этом устройстве синкается заново.
    func resetOnSignOut() {
        UserDefaults.standard.removeObject(forKey: lastPushKey)
        UserDefaults.standard.removeObject(forKey: lastPullKey)
        UserDefaults.standard.removeObject(forKey: lastDailyKey)
    }

    private static func dayString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
}
