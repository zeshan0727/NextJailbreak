import Foundation

final class CalculatorEngine {
    enum AngleMode { case deg, rad }

    private(set) var expression = ""
    private(set) var display = "0"
    private(set) var memory = 0.0
    private(set) var angleMode: AngleMode = .deg

    private var typing = false
    private var lastOperator: String?
    private var lastOperand = 0.0
    private var didEvaluate = false
    private var error = false

    func inputDigit(_ digit: String) {
        guard !error else { clearAll(); inputDigit(digit); return }
        if didEvaluate { expression = ""; display = "0"; didEvaluate = false; lastOperator = nil }
        if !typing || display == "0" { display = digit; typing = true }
        else { display.append(digit) }
        normalizeDisplay()
    }

    func decimal() {
        guard !error else { clearAll(); decimal(); return }
        if didEvaluate { expression = ""; display = "0"; didEvaluate = false; lastOperator = nil }
        if !typing { display = "0."; typing = true }
        else if !display.contains(".") { display.append(".") }
    }

    func toggleSign() {
        guard let v = Double(display), v != 0, !error else { return }
        display = format(-v)
    }

    func percent() {
        guard let v = Double(display), !error else { return }
        if let op = lastOperator, let base = currentBaseValue() {
            switch op {
            case "+", "-": display = format(base * v / 100)
            default: display = format(v / 100)
            }
        } else { display = format(v / 100) }
        typing = true
    }

    func setOperator(_ op: String) {
        guard !error else { clearAll(); return }
        if didEvaluate {
            expression = display
            didEvaluate = false
            lastOperator = nil
            typing = true
        }

        if let pending = lastOperator, typing, let v = Double(display) {
            let base = currentBaseValue() ?? v
            let applied: Double
            switch pending {
            case "+": applied = base + v
            case "-": applied = base - v
            case "*": applied = base * v
            case "/":
                if v == 0 { showError(); return }
                applied = base / v
            case "^": applied = Foundation.pow(base, v)
            default: applied = v
            }
            display = format(applied)
            expression = format(applied)
        }

        expression = expression.trimmingCharacters(in: .whitespaces)
        if expression.isEmpty { expression = display }
        expression += " (op) "
        lastOperator = op
        lastOperand = Double(display) ?? 0
        typing = false
        didEvaluate = false
    }

    func equals() {
        guard !error else { return }
        guard let op = lastOperator else {
            if !expression.isEmpty { evaluateExpression() }
            return
        }

        if !didEvaluate {
            let operand = Double(display) ?? 0
            let base = currentBaseValue() ?? 0
            switch op {
            case "+": display = format(base + operand)
            case "-": display = format(base - operand)
            case "*": display = format(base * operand)
            case "/":
                if operand == 0 { showError(); return }
                display = format(base / operand)
            case "^": display = format(Foundation.pow(base, operand))
            default: break
            }
            lastOperand = operand
            didEvaluate = true
            typing = false
            expression = "(format(base)) (op) (format(operand))"
        } else {
            let a = Double(display) ?? 0
            switch op {
            case "+": display = format(a + lastOperand)
            case "-": display = format(a - lastOperand)
            case "*": display = format(a * lastOperand)
            case "/":
                if lastOperand == 0 { showError(); return }
                display = format(a / lastOperand)
            case "^": display = format(Foundation.pow(a, lastOperand))
            default: break
            }
        }
    }

    func clear() {
        if display != "0" && !error { display = "0"; typing = false }
        else { clearAll() }
    }

    func clearAll() {
        expression = ""; display = "0"; typing = false
        lastOperator = nil; lastOperand = 0; didEvaluate = false; error = false
    }

    func scientific(_ name: String) {
        guard let v = Double(display), !error else { return }
        let source: String
        switch name {
        case "factorial": source = "(format(v))!"
        case "reciprocal":
            guard v != 0 else { showError(); return }
            display = format(1 / v)
            typing = true
            didEvaluate = false
            return
        default: source = "(name)((format(v)))"
        }
        do {
            display = format(try ScientificParser(source, angleMode: angleMode).evaluate())
            typing = true
            didEvaluate = false
        } catch { showError() }
    }

    func constant(_ name: String) {
        display = name == "π" ? format(Double.pi) : format(Foundation.exp(1))
        typing = true; didEvaluate = false
    }

    func power(_ exponent: String) {
        guard Double(display) != nil else { return }
        do {
            display = format(try ScientificParser("(display)^(exponent)", angleMode: angleMode).evaluate())
            typing = true; didEvaluate = false
        } catch { showError() }
    }

    func openParen() {
        if typing {
            expression = expression.trimmingCharacters(in: .whitespaces)
            if !expression.isEmpty { expression += " × " }
            expression += "(display) × "
            display = "0"
            typing = false
        }
        expression += "("
    }

    func closeParen() {
        if typing {
            expression += display
            typing = false
        }
        expression += ")"
    }

    func evaluateExpression() {
        guard !expression.isEmpty else { return }
        var src = expression
        if typing { src += display }
        do {
            display = format(try ScientificParser(src, angleMode: angleMode).evaluate())
            didEvaluate = true
            typing = false
            lastOperator = nil
        } catch { showError() }
    }

    func setAngleMode() { angleMode = angleMode == .deg ? .rad : .deg }
    func memoryClear() { memory = 0 }
    func memoryAdd() { memory += Double(display) ?? 0 }
    func memorySubtract() { memory -= Double(display) ?? 0 }
    func memoryRecall() { display = format(memory); typing = true }

    private func currentBaseValue() -> Double? {
        let parts = expression.split(separator: " ")
        return parts.first.flatMap { Double($0) }
    }

    private func showError() { display = "Error"; error = true; typing = false }

    private func normalizeDisplay() {
        if display.count > 18, let v = Double(display) { display = format(v) }
    }

    func format(_ v: Double) -> String {
        guard v.isFinite else { return "Error" }
        let av = abs(v)
        if av != 0 && (av >= 1e12 || av < 1e-9) {
            return String(format: "%.10g", locale: Locale(identifier: "en_US_POSIX"), v)
        }
        var s = String(format: "%.12f", locale: Locale(identifier: "en_US_POSIX"), v)
        while s.last == "0" { s.removeLast() }
        if s.last == "." { s.removeLast() }
        return s == "-0" ? "0" : s
    }
}
