#!/bin/sh

USER_NAME=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
TEAMS_CLASSIC_CACHE="/Users/$USER_NAME/Library/Application Support/Microsoft/Teams"

NEW_TEAMS_BUNDLE_ID="com.microsoft.teams2"

PKG_URL="https://statics.teams.cdn.office.net/production-osx/enterprise/webview2/lkg/MicrosoftTeams.pkg"
PKG_PATH="/tmp/MicrosoftTeams.pkg"

remove_file()
{
  if [ ! -d "$1" ]; then
    echo "$1 not found"
    return
  fi
  if [ -d "$1" ]; then
    if /usr/bin/sudo /bin/rm -rf "$1"; then
      echo "Removed $1"
    else
      echo "Failed to remove $1"
    fi
  fi
}

terminate_app() {
  local EXECUTABLE_NAME="$1"

  local TIMEOUT=5
  local INTERVAL=1
  local ELAPSED=0

  if /usr/bin/pgrep -q -x "$EXECUTABLE_NAME"; then
    echo "$EXECUTABLE_NAME is running. Forcibly closing."
    /usr/bin/pkill -HUP -x "$EXECUTABLE_NAME"
  fi
  # Wait for the process to terminate
  while /usr/bin/pgrep -q -x "$EXECUTABLE_NAME"; do
    if [ $ELAPSED -ge $TIMEOUT ]; then
      echo "Timeout reached. $EXECUTABLE_NAME is still running. Forcibly killing."
      /usr/bin/pkill -9 -x "$EXECUTABLE_NAME"
      break
    fi
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done
}

remove_app() {
  local APP_PATH="$1"
  local EXECUTABLE_NAME="$2"

  if [ -d "$APP_PATH" ]; then
    terminate_app "$EXECUTABLE_NAME"
    
    if /bin/rm -rf "$APP_PATH"; then
      echo "Removed app at $APP_PATH"
    else
      echo "Failed to remove app at $APP_PATH" "Error"
    fi
  fi
}

remove_legacy_teams_app() {
  local TEAMS_CLASSIC_BUNDLE_ID="com.microsoft.teams"
  local EXECUTABLE_NAME="Teams"

  local TEAMS_CLASSIC_PATHS=$(mdfind "kMDItemCFBundleIdentifier == '$TEAMS_CLASSIC_BUNDLE_ID'" -onlyin /Applications)

  if [ -z "$TEAMS_CLASSIC_PATHS" ]; then
    echo "No legacy Microsoft Teams app found" "Info"
    return
  fi

  IFS=$'\n' read -r -d '' -a T1_APP_PATHS <<< "$TEAMS_CLASSIC_PATHS"
  if [ ${#T1_APP_PATHS[@]} -gt 1 ]; then
    echo "Warning: Multiple instances of legacy Teams Classic app found. Processing the first match."
  fi

  for T1_APP_PATH in "${T1_APP_PATHS[@]}"; do
    if [ -n "$T1_APP_PATH" ]; then
      local TEAMS_CLASSIC_PATH_CANONICAL=$(realpath "$T1_APP_PATH")
      remove_app "$TEAMS_CLASSIC_PATH_CANONICAL" "$EXECUTABLE_NAME"
    fi
  done
}

# Cleanup localized folders containing Teams
cleanup_localized_teams() {
    echo "Searching for New Teams in localized folders."

    # Use mdfind to locate all apps with the target bundle ID
    app_paths=$(mdfind "kMDItemCFBundleIdentifier == '$NEW_TEAMS_BUNDLE_ID'")

    # Iterate through all found paths
    echo "$app_paths" | while read -r app_path; do
        # Check if the app is under /Applications and in a localized folder
        if [[ "$app_path" == /Applications/*.localized/* ]]; then
            echo "App is in a localized folder under /Applications: $app_path"

            # Remove the localized folder
            localized_folder=$(dirname "$app_path")
            rm -rf "$localized_folder"

            if [[ $? -eq 0 ]]; then
                echo "Successfully removed localized folder: $localized_folder"
            else
                echo "Failed to remove localized folder: $localized_folder."
            fi
        fi
    done

    echo "Cleanup of localized Teams folders completed."
}

echo "Running cleanup script..."

remove_legacy_teams_app
remove_file "$TEAMS_CLASSIC_CACHE"
cleanup_localized_teams

# Check if New Teams is already installed
if mdfind "kMDItemCFBundleIdentifier == '$NEW_TEAMS_BUNDLE_ID'" | grep -q "/Applications/Microsoft Teams.app"; then
    echo "Microsoft Teams (New Teams) is already installed. No action needed."
    echo "Cleanup completed."
    exit 0
fi

echo "Microsoft Teams (New Teams) not found. Proceeding with installation..."

echo "Downloading Microsoft Teams package..."
curl -L -o "$PKG_PATH" "$PKG_URL"

if [ $? -ne 0 ]; then
    echo "Failed to download the package."
    exit 1
fi

echo "Installing Microsoft Teams..."
sudo installer -pkg "$PKG_PATH" -target /Applications

if [ $? -eq 0 ]; then
    echo "Installation completed successfully."
else
    echo "Installation failed."
    exit 1
fi
rm -f "$PKG_PATH"

echo "Cleanup completed."

exit 0