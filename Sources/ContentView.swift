import SwiftUI

struct ContentView: View {
    @State private var red: Double = 255
    @State private var green: Double = 0
    @State private var blue: Double = 0
    @State private var hexInput: String = "#FF0000"
    @State private var hexError: String? = nil
    @State private var showFavorites: Bool = false
    @AppStorage("favoriteColors") private var favoriteHexColorsData: Data = Data()
    @State private var favoriteHexColors: [String] = []
    @State private var alertMessage: String? = nil
    
    private let sliderRange = 0.0...255.0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                colorDisplay
                rgbSliders
                hexInputField
                colorWheelPicker
                colorCodeFormats
                actionButtons
                Spacer()
            }
            .padding()
            .navigationTitle("Color Picker")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Favorites") {
                        showFavorites = true
                    }
                    .accessibilityLabel("Show favorite colors")
                }
            }
            .sheet(isPresented: $showFavorites) {
                FavoritesView(favoriteHexColors: $favoriteHexColors, onSelect: { hex in
                    if let rgb = Self.rgbFromHex(hex) {
                        updateColorFromRGB(rgb)
                        showFavorites = false
                    }
                })
            }
            .onAppear {
                loadFavorites()
                updateHexInputFromRGB()
            }
            .alert(item: $alertMessage) { msg in
                Alert(title: Text("Error"), message: Text(msg), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    // MARK: - Subviews
    
    private var colorDisplay: some View {
        Rectangle()
            .fill(currentColor)
            .frame(height: 150)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Selected color")
            .accessibilityValue(hexInput)
    }
    
    private var rgbSliders: some View {
        VStack(spacing: 12) {
            rgbSlider(value: $red, label: "Red", color: .red)
            rgbSlider(value: $green, label: "Green", color: .green)
            rgbSlider(value: $blue, label: "Blue", color: .blue)
        }
    }
    
    private func rgbSlider(value: Binding<Double>, label: String, color: Color) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(label)
                    .font(.headline)
                    .foregroundColor(color)
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: sliderRange, step: 1) {
                Text(label)
            }
            .tint(color)
            .accessibilityValue("\(Int(value.wrappedValue))")
            .onChange(of: value.wrappedValue) { _ in
                updateHexInputFromRGB()
            }
        }
    }
    
    private var hexInputField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Hex Code (#RRGGBB)", text: $hexInput)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(hexError == nil ? Color.secondary.opacity(0.5) : Color.red, lineWidth: 1)
                )
                .accessibilityLabel("Hex color code input")
                .accessibilityHint("Enter hex code in format #RRGGBB")
                .onChange(of: hexInput) { newValue in
                    validateAndUpdateColor(from: newValue)
                }
            if let error = hexError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .accessibilityLabel("Error: \(error)")
            }
        }
    }
    
    private var colorWheelPicker: some View {
        ColorPicker("Color Wheel", selection: Binding(get: {
            currentColor
        }, set: { newColor in
            updateColorFromColor(newColor)
        }))
        .labelsHidden()
        .accessibilityLabel("Color wheel picker")
        .frame(maxWidth: 100)
    }
    
    private var colorCodeFormats: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hex: \(hexInput.uppercased())")
                .font(.body.monospaced())
                .accessibilityLabel("Hex code")
                .accessibilityValue(hexInput.uppercased())
            Text("RGB: rgb(\(Int(red)), \(Int(green)), \(Int(blue)))")
                .font(.body.monospaced())
                .accessibilityLabel("RGB code")
                .accessibilityValue("rgb(\(Int(red)), \(Int(green)), \(Int(blue)))")
            Text("HSB: hsb(\(Int(hueDegrees)), \(Int(saturationPercent))%, \(Int(brightnessPercent))%)")
                .font(.body.monospaced())
                .accessibilityLabel("HSB code")
                .accessibilityValue("hsb(\(Int(hueDegrees)), \(Int(saturationPercent)) percent, \(Int(brightnessPercent)) percent)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 20) {
            Button(action: saveCurrentColor) {
                Label("Save Color", systemImage: "star")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCurrentColorSaved || hexError != nil)
            .accessibilityLabel("Save current color to favorites")
            
            Button(action: { showFavorites = true }) {
                Label("Favorites", systemImage: "star.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Show favorite colors")
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentColor: Color {
        Color(red: red/255, green: green/255, blue: blue/255)
    }
    
    private var isCurrentColorSaved: Bool {
        favoriteHexColors.contains(hexInput.uppercased())
    }
    
    private var hueDegrees: Double {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(currentColor).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Double(h * 360)
    }
    
    private var saturationPercent: Double {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(currentColor).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Double(s * 100)
    }
    
    private var brightnessPercent: Double {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(currentColor).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Double(b * 100)
    }
    
    // MARK: - Methods
    
    private func updateHexInputFromRGB() {
        let r = Int(red)
        let g = Int(green)
        let b = Int(blue)
        let hex = String(format: "#%02X%02X%02X", r, g, b)
        if hexInput.uppercased() != hex {
            hexInput = hex
            hexError = nil
        }
    }
    
    private func updateColorFromRGB(_ rgb: (r: Int, g: Int, b: Int)) {
        red = Double(rgb.r)
        green = Double(rgb.g)
        blue = Double(rgb.b)
        updateHexInputFromRGB()
    }
    
    private func updateColorFromColor(_ color: Color) {
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
            red = Double(r * 255)
            green = Double(g * 255)
            blue = Double(b * 255)
            updateHexInputFromRGB()
        }
    }
    
    private func validateAndUpdateColor(from hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.count == 7 && cleaned.first == "#" {
            let hexPart = String(cleaned.dropFirst())
            if let rgb = Self.rgbFromHex(cleaned) {
                hexError = nil
                updateColorFromRGB(rgb)
            } else {
                hexError = "Invalid hex code"
            }
        } else {
            hexError = "Hex code must be in format #RRGGBB"
        }
    }
    
    private func saveCurrentColor() {
        let hex = hexInput.uppercased()
        guard hexError == nil else { return }
        guard !favoriteHexColors.contains(hex) else { return }
        favoriteHexColors.append(hex)
        saveFavorites()
    }
    
    private func loadFavorites() {
        do {
            let decoded = try JSONDecoder().decode([String].self, from: favoriteHexColorsData)
            favoriteHexColors = decoded
        } catch {
            favoriteHexColors = []
        }
    }
    
    private func saveFavorites() {
        do {
            let encoded = try JSONEncoder().encode(favoriteHexColors)
            favoriteHexColorsData = encoded
        } catch {
            alertMessage = "Failed to save favorites."
        }
    }
    
    // MARK: - Helpers
    
    static func rgbFromHex(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        let r, g, b: Int
        let start = hex.index(hex.startIndex, offsetBy: 1)
        let hexColor = String(hex[start...])
        guard hexColor.count == 6 else { return nil }
        let scanner = Scanner(string: hexColor)
        var hexNumber: UInt64 = 0
        if scanner.scanHexInt64(&hexNumber) {
            r = Int((hexNumber & 0xFF0000) >> 16)
            g = Int((hexNumber & 0x00FF00) >> 8)
            b = Int(hexNumber & 0x0000FF)
            return (r, g, b)
        }
        return nil
    }
}

