#!/usr/bin/env python3
"""Regenerate Xcode metadata with pinned Supabase and LiveKit package references.

This writes project metadata only. It never invokes Xcode, Swift or Git.
"""

from hashlib import sha256
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "FLTiya.xcodeproj"
objects = {}
app_sources = []
test_sources = []
resources = []


def identifier(name):
    return sha256(name.encode("utf-8")).hexdigest()[:24].upper()


def add(object_key, isa, **values):
    key = identifier(object_key)
    if key in objects:
        raise ValueError("Duplicate project identifier: " + object_key)
    objects[key] = {"isa": isa, **values}
    return key


def group(path, target_sources):
    children = []
    for item in sorted(path.iterdir(), key=lambda item: (not item.is_dir(), item.name)):
        if item.name.startswith("."):
            continue
        relative = item.relative_to(ROOT).as_posix()
        if item.is_dir() and item.suffix != ".xcassets":
            children.append(group(item, target_sources))
            continue
        file_type = {
            ".swift": "sourcecode.swift",
            ".xcassets": "folder.assetcatalog",
            ".entitlements": "text.plist.entitlements",
            ".plist": "text.plist.xml",
            ".storekit": "text",
            ".md": "net.daringfireball.markdown",
            ".txt": "text",
            ".json": "text.json",
        }.get(item.suffix)
        if file_type is None:
            raise ValueError("Unrecognized app file: " + relative)
        reference = add(relative, "PBXFileReference", lastKnownFileType=file_type,
                        path=item.name, sourceTree="<group>")
        children.append(reference)
        if item.suffix == ".swift":
            target_sources.append(add(relative + ":build", "PBXBuildFile", fileRef=reference))
        elif item.suffix in (".xcassets", ".plist", ".txt", ".json"):
            resources.append(add(relative + ":build", "PBXBuildFile", fileRef=reference))
    return add(path.relative_to(ROOT).as_posix() + ":group", "PBXGroup",
               children=children, path=path.name, sourceTree="<group>")


app_group = group(ROOT / "FLTiya", app_sources)
tests_group = group(ROOT / "FLTiyaTests", test_sources)
storekit_group = group(ROOT / "StoreKit", [])
app_product = add("product:app", "PBXFileReference", explicitFileType="wrapper.application",
                  includeInIndex=0, path="FLTiya.app", sourceTree="BUILT_PRODUCTS_DIR")
test_product = add("product:tests", "PBXFileReference", explicitFileType="wrapper.cfbundle",
                   includeInIndex=0, path="FLTiyaTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
products = add("group:products", "PBXGroup", children=[app_product, test_product],
               name="Products", sourceTree="<group>")
readme = add("readme", "PBXFileReference", lastKnownFileType="net.daringfireball.markdown",
             path="README.md", sourceTree="<group>")
main_group = add("group:main", "PBXGroup", children=[app_group, tests_group, storekit_group, readme, products],
                 sourceTree="<group>")


def phase(name, kind, files):
    return add(name, kind, buildActionMask=2147483647, files=files,
               runOnlyForDeploymentPostprocessing=0)


supabase_package = add("package:supabase", "XCRemoteSwiftPackageReference",
    repositoryURL="https://github.com/supabase/supabase-swift.git",
    requirement={"kind": "exactVersion", "version": "2.55.6"})
supabase_product = add("package:supabase:product", "XCSwiftPackageProductDependency",
    package=supabase_package, productName="Supabase")
supabase_framework = add("package:supabase:build", "PBXBuildFile", productRef=supabase_product)
livekit_package = add("package:livekit", "XCRemoteSwiftPackageReference",
    repositoryURL="https://github.com/livekit/client-sdk-swift.git",
    requirement={"kind": "exactVersion", "version": "2.18.0"})
livekit_product = add("package:livekit:product", "XCSwiftPackageProductDependency",
    package=livekit_package, productName="LiveKit")
livekit_framework = add("package:livekit:build", "PBXBuildFile", productRef=livekit_product)
app_phases = [phase("app:sources", "PBXSourcesBuildPhase", app_sources),
              phase("app:frameworks", "PBXFrameworksBuildPhase", [supabase_framework, livekit_framework]),
              phase("app:resources", "PBXResourcesBuildPhase", resources)]
test_phases = [phase("tests:sources", "PBXSourcesBuildPhase", test_sources),
               phase("tests:frameworks", "PBXFrameworksBuildPhase", []),
               phase("tests:resources", "PBXResourcesBuildPhase", [])]

project_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES", "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17", "SDKROOT": "iphoneos",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
}
app_common = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "FLTiya/Resources/FLTiya.entitlements",
    "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_CFBundleDisplayName": "TIYA",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_NSMicrophoneUsageDescription": "Use your microphone for calls and to check microphone input.",
    "INFOPLIST_KEY_NSCameraUsageDescription": "Use your camera for video calls and to check the camera preview.",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": [
        "UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight"],
    "MARKETING_VERSION": "0.1.0", "PRODUCT_BUNDLE_IDENTIFIER": "im.seex.sao",
    "PRODUCT_NAME": "$(TARGET_NAME)", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "YES", "TARGETED_DEVICE_FAMILY": "1",
}
tests_common = {
    "BUNDLE_LOADER": "$(TEST_HOST)", "CODE_SIGN_STYLE": "Automatic",
    "GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": "com.fltiya.ios.development.tests",
    "PRODUCT_NAME": "$(TARGET_NAME)", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "TARGETED_DEVICE_FAMILY": "1", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/FLTiya.app/FLTiya",
}


