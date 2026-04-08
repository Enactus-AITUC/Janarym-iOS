#!/usr/bin/env python3
"""
Google GenerativeAI (Gemini) SPM Injector for Janarym.xcodeproj
Adds GoogleGenerativeAI package via Swift Package Manager.

Пайдалану / Usage:
    1. python3 generate_xcodeproj.py    # алдымен жобаны қайта жасаңыз
    2. python3 inject_firebase_spm.py   # Firebase-ты қосыңыз
    3. python3 inject_gemini_spm.py     # Gemini-ді қосыңыз
    4. Xcode-та ашыңыз → Build
"""

import os
import re

# ── Path to pbxproj ────────────────────────────────────────────────────────────
BASE    = os.path.dirname(os.path.abspath(__file__))
PBXPROJ = os.path.join(BASE, "Janarym.xcodeproj", "project.pbxproj")

if not os.path.exists(PBXPROJ):
    print("❌ Janarym.xcodeproj/project.pbxproj табылмады.")
    print("   Алдымен: python3 generate_xcodeproj.py")
    exit(1)

# ── Fixed UUIDs (stable, idempotent) ──────────────────────────────────────────
GEMINI_PKG_REF   = "GE00001234567890ABCDEF01"   # XCRemoteSwiftPackageReference
GEMINI_PROD_DEP  = "GE00001234567890ABCDEF02"   # XCSwiftPackageProductDependency
GEMINI_FW_BUILD  = "GE00001234567890ABCDEF03"   # PBXBuildFile (Frameworks)
GEMINI_SRC_FREF  = "GE00001234567890ABCDEF04"   # PBXFileReference (GeminiLiveService.swift)
GEMINI_SRC_BUILD = "GE00001234567890ABCDEF05"   # PBXBuildFile (Sources)
GEMINI_GRP       = "GE00001234567890ABCDEF06"   # PBXGroup (Gemini)

with open(PBXPROJ, "r", encoding="utf-8") as f:
    content = f.read()

if GEMINI_PKG_REF in content:
    print("✅ GoogleGenerativeAI SPM already present — nothing to do.")
    exit(0)

# ── 1. PBXBuildFile ────────────────────────────────────────────────────────────
content = content.replace(
    "/* End PBXBuildFile section */",
    (
        f"\t\t{GEMINI_FW_BUILD} /* GoogleGenerativeAI in Frameworks */ = "
        f"{{isa = PBXBuildFile; productRef = {GEMINI_PROD_DEP} /* GoogleGenerativeAI */; }};\n"
        f"\t\t{GEMINI_SRC_BUILD} /* GeminiLiveService.swift in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {GEMINI_SRC_FREF} /* GeminiLiveService.swift */; }};\n"
        "/* End PBXBuildFile section */"
    )
)

# ── 2. PBXFileReference ────────────────────────────────────────────────────────
content = content.replace(
    "/* End PBXFileReference section */",
    (
        f"\t\t{GEMINI_SRC_FREF} /* GeminiLiveService.swift */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        f"name = GeminiLiveService.swift; "
        f"path = Janarym/Services/Gemini/GeminiLiveService.swift; "
        f"sourceTree = SOURCE_ROOT; }};\n"
        "/* End PBXFileReference section */"
    )
)

# ── 3. PBXFrameworksBuildPhase — GoogleGenerativeAI framework ─────────────────
#    generate_xcodeproj.py жасаған бос files = (); бөліміне немесе Firebase-тен кейін
if f"{GEMINI_FW_BUILD} /* GoogleGenerativeAI in Frameworks */" not in content:
    # Firebase inject болған жағдайда (бос емес files = (...))
    fw_pattern = r"(files = \([^)]*?\)\s*;\s*runOnlyForDeploymentPostprocessing = 0;\s*\};\s*/\* End PBXFrameworksBuildPhase section \*/)"
    match = re.search(fw_pattern, content, re.DOTALL)
    if match:
        old_block = match.group(0)
        new_entry = f"\t\t\t\t\t{GEMINI_FW_BUILD} /* GoogleGenerativeAI in Frameworks */,\n"
        # Соңғы ) алдына қосу
        new_block = old_block.replace(
            "\t\t\t\t);",
            new_entry + "\t\t\t\t);",
            1
        )
        content = content.replace(old_block, new_block)

