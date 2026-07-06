#!/bin/bash
# Rebuild SonarQube Server from source and restart local instance.
#
# Usage:
#   sqs-rebuild.sh              — pull latest, build, stop, install, start
#   sqs-rebuild.sh --no-pull    — skip git pull (use current source)
#   sqs-rebuild.sh --no-build   — skip build (re-install from last build output)
#   sqs-rebuild.sh --no-pull --no-build  — just stop, re-install last build, start
#
# Paths:
#   Source:  ~/Documents/git/sonar-enterprise
#   Install: ~/sonarqube-local/server/

set -e

ENTERPRISE_DIR="$HOME/Documents/git/sonar-enterprise"
INSTALL_DIR="$HOME/sonarqube-local/server"
SQS_BIN="$INSTALL_DIR/bin/macosx-universal-64/sonar.sh"

DO_PULL=true
DO_BUILD=true

for arg in "$@"; do
  case "$arg" in
    --no-pull)  DO_PULL=false ;;
    --no-build) DO_BUILD=false ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--no-pull] [--no-build]"
      exit 1
      ;;
  esac
done

# Pull latest
if [ "$DO_PULL" = true ]; then
  echo "=== Pulling latest changes ==="
  git -C "$ENTERPRISE_DIR" pull
fi

# Build
if [ "$DO_BUILD" = true ]; then
  echo "=== Building server (skipping tests and obfuscation) ==="
  cd "$ENTERPRISE_DIR"
  ./gradlew build -x test -x obfuscate
fi

# Stop running server
if [ -f "$SQS_BIN" ]; then
  echo "=== Stopping running server ==="
  "$SQS_BIN" stop 2>/dev/null || true
  sleep 5
fi

# Find distribution zip
ZIPFILE=$(ls "$ENTERPRISE_DIR/sonar-application/build/distributions/sonarqube-"*.zip 2>/dev/null | head -1)
if [ -z "$ZIPFILE" ]; then
  echo "Error: no distribution zip found in $ENTERPRISE_DIR/sonar-application/build/distributions/"
  echo "Run without --no-build to produce one."
  exit 1
fi
echo "=== Installing: $(basename "$ZIPFILE") ==="

# Extract to temp location, then move into place
TMPDIR=$(mktemp -d)
unzip -q "$ZIPFILE" -d "$TMPDIR"
EXTRACTED=$(ls -d "$TMPDIR/sonarqube-"*/ | head -1)

rm -rf "$INSTALL_DIR"
mkdir -p "$(dirname "$INSTALL_DIR")"
mv "$EXTRACTED" "$INSTALL_DIR"
rm -rf "$TMPDIR"

# Start server
echo "=== Starting server ==="
"$SQS_BIN" start

echo ""
echo "Server starting at http://localhost:9000"
echo "Default credentials: admin / admin (forced to change on first login)"
echo "Logs: $INSTALL_DIR/logs/sonar.log"
