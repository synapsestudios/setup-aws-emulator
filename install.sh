#!/usr/bin/env bash
# Downloads the AWS Emulator Debian package, checks its signature, and installs it.
#
# Inputs, from the environment:
#   INPUT_VERSION    a release such as 1.0.385, or "latest"
#   INPUT_TELEMETRY  on or off
set -euo pipefail

BASE_URL=https://downloads.aws.com/aws-emulator/packages/aws-emulator/LTS
KEY_URL=https://downloads.aws.com/keys/gpg/current.asc
# Fingerprint of the AWS publishing key, from the AWS Emulator User Guide.
KEY_FINGERPRINT=98BCF336A3BE53B734E967C52E5BF49BD940F624
# Where the package puts the command. Running it by full path keeps another
# aws-emulator on PATH from standing in for the verified one.
EMULATOR_BIN=/usr/bin/aws-emulator

# Line breaks are removed so an input can't smuggle in a workflow command.
fail() {
  local message=${1//[$'\r\n']/ }
  echo "::error::$message"
  exit 1
}

download() { curl -fsSL --retry 3 --proto '=https' --proto-redir '=https' --tlsv1.2 -o "$1" "$2"; }

case "$(printf '%s' "${INPUT_TELEMETRY:-off}" | tr '[:upper:]' '[:lower:]')" in
  on | true | 1) telemetry=on ;;
  off | false | 0) telemetry=off ;;
  *) fail "telemetry must be on or off, got '${INPUT_TELEMETRY}'" ;;
esac

command -v dpkg >/dev/null || fail "AWS Emulator needs a Debian or Ubuntu runner"
arch=$(dpkg --print-architecture)
case "$arch" in
  amd64 | arm64) ;;
  *) fail "AWS Emulator has no package for $arch" ;;
esac

version=${INPUT_VERSION:-latest}
version=${version#v}
if [ "$version" = latest ]; then
  url="$BASE_URL/latest/aws-emulator_${arch}.deb"
elif [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  url="$BASE_URL/aws-emulator_${version}-1_${arch}.deb"
else
  fail "version must be latest or look like 1.0.385, got '${INPUT_VERSION}'"
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
package="$work/aws-emulator.deb"

download "$package" "$url" || fail "could not download $url"
download "$package.sig" "$url.sig" || fail "could not download $url.sig"
download "$work/key.asc" "$KEY_URL" || fail "could not download $KEY_URL"

# A throwaway keyring, so the runner's own keyring is left alone. The check
# passes only when the signature is good, the key is neither expired nor
# revoked (GOODSIG), and the key is the expected one (VALIDSIG).
export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --import "$work/key.asc"
status=$(gpg --batch --status-fd 1 --verify "$package.sig" "$package" 2>/dev/null) ||
  fail "signature check failed for $url"
if ! grep -q '^\[GNUPG:\] GOODSIG ' <<<"$status" ||
  ! grep -Eq "^\[GNUPG:\] VALIDSIG .* ${KEY_FINGERPRINT}\$" <<<"$status"; then
  fail "signature check failed for $url"
fi

sudo=""
[ "$(id -u)" -eq 0 ] || sudo=sudo
$sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$package" >/dev/null

[ -x "$EMULATOR_BIN" ] || fail "the package did not install $EMULATOR_BIN"
installed=$("$EMULATOR_BIN" -v | awk 'tolower($1) ~ /^version/ { print $NF; exit }')
echo "Installed AWS Emulator $installed, telemetry $telemetry"

# Covers any emulator a later step starts, including with start set to false.
echo "EMULATOR_TELEMETRY=$telemetry" >>"$GITHUB_ENV"
{
  echo "version=$installed"
  echo "telemetry=$telemetry"
} >>"$GITHUB_OUTPUT"
