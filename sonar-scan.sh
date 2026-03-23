#!/bin/bash
# Scan a local Maven project to SonarQube Cloud
#
# Usage:
#   sonar-scan.sh <project-dir> <project-key> <project-name> <token> [--instance staging|cloud] [extra-maven-args...]
#
# Instance defaults to 'staging' (sc-staging.io). Use --instance cloud for sonarcloud.io.
#
# Example:
#   sonar-scan.sh ~/Documents/git/gctoolkit \
#     the-dna-squad_gctoolkit-upstream-main \
#     "chris-chedgey / gctoolkit / upstream-main" \
#     $SONAR_TOKEN_GCTOOLKIT_UPSTREAM_MAIN
#
#   sonar-scan.sh ~/Documents/git/gctoolkit \
#     the-dna-squad_gctoolkit-main \
#     "chris-chedgey / gctoolkit / main" \
#     $SONAR_TOKEN_GCTOOLKIT_MAIN_CLOUD \
#     --instance cloud
#
#   sonar-scan.sh ~/Documents/git/maven \
#     the-dna-squad_maven-master \
#     "chris-chedgey / maven / master" \
#     $SONAR_TOKEN_MAVEN_MASTER \
#     -Drat.skip=true

set -e

PROJECT_DIR="$1"
PROJECT_KEY="$2"
PROJECT_NAME="$3"
TOKEN="$4"
shift 4

INSTANCE=staging
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance)
      INSTANCE="$2"
      shift 2
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

SCANNER_URL_ARGS=()
case "$INSTANCE" in
  staging)
    SONAR_HOST=https://sc-staging.io
    SONAR_PLUGIN=org.sonarsource.scanner.maven:sonar-maven-plugin:3.9.1.2184:sonar
    SCANNER_URL_ARGS=(
      "-Dsonar.scanner.sonarcloudUrl=https://sc-staging.io"
      "-Dsonar.scanner.apiBaseUrl=https://api.sc-staging.io"
    )
    ;;
  cloud)
    SONAR_HOST=https://sonarcloud.io
    SONAR_PLUGIN=org.sonarsource.scanner.maven:sonar-maven-plugin:5.1.0.4751:sonar
    ;;
  *)
    echo "Error: unknown instance '$INSTANCE'. Use 'staging' or 'cloud'."
    exit 1
    ;;
esac

SONAR_ORG=the-dna-squad

if [ -z "$PROJECT_DIR" ] || [ -z "$PROJECT_KEY" ] || [ -z "$PROJECT_NAME" ] || [ -z "$TOKEN" ]; then
  echo "Usage: $0 <project-dir> <project-key> <project-name> <token> [--instance staging|cloud] [extra-maven-args...]"
  exit 1
fi

cd "$PROJECT_DIR"

mvn package "$SONAR_PLUGIN" \
  -DskipTests \
  -Dsonar.token="$TOKEN" \
  -Dsonar.host.url="$SONAR_HOST" \
  -Dsonar.organization="$SONAR_ORG" \
  -Dsonar.projectKey="$PROJECT_KEY" \
  -Dsonar.projectName="$PROJECT_NAME" \
  "${SCANNER_URL_ARGS[@]}" \
  "${EXTRA_ARGS[@]}"
