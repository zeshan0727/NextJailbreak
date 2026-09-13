import UIKit
import Foundation
import Security

struct WorkflowItem {
    let title: String
    let file: String
}

final class KeychainStore {
    private let service = "com.nextjailbreak.trigger"
    private let account = "github-token"

    func save(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: MainViewController())
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class MainViewController: UIViewController, UITextFieldDelegate {
    private let owner = "zeshan0727"
    private let repo = "NextJailbreak"
    private let branch = "main"
    private let keychain = KeychainStore()

    private let workflows = [
        WorkflowItem(title: "Verified Tweak Post", file: "tweak-draft-generator.yml"),
        WorkflowItem(title: "Original-Source News", file: "ios-repo-original-source-news.yml"),
        WorkflowItem(title: "Dopamine 3 Post", file: "dopamine3-cluster-publisher.yml")
    ]

    private let tokenField = UITextField()
    private let statusLabel = UILabel()
    private let activity = UIActivityIndicatorView(style: .medium)
    private var actionButtons: [UIButton] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Next Jailbreak Trigger"
        view.backgroundColor = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles = true
        configureUI()
        tokenField.text = keychain.load()
        updateStatus("Ready. Save a GitHub token, then trigger a publisher.")
    }

    private func configureUI() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30)
        ])

        let intro = UILabel()
        intro.numberOfLines = 0
        intro.font = .preferredFont(forTextStyle: .body)
        intro.text = "Manual control for Next Jailbreak article automations. The GitHub token is stored only in this iPhone Keychain."
        stack.addArrangedSubview(intro)

        tokenField.placeholder = "GitHub fine-grained token"
        tokenField.isSecureTextEntry = true
        tokenField.autocapitalizationType = .none
        tokenField.autocorrectionType = .no
        tokenField.clearButtonMode = .whileEditing
        tokenField.borderStyle = .roundedRect
        tokenField.delegate = self
        stack.addArrangedSubview(tokenField)

        let tokenRow = UIStackView()
        tokenRow.axis = .horizontal
        tokenRow.distribution = .fillEqually
        tokenRow.spacing = 10
        let save = makeButton("Save Token", selector: #selector(saveToken))
        let test = makeButton("Test Token", selector: #selector(testToken))
        tokenRow.addArrangedSubview(save)
        tokenRow.addArrangedSubview(test)
        stack.addArrangedSubview(tokenRow)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stack.addArrangedSubview(separator)

        for (index, workflow) in workflows.enumerated() {
            let button = makeButton("Run: \(workflow.title)", selector: #selector(runWorkflow(_:)))
            button.tag = index
            actionButtons.append(button)
            stack.addArrangedSubview(button)
        }

        let runAll = makeButton("Run All Publishers", selector: #selector(runAll))
        runAll.configuration?.baseBackgroundColor = .systemOrange
        actionButtons.append(runAll)
        stack.addArrangedSubview(runAll)

        let refresh = makeButton("Refresh Latest Status", selector: #selector(refreshStatus))
        refresh.configuration?.baseBackgroundColor = .systemGray
        stack.addArrangedSubview(refresh)

        activity.hidesWhenStopped = true
        stack.addArrangedSubview(activity)

        statusLabel.numberOfLines = 0
        statusLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        statusLabel.backgroundColor = .secondarySystemBackground
        statusLabel.layer.cornerRadius = 10
        statusLabel.layer.masksToBounds = true
        statusLabel.textAlignment = .left
        statusLabel.setContentHuggingPriority(.required, for: .vertical)
        stack.addArrangedSubview(statusLabel)

        let help = UILabel()
        help.numberOfLines = 0
        help.font = .preferredFont(forTextStyle: .footnote)
        help.textColor = .secondaryLabel
        help.text = "Token permissions: Repository access to NextJailbreak and Actions: Read and write. Contents read is sufficient for status. Manual trigger bypasses the clock window, but existing daily limits and quality/safety gates still apply."
        stack.addArrangedSubview(help)
    }

    private func makeButton(_ title: String, selector: Selector) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.cornerStyle = .medium
        config.buttonSize = .large
        let button = UIButton(configuration: config)
        button.addTarget(self, action: selector, for: .touchUpInside)
        return button
    }

    @objc private func saveToken() {
        view.endEditing(true)
        let token = tokenField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            updateStatus("Token is empty.")
            return
        }
        updateStatus(keychain.save(token) ? "Token saved securely in Keychain." : "Could not save token to Keychain.")
    }

    @objc private func testToken() {
        guard let request = apiRequest(path: "repos/\(owner)/\(repo)", method: "GET") else { return }
        setBusy(true, message: "Testing GitHub token…")
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            DispatchQueue.main.async {
                self?.setBusy(false)
                if let error = error {
                    self?.updateStatus("Token test failed: \(error.localizedDescription)")
                } else if code == 200 {
                    self?.updateStatus("Token works. Repository access confirmed.")
                } else {
                    self?.updateStatus("Token test returned HTTP \(code). Check repository access and permissions.")
                }
            }
        }.resume()
    }

    @objc private func runWorkflow(_ sender: UIButton) {
        guard workflows.indices.contains(sender.tag) else { return }
        dispatch(workflows[sender.tag])
    }

    @objc private func runAll() {
        guard tokenReady() else { return }
        setBusy(true, message: "Triggering all publishers…")
        let group = DispatchGroup()
        let lock = NSLock()
        var results: [String] = []

        for item in workflows {
            group.enter()
            dispatchRequest(item) { result in
                lock.lock()
                results.append(result)
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.setBusy(false)
            self?.updateStatus(results.sorted().joined(separator: "\n"))
        }
    }

    private func dispatch(_ item: WorkflowItem) {
        guard tokenReady() else { return }
        setBusy(true, message: "Triggering \(item.title)…")
        dispatchRequest(item) { [weak self] result in
            DispatchQueue.main.async {
                self?.setBusy(false)
                self?.updateStatus(result)
            }
        }
    }

    private func dispatchRequest(_ item: WorkflowItem, completion: @escaping (String) -> Void) {
        let path = "repos/\(owner)/\(repo)/actions/workflows/\(item.file)/dispatches"
        guard var request = apiRequest(path: path, method: "POST") else {
            completion("\(item.title): invalid request")
            return
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["ref": branch])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion("\(item.title): \(error.localizedDescription)")
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if code == 204 {
                completion("\(item.title): TRIGGERED")
            } else {
                completion("\(item.title): HTTP \(code)")
            }
        }.resume()
    }

    @objc private func refreshStatus() {
        guard tokenReady() else { return }
        setBusy(true, message: "Loading latest workflow runs…")
        let group = DispatchGroup()
        let lock = NSLock()
        var lines: [String] = []

        for item in workflows {
            group.enter()
            let path = "repos/\(owner)/\(repo)/actions/workflows/\(item.file)/runs?per_page=1"
            guard let request = apiRequest(path: path, method: "GET") else {
                group.leave()
                continue
            }
            URLSession.shared.dataTask(with: request) { data, response, error in
                var line = "\(item.title): unavailable"
                defer {
                    lock.lock(); lines.append(line); lock.unlock(); group.leave()
                }
                if let error = error {
                    line = "\(item.title): \(error.localizedDescription)"
                    return
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                guard code == 200, let data = data,
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let runs = root["workflow_runs"] as? [[String: Any]],
                      let run = runs.first else {
                    line = "\(item.title): HTTP \(code)"
                    return
                }
                let status = run["status"] as? String ?? "unknown"
                let conclusion = run["conclusion"] as? String ?? "—"
                let number = run["run_number"] as? Int ?? 0
                line = "\(item.title): #\(number) \(status) / \(conclusion)"
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            self?.setBusy(false)
            self?.updateStatus(lines.sorted().joined(separator: "\n"))
        }
    }

    private func tokenReady() -> Bool {
        let token = tokenField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if token.isEmpty {
            updateStatus("Enter and save your GitHub token first.")
            return false
        }
        return true
    }

    private func apiRequest(path: String, method: String) -> URLRequest? {
        let token = tokenField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty,
              let url = URL(string: "https://api.github.com/\(path)") else {
            DispatchQueue.main.async { [weak self] in self?.updateStatus("GitHub token is missing.") }
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("NextJailbreakTrigger/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func setBusy(_ busy: Bool, message: String? = nil) {
        actionButtons.forEach { $0.isEnabled = !busy }
        busy ? activity.startAnimating() : activity.stopAnimating()
        if let message = message { updateStatus(message) }
    }

    private func updateStatus(_ text: String) {
        let padded = "  \(text.replacingOccurrences(of: "\n", with: "\n  "))  "
        statusLabel.text = padded
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
