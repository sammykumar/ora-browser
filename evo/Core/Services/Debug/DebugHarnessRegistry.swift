#if DEBUG
    import Foundation

    /// Debug-only bridge from the singleton harness server to per-window state.
    /// EvoRoot registers its managers on appear; references are weak so a closed
    /// window never keeps its managers alive.
    @MainActor
    final class DebugHarnessRegistry {
        static let shared = DebugHarnessRegistry()

        struct WindowSnapshot {
            let id: UUID
            let isPrivate: Bool
            let tabManager: TabManager
            let historyManager: HistoryManager
        }

        private struct Entry {
            let id: UUID
            let isPrivate: Bool
            weak var tabManager: TabManager?
            weak var historyManager: HistoryManager?
        }

        private var entries: [Entry] = []

        init() {}

        func register(tabManager: TabManager, historyManager: HistoryManager, isPrivate: Bool) -> UUID {
            let id = UUID()
            entries.append(Entry(id: id, isPrivate: isPrivate, tabManager: tabManager, historyManager: historyManager))
            return id
        }

        func unregister(_ id: UUID) {
            entries.removeAll { $0.id == id }
        }

        func snapshots() -> [WindowSnapshot] {
            entries.removeAll { $0.tabManager == nil || $0.historyManager == nil }
            return entries.compactMap { entry in
                guard let tabManager = entry.tabManager, let historyManager = entry.historyManager else { return nil }
                return WindowSnapshot(
                    id: entry.id,
                    isPrivate: entry.isPrivate,
                    tabManager: tabManager,
                    historyManager: historyManager
                )
            }
        }

        func findTab(_ tabID: UUID) -> (tab: Tab, manager: TabManager)? {
            for snapshot in snapshots() {
                for container in snapshot.tabManager.containers {
                    if let tab = container.tabs.first(where: { $0.id == tabID }) {
                        return (tab, snapshot.tabManager)
                    }
                }
            }
            return nil
        }
    }
#endif
