#!/bin/bash
#
# VEIN Dedicated Server Setup Script
# Ubuntu 22.04 / 24.04 向け (ConoHa VPS等)
# SteamCMD + Proton GE を使用してWindowsバイナリを実行します
#
# 使用ポート (ConoHaコンソールで開放してください):
#   UDP 7777  - ゲームポート
#   UDP 27015 - Steam クエリポート
#
# 使い方:
#   chmod +x setup-vein-server.sh
#   sudo ./setup-vein-server.sh

# ============================================================
# root チェック
# ============================================================
if [ "$LOGNAME" != "root" ]; then
  echo "rootで実行してください。(su の場合は 'su -' を使用してください)" >&2
  exit 1
fi

# ============================================================
# 定数
# ============================================================
APP_ID=2131400
VEIN_INSTALL_SUBDIR="vein_server"    # steam ホーム内のインストール先サブディレクトリ名
PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton9-20/GE-Proton9-20.tar.gz"
PROTON_TGZ="$(basename "$PROTON_URL")"
PROTON_NAME="$(basename "$PROTON_TGZ" ".tar.gz")"
MAX_RETRIES=3
RETRY_DELAY=15
LOG_FILE="/tmp/steamcmd_vein_install.log"

# ============================================================
# 既存サービスの停止・削除
# ============================================================
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

# ============================================================
# スワップ作成 (16GB、未作成の場合のみ)
# ============================================================
if ! swapon --show | grep -q "/swapfile"; then
  echo "16GB スワップファイルを作成します..."
  fallocate -l 16G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=16384
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
  echo "スワップを作成・有効化しました。"
else
  echo "スワップは既に存在します。スキップします。"
fi

# ============================================================
# 作業ディレクトリ
# ============================================================
[ -d /opt/game-resources ] || mkdir -p /opt/game-resources

# ============================================================
# 必要パッケージのインストール
# ============================================================
dpkg --add-architecture i386
apt update
apt install -y \
  software-properties-common \
  apt-transport-https \
  dirmngr \
  ca-certificates \
  curl \
  wget \
  sudo \
  lib32gcc-s1

# ============================================================
# Steam リポジトリの追加
# ============================================================
curl -s http://repo.steampowered.com/steam/archive/stable/steam.gpg \
  > /usr/share/keyrings/steam.gpg

echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] \
http://repo.steampowered.com/steam/ stable steam" \
  > /etc/apt/sources.list.d/steam.list

apt update
apt install -y steamcmd

# ============================================================
# Proton GE のダウンロード
# ============================================================
if [ ! -f "/opt/game-resources/$PROTON_TGZ" ]; then
  echo "Proton GE をダウンロードします: $PROTON_URL"
  wget "$PROTON_URL" -O "/opt/game-resources/$PROTON_TGZ"
else
  echo "Proton GE は既にダウンロード済みです。スキップします。"
fi

# ============================================================
# steam ユーザーの作成
# ============================================================
if ! id steam &>/dev/null; then
  useradd -m -U steam
  echo "steam ユーザーを作成しました。"
else
  echo "steam ユーザーは既に存在します。"
fi

# ============================================================
# VEIN サーバーのインストール (リトライ付き)
# ============================================================
echo "VEIN サーバー (App ID: $APP_ID) をインストールします..."

for ((i=1; i<=MAX_RETRIES; i++)); do
  echo "試行 $i / $MAX_RETRIES"

  sudo -u steam /usr/games/steamcmd \
    +login anonymous \
    +force_install_dir "/home/steam/$VEIN_INSTALL_SUBDIR" \
    +app_update $APP_ID validate \
    +quit | tee "$LOG_FILE"

  if grep -q "Success! App '$APP_ID'" "$LOG_FILE"; then
    echo "インストール成功。"
    break
  fi

  if [ "$i" -lt "$MAX_RETRIES" ]; then
    echo "インストール失敗。${RETRY_DELAY}秒後にリトライします..."
    sleep $RETRY_DELAY
  else
    echo "ERROR: ${MAX_RETRIES}回試行しましたがインストールに失敗しました。" >&2
    exit 1
  fi
done

# ============================================================
# Steam ディレクトリの検出
# ============================================================
if [ -d "/home/steam/Steam" ]; then
  STEAMDIR="/home/steam/Steam"
elif [ -d "/home/steam/.local/share/Steam" ]; then
  STEAMDIR="/home/steam/.local/share/Steam"
elif [ -d "/home/steam/.steam/steam" ]; then
  STEAMDIR="/home/steam/.steam/steam"
else
  echo "ERROR: Steam のインストールディレクトリが見つかりません。" >&2
  exit 1
fi

if [ -d "$STEAMDIR/steamapps" ]; then
  STEAMAPPSDIR="$STEAMDIR/steamapps"
elif [ -d "$STEAMDIR/SteamApps" ]; then
  STEAMAPPSDIR="$STEAMDIR/SteamApps"
else
  echo "ERROR: SteamApps ディレクトリが見つかりません。" >&2
  exit 1
fi

echo "Steam ディレクトリ: $STEAMDIR"
echo "SteamApps ディレクトリ: $STEAMAPPSDIR"

# ============================================================
# VEIN インストールディレクトリの確認
# ============================================================
VEIN_ROOT="/home/steam/$VEIN_INSTALL_SUBDIR"
VEIN_CONFIG_DIR="$VEIN_ROOT/Vein/Saved/Config/WindowsServer"
VEIN_LOG_DIR="$VEIN_ROOT/Vein/Saved/Logs"

