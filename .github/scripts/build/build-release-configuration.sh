#!/usr/bin/env bash
# Extracted from .github/workflows/build.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
mkdir -p artifact

projects=()
while IFS= read -r -d '' item; do projects+=("$item"); done < <(find . -type d \( -name '*.xcodeproj' -o -name '*.xcworkspace' \) -print0)
if (( ${#projects[@]} > 0 )); then
  project="${projects[0]}"
  [[ ${#projects[@]} -eq 1 ]] || echo "Multiple Xcode projects/workspaces found; using $project"
  if [[ "$project" == *.xcworkspace ]]; then
    project_args=(-workspace "$project")
    listing="$(xcodebuild -list -json -workspace "$project")" || fail "xcodebuild could not inspect workspace $project."
    schemes="$(python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).get("workspace",{}).get("schemes",[])))' <<< "$listing")"
  else
    project_args=(-project "$project")
    listing="$(xcodebuild -list -json -project "$project")" || fail "xcodebuild could not inspect project $project."
    schemes="$(python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).get("project",{}).get("schemes",[])))' <<< "$listing")"
  fi
  scheme="$(printf '%s\n' "$schemes" | sed '/^$/d' | head -n 1)"
  [[ -n "$scheme" ]] || fail "No shared Xcode scheme was found in $project."
  echo "Building Xcode project: $project (scheme=$scheme, configuration=Release)"
  archive="artifact/LLP.xcarchive"
  xcodebuild "${project_args[@]}" -scheme "$scheme" -configuration Release -destination 'generic/platform=macOS' -archivePath "$archive" CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION="$BUILD_NUMBER" MARKETING_VERSION="$VERSION" archive || fail "Xcode Release archive failed for scheme $scheme."
  [[ -d "$archive/Products/Applications" ]] || fail "Xcode archive contains no Applications directory."
  app="$(find "$archive/Products/Applications" -maxdepth 1 -type d -name '*.app' -print -quit)"
  [[ -n "$app" ]] || fail "Xcode archive contains no .app application."
elif [[ -f mac/Package.swift ]]; then
  echo "No Xcode project/workspace found; building detected Swift package mac in Release mode."
  swift build --package-path mac --configuration release --product LLP || fail "SwiftPM Release build failed for product LLP."
  executable="mac/.build/release/LLP"
  [[ -x "$executable" ]] || fail "SwiftPM build completed without expected executable $executable."
  archive="artifact/LLP.xcarchive"
  app="$archive/Products/Applications/LLP.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$executable" "$app/Contents/MacOS/LLP" || fail "Could not stage LLP executable."
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LLP</string>
<key>CFBundleIdentifier</key><string>com.llp.macos</string>
<key>CFBundleName</key><string>LLP</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${VERSION}</string>
<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
</dict></plist>
PLIST
  plutil -lint "$app/Contents/Info.plist" || fail "Generated application Info.plist is invalid."
  mkdir -p "$archive/dSYMs"
  cat > "$archive/Info.plist" <<ARCHIVE
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
  <key>ApplicationProperties</key><dict>
  <key>ApplicationPath</key><string>Applications/LLP.app</string>
  <key>CFBundleIdentifier</key><string>com.llp.macos</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>SigningIdentity</key><string></string>
  <key>Team</key><string></string>
  </dict>
  <key>ArchiveVersion</key><integer>2</integer>
  <key>CreationDate</key><date>$(date -u +%Y-%m-%dT%H:%M:%SZ)</date>
  <key>Name</key><string>LLP</string>
  <key>SchemeName</key><string>LLP</string>
  </dict></plist>
ARCHIVE
  plutil -lint "$archive/Info.plist" || fail "Generated .xcarchive metadata is invalid."
else
  fail "No .xcodeproj, .xcworkspace, or mac/Package.swift found; cannot identify a buildable macOS app."
fi

