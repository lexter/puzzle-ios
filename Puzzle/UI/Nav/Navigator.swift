import SwiftUI

enum Screen: Equatable {
    case landing
    case leaderboard
    case game(Mode)
    case lobby(Mode)
    case race
    case photo(Mode)
}

/// A screen model that wants to know when its back-stack entry goes away.
@MainActor
protocol ScreenModel: AnyObject {
    func onCleared()
}

extension ScreenModel {
    func onCleared() {}
}

/// One back-stack entry; owns the models of its screen and clears them when popped.
@MainActor
final class NavEntry: Identifiable {
    let id = UUID()
    let screen: Screen
    private var models: [ObjectIdentifier: ScreenModel] = [:]

    init(_ screen: Screen) { self.screen = screen }

    /// The entry's model of type `M`, created on first use.
    func model<M: ScreenModel>(_ make: () -> M) -> M {
        let key = ObjectIdentifier(M.self)
        if let existing = models[key] as? M { return existing }
        let created = make()
        models[key] = created
        return created
    }

    func clear() {
        models.values.forEach { $0.onCleared() }
        models.removeAll()
    }
}

/// App-scoped back stack.
@MainActor
final class Navigator: ObservableObject {
    @Published private(set) var stack = [NavEntry(.landing)]

    var current: NavEntry { stack[stack.count - 1] }
    var canPop: Bool { stack.count > 1 }

    func push(_ screen: Screen) { stack.append(NavEntry(screen)) }

    /// Replaces the top entry (e.g. Lobby → Race).
    func replace(_ screen: Screen) {
        let top = stack.removeLast()
        stack.append(NavEntry(screen))
        top.clear()
    }

    @discardableResult
    func pop() -> Bool {
        guard canPop else { return false }
        stack.removeLast().clear()
        return true
    }

    func popToRoot() {
        while canPop { pop() }
    }
}
