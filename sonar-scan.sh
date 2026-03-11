#!/bin/bash
# Scan a local Maven project to SonarQube Cloud (sc-staging.io)
#
# Usage:
#   sonar-scan.sh <project-dir> <project-key> <project-name> <token>
#
# Example:
#   sonar-scan.sh ~/Documents/git/gctoolkit \
#     the-dna-squad_gctoolkit-upstream-main \
#     "chris-chedgey / gctoolkit / upstream-main" \
#     $SONAR_TOKEN_GCTOOLKIT_UPSTREAM_MAIN

set -e

PROJECT_DIR="$1"
PROJECT_KEY="$2"
PROJECT_NAME="$3"
TOKEN="$4"

SONAR_HOST=https://sc-staging.io
SONAR_ORG=the-dna-squad
SONAR_PLUGIN=org.sonarsource.scanner.maven:sonar-maven-plugin:3.9.1.2184:sonar

if [ -z "$PROJECT_DIR" ] || [ -z "$PROJECT_KEY" ] || [ -z "$PROJECT_NAME" ] || [ -z "$TOKEN" ]; then
  echo "Usage: $0 <project-dir> <project-key> <project-name> <token>"
  exit 1
fi

cd "$PROJECT_DIR"

mvn package "$SONAR_PLUGIN" \
  -DskipTests \
  -Dsonar.token="$TOKEN" \
  -Dsonar.host.url="$SONAR_HOST" \
  -Dsonar.organization="$SONAR_ORG" \
  -Dsonar.projectKey="$PROJECT_KEY" \
  -Dsonar.projectName="$PROJECT_NAME"
