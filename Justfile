# Grid — run `just` to see all recipes.

app_name   := "Grid"
bundle_id  := "com.kurtwolf.grid"
app        := "build/Grid.app"
installed  := "/Applications/Grid.app"
repo       := "kurtbuilds/grid"
min_macos  := "14.0"
# Build with Xcode's toolchain when it's installed (needed for universal binaries); else the CLT.
xcode_dev  := "/Applications/Xcode.app/Contents/Developer"
use_xcode  := path_exists(xcode_dev)
# Codesigning identity: your Developer ID / Apple Development cert. Override with GRID_SIGN_IDENTITY="…".
# A stable identity is what lets macOS keep Grid's Accessibility access across rebuilds.
# Pin to one team's certificate when your Apple ID belongs to several (the Personal Team's ID).
export GRID_TEAM_ID := env("GRID_TEAM_ID", "")
sign_identity := `scripts/signing-identity.sh`
sign_name     := if sign_identity == "" { "" } else { `security find-identity -v -p codesigning | grep -o "$(scripts/signing-identity.sh) "[^"]*"" | cut -d'"' -f2 || true` }
# Swift Testing lives outside the default search paths when only the Command Line Tools are installed.
dev_dir    := `xcode-select -p`
test_flags := if dev_dir =~ "CommandLineTools" { "-Xswiftc -F" + dev_dir + "/Library/Developer/Frameworks -Xlinker -F" + dev_dir + "/Library/Developer/Frameworks -Xlinker -rpath -Xlinker " + dev_dir + "/Library/Developer/Frameworks -Xlinker -rpath -Xlinker " + dev_dir + "/Library/Developer/usr/lib" } else { "" }

# List recipes
default:
    @just --list --unsorted

# Build the signed release app bundle into build/Grid.app (universal when Xcode is installed)
build version="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{sign_identity}}" ]]; then
      echo "No Apple Development or Developer ID certificate found in your keychain." >&2
      echo "Install one (see README → Signing), or set GRID_SIGN_IDENTITY." >&2
      exit 1
    fi
    {{ if use_xcode == "true" { "export DEVELOPER_DIR=" + xcode_dev } else { "" } }}
    archs=({{ if use_xcode == "true" { "--arch arm64 --arch x86_64" } else { "" } }})
    # SwiftPM records the deployment target as the SDK version too, which makes macOS run the app
    # in compatibility mode (no current system look). Record the real SDK instead.
    sdk="$(xcrun --sdk macosx --show-sdk-version)"
    flags=(-c release "${archs[@]}" -Xlinker -platform_version -Xlinker macos -Xlinker {{min_macos}} -Xlinker "$sdk")
    swift build "${flags[@]}"
    bin="$(swift build "${flags[@]}" --show-bin-path)/{{app_name}}"

    rm -rf "{{app}}"
    mkdir -p "{{app}}/Contents/MacOS" "{{app}}/Contents/Resources"
    cp "$bin" "{{app}}/Contents/MacOS/{{app_name}}"
    cp Resources/Info.plist "{{app}}/Contents/Info.plist"
    cp Resources/AppIcon.icns "{{app}}/Contents/Resources/AppIcon.icns"
    plist="{{app}}/Contents/Info.plist"
    if [[ -n "{{version}}" ]]; then /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString {{version}}" "$plist"; fi
    # Build number = commit count, so every release is strictly newer than the last.
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "$plist"

    codesign --force --options runtime --timestamp=none --sign "{{sign_identity}}" "{{app}}"
    codesign --verify --strict "{{app}}"
    echo "Built {{app}} $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist") [$(lipo -archs "{{app}}/Contents/MacOS/{{app_name}}")] signed by {{sign_name}}"

# Build and launch the bundle from build/ (quits any running copy first)
run: quit build
    open "{{app}}"

# Build, install to /Applications, and launch
install: quit build
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{installed}}"
    cp -R "{{app}}" "{{installed}}"
    open "{{installed}}"
    echo "Installed {{installed}}"

# Build and publish a GitHub release (e.g. `just release 1.0`). Needs a clean, committed tree.
release version: (build version)
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "$(git status --porcelain)" ]]; then echo "Commit your changes first." >&2; exit 1; fi
    if git rev-parse "v{{version}}" >/dev/null 2>&1; then echo "v{{version}} already exists." >&2; exit 1; fi
    ditto -c -k --keepParent "{{app}}" build/Grid.zip
    git push origin HEAD
    gh release create "v{{version}}" build/Grid.zip --repo {{repo}} --target "$(git rev-parse HEAD)" \
      --title "Grid {{version}}" --generate-notes
    git fetch --tags --quiet
    echo "Released v{{version}}. On other Macs: just update  (or see README → Install on other Macs)"

# Install the latest GitHub release into /Applications (any Mac signed in to `gh`)
update:
    scripts/install-latest.sh {{repo}}

# Show which signing identity builds will use
signing:
    @echo "Builds sign with: {{ if sign_identity == "" { "(none found; install an Apple Development or Developer ID certificate)" } else { sign_name } }}"

# Run the unit tests
test *args:
    swift test {{test_flags}} {{args}}

# Debug build, no bundle
build-debug:
    swift build

# Render settings, overlay and every onboarding step to PNGs (debug build)
snapshot dir="build/snapshots": build-debug
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{dir}}"
    "$(swift build --show-bin-path)/{{app_name}}" --snapshot "$(cd "{{dir}}" && pwd)"
    ls "{{dir}}"

# Regenerate Resources/AppIcon.icns
icon:
    swift scripts/make-icon.swift

# Quit the running app, if any
quit:
    -@pkill -x {{app_name}} && sleep 0.5 || true

# Show onboarding again on next launch
reset-onboarding:
    -defaults delete {{bundle_id}} onboardingCompleted

# Clear Grid's Accessibility permission
reset-permissions:
    tccutil reset Accessibility {{bundle_id}}

# Wipe all settings, shortcuts and permissions (back to first launch)
reset-all: quit reset-permissions
    -defaults delete {{bundle_id}}

# Stream the app's log output
logs:
    log stream --style compact --predicate 'process == "{{app_name}}"'

# Remove build products
clean:
    rm -rf .build build