struct FavoritesView: View {
    @Binding var favoriteHexColors: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedToast: Bool = false
    @State private var copiedHex: String = ""
    @State private var editMode: EditMode = .inactive
    let onSelect: (String) -> Void
    
    var body: some View {
        NavigationStack {
            Group {
                if favoriteHexColors.isEmpty {
                    Text("No favorite colors saved.")
                        .foregroundColor(.secondary)
                        .accessibilityLabel("No favorite colors saved")
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 16)], spacing: 16) {
                            ForEach(favoriteHexColors, id: \ .self) { hex in
                                favoriteColorItem(hex: hex)
                            }
                            .onDelete(perform: delete)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Favorites")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close favorites")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                        .accessibilityLabel(editMode == .active ? "Done editing favorites" : "Edit favorites")
                }
            }
            .environment(\.editMode, $editMode)
            .toast(isPresented: $showCopiedToast, message: "Copied to clipboard: \(copiedHex)")
        }
    }
    
    @ViewBuilder
    private func favoriteColorItem(hex: String) -> some View {
        let color = ColorCodePickerHelpers.colorFromHex(hex) ?? .black
        VStack(spacing: 8) {
            Rectangle()
                .fill(color)
                .frame(height: 80)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Favorite color")
                .accessibilityValue(hex)
            Text(hex)
                .font(.footnote.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundColor(ColorCodePickerHelpers.textColor(for: color))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if editMode == .active {
                // no tap action in edit mode
            } else {
                UIPasteboard.general.string = hex
                copiedHex = hex
                showCopiedToast = true
                onSelect(hex)
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = hex
                copiedHex = hex
                showCopiedToast = true
            } label: {
                Label("Copy Hex Code", systemImage: "doc.on.doc")
            }
        }
    }
    
    private func delete(at offsets: IndexSet) {
        favoriteHexColors.remove(atOffsets: offsets)
        saveFavorites()
    }
    
    private func saveFavorites() {
        do {
            let encoded = try JSONEncoder().encode(favoriteHexColors)
            UserDefaults.standard.set(encoded, forKey: "favoriteColors")
        } catch {
            // ignore save errors here
        }
    }
}

// MARK: - Toast Modifier

fileprivate struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    
    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if isPresented {
                Text(message)
                    .font(.footnote)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                isPresented = false
                            }
                        }
                    }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.easeInOut, value: isPresented)
    }
}

fileprivate extension View {
    func toast(isPresented: Binding<Bool>, message: String) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message))
    }
}

// MARK: - Helpers

fileprivate enum ColorCodePickerHelpers {
    static func colorFromHex(_ hex: String) -> Color? {
        let r, g, b: Int
        let start = hex.index(hex.startIndex, offsetBy: 1)
        let hexColor = String(hex[start...])
        guard hexColor.count == 6 else { return nil }
        let scanner = Scanner(string: hexColor)
        var hexNumber: UInt64 = 0
        if scanner.scanHexInt64(&hexNumber) {
            r = Int((hexNumber & 0xFF0000) >> 16)
            g = Int((hexNumber & 0x00FF00) >> 8)
            b = Int(hexNumber & 0x0000FF)
            return Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
        }
        return nil
    }
    
    static func textColor(for background: Color) -> Color {
        // Calculate luminance to decide black or white text
        let uiColor = UIColor(background)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.6 ? .black : .white
    }
}