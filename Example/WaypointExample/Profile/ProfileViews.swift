import SwiftUI
import Waypoint

@MainActor
protocol ProfileNavigation: AnyObject {
    func editName(current: String) async -> String?
    func pickColor(current: ProfileColor) async -> ProfileColor?
    func showSettings()
}

@MainActor
@Observable
final class ProfileViewModel {
    private(set) var lastEvent = "Nothing yet"
    private let session: SessionStore
    private let navigation: ProfileNavigation

    init(session: SessionStore, navigation: ProfileNavigation) {
        self.session = session
        self.navigation = navigation
        LifetimeTracker.track(self, kind: .viewModel)
    }

    var user: User? { session.user }

    func editName() async {
        guard var user else { return }
        guard let name = await navigation.editName(current: user.name) else {
            lastEvent = "Edit name: cancelled"
            return
        }
        user.name = name
        session.update(user)
        lastEvent = "Edit name: saved \"\(name)\""
    }

    func pickColor() async {
        guard var user else { return }
        guard let color = await navigation.pickColor(current: user.favoriteColor) else {
            lastEvent = "Pick color: dismissed"
            return
        }
        user.favoriteColor = color
        session.update(user)
        lastEvent = "Pick color: \(color.title)"
    }

    func showSettings() {
        navigation.showSettings()
    }
}

struct ProfileView: View {
    let viewModel: ProfileViewModel

    var body: some View {
        List {
            if let user = viewModel.user {
                Section {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(user.favoriteColor.color.gradient)
                            .frame(width: 56, height: 56)
                            .overlay { Text(user.name.prefix(1)).font(.title2.bold()).foregroundStyle(.white) }
                        VStack(alignment: .leading) {
                            Text(user.name).font(.title3.bold()).accessibilityIdentifier("profile.name")
                            Text(user.email).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                DemoRow(title: "Edit name", subtitle: "await push → String?", systemImage: "character.cursor.ibeam") {
                    Task { await viewModel.editName() }
                }
                .accessibilityIdentifier("profile.editName")
                DemoRow(title: "Favorite color", subtitle: "await present(.sheet) → ProfileColor?", systemImage: "paintpalette") {
                    Task { await viewModel.pickColor() }
                }
                .accessibilityIdentifier("profile.pickColor")
            } header: {
                Text("Results")
            } footer: {
                Text("Last result: \(viewModel.lastEvent)").accessibilityIdentifier("profile.lastEvent")
            }
            Section {
                DemoRow(title: "Settings", subtitle: "A child coordinator pushed onto this stack", systemImage: "gearshape", action: viewModel.showSettings)
                    .accessibilityIdentifier("profile.settings")
            }
        }
        .navigationTitle("Profile")
    }
}

@MainActor
@Observable
final class EditNameViewModel {
    var name: String
    private let onSave: Callback<String>

    init(name: String, onSave: Callback<String>) {
        self.name = name
        self.onSave = onSave
        LifetimeTracker.track(self, kind: .viewModel)
    }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    func save() {
        onSave(name.trimmingCharacters(in: .whitespaces))
    }
}

struct EditNameView: View {
    @Bindable var viewModel: EditNameViewModel

    var body: some View {
        Form {
            TextField("Name", text: $viewModel.name)
                .accessibilityIdentifier("editName.field")
            Text("Save pops this screen and returns the name. Back returns nil.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Edit name")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: viewModel.save)
                    .disabled(!viewModel.canSave)
                    .accessibilityIdentifier("editName.save")
            }
        }
    }
}

struct ColorPickerView: View {
    let selected: ProfileColor
    let onPick: (ProfileColor) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 16) {
                ForEach(ProfileColor.allCases) { color in
                    Button { onPick(color) } label: {
                        VStack {
                            Circle()
                                .fill(color.color.gradient)
                                .frame(width: 56, height: 56)
                                .overlay {
                                    if color == selected { Image(systemName: "checkmark").font(.title3.bold()).foregroundStyle(.white) }
                                }
                            Text(color.title).font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("color.\(color.rawValue)")
                }
            }
            .padding(16)
        }
        .navigationTitle("Favorite color")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CloseButton(action: onClose) }
    }
}
