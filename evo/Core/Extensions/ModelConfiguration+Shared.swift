import Foundation
import SwiftData

extension ModelConfiguration {
    /// Shared model configuration for the main Evo database
    static func evoDatabase(isPrivate: Bool = false) -> ModelConfiguration {
        if isPrivate {
            return ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            return ModelConfiguration(
                "EvoData",
                schema: Schema([TabContainer.self, History.self, Download.self]),
                url: URL.applicationSupportDirectory.appending(path: "Evo/EvoData.sqlite")
            )
        }
    }

    /// Creates a ModelContainer using the standard Evo database configuration
    static func createEvoContainer(isPrivate: Bool = false) throws -> ModelContainer {
        return try ModelContainer(
            for: TabContainer.self, History.self, Download.self,
            configurations: evoDatabase(isPrivate: isPrivate)
        )
    }
}