def configurations(name, common, is_project=False):
    result = []
    for configuration in ("Debug", "Preview", "CommunityTesting", "Release"):
        settings = dict(common)
        if is_project:
            if configuration in ("Debug", "Preview", "CommunityTesting"):
                swift_conditions = {
                    "Debug": "DEBUG", "Preview": "DEBUG DEVELOPMENT_PREVIEW",
                    "CommunityTesting": "DEBUG COMMUNITY_TESTING",
                }[configuration]
                settings.update({"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES",
                                 "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
                                 "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS":
                                     f"{swift_conditions} $(inherited)",
                                 "SWIFT_OPTIMIZATION_LEVEL": "-Onone"})
            else:
                settings.update({"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                                 "SWIFT_COMPILATION_MODE": "wholemodule", "SWIFT_OPTIMIZATION_LEVEL": "-O",
                                 "VALIDATE_PRODUCT": "YES"})
        elif configuration in ("Preview", "CommunityTesting"):
            suffix = ".preview" if configuration == "Preview" else ".community"
            if name == "app":
                settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.fltiya.ios.development" + suffix
                settings["INFOPLIST_KEY_CFBundleDisplayName"] = (
                    "TIYA Preview" if configuration == "Preview" else "TIYA Social Test"
                )
                # These separate app identities do not use Sign in with Apple.
                settings.pop("CODE_SIGN_ENTITLEMENTS", None)
            elif name == "tests":
                settings["PRODUCT_BUNDLE_IDENTIFIER"] = common["PRODUCT_BUNDLE_IDENTIFIER"] + suffix
        result.append(add(name + ":" + configuration, "XCBuildConfiguration",
                          buildSettings=settings, name=configuration))
    return add(name + ":configuration-list", "XCConfigurationList", buildConfigurations=result,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


app_config = configurations("app", app_common)
tests_config = configurations("tests", tests_common)
project_config = configurations("project", project_common, is_project=True)
app_target = add("target:app", "PBXNativeTarget", buildConfigurationList=app_config,
                 buildPhases=app_phases, buildRules=[], dependencies=[], name="FLTiya",
                 packageProductDependencies=[supabase_product, livekit_product],
                 productName="FLTiya", productReference=app_product,
                 productType="com.apple.product-type.application")
proxy = add("tests:proxy", "PBXContainerItemProxy", containerPortal=identifier("project"),
            proxyType=1, remoteGlobalIDString=app_target, remoteInfo="FLTiya")
dependency = add("tests:dependency", "PBXTargetDependency", target=app_target, targetProxy=proxy)
tests_target = add("target:tests", "PBXNativeTarget", buildConfigurationList=tests_config,
                   buildPhases=test_phases, buildRules=[], dependencies=[dependency], name="FLTiyaTests",
                   productName="FLTiyaTests", productReference=test_product,
                   productType="com.apple.product-type.bundle.unit-test")
project = add("project", "PBXProject", attributes={
    "BuildIndependentTargetsInParallel": "YES", "LastSwiftUpdateCheck": "2600", "LastUpgradeCheck": "2600",
    "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "26.0.1",
        "SystemCapabilities": {"com.apple.SignInWithApple": {"enabled": 1}}},
        tests_target: {"CreatedOnToolsVersion": "26.0.1", "TestTargetID": app_target}}},
    buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0",
    developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"],
    mainGroup=main_group, productRefGroup=products, projectDirPath="", projectRoot="",
    targets=[app_target, tests_target], packageReferences=[supabase_package, livekit_package])


