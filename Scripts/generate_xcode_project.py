#!/usr/bin/env python3
"""Generate UltramarAI.xcodeproj from repo layout."""

from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT_NAME = "UltramarAI"
XCODEPROJ = ROOT / f"{PROJECT_NAME}.xcodeproj"
PBXPROJ = XCODEPROJ / "project.pbxproj"

APP_DIR = ROOT / PROJECT_NAME
PACKAGES = [
    ("UltramarCore", ROOT / "Packages/UltramarCore"),
    ("UltramarLLM", ROOT / "Packages/UltramarLLM"),
]

APP_SOURCES = [
    APP_DIR / "UltramarAIApp.swift",
    APP_DIR / "AppDelegate.swift",
    APP_DIR / "ContentView.swift",
]

BUNDLE_ID = "com.felipebasurto.ultramar"
DEPLOYMENT_TARGET = "26.0"
SWIFT_VERSION = "6.0"


def uid(seed: str) -> str:
    """Deterministic 24-char uppercase hex ID for pbxproj."""
    digest = hashlib.sha1(f"ultramar:{seed}".encode()).hexdigest()[:24]
    return digest.upper()


# Stable IDs
IDS = {
    "project": uid("project"),
    "main_group": uid("main_group"),
    "products_group": uid("products_group"),
    "frameworks_group": uid("frameworks_group"),
    "app_group": uid("app_group"),
    "packages_group": uid("packages_group"),
    "target": uid("target"),
    "target_config_list": uid("target_config_list"),
    "project_config_list": uid("project_config_list"),
    "debug_project": uid("debug_project"),
    "release_project": uid("release_project"),
    "debug_target": uid("debug_target"),
    "release_target": uid("release_target"),
    "sources_phase": uid("sources_phase"),
    "frameworks_phase": uid("frameworks_phase"),
    "resources_phase": uid("resources_phase"),
    "product_ref": uid("product_ref"),
    "assets_catalog": uid("assets_catalog"),
}

for name, _ in PACKAGES:
    IDS[f"pkg_{name}"] = uid(f"pkg_{name}")
    IDS[f"pkg_prod_{name}"] = uid(f"pkg_prod_{name}")

for i, src in enumerate(APP_SOURCES):
    IDS[f"src_{src.name}"] = uid(f"src_{src.name}")


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def build_file_ref(file_id: str, path: Path, last_known: str | None = None) -> str:
    name = path.name
    lk = last_known or name
    return (
        f"\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = sourcecode.swift; path = {lk}; sourceTree = \"<group>\"; }};"
    )


