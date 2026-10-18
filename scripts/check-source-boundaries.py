#!/usr/bin/env python3
"""Check the source distribution for private services and signing material."""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
).decode().split("\0")
private_extensions = {".p8", ".p12", ".pfx", ".key", ".pem", ".mobileprovision", ".provisionprofile", ".entitlements"}
private_directories = {"signing", "Sync", "AgentHUDServices"}
service_patterns = [
    r"\bimport\s+(?:CloudKit|UserNotifications|AgentHUDServices)\b",
    r"\b(?:CKContainer|CKDatabase|ICloudSync|LiveActivitySender|NotificationTracker)\b",
    r"com\.apple\.developer\.(?:icloud|aps|team-identifier)",
    r"\b(?:DEVELOPMENT_TEAM|NOTARY_PROFILE|ICLOUD_PROVISIONING_PROFILE)\b",
    r"iCloud\.",
]
secret_patterns = [
    r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    r"\bgh[pousr]_[A-Za-z0-9]{30,}\b",
    r"\bgithub_pat_[A-Za-z0-9_]{40,}\b",
    r"\bAKIA[0-9A-Z]{16}\b",
]
failures = []
# Core files the Windows build replaces, as Package.swift lists them in `windowsReplaced`.
_replaced = re.search(r"let windowsReplaced = \[(.*?)\]", (ROOT / "Package.swift").read_text(encoding="utf-8"), re.S)
windows_replaced = {"Sources/AgentHUDCore/" + item for item in re.findall(r'"([^"]+)"', _replaced.group(1))} if _replaced else set()
for name in sorted(set(filter(None, paths))):
    path = ROOT / name
    if not path.is_file():
        continue
    if path.suffix in private_extensions or private_directories.intersection(Path(name).parts):
        failures.append(f"{name}: private material is not a source asset")
    if (path.name.startswith(".env") and path.name != ".env.example") or ".local." in path.name:
        failures.append(f"{name}: local configuration is not a source asset")
    if path.is_symlink() and not path.resolve().is_relative_to(ROOT):
        failures.append(f"{name}: symlink points outside the package")
    try:
        # UTF-8 on every platform: Windows' default code page fails on, and so skips, most UTF-8 files.
        content = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    patterns = secret_patterns + (service_patterns if path.suffix in {".swift", ".sh", ".plist", ".yml"} else [])
    for pattern in patterns:
        if re.search(pattern, content):
            failures.append(f"{name}: prohibited source content ({pattern})")
    # Core reads the home folder through UserHome, which honours USERPROFILE on Windows (docs/windows-port D-020).
    # The macOS files the Windows build replaces never compile there and stay as upstream wrote them (D-006).
    if (name.startswith("Sources/AgentHUDCore/") and path.suffix == ".swift"
            and name != "Sources/AgentHUDCore/System/UserHome.swift"
            and not name.startswith("Sources/AgentHUDCore/Platform/Windows/")
            and name not in windows_replaced
            and "homeDirectoryForCurrentUser" in content):
        failures.append(f"{name}: read the home folder through UserHome.directory")

# The notices the application carries are the ones the repository publishes.
bundled = "Sources/AgentHUDDesktop/Resources/THIRD_PARTY_NOTICES.txt"
if (ROOT / "THIRD_PARTY_NOTICES.txt").read_bytes() != (ROOT / bundled).read_bytes():
    failures.append(f"{bundled}: differs from THIRD_PARTY_NOTICES.txt; copy the root file over it")

manifest = (ROOT / "Package.swift").read_text(encoding="utf-8")
if re.search(r"\.package\s*\(", manifest):
    failures.append("Package.swift: review external package dependencies before including them")

# The Windows shell's .NET projects (docs/windows-port, TASK.md G6): only the packages recorded in DECISIONS.md and
# THIRD_PARTY_NOTICES.txt, at their recorded versions, and only in test projects; no feed other than nuget.org.
import xml.etree.ElementTree as ElementTree