def openstep(value, level=0):
    indent = "\t" * level
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (level + 1) + json.dumps(key) + " = " +
                                openstep(item, level + 1) + ";\n" for key, item in value.items()) + indent + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (level + 1) + openstep(item, level + 1) + ",\n"
                                for item in value) + indent + ")"
    return json.dumps(value, ensure_ascii=False)


PROJECT.mkdir(exist_ok=True)
document = {"archiveVersion": 1, "classes": {}, "objectVersion": 56,
            "objects": objects, "rootObject": project}
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + openstep(document) + "\n")
workspace = PROJECT / "project.xcworkspace"
workspace.mkdir(exist_ok=True)
(workspace / "contents.xcworkspacedata").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n')


def buildable(target, product, name):
    return ('<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="' + target +
            '" BuildableName="' + product + '" BlueprintName="' + name +
            '" ReferencedContainer="container:FLTiya.xcodeproj"/>')


app_reference = buildable(app_target, "FLTiya.app", "FLTiya")
test_reference = buildable(tests_target, "FLTiyaTests.xctest", "FLTiyaTests")
scheme = '''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app}</BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="{test_inherits_launch}">
    <Testables><TestableReference skipped="NO">{tests}</TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="{run_configuration}" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable>
    {launch_options}
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="{profile_inherits_launch}" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugServiceExtension="internal">
    <BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="{analyze_configuration}"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
local_storekit = '''<StoreKitConfigurationFileReference identifier="../../StoreKit/FLTiya.storekit"/>
    <EnvironmentVariables>
      <EnvironmentVariable key="FLTIYA_LOCAL_STOREKIT_TESTING" value="1" isEnabled="YES"/>
    </EnvironmentVariables>'''
community_login = '''<EnvironmentVariables>
      <EnvironmentVariable key="FLTIYA_UI_REVIEW_ACCESS_CODE" value="" isEnabled="NO"/>
    </EnvironmentVariables>'''
for name, configuration in (("FLTiya", "Debug"), ("FLTiyaPreview", "Preview"),
                             ("FLTiyaStoreKitTesting", "Debug"), ("FLTiyaCommunityTesting", "CommunityTesting")):
    local_testing = name in {"FLTiya", "FLTiyaStoreKitTesting"}
    community_testing = name == "FLTiyaCommunityTesting"
    contents = scheme.format(
        app=app_reference, tests=test_reference, run_configuration=configuration,
        analyze_configuration="Debug" if community_testing else configuration,
        launch_options=local_storekit if local_testing else community_login if community_testing else "",
        test_inherits_launch="NO" if community_testing or name == "FLTiya" else "YES",
        profile_inherits_launch="NO" if local_testing or community_testing else "YES")
    (scheme_dir / (name + ".xcscheme")).write_text("\n".join(line.rstrip() for line in contents.splitlines()) + "\n")
print(f"Generated {PROJECT.name}: {len(app_sources)} app sources, {len(test_sources)} test sources; no build performed.")
