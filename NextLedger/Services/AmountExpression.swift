import Foundation

enum AmountExpression {
    static func evaluate(_ text: String) -> Decimal? {
        let cleaned = text.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        var numbers: [Decimal] = []
        var operators: [Character] = []
        var token = ""
        for character in cleaned {
            if "+-*/".contains(character), !token.isEmpty {
                guard let value = Decimal(string: token, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
                numbers.append(value)
                operators.append(character)
                token = ""
            } else {
                token.append(character)
            }
        }
        guard let last = Decimal(string: token, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        numbers.append(last)
        guard numbers.count == operators.count + 1 else { return nil }

        var collapsed = [numbers[0]]
        var additions: [Character] = []
        for index in operators.indices {
            let next = numbers[index + 1]
            switch operators[index] {
            case "*": collapsed[collapsed.count - 1] *= next
            case "/":
                guard next != 0 else { return nil }
                collapsed[collapsed.count - 1] /= next
            default:
                additions.append(operators[index])
                collapsed.append(next)
            }
        }
        var result = collapsed[0]
        for index in additions.indices {
            result = additions[index] == "+" ? result + collapsed[index + 1] : result - collapsed[index + 1]
        }
        return result
    }

    static func appending(_ symbol: String, to text: String) -> String {
        guard !text.isEmpty, let last = text.last, !" +−-×*/÷".contains(last) else { return text }
        return text + symbol
    }
}
