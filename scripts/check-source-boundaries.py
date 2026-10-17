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
    if (name.startswith("Sources/AgentHUDCore/") and path.suffix == ".swift"
            and name != "Sources/AgentHUDCore/System/UserHome.swift"
            and not name.startswith("Sources/AgentHUDCore/Platform/Windows/")
            and "homeDirectoryForCurrentUser" in content):
        failures.append(f"{name}: read the home folder through UserHome.directory")

# The notices the application carries are the ones the repository publishes.
bundled = "Sources/AgentHUDDesktop/Resources/THIRD_PARTY_NOTICES.txt"
if (ROOT / "THIRD_PARTY_NOTICES.txt").read_bytes() != (ROOT / bundled).read_bytes():
    failures.append(f"{bundled}: differs from THIRD_PARTY_NOTICES.txt; copy the root file over it")

manifest = (ROOT / "Package.swift").read_text(encoding="utf-8")
if re.search(r"\.package\s*\(", manifest):
    failures.append("Package.swift: review external package dependencies before including them")

# Verify ignore rules without creating any secret-shaped files.
ignored = [".env", "signing/local.env", "config/service.local.json", "AuthKey_example.p8", "certificate.p12",
           "account.key", "development.mobileprovision", "build/Agent HUD Open.app/Contents/Info.plist", ".build/ignore-check/AgentHUDOpen"]
# Bytes, so that no platform writes the line ends as CR LF, which git would read as part of each path.
result = subprocess.run(["git", "check-ignore", "--stdin"], cwd=ROOT,
                        input=("\n".join(ignored)+"\n").encode(), capture_output=True)
missing = set(ignored) - set(result.stdout.decode().splitlines())
failures.extend(f".gitignore: missing rule for {name}" for name in sorted(missing))

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print("Source boundaries and ignore rules passed.")
