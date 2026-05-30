#!/bin/bash

#############################################
# ARK Bulk Service Option Change + Update
#############################################

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./update-ark-services.sh)"
  exit 1
fi

SERVICE_DIR="/etc/systemd/system"
APP_ID=2430930

declare -A MAPS=(
  ["island"]="TheIsland_WP"
  ["ScorchedEarth"]="ScorchedEarth_WP"
  ["Center"]="Center_WP"
  ["Aberration"]="Aberration_WP"
  ["Extinction"]="Extinction_WP"
  ["Astraeos"]="Astraeos_WP"
  ["Ragnarok"]="Ragnarok_WP"
  ["Valguero"]="Valguero_WP"
  ["LostColony"]="LostColony_WP"
)

echo "==========================================="
echo " ARK Service Configuration Tool"
echo "==========================================="

#############################################
# ① Select Target
#############################################

echo ""
echo "① Select target to modify"
echo "1) All MAPs"
echo "2) Single MAP"
read -p "Enter number: " TARGET_TYPE

TARGET_SERVICES=()

if [ "$TARGET_TYPE" == "1" ]; then
  for MAP in "${!MAPS[@]}"; do
    TARGET_SERVICES+=("ark-${MAP}.service")
  done
elif [ "$TARGET_TYPE" == "2" ]; then
  echo ""
  MAP_KEYS=("${!MAPS[@]}")
  i=1
  for MAP in "${MAP_KEYS[@]}"; do
    echo "$i) $MAP"
    ((i++))
  done
  read -p "Select number: " MAP_INDEX
  SELECTED_MAP="${MAP_KEYS[$((MAP_INDEX-1))]}"
  TARGET_SERVICES+=("ark-${SELECTED_MAP}.service")
else
  echo "Input error"
  exit 1
fi

#############################################
# Stop Services
#############################################

echo ""
echo "Stopping target services..."
for SVC in "${TARGET_SERVICES[@]}"; do
  systemctl stop "$SVC" 2>/dev/null
done

#############################################
# Get Current ExecStart (from first service)
#############################################

FIRST_SERVICE="${SERVICE_DIR}/${TARGET_SERVICES[0]}"
CURRENT_LINE=$(grep "^ExecStart=" "$FIRST_SERVICE")

# 修正: スペースも区切り文字に含めて MAP 名を正しく抽出
CURRENT_MAP=$(echo "$CURRENT_LINE" | sed -E 's/.*ArkAscendedServer\.exe ([^ ?]+).*/\1/')

CURRENT_SESSION=$(echo "$CURRENT_LINE" | sed -E 's/.*SessionName=([^?]+).*/\1/')
CURRENT_PASS=$(echo "$CURRENT_LINE" | grep -oP 'ServerPassword=\K[^ ]+' || echo "")
CURRENT_PLATFORM=$(echo "$CURRENT_LINE" | grep -oP 'ServerPlatform=\K[^ ]+' || echo "")
CURRENT_MODS=$(echo "$CURRENT_LINE" | grep -oP 'mods=\K[^ ]+' || echo "")

#############################################
# ② Server Name
#############################################

SESSION_NAME="$CURRENT_SESSION"
read -p "② Change server name? (y/n): " CHANGE
if [ "$CHANGE" == "y" ]; then
  read -p "New server name: " SESSION_NAME
fi

#############################################
# ③ Password
#############################################

SERVER_PASS="$CURRENT_PASS"
read -p "③ Change password? (y/n): " CHANGE
if [ "$CHANGE" == "y" ]; then
  read -p "New password: " SERVER_PASS
fi

#############################################
# ④ Platform
#############################################

PLATFORM="$CURRENT_PLATFORM"
read -p "④ Change platform? (y/n): " CHANGE
if [ "$CHANGE" == "y" ]; then
  echo "1) PC only"
  echo "2) XSX only"
  echo "3) PS5 only"
  echo "4) PC+XSX+PS5+WINGDK (Allow All)"
  read -p "Enter number: " PLATFORM_TYPE
  case $PLATFORM_TYPE in
    1) PLATFORM="PC" ;;
    2) PLATFORM="XSX" ;;
    3) PLATFORM="PS5" ;;
    4) PLATFORM="PC+XSX+PS5+WINGDK" ;;
    *) echo "Input error"; exit 1 ;;
  esac
fi

# 空ならPCに強制
if [ -z "$PLATFORM" ]; then
  PLATFORM="PC"
fi

#############################################
# ⑤ MOD
#############################################

MOD_IDS="$CURRENT_MODS"
read -p "⑤ Change MODs? (y/n): " CHANGE
if [ "$CHANGE" == "y" ]; then
  read -p "MOD IDs (comma-separated, leave empty for none): " MOD_IDS
fi

#############################################
# Final Confirmation
#############################################

echo ""
echo "-------------------------------------------"
echo "Final settings:"
echo " Server Name: $SESSION_NAME"
echo " Password: $SERVER_PASS"
echo " Platform: $PLATFORM"
echo " MODs: ${MOD_IDS:-None}"
echo "-------------------------------------------"
read -p "Apply these changes? (y/n): " CONFIRM
[ "$CONFIRM" != "y" ] && exit 0

#############################################
# Update ExecStart
#############################################

BASE_FLAGS="-ServerPlatform=${PLATFORM}"
[ -n "$MOD_IDS" ] && BASE_FLAGS="$BASE_FLAGS -mods=${MOD_IDS}"

for SVC in "${TARGET_SERVICES[@]}"; do

  SERVICE_FILE="${SERVICE_DIR}/${SVC}"
  [ ! -f "$SERVICE_FILE" ] && continue

  LINE=$(grep "^ExecStart=" "$SERVICE_FILE")

  # 修正: スペースも区切り文字に含めて MAP 名を正しく抽出
  MAP_NAME=$(echo "$LINE" | sed -E 's/.*ArkAscendedServer\.exe ([^ ?]+).*/\1/')

  # 修正: 「proton run ArkAscendedServer.exe」までを最短一致で切り出す
  #        これにより前マップ名がプレフィックスに混入するバグを修正
  EXEC_PREFIX=$(echo "$LINE" | sed -E 's/^ExecStart=([^ ]+ run ArkAscendedServer\.exe).*/\1/')

  NEW_EXEC="ExecStart=${EXEC_PREFIX} ${MAP_NAME}?listen?SessionName=${SESSION_NAME}?ServerPassword=${SERVER_PASS} ${BASE_FLAGS}"

  sed -i "s|^ExecStart=.*|${NEW_EXEC}|g" "$SERVICE_FILE"

  echo "Update completed: $SVC"

done

systemctl daemon-reload

echo ""
echo "To start a service:"
echo " sudo systemctl start <service-name>"
