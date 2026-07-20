#!/bin/sh
set -e

# Fetch ENGINE_PAT directly from Infisical using the project ID or a dedicated scoped token
if [ -n "$INFISICAL_ENGINE_TOKEN" ]; then
  echo "Retrieving access token from Infisical using dedicated engine token..."
  ENGINE_PAT=$(infisical secrets get ENGINE_PAT --token "$INFISICAL_ENGINE_TOKEN" --plain)
elif [ -n "$INFISICAL_PROJECT_ID" ]; then
  echo "Retrieving access token from Infisical using default credentials..."
  ENGINE_PAT=$(infisical secrets get ENGINE_PAT --projectId "$INFISICAL_PROJECT_ID" --path /runtime --env prod --plain)
fi

# Fetch the real private file if the token was successfully retrieved
if [ -n "$ENGINE_PAT" ]; then
  echo "Fetching confidential engine from private repository..."
  if curl -sSL --fail \
    -H "Authorization: token $ENGINE_PAT" \
    -H "Accept: application/vnd.github.v3.raw" \
    "https://raw.githubusercontent.com/devakesu/Nexus_Engine/main/engine.py" \
    -o /app/Nexus_Engine/engine.py; then
      echo "Confidential engine loaded successfully."
  else
      echo "ERROR: Failed to fetch the confidential engine from private repository." >&2
      exit 1
  fi
else
  echo "ERROR: ENGINE_PAT not found. Cannot fetch confidential engine." >&2
  exit 1
fi

# Execute the container's CMD
exec "$@"
