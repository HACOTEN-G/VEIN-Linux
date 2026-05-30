#!/bin/bash

#############################################
# ARK Server Auto-Reboot Cron Setup Script
#############################################

if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root."
  echo "Example: sudo ./setup-cron-reboot.sh"
  exit 1
fi

echo "==========================================="
echo " ARK Server Auto Reboot Setup"
echo "==========================================="
echo ""

read -p "Enter the reboot hour (0-23): " REBOOT_HOUR

if ! [[ "$REBOOT_HOUR" =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; then
  echo "Invalid time. Please enter a number between 0 and 23."
  exit 1
fi

echo ""
echo "Select reboot frequency:"
echo "1) Daily"
echo "2) Weekly"
read -p "Enter number (1 or 2): " SCHEDULE_TYPE

if [ "$SCHEDULE_TYPE" == "1" ]; then
  CRON_ENTRY="0 $REBOOT_HOUR * * * /usr/sbin/shutdown -r now"
  DESCRIPTION="Reboot daily at ${REBOOT_HOUR}:00"
elif [ "$SCHEDULE_TYPE" == "2" ]; then
  echo ""
  echo "Select day of the week:"
  echo "0=Sun 1=Mon 2=Tue 3=Wed 4=Thu 5=Fri 6=Sat"
  read -p "Enter weekday number (0-6): " WEEKDAY

  if ! [[ "$WEEKDAY" =~ ^[0-6]$ ]]; then
    echo "Invalid weekday."
    exit 1
  fi

  WEEKNAME=("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat")
  CRON_ENTRY="0 $REBOOT_HOUR * * $WEEKDAY /usr/sbin/shutdown -r now"
  DESCRIPTION="Reboot weekly on ${WEEKNAME[$WEEKDAY]} at ${REBOOT_HOUR}:00"
else
  echo "Invalid selection."
  exit 1
fi

echo ""
echo "-------------------------------------------"
echo "The following settings will be applied:"
echo "  $DESCRIPTION"
echo "-------------------------------------------"
read -p "Apply these settings? (y/n): " CONFIRM

if [ "$CONFIRM" != "y" ]; then
  echo "Operation cancelled."
  exit 0
fi

# Remove existing shutdown entries
crontab -l 2>/dev/null | grep -v "/usr/sbin/shutdown -r now" > /tmp/cron_backup

echo "$CRON_ENTRY" >> /tmp/cron_backup
crontab /tmp/cron_backup
rm /tmp/cron_backup

echo ""
echo "==========================================="
echo " Setup completed successfully"
echo "==========================================="
echo ""
echo "Current crontab configuration:"
echo "-------------------------------------------"
crontab -l
echo "-------------------------------------------"
