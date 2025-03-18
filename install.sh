#!/bin/bash

# Exit on any error
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "\e[31mPlease run as root\e[0m"
  exit 1
fi

# Colors and formatting
BLUE="\e[34m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BOLD="\e[1m"
UNDERLINE="\e[4m"
RESET="\e[0m"

# Introduction
display_intro() {
  clear
  echo -e "${BLUE}${BOLD}======================================================${RESET}"
  echo -e "${BLUE}${BOLD}             TELEMETRY HARBOR MONITOR               ${RESET}"
  echo -e "${BLUE}${BOLD}======================================================${RESET}"
  echo ""
  echo -e "This script will set up a monitoring service that collects"
  echo -e "various system metrics and sends them to your Telemetry Harbor endpoint."
  echo ""
  echo -e "${YELLOW}The Harbor Monitor will:${RESET}"
  echo -e "  • Run as a systemd service that starts automatically on boot"
  echo -e "  • Collect your selected metrics at your chosen interval"
  echo -e "  • Send data to your Telemetry Harbor endpoint in batch format"
  echo -e "  • Each metric will be sent as a separate cargo with your hostname as the ship_id"
  echo ""
}

# Check if service is already installed
check_installation() {
  if [ -f "/etc/systemd/system/harbor-monitor.service" ] || [ -f "/usr/local/bin/harbor-monitor.sh" ]; then
    echo -e "${YELLOW}Harbor Monitor is already installed on this system.${RESET}"
    echo ""
    echo -e "What would you like to do?"
    echo -e "  ${BOLD}1.${RESET} Reinstall Harbor Monitor"
    echo -e "  ${BOLD}2.${RESET} Exit"
    
    read -p "Enter your choice (1-2): " REINSTALL_CHOICE
    
    if [ "$REINSTALL_CHOICE" = "1" ]; then
      uninstall "quiet"
      echo -e "${GREEN}Previous installation removed. Proceeding with new installation...${RESET}"
      echo ""
    else
      echo -e "${YELLOW}Installation cancelled.${RESET}"
      exit 0
    fi
  fi
}

# Uninstall function
uninstall() {
  if [ "$1" != "quiet" ]; then
    echo -e "${YELLOW}Uninstalling Harbor Monitor...${RESET}"
  fi
  
  # Stop and disable the service
  systemctl stop harbor-monitor.service 2>/dev/null || true
  systemctl disable harbor-monitor.service 2>/dev/null || true
  
  # Remove service file
  rm -f /etc/systemd/system/harbor-monitor.service
  
  # Remove monitoring script
  rm -f /usr/local/bin/harbor-monitor.sh
  
  # Reload systemd
  systemctl daemon-reload
  
  if [ "$1" != "quiet" ]; then
    echo -e "${GREEN}Harbor Monitor has been uninstalled.${RESET}"
    exit 0
  fi
}

# Check for uninstall argument
if [ "$1" = "--uninstall" ]; then
  uninstall
fi

# Available metrics to collect with detailed descriptions
declare -a available_metrics=(
  "cpu_usage:Overall CPU Usage (%):Measures the total CPU utilization across all cores"
  "ram_usage:RAM Usage (%):Percentage of total RAM currently in use"
  "disk_usage:Root Disk Usage (%):Percentage of root partition (/) space used"
  "load_average_1m:Load Average (1 min):System load average over the last 1 minute"
  "load_average_5m:Load Average (5 min):System load average over the last 5 minutes"
  "load_average_15m:Load Average (15 min):System load average over the last 15 minutes"
  "processes:Process Count:Total number of running processes"
  "zombie_processes:Zombie Process Count:Number of zombie processes (terminated but not reaped)"
  "network_in:Network In (bytes/s):Incoming network traffic rate"
  "network_out:Network Out (bytes/s):Outgoing network traffic rate"
  "temperature:CPU Temperature (°C):Temperature of the CPU if available"
  "uptime:System Uptime (seconds):How long the system has been running"
  "swap_usage:Swap Usage (%):Percentage of swap space currently in use"
  "disk_io:Disk I/O Operations (IOPS):Total disk I/O operations per second"
  "disk_read:Disk Read (ops/s):Disk read operations per second"
  "disk_write:Disk Write (ops/s):Disk write operations per second"
  "open_files:Open File Descriptors:Number of open file descriptors system-wide"
  "tcp_connections:TCP Connection Count:Number of established TCP connections"
  "udp_connections:UDP Connection Count:Number of UDP connections"
  "logged_users:Logged in Users:Number of users currently logged into the system"
  "entropy:System Entropy:Available entropy in the system's random pool"
  "context_switches:Context Switches (per sec):Rate of CPU context switches"
  "interrupts:Interrupts (per sec):Rate of hardware interrupts"
)

# Function to display checkbox menu for metric selection
select_metrics_with_checkboxes() {
  # Save cursor position and hide cursor
  tput sc
  tput civis
  
  # Initialize variables
  local selected=()
  local current_pos=0
  local max_pos=$((${#available_metrics[@]}))  # +1 for "Select All" option
  
  # Initialize selected array with zeros (not selected)
  for ((i=0; i<=${max_pos}; i++)); do
    selected[$i]=0
  done
  
  # Function to draw the menu
  draw_menu() {
    # Restore cursor position
    tput rc
    
    echo -e "${BLUE}${BOLD}Select metrics to monitor:${RESET} (use ${UNDERLINE}UP/DOWN${RESET} to navigate, ${UNDERLINE}SPACE${RESET} to select, ${UNDERLINE}ENTER${RESET} to confirm)"
    echo -e "${YELLOW}Note:${RESET} The number of metrics should not exceed your telemetry harbor's max batch size."
    echo ""
    
    # Add "Select All" option at the top
    if [ "$current_pos" -eq 0 ]; then
      echo -e " \e[7m[ ] ${BOLD}SELECT ALL METRICS${RESET}\e[0m"
    else
      local check="[ ]"
      if [ "${selected[0]}" -eq 1 ]; then
        check="[x]"
      fi
      echo -e " $check ${BOLD}SELECT ALL METRICS${RESET}"
    fi
    
    echo ""
    
    for i in "${!available_metrics[@]}"; do
      local pos=$((i+1))  # Offset by 1 because of "Select All"
      local metric_info=(${available_metrics[$i]//:/ })
      local check="[ ]"
      if [ "${selected[$pos]}" -eq 1 ]; then
        check="[x]"
      fi
      
      if [ "$pos" -eq "$current_pos" ]; then
        echo -e " \e[7m$check ${BOLD}${metric_info[1]}${RESET}\e[0m"
        echo -e "      \e[3m${metric_info[2]}\e[0m"
      else
        echo -e " $check ${metric_info[1]}"
        echo -e "      \e[3m${metric_info[2]}\e[0m"
      fi
    done
  }
  
  # Initial draw
  draw_menu
  
  # Handle key presses - improved method for better terminal compatibility
  while true; do
    # Use stty to disable canonical mode and echo
    stty -echo -icanon
    
    # Read a single character
    dd if=/dev/tty bs=1 count=1 2>/dev/null | xxd -p > /tmp/key_press
    
    # Re-enable canonical mode and echo
    stty echo icanon
    
    # Get the key code
    key=$(cat /tmp/key_press)
    
    # Check for arrow keys and other special keys
    if [ "$key" = "1b" ]; then # ESC
      # Read the next two bytes for arrow keys
      stty -echo -icanon
      dd if=/dev/tty bs=1 count=2 2>/dev/null | xxd -p > /tmp/key_press_ext
      stty echo icanon
      
      key_ext=$(cat /tmp/key_press_ext)
      
      if [ "$key_ext" = "5b41" ]; then # Up arrow
        ((current_pos--))
        if [ "$current_pos" -lt 0 ]; then
          current_pos=$max_pos
        fi
      elif [ "$key_ext" = "5b42" ]; then # Down arrow
        ((current_pos++))
        if [ "$current_pos" -gt "$max_pos" ]; then
          current_pos=0
        fi
      fi
    elif [ "$key" = "20" ]; then # Space
      # Toggle selection
      if [ "$current_pos" -eq 0 ]; then
        # Select/deselect all
        if [ "${selected[0]}" -eq 0 ]; then
          selected[0]=1
          # Select all metrics
          for ((i=1; i<=${max_pos}; i++)); do
            selected[$i]=1
          done
        else
          selected[0]=0
          # Deselect all metrics
          for ((i=1; i<=${max_pos}; i++)); do
            selected[$i]=0
          done
        fi
      else
        # Toggle individual metric
        if [ "${selected[$current_pos]}" -eq 0 ]; then
          selected[$current_pos]=1
        else
          selected[$current_pos]=0
        fi
        
        # Check if all metrics are selected
        local all_selected=1
        for ((i=1; i<=${max_pos}; i++)); do
          if [ "${selected[$i]}" -eq 0 ]; then
            all_selected=0
            break
          fi
        done
        
        # Update "Select All" status
        selected[0]=$all_selected
      fi
    elif [ "$key" = "0a" ]; then # Enter
      # Break the loop
      break
    fi
    
    # Redraw menu
    draw_menu
  done
  
  # Show cursor again
  tput cnorm
  
  # Clear the menu area
  tput rc
  for ((i=0; i<=$((max_pos*2+5)); i++)); do
    tput el
    echo ""
  done
  tput rc
  
  # Build the selected metrics array
  for i in "${!available_metrics[@]}"; do
    local pos=$((i+1))  # Offset by 1 because of "Select All"
    if [ "${selected[$pos]}" -eq 1 ]; then
      local metric_info=(${available_metrics[$i]//:/ })
      SELECTED_METRICS+=("${metric_info[0]}")
    fi
  done
  
  # If nothing selected, default to CPU and RAM
  if [ ${#SELECTED_METRICS[@]} -eq 0 ]; then
    echo -e "${YELLOW}No metrics selected. Defaulting to CPU and RAM usage.${RESET}"
    SELECTED_METRICS=("cpu_usage" "ram_usage")
  else
    echo -e "${GREEN}Selected metrics:${RESET} ${SELECTED_METRICS[*]}"
  fi
  echo ""
}

# Alternative selection method if the checkbox UI doesn't work
select_metrics_simple() {
  echo -e "${BLUE}${BOLD}Available metrics to monitor:${RESET}"
  echo ""
  
  for i in "${!available_metrics[@]}"; do
    IFS=':' read -r id name description <<< "${available_metrics[$i]}"
    echo -e "  ${BOLD}$((i+1)).${RESET} $name"
    echo -e "     ${YELLOW}$description${RESET}"
  done
  
  echo ""
  echo -e "  ${BOLD}A.${RESET} ${GREEN}Select ALL metrics${RESET}"
  echo ""
  echo -e "${YELLOW}Enter the numbers of metrics you want to collect, separated by spaces.${RESET}"
  echo -e "Note: The number of metrics should not exceed your telemetry harbor's max batch size."
  read -p "Metrics to collect (e.g., '1 3 5 7' or 'A' for all): " METRICS_INPUT
  
  # Check if user wants all metrics
  if [[ "$METRICS_INPUT" == "A" || "$METRICS_INPUT" == "a" ]]; then
    for i in "${!available_metrics[@]}"; do
      IFS=':' read -r id name description <<< "${available_metrics[$i]}"
      SELECTED_METRICS+=("$id")
    done
    echo -e "${GREEN}Selected ALL metrics.${RESET}"
    return
  fi
  
  # Convert input to array
  IFS=' ' read -r -a selected_indices <<< "$METRICS_INPUT"
  
  for index in "${selected_indices[@]}"; do
    if [[ $index =~ ^[0-9]+$ ]] && [ "$index" -ge 1 ] && [ "$index" -le "${#available_metrics[@]}" ]; then
      IFS=':' read -r id name description <<< "${available_metrics[$((index-1))]}"
      SELECTED_METRICS+=("$id")
    fi
  done
  
  if [ ${#SELECTED_METRICS[@]} -eq 0 ]; then
    echo -e "${YELLOW}No valid metrics selected. Defaulting to CPU and RAM usage.${RESET}"
    SELECTED_METRICS=("cpu_usage" "ram_usage")
  else
    echo -e "${GREEN}Selected metrics:${RESET} ${SELECTED_METRICS[*]}"
  fi
  echo ""
}

# Main menu function
main_menu() {
  display_intro
  
  echo -e "${BLUE}${BOLD}What would you like to do?${RESET}"
  echo -e "  ${BOLD}1.${RESET} Install Harbor Monitor"
  echo -e "  ${BOLD}2.${RESET} Uninstall Harbor Monitor"
  echo -e "  ${BOLD}3.${RESET} Exit"
  echo ""
  
  read -p "Enter your choice (1-3): " MAIN_CHOICE
  
  case $MAIN_CHOICE in
    1)
      # Check if already installed
      check_installation
      install_monitor
      ;;
    2)
      uninstall
      ;;
    3)
      echo -e "${YELLOW}Exiting...${RESET}"
      exit 0
      ;;
    *)
      echo -e "${RED}Invalid choice. Exiting.${RESET}"
      exit 1
      ;;
  esac
}

# Install function
install_monitor() {
  clear
  display_intro
  
  # API endpoint configuration
  echo -e "${BLUE}${BOLD}API Configuration:${RESET}"
  read -p "Enter telemetry batch API endpoint URL: " API_ENDPOINT
  read -p "Enter API key: " API_KEY
  
  # Sampling rate configuration
  echo ""
  echo -e "${BLUE}${BOLD}Select sampling rate:${RESET}"
  echo -e "  ${BOLD}1.${RESET} Every 1 second"
  echo -e "  ${BOLD}2.${RESET} Every 5 seconds"
  echo -e "  ${BOLD}3.${RESET} Every 30 seconds"
  echo -e "  ${BOLD}4.${RESET} Every 1 minute"
  echo -e "  ${BOLD}5.${RESET} Every 5 minutes"
  read -p "Enter your choice (1-5): " RATE_CHOICE
  
  case $RATE_CHOICE in
    1) SAMPLING_RATE=1 ;;
    2) SAMPLING_RATE=5 ;;
    3) SAMPLING_RATE=30 ;;
    4) SAMPLING_RATE=60 ;;
    5) SAMPLING_RATE=300 ;;
    *) 
      echo -e "${YELLOW}Invalid choice. Defaulting to 60 seconds.${RESET}"
      SAMPLING_RATE=60
      ;;
  esac
  
  # Metric selection
  echo ""
  echo -e "${BLUE}${BOLD}Metric Selection:${RESET}"
  declare -a SELECTED_METRICS=()
  
  # Ask user which selection method to use
  echo -e "How would you like to select metrics?"
  echo -e "  ${BOLD}1.${RESET} Interactive checkbox menu (use arrow keys and space)"
  echo -e "  ${BOLD}2.${RESET} Simple number entry"
  read -p "Enter your choice (1-2): " SELECTION_METHOD
  
  if [ "$SELECTION_METHOD" = "1" ]; then
    select_metrics_with_checkboxes
  else
    select_metrics_simple
  fi
  
  echo -e "${YELLOW}Creating monitoring script...${RESET}"
  
  # Create the monitoring script
cat > /usr/local/bin/harbor-monitor.sh << 'EOF'
#!/bin/bash

# Configuration will be injected here
API_ENDPOINT="__API_ENDPOINT__"
API_KEY="__API_KEY__"
SAMPLING_RATE=__SAMPLING_RATE__
SELECTED_METRICS=(__SELECTED_METRICS__)

# Get hostname for ship_id
HOSTNAME=$(hostname)

# Function to collect CPU usage - more reliable method without sed
get_cpu_usage() {
  # Use awk directly instead of sed to avoid errors
  top -bn1 | grep "Cpu(s)" | awk '{print 100.0-$8}'
}

# Function to collect individual CPU core usage - improved reliability
get_cpu_cores() {
  # Get number of cores
  local num_cores=$(nproc)
  local core_data="{"
  
  # Get usage for each core - more reliable method
  for ((i=0; i<num_cores; i++)); do
    # Try mpstat first, fall back to /proc/stat if not available
    if command -v mpstat >/dev/null 2>&1; then
      local usage=$(mpstat -P $i 1 1 2>/dev/null | awk '/Average:/ {print 100-$NF}' || echo 0)
    else
      # Alternative method using /proc/stat
      local cpu_line=$(grep -E "^cpu$i " /proc/stat)
      if [ -n "$cpu_line" ]; then
        local cpu_values=($(echo $cpu_line | awk '{print $2, $3, $4, $5}'))
        local user=${cpu_values[0]}
        local nice=${cpu_values[1]}
        local system=${cpu_values[2]}
        local idle=${cpu_values[3]}
        local total=$((user + nice + system + idle))
        if [ $total -gt 0 ]; then
          local usage=$(echo "scale=2; 100 - ($idle * 100 / $total)" | bc)
        else
          local usage="0.0"
        fi
      else
        local usage="0.0"
      fi
    fi
    core_data+="\"core$i\":$usage,"
  done
  
  # Remove trailing comma and close JSON
  core_data=${core_data%,}
  core_data+="}"
  
  echo "$core_data"
}

# Function to collect RAM usage - more accurate calculation
get_ram_usage() {
  # More accurate calculation that accounts for cached memory
  free | grep Mem | awk '{printf "%.2f", ($2-$7)/$2 * 100.0}'
}

# Function to collect detailed memory stats - add proper formatting
get_ram_detailed() {
  local total=$(free | grep Mem | awk '{print $2}')
  local used=$(free | grep Mem | awk '{print $3}')
  local free=$(free | grep Mem | awk '{print $4}')
  local shared=$(free | grep Mem | awk '{print $5}')
  local buffers=$(free | grep Mem | awk '{print $6}')
  local cached=$(free | grep Mem | awk '{print $7}')
  local available=$(free | grep Mem | awk '{print $7}')
  
  # Add actual available memory if present in newer versions of free
  if free | grep -q "available"; then
    available=$(free | grep Mem | awk '{print $7}')
  fi
  
  echo "{\"total\":$total,\"used\":$used,\"free\":$free,\"shared\":$shared,\"buffers\":$buffers,\"cached\":$cached,\"available\":$available}"
}

# Function to collect disk usage - more accurate with proper formatting
get_disk_usage() {
  df -P / | grep / | awk '{printf "%.2f", $5+0}'
}

# Function to collect all mounted partitions usage - improved formatting
get_disk_all() {
  local result="{"
  local partitions=$(df -P | grep '^/dev/' | awk '{print $6}')
  
  for partition in $partitions; do
    local usage=$(df -P "$partition" | grep "$partition" | awk '{printf "%.2f", $5+0}')
    # Replace / with _ in partition name for valid JSON
    local safe_name=$(echo "$partition" | tr '/' '_')
    result+="\"$safe_name\":$usage,"
  done
  
  # Remove trailing comma and close JSON
  result=${result%,}
  result+="}"
  
  echo "$result"
}

# Function to collect load average values - ensure they return floating point values
get_load_average_1m() {
  cat /proc/loadavg | awk '{printf "%.6f", $1}'
}

get_load_average_5m() {
  cat /proc/loadavg | awk '{printf "%.6f", $2}'
}

get_load_average_15m() {
  cat /proc/loadavg | awk '{printf "%.6f", $3}'
}

# Function to count processes
get_processes() {
  ps aux | wc -l | awk '{printf "%.1f", $1}'
}

# Function to count zombie processes
get_zombie_processes() {
  ps aux | grep -c 'Z' | awk '{printf "%.1f", $1}'
}

# Function to collect network errors and dropped packets - improved formatting
get_network_errors() {
  local interface=$(ip route | grep default | awk '{print $5}' | head -n1)
  if [ -z "$interface" ]; then
    interface="eth0"
  fi
  
  if [ -f "/proc/net/dev" ]; then
    local stats=$(grep "$interface:" /proc/net/dev)
    local rx_errors=$(echo $stats | awk '{printf "%.1f", $3+0}')
    local rx_dropped=$(echo $stats | awk '{printf "%.1f", $4+0}')
    local tx_errors=$(echo $stats | awk '{printf "%.1f", $11+0}')
    local tx_dropped=$(echo $stats | awk '{printf "%.1f", $12+0}')
    
    echo "{\"rx_errors\":$rx_errors,\"rx_dropped\":$rx_dropped,\"tx_errors\":$tx_errors,\"tx_dropped\":$tx_dropped}"
  else
    echo "{\"rx_errors\":0.0,\"rx_dropped\":0.0,\"tx_errors\":0.0,\"tx_dropped\":0.0}"
  fi
}

# Function to get CPU temperature - more reliable with fallbacks
get_temperature() {
  # Try multiple temperature sources
  if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    # Most common location, divide by 1000 to get degrees C
    echo $(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp)
  elif [ -f /sys/class/hwmon/hwmon0/temp1_input ]; then
    # Alternative location
    echo $(awk '{printf "%.1f", $1/1000}' /sys/class/hwmon/hwmon0/temp1_input)
  elif command -v sensors >/dev/null 2>&1; then
    # Try using lm-sensors if available
    sensors | grep -i "core 0" | awk '{printf "%.1f", $3}' | tr -d '°C+' || echo "0.0"
  else
    echo "0.0"
  fi
}

# Function to get uptime in seconds - ensure it returns a floating point value
get_uptime() {
  cat /proc/uptime | awk '{printf "%.2f", $1}'
}

# Function to get swap usage - ensure it returns a floating point value
get_swap_usage() {
  free | grep Swap | awk '{if ($2 > 0) printf "%.2f", $3/$2 * 100.0; else print "0.0"}'
}

# Function to get open file descriptors
get_open_files() {
  if command -v lsof >/dev/null 2>&1; then
    lsof 2>/dev/null | wc -l | awk '{printf "%.1f", $1}' || echo "0.0"
  else
    echo "0.0"
  fi
}

# Function to get TCP connection count
get_tcp_connections() {
  if command -v netstat >/dev/null 2>&1; then
    netstat -ant 2>/dev/null | grep ESTABLISHED | wc -l | awk '{printf "%.1f", $1}' || echo "0.0"
  elif command -v ss >/dev/null 2>&1; then
    ss -t state established 2>/dev/null | wc -l | awk '{printf "%.1f", ($1 > 1) ? $1-1 : 0}' || echo "0.0"
  else
    echo "0.0"
  fi
}

# Function to get UDP connection count
get_udp_connections() {
  if command -v netstat >/dev/null 2>&1; then
    netstat -anu 2>/dev/null | grep -v "^Active" | wc -l | awk '{printf "%.1f", $1}' || echo "0.0"
  elif command -v ss >/dev/null 2>&1; then
    ss -u 2>/dev/null | wc -l | awk '{printf "%.1f", ($1 > 1) ? $1-1 : 0}' || echo "0.0"
  else
    echo "0.0"
  fi
}

# Function to get logged in users count
get_logged_users() {
  who | wc -l | awk '{printf "%.1f", $1}'
}

# Function to get system entropy
get_entropy() {
  if [ -f /proc/sys/kernel/random/entropy_avail ]; then
    cat /proc/sys/kernel/random/entropy_avail | awk '{printf "%.1f", $1}'
  else
    echo "0.0"
  fi
}

# Variables for context switches and interrupts
CONTEXT_SWITCHES_PREV=0
INTERRUPTS_PREV=0
STAT_TIMESTAMP_PREV=0

# Function to get context switches per second
get_context_switches() {
  if [ -f /proc/stat ]; then
    local ctxt=$(grep "ctxt" /proc/stat | awk '{print $2}')
    local timestamp=$(date +%s)
    
    if [ $STAT_TIMESTAMP_PREV -ne 0 ]; then
      local time_diff=$((timestamp - STAT_TIMESTAMP_PREV))
      if [ $time_diff -gt 0 ]; then
        local rate=$(( (ctxt - CONTEXT_SWITCHES_PREV) / time_diff ))
        CONTEXT_SWITCHES_PREV=$ctxt
        echo $(printf "%.2f" $rate)
      else
        echo "0.0"
      fi
    else
      CONTEXT_SWITCHES_PREV=$ctxt
      echo "0.0"
    fi
    
    STAT_TIMESTAMP_PREV=$timestamp
  else
    echo "0.0"
  fi
}

# Function to get interrupts per second
get_interrupts() {
  if [ -f /proc/stat ]; then
    local intr=$(grep "intr" /proc/stat | awk '{print $2}')
    local timestamp=$(date +%s)
    
    if [ $STAT_TIMESTAMP_PREV -ne 0 ]; then
      local time_diff=$((timestamp - STAT_TIMESTAMP_PREV))
      if [ $time_diff -gt 0 ]; then
        local rate=$(( (intr - INTERRUPTS_PREV) / time_diff ))
        INTERRUPTS_PREV=$intr
        echo $(printf "%.2f" $rate)
      else
        echo "0.0"
      fi
    else
      INTERRUPTS_PREV=$intr
      echo "0.0"
    fi
    
    STAT_TIMESTAMP_PREV=$timestamp
  else
    echo "0.0"
  fi
}

# Variables for network monitoring
NETWORK_RX_PREV=0
NETWORK_TX_PREV=0
TIMESTAMP_PREV=0

# Update network stats processing
get_network_stats() {
  local interface=$(ip route | grep default | awk '{print $5}' | head -n1)
  if [ -z "$interface" ]; then
    interface="eth0"
  fi
  
  if [ -f "/proc/net/dev" ]; then
    local stats=$(grep "$interface:" /proc/net/dev | awk '{print $2, $10}')
    local rx=$(echo $stats | awk '{print $1}')
    local tx=$(echo $stats | awk '{print $2}')
    local timestamp=$(date +%s)
    
    if [ $TIMESTAMP_PREV -ne 0 ]; then
      local time_diff=$((timestamp - TIMESTAMP_PREV))
      if [ $time_diff -gt 0 ]; then
        # Use bc for floating point division if available
        if command -v bc >/dev/null 2>&1; then
          NETWORK_IN=$(echo "scale=2; ($rx - $NETWORK_RX_PREV) / $time_diff" | bc)
          NETWORK_OUT=$(echo "scale=2; ($tx - $NETWORK_TX_PREV) / $time_diff" | bc)
        else
          # Fallback to awk
          NETWORK_IN=$(awk -v rx="$rx" -v prev="$NETWORK_RX_PREV" -v td="$time_diff" 'BEGIN {printf "%.2f", (rx-prev)/td}')
          NETWORK_OUT=$(awk -v tx="$tx" -v prev="$NETWORK_TX_PREV" -v td="$time_diff" 'BEGIN {printf "%.2f", (tx-prev)/td}')
        fi
      else
        NETWORK_IN="0.0"
        NETWORK_OUT="0.0"
      fi
    else
      NETWORK_IN="0.0"
      NETWORK_OUT="0.0"
    fi
    
    NETWORK_RX_PREV=$rx
    NETWORK_TX_PREV=$tx
    TIMESTAMP_PREV=$timestamp
  else
    NETWORK_IN="0.0"
    NETWORK_OUT="0.0"
  fi
}

# Variables for disk I/O monitoring
DISK_READ_PREV=0
DISK_WRITE_PREV=0
DISK_IO_TIMESTAMP_PREV=0

# Update disk I/O stats processing
get_disk_io_stats() {
  # Try to find the root disk more reliably
  local disk=$(lsblk -no NAME,MOUNTPOINT 2>/dev/null | grep " /$" | cut -d' ' -f1 | head -n1)
  if [ -z "$disk" ]; then
    # Try alternative methods
    if [ -e "/dev/sda" ]; then
      disk="sda"
    elif [ -e "/dev/vda" ]; then
      disk="vda"
    elif [ -e "/dev/xvda" ]; then
      disk="xvda"
    else
      # Find first block device
      disk=$(lsblk -no NAME | head -n1)
    fi
  fi
  
  if [ -f "/sys/block/$disk/stat" ]; then
    local stats=$(cat "/sys/block/$disk/stat")
    local reads=$(echo $stats | awk '{print $1}')
    local writes=$(echo $stats | awk '{print $5}')
    local timestamp=$(date +%s)
    
    if [ $DISK_IO_TIMESTAMP_PREV -ne 0 ]; then
      local time_diff=$((timestamp - DISK_IO_TIMESTAMP_PREV))
      if [ $time_diff -gt 0 ]; then
        # Use bc for floating point division if available
        if command -v bc >/dev/null 2>&1; then
          DISK_IO=$(echo "scale=2; ($reads - $DISK_READ_PREV + $writes - $DISK_WRITE_PREV) / $time_diff" | bc)
          DISK_READ=$(echo "scale=2; ($reads - $DISK_READ_PREV) / $time_diff" | bc)
          DISK_WRITE=$(echo "scale=2; ($writes - $DISK_WRITE_PREV) / $time_diff" | bc)
        else
          # Fallback to awk
          DISK_IO=$(awk -v r="$reads" -v rp="$DISK_READ_PREV" -v w="$writes" -v wp="$DISK_WRITE_PREV" -v td="$time_diff" 'BEGIN {printf "%.2f", (r-rp+w-wp)/td}')
          DISK_READ=$(awk -v r="$reads" -v rp="$DISK_READ_PREV" -v td="$time_diff" 'BEGIN {printf "%.2f", (r-rp)/td}')
          DISK_WRITE=$(awk -v w="$writes" -v wp="$DISK_WRITE_PREV" -v td="$time_diff" 'BEGIN {printf "%.2f", (w-wp)/td}')
        fi
      else
        DISK_IO="0.0"
        DISK_READ="0.0"
        DISK_WRITE="0.0"
      fi
    else
      DISK_IO="0.0"
      DISK_READ="0.0"
      DISK_WRITE="0.0"
    fi
    
    DISK_READ_PREV=$reads
    DISK_WRITE_PREV=$writes
    DISK_IO_TIMESTAMP_PREV=$timestamp
  else
    DISK_IO="0.0"
    DISK_READ="0.0"
    DISK_WRITE="0.0"
  fi
}

# Function to test all metrics before sending
test_metrics() {
  local failed_metrics=()
  local json_data="["
  
  echo "Testing selected metrics..."
  
  # Test each selected metric
  for metric in "${SELECTED_METRICS[@]}"; do
    echo -n "Testing $metric... "
    
    # Try to collect the metric
    case $metric in
      cpu_usage)
        value=$(get_cpu_usage 2>/dev/null) || value="error"
        ;;
      ram_usage)
        value=$(get_ram_usage 2>/dev/null) || value="error"
        ;;
      disk_usage)
        value=$(get_disk_usage 2>/dev/null) || value="error"
        ;;
      load_average_1m)
        value=$(get_load_average_1m 2>/dev/null) || value="error"
        ;;
      load_average_5m)
        value=$(get_load_average_5m 2>/dev/null) || value="error"
        ;;
      load_average_15m)
        value=$(get_load_average_15m 2>/dev/null) || value="error"
        ;;
      processes)
        value=$(get_processes 2>/dev/null) || value="error"
        ;;
      zombie_processes)
        value=$(get_zombie_processes 2>/dev/null) || value="error"
        ;;
      network_in)
        get_network_stats 2>/dev/null
        value=$NETWORK_IN
        ;;
      network_out)
        get_network_stats 2>/dev/null
        value=$NETWORK_OUT
        ;;
      temperature)
        value=$(get_temperature 2>/dev/null) || value="error"
        ;;
      uptime)
        value=$(get_uptime 2>/dev/null) || value="error"
        ;;
      swap_usage)
        value=$(get_swap_usage 2>/dev/null) || value="error"
        ;;
      disk_io)
        get_disk_io_stats 2>/dev/null
        value=$DISK_IO
        ;;
      disk_read)
        get_disk_io_stats 2>/dev/null
        value=$DISK_READ
        ;;
      disk_write)
        get_disk_io_stats 2>/dev/null
        value=$DISK_WRITE
        ;;
      open_files)
        value=$(get_open_files 2>/dev/null) || value="error"
        ;;
      tcp_connections)
        value=$(get_tcp_connections 2>/dev/null) || value="error"
        ;;
      udp_connections)
        value=$(get_udp_connections 2>/dev/null) || value="error"
        ;;
      logged_users)
        value=$(get_logged_users 2>/dev/null) || value="error"
        ;;
      entropy)
        value=$(get_entropy 2>/dev/null) || value="error"
        ;;
      context_switches)
        value=$(get_context_switches 2>/dev/null) || value="error"
        ;;
      interrupts)
        value=$(get_interrupts 2>/dev/null) || value="error"
        ;;
      *)
        value="error"
        ;;
    esac
    
    # Check if the metric was collected successfully
    if [ "$value" = "error" ]; then
      echo "FAILED"
      failed_metrics+=("$metric")
    else
      echo "OK"
      
      # Ensure numeric values are properly formatted
      if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        value="0.0"
      fi
      
      # Add to test JSON
      json_data+="{\"time\":\"$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")\",\"ship_id\":\"$HOSTNAME\",\"cargo_id\":\"$metric\",\"value\":$value},"
    fi
  done
  
  # Remove trailing comma and close JSON array
  json_data=${json_data%,}
  json_data+="]"
  
  # Return results
  if [ ${#failed_metrics[@]} -gt 0 ]; then
    echo "The following metrics failed to collect: ${failed_metrics[*]}"
    return 1
  else
    echo "All metrics collected successfully!"
    echo "$json_data" > /tmp/test_metrics.json
    return 0
  fi
}

# Function to send metrics to the API
send_metrics() {
  local json="$1"
  
  # Debug: Print the payload being sent with clear formatting
  echo "DEBUG - Sending payload:"
  echo "$json" | jq . || echo "$json"
  
  # Send data to telemetry endpoint and capture response
  # Using X-API-Key header for authentication
  local response=$(curl -s -w "\n%{http_code}" -X POST "$API_ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d "$json")
  
  # Extract HTTP status code
  local status_code=$(echo "$response" | tail -n1)
  
  # Debug: Print the response
  echo "DEBUG - Response (HTTP $status_code):"
  echo "$(echo "$response" | head -n -1)"
  
  # Log if there's an error
  if [ "$status_code" != "200" ]; then
    echo "Error sending metrics: HTTP $status_code" >&2
    echo "Response: $(echo "$response" | head -n -1)" >&2
    return 1
  fi
  
  return 0
}

# Check for command line arguments - AFTER all functions are defined
if [ "$1" = "test_metrics" ]; then
  # Only run the test_metrics function and exit
  test_metrics
  exit $?
fi

# Main monitoring loop
while true; do
  # Get current timestamp in ISO format
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
  
  # Update network stats
  get_network_stats
  
  # Update disk I/O stats
  get_disk_io_stats
  
  # Prepare JSON payload
  JSON="["
  
  # Add metrics based on selection
  for metric in "${SELECTED_METRICS[@]}"; do
    # Get the value based on the metric type
    case $metric in
      cpu_usage)
        raw_value=$(get_cpu_usage)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      ram_usage)
        raw_value=$(get_ram_usage)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      disk_usage)
        raw_value=$(get_disk_usage)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      load_average_1m)
        raw_value=$(get_load_average_1m)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      load_average_5m)
        raw_value=$(get_load_average_5m)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      load_average_15m)
        raw_value=$(get_load_average_15m)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      processes)
        raw_value=$(get_processes)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      zombie_processes)
        raw_value=$(get_zombie_processes)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      network_in)
        # Ensure it's a valid number
        if [[ "$NETWORK_IN" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$NETWORK_IN"
        else
          value="0.0"
        fi
        ;;
      network_out)
        # Ensure it's a valid number
        if [[ "$NETWORK_OUT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$NETWORK_OUT"
        else
          value="0.0"
        fi
        ;;
      temperature)
        raw_value=$(get_temperature)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      uptime)
        raw_value=$(get_uptime)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      swap_usage)
        raw_value=$(get_swap_usage)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      disk_io)
        # Ensure it's a valid number
        if [[ "$DISK_IO" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$DISK_IO"
        else
          value="0.0"
        fi
        ;;
      disk_read)
        # Ensure it's a valid number
        if [[ "$DISK_READ" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$DISK_READ"
        else
          value="0.0"
        fi
        ;;
      disk_write)
        # Ensure it's a valid number
        if [[ "$DISK_WRITE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$DISK_WRITE"
        else
          value="0.0"
        fi
        ;;
      open_files)
        raw_value=$(get_open_files)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      tcp_connections)
        raw_value=$(get_tcp_connections)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      udp_connections)
        raw_value=$(get_udp_connections)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      logged_users)
        raw_value=$(get_logged_users)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      entropy)
        raw_value=$(get_entropy)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      context_switches)
        raw_value=$(get_context_switches)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      interrupts)
        raw_value=$(get_interrupts)
        # Ensure it's a valid number
        if [[ "$raw_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          value="$raw_value"
        else
          value="0.0"
        fi
        ;;
      *)
        value="0.0"
        ;;
    esac
    
    # Add to JSON payload
    JSON+="{ \"time\": \"$TIMESTAMP\", \"ship_id\": \"$HOSTNAME\", \"cargo_id\": \"$metric\", \"value\": $value },"
  done

  # Remove trailing comma and close JSON array
  JSON=${JSON%,}
  JSON+="]"
  
  # Send data to telemetry endpoint
  send_metrics "$JSON"
  
  # Wait for next sampling interval
  sleep $SAMPLING_RATE
done
EOF

# Replace placeholders with actual values
sed -i "s|__API_ENDPOINT__|$API_ENDPOINT|g" /usr/local/bin/harbor-monitor.sh
sed -i "s|__API_KEY__|$API_KEY|g" /usr/local/bin/harbor-monitor.sh
sed -i "s|__SAMPLING_RATE__|$SAMPLING_RATE|g" /usr/local/bin/harbor-monitor.sh

# Convert selected metrics array to bash array string
METRICS_STRING=$(printf "\"%s\" " "${SELECTED_METRICS[@]}")
sed -i "s|__SELECTED_METRICS__|$METRICS_STRING|g" /usr/local/bin/harbor-monitor.sh

# Make the script executable
chmod +x /usr/local/bin/harbor-monitor.sh

# Create systemd service file
cat > /etc/systemd/system/harbor-monitor.service << EOF
[Unit]
Description=Telemetry Harbor Monitor
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/harbor-monitor.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Test all metrics before sending to API
echo -e "${YELLOW}Testing all selected metrics before installation...${RESET}"
/usr/local/bin/harbor-monitor.sh test_metrics

# Check the return code from the test_metrics function
TEST_RESULT=$?
if [ $TEST_RESULT -ne 0 ]; then
  echo -e "${YELLOW}Some metrics failed to collect. Continuing with installation anyway.${RESET}"
  echo -e "${YELLOW}You may want to check the logs after installation for more details.${RESET}"
fi

# Send a test data point to verify connectivity
echo -e "${YELLOW}Sending test data point to verify API connectivity...${RESET}"

# Get hostname
HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

# Create test JSON payload
TEST_JSON="[{\"time\": \"$TIMESTAMP\", \"ship_id\": \"$HOSTNAME\", \"cargo_id\": \"test\", \"value\": 1.0}]"

# Send test data with X-API-Key header
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_ENDPOINT" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d "$TEST_JSON")

# Extract HTTP status code
STATUS_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$STATUS_CODE" = "200" ]; then
  echo -e "${GREEN}Test data point sent successfully! API returned HTTP 200.${RESET}"
  
  # Enable and start the service
  systemctl daemon-reload
  systemctl enable harbor-monitor.service
  systemctl start harbor-monitor.service
  
  echo ""
  echo -e "${GREEN}${BOLD}=== Installation Complete ===${RESET}"
  echo -e "${GREEN}Harbor Monitor has been installed and started.${RESET}"
  echo -e "${YELLOW}Monitoring the following metrics:${RESET} ${SELECTED_METRICS[*]}"
  echo -e "${YELLOW}Sampling rate:${RESET} Every $SAMPLING_RATE seconds"
  echo ""
  echo -e "${BLUE}To check service status:${RESET} systemctl status harbor-monitor"
  echo -e "${BLUE}To view logs:${RESET} journalctl -u harbor-monitor -f"
  echo -e "${BLUE}To manage the service:${RESET} Run this script again and select from the menu"
else
  echo -e "${RED}Error: Failed to send test data point. API returned HTTP $STATUS_CODE${RESET}"
  echo -e "${RED}Response: $RESPONSE_BODY${RESET}"
  echo ""
  echo -e "${YELLOW}Please check your API endpoint and key, then try again.${RESET}"
  echo -e "${YELLOW}The service has not been started due to this error.${RESET}"
  exit 1
fi
}

# Run the main menu
main_menu

