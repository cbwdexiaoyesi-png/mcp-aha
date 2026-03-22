import Foundation

struct APIGroup: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

@MainActor
class GroupStore: ObservableObject {
    static let shared = GroupStore()

    @Published var groups: [APIGroup] {
        didSet { save() }
    }

    private let key = "api_groups"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([APIGroup].self, from: data) {
            self.groups = saved
        } else {
            self.groups = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(_ group: APIGroup) { groups.append(group) }

    func update(_ group: APIGroup) {
        if let i = groups.firstIndex(where: { $0.id == group.id }) {
            groups[i] = group
        }
    }

    func delete(_ group: APIGroup) {
        groups.removeAll { $0.id == group.id }
    }
}