def write_pbxproj() -> None:
    file_refs: list[str] = []
    build_files: list[str] = []
    source_entries: list[str] = []
    package_refs: list[str] = []
    package_defs: list[str] = []
    product_deps: list[str] = []

    assets_id = IDS["assets_catalog"]
    file_refs.append(
        f"\t\t{assets_id} /* Assets.xcassets */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};"
    )
    build_assets = uid("build_assets")
    build_files.append(
        f"\t\t{build_assets} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; "
        f"fileRef = {assets_id} /* Assets.xcassets */; }};"
    )
    resource_entries = [
        f"\t\t\t\t{build_assets} /* Assets.xcassets in Resources */,"
    ]

    for src in APP_SOURCES:
        fid = IDS[f"src_{src.name}"]
        bf = uid(f"bf_{src.name}")
        file_refs.append(build_file_ref(fid, src))
        build_files.append(
            f"\t\t{bf} /* {src.name} in Sources */ = {{isa = PBXBuildFile; "
            f"fileRef = {fid} /* {src.name} */; }};"
        )
        source_entries.append(f"\t\t\t\t{bf} /* {src.name} in Sources */,")

    for pkg_name, pkg_path in PACKAGES:
        pkg_id = IDS[f"pkg_{pkg_name}"]
        prod_id = IDS[f"pkg_prod_{pkg_name}"]
        package_refs.append(
            f"\t\t{pkg_id} /* {pkg_name} */ = {{isa = XCLocalSwiftPackageReference; "
            f'relativePath = "{rel(pkg_path)}"; }};'
        )
        package_defs.append(
            f"\t\t{prod_id} /* {pkg_name} */ = {{isa = XCSwiftPackageProductDependency; "
            f"productName = {pkg_name}; package = {pkg_id} /* {pkg_name} */; }};"
        )
        product_deps.append(f"\t\t\t\t{prod_id} /* {pkg_name} */,")

    product_deps_block = "\n".join(product_deps)
    source_block = "\n".join(source_entries)
    resource_block = "\n".join(resource_entries)
    file_ref_block = "\n".join(file_refs)
    build_file_block = "\n".join(build_files)
    package_ref_block = "\n".join(package_refs)
    package_def_block = "\n".join(package_defs)
    project_package_refs_block = "\n".join(
        f"\t\t\t\t{IDS[f'pkg_{name}']} /* {name} */," for name, _ in PACKAGES
    )

    app_children = []
    for src in APP_SOURCES:
        app_children.append(f"\t\t\t\t{IDS[f'src_{src.name}']} /* {src.name} */,")
    app_children.append(f"\t\t\t\t{assets_id} /* Assets.xcassets */,")
    app_group_children = "\n".join(app_children)

    content = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXBuildFile section */
{build_file_block}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
\t\t{IDS['product_ref']} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {PROJECT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
{file_ref_block}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{IDS['frameworks_phase']} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{IDS['main_group']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{IDS['app_group']} /* {PROJECT_NAME} */,
\t\t\t\t{IDS['products_group']} /* Products */,
\t\t\t\t{IDS['frameworks_group']} /* Frameworks */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{IDS['app_group']} /* {PROJECT_NAME} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{app_group_children}
\t\t\t);
\t\t\tpath = {PROJECT_NAME};
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{IDS['products_group']} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{IDS['product_ref']} /* {PROJECT_NAME}.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{IDS['frameworks_group']} /* Frameworks */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t);
\t\t\tname = Frameworks;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{IDS['target']} /* {PROJECT_NAME} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {IDS['target_config_list']} /* Build configuration list for PBXNativeTarget "{PROJECT_NAME}" */;
\t\t\tbuildPhases = (
\t\t\t\t{IDS['sources_phase']} /* Sources */,
\t\t\t\t{IDS['frameworks_phase']} /* Frameworks */,
\t\t\t\t{IDS['resources_phase']} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = {PROJECT_NAME};
\t\t\tpackageProductDependencies = (
{product_deps_block}
\t\t\t);
\t\t\tproductName = {PROJECT_NAME};
\t\t\tproductReference = {IDS['product_ref']} /* {PROJECT_NAME}.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{IDS['project']} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2600;
\t\t\t\tLastUpgradeCheck = 2600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{IDS['target']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {IDS['project_config_list']} /* Build configuration list for PBXProject "{PROJECT_NAME}" */;
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {IDS['main_group']};
\t\t\tminimizedProjectReferenceProxies = 1;
\t\t\tpackageReferences = (
{project_package_refs_block}
\t\t\t);
\t\t\tpreferredProjectObjectVersion = 77;
\t\t\tproductRefGroup = {IDS['products_group']} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{IDS['target']} /* {PROJECT_NAME} */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{IDS['resources_phase']} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{resource_block}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{IDS['sources_phase']} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{source_block}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{IDS['debug_project']} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{IDS['release_project']} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = s;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{IDS['debug_target']} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Ultramar AI";
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{IDS['release_target']} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Ultramar AI";
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{IDS['project_config_list']} /* Build configuration list for PBXProject "{PROJECT_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{IDS['debug_project']} /* Debug */,
\t\t\t\t{IDS['release_project']} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{IDS['target_config_list']} /* Build configuration list for PBXNativeTarget "{PROJECT_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{IDS['debug_target']} /* Debug */,
\t\t\t\t{IDS['release_target']} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
{package_ref_block}
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
{package_def_block}
/* End XCSwiftPackageProductDependency section */
\t}};
\trootObject = {IDS['project']} /* Project object */;
}}
"""
    XCODEPROJ.mkdir(parents=True, exist_ok=True)
    PBXPROJ.write_text(content, encoding="utf-8")
    write_scheme(IDS["target"])


def write_scheme(target_id: str) -> None:
    scheme_dir = XCODEPROJ / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme_path = scheme_dir / f"{PROJECT_NAME}.xcscheme"
    scheme_path.write_text(
        f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "{PROJECT_NAME}.app"
               BlueprintName = "{PROJECT_NAME}"
               ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""",
        encoding="utf-8",
    )


def ensure_assets() -> None:
    assets = APP_DIR / "Assets.xcassets"
    appicon = assets / "AppIcon.appiconset"
    appicon.mkdir(parents=True, exist_ok=True)
    contents = {
        "images": [],
        "info": {"author": "xcode", "version": 1},
    }
    (appicon / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    (assets / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    os.chdir(ROOT)
    for src in APP_SOURCES:
        if not src.exists():
            print(f"Missing source file: {src}", file=sys.stderr)
            return 1
    for _, pkg in PACKAGES:
        if not (pkg / "Package.swift").exists():
            print(f"Missing package: {pkg / 'Package.swift'}", file=sys.stderr)
            return 1
    ensure_assets()
    write_pbxproj()
    print(f"Wrote {PBXPROJ.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
