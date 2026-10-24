import SwiftUI

struct ContentView: View {
    @StateObject private var gameManager = GameManager()
    @State private var path = NavigationPath()
    @State private var showExitConfirmation = false
    @State private var showPersistenceErrorAlert = false
    @State private var persistenceErrorMessage = ""
    
    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .environmentObject(gameManager)
                .navigationDestination(for: Screen.self) { screen in
                    switch screen {
                    case .game:
                        GameView(showExitConfirmation: $showExitConfirmation)
                            .environmentObject(gameManager)
                    case .settings:
                        SettingsView()
                            .environmentObject(gameManager)
                    }
                }
                .alert("Error", isPresented: $showPersistenceErrorAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(persistenceErrorMessage)
                }
                .confirmationDialog("Exit current game? Unsaved progress will be lost.", isPresented: $showExitConfirmation, titleVisibility: .visible) {
                    Button("Exit", role: .destructive) {
                        gameManager.resetGame()
                        path.removeLast(path.count)
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .onReceive(gameManager.$persistenceError) { error in
                    if let error = error {
                        persistenceErrorMessage = error.localizedDescription
                        showPersistenceErrorAlert = true
                        gameManager.clearPersistenceError()
                    }
                }
        }
    }
}

enum Screen: Hashable {
    case game
    case settings
}

struct HomeView: View {
    @EnvironmentObject private var gameManager: GameManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isNavigating = false
    
    var body: some View {
        VStack(spacing: 40) {
            Text("Solitaire")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 60)
            Spacer()
            VStack(spacing: 24) {
                Button(action: {
                    gameManager.startNewGame()
                    isNavigating = true
                }) {
                    Text("New Game")
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .accessibilityLabel("Start a new game")
                .accessibilityAddTraits(.isButton)
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .padding(.horizontal)
                .disabled(isNavigating)
                
                Button(action: {
                    if gameManager.canResume {
                        gameManager.loadSavedGame()
                        isNavigating = true
                    }
                }) {
                    Text("Resume Game")
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(gameManager.canResume ? Color.accentColor : Color.gray.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .accessibilityLabel(gameManager.canResume ? "Resume saved game" : "No saved game available")
                .accessibilityAddTraits(.isButton)
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(!gameManager.canResume || isNavigating)
                
                NavigationLink("Settings", value: Screen.settings)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .accessibilityLabel("Open settings")
                    .accessibilityAddTraits(.isButton)
                    .padding(.horizontal)
            }
            Spacer()
        }
        .navigationDestination(isPresented: $isNavigating) {
            GameView(showExitConfirmation: .constant(false))
                .environmentObject(gameManager)
        }
    }
}

struct GameView: View {
    @EnvironmentObject private var gameManager: GameManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showExitConfirmation: Bool
    @State private var showUndoDisabledAlert = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button(action: {
                    if gameManager.canUndo {
                        withAnimation(reduceMotion ? nil : .easeInOut) {
                            gameManager.undoMove()
                        }
                    } else {
                        showUndoDisabledAlert = true
                    }
                }) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 70)
                        .padding(8)
                        .background(gameManager.canUndo ? Color.accentColor : Color.gray.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(!gameManager.canUndo)
                .accessibilityLabel(gameManager.canUndo ? "Undo last move" : "Undo not available")
                
                Button(action: {
                    showExitConfirmation = true
                }) {
                    Label("Menu", systemImage: "list.bullet")
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 70)
                        .padding(8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .accessibilityLabel("Return to menu")
                
                Spacer()
                
                Button(action: {
                    withAnimation(reduceMotion ? nil : .easeInOut) {
                        gameManager.startNewGame()
                    }
                }) {
                    Label("Restart", systemImage: "arrow.clockwise")
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 70)
                        .padding(8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .accessibilityLabel("Restart current game")
            }
            .padding(.horizontal)
            
            CardLayoutView()
                .environmentObject(gameManager)
                .padding(.horizontal)
                .padding(.bottom)
        }
        .alert("Undo not available", isPresented: $showUndoDisabledAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("There are no moves to undo.")
        }
        .navigationBarBackButtonHidden(true)
    }
}

struct CardLayoutView: View {
    @EnvironmentObject private var gameManager: GameManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOverPile: PileType? = nil
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(PileType.foundationPiles, id: \.self) { pileType in
                        PileView(pileType: pileType)
                            .environmentObject(gameManager)
                            .frame(width: geo.size.width / 7 - 10, height: geo.size.width / 7 * 1.4)
                    }
                    Spacer()
                    StockWasteView()
                        .environmentObject(gameManager)
                        .frame(width: geo.size.width / 7 - 10, height: geo.size.width / 7 * 1.4)
                }
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { index in
                        PileView(pileType: .tableau(index))
                            .environmentObject(gameManager)
                            .frame(width: geo.size.width / 7 - 10, height: geo.size.height * 0.5)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PileView: View {
    @EnvironmentObject private var gameManager: GameManager
    let pileType: PileType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary, lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(UIColor.systemBackground))
                )
                .accessibilityHidden(true)
            
