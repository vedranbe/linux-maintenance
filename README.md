# 🛠 Linux Mint System Maintenance Tool

![Linux](https://img.shields.io/badge/Linux-Ubuntu--based-red)  
![Desktop](https://img.shields.io/badge/Desktop-GNOME-4A86CF?logo=gnome&logoColor=white)   
![Shell Script](https://img.shields.io/badge/Bash-Script-blue)  
![Status](https://img.shields.io/badge/Status-Stable-brightgreen)  
![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)     

A powerful, menu-driven maintenance utility for **Ubuntu-based systems** that safely handles system updates, cleanup, and optimization from a friendly terminal interface.

---

## ✨ Features

- Interactive terminal menu  
- Secure administrator authentication (no GUI popups)  
- Full system update support  
- Deep system cleaning (logs, caches, packages)  
- Automatic timestamped logging  
- Flatpak & Snap support  
- Firmware update support  
- Smart safety checks (Timeshift detection)  
- Clean exit handling  

---

## 🔐 Privilege Model

The script uses a secure privilege bootstrap:

1. Starts as a normal user  
2. Displays a system banner  
3. Requests administrator password inside the terminal  
4. Relaunches itself with elevated privileges  

This avoids:

- GUI password dialogs  
- Broken logging  
- Multiple password prompts  

---

## 🧹 Cleaning Scope

The tool safely removes:

- Unused packages and old kernels  
- Package caches  
- Old logs and compressed logs  
- Oversized log files  
- Old systemd journal entries  
- Old Snap revisions  
- Unused Flatpak runtimes  
- Browser caches  
- Thumbnail cache  

---

## 🔄 Update Scope

- System package updates  
- Flatpak application updates  
- Firmware updates (if supported)  

---

## 🖥 Menu Overview

| Option | Description |
|--------|-------------|
| 1 | Full Update |
| 2 | Full Clean |
| 3 | Update + Clean |
| 4 | Quick Update |
| 5 | Quick Clean |
| 6 | Disk Usage Report |
| 7 | View Logs |
| 0 | Exit |

---

## 📜 Logging

Logs are stored in:
~/Documents/Shortcuts/logs/

You can change it :) 

Each run creates a timestamped log file for troubleshooting or review.

---

## 🚀 Running the Tool

### Make it executable

```bash
chmod +x /path/to/mint-maint.sh
```

### Run from Terminal

```bash
bash /path/to/mint-maint.sh
```

### Desktop Launcher Example
```
[Desktop Entry]
Version=1.0
Type=Application
Name=Mint Maintenance
Exec=gnome-terminal -- bash -c "/path/to/mint-maint.sh"
Icon=utilities-terminal
Terminal=false
Categories=System;
```
