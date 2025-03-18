# Linux Monitoring Agent

Easily collect and visualize system metrics from your Linux servers and devices in **Grafana** with **Telemetry Harbor**.

**_Repo Link:_** https://github.com/TelemetryHarbor/harbor-linux-monitor

## Features
- Collect over 30 different system metrics including CPU, memory, disk, network, and more
- Customizable metric selection to fit your monitoring needs
- Configurable sampling rates from 1 second to 5 minutes
- Automatic service installation with systemd integration
- Interactive installation with color-coded interface
- Support for multiple Linux distributions
- Minimal dependencies - works on most Linux systems out of the box

## Prerequisites

Before starting, ensure you have:
- A **Linux** system with **root/sudo** access
- **curl** installed for API communication
- A working internet connection to send metrics to Telemetry Harbor
- Basic knowledge of Linux terminal commands

## Setup
### 1. Create a Telemetry Harbor Account
1. **Sign up** at [Telemetry Harbor](https://telemetryharbor.com/)
2. **Verify** your email and log in
3. **Create a Harbor**:
   - Click **Create Harbor** on your dashboard
   - Choose a **name** and select **General** as the type
   - Select the **Free** plan (or upgrade for more data capacity)
   - Click **Create**

4. **Retrieve your credentials**:
   - After creation, go to **View Details**
   - Note down:
     - `API Batch Endpoint`
     - `API Key`
     - `Grafana Endpoint`
     - `Grafana Username`
     - `Grafana Password`

### 2. Install the Monitoring Agent
1. Download the installation script:
``` bash
curl -sSL -o install-monitoring.sh https://raw.githubusercontent.com/TelemetryHarbor/harbor-linux-monitor/refs/heads/main/install.sh
```
2. Make it executable:
``` bash
chmod +x install-monitoring.sh
```
3. Run the installation script with root privileges:
``` bash
sudo ./install-monitoring.sh
```
### 3. Configuration During Installation

During installation, you'll be prompted to:

1. **Enter your Telemetry Harbor API details**:
   - API Batch Endpoint URL
   - API Key

2. **Select a sampling rate** for how often metrics are collected:
   - Every 1 second
   - Every 5 seconds
   - Every 30 seconds
   - Every 1 minute (default)
   - Every 5 minutes

3. **Choose which metrics to monitor** using either:
   - Interactive checkbox menu (arrow keys to navigate, space to select)
   - Simple number entry

## Available Metrics

The monitoring agent can collect the following metrics:

| Metric | Description |
|--------|-------------|
| CPU Usage | Overall CPU utilization percentage |
| CPU Cores | Individual CPU core usage percentages |
| RAM Usage | Memory usage percentage |
| RAM Detailed | Detailed memory statistics (used, free, cached, etc.) |
| Disk Usage | Root partition usage percentage |
| Disk All | Usage for all mounted partitions |
| Load Average | System load averages (1, 5, and 15 minutes) |
| Processes | Total number of running processes |
| Zombie Processes | Count of zombie processes |
| Network In/Out | Network traffic rates |
| Network Errors | Network error and dropped packet counts |
| Temperature | CPU temperature (if available) |
| Uptime | System uptime in seconds |
| Boot Time | When the system was last booted |
| Swap Usage | Swap space usage percentage |
| Disk I/O | Disk read/write operations per second |
| Open Files | Number of open file descriptors |
| TCP/UDP Connections | Count of active network connections |
| Logged Users | Number of users logged into the system |
| System Entropy | Available entropy in the random pool |
| Context Switches | Rate of CPU context switches |
| Interrupts | Rate of hardware interrupts |
| Kernel Version | Linux kernel version |
| Battery | Battery status and capacity (if applicable) |

## Managing the Service

After installation, the monitoring service runs automatically. You can manage it using:

# Check service status
``` bash
systemctl status harbor-monitor
```
# View logs
``` bash
journalctl -u harbor-monitor -f
```
# Stop the service
``` bash
systemctl stop harbor-monitor
```
# Start the service
``` bash
systemctl start harbor-monitor
```
# Disable automatic startup
``` bash
systemctl disable harbor-monitor
```
# Enable automatic startup
``` bash
systemctl enable harbor-monitor
```
## Uninstalling

To uninstall the monitoring agent:

1. Run the installation script again:
``` bash
sudo ./install-monitoring.sh
```
3. Select the "Uninstall Harbor Monitor" option from the menu.

## Troubleshooting

### Common Issues

**Error: Failed to send test data point**
- Verify your API endpoint and key are correct
- Check your internet connection
- Ensure your firewall allows outbound connections

**Service starts but no data appears in Grafana**
- Check the service logs: `journalctl -u harbor-monitor -f`
- Verify the metrics are being collected correctly
- Ensure your Telemetry Harbor account is active

**High CPU usage from the monitoring service**
- Increase the sampling rate to reduce frequency
- Reduce the number of metrics being collected
- Check for any system issues that might be causing high CPU usage
