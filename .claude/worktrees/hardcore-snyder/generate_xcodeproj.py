#!/usr/bin/env python3
"""Generates Janarym.xcodeproj/project.pbxproj for the Janarym iOS app."""

import os
import uuid

BASE = os.path.dirname(os.path.abspath(__file__))
PROJ_DIR = os.path.join(BASE, "Janarym.xcodeproj")
os.makedirs(PROJ_DIR, exist_ok=True)

def uid():
    return uuid.uuid4().hex[:24].upper()

# ── Fixed UUIDs ────────────────────────────────────────────────────────────────
PROJECT_UID           = uid()
MAIN_GROUP_UID        = uid()
JANARYM_GROUP_UID     = uid()
PRODUCTS_GROUP_UID    = uid()
APP_GROUP_UID         = uid()
CORE_GROUP_UID        = uid()
FEATURES_GROUP_UID    = uid()
CAM_GROUP_UID         = uid()
PERM_GROUP_UID        = uid()
ASST_GROUP_UID        = uid()
MODES_GROUP_UID       = uid()
SVC_GROUP_UID         = uid()
OPENAI_GROUP_UID      = uid()
SPEECH_GROUP_UID      = uid()
GEMINI_GROUP_UID      = uid()
RES_GROUP_UID         = uid()
TARGET_UID            = uid()
SRC_PHASE_UID         = uid()
RES_PHASE_UID         = uid()
FW_PHASE_UID          = uid()
PROJ_CFGLIST_UID      = uid()
TGT_CFGLIST_UID       = uid()
PROJ_DEBUG_UID        = uid()
PROJ_RELEASE_UID      = uid()
TGT_DEBUG_UID         = uid()
TGT_RELEASE_UID       = uid()
PRODUCT_FILE_UID      = uid()

# ── Source files ───────────────────────────────────────────────────────────────
sources = [
    ("JanarymApp.swift",                  "Janarym/App/JanarymApp.swift",                      APP_GROUP_UID),
    ("RootView.swift",                    "Janarym/App/RootView.swift",                         APP_GROUP_UID),
    ("AppLifecycleCoordinator.swift",     "Janarym/App/AppLifecycleCoordinator.swift",          APP_GROUP_UID),
    ("AppConfig.swift",                   "Janarym/Core/AppConfig.swift",                       CORE_GROUP_UID),
    ("AudioSessionManager.swift",         "Janarym/Core/AudioSessionManager.swift",              CORE_GROUP_UID),
    ("AppError.swift",                    "Janarym/Core/AppError.swift",                        CORE_GROUP_UID),
    ("AssistantMode.swift",               "Janarym/Core/AssistantMode.swift",                   CORE_GROUP_UID),
    ("LanguageResolver.swift",            "Janarym/Core/LanguageResolver.swift",                CORE_GROUP_UID),
    ("StringNormalizer.swift",            "Janarym/Core/StringNormalizer.swift",                CORE_GROUP_UID),
    ("CameraService.swift",               "Janarym/Features/Camera/CameraService.swift",        CAM_GROUP_UID),
    ("CameraPreviewView.swift",           "Janarym/Features/Camera/CameraPreviewView.swift",    CAM_GROUP_UID),
    ("PermissionManager.swift",           "Janarym/Features/Permissions/PermissionManager.swift", PERM_GROUP_UID),
    ("PermissionsView.swift",             "Janarym/Features/Permissions/PermissionsView.swift", PERM_GROUP_UID),
    ("AssistantCoordinator.swift",        "Janarym/Features/Assistant/AssistantCoordinator.swift", ASST_GROUP_UID),
    ("ConversationStore.swift",           "Janarym/Features/Assistant/ConversationStore.swift", ASST_GROUP_UID),
    ("SpeechRecorder.swift",              "Janarym/Features/Assistant/SpeechRecorder.swift",    ASST_GROUP_UID),
    ("WakeWordListener.swift",            "Janarym/Features/Assistant/WakeWordListener.swift",  ASST_GROUP_UID),
    ("ModesSheetView.swift",              "Janarym/Features/Modes/ModesSheetView.swift",         MODES_GROUP_UID),
    ("ChatCompletionService.swift",       "Janarym/Services/OpenAI/ChatCompletionService.swift", OPENAI_GROUP_UID),
    ("MultipartFormDataBuilder.swift",    "Janarym/Services/OpenAI/MultipartFormDataBuilder.swift", OPENAI_GROUP_UID),
    ("OpenAIClient.swift",                "Janarym/Services/OpenAI/OpenAIClient.swift",          OPENAI_GROUP_UID),
    ("WhisperTranscriptionService.swift", "Janarym/Services/OpenAI/WhisperTranscriptionService.swift", OPENAI_GROUP_UID),
    ("SpeechSynthesizerService.swift",    "Janarym/Services/Speech/SpeechSynthesizerService.swift", SPEECH_GROUP_UID),
    ("GeminiLiveService.swift",           "Janarym/Services/Gemini/GeminiLiveService.swift",        GEMINI_GROUP_UID),
]

