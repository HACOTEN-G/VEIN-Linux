#!/bin/bash
#
# set-vein-config.sh
# Update VEIN server name and password from the command line.
#
# Usage:
#   sudo ./set-vein-config.sh --name "My Server" --password "mypass"
#   sudo ./set-vein-config.sh --name "My Server"   # password unchanged
#   sudo ./set-vein-config.sh --password ""         # remove password

GAMEINI="/home/steam/vein_server/Vein/Saved/Config/LinuxServer/Game.ini"

# ============================================================
# Root check
# ============================================================
if [ "$LOGNAME" != "root" ]; then
  echo "Please run this script as root!" >&2
  exit 1
fi

# ============================================================
# Parse arguments
# ============================================================
NEW_NAME=""
NEW_PASSWORD=""
SET_PASSWORD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      NEW_NAME="$2"
      shift 2
      ;;
    --password)
      NEW_PASSWORD="$2"
      SET_PASSWORD=true
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: sudo $0 --name \"Server Name\" --password \"pass\""
      exit 1
      ;;
  esac
done

if [ -z "$NEW_NAME" ] && [ "$SET_PASSWORD" = false ]; then
  echo "Nothing to update. Use --name and/or --password."
  echo "Usage: sudo $0 --name \"Server Name\" --password \"pass\""
  exit 1
fi

# ============================================================
# Check Game.ini exists
# ============================================================
if [ ! -f "$GAMEINI" ]; then
  echo "ERROR: Game.ini not found: $GAMEINI" >&2
  exit 1
fi

echo "Updating: $GAMEINI"

# ============================================================
# Apply changes
# ============================================================
if [ -n "$NEW_NAME" ]; then
  # Update ServerName under [/Script/Vein.VeinGameSession]
  sed -i "s|^ServerName=.*|ServerName=\"$NEW_NAME\"|" "$GAMEINI"
  echo "  ServerName -> \"$NEW_NAME\""
fi

if [ "$SET_PASSWORD" = true ]; then
  # Update Password under [/Script/Vein.VeinGameSession]
  sed -i "s|^Password=.*|Password=\"$NEW_PASSWORD\"|" "$GAMEINI"
  if [ -z "$NEW_PASSWORD" ]; then
    echo "  Password   -> (none)"
  else
    echo "  Password   -> \"$NEW_PASSWORD\""
  fi
fi

chown steam:steam "$GAMEINI"

# ============================================================
# Restart service
# ============================================================
echo ""
echo "Restarting vein-server..."
systemctl restart vein-server
echo "Done. Changes applied."
