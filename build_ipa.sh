#!/bin/zsh
# Build file UpSnap.ipa CHƯA KÝ -> dùng Sideloadly / AltStore để ký & cài lên iPhone.
set -e -o pipefail
cd "$(dirname "$0")"

# DerivedData phải nằm trên ổ APFS của máy: ổ SSD ngoài (NTFS/exFAT) làm hỏng module cache của Xcode.
DD="${TMPDIR:-/tmp}/UpSnap-DerivedData"

xcodebuild -project UpSnap.xcodeproj -scheme UpSnap -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build \
  | grep -E "error:|BUILD" || true

APP="$DD/Build/Products/Release-iphoneos/UpSnap.app"
if [[ ! -d "$APP" ]]; then
  echo "Build thất bại." >&2
  exit 1
fi

STAGE="$(mktemp -d)"
mkdir -p "$STAGE/Payload" build
cp -R "$APP" "$STAGE/Payload/"
rm -f build/UpSnap.ipa
(cd "$STAGE" && zip -qry UpSnap.ipa Payload)
cp "$STAGE/UpSnap.ipa" build/UpSnap.ipa
rm -rf "$STAGE"
echo "Đã tạo: $(pwd)/build/UpSnap.ipa"