resources = [
    ("Secrets.plist",         "Janarym/Resources/Secrets.plist",         RES_GROUP_UID),
    ("Secrets.example.plist", "Janarym/Resources/Secrets.example.plist", RES_GROUP_UID),
]

info_plist_path = "Janarym/Resources/Info.plist"
INFO_PLIST_UID = uid()

# Assign UIDs
for entry in sources:
    entry = list(entry)
src_uids  = [(name, path, grp, uid(), uid()) for name, path, grp in sources]
#              name, path, group, fileref_uid, buildfile_uid
res_uids  = [(name, path, grp, uid(), uid()) for name, path, grp in resources]

# ── Build group child lists ────────────────────────────────────────────────────
group_children = {
    APP_GROUP_UID:    [],
    CORE_GROUP_UID:   [],
    CAM_GROUP_UID:    [],
    PERM_GROUP_UID:   [],
    ASST_GROUP_UID:   [],
    MODES_GROUP_UID:  [],
    OPENAI_GROUP_UID: [],
    SPEECH_GROUP_UID: [],
    GEMINI_GROUP_UID: [],
    RES_GROUP_UID:    [INFO_PLIST_UID],
}

for name, path, grp, fref, bfid in src_uids:
    group_children[grp].append(fref)

for name, path, grp, fref, bfid in res_uids:
    group_children[grp].append(fref)

def children_str(lst):
    return "\n\t\t\t\t".join(lst)

# ── Assemble pbxproj ───────────────────────────────────────────────────────────
lines = []

def L(s=""):
    lines.append(s)

L("// !$*UTF8*$!")
L("{")
L("\tarchiveVersion = 1;")
L("\tclasses = {")
L("\t};")
L("\tobjectVersion = 56;")
L("\tobjects = {")
L()

# PBXBuildFile
L("/* Begin PBXBuildFile section */")
for name, path, grp, fref, bfid in src_uids:
    L(f"\t\t{bfid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};")
for name, path, grp, fref, bfid in res_uids:
    L(f"\t\t{bfid} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};")
L("/* End PBXBuildFile section */")
L()

