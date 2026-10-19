import SwiftUI

struct BalanceCard: View {
    @AppStorage(DeveloperLabKey.enabled) private var devEnabled = true
    @AppStorage(DeveloperLabKey.cardCornerRadius) private var devCornerRadius = 28.0
    let balance: Decimal
    let income: Decimal
    let expense: Decimal
    let loanMovements: [LoanNetMovement]
    let currencyCode: String
    let accountSummary: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("REMAINING ACCOUNT BALANCE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(DisplayFormat.currency(balance, code: currencyCode))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text(accountSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }

            HStack(spacing: 16) {
                BalanceMiniStat(
                    title: "Income",
                    value: income,
                    icon: "arrow.down.left",
                    currencyCode: currencyCode
                )
                BalanceMiniStat(
                    title: "Expenses",
                    value: expense,
                    icon: "arrow.up.right",
                    currencyCode: currencyCode
                )
                LoanMovementMiniStat(movements: loanMovements)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.balanceGradient)
        .clipShape(RoundedRectangle(cornerRadius: devEnabled ? CGFloat(devCornerRadius) : 28, style: .continuous))
        .developerSurface()
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 140, height: 140)
                .offset(x: 45, y: -55)
        }
        .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }
}

private struct LoanMovementMiniStat: View {
    let movements: [LoanNetMovement]

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "banknote.fill")
                .font(.caption.bold())
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                if movements.isEmpty {
                    Text("No net loan movement")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                } else {
                    ForEach(movements) { movement in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(movement.title)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.72))
                            Text(DisplayFormat.currency(
                                abs(movement.netAmount),
                                code: movement.currencyCode
                            ))
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BalanceMiniStat: View {
    let title: String
    let value: Decimal
    let icon: String
    let currencyCode: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.caption.bold())
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                Text(DisplayFormat.currency(value, code: currencyCode))
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TransactionRow: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage(DeveloperLabKey.enabled) private var devEnabled = true
    @AppStorage(DeveloperLabKey.density) private var devDensity = DeveloperDensity.standard.rawValue
    @AppStorage(DeveloperLabKey.transactionShowIcon) private var devShowIcon = true
    @AppStorage(DeveloperLabKey.transactionShowDate) private var devShowDate = true
    @AppStorage(DeveloperLabKey.transactionShowSecondary) private var devShowSecondary = true
    @AppStorage(DeveloperLabKey.transactionShowRunningBalance) private var devShowRunningBalance = true
    @AppStorage(DeveloperLabKey.transactionShowTransferSecondary) private var devShowTransferSecondary = true
    @AppStorage(DeveloperLabKey.transactionCompactRows) private var devCompactRows = false
    let transaction: LedgerTransaction
    var accountID: UUID? = nil

    var body: some View {
        HStack(spacing: effectiveCompactRow ? 9 : 13) {
            if !devEnabled || devShowIcon {
            Image(systemName: AppTheme.categoryIcon(transaction.category))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 42, height: 42)
                .background(
                    iconColor.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
            }

            VStack(alignment: .leading, spacing: effectiveCompactRow ? 2 : 4) {
                Text(primaryText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !devEnabled || devShowSecondary {
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if !devEnabled || devShowDate {
                    Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(amountText)
                    .font(.subheadline.bold())
                    .foregroundStyle(amountColor)
                if (!devEnabled || devShowTransferSecondary),
                   accountID == nil,
                   transaction.type == .transfer,
                   let destination = destinationAccount {
                    Text("IN +" + DisplayFormat.currency(
                        store.effectiveDestinationAmount(transaction),
                        code: destination.currencyCode
                    ))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.green)
                }
                if (!devEnabled || devShowRunningBalance),
                   let runningBalance = store.runningBalance(
                    for: transaction.id,
                    accountID: balanceAccountID
                ) {
                    Text("Balance " + DisplayFormat.currency(
                        runningBalance,
                        code: balanceAccount?.currencyCode ?? store.currencyCode
                    ))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
        .padding(.vertical, effectiveCompactRow ? 2 : 5)
        .accessibilityElement(children: .combine)
    }

    private var effectiveCompactRow: Bool {
        guard devEnabled else { return false }
        if devCompactRows { return true }
        return devDensity == DeveloperDensity.compact.rawValue
    }

    private var amountText: String {
        let incoming = transaction.type == .income || isDestinationTransfer
        let prefix = incoming ? "+" : "−"
        let value = isDestinationTransfer
            ? store.effectiveDestinationAmount(transaction)
            : transaction.amount
        let signed = prefix + DisplayFormat.currency(
            value,
            code: balanceAccount?.currencyCode ?? store.currencyCode
        )
        if transaction.type == .transfer {
            return (isDestinationTransfer ? "IN " : "OUT ") + signed
        }
        return (transaction.type == .income ? "IN " : "OUT ") + signed
    }

    private var isDestinationTransfer: Bool {
        transaction.type == .transfer &&
            accountID != nil &&
            transaction.destinationAccountID == accountID
    }

    private var balanceAccountID: UUID? {
        accountID ?? transaction.accountID
    }

    private var balanceAccount: LedgerAccount? {
        store.account(withID: balanceAccountID)
    }

    private var primaryText: String {
        if transaction.type == .transfer {
            return "\(sourceAccount?.name ?? "Account") → \(destinationAccount?.name ?? "Account")"
        }
        if let vendor = transaction.vendor, !vendor.isEmpty { return vendor }
        return transaction.category
    }

    private var secondaryText: String {
        if transaction.type == .transfer {
            return transaction.details.isEmpty ? "Transfer" : transaction.details
        }
        return [sourceAccount?.name, transaction.category]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var sourceAccount: LedgerAccount? {
        store.account(withID: transaction.accountID)
    }

    private var destinationAccount: LedgerAccount? {
        store.account(withID: transaction.destinationAccountID)
    }

    private var amountColor: Color {
        switch transaction.type {
        case .income:
            return AppTheme.green
        case .expense:
            return AppTheme.red
        case .transfer:
            return isDestinationTransfer ? AppTheme.green : AppTheme.red
        }
    }

    private var iconColor: Color {
        transaction.type == .transfer
            ? amountColor
            : AppTheme.categoryColor(transaction.category)
    }
}

struct EmptyLedgerView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.fill")
                .font(.system(size: 34))
                .foregroundStyle(AppTheme.purple.opacity(0.7))
                .frame(width: 72, height: 72)
                .background(AppTheme.purple.opacity(0.10), in: Circle())
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(36)
    }
}
