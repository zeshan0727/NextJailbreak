#!/usr/bin/env python3
"""Generate a deterministic, dependency-free Xcode project and shared scheme."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(object_key, isa, **fields):
    key = uid(object_key)
    objects[key] = {"isa": isa, **fields}
    return key

def serialize(value, depth=0):
    pad = "\t" * depth
    if isinstance(value, dict):
        return "{\n" + "".join(f'{pad}\t{json.dumps(k)} = {serialize(v, depth+1)};\n' for k, v in value.items()) + pad + "}"
    if isinstance(value, list):
        return "(\n" + "".join(pad + "\t" + serialize(x, depth+1) + ",\n" for x in value) + pad + ")"
    return json.dumps(str(value))

def configuration_list(name, common, debug=None, release=None):
    refs = []
    for label, extra in [("Debug", debug or {}), ("Release", release or {})]:
        refs.append(add(name + label, "XCBuildConfiguration", name=label, buildSettings={**common, **extra}))
    return add(name + "ConfigurationList", "XCConfigurationList", buildConfigurations=refs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

def main():
    app_sources, test_sources, resources, all_files = [], [], [], []
    for path in sorted(ROOT.glob("NovaBrowser/**/*.swift")) + sorted(ROOT.glob("NovaBrowserTests/*.swift")):
        relative = str(path.relative_to(ROOT))
        ref = add(relative, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="SOURCE_ROOT")
        build = add(relative + "build", "PBXBuildFile", fileRef=ref)
        (test_sources if relative.startswith("NovaBrowserTests/") else app_sources).append(build)
        all_files.append(ref)
    for relative, kind in [("NovaBrowser/Resources/Assets.xcassets", "folder.assetcatalog"), ("NovaBrowser/Resources/test-browser.html", "text.html")]:
        ref = add(relative, "PBXFileReference", lastKnownFileType=kind, path=relative, sourceTree="SOURCE_ROOT")
        all_files.append(ref)
        resources.append(add(relative + "build", "PBXBuildFile", fileRef=ref))
    all_files.append(add("info", "PBXFileReference", lastKnownFileType="text.plist.xml", path="NovaBrowser/App/Info.plist", sourceTree="SOURCE_ROOT"))
    app_product = add("appProduct", "PBXFileReference", explicitFileType="wrapper.application", path="NovaBrowser.app", sourceTree="BUILT_PRODUCTS_DIR", includeInIndex=0)
    test_product = add("testProduct", "PBXFileReference", explicitFileType="wrapper.cfbundle", path="NovaBrowserTests.xctest", sourceTree="BUILT_PRODUCTS_DIR", includeInIndex=0)
    product_group = add("products", "PBXGroup", children=[app_product, test_product], name="Products", sourceTree="<group>")
    group = add("rootGroup", "PBXGroup", children=all_files + [product_group], sourceTree="<group>")
    project_config = configuration_list("project", {
        "IPHONEOS_DEPLOYMENT_TARGET": "16.0", "SWIFT_VERSION": "5.0", "SDKROOT": "iphoneos",
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "TARGETED_DEVICE_FAMILY": "1,2", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "SWIFT_STRICT_CONCURRENCY": "minimal", "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES"
    }, {"SWIFT_OPTIMIZATION_LEVEL": "-Onone", "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"},
       {"SWIFT_OPTIMIZATION_LEVEL": "-O", "SWIFT_COMPILATION_MODE": "wholemodule", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "VALIDATE_PRODUCT": "YES"})
    app_config = configuration_list("app", {
        "PRODUCT_BUNDLE_IDENTIFIER": "com.example.novabrowser", "PRODUCT_NAME": "$(TARGET_NAME)",
        "INFOPLIST_FILE": "NovaBrowser/App/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "MARKETING_VERSION": "1.0.0", "CURRENT_PROJECT_VERSION": "1",
        "CODE_SIGN_STYLE": "Manual", "CODE_SIGNING_ALLOWED": "NO", "CODE_SIGNING_REQUIRED": "NO",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"], "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO"
    })
    test_config = configuration_list("tests", {
        "PRODUCT_BUNDLE_IDENTIFIER": "com.example.novabrowser.tests", "PRODUCT_NAME": "$(TARGET_NAME)", "GENERATE_INFOPLIST_FILE": "YES",
        "CODE_SIGNING_ALLOWED": "NO", "CODE_SIGNING_REQUIRED": "NO", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/NovaBrowser.app/NovaBrowser",
        "BUNDLE_LOADER": "$(TEST_HOST)", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"]
    })
    app_phases = [add("appSources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=app_sources, runOnlyForDeploymentPostprocessing=0),
                  add("appFrameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0),
                  add("appResources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)]
    app = add("appTarget", "PBXNativeTarget", buildConfigurationList=app_config, buildPhases=app_phases, buildRules=[], dependencies=[], name="NovaBrowser", productName="NovaBrowser", productReference=app_product, productType="com.apple.product-type.application")
    proxy = add("testProxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType=1, remoteGlobalIDString=app, remoteInfo="NovaBrowser")
    dependency = add("testDependency", "PBXTargetDependency", target=app, targetProxy=proxy)
    test_phases = [add("testSources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=test_sources, runOnlyForDeploymentPostprocessing=0), add("testFrameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)]
    tests = add("testTarget", "PBXNativeTarget", buildConfigurationList=test_config, buildPhases=test_phases, buildRules=[], dependencies=[dependency], name="NovaBrowserTests", productName="NovaBrowserTests", productReference=test_product, productType="com.apple.product-type.bundle.unit-test")
    project = add("project", "PBXProject", attributes={"LastUpgradeCheck": "1500", "BuildIndependentTargetsInParallel": "YES", "TargetAttributes": {app: {"CreatedOnToolsVersion": "15.0"}, tests: {"CreatedOnToolsVersion": "15.0", "TestTargetID": app}}}, buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=group, productRefGroup=product_group, projectDirPath="", projectRoot="", targets=[app, tests])
    destination = ROOT / "NovaBrowser.xcodeproj"
    destination.mkdir(exist_ok=True)
    payload = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}
    (destination / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize(payload) + "\n")
    def reference(identifier, name, product):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:NovaBrowser.xcodeproj"/>'
    app_ref = reference(app, "NovaBrowser", "NovaBrowser.app")
    test_ref = reference(tests, "NovaBrowserTests", "NovaBrowserTests.xctest")
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{test_ref}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
    schemes = destination / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    (schemes / "NovaBrowser.xcscheme").write_text(scheme + "\n")
    print(f"Generated project with {len(app_sources)} app files and {len(test_sources)} test files.")

if __name__ == "__main__":
    main()
