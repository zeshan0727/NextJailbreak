import Foundation

/// Restricts model-controlled paths, then layers non-model scaffold files over them.
enum ProjectFactory {
    static func parseModelJSON(_ raw: String) throws -> ForgeProject {
        let unwrapped = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = unwrapped.firstIndex(of: "{"), let last = unwrapped.lastIndex(of: "}"), first <= last else {
            throw ForgeError.message("AI response did not contain a JSON object")
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

    static func scaffold(_ project: ForgeProject, minIOS: String) throws -> ForgeProject {
        let safe = try sanitize(project)
        let target = safe.appName
        let ios = minIOS.range(of: #"^\d{1,2}\.\d{1,2}$"#, options: .regularExpression) == nil ? "16.0" : minIOS
        let yaml = """
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
        schemes:
          \(target):
            build:
              targets:
                \(target): all
            archive:
              config: Release
        """
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
              - name: Package IPA and TIPA
                run: |
                  set -euo pipefail
                  mkdir -p out/Payload
                  ditto "DerivedData/Build/Products/Release-iphoneos/\(target).app" "out/Payload/\(target).app"
                  (cd out && zip -qry \(target).ipa Payload)
                  cp "out/\(target).ipa" "out/\(target).tipa"
              - name: Upload artifact
                uses: actions/upload-artifact@v4
                with:
                  name: \(target)-${{ github.run_number }}
                  path: |
                    out/*.ipa
                    out/*.tipa
              - name: Publish GitHub Release
                env:
                  GH_TOKEN: ${{ github.token }}
                run: |
                  gh release create "build-${{ github.run_number }}" "out/\(target).ipa" "out/\(target).tipa" \\
                    --title "\(target) build ${{ github.run_number }}" \\
                    --notes "Unsigned output. Requires compatible installation/signing." --target "$GITHUB_SHA"
        """
        var all = safe.files
        all.append(contentsOf: [
            ForgeFile(path: "Sources/AppEntry.swift", content: "import SwiftUI\n@main struct \(target)App: App { var body: some Scene { WindowGroup { ContentView() } } }\n"),
            ForgeFile(path: "project.yml", content: yaml + "\n"),
            ForgeFile(path: "Info.plist", content: info + "\n"),
            ForgeFile(path: "Assets.xcassets/Contents.json", content: "{\"info\":{\"author\":\"xcode\",\"version\":1}}\n"),
            ForgeFile(path: ".github/workflows/build.yml", content: workflow + "\n"),
            ForgeFile(path: "README.md", content: "# \(target)\n\nGenerated by AppForge. Push to GitHub to run an unsigned build. An IPA is not an Apple-signed distribution package.\n")
        ])
        return ForgeProject(appName: target, bundleId: safe.bundleId, files: all)
    }
}
