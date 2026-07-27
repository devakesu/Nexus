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

# Fetch the real private engine archive if the token was successfully retrieved
if [ -n "$ENGINE_PAT" ]; then
  echo "Fetching confidential engine archive from private repository..."
  TEMP_TAR=$(mktemp)
  if curl -sSL --fail \
    -H "Authorization: token $ENGINE_PAT" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/devakesu/Nexus_Engine/tarball/main" \
    -o "$TEMP_TAR"; then
      echo "Archive fetched successfully. Extracting..."
      # Clean the existing directory to ensure no stale/mock files remain
      rm -rf /app/Nexus_Engine/*
      if tar -xzf "$TEMP_TAR" -C /app/Nexus_Engine --strip-components=1; then
        echo "Confidential engine loaded successfully."
      else
        echo "ERROR: Failed to extract confidential engine archive." >&2
        rm -f "$TEMP_TAR"
        exit 1
      fi
      rm -f "$TEMP_TAR"
  else
      echo "ERROR: Failed to fetch the confidential engine archive from private repository." >&2
      rm -f "$TEMP_TAR"
      exit 1
  fi
else
  echo "ERROR: ENGINE_PAT not found. Cannot fetch confidential engine." >&2
  exit 1
fi

# Execute the container's CMD
exec "$@"