            if let pile = gameManager.piles[pileType], !pile.cards.isEmpty {
                pileCardsView(pile.cards)
            } else {
                Text(pileType.emptyLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel(pileType.accessibilityEmptyLabel)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pileType.accessibilityLabel(cardCount: gameManager.piles[pileType]?.cards.count ?? 0))
        .onDrop(of: [.utf8PlainText], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }
    
    @ViewBuilder
    private func pileCardsView(_ cards: [Card]) -> some View {
        switch pileType {
        case .foundation:
            if let card = cards.last {
                CardView(card: card, faceUp: true)
                    .environmentObject(gameManager)
                    .transition(.opacity)
            }
        case .tableau(let index):
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .center, spacing: -40) {
                    ForEach(cards) { card in
                        CardView(card: card, faceUp: card.isFaceUp)
                            .environmentObject(gameManager)
                            .offset(y: card.isFaceUp ? 0 : 10)
                            .zIndex(Double(card.rank.rawValue))
                            .onDrag {
                                if gameManager.canDrag(card: card, from: pileType) {
                                    return NSItemProvider(object: card.id.uuidString as NSString)
                                }
                                return NSItemProvider()
                            }
                    }
                }
                .padding(.vertical, 40)
            }
        case .stock, .waste:
            if let card = cards.last {
                CardView(card: card, faceUp: pileType == .waste)
                    .environmentObject(gameManager)
                    .onTapGesture {
                        if pileType == .stock {
                            withAnimation(reduceMotion ? nil : .easeInOut) {
                                gameManager.drawFromStock()
                            }
                        }
                    }
                    .accessibilityAddTraits(pileType == .stock ? .isButton : [])
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { nsString, _ in
                    if let idString = nsString as? NSString, let uuid = UUID(uuidString: idString as String) {
                        DispatchQueue.main.async {
                            withAnimation(reduceMotion ? nil : .easeInOut) {
                                gameManager.handleDrop(cardID: uuid, to: pileType)
                            }
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}

struct StockWasteView: View {
    @EnvironmentObject private var gameManager: GameManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary, lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.systemBackground)))
                    .frame(width: 60, height: 90)
                    .accessibilityLabel("Stock pile")
                    .accessibilityAddTraits(.isButton)
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : .easeInOut) {
                            gameManager.drawFromStock()
                        }
                    }
                if let topCard = gameManager.piles[.stock]?.cards.last {
                    CardView(card: topCard, faceUp: false)
                        .environmentObject(gameManager)
                        .frame(width: 60, height: 90)
                }
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary, lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.systemBackground)))
                    .frame(width: 60, height: 90)
                    .accessibilityLabel("Waste pile")
                if let topCard = gameManager.piles[.waste]?.cards.last {
                    CardView(card: topCard, faceUp: true)
                        .environmentObject(gameManager)
                        .frame(width: 60, height: 90)
                        .onDrag {
                            NSItemProvider(object: topCard.id.uuidString as NSString)
                        }
                }
            }
        }
    }
}