# PBXFileReference
L("/* Begin PBXFileReference section */")
L(f"\t\t{PRODUCT_FILE_UID} /* Janarym.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Janarym.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
L(f"\t\t{INFO_PLIST_UID} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
for name, path, grp, fref, bfid in src_uids:
    L(f"\t\t{fref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};")
for name, path, grp, fref, bfid in res_uids:
    L(f"\t\t{fref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {name}; sourceTree = \"<group>\"; }};")
L("/* End PBXFileReference section */")
L()

# PBXFrameworksBuildPhase
L("/* Begin PBXFrameworksBuildPhase section */")
L(f"\t\t{FW_PHASE_UID} /* Frameworks */ = {{")
L("\t\t\tisa = PBXFrameworksBuildPhase;")
L("\t\t\tbuildActionMask = 2147483647;")
L("\t\t\tfiles = (")
L("\t\t\t);")
L("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
L("\t\t};")
L("/* End PBXFrameworksBuildPhase section */")
L()

# PBXGroup
L("/* Begin PBXGroup section */")

# Root main group
L(f"\t\t{MAIN_GROUP_UID} = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
L(f"\t\t\t\t{JANARYM_GROUP_UID} /* Janarym */,")
L(f"\t\t\t\t{PRODUCTS_GROUP_UID} /* Products */,")
L("\t\t\t);")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")
L()
# Janarym wrapper group (path = Janarym)
L(f"\t\t{JANARYM_GROUP_UID} /* Janarym */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
L(f"\t\t\t\t{APP_GROUP_UID} /* App */,")
L(f"\t\t\t\t{CORE_GROUP_UID} /* Core */,")
L(f"\t\t\t\t{FEATURES_GROUP_UID} /* Features */,")
L(f"\t\t\t\t{SVC_GROUP_UID} /* Services */,")
L(f"\t\t\t\t{RES_GROUP_UID} /* Resources */,")
L("\t\t\t);")
L("\t\t\tpath = Janarym;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

# Products
L(f"\t\t{PRODUCTS_GROUP_UID} /* Products */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
L(f"\t\t\t\t{PRODUCT_FILE_UID} /* Janarym.app */,")
L("\t\t\t);")
L("\t\t\tname = Products;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

# App group
L(f"\t\t{APP_GROUP_UID} /* App */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
for fref in group_children[APP_GROUP_UID]:
    name = next(n for n, p, g, f, b in src_uids if f == fref)
    L(f"\t\t\t\t{fref} /* {name} */,")
L("\t\t\t);")
L("\t\t\tpath = App;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

# Core group
L(f"\t\t{CORE_GROUP_UID} /* Core */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
for fref in group_children[CORE_GROUP_UID]:
    name = next(n for n, p, g, f, b in src_uids if f == fref)
    L(f"\t\t\t\t{fref} /* {name} */,")
L("\t\t\t);")
L("\t\t\tpath = Core;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

# Features group
L(f"\t\t{FEATURES_GROUP_UID} /* Features */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
L(f"\t\t\t\t{CAM_GROUP_UID} /* Camera */,")
L(f"\t\t\t\t{PERM_GROUP_UID} /* Permissions */,")
L(f"\t\t\t\t{ASST_GROUP_UID} /* Assistant */,")
L(f"\t\t\t\t{MODES_GROUP_UID} /* Modes */,")
L("\t\t\t);")
L("\t\t\tpath = Features;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

# Camera group
L(f"\t\t{CAM_GROUP_UID} /* Camera */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
for fref in group_children[CAM_GROUP_UID]:
    name = next(n for n, p, g, f, b in src_uids if f == fref)
    L(f"\t\t\t\t{fref} /* {name} */,")
L("\t\t\t);")
L("\t\t\tpath = Camera;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

# Permissions group
L(f"\t\t{PERM_GROUP_UID} /* Permissions */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
for fref in group_children[PERM_GROUP_UID]:
    name = next(n for n, p, g, f, b in src_uids if f == fref)
    L(f"\t\t\t\t{fref} /* {name} */,")
L("\t\t\t);")
L("\t\t\tpath = Permissions;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

# Assistant group
L(f"\t\t{ASST_GROUP_UID} /* Assistant */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
for fref in group_children[ASST_GROUP_UID]:
    name = next(n for n, p, g, f, b in src_uids if f == fref)
    L(f"\t\t\t\t{fref} /* {name} */,")
L("\t\t\t);")
L("\t\t\tpath = Assistant;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

# Modes group
L(f"\t\t{MODES_GROUP_UID} /* Modes */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
for fref in group_children[MODES_GROUP_UID]:
    name = next(n for n, p, g, f, b in src_uids if f == fref)
    L(f"\t\t\t\t{fref} /* {name} */,")
L("\t\t\t);")
L("\t\t\tpath = Modes;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

# Services group
L(f"\t\t{SVC_GROUP_UID} /* Services */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
L(f"\t\t\t\t{OPENAI_GROUP_UID} /* OpenAI */,")
L(f"\t\t\t\t{SPEECH_GROUP_UID} /* Speech */,")
L(f"\t\t\t\t{GEMINI_GROUP_UID} /* Gemini */,")
L("\t\t\t);")
L("\t\t\tpath = Services;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

# OpenAI group
L(f"\t\t{OPENAI_GROUP_UID} /* OpenAI */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
for fref in group_children[OPENAI_GROUP_UID]:
    name = next(n for n, p, g, f, b in src_uids if f == fref)
    L(f"\t\t\t\t{fref} /* {name} */,")
L("\t\t\t);")
L("\t\t\tpath = OpenAI;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

# Speech service group
L(f"\t\t{SPEECH_GROUP_UID} /* Speech */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
for fref in group_children[SPEECH_GROUP_UID]:
    name = next(n for n, p, g, f, b in src_uids if f == fref)
    L(f"\t\t\t\t{fref} /* {name} */,")
L("\t\t\t);")
L("\t\t\tpath = Speech;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

# Gemini service group
L(f"\t\t{GEMINI_GROUP_UID} /* Gemini */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
for fref in group_children[GEMINI_GROUP_UID]:
    name = next(n for n, p, g, f, b in src_uids if f == fref)
    L(f"\t\t\t\t{fref} /* {name} */,")
L("\t\t\t);")
L("\t\t\tpath = Gemini;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

# Resources group
L(f"\t\t{RES_GROUP_UID} /* Resources */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
L(f"\t\t\t\t{INFO_PLIST_UID} /* Info.plist */,")
for fref in group_children[RES_GROUP_UID]:
    if fref == INFO_PLIST_UID:
        continue
    name = next(n for n, p, g, f, b in res_uids if f == fref)
    L(f"\t\t\t\t{fref} /* {name} */,")
L("\t\t\t);")
L("\t\t\tpath = Resources;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")

L("/* End PBXGroup section */")
L()

# PBXNativeTarget
L("/* Begin PBXNativeTarget section */")
L(f"\t\t{TARGET_UID} /* Janarym */ = {{")
L("\t\t\tisa = PBXNativeTarget;")
L(f"\t\t\tbuildConfigurationList = {TGT_CFGLIST_UID} /* Build configuration list for PBXNativeTarget \"Janarym\" */;")
L("\t\t\tbuildPhases = (")
L(f"\t\t\t\t{SRC_PHASE_UID} /* Sources */,")
L(f"\t\t\t\t{RES_PHASE_UID} /* Resources */,")
L(f"\t\t\t\t{FW_PHASE_UID} /* Frameworks */,")
L("\t\t\t);")
L("\t\t\tbuildRules = (")
L("\t\t\t);")
L("\t\t\tdependencies = (")
L("\t\t\t);")
L("\t\t\tname = Janarym;")
L(f"\t\t\tproductName = Janarym;")
L(f"\t\t\tproductReference = {PRODUCT_FILE_UID} /* Janarym.app */;")
L("\t\t\tproductType = \"com.apple.product-type.application\";")
L("\t\t};")
L("/* End PBXNativeTarget section */")
L()

# PBXProject
L("/* Begin PBXProject section */")
L(f"\t\t{PROJECT_UID} /* Project object */ = {{")
L("\t\t\tisa = PBXProject;")
L("\t\t\tattributes = {")
L("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
L("\t\t\t\tLastSwiftUpdateCheck = 1500;")
L("\t\t\t\tLastUpgradeCheck = 1500;")
L(f"\t\t\t\tTargetAttributes = {{")
L(f"\t\t\t\t\t{TARGET_UID} = {{")
L("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
L("\t\t\t\t\t};")
L("\t\t\t\t};")
L("\t\t\t};")
L(f"\t\t\tbuildConfigurationList = {PROJ_CFGLIST_UID} /* Build configuration list for PBXProject \"Janarym\" */;")
L("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
L("\t\t\tdevelopmentRegion = en;")
L("\t\t\thasScannedForEncodings = 0;")
L("\t\t\tknownRegions = (")
L("\t\t\t\ten,")
L("\t\t\t\tBase,")
L("\t\t\t);")
L(f"\t\t\tmainGroup = {MAIN_GROUP_UID};")
L(f"\t\t\tproductRefGroup = {PRODUCTS_GROUP_UID} /* Products */;")
L("\t\t\tprojectDirPath = \"\";")
L("\t\t\tprojectRoot = \"\";")
L("\t\t\ttargets = (")
L(f"\t\t\t\t{TARGET_UID} /* Janarym */,")
L("\t\t\t);")
L("\t\t};")
L("/* End PBXProject section */")
L()

# PBXResourcesBuildPhase
L("/* Begin PBXResourcesBuildPhase section */")
L(f"\t\t{RES_PHASE_UID} /* Resources */ = {{")
L("\t\t\tisa = PBXResourcesBuildPhase;")
L("\t\t\tbuildActionMask = 2147483647;")
L("\t\t\tfiles = (")
for name, path, grp, fref, bfid in res_uids:
    L(f"\t\t\t\t{bfid} /* {name} in Resources */,")
L("\t\t\t);")
L("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
L("\t\t};")
L("/* End PBXResourcesBuildPhase section */")
L()

# PBXSourcesBuildPhase
L("/* Begin PBXSourcesBuildPhase section */")
L(f"\t\t{SRC_PHASE_UID} /* Sources */ = {{")
L("\t\t\tisa = PBXSourcesBuildPhase;")
L("\t\t\tbuildActionMask = 2147483647;")
L("\t\t\tfiles = (")
for name, path, grp, fref, bfid in src_uids:
    L(f"\t\t\t\t{bfid} /* {name} in Sources */,")
L("\t\t\t);")
L("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
L("\t\t};")
L("/* End PBXSourcesBuildPhase section */")
L()

# XCBuildConfiguration
L("/* Begin XCBuildConfiguration section */")

proj_debug_settings = """			ALWAYS_SEARCH_USER_PATHS = NO;
			ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
			CLANG_ANALYZER_NONNULL = YES;
			CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
			CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
			CLANG_ENABLE_MODULES = YES;
			CLANG_ENABLE_OBJC_ARC = YES;
			CLANG_ENABLE_OBJC_WEAK = YES;
			CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
			CLANG_WARN_BOOL_CONVERSION = YES;
			CLANG_WARN_COMMA = YES;
			CLANG_WARN_CONSTANT_CONVERSION = YES;
			CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
			CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
			CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
			CLANG_WARN_EMPTY_BODY = YES;
			CLANG_WARN_ENUM_CONVERSION = YES;
			CLANG_WARN_INFINITE_RECURSION = YES;
			CLANG_WARN_INT_CONVERSION = YES;
			CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
			CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
			CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
			CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
			CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
			CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
			CLANG_WARN_STRICT_PROTOTYPES = YES;
			CLANG_WARN_SUSPICIOUS_MOVE = YES;
			CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
			CLANG_WARN_UNREACHABLE_CODE = YES;
			CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
			COPY_PHASE_STRIP = NO;
			DEBUG_INFORMATION_FORMAT = dwarf;
			ENABLE_STRICT_OBJC_MSGSEND = YES;
			ENABLE_TESTABILITY = YES;
			ENABLE_USER_SCRIPT_SANDBOXING = YES;
			GCC_C_LANGUAGE_STANDARD = gnu17;
			GCC_DYNAMIC_NO_PIC = NO;
			GCC_NO_COMMON_BLOCKS = YES;
			GCC_OPTIMIZATION_LEVEL = 0;
			GCC_PREPROCESSOR_DEFINITIONS = (
				"DEBUG=1",
				"$(inherited)",
			);
			GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
			GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
			GCC_WARN_UNDECLARED_SELECTOR = YES;
			GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
			GCC_WARN_UNUSED_FUNCTION = YES;
			GCC_WARN_UNUSED_VARIABLE = YES;
			IPHONEOS_DEPLOYMENT_TARGET = 16.0;
			MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
			MTL_FAST_MATH = YES;
			ONLY_ACTIVE_ARCH = YES;
			SDKROOT = iphoneos;
			SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
			SWIFT_OPTIMIZATION_LEVEL = "-Onone";"""

proj_release_settings = """			ALWAYS_SEARCH_USER_PATHS = NO;
			ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
			CLANG_ANALYZER_NONNULL = YES;
			CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
			CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
			CLANG_ENABLE_MODULES = YES;
			CLANG_ENABLE_OBJC_ARC = YES;
			CLANG_ENABLE_OBJC_WEAK = YES;
			CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
			CLANG_WARN_BOOL_CONVERSION = YES;
			CLANG_WARN_COMMA = YES;
			CLANG_WARN_CONSTANT_CONVERSION = YES;
			CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
			CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
			CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
			CLANG_WARN_EMPTY_BODY = YES;
			CLANG_WARN_ENUM_CONVERSION = YES;
			CLANG_WARN_INFINITE_RECURSION = YES;
			CLANG_WARN_INT_CONVERSION = YES;
			CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
			CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
			CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
			CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
			CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
			CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
			CLANG_WARN_STRICT_PROTOTYPES = YES;
			CLANG_WARN_SUSPICIOUS_MOVE = YES;
			CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
			CLANG_WARN_UNREACHABLE_CODE = YES;
			CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
			COPY_PHASE_STRIP = NO;
			DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
			ENABLE_NS_ASSERTIONS = NO;
			ENABLE_STRICT_OBJC_MSGSEND = YES;
			ENABLE_USER_SCRIPT_SANDBOXING = YES;
			GCC_C_LANGUAGE_STANDARD = gnu17;
			GCC_NO_COMMON_BLOCKS = YES;
			GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
			GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
			GCC_WARN_UNDECLARED_SELECTOR = YES;
			GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
			GCC_WARN_UNUSED_FUNCTION = YES;
			GCC_WARN_UNUSED_VARIABLE = YES;
			IPHONEOS_DEPLOYMENT_TARGET = 16.0;
			MTL_FAST_MATH = YES;
			SDKROOT = iphoneos;
			SWIFT_COMPILATION_MODE = wholemodule;
			VALIDATE_PRODUCT = YES;"""

tgt_common_settings = f"""			ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
			ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
			CODE_SIGN_STYLE = Automatic;
			CURRENT_PROJECT_VERSION = 1;
			DEVELOPMENT_TEAM = "";
			ENABLE_PREVIEWS = YES;
			GENERATE_INFOPLIST_FILE = NO;
			INFOPLIST_FILE = Janarym/Resources/Info.plist;
			IPHONEOS_DEPLOYMENT_TARGET = 16.0;
			LD_RUNPATH_SEARCH_PATHS = (
				"$(inherited)",
				"@executable_path/Frameworks",
			);
			MARKETING_VERSION = 1.0;
			PRODUCT_BUNDLE_IDENTIFIER = "com.example.Janarym";
			PRODUCT_NAME = "$(TARGET_NAME)";
			SUPPORTS_MACCATALYST = NO;
			SWIFT_EMIT_LOC_STRINGS = YES;
			SWIFT_VERSION = 5.0;
			TARGETED_DEVICE_FAMILY = 1;"""

L(f"\t\t{PROJ_DEBUG_UID} /* Debug */ = {{")
L("\t\t\tisa = XCBuildConfiguration;")
L("\t\t\tbuildSettings = {")
L(proj_debug_settings)
L("\t\t\t};")
L("\t\t\tname = Debug;")
L("\t\t};")

L(f"\t\t{PROJ_RELEASE_UID} /* Release */ = {{")
L("\t\t\tisa = XCBuildConfiguration;")
L("\t\t\tbuildSettings = {")
L(proj_release_settings)
L("\t\t\t};")
L("\t\t\tname = Release;")
L("\t\t};")

L(f"\t\t{TGT_DEBUG_UID} /* Debug */ = {{")
L("\t\t\tisa = XCBuildConfiguration;")
L("\t\t\tbuildSettings = {")
L(tgt_common_settings)
L("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
L("\t\t\t};")
L("\t\t\tname = Debug;")
L("\t\t};")

L(f"\t\t{TGT_RELEASE_UID} /* Release */ = {{")
L("\t\t\tisa = XCBuildConfiguration;")
L("\t\t\tbuildSettings = {")
L(tgt_common_settings)
L("\t\t\t};")
L("\t\t\tname = Release;")
L("\t\t};")

L("/* End XCBuildConfiguration section */")
L()

# XCConfigurationList
L("/* Begin XCConfigurationList section */")

L(f"\t\t{PROJ_CFGLIST_UID} /* Build configuration list for PBXProject \"Janarym\" */ = {{")
L("\t\t\tisa = XCConfigurationList;")
L("\t\t\tbuildConfigurations = (")
L(f"\t\t\t\t{PROJ_DEBUG_UID} /* Debug */,")
L(f"\t\t\t\t{PROJ_RELEASE_UID} /* Release */,")
L("\t\t\t);")
L("\t\t\tdefaultConfigurationIsVisible = 0;")
L("\t\t\tdefaultConfigurationName = Release;")
L("\t\t};")

L(f"\t\t{TGT_CFGLIST_UID} /* Build configuration list for PBXNativeTarget \"Janarym\" */ = {{")
L("\t\t\tisa = XCConfigurationList;")
L("\t\t\tbuildConfigurations = (")
L(f"\t\t\t\t{TGT_DEBUG_UID} /* Debug */,")
L(f"\t\t\t\t{TGT_RELEASE_UID} /* Release */,")
L("\t\t\t);")
L("\t\t\tdefaultConfigurationIsVisible = 0;")
L("\t\t\tdefaultConfigurationName = Release;")
L("\t\t};")

L("/* End XCConfigurationList section */")
L()

L("\t};")
L(f"\trootObject = {PROJECT_UID} /* Project object */;")
L("}")

pbxproj = "\n".join(lines)
out = os.path.join(PROJ_DIR, "project.pbxproj")
with open(out, "w", encoding="utf-8") as f:
    f.write(pbxproj)

print(f"✅ Created: {out}")
print("Now run: open 'Janarym.xcodeproj'")
