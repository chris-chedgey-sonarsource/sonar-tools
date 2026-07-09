#!/bin/bash
# Post-install setup for a fresh local SonarQube Server instance.
#
# Runs after any install (snapshot or rebuild) that wipes the H2 database.
# Does everything needed to get back to a working state:
#   1. Waits for the server to be UP
#   2. Sets the admin password
#   3. Applies the enterprise license
#   4. Creates each configured project and generates a project analysis token
#   5. Updates ~/.zshrc with the new tokens
#
# Usage:
#   sqs-post-install.sh
#
# Requires:
#   ~/Documents/git/licenses/edition_testing/ee.txt  — enterprise test license
#   SONAR_TOKEN_SQS in ~/.zshrc                       — existing user token (or will be created)

set -e

SQS_URL=http://localhost:9000
ADMIN_USER=admin
ADMIN_DEFAULT_PASS=admin
ADMIN_PASS=Localhost-admin1
LICENSE_FILE="$HOME/Documents/git/licenses/edition_testing/ee.txt"
INSTALL_DIR="$HOME/sonarqube-local/server"

# Persistent JWT secret — keeps sessions alive across server restarts/reinstalls.
# Generated once; do not change unless you want to log everyone out.
JWT_SECRET="b/okSAXqd3WVcosVcYZZJLtzXWBfqOZcWWdUDzm48EI="

SQS_BIN="$INSTALL_DIR/bin/macosx-universal-64/sonar.sh"
PROPS="$INSTALL_DIR/conf/sonar.properties"

# --- Set JWT secret before server starts so sessions survive restarts ---
echo "=== Setting persistent JWT secret ==="
if grep -q "^sonar.auth.jwtBase64Hs256Secret=" "$PROPS" 2>/dev/null; then
  sed -i '' "s|^sonar.auth.jwtBase64Hs256Secret=.*|sonar.auth.jwtBase64Hs256Secret=$JWT_SECRET|" "$PROPS"
else
  sed -i '' "s|^#sonar.auth.jwtBase64Hs256Secret=.*|sonar.auth.jwtBase64Hs256Secret=$JWT_SECRET|" "$PROPS"
fi
echo "JWT secret set — restarting server to apply it."
"$SQS_BIN" stop 2>/dev/null || true
sleep 5
"$SQS_BIN" start

# --- Wait for server to be UP ---
echo "=== Waiting for SonarQube to be UP ==="
until curl -s "$SQS_URL/api/system/status" | grep -q '"status":"UP"'; do
  sleep 3
done
echo "Server is UP."

# --- Set admin password ---
echo "=== Setting admin password ==="
# Always attempt to set the password — the validate endpoint can return 200 on a fresh
# install before authentication is fully initialised, causing false "already set" skips.
CHANGE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "$ADMIN_USER:$ADMIN_DEFAULT_PASS" -X POST "$SQS_URL/api/users/change_password" \
  -d "login=$ADMIN_USER&previousPassword=$ADMIN_DEFAULT_PASS&password=$ADMIN_PASS")
if [ "$CHANGE_STATUS" = "204" ] || [ "$CHANGE_STATUS" = "200" ]; then
  echo "Password set."
else
  echo "Password already set (or change failed with HTTP $CHANGE_STATUS), continuing."
fi

# --- Apply enterprise license ---
echo "=== Applying enterprise license ==="
if [ ! -f "$LICENSE_FILE" ]; then
  echo "Error: license file not found at $LICENSE_FILE"
  echo "Clone it with: gh repo clone SonarSource/licenses ~/Documents/git/licenses"
  exit 1
fi
LICENSE=$(grep -v '^-' "$LICENSE_FILE" | grep -v '^Enterprise\|^$' | tr -d '\n')
curl -s -u "$ADMIN_USER:$ADMIN_PASS" -X POST "$SQS_URL/api/editions/set_license" \
  --data-urlencode "license=$LICENSE"
echo "License applied."

# --- Create user token (if SONAR_TOKEN_SQS not already set/valid) ---
source ~/.zshrc 2>/dev/null || true
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "$SONAR_TOKEN_SQS:" "$SQS_URL/api/authentication/validate" 2>/dev/null)
if [ "$HTTP_STATUS" != "200" ] || [ -z "$SONAR_TOKEN_SQS" ]; then
  echo "=== Creating user token ==="
  NEW_USER_TOKEN=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" -X POST "$SQS_URL/api/user_tokens/generate" \
    -d "name=admin-api&type=USER_TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
  if grep -q "^export SONAR_TOKEN_SQS=" ~/.zshrc; then
    sed -i '' "s|^export SONAR_TOKEN_SQS=.*|export SONAR_TOKEN_SQS=$NEW_USER_TOKEN|" ~/.zshrc
  else
    echo "export SONAR_TOKEN_SQS=$NEW_USER_TOKEN" >> ~/.zshrc
  fi
  export SONAR_TOKEN_SQS="$NEW_USER_TOKEN"
  echo "User token created and saved."
fi

# --- Projects: add entries here for each project to set up ---
# Format: "project-key|display-name|env-var-name"
PROJECTS=(
  "gctoolkit-upstream-main|chris-chedgey / gctoolkit / upstream-main|SONAR_TOKEN_GCTOOLKIT_UPSTREAM_MAIN_SQS"
  "maven-master|chris-chedgey / maven / master|SONAR_TOKEN_MAVEN_MASTER_SQS"
  "gctoolkit-testing|chris-chedgey / gctoolkit / testing|SONAR_TOKEN_GCTOOLKIT_TESTING_SQS"
)

for entry in "${PROJECTS[@]}"; do
  PROJECT_KEY=$(echo "$entry" | cut -d'|' -f1)
  PROJECT_NAME=$(echo "$entry" | cut -d'|' -f2)
  TOKEN_VAR=$(echo "$entry" | cut -d'|' -f3)

  echo "=== Setting up project: $PROJECT_KEY ==="

  curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$SQS_URL/api/projects/create" -X POST \
    -d "name=$PROJECT_NAME&project=$PROJECT_KEY&visibility=private" > /dev/null

  TOKEN=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$SQS_URL/api/user_tokens/generate" -X POST \
    -d "name=${PROJECT_KEY}-scan&type=GLOBAL_ANALYSIS_TOKEN" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

  if grep -q "^export ${TOKEN_VAR}=" ~/.zshrc; then
    sed -i '' "s|^export ${TOKEN_VAR}=.*|export ${TOKEN_VAR}=$TOKEN|" ~/.zshrc
  else
    echo "export ${TOKEN_VAR}=$TOKEN" >> ~/.zshrc
  fi
  echo "  Token saved to \$${TOKEN_VAR}"
done

echo ""
echo "=== Setup complete. Run: source ~/.zshrc ==="
echo "Then re-scan each project against --instance sqs."
