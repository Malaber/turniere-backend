#!/usr/bin/env bash
set -euo pipefail

package_dir=$(cd "$(dirname "$0")/.." && pwd)
marketing_version=${1:-}
build_number=${2:-}
environment=${3:-production}
case "$environment" in
  production) scheme=Turniere; bundle_id=re.turnie; export_options=ExportOptions.TestFlight.plist ;;
  beta) scheme=TurniereBeta; bundle_id=re.turnie.beta; export_options=ExportOptions.BetaTestFlight.plist ;;
  *) echo "Environment must be production or beta." >&2; exit 2 ;;
esac

if [[ ! "$marketing_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Usage: $0 <marketing-version> <build-number>" >&2
  echo "Use the repository task: inv upload-ios-testflight --build-number=2" >&2
  exit 2
fi
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "Build number must be a positive integer." >&2
  exit 2
fi

# Optional existing App Store Connect API credentials; never print key contents.
auth_args=()
if [[ -n "${APP_STORE_CONNECT_KEY_PATH:-}${APP_STORE_CONNECT_KEY_ID:-}${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  : "${APP_STORE_CONNECT_KEY_PATH:?Set the path to an existing .p8 key}"
  : "${APP_STORE_CONNECT_KEY_ID:?Set the existing API key ID}"
  : "${APP_STORE_CONNECT_ISSUER_ID:?Set the existing API issuer ID}"
  [[ -f "$APP_STORE_CONNECT_KEY_PATH" ]] || { echo "API key file not found." >&2; exit 2; }
  auth_args=(-authenticationKeyPath "$APP_STORE_CONNECT_KEY_PATH"
             -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID"
             -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID")
fi

temp_base=${TMPDIR:-/tmp}
release_dir=$(mktemp -d "${temp_base%/}/turniere-testflight.XXXXXX")
archive_path="$release_dir/Turniere-$marketing_version-$build_number.xcarchive"
export_path="$release_dir/export"

cd "$package_dir"
xcodegen generate

env PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/xcodebuild \
  -project TurniereApp.xcodeproj \
  -scheme "$scheme" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  DEVELOPMENT_TEAM=VWKG94374J \
  PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
  MARKETING_VERSION="$marketing_version" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  ${auth_args[@]+"${auth_args[@]}"} \
  archive

# Fail closed on a mismatched archive or unsafe beta export configuration.
python3 "$package_dir/Scripts/validate_testflight_export.py" \
  "$archive_path/Products/Applications/$scheme.app/Info.plist" \
  "$package_dir/$export_options" "$environment"

env PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$package_dir/$export_options" \
  -allowProvisioningUpdates ${auth_args[@]+"${auth_args[@]}"}

echo "TestFlight upload accepted. Archive: $archive_path"