if [ ! -d "$VEIN_ROOT" ]; then
  echo "ERROR: VEIN インストールディレクトリが見つかりません: $VEIN_ROOT" >&2
  exit 1
fi

echo "VEIN インストールディレクトリ: $VEIN_ROOT"

# ============================================================
# Proton GE のインストール
# ============================================================
[ -d "$STEAMDIR/compatibilitytools.d" ] || \
  sudo -u steam mkdir -p "$STEAMDIR/compatibilitytools.d"

if [ ! -d "$STEAMDIR/compatibilitytools.d/$PROTON_NAME" ]; then
  echo "Proton GE を展開します..."
  sudo -u steam tar -x \
    -C "$STEAMDIR/compatibilitytools.d/" \
    -f "/opt/game-resources/$PROTON_TGZ"
  echo "Proton GE のインストール完了。"
else
  echo "Proton GE は既にインストール済みです。スキップします。"
fi

# ============================================================
# compatdata のセットアップ
# ============================================================
[ -d "$STEAMAPPSDIR/compatdata" ] || \
  sudo -u steam mkdir -p "$STEAMAPPSDIR/compatdata"

if [ ! -d "$STEAMAPPSDIR/compatdata/$APP_ID" ]; then
  echo "compatdata をセットアップします..."
  sudo -u steam cp \
    "$STEAMDIR/compatibilitytools.d/$PROTON_NAME/files/share/default_pfx" \
    "$STEAMAPPSDIR/compatdata/$APP_ID" -r
  echo "compatdata のセットアップ完了。"
fi

# ============================================================
# Game.ini の初期作成
# ============================================================
# サービス起動前に設定ファイルが置けるようディレクトリを作成
sudo -u steam mkdir -p "$VEIN_CONFIG_DIR"

GAMEINI_PATH="$VEIN_CONFIG_DIR/Game.ini"

if [ ! -f "$GAMEINI_PATH" ]; then
  echo "Game.ini を作成します..."

  sudo -u steam tee "$GAMEINI_PATH" > /dev/null <<'GAMEINI'
[/script/engine.gamesession]
MaxPlayers=8

[/script/vein.veingamesession]
ServerName="My VEIN Server"
Password=""
GAMEINI

  chmod 644 "$GAMEINI_PATH"
  chown steam:steam "$GAMEINI_PATH"
  echo "Game.ini を作成しました: $GAMEINI_PATH"
  echo ">>> サーバー名やパスワードは以下のファイルで編集してください:"
  echo "    $GAMEINI_PATH"
else
  echo "Game.ini は既に存在します。スキップします。"
fi

# ============================================================
# systemd サービスの作成
# ============================================================
STEAM_UID=$(id -u steam)

cat > /etc/systemd/system/vein-server.service <<EOF
[Unit]
Description=VEIN Dedicated Server
After=network.target

[Service]
Type=simple
LimitNOFILE=10000
User=steam
Group=steam
WorkingDirectory=$VEIN_ROOT
Environment=XDG_RUNTIME_DIR=/run/user/${STEAM_UID}
Environment="STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAMDIR"
Environment="STEAM_COMPAT_DATA_PATH=$STEAMAPPSDIR/compatdata/$APP_ID"
ExecStart=$STEAMDIR/compatibilitytools.d/$PROTON_NAME/proton run VeinServer.exe -log
Restart=on-failure
RestartSec=20s

[Install]
WantedBy=multi-user.target
EOF

echo "systemd サービスファイルを作成しました。"

# ============================================================
# サービスの有効化と起動
# ============================================================
systemctl daemon-reload
systemctl enable vein-server
systemctl start vein-server

echo "vein-server サービスを起動しました。"

# ============================================================
# 便利なシンボリックリンクの作成
# ============================================================

# Game.ini
[ -e "/home/steam/vein-Game.ini" ] || \
  sudo -u steam ln -s "$VEIN_CONFIG_DIR/Game.ini" /home/steam/vein-Game.ini

# GameUserSettings.ini (起動後に生成される)
if [ -f "$VEIN_CONFIG_DIR/GameUserSettings.ini" ]; then
  [ -e "/home/steam/vein-GameUserSettings.ini" ] || \
    sudo -u steam ln -s "$VEIN_CONFIG_DIR/GameUserSettings.ini" \
      /home/steam/vein-GameUserSettings.ini
fi

# ログファイル (起動後に生成される)
if [ -d "$VEIN_LOG_DIR" ]; then
  [ -e "/home/steam/vein-Vein.log" ] || \
    sudo -u steam ln -s "$VEIN_LOG_DIR/Vein.log" /home/steam/vein-Vein.log 2>/dev/null || true
fi

# ============================================================
# 完了メッセージ
# ============================================================
echo ""
echo "========================================================================"
echo "VEIN Dedicated Server のセットアップが完了しました！"
echo ""
echo "【サービス操作】"
echo "  起動:    sudo systemctl start vein-server"
echo "  停止:    sudo systemctl stop vein-server"
echo "  再起動:  sudo systemctl restart vein-server"
echo "  状態確認: sudo systemctl status vein-server"
echo ""
echo "【設定ファイル】"
echo "  $GAMEINI_PATH"
echo "  (シンボリックリンク: /home/steam/vein-Game.ini)"
echo ""
echo "【ログ確認】"
echo "  sudo journalctl -u vein-server -f"
echo ""
echo "【使用ポート (ConoHaコンソールで開放済みであること)】"
echo "  UDP 7777  - ゲームポート"
echo "  UDP 27015 - Steam クエリポート"
echo ""
echo "【接続方法】"
echo "  VEINクライアントの「Join Multiplayer」からサーバー名で検索してください。"
echo "========================================================================"
