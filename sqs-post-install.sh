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

# --- Wait for server to be UP ---
echo "=== Waiting for SonarQube to be UP ==="
until curl -s "$SQS_URL/api/system/status" | grep -q '"status":"UP"'; do
  sleep 3
done
echo "Server is UP."

# --- Set admin password ---
echo "=== Setting admin password ==="
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "$ADMIN_USER:$ADMIN_PASS" "$SQS_URL/api/authentication/validate")
if [ "$HTTP_STATUS" = "200" ]; then
  echo "Password already set to Localhost-admin1, skipping."
else
  curl -s -u "$ADMIN_USER:$ADMIN_DEFAULT_PASS" -X POST "$SQS_URL/api/users/change_password" \
    -d "login=$ADMIN_USER&previousPassword=$ADMIN_DEFAULT_PASS&password=$ADMIN_PASS"
  echo "Password set."
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
  sed -i '' "s|SONAR_TOKEN_SQS=.*|SONAR_TOKEN_SQS=$NEW_USER_TOKEN|" ~/.zshrc
  export SONAR_TOKEN_SQS="$NEW_USER_TOKEN"
  echo "User token created and saved."
fi

# --- Projects: add entries here for each project to set up ---
# Format: "project-key|display-name|env-var-name"
PROJECTS=(
  "gctoolkit-upstream-main|chris-chedgey / gctoolkit / upstream-main|SONAR_TOKEN_GCTOOLKIT_UPSTREAM_MAIN_SQS"
  "maven-master|chris-chedgey / maven / master|SONAR_TOKEN_MAVEN_MASTER_SQS"
)

for entry in "${PROJECTS[@]}"; do
  PROJECT_KEY=$(echo "$entry" | cut -d'|' -f1)
  PROJECT_NAME=$(echo "$entry" | cut -d'|' -f2)
  TOKEN_VAR=$(echo "$entry" | cut -d'|' -f3)

  echo "=== Setting up project: $PROJECT_KEY ==="

  curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$SQS_URL/api/projects/create" -X POST \
    -d "name=$PROJECT_NAME&project=$PROJECT_KEY&visibility=private" > /dev/null

  TOKEN=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$SQS_URL/api/user_tokens/generate" -X POST \
    -d "name=${PROJECT_KEY}-scan&type=PROJECT_ANALYSIS_TOKEN&projectKey=$PROJECT_KEY" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

  sed -i '' "s|${TOKEN_VAR}=.*|${TOKEN_VAR}=$TOKEN|" ~/.zshrc
  echo "  Token saved to \$${TOKEN_VAR}"
done

echo ""
echo "=== Setup complete. Run: source ~/.zshrc ==="
echo "Then re-scan each project against --instance sqs."
