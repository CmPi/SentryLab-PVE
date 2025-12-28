# SentryLab-PVE 🛡️
**Advanced Monitoring for Proxmox/NAS with MQTT & ESPHome Integration.**

`SentryLab-PVE` is a lightweight, modular monitoring suite designed for Proxmox hosts and NAS systems. It collects hardware metrics (Temperature, ZFS health, NVMe Wear/Smart) and broadcasts them via MQTT for real-time visualization on Home Assistant and ESPHome-based physical displays.

## 🚀 Key Features
* **Logical Separation**: Metrics are split into specialized scripts (Temp, ZFS, Wear, Health).
* **Smart Automation**: Driven by Systemd Timers (no more messy crontabs).
* **Physical Dashboard**: Provide with an example for an ESP8266 (Witty Cloud) to provide visual alerts (RGB LED color coding).
* **Safe Execution**: NVMe SMART checks are optimized to avoid waking up sleeping drives unnecessarily.
* **AI-Ready**: Generates CSV maps of your hardware to help LLMs generate perfect Home Assistant dashboards for you.

---

## 📂 Repository Structure


```text
SentryLab-PVE/
├── install.sh                 # Main installer (deploys scripts & units)
├── scripts/                   # Core engine
│   ├── config.conf            # Central configuration (MQTT, Hostname)
│   ├── start.sh               # Activation tool
│   ├── stop.sh                # Maintenance tool
│   ├── utils.sh               # Shared functions
│   ├── temp.sh                # Thermal monitoring
│   ├── zfs.sh                 # ZFS Health & Space
│   ├── wear.sh                # NVMe Wear level
│   ├── health.sh              # NVMe Smart Health
│   ├── *.service              # Systemd service units
│   └── *.timer                # Systemd scheduling units
└── esphome/                   # IoT Monitoring examples
    ├── sentrylab-witty.yaml   # Full ESPHome example for Witty Cloud
    └── fragments.yaml         # Universal code blocks for any RGB LED
```

## 🛠️ Installation & Setup Guide

### 0. Dependencies and prerequesites

#### Prerequesites

* HomeAssitant
* A MQTT Broker
* A host to be monitored

#### host dependencies

* **mosquitto_pub** for MQTT publication 
* **jq** for json

### 1. Deployment

Clone the repository to your Proxmox host and run the installer:
```bash
git clone [https://github.com/CmPi/SentryLab-PVE.git](https://github.com/CmPi/SentryLab-PVE.git)
cd SentryLab-PVE
sudo ./install.sh
```

Note: The installer copies scripts to /usr/local/bin/sentrylab/ and systemd units to /etc/systemd/system/.

#### Deployed files location

```text

usr/
├── local/           
│   ├── etc/
│   │   └── sentrylab.conf          # Configuration file to be modified
│   └── bin/
│       └── sentrylab/
│           ├── discovery.sh        # Initial sensor discovery and MQTT declaration
│           ├── temp.sh             # Thermal monitoring
│           ├── zfs.sh              # ZFS oool(s) Health & Space
│           ├── wear.sh             # NVMEs wear
│           └── health.sh           # NVMe Smart Health
etc/
└── systemd/          
    └── system/          
        ├── sentrylab-discovery.service
        ├── sentrylab-temp.service
        ├── sentrylab-temp.timer
        ├── sentrylab-zfs.service
        ├── sentrylab-zfs.timer
        ├── sentrylab-smart.service
        └── sentrylab-smart.timer
         
```

### 2. Configuration

Before starting the services, you must configure your MQTT broker settings editing the configuration file (sentrylab-config.conf):

```bash
sudo nano /usr/local/etc/sentrylab/sentrylab-config.conf
```

Key Parameters:

MQTT_HOST: Your MQTT Broker IP.

MQTT_USER / MQTT_PASS: MQTT Credentials.

HOST_NAME: The identifier for Home Assistant (e.g., albusnexus).

### 3. Manual Testing (Debug Mode)
Verify your configuration by running any script with the DEBUG flag. This prints the JSON output and attempts to publish to MQTT:

# Test temperatures
DEBUG=true /usr/local/bin/sentrylab-temp.sh

# Test ZFS
DEBUG=true /usr/local/bin/sentrylab-zfs.sh

### 4. Enable Automation
Once verified, activate the systemd timers to start periodic monitoring:

sudo sentrylab-start

To stop everything for maintenance, use sudo sentrylab-stop.

## 💡 ESPHome Visual Alerts
The `esphome/sentrylab-witty.yaml` provides a turnkey solution for a **Witty Cloud** module.

1.  **Secrets**: Create a `secrets.yaml` with your `wifi_ssid`, `wifi_password`, `api_encryption_key`, and `ota_password`.
2.  **Substitution**: Set `nas_hostname` in the YAML to match the `HOST_NAME` in your `.conf` file.
3.  **Flash**: Deploy using ESPHome Dashboard or CLI.

**LED Logic:**
* **Blinking Red/Blue**: **ZFS Alert!** One of your pools is NOT 'ONLINE'.
* **Green / Orange / Red**: CPU Thermal status.
* **Off**: CPU Temperature below 35°C (Server idle or off).

---

## 📝 Hardware Mapping (CSV)
Upon startup, the discovery script exports your hardware mapping to:
* `/usr/local/etc/sentrylab/maps/nvme_map.csv`
* `/usr/local/etc/sentrylab/maps/zfs_map.csv`

**Pro Tip:** Upload these CSV files to an AI (like ChatGPT or Claude) and ask: *"Using these hardware IDs, write the YAML for a Home Assistant dashboard using the flex-table-card."*

---

## 🤝 Contributing
Feel free to open issues or pull requests.

**Author:** CmPi <cmpi@webe.fr>  
**Repository:** [https://github.com/CmPi/SentryLab-PVE](https://github.com/CmPi/SentryLab-PVE)  
**License:** MIT
