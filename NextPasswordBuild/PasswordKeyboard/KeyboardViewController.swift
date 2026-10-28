import UIKit

final class KeyboardViewController: UIInputViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private struct Entry: Codable {
        let id: UUID
        let site: String
        let username: String
        let password: String
        let link: String
        let notes: String
        let createdAt: Date
    }

    private let siteField = UITextField()
    private let generatedLabel = UILabel()
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var entries: [Entry] = []
    private var filtered: [Entry] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureUI()
        loadEntries()
    }

    private func configureUI() {
        let globe = UIButton(type: .system)
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        siteField.placeholder = "Website name"
        siteField.borderStyle = .roundedRect
        siteField.autocapitalizationType = .none
        siteField.addTarget(self, action: #selector(siteChanged), for: .editingChanged)

        let insert = UIButton(type: .system)
        insert.setTitle("Insert", for: .normal)
        insert.titleLabel?.font = .boldSystemFont(ofSize: 15)
        insert.addTarget(self, action: #selector(insertGenerated), for: .touchUpInside)

        generatedLabel.text = "MpMr@"
        generatedLabel.font = .monospacedSystemFont(ofSize: 17, weight: .semibold)
        generatedLabel.adjustsFontSizeToFitWidth = true

        let top = UIStackView(arrangedSubviews: [globe, siteField, insert])
        top.axis = .horizontal
        top.spacing = 8
        top.alignment = .center
        globe.widthAnchor.constraint(equalToConstant: 40).isActive = true
        insert.widthAnchor.constraint(equalToConstant: 58).isActive = true

        searchBar.placeholder = "Search saved passwords"
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 46
        tableView.keyboardDismissMode = .onDrag

        let stack = UIStackView(arrangedSubviews: [top, generatedLabel, searchBar, tableView])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            generatedLabel.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func loadEntries() {
        guard let defaults = UserDefaults(suiteName: "group.app.nextsolution.nextpassword"),
              let data = defaults.data(forKey: "keyboardVault"),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
        filtered = decoded
        tableView.reloadData()
    }

    @objc private func siteChanged() {
        generatedLabel.text = Self.password(for: siteField.text ?? "")
    }

    @objc private func insertGenerated() {
        let value = Self.password(for: siteField.text ?? "")
        guard value != "MpMr@" else { return }
        textDocumentProxy.insertText(value)
    }

    static func password(for site: String) -> String {
        let letters = site.uppercased().filter { $0.isLetter }
        guard let first = letters.first, let last = letters.last else { return "MpMr@" }
        func position(_ character: Character) -> Int {
            guard let scalar = character.unicodeScalars.first else { return 0 }
            return Int(scalar.value) - 64
        }
        return String(format: "MpMr@%d%02d%02d", letters.count, position(first), position(last))
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        filtered = searchText.isEmpty ? entries : entries.filter {
            $0.site.localizedCaseInsensitiveContains(searchText) || $0.username.localizedCaseInsensitiveContains(searchText)
        }
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filtered.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Entry") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "Entry")
        let entry = filtered[indexPath.row]
        cell.textLabel?.text = entry.site
        cell.detailTextLabel?.text = entry.username.isEmpty ? "Tap to insert password" : entry.username
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        textDocumentProxy.insertText(filtered[indexPath.row].password)
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
