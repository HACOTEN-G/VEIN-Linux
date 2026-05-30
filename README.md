# Tools for managing VEIN Dedicated Server on Linux

This script is a copy.

## What does it do?

This script will:

* Download Proton from Glorious Eggroll's build
* Install Steam and SteamCMD
* Create a `steam` user for running the game server
* Install the VEIN Dedicated Server using standard Steam procedures
* Setup a systemd service for running the game server

---

What this script will *not* do:

Provide any sort of management interface over your server.

It's just a bootstrap script to install the game and its dependencies in a standard way so *you* can choose how you want to manage it.

## Features

Because it's managed with systemd, standardized commands are used for managing the server.

This includes:

* Automatic restart if the server crashes
* Automatic updates when the service is restarted
* Easy management through systemctl

By default, the server will **automatically start at boot**.

## Installation on Linux

Quick run (if you trust me, which you of course should not):

```bash
mkdir git && cd $_
```

```bash
git clone https://github.com/HACOTEN-G/VEIN-Linux.git
```

```bash
sudo chmod -R 777 /root/git/VEIN-Linux
```

```bash
cd VEIN-Linux/
```

```bash
sudo ./setup-vein-server.sh
```

---

## Restarting your server (and updating)

The service will automatically check Steam for the newest version of VEIN on restart.

```bash
sudo systemctl restart vein-server
```

---

## Stopping your server

```bash
sudo systemctl stop vein-server
```

---

## Configuring the server

Configuration files are stored in the VEIN server directory.

Example:

```bash
sudo -u steam nano /home/steam/vein-server/config.json
```

*If your installation uses a different configuration file name or location, adjust the path accordingly.*

---

## Adding command line arguments

Some server settings may need to be passed as command-line arguments.

Edit the systemd service file:

```bash
sudo nano /etc/systemd/system/vein-server.service
```

Look for the `ExecStart=` line:

```bash
ExecStart=/home/steam/(wherever-steam-is)/compatibilitytools.d/GE-Proton/proton run VEINServer.exe
```

Add any required command-line arguments to the end of that line.

After saving your changes, reload systemd:

```bash
sudo systemctl daemon-reload
```

This command does **not** restart the server.

---

## Automatic restarts

Want to restart your server automatically at 5:00 AM every day?

Edit crontab:

```bash
sudo nano /etc/crontab
```

Add:

```bash
0 5 * * * root systemctl restart vein-server
```

(0 = minute, 5 = hour in 24-hour notation, followed by `* * *` for every day, every month, and every weekday.)

---

## Notes

(2026/05/30 by HACOTEN)

* Added Proton installation support.
* Added automatic SteamCMD installation.
* Added systemd service creation.
* Fixed Proton-related audio issues by automatically copying required DLL files when necessary.
