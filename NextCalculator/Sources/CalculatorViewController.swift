import UIKit

final class CalculatorViewController: UIViewController {
    private let engine = CalculatorEngine()
    private let displayLabel = UILabel()
    private let expressionLabel = UILabel()
    private let angleLabel = UILabel()
    private var grid = UIStackView()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureDisplay()
        rebuildLayout()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.rebuildLayout() })
    }

    private func configureDisplay() {
        displayLabel.text = "0"
        displayLabel.textColor = .white
        displayLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 68, weight: .regular)
        displayLabel.minimumScaleFactor = 0.35
        displayLabel.adjustsFontSizeToFitWidth = true
        displayLabel.textAlignment = .right

        expressionLabel.textColor = UIColor(white: 0.55, alpha: 1)
        expressionLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        expressionLabel.textAlignment = .right
        expressionLabel.numberOfLines = 1

        angleLabel.text = "DEG"
        angleLabel.textColor = .systemOrange
        angleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        angleLabel.textAlignment = .left
    }

    private func rebuildLayout() {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        grid.removeFromSuperview()
        let landscape = view.bounds.width > view.bounds.height * 1.2

        let root = UIStackView()
        root.axis = .vertical
        root.spacing = landscape ? 8 : 10
        root.translatesAutoresizingMaskIntoConstraints = false

        let displayBox = UIStackView(arrangedSubviews: [angleLabel, UIView(), expressionLabel])
        displayBox.axis = .horizontal
        displayBox.alignment = .center
        displayBox.spacing = 8

        root.addArrangedSubview(displayBox)
        root.addArrangedSubview(displayLabel)

        grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = landscape ? 7 : 10
        grid.distribution = .fillEqually
        root.addArrangedSubview(grid)

        view.addSubview(root)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: landscape ? 12 : 10),
            root.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: landscape ? -12 : -10),
            root.topAnchor.constraint(equalTo: guide.topAnchor, constant: landscape ? 4 : 8),
            root.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: landscape ? -4 : -8),
            displayLabel.heightAnchor.constraint(equalToConstant: landscape ? 78 : 116),
            displayBox.heightAnchor.constraint(equalToConstant: 24)
        ])

        if landscape { buildLandscape() } else { buildPortrait() }
    }

    private func buildPortrait() {
        let rows = [
            [button("AC", .utility), button("±", .utility), button("%", .utility), button("÷", .operator)],
            [button("7", .number), button("8", .number), button("9", .number), button("×", .operator)],
            [button("4", .number), button("5", .number), button("6", .number), button("−", .operator)],
            [button("1", .number), button("2", .number), button("3", .number), button("+", .operator)],
            [button("0", .numberWide), button(".", .number), button("=", .operator)]
        ]
        rows.forEach { addRow($0) }
    }

    private func buildLandscape() {
        let scientific = [
            ["(", ")", "sin", "asin", "ln", "log", "MC", "M+"],
            ["√", "∛", "cos", "acos", "e", "exp", "M−", "MR"],
            ["x²", "x³", "tan", "atan", "π", "!", "DEG", "RAD"],
            ["sinh", "cosh", "tanh", "abs", "1/x", "xʸ", "AC", "±"],
            ["", "", "", "", "", "", "%", "÷"]
        ]
        let standard = [
            ["7","8","9","×"],
            ["4","5","6","−"],
            ["1","2","3","+"],
            ["0",".","="]
        ]
        for r in 0..<5 {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 7
            row.distribution = .fillEqually
            for c in 0..<8 {
                let title: String
                if r < 4 { title = scientific[r][c] }
                else if c < 7 { title = c == 6 ? "%" : "" }
                else { title = "÷" }
                row.addArrangedSubview(title.isEmpty ? UIView() : makeLandscapeButton(title, scientific: true))
            }
            grid.addArrangedSubview(row)
        }

        let standardPanel = UIStackView()
        standardPanel.axis = .horizontal
        standardPanel.spacing = 7
        standardPanel.distribution = .fillEqually
        for row in standard {
            let v = UIStackView()
            v.axis = .vertical
            v.spacing = 7
            v.distribution = .fillEqually
            for title in row {
                v.addArrangedSubview(makeLandscapeButton(title, scientific: false))
            }
            standardPanel.addArrangedSubview(v)
        }
        let wrapper = UIView()
        wrapper.addSubview(standardPanel)
        standardPanel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            standardPanel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 8),
            standardPanel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -8),
            standardPanel.topAnchor.constraint(equalTo: wrapper.topAnchor),
            standardPanel.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        grid.insertArrangedSubview(wrapper, at: 0)
    }

    private enum ButtonKind { case number, numberWide, operator, utility, scientific }

    private func button(_ title: String, _ kind: ButtonKind) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 29, weight: .medium)
        b.setTitleColor(kind == .operator ? .white : (kind == .utility ? .black : .white), for: .normal)
        b.backgroundColor = kind == .operator ? .systemOrange : (kind == .utility ? UIColor(white: 0.72, alpha: 1) : UIColor(white: 0.15, alpha: 1))
        b.layer.cornerRadius = 100
        b.clipsToBounds = true
        b.addAction(UIAction { [weak self] _ in self?.tap(title) }, for: .touchUpInside)
        return b
    }

    private func makeLandscapeButton(_ title: String, scientific: Bool) -> UIButton {
        let kind: ButtonKind = scientific ? (title == "AC" || title == "±" || title == "DEG" || title == "RAD" ? .utility : .scientific) :
            (["×","−","+","÷","=","%"].contains(title) ? .operator : .number)
        let b = button(title, kind)
        b.titleLabel?.font = UIFont.systemFont(ofSize: scientific ? 17 : 25, weight: .medium)
        if scientific { b.backgroundColor = title == "DEG" || title == "RAD" ? UIColor(white: 0.24, alpha: 1) : UIColor(white: 0.19, alpha: 1) }
        return b
    }

    private func addRow(_ buttons: [UIButton]) {
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        if buttons.count == 3 {
            row.insertArrangedSubview(UIView(), at: 1)
        }
        if buttons.first?.currentTitle == "0" { buttons.first?.widthAnchor.constraint(equalTo: buttons[1].widthAnchor, multiplier: 2.05).isActive = true }
        grid.addArrangedSubview(row)
    }

    private func tap(_ title: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        switch title {
        case "0","1","2","3","4","5","6","7","8","9": engine.inputDigit(title)
        case ".": engine.decimal()
        case "AC": engine.clear()
        case "±": engine.toggleSign()
        case "%": engine.percent()
        case "÷","×","−","+": engine.setOperator(title)
        case "=": engine.equals()
        case "DEG","RAD": engine.setAngleMode()
        case "(": engine.openParen()
        case ")": engine.closeParen()
        case "sin","cos","tan","sinh","cosh","tanh","ln","log","exp","sqrt","cbrt","abs": engine.scientific(title)
        case "asin","acos","atan": engine.scientific(title.replacingOccurrences(of: "a", with: "a"), inverse: false)
        case "π","e": engine.constant(title)
        case "!": engine.scientific("factorial") // handled by fallback below
        case "x²": engine.power("2")
        case "x³": engine.power("3")
        case "xʸ": engine.setOperator("^")
        case "1/x": 
            engine.scientific("reciprocal")
        case "MC": engine.memoryClear()
        case "M+": engine.memoryAdd()
        case "M−": engine.memorySubtract()
        case "MR": engine.memoryRecall()
        default:
            break
        }
        if title == "RAD" || title == "DEG" { angleLabel.text = engine.angleMode == .deg ? "DEG" : "RAD" }
        displayLabel.text = engine.display
        expressionLabel.text = engine.expression
    }
}
