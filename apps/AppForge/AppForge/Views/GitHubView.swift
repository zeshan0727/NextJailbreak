import SwiftUI

struct GitHubView: View {
    @EnvironmentObject private var state: AppState
    @State private var newRepoName = ""
    @State private var newRepoPrivate = false
    @State private var showNewRepo = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScreenHeading(title: "GitHub Push", subtitle: "Commit the project and start an automated iOS build.")
                }
                Section("Repository owner") {
                    TextField("GitHub username", text: $state.preferences.githubUsername)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {
                        Button("Load repositories") { Task { await state.refreshRepos() } }
                        Spacer()
                        Button { showNewRepo = true } label: { Label("Create repo", systemImage: "plus") }
                    }
                }
                Section("Repository") {
                    if !state.repositories.isEmpty {
                        Picker("Choose repository", selection: $state.chosenRepo) {
                            ForEach(state.repositories) { repo in
                                Text(repo.name).tag(repo.name)
                            }
                        }.onChange(of: state.chosenRepo) { _ in Task { await state.refreshBranches() } }
                    }
                    TextField("Repository name", text: $state.chosenRepo)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !state.branches.isEmpty {
                        Picker("Existing branch", selection: $state.chosenBranch) {
                            ForEach(state.branches) { branch in Text(branch.name).tag(branch.name) }
                        }
                    }
                    TextField("Branch (existing or new)", text: $state.chosenBranch)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("New branches start from the selected repo's default branch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Commit") {
                    TextField("Commit message", text: $state.commitMessage)
                    if let project = state.project {
                        LabeledContent("Application", value: project.appName)
                        LabeledContent("Files", value: "\(project.files.count)")
                    } else {
                        Text("Generate app source in Code first").foregroundStyle(.secondary)
                    }
                    ForgeButton(title: "Push & Build", symbol: "shippingbox", loading: state.busyPush) {
                        Task { await state.pushAndBuild() }
                    }.disabled(state.project == nil)
                }
                Section {
                    Text("GitHub Actions on public repositories can use standard runners without metered minutes. Your provider may enforce rate limits. Pushing code to a public repo makes the generated source public.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .task { if state.repositories.isEmpty && !Keychain.read("github").isEmpty { await state.refreshRepos() } }
            .alert("Create repository", isPresented: $showNewRepo) {
                TextField("Repository name", text: $newRepoName)
                Button("Public") {
                    newRepoPrivate = false
                    Task { await state.createRepo(name: newRepoName, isPrivate: false) }
                }
                Button("Private") {
                    newRepoPrivate = true
                    Task { await state.createRepo(name: newRepoName, isPrivate: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Public repos support free standard Actions builds. Private repo builds consume your included Actions minutes.")
            }
        }
    }
}
