@testable import Evo
import Foundation
import SwiftData
import Testing

@MainActor
struct DebugHarnessRegistryTests {
    private func makeManagers() throws -> (TabManager, HistoryManager) {
        let container = try ModelContainer(
            for: TabContainer.self, History.self, Download.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let tabManager = TabManager(
            modelContainer: container,
            modelContext: context,
            mediaController: MediaController()
        )
        let historyManager = HistoryManager(modelContainer: container, modelContext: context)
        return (tabManager, historyManager)
    }

    @Test func registerAndSnapshot() throws {
        let registry = DebugHarnessRegistry()
        let (tabManager, historyManager) = try makeManagers()
        let id = registry.register(tabManager: tabManager, historyManager: historyManager, isPrivate: false)
        let snapshots = registry.snapshots()
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.id == id)
        #expect(snapshots.first?.isPrivate == false)
    }

    @Test func unregisterRemoves() throws {
        let registry = DebugHarnessRegistry()
        let (tabManager, historyManager) = try makeManagers()
        let id = registry.register(tabManager: tabManager, historyManager: historyManager, isPrivate: true)
        registry.unregister(id)
        #expect(registry.snapshots().isEmpty)
    }

    @Test func deadReferencesArePruned() throws {
        let registry = DebugHarnessRegistry()
        let container = try ModelContainer(
            for: TabContainer.self, History.self, Download.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let historyManager = HistoryManager(modelContainer: container, modelContext: context)
        // Assigned directly into the optional var (no other strong binding) so
        // nilling it out below is the only reference and the weak entry dies.
        var tabManager: TabManager? = TabManager(
            modelContainer: container,
            modelContext: context,
            mediaController: MediaController()
        )
        if let manager = tabManager {
            _ = registry.register(tabManager: manager, historyManager: historyManager, isPrivate: false)
        }
        tabManager = nil
        #expect(registry.snapshots().isEmpty)
    }
}