struct CardView: View {
    @EnvironmentObject private var gameManager: GameManager
    let card: Card
    let faceUp: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(faceUp ? Color.white : Color.red.opacity(0.8))
                .shadow(radius: 2)
            if faceUp {
                VStack(alignment: .leading) {
                    Text(card.rank.display)
                        .font(.caption.bold())
                        .foregroundColor(card.suit.color)
                        .padding(4)
                    Spacer()
                    Text(card.suit.symbol)
                        .font(.title)
                        .foregroundColor(card.suit.color)
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red)
                    .opacity(0.8)
            }
        }
        .frame(width: 60, height: 90)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(faceUp ? card.accessibilityLabel : "Face down card")
        .accessibilityAddTraits(.isButton)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var gameManager: GameManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    var body: some View {
        Form {
            Section(header: Text("Sound")) {
                Toggle("Sound Effects", isOn: $gameManager.settings.soundEffects)
            }
            Section(header: Text("Animations")) {
                Toggle("Animations", isOn: $gameManager.settings.animations)
            }
            Section(header: Text("Accessibility")) {
                Toggle("Reduce Motion", isOn: $gameManager.settings.reduceMotion)
            }
            Section {
                Button("Back to Home") {
                    dismiss()
                }
                .accessibilityLabel("Return to home screen")
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Models and Game Logic

final class GameManager: ObservableObject {
    @Published var piles: [PileType: Pile] = [:]
    @Published var settings = Settings()
    @Published var persistenceError: Error? = nil
    private var undoStack: [[PileType: Pile]] = []
    private let saveKey = "SolitaireSavedGame"
    private var isLoading = false
    
    var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    var canResume: Bool {
        UserDefaults.standard.data(forKey: saveKey) != nil
    }
    
    init() {
        if !loadSavedGame() { startNewGame() }
    }
    
    func startNewGame() {
        undoStack.removeAll()
        piles = GameLogic.newGamePiles()
        saveGame()
    }
    
    func resetGame() {
        undoStack.removeAll()
        piles.removeAll()
        saveGame()
    }
    
    func loadSavedGame() -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        defer { isLoading = false }
        guard let data = UserDefaults.standard.data(forKey: saveKey) else { return false }
        do {
            let saved = try JSONDecoder().decode([PileType: Pile].self, from: data)
            piles = saved
            undoStack.removeAll()
            return true
        } catch {
            persistenceError = error
            return false
        }
    }
    
    func saveGame() {
        do {
            let data = try JSONEncoder().encode(piles)
            UserDefaults.standard.set(data, forKey: saveKey)
        } catch {
            persistenceError = error
        }
    }
    
    func clearPersistenceError() {
        persistenceError = nil
    }
    
    func undoMove() {
        guard let last = undoStack.popLast() else { return }
        piles = last
        saveGame()
    }
    
    func canDrag(card: Card, from pileType: PileType) -> Bool {
        guard let pile = piles[pileType] else { return false }
        if pileType.isTableau {
            // Only allow dragging face-up cards and all cards below it
            guard let index = pile.cards.firstIndex(of: card), pile.cards[index].isFaceUp else { return false }
            return true
        } else if pileType == .waste {
            // Only top card of waste can be dragged
            return pile.cards.last == card
        }
        return false
    }
    
    func handleDrop(cardID: UUID, to destination: PileType) {
        guard let sourcePileType = piles.first(where: { $0.value.cards.contains(where: { $0.id == cardID }) })?.key else { return }
        guard let sourcePile = piles[sourcePileType] else { return }
        guard let cardIndex = sourcePile.cards.firstIndex(where: { $0.id == cardID }) else { return }
        let movingCards = Array(sourcePile.cards[cardIndex...])
        
        if GameLogic.isValidMove(cards: movingCards, from: sourcePileType, to: destination, piles: piles) {
            undoStack.append(piles)
            var newPiles = piles
            newPiles[sourcePileType]?.cards.removeLast(movingCards.count)
            newPiles[destination]?.cards.append(contentsOf: movingCards)
            // Flip top card of tableau if needed
            if sourcePileType.isTableau, let lastCard = newPiles[sourcePileType]?.cards.last, !lastCard.isFaceUp {
                newPiles[sourcePileType]?.cards[newPiles[sourcePileType]!.cards.count - 1].isFaceUp = true
            }
            piles = newPiles
            saveGame()
            checkWinCondition()
        } else {
            // Invalid move feedback
            // Could add animation or haptic feedback here
        }
    }
    
    func drawFromStock() {
        guard var stockPile = piles[.stock], !stockPile.cards.isEmpty else {
            // Reset stock from waste
            if let wastePile = piles[.waste], !wastePile.cards.isEmpty {
                undoStack.append(piles)
                piles[.stock]?.cards = wastePile.cards.reversed().map { Card(id: $0.id, suit: $0.suit, rank: $0.rank, isFaceUp: false) }
                piles[.waste]?.cards.removeAll()
                saveGame()
            }
            return
        }
        undoStack.append(piles)
        var newStock = stockPile.cards
        let drawCount = min(3, newStock.count)
        let drawnCards = newStock.suffix(drawCount).map { Card(id: $0.id, suit: $0.suit, rank: $0.rank, isFaceUp: true) }
        newStock.removeLast(drawCount)
        piles[.stock]?.cards = newStock
        piles[.waste]?.cards.append(contentsOf: drawnCards)
        saveGame()
    }
    
    private func checkWinCondition() {
        let allFoundationsComplete = PileType.foundationPiles.allSatisfy { pileType in
            guard let pile = piles[pileType] else { return false }
            return pile.cards.count == 13
        }
        if allFoundationsComplete {
            // Could add win alert or animation
        }
    }
}

struct Settings: Codable {
    var soundEffects: Bool = true
    var animations: Bool = true
    var reduceMotion: Bool = false
}

struct Card: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let suit: Suit
    let rank: Rank
    var isFaceUp: Bool
    
    var accessibilityLabel: String {
        "\(rank.display) of \(suit.name)"
    }
}

enum Suit: String, Codable, CaseIterable {
    case hearts, diamonds, clubs, spades
    
    var symbol: String {
        switch self {
        case .hearts: return "♥️"
        case .diamonds: return "♦️"
        case .clubs: return "♣️"
        case .spades: return "♠️"
        }
    }
    
    var color: Color {
        switch self {
        case .hearts, .diamonds: return .red
        case .clubs, .spades: return .black
        }
    }
    
    var name: String {
        rawValue.capitalized
    }
}

enum Rank: Int, Codable, CaseIterable {
    case ace = 1, two, three, four, five, six, seven, eight, nine, ten, jack, queen, king
    
    var display: String {
        switch self {
        case .ace: return "A"
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        default: return String(rawValue)
        }
    }
}

struct Pile: Codable, Equatable, Hashable {
    var cards: [Card]
}

enum PileType: Codable, Hashable {
    case stock
    case waste
    case foundation(Int) // 0 to 3
    case tableau(Int) // 0 to 6
    
    static let foundationPiles: [PileType] = [.foundation(0), .foundation(1), .foundation(2), .foundation(3)]
    static let tableauPiles: [PileType] = (0..<7).map { .tableau($0) }
    
    var isTableau: Bool {
        if case .tableau = self { return true }
        return false
    }
    
    var emptyLabel: String {
        switch self {
        case .stock: return "Stock"
        case .waste: return "Waste"
        case .foundation: return "Foundation"
        case .tableau: return ""
        }
    }
    
    func accessibilityLabel(cardCount: Int) -> String {
        switch self {
        case .stock:
            return "Stock pile with \(cardCount) cards"
        case .waste:
            return "Waste pile with \(cardCount) cards"
        case .foundation(let index):
            return "Foundation pile \(index + 1) with \(cardCount) cards"
        case .tableau(let index):
            return "Tableau pile \(index + 1) with \(cardCount) cards"
        }
    }
    
    var accessibilityEmptyLabel: String {
        switch self {
        case .stock: return "Empty stock pile"
        case .waste: return "Empty waste pile"
        case .foundation(let index): return "Empty foundation pile \(index + 1)"
        case .tableau(let index): return "Empty tableau pile \(index + 1)"
        }
    }
}

enum GameLogic {
    static func newGamePiles() -> [PileType: Pile] {
        var deck = createDeck()
        deck.shuffle()
        var piles: [PileType: Pile] = [:]
        
        // Stock pile starts empty, will fill after dealing tableau
        piles[.stock] = Pile(cards: [])
        piles[.waste] = Pile(cards: [])
        
        // Foundation piles start empty
        for i in 0..<4 {
            piles[.foundation(i)] = Pile(cards: [])
        }
        
        // Tableau piles
        for i in 0..<7 {
            var cards: [Card] = []
            for j in 0...i {
                var card = deck.removeFirst()
                card.isFaceUp = (j == i)
                cards.append(card)
            }
            piles[.tableau(i)] = Pile(cards: cards)
        }
        
        // Remaining cards go to stock
        piles[.stock]?.cards = deck.map { Card(id: $0.id, suit: $0.suit, rank: $0.rank, isFaceUp: false) }
        
        return piles
    }
    
    static func createDeck() -> [Card] {
        var deck: [Card] = []
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                deck.append(Card(id: UUID(), suit: suit, rank: rank, isFaceUp: false))
            }
        }
        return deck
    }
    
    static func isValidMove(cards: [Card], from source: PileType, to destination: PileType, piles: [PileType: Pile]) -> Bool {
        guard !cards.isEmpty else { return false }
        let firstCard = cards.first!
        switch destination {
        case .foundation(let index):
            guard cards.count == 1 else { return false } // Only single card to foundation
            let foundationPile = piles[.foundation(index)]?.cards ?? []
            if foundationPile.isEmpty {
                return firstCard.rank == .ace
            } else if let topCard = foundationPile.last {
                return firstCard.suit == topCard.suit && firstCard.rank.rawValue == topCard.rank.rawValue + 1
            }
            return false
        case .tableau(let index):
            let tableauPile = piles[.tableau(index)]?.cards ?? []
            if tableauPile.isEmpty {
                return firstCard.rank == .king
            } else if let topCard = tableauPile.last {
                // Opposite color and rank one less
                if firstCard.suit.color == topCard.suit.color { return false }
                return firstCard.rank.rawValue == topCard.rank.rawValue - 1
            }
            return false
        case .waste, .stock:
            return false
        }
    }
}
