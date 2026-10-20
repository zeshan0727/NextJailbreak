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
        guard !error else { clearAll() ; return }
        if didEvaluate { expression = ""; display = "0"; didEvaluate = false }
        if !typing || display == "0" {
            display = digit
            typing = true
        } else if digit != "0" || display != "0" {
            display.append(digit)
        }
        normalizeDisplay()
    }

    func decimal() {
        guard !error else { clearAll(); return }
        if didEvaluate { expression = ""; display = "0"; didEvaluate = false }
        if !typing { display = "0."; typing = true }
        else if !display.contains(".") { display.append(".") }
    }

    func toggleSign() {
        guard let v = Double(display), v != 0 else { return }
        display = format(-v)
    }

    func percent() {
        guard let v = Double(display) else { return }
        if let op = lastOperator, let base = lastBaseValue() {
            switch op {
            case "+", "-": display = format(base * v / 100)
            case "*", "/": display = format(v / 100)
            default: display = format(v / 100)
            }
        } else { display = format(v / 100) }
        typing = true
    }

    func setOperator(_ op: String) {
        guard !error else { clearAll(); return }
        let v = Double(display) ?? 0
        if lastOperator != nil && typing { applyPending(with: v) }
        else if !expression.isEmpty && !typing { }
        else if !didEvaluate { expression = format(v) }

        if expression.isEmpty { expression = format(v) }
        expression += " (op) "
        lastOperator = op
        lastOperand = v
        typing = false
        didEvaluate = false
    }

    func equals() {
        guard !error else { return }
        if let op = lastOperator, let v = Double(display) {
            if !expression.isEmpty {
                expression += format(v)
            }
            evaluateCurrent()
            lastOperand = v
            lastOperator = op
        } else if didEvaluate {
            let op = lastOperator ?? ""
            if !op.isEmpty {
                let a = Double(display) ?? 0
                if op == "+" { display = format(a + lastOperand) }
                else if op == "-" { display = format(a - lastOperand) }
                else if op == "*" { display = format(a * lastOperand) }
                else if op == "/" {
                    if lastOperand == 0 { showError(); return }
                    display = format(a / lastOperand)
                }
            }
        }
        typing = false
        didEvaluate = true
    }

    func clear() {
        if display != "0" { display = "0"; typing = false }
        else { clearAll() }
    }

    func clearAll() {
        expression = ""; display = "0"; typing = false
        lastOperator = nil; lastOperand = 0; didEvaluate = false; error = false
    }

    func scientific(_ name: String, inverse: Bool = false) {
        guard let v = Double(display), !error else { return }
        let fn: String
        if inverse {
            switch name {
            case "sin": fn = "asin"; case "cos": fn = "acos"; case "tan": fn = "atan"
            default: fn = name
            }
        } else { fn = name }
        let source = "(fn)((format(v)))"
        do {
            display = format(try ScientificParser(source, angleMode: angleMode).evaluate())
            typing = true; didEvaluate = false
        } catch { showError() }
    }

    func constant(_ name: String) {
        if name == "π" { display = format(Double.pi) }
        else { display = format(exp(1)) }
        typing = true; didEvaluate = false
    }

    func power(_ exponent: String) {
        guard let v = Double(display) else { return }
        do { display = format(try ScientificParser("(format(v))^(exponent)", angleMode: angleMode).evaluate()); typing = true }
        catch { showError() }
    }

    func openParen() {
        if typing { expression += " (format(Double(display) ?? 0)) × "; display = "0"; typing = false }
        expression += "("
    }

    func closeParen() {
        if typing { expression += format(Double(display) ?? 0); typing = false }
        expression += ")"
    }

    func evaluateExpression() {
        guard !expression.isEmpty else { return }
        var src = expression
        if typing { src += format(Double(display) ?? 0) }
        do {
            display = format(try ScientificParser(src, angleMode: angleMode).evaluate())
            didEvaluate = true; typing = false; lastOperator = nil
        } catch { showError() }
    }

    func setAngleMode() { angleMode = angleMode == .deg ? .rad : .deg }

    func memoryClear() { memory = 0 }
    func memoryAdd() { memory += Double(display) ?? 0 }
    func memorySubtract() { memory -= Double(display) ?? 0 }
    func memoryRecall() { display = format(memory); typing = true }

    private func applyPending(with v: Double) {
        if let op = lastOperator {
            var base = extractBase()
            switch op {
            case "+": base += v
            case "-": base -= v
            case "*": base *= v
            case "/":
                if v == 0 { showError(); return }
                base /= v
            default: break
            }
            expression = format(base)
            display = format(base)
        }
    }

    private func evaluateCurrent() {
        var src = expression
        if typing { src += format(Double(display) ?? 0) }
        do {
            display = format(try ScientificParser(src, angleMode: angleMode).evaluate())
        } catch { showError() }
    }

    private func extractBase() -> Double {
        let parts = expression.split(separator: " ")
        if let first = parts.first { return Double(first) ?? (Double(display) ?? 0) }
        return Double(display) ?? 0
    }

    private func lastBaseValue() -> Double? { extractBase() }

    private func showError() {
        display = "Error"; error = true; typing = false
    }

    private func normalizeDisplay() {
        if display.count > 18, let v = Double(display) { display = format(v) }
    }

    func format(_ v: Double) -> String {
        guard v.isFinite else { return "Error" }
        let av = abs(v)
        if av != 0 && (av >= 1e12 || av < 1e-9) {
            return String(format: "%.10g", locale: Locale(identifier: "en_US_POSIX"), v)
        }
        let s = String(format: "%.12f", locale: Locale(identifier: "en_US_POSIX"), v)
        var trimmed = s
        while trimmed.last == "0" { trimmed.removeLast() }
        if trimmed.last == "." { trimmed.removeLast() }
        return trimmed == "-0" ? "0" : trimmed
    }
}
