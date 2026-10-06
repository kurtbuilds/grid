# Grid — run `just` to see all recipes.

app_name   := "Grid"
bundle_id  := "com.kurtwolf.grid"
app        := "build/Grid.app"
installed  := "/Applications/Grid.app"
# Codesigning identity: your Developer ID / Apple Development cert. Override with GRID_SIGN_IDENTITY="…".
# A stable identity is what lets macOS keep Grid's Accessibility access across rebuilds.
sign_identity := `scripts/signing-identity.sh`
# Swift Testing lives outside the default search paths when only the Command Line Tools are installed.
dev_dir    := `xcode-select -p`
test_flags := if dev_dir =~ "CommandLineTools" { "-Xswiftc -F" + dev_dir + "/Library/Developer/Frameworks -Xlinker -F" + dev_dir + "/Library/Developer/Frameworks -Xlinker -rpath -Xlinker " + dev_dir + "/Library/Developer/Frameworks -Xlinker -rpath -Xlinker " + dev_dir + "/Library/Developer/usr/lib" } else { "" }

# List recipes
default:
    @just --list --unsorted

# Build the release app bundle into build/Grid.app
build:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{sign_identity}}" ]]; then
      echo "No Apple Development or Developer ID certificate found in your keychain." >&2
      echo "Install one (see README → Signing), or set GRID_SIGN_IDENTITY." >&2
      exit 1
    fi
    swift build -c release
    bin="$(swift build -c release --show-bin-path)/{{app_name}}"
    rm -rf "{{app}}"
    mkdir -p "{{app}}/Contents/MacOS" "{{app}}/Contents/Resources"
    cp "$bin" "{{app}}/Contents/MacOS/{{app_name}}"
    cp Resources/Info.plist "{{app}}/Contents/Info.plist"
    cp Resources/AppIcon.icns "{{app}}/Contents/Resources/AppIcon.icns"
    codesign --force --options runtime --sign "{{sign_identity}}" "{{app}}"
    echo "Built {{app}} (signed: {{sign_identity}})"

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

# Show which signing identity builds will use
signing:
    @echo "Builds sign with: {{ if sign_identity == "" { "(none found; install an Apple Development or Developer ID certificate)" } else { sign_identity } }}"

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