# ── 4. PBXGroup — Gemini group (Services/Gemini) ──────────────────────────────
#    Егер generate_xcodeproj.py Gemini тобын қазір жасамаса — inject жасаймыз
if GEMINI_GRP not in content:
    content = content.replace(
        "/* End PBXGroup section */",
        (
            f"\t\t{GEMINI_GRP} /* Gemini */ = {{\n"
            f"\t\t\tisa = PBXGroup;\n"
            f"\t\t\tchildren = (\n"
            f"\t\t\t\t{GEMINI_SRC_FREF} /* GeminiLiveService.swift */,\n"
            f"\t\t\t);\n"
            f"\t\t\tpath = Gemini;\n"
            f"\t\t\tsourceTree = \"<group>\";\n"
            f"\t\t}};\n"
            "/* End PBXGroup section */"
        )
    )

# ── 5. PBXNativeTarget — packageProductDependencies ───────────────────────────
if "packageProductDependencies" in content:
    # Firebase inject'тен кейін — тізімге қосу
    # Соңғы жазба жолынан кейін қосу
    content = content.replace(
        f"\t\t\tproductName = Janarym;",
        (
            f"\t\t\tproductName = Janarym;"
        ),
        1
    )
    # packageProductDependencies тізімінің соңына Gemini-ді қосу
    content = re.sub(
        r"(packageProductDependencies = \([^)]*?)(\s*\);)",
        lambda m: m.group(1) + f"\n\t\t\t\t{GEMINI_PROD_DEP} /* GoogleGenerativeAI */," + m.group(2),
        content,
        count=1
    )
else:
    # Firebase inject болмаса — packageProductDependencies бөлімін жаңадан қосу
    content = content.replace(
        "\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = Janarym;\n\t\t\tproductName = Janarym;",
        (
            f"\t\t\tdependencies = (\n\t\t\t);\n"
            f"\t\t\tname = Janarym;\n"
            f"\t\t\tpackageProductDependencies = (\n"
            f"\t\t\t\t{GEMINI_PROD_DEP} /* GoogleGenerativeAI */,\n"
            f"\t\t\t);\n"
            f"\t\t\tproductName = Janarym;"
        )
    )

# ── 6. PBXProject — packageReferences ─────────────────────────────────────────
if "packageReferences" in content:
    # Firebase inject'тен кейін — тізімге қосу
    content = re.sub(
        r"(packageReferences = \([^)]*?)(\s*\);)",
        lambda m: m.group(1) + f"\n\t\t\t\t{GEMINI_PKG_REF} /* XCRemoteSwiftPackageReference \"generative-ai-swift\" */," + m.group(2),
        content,
        count=1
    )
else:
    content = content.replace(
        "\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (",
        (
            f"\t\t\tpackageReferences = (\n"
            f"\t\t\t\t{GEMINI_PKG_REF} /* XCRemoteSwiftPackageReference \"generative-ai-swift\" */,\n"
            f"\t\t\t);\n"
            f"\t\t\tprojectDirPath = \"\";\n"
            f"\t\t\tprojectRoot = \"\";\n"
            f"\t\t\ttargets = ("
        )
    )

# ── 7. Sources build phase — GeminiLiveService.swift ──────────────────────────
#    SpeechSynthesizerService.swift жолынан кейін қосу (generate_xcodeproj.py-ден белгілі)
if "GeminiLiveService.swift in Sources" not in content:
    content = re.sub(
        r"(/\* SpeechSynthesizerService\.swift in Sources \*/,)",
        r"\1\n\t\t\t\t\t" + GEMINI_SRC_BUILD + r" /* GeminiLiveService.swift in Sources */,",
        content,
        count=1
    )

