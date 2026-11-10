#!/usr/bin/env python3
"""Check Xcode references and Swift grammar; never build or launch the app."""

import json
from pathlib import Path
import plistlib
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "FLTiya.xcodeproj"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True)
    require(result.returncode == 0, result.stderr.strip() or result.stdout.strip())
    return result.stdout


document = json.loads(run(["/usr/bin/plutil", "-convert", "json", "-o", "-", str(PROJECT / "project.pbxproj")]))
objects = document["objects"]
project = objects[document["rootObject"]]
require(project["isa"] == "PBXProject", "Root must be PBXProject")
single_refs = {"buildConfigurationList", "mainGroup", "productRefGroup", "productReference",
               "fileRef", "target", "targetProxy", "containerPortal", "remoteGlobalIDString", "package", "productRef"}
array_refs = {"children", "buildConfigurations", "buildPhases", "dependencies", "files", "targets",
              "packageReferences", "packageProductDependencies"}
for key, value in objects.items():
    for field in single_refs:
        if field in value:
            require(value[field] in objects, f"Unresolved {field} in {key}")
    for field in array_refs:
        for reference in value.get(field, []):
            require(reference in objects, f"Unresolved {field} in {key}")

file_paths = {}


def walk_group(key, parent):
    node = objects[key]
    if node["isa"] == "PBXGroup":
        current = parent / node.get("path", "")
        for child in node["children"]:
            walk_group(child, current)
    elif node["isa"] == "PBXFileReference" and node["sourceTree"] != "BUILT_PRODUCTS_DIR":
        path = parent / node["path"]
        require(path.exists(), "Missing file: " + str(path.relative_to(ROOT)))
        require(path.resolve().is_relative_to(ROOT.resolve()), "File reference leaves repository")
        file_paths[key] = path


walk_group(project["mainGroup"], ROOT)
targets = {objects[key]["name"]: objects[key] for key in project["targets"]}
require(set(targets) == {"FLTiya", "FLTiyaTests"}, "Expected app and test targets")
expected_packages = {"https://github.com/supabase/supabase-swift.git": "2.55.6",
                     "https://github.com/livekit/client-sdk-swift.git": "2.18.0"}
packages = [objects[key] for key in project["packageReferences"]]
require(len(packages) == len(expected_packages), "Unexpected package count")
for package in packages:
    url = package["repositoryURL"]
    require(url in expected_packages, "Unexpected SDK source")
    require(package["requirement"] == {"kind": "exactVersion", "version": expected_packages[url]}, "SDK must be pinned")
products = {objects[key]["productName"] for key in targets["FLTiya"]["packageProductDependencies"]}
require(products == {"Supabase", "LiveKit"}, "Missing Supabase/LiveKit product")
source_counts = {}
for name in ("FLTiya", "FLTiyaTests"):
    included = []
    for key in targets[name]["buildPhases"]:
        phase = objects[key]
        if phase["isa"] == "PBXSourcesBuildPhase":
            included.extend(file_paths[objects[file]["fileRef"]] for file in phase["files"])
    expected = set((ROOT / name).rglob("*.swift"))
    require(set(included) == expected and len(included) == len(expected), "Incorrect source membership: " + name)
    source_counts[name] = len(included)

# Source presence alone does not make a license notice available to Bundle.main.
# Require every bundled text notice exactly once in the app's resources phase.
resource_paths = []
for key in targets["FLTiya"]["buildPhases"]:
    phase = objects[key]
    if phase["isa"] == "PBXResourcesBuildPhase":
        resource_paths.extend(file_paths[objects[file]["fileRef"]] for file in phase["files"])
text_notices = set((ROOT / "FLTiya/Resources").rglob("*.txt"))
require(all(resource_paths.count(path) == 1 for path in text_notices), "Text notice is not bundled exactly once")
bundled_json = set((ROOT / "FLTiya/Resources").glob("*.json"))
for path in bundled_json:
    json.loads(path.read_text(encoding="utf-8"))
    require(resource_paths.count(path) == 1, "JSON document is not bundled exactly once: " + path.name)
