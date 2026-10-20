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
        displayLabel.minimumScaleFactor = 0.25
        displayLabel.adjustsFontSizeToFitWidth = true
        displayLabel.textAlignment = .right

        expressionLabel.textColor = UIColor(white: 0.48, alpha: 1)
        expressionLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        expressionLabel.textAlignment = .right

        angleLabel.textColor = .systemOrange
        angleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        angleLabel.text = "DEG"
    }

    private func rebuildLayout() {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        grid.removeFromSuperview()

        let landscape = view.bounds.width > view.bounds.height * 1.15
        let root = UIStackView()
        root.axis = .vertical
        root.spacing = landscape ? 5 : 10
        root.translatesAutoresizingMaskIntoConstraints = false

        let meta = UIStackView(arrangedSubviews: [angleLabel, UIView(), expressionLabel])
        meta.axis = .horizontal
        meta.alignment = .center
        meta.heightAnchor.constraint(equalToConstant: 22).isActive = true

        root.addArrangedSubview(meta)
        root.addArrangedSubview(displayLabel)

        grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = landscape ? 5 : 10
        grid.distribution = .fillEqually
        root.addArrangedSubview(grid)
        view.addSubview(root)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: landscape ? 8 : 8),
            root.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: landscape ? -8 : -8),
            root.topAnchor.constraint(equalTo: g.topAnchor, constant: 4),
            root.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -4),
            displayLabel.heightAnchor.constraint(equalToConstant: landscape ? 62 : 116)
        ])

        landscape ? buildLandscape() : buildPortrait()
    }

    private func buildPortrait() {
        addRow(["AC","±","%","÷"])
        addRow(["7","8","9","×"])
        addRow(["4","5","6","−"])
        addRow(["1","2","3","+"])
        let row = UIStackView(); row.axis = .horizontal; row.spacing = 10; row.distribution = .fillEqually
        let zero = makeButton("0", .number)
        let dot = makeButton(".", .number)
        let eq = makeButton("=", .operator)
        row.addArrangedSubview(zero); row.addArrangedSubview(dot); row.addArrangedSubview(eq)
        zero.widthAnchor.constraint(equalTo: dot.widthAnchor, multiplier: 2.04).isActive = true
        grid.addArrangedSubview(row)
    }

    private func buildLandscape() {
        let scientific: [[String]] = [
            ["(", ")", "MC", "M+", "M−"],
            ["√", "∛", "MR", "π", "e"],
            ["sin", "asin", "cos", "acos", "DEG"],
            ["tan", "atan", "sinh", "cosh", "RAD"],
            ["tanh", "ln", "log", "exp", "!"],
            ["x²", "x³", "xʸ", "1/x", "abs"]
        ]
        let standard = [
            ["AC","±","%","÷"],
            ["7","8","9","×"],
            ["4","5","6","−"],
            ["1","2","3","+"],
            ["0",".","=",""],
            ["","","",""]
        ]

        for r in 0..<6 {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 5
            row.distribution = .fillEqually
            for title in scientific[r] { row.addArrangedSubview(makeButton(title, scientific: true)) }
            for title in standard[r] {
                row.addArrangedSubview(title.isEmpty ? UIView() : makeButton(title, scientific: false))
            }
            grid.addArrangedSubview(row)
        }
    }

    private func addRow(_ titles: [String]) {
        let row = UIStackView(); row.axis = .horizontal; row.spacing = 10; row.distribution = .fillEqually
        for title in titles { row.addArrangedSubview(makeButton(title, .standard)) }
        grid.addArrangedSubview(row)
    }

    private enum Kind { case standard, number, op, utility, scientific }

    private func makeButton(_ title: String, _ kind: Kind = .standard, scientific: Bool = false) -> UIButton {
        let resolved: Kind
        if scientific {
            resolved = ["AC","±","DEG","RAD"].contains(title) ? .utility :
                (["×","−","+","÷","=","%"].contains(title) ? .op : .scientific)
        } else {
            resolved = ["×","−","+","÷","="].contains(title) ? .op :
                (["AC","±","%"].contains(title) ? .utility : kind)
        }
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: scientific ? 15.5 : (resolved == .op ? 29 : 28), weight: .medium)
        b.setTitleColor(resolved == .utility ? .black : .white, for: .normal)
        b.backgroundColor = resolved == .op ? .systemOrange : (resolved == .utility ? UIColor(white: 0.72, alpha: 1) : UIColor(white: 0.16, alpha: 1))
        b.layer.cornerRadius = 999
        b.clipsToBounds = true
        b.addAction(UIAction { [weak self] _ in self?.tap(title) }, for: .touchUpInside)
        return b
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
        case "sin","cos","tan","sinh","cosh","tanh","ln","log","exp","abs": engine.scientific(title)
        case "asin","acos","atan": engine.scientific(title)
        case "√": engine.scientific("sqrt")
        case "∛": engine.scientific("cbrt")
        case "π","e": engine.constant(title)
        case "!": engine.scientific("factorial")
        case "x²": engine.power("2")
        case "x³": engine.power("3")
        case "xʸ": engine.setOperator("^")
        case "1/x": engine.scientific("reciprocal")
        case "MC": engine.memoryClear()
        case "M+": engine.memoryAdd()
        case "M−": engine.memorySubtract()
        case "MR": engine.memoryRecall()
        default: break
        }
        angleLabel.text = engine.angleMode == .deg ? "DEG" : "RAD"
        displayLabel.text = engine.display
        expressionLabel.text = engine.expression
    }
}
