#!/bin/bash
#
# The script worked on Contabo's Ubuntu 20.04 in early November 2023.
# Please note that the Steam install path, etc. may have changed.

# Only allow running as root
if [ "$LOGNAME" != "root" ]; then
  echo "Please run this script as root! (If you ran with 'su', use 'su -' instead)" >&2
  exit 1
fi

#############################################
# Stop & Remove Existing Service (Safe Check)
#############################################
if [ -f /etc/systemd/system/ark-server.service ]; then
  echo "Existing ark-server.service found. Stopping and removing..."

  systemctl stop ark-server 2>/dev/null || true
  systemctl disable ark-server 2>/dev/null || true
  rm -f /etc/systemd/system/ark-server.service
  systemctl daemon-reload

  echo "Old service removed."
fi

# /opt/ARK completely remove if exists
if [ -d /opt/ark ]; then
  echo "Removing /opt/ark directory..."
  rm -rf /opt/ark
  echo "/opt/ark removed."
fi

#############################################
# Create Swap (16GB if not exists)
#############################################
if ! swapon --show | grep -q "/swapfile"; then
  echo "Creating 16GB swapfile..."

  fallocate -l 16G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=16384
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab

  echo "Swap created and enabled."
else
  echo "Swap already exists. Skipping swap creation."
fi

#############################################
# Working Directory
#############################################
[ -d /opt/game-resources ] || mkdir -p /opt/game-resources

#############################################
# Preliminary requirements
#############################################
dpkg --add-architecture i386
apt update
apt install -y software-properties-common apt-transport-https dirmngr ca-certificates curl wget sudo

#############################################
# Enable restricted & multiverse (Ubuntu 20.04)
#############################################
if grep -Eq '^deb (http|https)://.*ubuntu\.com' /etc/apt/sources.list; then
  if [ -z "$(grep -E '^deb (http|https)://.*ubuntu\.com.*' /etc/apt/sources.list | grep 'restricted')" ]; then
    add-apt-repository -y --enable-component=restricted
  fi
  if [ -z "$(grep -E '^deb (http|https)://.*ubuntu\.com.*' /etc/apt/sources.list | grep 'multiverse')" ]; then
    add-apt-repository -y --enable-component=multiverse
  fi
else
  add-apt-repository -y 'deb http://archive.ubuntu.com/ubuntu/ focal restricted universe multiverse'
  add-apt-repository -y 'deb http://security.ubuntu.com/ubuntu/ focal-security restricted universe multiverse'
  add-apt-repository -y 'deb http://archive.ubuntu.com/ubuntu/ focal-updates restricted universe multiverse'
fi

#############################################
# Install Steam repo
#############################################
curl -s http://repo.steampowered.com/steam/archive/stable/steam.gpg > /usr/share/keyrings/steam.gpg
echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] http://repo.steampowered.com/steam/ stable steam" > /etc/apt/sources.list.d/steam.list

apt update
apt install -y lib32gcc-s1 steamcmd steam-launcher

#############################################
# Proton GE (for ARK: Survival Ascended)
#############################################
PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton8-21/GE-Proton8-21.tar.gz"
PROTON_TGZ="$(basename "$PROTON_URL")"
PROTON_NAME="$(basename "$PROTON_TGZ" ".tar.gz")"

if [ ! -e "/opt/game-resources/$PROTON_TGZ" ]; then
  wget "$PROTON_URL" -O "/opt/game-resources/$PROTON_TGZ"
fi

#############################################
# Create steam user
#############################################
[ -d /home/steam ] || useradd -m -U steam

#############################################
# Install ARK: Survival Ascended Dedicated (Retry Logic)
#############################################

APP_ID=2430930
MAX_RETRIES=3
RETRY_DELAY=15
LOG_FILE="/tmp/steamcmd_ark_install.log"

echo "Installing app $APP_ID ..."