freedoom_notice = ROOT / "FLTiya/Resources/FreedoomLicense.txt"
require(freedoom_notice in text_notices, "Missing Freedoom license notice")
notice = freedoom_notice.read_text(encoding="utf-8")
require("Copyright © 2001-2024" in notice and "Contributors to the Freedoom project" in notice
        and "Redistribution and use in source and binary forms" in notice
        and "Neither the name of the Freedoom project" in notice
        and "THIS SOFTWARE IS PROVIDED" in notice
        and "SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE." in notice,
        "Incomplete Freedoom copyright, BSD conditions or disclaimer")

def configuration_settings(owner):
    return {objects[key]["name"]: objects[key]["buildSettings"]
            for key in objects[owner["buildConfigurationList"]]["buildConfigurations"]}


project_settings = configuration_settings(project)
app_settings = configuration_settings(targets["FLTiya"])
for settings in app_settings.values():
    require(bool(settings.get("INFOPLIST_KEY_NSMicrophoneUsageDescription")), "Missing microphone purpose")
    require(bool(settings.get("INFOPLIST_KEY_NSCameraUsageDescription")), "Missing camera purpose")
    require(settings.get("ASSETCATALOG_COMPILER_APPICON_NAME") == "AppIcon", "Missing app icon selection")
    require("@executable_path/Frameworks" in settings.get("LD_RUNPATH_SEARCH_PATHS", []),
            "Missing embedded-framework runtime search path")
expected_configurations = {"Debug", "Preview", "CommunityTesting", "Release"}
require(set(project_settings) == expected_configurations, "Missing build configuration")
for settings in project_settings.values():
    require(settings["IPHONEOS_DEPLOYMENT_TARGET"] == "17.0", "Unexpected deployment target")
    require(settings["SWIFT_VERSION"] == "5.0", "Unexpected Swift language mode")

def compilation_conditions(settings):
    value = settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "")
    return set(value if isinstance(value, list) else value.split())


require({"DEBUG", "DEVELOPMENT_PREVIEW"} <= compilation_conditions(project_settings["Preview"]),
        "Preview requires explicit debug and preview conditions")
for owner in (project, *targets.values()):
    configurations = configuration_settings(owner)
    require(set(configurations) == expected_configurations, "Inconsistent build configurations")
    require(not ({"DEBUG", "DEVELOPMENT_PREVIEW", "COMMUNITY_TESTING"} & compilation_conditions(configurations["Release"])),
            "Release must exclude development compilation conditions")
    require(all("COMMUNITY_TESTING" not in compilation_conditions(settings)
                for name, settings in configurations.items() if name != "CommunityTesting"),
            "Test account switching must be isolated to CommunityTesting")
require(app_settings["Preview"]["PRODUCT_BUNDLE_IDENTIFIER"] != app_settings["Debug"]["PRODUCT_BUNDLE_IDENTIFIER"],
        "Preview must have a distinct app identity")
require(app_settings["Preview"]["INFOPLIST_KEY_CFBundleDisplayName"] == "TIYA Preview", "Missing preview app label")
require(not app_settings["Preview"].get("CODE_SIGN_ENTITLEMENTS"), "Offline preview must not request Apple capability")
require({"DEBUG", "COMMUNITY_TESTING"} <= compilation_conditions(project_settings["CommunityTesting"]),
        "Community testing needs its own compile-time sign-in gate")
community_app = app_settings["CommunityTesting"]
require(community_app["PRODUCT_BUNDLE_IDENTIFIER"] == "com.fltiya.ios.development.community"
        and all(settings["PRODUCT_BUNDLE_IDENTIFIER"] != community_app["PRODUCT_BUNDLE_IDENTIFIER"]
                for name, settings in app_settings.items() if name != "CommunityTesting"),
        "Community testing must use a distinct installation and auth storage")
require(community_app["INFOPLIST_KEY_CFBundleDisplayName"] == "TIYA Social Test"
        and not community_app.get("CODE_SIGN_ENTITLEMENTS"),
        "Community testing must have a separate app label and no Apple sign-in entitlement")

