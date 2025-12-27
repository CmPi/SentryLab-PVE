# SentryLab-PVE 🛡️
**Advanced Monitoring for Proxmox/NAS with MQTT & ESPHome Integration.**

`SentryLab-PVE` is a lightweight, modular monitoring suite designed for Proxmox hosts and NAS systems. It collects hardware metrics (Temperature, ZFS health, NVMe Wear/Smart) and broadcasts them via MQTT for real-time visualization on Home Assistant and ESPHome-based physical displays.

## 🚀 Key Features
* **Logical Separation**: Metrics are split into specialized scripts (Temp, ZFS, Wear, Health).
* **Smart Automation**: Driven by Systemd Timers (no more messy crontabs).
* **Physical Dashboard**: Optimized for ESP8266/ESP32 (Witty Cloud) to provide visual alerts (RGB LED color coding).
* **Safe Execution**: NVMe SMART checks are optimized to avoid waking up sleeping drives unnecessarily.
* **AI-Ready**: Generates CSV maps of your hardware to help LLMs generate perfect Home Assistant dashboards for you.

---

## 📂 Repository Structure
```text
SentryLab-PVE/
├── install.sh                # Main installer (deploys scripts & units)
├── sentrylab-config.conf      # Central configuration (MQTT, Hostname)
├── sentrylab-start.sh         # Activation tool
├── sentrylab-stop.sh          # Maintenance tool
├── scripts/                   # Core engine
│   ├── sentrylab-utils.sh     # Shared functions
│   ├── sentrylab-temp.sh      # Thermal monitoring
│   ├── sentrylab-zfs.sh       # ZFS Health & Space
│   ├── sentrylab-wear.sh      # NVMe Wear level
│   ├── sentrylab-health.sh    # NVMe Smart Health
│   ├── *.service              # Systemd service units
│   └── *.timer                # Systemd scheduling units
└── esphome/                   # IoT Monitoring
    ├── sentrylab-witty.yaml   # Full ESPHome example for Witty Cloud
    └── fragments.yaml         # Universal code blocks for any RGB LED