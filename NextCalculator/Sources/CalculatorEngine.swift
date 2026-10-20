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
        guard !error else {
            clearAll()
            inputDigit(digit)
            return
        }
        if didEvaluate {
            expression = ""
            display = "0"
            didEvaluate = false
            lastOperator = nil
        }
        if !typing || display == "0" {
            display = digit
            typing = true
        } else {
            display.append(digit)
        }
        normalizeDisplay()
    }

    func decimal() {
        guard !error else {
            clearAll()
            decimal()
            return
        }
        if didEvaluate {
            expression = ""
            display = "0"
            didEvaluate = false
            lastOperator = nil
        }
        if !typing {
            display = "0."
            typing = true
        } else if !display.contains(".") {
            display.append(".")
        }
    }

    func toggleSign() {
        guard let value = Double(display), value != 0, !error else { return }
        display = format(-value)
    }

    func percent() {
        guard let value = Double(display), !error else { return }
        if let op = lastOperator, let base = currentBaseValue() {
            switch op {
            case "+", "-":
                display = format(base * value / 100.0)
            default:
                display = format(value / 100.0)
            }
        } else {
            display = format(value / 100.0)
        }
        typing = true
    }

    func setOperator(_ op: String) {
        guard !error else {
            clearAll()
            return
        }

        if didEvaluate {
            expression = display
            didEvaluate = false
            lastOperator = nil
            typing = true
        }

        if lastOperator != nil && !typing {
            expression = String(expression.dropLast(3)) + " " + op + " "
            lastOperator = op
            lastOperand = Double(display) ?? 0
            return
        }

        if let pending = lastOperator, typing, let value = Double(display) {
            let base = currentBaseValue() ?? value
            let applied: Double
            switch pending {
            case "+": applied = base + value
            case "-": applied = base - value
            case "*": applied = base * value
            case "/":
                if value == 0 { showError(); return }
                applied = base / value
            case "^": applied = Foundation.pow(base, value)
            default: applied = value
            }
            display = format(applied)
            expression = format(applied)
        }

        expression = expression.trimmingCharacters(in: .whitespaces)
        if expression.isEmpty { expression = display }
        expression += " " + op + " "
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
            expression = format(base) + " " + op + " " + format(operand)
        } else {
            let current = Double(display) ?? 0
            switch op {
            case "+": display = format(current + lastOperand)
            case "-": display = format(current - lastOperand)
            case "*": display = format(current * lastOperand)
            case "/":
                if lastOperand == 0 { showError(); return }
                display = format(current / lastOperand)
            case "^": display = format(Foundation.pow(current, lastOperand))
            default: break
            }
        }
    }

    func clear() {
        if display != "0" && !error {
            display = "0"
            typing = false
        } else {
            clearAll()
        }
    }

    func clearAll() {
        expression = ""
        display = "0"
        typing = false
        lastOperator = nil
        lastOperand = 0
        didEvaluate = false
        error = false
    }

    func scientific(_ name: String) {
        guard let value = Double(display), !error else { return }

        if name == "factorial" {
            guard value >= 0, value.rounded() == value, value <= 170 else {
                showError()
                return
            }
            var result = 1.0
            if value > 0 {
                for n in 1...Int(value) { result *= Double(n) }
            }
            display = format(result)
            typing = true
            didEvaluate = false
            return
        }

        if name == "reciprocal" {
            guard value != 0 else {
                showError()
                return
            }
            display = format(1.0 / value)
            typing = true
            didEvaluate = false
            return
        }

        let source = name + "(" + format(value) + ")"
        do {
            display = format(try ScientificParser(source, angleMode: angleMode).evaluate())
            typing = true
            didEvaluate = false
        } catch {
            showError()
        }
    }

    func constant(_ name: String) {
        display = name == "π" ? format(Double.pi) : format(Foundation.exp(1))
        typing = true
        didEvaluate = false
    }

    func power(_ exponent: String) {
        guard Double(display) != nil else { return }
        let source = display + "^" + exponent
        do {
            display = format(try ScientificParser(source, angleMode: angleMode).evaluate())
            typing = true
            didEvaluate = false
        } catch {
            showError()
        }
    }

    func openParen() {
        if typing {
            expression = expression.trimmingCharacters(in: .whitespaces)
            if !expression.isEmpty { expression += " × " }
            expression += display + " × "
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
        var source = expression
        if typing { source += display }
        do {
            display = format(try ScientificParser(source, angleMode: angleMode).evaluate())
            didEvaluate = true
            typing = false
            lastOperator = nil
        } catch {
            showError()
        }
    }

    func setAngleMode(_ mode: AngleMode) {
        angleMode = mode
    }

    func memoryClear() { memory = 0 }
    func memoryAdd() { memory += Double(display) ?? 0 }
    func memorySubtract() { memory -= Double(display) ?? 0 }
    func memoryRecall() {
        display = format(memory)
        typing = true
    }

    private func currentBaseValue() -> Double? {
        let parts = expression.split(separator: " ")
        return parts.first.flatMap { Double($0) }
    }

    private func showError() {
        display = "Error"
        error = true
        typing = false
    }

    private func normalizeDisplay() {
        if display.count > 18, let value = Double(display) {
            display = format(value)
        }
    }

    func format(_ value: Double) -> String {
        guard value.isFinite else { return "Error" }
        let absolute = abs(value)
        if absolute != 0 && (absolute >= 1e12 || absolute < 1e-9) {
            return String(format: "%.10g", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        var result = String(format: "%.12f", locale: Locale(identifier: "en_US_POSIX"), value)
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result == "-0" ? "0" : result
    }
}