for ((i=1; i<=MAX_RETRIES; i++)); do
  echo "Attempt $i / $MAX_RETRIES"

  sudo -u steam /usr/games/steamcmd \
    +login anonymous \
    +app_update $APP_ID validate \
    +quit | tee "$LOG_FILE"

  # 成功ログ判定
  if grep -q "Success! App '$APP_ID'" "$LOG_FILE"; then
      echo "App installation successful."
      break
  fi

  if [ "$i" -lt "$MAX_RETRIES" ]; then
    echo "Install failed. Retrying in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
  else
    echo "ERROR: Failed to install app after $MAX_RETRIES attempts." >&2
    exit 1
  fi
done

#############################################
# Detect Steam directory
#############################################
if [ -e "/home/steam/Steam" ]; then
  STEAMDIR="/home/steam/Steam"
elif [ -e "/home/steam/.local/share/Steam" ]; then
  STEAMDIR="/home/steam/.local/share/Steam"
elif [ -e "/home/steam/.steam" ]; then
  STEAMDIR="/home/steam/.steam"
else
  echo "Unable to guess where Steam is installed." >&2
  exit 1
fi

if [ -e "$STEAMDIR/steamapps" ]; then
  STEAMAPPSDIR="$STEAMDIR/steamapps"
elif [ -e "$STEAMDIR/SteamApps" ]; then
  STEAMAPPSDIR="$STEAMDIR/SteamApps"
else
  echo "Unable to guess where SteamApps is installed." >&2
  exit 1
fi

#############################################
# Detect ARK install directory dynamically
#############################################

APP_ID=2430930
MANIFEST_FILE="$STEAMAPPSDIR/appmanifest_${APP_ID}.acf"

if [ ! -f "$MANIFEST_FILE" ]; then
  echo "ERROR: appmanifest file not found: $MANIFEST_FILE" >&2
  exit 1
fi

ARK_DIR_NAME=$(grep -i '"installdir"' "$MANIFEST_FILE" | awk -F'"' '{print $4}')

if [ -z "$ARK_DIR_NAME" ]; then
  echo "ERROR: Could not determine ARK install directory." >&2
  exit 1
fi

ARK_ROOT="$STEAMAPPSDIR/common/$ARK_DIR_NAME"
ARK_WIN64="$ARK_ROOT/ShooterGame/Binaries/Win64"
ARK_CONFIG_DIR="$ARK_ROOT/ShooterGame/Saved/Config/WindowsServer"
ARK_LOG_DIR="$ARK_ROOT/ShooterGame/Saved/Logs"

echo "Detected ARK directory:"
echo "  $ARK_ROOT"

#############################################
# Install Proton GE
#############################################
[ -d "$STEAMDIR/compatibilitytools.d" ] || sudo -u steam mkdir -p "$STEAMDIR/compatibilitytools.d"
sudo -u steam tar -x -C "$STEAMDIR/compatibilitytools.d/" -f "/opt/game-resources/$PROTON_TGZ"

#############################################
# Setup compatdata
#############################################
[ -d "$STEAMAPPSDIR/compatdata" ] || sudo -u steam mkdir -p "$STEAMAPPSDIR/compatdata"
[ -d "$STEAMAPPSDIR/compatdata/2430930" ] || \
  sudo -u steam cp "$STEAMDIR/compatibilitytools.d/$PROTON_NAME/files/share/default_pfx" "$STEAMAPPSDIR/compatdata/2430930" -r

#############################################
# Create systemd service
#############################################
cat > /etc/systemd/system/ark-island.service <<EOF
[Unit]
Description=ARK Survival Ascended Dedicated Server (Island)
After=network.target

[Service]
Type=simple
LimitNOFILE=10000
User=steam
Group=steam
WorkingDirectory=$ARK_WIN64
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u)
Environment="STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAMDIR"
Environment="STEAM_COMPAT_DATA_PATH=$STEAMAPPSDIR/compatdata/2430930"
ExecStart=$STEAMDIR/compatibilitytools.d/$PROTON_NAME/proton run ArkAscendedServer.exe TheIsland_WP?listen
Restart=on-failure
RestartSec=20s

[Install]
WantedBy=multi-user.target
EOF

