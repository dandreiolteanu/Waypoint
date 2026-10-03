import SwiftUI
import Waypoint

/// Passing data back. Edit name is a pushed screen and pick color is a sheet. Both are awaited:
/// the value comes back when the screen calls its callback, and `nil` comes back when the user leaves some other way.
@MainActor
final class ProfileCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case profile
        case editName(current: String, onSave: Callback<String>)
        case colorPicker(current: ProfileColor, onPick: Callback<ProfileColor>)
    }

    private let session: SessionStore
    private let onSignOut: () -> Void

    init(session: SessionStore, onSignOut: @escaping () -> Void) {
        self.session = session
        self.onSignOut = onSignOut
    }

    var initialRoute: Route { .profile }

    func destination(for route: Route) -> some View {
        switch route {
        case .profile:
            ProfileView(viewModel: ProfileViewModel(session: session, navigation: self))
        case let .editName(current, onSave):
            EditNameView(viewModel: EditNameViewModel(name: current, onSave: onSave))
        case let .colorPicker(current, onPick):
            ColorPickerView(selected: current, onPick: { onPick($0) }, onClose: { self.dismissPresented() })
        }
    }

    func showSettings(section: SettingsCoordinator.Route?) {
        let settings = SettingsCoordinator(onSignOut: onSignOut)
        push(child: settings)
        if let section, section != settings.initialRoute {
            settings.push(section)
        }
    }
}

extension ProfileCoordinator: ProfileNavigation {
    func editName(current: String) async -> String? {
        await push { .editName(current: current, onSave: $0) }
    }

    func pickColor(current: ProfileColor) async -> ProfileColor? {
        await present(as: .sheet(detents: [.medium], dragIndicator: .visible)) { .colorPicker(current: current, onPick: $0) }
    }

    func showSettings() {
        showSettings(section: nil)
    }
}
