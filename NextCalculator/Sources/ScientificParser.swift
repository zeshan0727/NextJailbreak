import Foundation

final class ScientificParser {
    enum ParseError: Error { case invalid, divisionByZero, domain }

    private let source: String
    private var i = 0
    private var angleMode: CalculatorEngine.AngleMode = .deg

    init(_ source: String, angleMode: CalculatorEngine.AngleMode) {
        self.source = source.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
        self.angleMode = angleMode
    }

    func evaluate() throws -> Double {
        i = 0
        let value = try parseExpression()
        skipSpaces()
        guard i == source.count else { throw ParseError.invalid }
        guard value.isFinite else { throw ParseError.domain }
        return value
    }

    private func parseExpression() throws -> Double {
        var v = try parseTerm()
        while true {
            skipSpaces()
            guard let c = peek(), c == "+" || c == "-" else { return v }
            i += 1
            let r = try parseTerm()
            v = c == "+" ? v + r : v - r
        }
    }

    private func parseTerm() throws -> Double {
        var v = try parsePower()
        while true {
            skipSpaces()
            guard let c = peek(), c == "*" || c == "/" else { return v }
            i += 1
            let r = try parsePower()
            if c == "/" && r == 0 { throw ParseError.divisionByZero }
            v = c == "*" ? v * r : v / r
        }
    }

    private func parsePower() throws -> Double {
        var v = try parseUnary()
        skipSpaces()
        if peek() == "^" {
            i += 1
            let r = try parsePower()
            v = Foundation.pow(v, r)
        }
        return v
    }

    private func parseUnary() throws -> Double {
        skipSpaces()
        if peek() == "-" { i += 1; return -(try parseUnary()) }
        if peek() == "+" { i += 1; return try parseUnary() }
        return try parsePostfix()
    }

    private func parsePostfix() throws -> Double {
        var v = try parsePrimary()
        while true {
            skipSpaces()
            if peek() == "%" {
                i += 1
                v /= 100
            } else if peek() == "!" {
                i += 1
                v = try factorial(v)
            } else {
                return v
            }
        }
    }

    private func parsePrimary() throws -> Double {
        skipSpaces()
        if peek() == "(" {
            i += 1
            let v = try parseExpression()
            skipSpaces()
            guard peek() == ")" else { throw ParseError.invalid }
            i += 1
            return v
        }

        if let ident = readIdentifier() {
            if ident == "pi" { return Double.pi }
            if ident == "e" { return Foundation.exp(1) }
            if ident == "Ans" { return 0 }

            skipSpaces()
            if peek() != "(" { throw ParseError.invalid }
            i += 1
            let x = try parseExpression()
            skipSpaces()
            guard peek() == ")" else { throw ParseError.invalid }
            i += 1
            return try function(ident, x)
        }

        return try readNumber()
    }

    private func function(_ name: String, _ x: Double) throws -> Double {
        let radians = angleMode == .deg ? x * Double.pi / 180 : x
        switch name.lowercased() {
        case "sin": return Foundation.sin(radians)
        case "cos": return Foundation.cos(radians)
        case "tan":
            let c = Foundation.cos(radians)
            if abs(c) < 1e-12 { throw ParseError.domain }
            return Foundation.tan(radians)
        case "asin":
            guard x >= -1 && x <= 1 else { throw ParseError.domain }
            let r = Foundation.asin(x)
            return angleMode == .deg ? r * 180 / Double.pi : r
        case "acos":
            guard x >= -1 && x <= 1 else { throw ParseError.domain }
            let r = Foundation.acos(x)
            return angleMode == .deg ? r * 180 / Double.pi : r
        case "atan":
            let r = Foundation.atan(x)
            return angleMode == .deg ? r * 180 / Double.pi : r
        case "sinh": return Foundation.sinh(radians)
        case "cosh": return Foundation.cosh(radians)
        case "tanh": return Foundation.tanh(radians)
        case "ln":
            guard x > 0 else { throw ParseError.domain }
            return Foundation.log(x)
        case "log":
            guard x > 0 else { throw ParseError.domain }
            return Foundation.log10(x)
        case "exp": return Foundation.exp(x)
        case "sqrt":
            guard x >= 0 else { throw ParseError.domain }
            return Foundation.sqrt(x)
        case "cbrt": return Foundation.pow(x, 1.0 / 3.0)
        case "abs": return Foundation.fabs(x)
        default: throw ParseError.invalid
        }
    }

    private func factorial(_ x: Double) throws -> Double {
        guard x >= 0, x.rounded() == x, x <= 170 else { throw ParseError.domain }
        if x == 0 { return 1 }
        var r = 1.0
        for n in 1...Int(x) { r *= Double(n) }
        return r
    }

    private func readNumber() throws -> Double {
        skipSpaces()
        let start = i
        var dotSeen = false
        var expSeen = false
        var expSignAllowed = false
        while i < source.count {
            let c = char(at: i)
            if c.isNumber {
                i += 1; expSignAllowed = false
            } else if c == "." && !dotSeen && !expSeen {
                dotSeen = true; i += 1
            } else if (c == "e" || c == "E") && !expSeen {
                expSeen = true; expSignAllowed = true; i += 1
            } else if (c == "+" || c == "-") && expSignAllowed {
                expSignAllowed = false; i += 1
            } else { break }
        }
        guard i > start, let v = Double(sourceSlice(start, i)) else { throw ParseError.invalid }
        return v
    }

    private func readIdentifier() -> String? {
        skipSpaces()
        let start = i
        while i < source.count {
            let c = char(at: i)
            if c.isLetter { i += 1 } else { break }
        }
        return i > start ? sourceSlice(start, i) : nil
    }

    private func skipSpaces() { while i < source.count && char(at: i).isWhitespace { i += 1 } }
    private func peek() -> Character? { i < source.count ? char(at: i) : nil }
    private func char(at index: Int) -> Character {
        source[source.index(source.startIndex, offsetBy: index)]
    }
    private func sourceSlice(_ start: Int, _ end: Int) -> String {
        String(source[source.index(source.startIndex, offsetBy: start)..<source.index(source.startIndex, offsetBy: end)])
    }
}
