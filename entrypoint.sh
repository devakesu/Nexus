#!/bin/sh
set -e

ENGINE_DIR="/app/Nexus_Engine"
CACHE_DIR="/app/cache/nexus_engine"
COMMIT_FILE="$ENGINE_DIR/.current_commit"

# 1. Resolve target commit SHA (strictly enforced, no fallback to main)
TARGET_SHA="${ENGINE_COMMIT_SHA:-}"
if [ -z "$TARGET_SHA" ] || [ "$TARGET_SHA" = "main" ]; then
  echo "ERROR: ENGINE_COMMIT_SHA is missing or set to floating 'main'. A valid pinned commit SHA is required." >&2
  exit 1
fi
CACHE_TARGET="$CACHE_DIR/$TARGET_SHA"

mkdir -p "$CACHE_DIR" "$ENGINE_DIR"

# 2. Fast Path: Check if the currently loaded engine in filesystem already matches TARGET_SHA
if [ -f "$COMMIT_FILE" ] && [ "$(cat "$COMMIT_FILE" 2>/dev/null)" = "$TARGET_SHA" ] && [ -f "$ENGINE_DIR/engine.py" ]; then
  echo "✓ Nexus_Engine already matches commit [${TARGET_SHA}]. Starting directly."
  exec "$@"
fi

# 3. Cache Hit Path: Check if cached engine for TARGET_SHA exists on disk/volume
if [ -d "$CACHE_TARGET" ] && [ -f "$CACHE_TARGET/engine.py" ]; then
  echo "✓ Cache hit for Nexus_Engine commit [${TARGET_SHA}]. Loading from local cache..."
  rm -rf "${ENGINE_DIR:?}"/*
  cp -r "$CACHE_TARGET"/* "$ENGINE_DIR/"
  echo "$TARGET_SHA" > "$COMMIT_FILE"
  exec "$@"
fi

# 4. Cache Miss: Fetch ENGINE_PAT from Infisical if not in environment
if [ -z "$ENGINE_PAT" ]; then
  if [ -n "$INFISICAL_ENGINE_TOKEN" ]; then
    echo "Retrieving access token from Infisical using dedicated engine token..."
    ENGINE_PAT=$(infisical secrets get ENGINE_PAT --token "$INFISICAL_ENGINE_TOKEN" --plain 2>/dev/null || true)
  elif [ -n "$INFISICAL_PROJECT_ID" ]; then
    echo "Retrieving access token from Infisical using default credentials..."
    ENGINE_PAT=$(infisical secrets get ENGINE_PAT --projectId "$INFISICAL_PROJECT_ID" --path /runtime --env prod --plain 2>/dev/null || true)
  fi
fi

if [ -n "$ENGINE_PAT" ]; then
  echo "Fetching confidential engine archive (commit: ${TARGET_SHA})..."
  TEMP_TAR=$(mktemp)
  
  if curl -sSL --fail --retry 3 --retry-delay 2 \
    -H "Authorization: token $ENGINE_PAT" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/devakesu/Nexus_Engine/tarball/${TARGET_SHA}" \
    -o "$TEMP_TAR"; then
      
      echo "Archive fetched successfully. Populating cache and extracting..."
      mkdir -p "$CACHE_TARGET"
      rm -rf "${CACHE_TARGET:?}"/* "${ENGINE_DIR:?}"/*
      
      # Extract into cache directory and copy to runtime engine directory
      tar -xzf "$TEMP_TAR" -C "$CACHE_TARGET" --strip-components=1
      cp -r "$CACHE_TARGET"/* "$ENGINE_DIR/"
      echo "$TARGET_SHA" > "$COMMIT_FILE"
      rm -f "$TEMP_TAR"
      echo "✓ Confidential engine [${TARGET_SHA}] loaded and cached successfully."
  else
      # Network fallback: Check if any previous engine exists in cache
      LATEST_CACHED=$(find "$CACHE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)
      if [ -n "$LATEST_CACHED" ] && [ -f "$LATEST_CACHED/engine.py" ]; then
        echo "⚠️ WARNING: Network download failed. Falling back to cached engine from $(basename "$LATEST_CACHED")."
        rm -rf "${ENGINE_DIR:?}"/*
        cp -r "$LATEST_CACHED"/* "$ENGINE_DIR/"
        rm -f "$TEMP_TAR"
      else
        echo "ERROR: Failed to fetch engine archive from GitHub and no local cache available." >&2
        rm -f "$TEMP_TAR"
        exit 1
      fi
  fi
else
  # No token: Fallback to existing cache if available
  LATEST_CACHED=$(find "$CACHE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)
  if [ -n "$LATEST_CACHED" ] && [ -f "$LATEST_CACHED/engine.py" ]; then
    echo "⚠️ WARNING: ENGINE_PAT not found. Falling back to existing cached engine from $(basename "$LATEST_CACHED")."
    rm -rf "${ENGINE_DIR:?}"/*
    cp -r "$LATEST_CACHED"/* "$ENGINE_DIR/"
  else
    echo "ERROR: ENGINE_PAT not found and no cached engine available. Cannot load confidential engine." >&2
    exit 1
  fi
fi

# Execute the container's CMD
exec "$@"
