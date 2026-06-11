import Foundation

/// Tiny JSON file persistence shared by the app's stores.
enum Persistence {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Parlor", isDirectory: true)
    }

    static func load<T: Decodable>(_ file: String) -> T? {
        let url = directory.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to file: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: directory.appendingPathComponent(file), options: .atomic)
        } catch {
            // Persistence is best-effort; the in-memory state stays correct.
        }
    }
}