# ── 8. XCRemoteSwiftPackageReference + XCSwiftPackageProductDependency ─────────
new_spm = (
    "/* Begin XCRemoteSwiftPackageReference section */\n"
    f"\t\t{GEMINI_PKG_REF} /* XCRemoteSwiftPackageReference \"generative-ai-swift\" */ = {{\n"
    f"\t\t\tisa = XCRemoteSwiftPackageReference;\n"
    f"\t\t\trepositoryURL = \"https://github.com/google/generative-ai-swift\";\n"
    f"\t\t\trequirement = {{\n"
    f"\t\t\t\tkind = upToNextMajorVersion;\n"
    f"\t\t\t\tminimumVersion = 1.0.0;\n"
    f"\t\t\t}};\n"
    f"\t\t}};\n"
    "/* End XCRemoteSwiftPackageReference section */\n\n"
    "/* Begin XCSwiftPackageProductDependency section */\n"
    f"\t\t{GEMINI_PROD_DEP} /* GoogleGenerativeAI */ = {{\n"
    f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
    f"\t\t\tpackage = {GEMINI_PKG_REF} /* XCRemoteSwiftPackageReference \"generative-ai-swift\" */;\n"
    f"\t\t\tproductName = GoogleGenerativeAI;\n"
    f"\t\t}};\n"
    "/* End XCSwiftPackageProductDependency section */\n\n"
)

# Firebase inject болса, XCRemoteSwiftPackageReference бөлімі бар
if "/* Begin XCRemoteSwiftPackageReference section */" in content:
    # Firebase бөліміне қосу — соңынан алдын
    content = content.replace(
        "/* End XCRemoteSwiftPackageReference section */",
        (
            f"\t\t{GEMINI_PKG_REF} /* XCRemoteSwiftPackageReference \"generative-ai-swift\" */ = {{\n"
            f"\t\t\tisa = XCRemoteSwiftPackageReference;\n"
            f"\t\t\trepositoryURL = \"https://github.com/google/generative-ai-swift\";\n"
            f"\t\t\trequirement = {{\n"
            f"\t\t\t\tkind = upToNextMajorVersion;\n"
            f"\t\t\t\tminimumVersion = 1.0.0;\n"
            f"\t\t\t}};\n"
            f"\t\t}};\n"
            "/* End XCRemoteSwiftPackageReference section */"
        ),
        1
    )
    content = content.replace(
        "/* End XCSwiftPackageProductDependency section */",
        (
            f"\t\t{GEMINI_PROD_DEP} /* GoogleGenerativeAI */ = {{\n"
            f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
            f"\t\t\tpackage = {GEMINI_PKG_REF} /* XCRemoteSwiftPackageReference \"generative-ai-swift\" */;\n"
            f"\t\t\tproductName = GoogleGenerativeAI;\n"
            f"\t\t}};\n"
            "/* End XCSwiftPackageProductDependency section */"
        ),
        1
    )
else:
    # Firebase inject болмаса — XCConfigurationList алдына толық бөлім қосу
    content = content.replace(
        "/* Begin XCConfigurationList section */",
        new_spm + "/* Begin XCConfigurationList section */"
    )

# ── Write ─────────────────────────────────────────────────────────────────────
with open(PBXPROJ, "w", encoding="utf-8") as f:
    f.write(content)

print("✅ GoogleGenerativeAI SPM successfully injected into Janarym.xcodeproj!")
print("   Package: https://github.com/google/generative-ai-swift (≥ 1.0.0)")
print("   File:    Janarym/Services/Gemini/GeminiLiveService.swift")
print()
print("   Келесі қадамдар / Next steps:")
print("   1. Xcode-та File → Packages → Resolve Package Versions")
print("   2. Secrets.plist-ке GEMINI_API_KEY қосыңыз")
print("   3. Build & Run")