with (ROOT / "FLTiya/Resources/FLTiya.entitlements").open("rb") as file:
    entitlements = plistlib.load(file)
require(entitlements == {"com.apple.developer.applesignin": ["Default"]}, "Unexpected entitlements")
for path in (ROOT / "FLTiya").rglob("*.plist"):
    with path.open("rb") as file:
        plistlib.load(file)
asset_json = list((ROOT / "FLTiya/Resources/Assets.xcassets").rglob("*.json"))
for path in asset_json:
    json.loads(path.read_text())

icon_directory = ROOT / "FLTiya/Resources/Assets.xcassets/AppIcon.appiconset"
icon_manifest = json.loads((icon_directory / "Contents.json").read_text())
require(icon_manifest["images"] == [{"filename": "AppIcon.png", "idiom": "universal",
                                     "platform": "ios", "size": "1024x1024"}], "Unexpected app icon manifest")
icon_png = (icon_directory / "AppIcon.png").read_bytes()
require(icon_png[:16] == b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR", "App icon must be PNG")
require(int.from_bytes(icon_png[16:20], "big") == 1024
        and int.from_bytes(icon_png[20:24], "big") == 1024, "App icon must be 1024 square")
require(icon_png[25] == 2 and b"tRNS" not in icon_png, "App icon must be opaque RGB")
require(resource_paths.count(icon_directory.parent) == 1, "App icon catalog must be bundled once")

storekit_path = ROOT / "StoreKit/FLTiya.storekit"
require(storekit_path.exists(), "Missing local StoreKit configuration")
storekit = json.loads(storekit_path.read_text())
expected_amounts = [400, 800, 2450, 5150, 10800, 16800, 29400, 42700, 63700]
expected_prices = ["0.99", "1.99", "4.99", "9.99", "19.99", "29.99", "49.99", "69.99", "99.99"]
expected_products = {f"com.fltiya.local.sparks.{amount}": price
                     for amount, price in zip(expected_amounts, expected_prices)}
products = storekit["products"]
require(len(products) == 9 and len({p["productID"] for p in products}) == 9,
        "Expected nine unique local StoreKit products")
require({p["productID"]: p["displayPrice"] for p in products} == expected_products,
        "Local StoreKit catalog differs from agreed Sparks packs")
require(all(p["type"] == "Consumable" and p["familyShareable"] is False and p["localizations"] for p in products),
        "Local Sparks products must be localized non-shared consumables")
require(storekit["settings"]["_disableDialogs"] is False, "Local test payment sheet must remain enabled")
require(not storekit.get("subscriptionGroups"), "Sparks test config must not introduce subscriptions")
for target in targets.values():
    for phase_id in target["buildPhases"]:
        phase = objects[phase_id]
        if phase["isa"] == "PBXResourcesBuildPhase":
            require(all(file_paths[objects[file]["fileRef"]] != storekit_path for file in phase["files"]),
                    "StoreKit testing configuration must not be an app resource")

review_code_key = "FLTIYA_UI_REVIEW_ACCESS_CODE"
community_accounts_key = "FLTIYA_COMMUNITY_TEST_ACCOUNTS"
for name, run_configuration in (("FLTiya", "Debug"), ("FLTiyaPreview", "Preview"),
                                 ("FLTiyaStoreKitTesting", "Debug"),
                                 ("FLTiyaCommunityTesting", "CommunityTesting")):
    scheme = ET.parse(PROJECT / f"xcshareddata/xcschemes/{name}.xcscheme").getroot()
    require(scheme.find("LaunchAction").attrib["buildConfiguration"] == run_configuration, "Wrong scheme run configuration")
    for action in ("ArchiveAction", "ProfileAction"):
        require(scheme.find(action).attrib["buildConfiguration"] == "Release", "Distribution actions must use Release")
    launch = scheme.find("LaunchAction")
    reference = launch.find("StoreKitConfigurationFileReference")
    environment = {entry.attrib["key"]: entry.attrib for entry in launch.findall("EnvironmentVariables/EnvironmentVariable")}
    require(all(not entry.attrib.get("value") and entry.attrib.get("isEnabled") == "NO"
                for entry in scheme.iter("EnvironmentVariable")
                if entry.attrib["key"] in {review_code_key, community_accounts_key}),
            "Shared schemes must not store or enable private test credentials")
    if name == "FLTiyaCommunityTesting":
        require(community_accounts_key in environment and review_code_key not in environment,
                "Community test scheme needs the account list template, without auto-login")
        for action in ("TestAction", "ProfileAction"):
            require(scheme.find(action).attrib["shouldUseLaunchSchemeArgsEnv"] == "NO",
                    "Test and Profile must not inherit the community launch credentials")
    else:
        require(community_accounts_key not in environment, "Unexpected test account list in another shared scheme")
    if name in {"FLTiya", "FLTiyaStoreKitTesting"}:
        require(reference is not None and reference.attrib["identifier"] == "../../StoreKit/FLTiya.storekit",
                f"{name} Run must reference the standalone StoreKit config")
        # Xcode's identifier is relative to project.xcodeproj/xcshareddata,
        # matching Apple's downloadable StoreKit sample scheme.
        require((PROJECT / "xcshareddata" / reference.attrib["identifier"]).resolve() == storekit_path.resolve(),
                "Local StoreKit scheme path resolves incorrectly")
        require(environment.get("FLTIYA_LOCAL_STOREKIT_TESTING", {}).get("value") == "1"
                and environment["FLTIYA_LOCAL_STOREKIT_TESTING"]["isEnabled"] == "YES",
                "Local test scheme requires explicit Debug-only selection")
        require(scheme.find("ProfileAction").attrib["shouldUseLaunchSchemeArgsEnv"] == "NO",
                "Profiling must not inherit local test launch flags")
        if name == "FLTiya":
            require(scheme.find("TestAction").attrib["shouldUseLaunchSchemeArgsEnv"] == "NO",
                    "The main scheme's Test action must not inherit local payment settings")
    else:
        require(reference is None and "FLTIYA_LOCAL_STOREKIT_TESTING" not in environment,
                "Preview and community schemes must not activate local payments")
    for reference in scheme.iter("BuildableReference"):
        key = reference.attrib["BlueprintIdentifier"]
        require(key in objects and objects[key]["isa"] == "PBXNativeTarget", "Unknown scheme target")
        require(reference.attrib["ReferencedContainer"] == "container:FLTiya.xcodeproj", "Scheme leaves project")
ET.parse(PROJECT / "project.xcworkspace/contents.xcworkspacedata")

# -frontend -parse checks grammar only. It does not type-check, compile modules,
# link, execute tests, render previews or launch an app.
developer_directory = run(["/usr/bin/xcode-select", "-p"]).strip()
compiler = Path(developer_directory) / "Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
sources = sorted((ROOT / "FLTiya").rglob("*.swift")) + sorted((ROOT / "FLTiyaTests").rglob("*.swift"))
for conditions in ([], ["-D", "DEBUG"], ["-D", "DEBUG", "-D", "DEVELOPMENT_PREVIEW"],
                   ["-D", "DEBUG", "-D", "COMMUNITY_TESTING"]):
    run([str(compiler), "-frontend", "-parse", *conditions, *map(str, sources)])
print(json.dumps({
    "projectReferences": "valid", "sourceMembership": source_counts,
    "schemeAndWorkspaceXML": "valid", "assetJSONFiles": len(asset_json),
    "appIcon": "1024x1024 opaque RGB; selected in every app configuration",
    "bundledTextNotices": len(text_notices), "licenseNoticeResourceMembership": "valid",
    "bundledJSONDocuments": len(bundled_json), "jsonDocumentResourceMembership": "valid",
    "entitlements": "valid", "swiftGrammarFiles": len(sources), "swiftGrammar": "valid",
    "grammarConfigurations": ["Release", "Debug", "Preview", "CommunityTesting"], "previewConfigurationIsolation": "valid",
    "communityTestingSchemeIsolation": "valid",
    "localStoreKitProducts": len(products), "localStoreKitSchemeIsolation": "valid",
    "compiled": False, "testsExecuted": False, "appLaunched": False,
}, indent=2))
