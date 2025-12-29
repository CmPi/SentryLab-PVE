# SentryLab-PVE 🛡️
**Advanced Monitoring for Proxmox with MQTT & ESPHome Integration.**

`SentryLab-PVE` stands for Sentry Home Lab based on Proxmox Virtual Envirnoment. It is a lightweight, modular monitoring suite designed for my Proxmox host. It collects hardware metrics (Temperature, ZFS health, NVMe Wear/Smart...) and broadcasts them via a MQTT broker for real-time visualization on Home Assistant and, eventually, ESPHome-based physical displays.

Tested on and deployed in my Proxmox 9.1.4.

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
├── src/                       # Core engine
│   ├── sentrylab.conf         # Central configuration (MQTT, Hostname)
│   ├── utils.sh               # Shared functions
│   ├── discovery.sh           # Activation tool (enable all the timers)
│   ├── temp.sh                # Thermal monitoring
│   ├── zfs.sh                 # ZFS Health & Space
│   ├── wear.sh                # NVMe Wear level
│   ├── health.sh              # NVMe Smart Health
│   ├── *.service              # Systemd service units
│   ├── *.timer                # Systemd scheduling units
│   ├── start.sh               # Activation tool (enable all the timers)
│   └── stop.sh                # Maintenance tool (disable the timers)
└── esphome/                   # IoT Monitoring examples
    ├── sentrylab-witty.yaml   # Full ESPHome example for Witty Cloud
    └── fragments.yaml         # Universal code blocks for any RGB LED
```

## 🛠️ Installation & Setup Guide

### 0. Dependencies and Prerequisites

#### Prerequisites

* HomeAssitant
* A MQTT Broker
* One or many proxmox hosts to be monitored

#### host dependencies

The more convennient way to install or update SentryLab-PVE is to use `git`. Install it fi necessary:

```bash
apt update && apt install git -y
```
Alternatively you may of course download/unzip it with other tools.

To actually use it, mosquitto_pub and jq are required

```bash
apt update && apt install jq mosquitto_pub -y
```

* **mosquitto_pub** for MQTT publication 
* **jq** for json manipulation
* **git** to retrieve this tool

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
│   │   └── sentrylab.conf                # Configuration file to be modified        
│   └── bin/
│       └── sentrylab/
│           ├── utils.sh                  # common functions
│           ├── discovery.sh              # Initial sensor discovery and MQTT declaration
│           ├── temp.sh                   # Thermal monitoring
│           ├── zfs.sh                    # ZFS pool(s) Health & Space
│           ├── non-zfs.sh                # Other storage places
│           ├── wear.sh                   # NVMEs wear
│           └── health.sh                 # NVMe Smart Health
etc/
├── systemd/          
│   └── system/          
│       ├── sentrylab-discovery.service
│       ├── sentrylab-temp.service
│       ├── sentrylab-temp.timer          # 3mn suggested
│       ├── sentrylab-zfs.service 
│       ├── sentrylab-zfs.timer           # 15mn
│       ├── sentrylab-smart.service 
│       └── sentrylab-smart.timer         # 12h
var/
└── lib/
    └── sentrylab/
        └── exports/
            └── *.csv
         
```

### 2. Configuration

Before starting the services, you must configure your MQTT broker settings editing the configuration file (sentrylab-config.conf):

```bash
sudo nano /usr/local/etc/sentrylab.conf
```

Key Parameters:

MQTT_HOST: Replace 192.168.x.x by your MQTT Broker IP.
MQTT_USER / MQTT_PASS: MQTT Credentials.

### 3. Recommended Manual Testing (Debug/Simulation Mode)

Verify your configuration by running scripts with the DEBUG flag set to true in SentrLab.conf. This prints the JSON output and simulates MQTT publications.

# Review the configuration once more

```bash
sudo nano /usr/local/bin/utils.sh
```

# Test discovery

```bash
sudo nano /usr/local/bin/discovery.sh
```

# Test temperatures
DEBUG=true /usr/local/bin/sentrylab/temp.sh

# Test ZFS
DEBUG=true /usr/local/bin/sentrylab/zfs.sh

### 4. Enable Automation
Once discovery and reporting have been verified, activate the systemd timers to start periodic monitoring:

```bash
sudo /usr/local/bin/sentrylab/start.sh
```

To stop everything for maintenance, use sudo stop bash.

```bash
sudo /usr/local/bin/sentrylab/stop.sh
```
### 5. Integration in Home Assistant



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
* `/var/lib/sentrylab/exports/nvme_map.csv`
* `/var/lib/sentrylab/exports/zfs_map.csv`

**Pro Tip:** Upload these CSV files to an AI (like ChatGPT or Claude) and ask: *"Using these hardware IDs, write the YAML for a Home Assistant dashboard using the flex-table-card."*

---

## 🤝 Contributing
Feel free to open issues or pull requests.

**Author:** CmPi
**Repository:** [https://github.com/CmPi/SentryLab-PVE](https://github.com/CmPi/SentryLab-PVE)  
**License:** MIT