#############################################
# Install xaudio
#############################################
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XAUDIO_SRC="$SCRIPT_DIR/xaudio2_9.dll"
XAUDIO_DST="$ARK_WIN64/xaudio2_9.dll"

if [ ! -f "$XAUDIO_SRC" ]; then
  echo "xaudio2_9.dll not found next to install script" >&2
  exit 1
fi

cp "$XAUDIO_SRC" "$XAUDIO_DST"
chmod 644 "$XAUDIO_DST"
chown steam:steam "$XAUDIO_DST"

#############################################
# Enable & Start Service
#############################################
systemctl daemon-reload
systemctl enable ark-island
systemctl start ark-island

echo "Waiting for WindowsServer config directory..."

while [ ! -d "$ARK_CONFIG_DIR" ]; do
  sleep 5
done

#############################################
# Install default Game.ini
#############################################

GAMEINI_SRC="$SCRIPT_DIR/Game.ini"
GAMEINI_DST="$ARK_CONFIG_DIR/Game.ini"

if [ ! -f "$GAMEINI_SRC" ]; then
  echo "Game.ini not found next to install script" >&2
  exit 1
fi

echo "Installing default Game.ini..."

cp "$GAMEINI_SRC" "$GAMEINI_DST"
chmod 644 "$GAMEINI_DST"
chown steam:steam "$GAMEINI_DST"

echo "Game.ini installed."

#############################################
# Create MAP-specific services (No auto start)
#############################################

BASE_SERVICE="/etc/systemd/system/ark-island.service"

if [ ! -f "$BASE_SERVICE" ]; then
  echo "Base service ark-island.service not found." >&2
  exit 1
fi

# MAP定義（必要に応じて追加）
declare -A MAPS=(
  ["ScorchedEarth"]="ScorchedEarth_WP"
  ["Center"]="Center_WP"
  ["Aberration"]="Aberration_WP"
  ["Extinction"]="Extinction_WP"
  ["Astraeos"]="Astraeos_WP"
  ["Ragnarok"]="Ragnarok_WP"
  ["Valguero"]="Valguero_WP"
  ["LostColony"]="LostColony_WP"
)

echo "Creating additional MAP services..."

for MAP_KEY in "${!MAPS[@]}"; do

  MAP_INTERNAL="${MAPS[$MAP_KEY]}"
  NEW_SERVICE="/etc/systemd/system/ark-${MAP_KEY}.service"

  echo "Creating $NEW_SERVICE"

  cp "$BASE_SERVICE" "$NEW_SERVICE"

  # Description書き換え
  sed -i "s/(Island)/(${MAP_KEY^})/g" "$NEW_SERVICE"

  # ExecStart内のMAP名を書き換え
  sed -i "s/TheIsland_WP/${MAP_INTERNAL}/g" "$NEW_SERVICE"

done

systemctl daemon-reload

echo "MAP services created."


#############################################
# Helpful Symlinks
#############################################
[ -e "/home/steam/island-Game.ini" ] || \
  sudo -u steam ln -s "$ARK_CONFIG_DIR/Game.ini" /home/steam/island-Game.ini

[ -e "/home/steam/island-GameUserSettings.ini" ] || \
  sudo -u steam ln -s "$ARK_CONFIG_DIR/GameUserSettings.ini" /home/steam/island-GameUserSettings.ini

[ -e "/home/steam/island-ShooterGame.log" ] || \
  sudo -u steam ln -s "$ARK_LOG_DIR/ShooterGame.log" /home/steam/island-ShooterGame.log


echo "You can switch maps manually using:"
echo "  sudo systemctl stop ark-island"
echo "  sudo systemctl start ark-astraeos"




echo "================================================================================"
echo "If everything went well, ARK Survival Ascended should be installed and starting!"
echo ""
echo "To restart the server: sudo systemctl restart ark-island"
echo "To start the server:   sudo systemctl start ark-island"
echo "To stop the server:    sudo systemctl stop ark-island"
echo ""
echo "Configuration:"
echo "/home/steam/island-Game.ini"
echo "/home/steam/island-GameUserSettings.ini"