allowed_packages = {("Microsoft.NET.Test.Sdk", "18.0.1"), ("MSTest.TestAdapter", "4.0.2"), ("MSTest.TestFramework", "4.0.2")}
allowed_sdks = {"Microsoft.NET.Sdk", "Microsoft.NET.Sdk.WindowsDesktop"}
msbuild_suffixes = {".csproj", ".fsproj", ".vbproj", ".proj", ".props", ".targets"}
# The one NuGet configuration the repository may hold: every inherited feed cleared, nuget.org alone, every package
# mapped to it (D-042).
nuget_config = """<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
  <packageSourceMapping>
    <clear />
    <packageSource key="nuget.org">
      <package pattern="*" />
    </packageSource>
  </packageSourceMapping>
</configuration>
"""
notices = (ROOT / "THIRD_PARTY_NOTICES.txt").read_text(encoding="utf-8")
decisions = (ROOT / "docs/windows-port/DECISIONS.md").read_text(encoding="utf-8")


def local(tag):
    return tag.rsplit("}", 1)[-1]


for name in sorted(set(filter(None, paths))):
    path = ROOT / name
    if not path.is_file():
        continue
    lowered = Path(name).name.lower()
    if lowered == "packages.config":
        failures.append(f"{name}: packages come through PackageReference only")
    if lowered == "nuget.config":
        if name != "windows/nuget.config" or path.read_text(encoding="utf-8").replace("\r\n", "\n") != nuget_config:
            failures.append(f"{name}: only windows/nuget.config, clearing every feed for nuget.org alone, is allowed")
        continue
    if path.suffix.lower() not in msbuild_suffixes:
        continue
    try:
        project = ElementTree.parse(path).getroot()
    except ElementTree.ParseError as error:
        failures.append(f"{name}: not readable as MSBuild XML ({error})")
        continue
    for sdk in filter(None, (project.get("Sdk") or "").split(";")):
        if sdk.strip() not in allowed_sdks:
            failures.append(f"{name}: SDK {sdk.strip()} is not allowed")
    for element in project.iter():
        tag = local(element.tag)
        if tag in {"Sdk", "Import"} and element.get("Sdk" if tag == "Import" else "Name") not in (None, *allowed_sdks):
            failures.append(f"{name}: SDK {element.get('Sdk') or element.get('Name')} is not allowed")
        if tag in {"PackageVersion", "GlobalPackageReference", "PackageDownload"}:
            failures.append(f"{name}: {tag} is not used; each test project names its packages")
        if tag != "PackageReference":
            continue
        package = element.get("Include") or element.get("Update")
        version = element.get("Version") or next((local(child.tag) == "Version" and (child.text or "").strip() or None
                                                  for child in element if local(child.tag) == "Version"), None)
        if not package or not version:
            failures.append(f"{name}: every package reference names its package and version")
            continue
        if (package, version) not in allowed_packages:
            failures.append(f"{name}: package {package} {version} is not on the recorded list")
        elif not name.endswith(".Tests.csproj"):
            failures.append(f"{name}: package {package} belongs in a test project only")
        if f"{package} {version}" not in notices or package not in decisions:
            failures.append(f"{name}: {package} {version} must be named in THIRD_PARTY_NOTICES.txt and DECISIONS.md")

# Verify ignore rules without creating any secret-shaped files.
ignored = [".env", "signing/local.env", "config/service.local.json", "AuthKey_example.p8", "certificate.p12",
           "account.key", "development.mobileprovision", "build/Agent HUD Open.app/Contents/Info.plist", ".build/ignore-check/AgentHUDOpen",
           "windows/AgentHUD.Protocol/bin/Release/net10.0/AgentHUD.Protocol.dll", "windows/AgentHUD.Protocol/obj/project.assets.json",
           "windows/TestResults/run.trx"]
# Bytes, so that no platform writes the line ends as CR LF, which git would read as part of each path.
result = subprocess.run(["git", "check-ignore", "--stdin"], cwd=ROOT,
                        input=("\n".join(ignored)+"\n").encode(), capture_output=True)
missing = set(ignored) - set(result.stdout.decode().splitlines())
failures.extend(f".gitignore: missing rule for {name}" for name in sorted(missing))

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print("Source boundaries and ignore rules passed.")
