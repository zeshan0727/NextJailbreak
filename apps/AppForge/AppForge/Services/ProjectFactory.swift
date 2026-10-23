import Foundation

/// Restricts model-controlled paths, then layers non-model scaffold files over them.
enum ProjectFactory {
    static func parseModelJSON(_ raw: String) throws -> ForgeProject {
        // Extract the first balanced JSON object, respecting braces in quoted Swift source.
        let unwrapped = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = unwrapped.firstIndex(of: "{") else {
            throw ForgeError.message("AI response did not contain a JSON object")
        }
        var depth = 0
        var quoted = false
        var escaped = false
        var last: String.Index?
        for index in unwrapped[first...].indices {
            let character = unwrapped[index]
            if quoted {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted = false }
                continue
            }
            if character == "\"" { quoted = true }
            else if character == "{" { depth += 1 }
            else if character == "}" {
                depth -= 1
                if depth == 0 { last = index; break }
            }
        }
        guard let last else {
            throw ForgeError.message("AI JSON was incomplete or truncated.")
        }
        let json = String(unwrapped[first...last])
        let decoded: ForgeProject
        do { decoded = try JSONDecoder().decode(ForgeProject.self, from: Data(json.utf8)) }
        catch { throw ForgeError.message("Could not parse AI JSON: \(error.localizedDescription)") }
        return try sanitize(decoded)
    }

    static func sanitize(_ project: ForgeProject) throws -> ForgeProject {
        let name = String(project.appName.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(42))
        guard !name.isEmpty else { throw ForgeError.message("Model produced an invalid app name") }
        let bid = project.bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = bid.split(separator: ".")
        guard components.count >= 2,
              components.allSatisfy({ segment in
                  guard let first = segment.first, first.isASCII && first.isLetter else { return false }
                  return segment.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
              }) else { throw ForgeError.message("Model produced an invalid bundle identifier") }
        var files = [ForgeFile]()
        var seen = Set<String>()
        for file in project.files {
            var path = file.path.replacingOccurrences(of: "\\", with: "/")
            guard !path.contains(".."), !path.hasPrefix("/"), !path.contains("//") else {
                throw ForgeError.message("Unsafe generated file path: \(file.path)")
            }
            if !path.hasPrefix("Sources/") { path = "Sources/" + path }
            guard path.hasSuffix(".swift"), !path.contains(":"), path != "Sources/AppEntry.swift" else { continue }
            guard seen.insert(path).inserted else { throw ForgeError.message("Duplicate file: \(path)") }
            guard !file.content.contains("@main") else {
                throw ForgeError.message("Generated source contains @main; AppForge supplies its own app entry")
            }
            files.append(ForgeFile(path: path, content: file.content))
        }
        guard files.contains(where: { $0.content.contains("struct ContentView") }) else {
            throw ForgeError.message("Generated files must define struct ContentView: View")
        }
        return ForgeProject(appName: name, bundleId: bid, files: files)
    }

    /// A SwiftUI navigation value must be Hashable. AI sometimes emits only Equatable,
    /// which leads to misleading "unable to type-check" errors on large View bodies.
    /// Apply a conservative correction to plain Codable/Equatable/Identifiable structs.
    private static func repairNavigationModels(_ files: [ForgeFile]) -> [ForgeFile] {
        let combined = files.map(\.content).joined(separator: "\n")
        guard let nav = try? NSRegularExpression(
            pattern: #"navigationDestination\s*\(\s*for\s*:\s*([A-Za-z_][A-Za-z0-9_]*)\.self"#
        ) else { return files }
        let sourceRange = NSRange(combined.startIndex..<combined.endIndex, in: combined)
        var types = Set<String>()
        for match in nav.matches(in: combined, range: sourceRange) {
            if let range = Range(match.range(at: 1), in: combined) {
                types.insert(String(combined[range]))
            }
        }
        guard !types.isEmpty else { return files }
        return files.map { source in
            guard source.path.hasSuffix(".swift") else { return source }
            var updated = source.content
            for type in types.sorted() {
                let pattern = #"(?m)\bstruct\s+"#
                    + NSRegularExpression.escapedPattern(for: type)
                    + #"\s*:\s*([^{\n]+)\{"#
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: updated,
                          range: NSRange(updated.startIndex..<updated.endIndex, in: updated)),
                      let fullRange = Range(match.range, in: updated),
                      let clauses = Range(match.range(at: 1), in: updated) else { continue }
                let inherited = String(updated[clauses]).trimmingCharacters(in: .whitespaces)
                guard inherited.contains("Identifiable"),
                      inherited.contains("Codable"),
                      inherited.contains("Equatable"),
                      !inherited.contains("Hashable") else { continue }
                updated.replaceSubrange(fullRange,
                    with: "struct \(type): \(inherited), Hashable {")
            }
            return ForgeFile(path: source.path, content: updated)
        }
    }


    /// Repairs a narrow, recurring model-generated SwiftUI mistake:
    /// .alert("...", isPresented: ...) { buttons }, message: { text })
    /// has to use the 'message:' trailing closure without a comma or closing ')'.
    /// Only rewrite when a .alert call appears immediately before the malformed closure.
    private static func repairAlertTrailingClosure(_ files: [ForgeFile]) -> [ForgeFile] {
        files.map { file in
            guard file.path.hasSuffix(".swift") else { return file }
            var lines = file.content.components(separatedBy: "\n")
            guard lines.count > 2 else { return file }
            for index in lines.indices {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                guard trimmed == "}, message: {" else { continue }
                let lookback = lines[max(0, index - 32)..<index].joined(separator: "\n")
                guard lookback.contains(".alert(") else { continue }
                let indent = String(lines[index].prefix(while: { $0 == " " || $0 == "\t" }))
                let end = min(lines.count, index + 24)
                guard index + 1 < end,
                      let endIndex = (index+1..<end).first(where: {
                          lines[$0].trimmingCharacters(in: .whitespaces) == "})"
                          && String(lines[$0].prefix(while: { $0 == " " || $0 == "\t" })) == indent
                      }) else { continue }
                lines[index] = indent + "} message: {"
                lines[endIndex] = indent + "}"
            }
            return ForgeFile(path: file.path, content: lines.joined(separator: "\n"))
        }
    }

    static func repairKnownCompilerErrors(_ project: ForgeProject, log: String) -> ForgeProject? {
        guard log.contains("consecutive statements on a line")
           || log.contains("labeled block needs 'do'")
           || log.contains("Expected expression")
           || log.contains("expected expression") else { return nil }
        var updated = project
        updated.files = repairAlertTrailingClosure(project.files)
        return updated.files == project.files ? nil : updated
    }

    static func scaffold(_ project: ForgeProject, minIOS: String) throws -> ForgeProject {
        var safe = try sanitize(project)
        safe.files = repairAlertTrailingClosure(repairNavigationModels(safe.files))
        let target = safe.appName
        let ios = minIOS.range(of: #"^\d{1,2}\.\d{1,2}$"#, options: .regularExpression) == nil ? "16.0" : minIOS
        var yaml = """
        name: \(target)
        options:
          deploymentTarget:
            iOS: "\(ios)"
        settings:
          base:
            SWIFT_VERSION: "5.0"
            IPHONEOS_DEPLOYMENT_TARGET: "\(ios)"
        targets:
          \(target):
            type: application
            platform: iOS
            sources:
              - Sources
              - Assets.xcassets
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: \(safe.bundleId)
                INFOPLIST_FILE: Info.plist
                GENERATE_INFOPLIST_FILE: NO
                TARGETED_DEVICE_FAMILY: "1,2"
                ASSETCATALOG_COMPILER_APPICON_NAME: ""
        schemes:
          \(target):
            build:
              targets:
                \(target): all
            archive:
              config: Release
        """
        // The selected repository may already contain a different app under Sources/.
        // Include ONLY this app's generated Swift files, never the entire inherited folder.
        let swiftFiles = (safe.files.map(\.path) + ["Sources/AppEntry.swift"])
            .sorted()
        let explicitSources = swiftFiles.map { "      - \($0)" }.joined(separator: "\n")
        yaml = yaml.replacingOccurrences(of: "      - Sources\n",
            with: explicitSources + "\n")
        let info = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
          <key>CFBundleDisplayName</key><string>\(target)</string>
          <key>CFBundleShortVersionString</key><string>1.0.0</string>
          <key>CFBundleVersion</key><string>1</string>
          <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
          <key>CFBundlePackageType</key><string>APPL</string>
          <key>UILaunchScreen</key><dict/>
        </dict></plist>
        """
        let workflow = """
        name: Build iOS App
        on:
          push:
            branches: ['**']
          workflow_dispatch:
        permissions:
          contents: write
        jobs:
          build:
            runs-on: macos-latest
            steps:
              - name: Checkout
                uses: actions/checkout@v4
              - name: Install XcodeGen
                run: brew install xcodegen
              - name: Generate project
                run: xcodegen generate
              - name: Build unsigned app
                run: |
                  set -euo pipefail
                  xcodebuild -project \(target).xcodeproj -scheme \(target) -configuration Release \\
                    -sdk iphoneos -destination 'generic/platform=iOS' \\
                    -derivedDataPath "$PWD/DerivedData" \\
                    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
              - name: Ad-hoc sign for TrollStore
                run: |
                  set -euo pipefail
                  codesign --force --sign - --timestamp=none "DerivedData/Build/Products/Release-iphoneos/\(target).app"
                  codesign --verify --verbose=2 "DerivedData/Build/Products/Release-iphoneos/\(target).app"
              - name: Package IPA
                run: |
                  set -euo pipefail
                  mkdir -p out/Payload
                  ditto "DerivedData/Build/Products/Release-iphoneos/\(target).app" "out/Payload/\(target).app"
                  (cd out && zip -qry \(target).ipa Payload)
              - name: Upload artifact
                uses: actions/upload-artifact@v4
                with:
                  name: \(target)-${{ github.run_number }}
                  path: |
                    out/*.ipa
              - name: Publish GitHub Release
                env:
                  GH_TOKEN: ${{ github.token }}
                run: |
                  gh release create "\(target)-build-${{ github.run_number }}-${{ github.run_attempt }}" "out/\(target).ipa" \\
                    --title "\(target) build ${{ github.run_number }}" \\
                    --notes "Ad-hoc signed IPA for compatible TrollStore installation." --target "$GITHUB_SHA"
        """
        var all = safe.files
        all.append(contentsOf: [
            ForgeFile(path: "Sources/AppEntry.swift", content: "import SwiftUI\n@main struct \(target)App: App { var body: some Scene { WindowGroup { ContentView() } } }\n"),
            ForgeFile(path: "project.yml", content: yaml + "\n"),
            ForgeFile(path: "Info.plist", content: info + "\n"),
            ForgeFile(path: "Assets.xcassets/Contents.json", content: "{\"info\":{\"author\":\"xcode\",\"version\":1}}\n"),
            ForgeFile(path: ".github/workflows/build.yml", content: workflow + "\n"),
            ForgeFile(path: "README.md", content: "# \(target)\n\nGenerated by AppForge. Push to GitHub for an ad-hoc signed IPA build. TrollStore or compatible installation required.\n")
        ])
        return try CrashDoctor.preflight(ForgeProject(appName: target, bundleId: safe.bundleId, files: all))
    }
}
