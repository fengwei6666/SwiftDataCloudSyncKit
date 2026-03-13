import CoreData
import SwiftData

extension ModelContainer {
    /// The underlying NSPersistentContainer extracted via Mirror-based reflection.
    var underlyingPersistentContainer: NSPersistentContainer? {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if let pc = child.value as? NSPersistentContainer { return pc }
        }
        if let superMirror = mirror.superclassMirror {
            for child in superMirror.children {
                if let pc = child.value as? NSPersistentContainer { return pc }
            }
        }
        return nil
    }

    /// Store identifiers for all persistent stores in this container.
    var persistentStoreIdentifiers: Set<String> {
        guard let pc = underlyingPersistentContainer else { return [] }
        return Set(pc.persistentStoreCoordinator.persistentStores.map(\.identifier))
    }
}
