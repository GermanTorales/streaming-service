#!/bin/bash

# =============================================================================
# VPN Services Monitor Script
# Monitors Gluetun and Transmission services, VPN status, and network metrics
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration - Adjust these variables according to your setup
GLUETUN_CONTAINER="gluetun"           # Docker container name for Gluetun
TRANSMISSION_CONTAINER="transmission" # Docker container name for Transmission
TRANSMISSION_HOST="localhost"
TRANSMISSION_PORT="9091"
TRANSMISSION_USER="" # Leave empty if no auth
TRANSMISSION_PASS="" # Leave empty if no auth
SPEEDTEST_SERVER=""  # Leave empty for auto-select, or specify server ID

# Check if running as root (some commands might need it)
if [ "$EUID" -eq 0 ]; then
  echo -e "${YELLOW}Note: Running as root${NC}"
fi

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
  echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}  $1${NC}"
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_status() {
  local label="$1"
  local value="$2"
  local status="$3"

  if [ "$status" = "ok" ]; then
    echo -e "${GREEN}✓${NC} ${BOLD}$label:${NC} $value"
  elif [ "$status" = "error" ]; then
    echo -e "${RED}✗${NC} ${BOLD}$label:${NC} $value"
  elif [ "$status" = "warning" ]; then
    echo -e "${YELLOW}⚠${NC} ${BOLD}$label:${NC} $value"
  else
    echo -e "  ${BOLD}$label:${NC} $value"
  fi
}

check_command() {
  if ! command -v "$1" &>/dev/null; then
    echo -e "${RED}Error: $1 is not installed${NC}"
    return 1
  fi
  return 0
}

# =============================================================================
# Service Status Functions
# =============================================================================

check_docker_service() {
  local container_name="$1"

  if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    local status=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
    local health=$(docker inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")

    if [ "$health" = "healthy" ]; then
      print_status "Status" "Running (Healthy)" "ok"
    elif [ "$health" = "unhealthy" ]; then
      print_status "Status" "Running (Unhealthy)" "warning"
    elif [ "$status" = "running" ]; then
      print_status "Status" "Running" "ok"
    else
      print_status "Status" "$status" "warning"
    fi

    # Get container uptime
    local started=$(docker inspect -f '{{.State.StartedAt}}' "$container_name" 2>/dev/null)
    if [ ! -z "$started" ]; then
      local uptime=$(docker inspect -f '{{.State.StartedAt}}' "$container_name" | xargs -I {} date -d {} +%s)
      local now=$(date +%s)
      local diff=$((now - uptime))
      local days=$((diff / 86400))
      local hours=$(((diff % 86400) / 3600))
      local mins=$(((diff % 3600) / 60))
      print_status "Uptime" "${days}d ${hours}h ${mins}m" ""
    fi

    return 0
  else
    print_status "Status" "Not Running" "error"
    return 1
  fi
}

# =============================================================================
# IP and Location Functions
# =============================================================================

get_ip_info() {
  local container="$1"
  local is_vpn="$2"

  if [ "$is_vpn" = "true" ] && [ ! -z "$container" ]; then
    # Get IP through docker container
    local ip_data=$(docker exec "$container" wget -qO- "https://ipapi.co/json/" 2>/dev/null ||
      docker exec "$container" curl -s "https://ipapi.co/json/" 2>/dev/null)
  else
    # Get IP directly
    local ip_data=$(curl -s "https://ipapi.co/json/" 2>/dev/null || wget -qO- "https://ipapi.co/json/" 2>/dev/null)
  fi

  if [ ! -z "$ip_data" ]; then
    local ip=$(echo "$ip_data" | grep -oP '"ip"\s*:\s*"\K[^"]+')
    local country=$(echo "$ip_data" | grep -oP '"country_name"\s*:\s*"\K[^"]+')
    local city=$(echo "$ip_data" | grep -oP '"city"\s*:\s*"\K[^"]+')
    local isp=$(echo "$ip_data" | grep -oP '"org"\s*:\s*"\K[^"]+')
    local asn=$(echo "$ip_data" | grep -oP '"asn"\s*:\s*"\K[^"]+')

    print_status "IP Address" "$ip" "ok"
    print_status "Country" "$country" ""
    print_status "City" "$city" ""
    print_status "ISP/Provider" "$isp" ""
    print_status "ASN" "$asn" ""

    # Check for VPN/Proxy detection
    local vpn_check=$(curl -s "https://ipapi.co/$ip/json/" | grep -oP '"in_eu"\s*:\s*\K[^,]+')

    # DNS Leak Test
    if [ "$is_vpn" = "true" ]; then
      echo -e "\n  ${BOLD}DNS Servers:${NC}"
      if [ ! -z "$container" ]; then
        docker exec "$container" cat /etc/resolv.conf 2>/dev/null | grep nameserver | awk '{print "    - " $2}'
      else
        cat /etc/resolv.conf | grep nameserver | awk '{print "    - " $2}'
      fi
    fi

    return 0
  else
    print_status "IP Address" "Failed to retrieve" "error"
    return 1
  fi
}

# =============================================================================
# Port Forwarding Check
# =============================================================================

check_port_forwarding() {
  local container="$1"

  # Check Gluetun port forwarding status
  if [ ! -z "$container" ]; then
    local port=""

    # Method 1: Check for automated port forwarding file (ProtonVPN, PIA, etc.)
    local port_file="/tmp/gluetun/forwarded_port"
    port=$(docker exec "$container" cat "$port_file" 2>/dev/null)

    # Method 2: Check environment variables for manual port forwarding (AirVPN, Mullvad, etc.)
    if [ -z "$port" ]; then
      # Check FIREWALL_VPN_INPUT_PORTS environment variable
      port=$(docker exec "$container" printenv FIREWALL_VPN_INPUT_PORTS 2>/dev/null | tr -d ' ')

      # If multiple ports, take the first one
      if [ ! -z "$port" ] && echo "$port" | grep -q ","; then
        port=$(echo "$port" | cut -d',' -f1)
      fi
    fi

    # Method 3: Check docker-compose labels or inspect
    if [ -z "$port" ]; then
      # Try to get from docker inspect
      port=$(docker inspect "$container" --format '{{range $p, $conf := .Config.Env}}{{if eq (index (split $p "=") 0) "FIREWALL_VPN_INPUT_PORTS"}}{{index (split $p "=") 1}}{{end}}{{end}}' 2>/dev/null | tr -d ' ')
      if [ ! -z "$port" ] && echo "$port" | grep -q ","; then
        port=$(echo "$port" | cut -d',' -f1)
      fi
    fi

    # Method 4: Check iptables rules for forwarded ports
    if [ -z "$port" ]; then
      # Look for ACCEPT rules on specific ports in iptables
      local iptables_ports=$(docker exec "$container" iptables -L INPUT -n 2>/dev/null | grep "ACCEPT.*dpt:" | grep -oP 'dpt:\K[0-9]+' | head -1)
      if [ ! -z "$iptables_ports" ]; then
        port="$iptables_ports"
      fi
    fi

    if [ ! -z "$port" ]; then
      print_status "Forwarded Port" "$port" "ok"

      # Test if port is actually open from outside using multiple methods
      local external_ip=$(docker exec "$container" wget -qO- "https://ipapi.co/ip/" 2>/dev/null || docker exec "$container" curl -s "https://ipapi.co/ip/" 2>/dev/null)

      if [ ! -z "$external_ip" ]; then
        echo -e "\n  ${BOLD}Port Check Methods:${NC}"

        # Method 1: Direct netcat check
        local port_check=$(timeout 5 nc -zv "$external_ip" "$port" 2>&1)
        if echo "$port_check" | grep -q "succeeded\|open"; then
          print_status "  Direct Check" "Port $port is OPEN" "ok"
        else
          print_status "  Direct Check" "Port appears closed/filtered" "warning"
        fi

        # Method 2: Online port checker (alternative)
        echo -e "  ${BOLD}Testing with online port checker...${NC}"
        local online_check=$(curl -s "https://www.yougetsignal.com/tools/open-ports/php/check-port.php" \
          -d "remoteAddress=$external_ip&portNumber=$port" 2>/dev/null | grep -o '"status":[0-9]' | cut -d':' -f2)

        if [ "$online_check" = "1" ]; then
          print_status "  Online Check" "Port $port confirmed OPEN" "ok"
        elif [ "$online_check" = "0" ]; then
          print_status "  Online Check" "Port $port appears CLOSED" "error"
        else
          # Method 3: Using canyouseeme.org
          local canyouseeme=$(curl -s "https://canyouseeme.org/" \
            --data "port=$port&IP=$external_ip" 2>/dev/null)
          if echo "$canyouseeme" | grep -q "Success\|can see"; then
            print_status "  CanYouSeeMe" "Port $port is OPEN" "ok"
          else
            print_status "  CanYouSeeMe" "Cannot verify port status" "warning"
          fi
        fi
      fi
    else
      print_status "Port Forwarding" "Not detected - Check configuration" "warning"
      echo -e "${YELLOW}  Tip: For AirVPN, ensure FIREWALL_VPN_INPUT_PORTS is set${NC}"
      echo -e "${YELLOW}  Example: FIREWALL_VPN_INPUT_PORTS=12345${NC}"
    fi

    # Check if Transmission is using the correct port
    if [ ! -z "$port" ] && [ ! -z "$TRANSMISSION_CONTAINER" ]; then
      echo -e "\n  ${BOLD}Transmission Port Configuration:${NC}"

      # Get Transmission listening port
      local trans_port=""

      # Try multiple methods to get Transmission port
      # Method 1: transmission-remote
      trans_port=$(docker exec "$TRANSMISSION_CONTAINER" transmission-remote ${TRANSMISSION_HOST}:${TRANSMISSION_PORT} -n "$TRANSMISSION_USER:$TRANSMISSION_PASS" -si 2>/dev/null | grep -i "listenport\|peer port" | grep -oP '[0-9]+' | head -1)

      # Method 2: Check settings.json
      if [ -z "$trans_port" ]; then
        trans_port=$(docker exec "$TRANSMISSION_CONTAINER" grep '"peer-port"' /config/settings.json 2>/dev/null | grep -oP '[0-9]+')
      fi

      # Method 3: Check environment variable
      if [ -z "$trans_port" ]; then
        trans_port=$(docker exec "$TRANSMISSION_CONTAINER" printenv TRANSMISSION_PEER_PORT 2>/dev/null)
      fi

      if [ ! -z "$trans_port" ]; then
        if [ "$trans_port" = "$port" ]; then
          print_status "  Transmission Port" "Correctly configured ($trans_port)" "ok"
        else
          print_status "  Transmission Port" "MISMATCH! Using: $trans_port, Should be: $port" "error"
          echo -e "${RED}  ⚠ WARNING: Port mismatch will prevent seeding!${NC}"
          echo -e "${YELLOW}  Fix: Set Transmission peer-port to $port${NC}"
        fi
      else
        print_status "  Transmission Port" "Could not determine" "warning"
      fi

      # Check if port is actually listening inside container
      local listening=$(docker exec "$TRANSMISSION_CONTAINER" netstat -tuln 2>/dev/null | grep ":${trans_port:-$port} " | grep LISTEN)
      if [ ! -z "$listening" ]; then
        print_status "  Port Listening" "Yes (internal)" "ok"
      else
        print_status "  Port Listening" "Not detected" "warning"
      fi
    fi
  fi
}

# =============================================================================
# Network Performance Tests
# =============================================================================

test_network_performance() {
  local container="$1"

  print_header "NETWORK PERFORMANCE"

  # Ping tests to various servers
  echo -e "\n  ${BOLD}Latency Tests:${NC}"

  local servers=(
    "1.1.1.1:Cloudflare DNS"
    "8.8.8.8:Google DNS"
    "208.67.222.222:OpenDNS"
  )

  for server_info in "${servers[@]}"; do
    IFS=':' read -r server name <<<"$server_info"

    if [ ! -z "$container" ]; then
      local ping_result=$(docker exec "$container" ping -c 4 -W 2 "$server" 2>/dev/null | tail -1)
    else
      local ping_result=$(ping -c 4 -W 2 "$server" 2>/dev/null | tail -1)
    fi

    if [ ! -z "$ping_result" ]; then
      local avg_ping=$(echo "$ping_result" | awk -F'/' '{print $5}' | cut -d'.' -f1)
      if [ ! -z "$avg_ping" ]; then
        if [ "$avg_ping" -lt 50 ]; then
          print_status "  $name" "${avg_ping}ms" "ok"
        elif [ "$avg_ping" -lt 150 ]; then
          print_status "  $name" "${avg_ping}ms" "warning"
        else
          print_status "  $name" "${avg_ping}ms" "error"
        fi
      else
        print_status "  $name" "Unreachable" "error"
      fi
    else
      print_status "  $name" "Unreachable" "error"
    fi
  done

  # Bandwidth test (simple download test)
  echo -e "\n  ${BOLD}Bandwidth Test:${NC}"

  # Test with a small file download
  local test_url="https://speed.cloudflare.com/__down?bytes=10000000" # 10MB
  local start_time=$(date +%s%N)

  if [ ! -z "$container" ]; then
    docker exec "$container" wget -O /dev/null "$test_url" 2>&1 | grep -o '[0-9.]\+ [KMG]B/s' | tail -1 >/tmp/speed_result
  else
    wget -O /dev/null "$test_url" 2>&1 | grep -o '[0-9.]\+ [KMG]B/s' | tail -1 >/tmp/speed_result
  fi

  local speed_result=$(cat /tmp/speed_result 2>/dev/null)
  if [ ! -z "$speed_result" ]; then
    print_status "  Download Speed" "$speed_result" "ok"
  fi
  rm -f /tmp/speed_result

  # MTU check
  if [ ! -z "$container" ]; then
    local mtu=$(docker exec "$container" ip link show | grep -oP 'mtu \K[0-9]+' | head -1)
  else
    local mtu=$(ip link show | grep -oP 'mtu \K[0-9]+' | head -1)
  fi
  print_status "MTU Size" "$mtu" ""
}

# =============================================================================
# Transmission Status
# =============================================================================

check_transmission() {
  print_header "TRANSMISSION STATUS"

  if ! check_docker_service "$TRANSMISSION_CONTAINER"; then
    return 1
  fi

  # Debug: Check if transmission-remote is available
  if ! docker exec "$TRANSMISSION_CONTAINER" which transmission-remote &>/dev/null; then
    print_status "Error" "transmission-remote not found in container" "error"

    # Try alternative method using RPC directly
    echo -e "\n  ${BOLD}Trying RPC method:${NC}"

    # Get session ID for RPC
    local session_id=$(docker exec "$TRANSMISSION_CONTAINER" curl -s -I "http://localhost:${TRANSMISSION_PORT}/transmission/rpc" | grep "X-Transmission-Session-Id" | cut -d' ' -f2 | tr -d '\r')

    if [ ! -z "$session_id" ]; then
      # Get stats via RPC
      local rpc_stats=$(docker exec "$TRANSMISSION_CONTAINER" curl -s \
        -H "X-Transmission-Session-Id: ${session_id}" \
        -d '{"method":"session-stats"}' \
        "http://localhost:${TRANSMISSION_PORT}/transmission/rpc" 2>/dev/null)

      if [ ! -z "$rpc_stats" ]; then
        # Parse JSON response (basic parsing without jq)
        local active_count=$(echo "$rpc_stats" | grep -oP '"activeTorrentCount":\K[0-9]+')
        local download_speed=$(echo "$rpc_stats" | grep -oP '"downloadSpeed":\K[0-9]+')
        local upload_speed=$(echo "$rpc_stats" | grep -oP '"uploadSpeed":\K[0-9]+')
        local total_torrents=$(echo "$rpc_stats" | grep -oP '"torrentCount":\K[0-9]+')

        # Convert speeds to human readable
        if [ ! -z "$download_speed" ]; then
          download_speed=$(numfmt --to=iec-i --suffix=B/s "$download_speed" 2>/dev/null || echo "${download_speed} B/s")
        fi
        if [ ! -z "$upload_speed" ]; then
          upload_speed=$(numfmt --to=iec-i --suffix=B/s "$upload_speed" 2>/dev/null || echo "${upload_speed} B/s")
        fi

        print_status "Active Torrents" "${active_count:-0} / ${total_torrents:-0}" ""
        print_status "Download Speed" "${download_speed:-0 B/s}" ""
        print_status "Upload Speed" "${upload_speed:-0 B/s}" ""
      else
        print_status "RPC Connection" "Failed" "error"
      fi
    else
      print_status "Session ID" "Could not obtain" "error"
    fi

    return 1
  fi

  # Build authentication string
  local auth_string=""
  if [ ! -z "$TRANSMISSION_USER" ] && [ ! -z "$TRANSMISSION_PASS" ]; then
    auth_string="-n ${TRANSMISSION_USER}:${TRANSMISSION_PASS}"
  fi

  # First, test connection
  echo -e "\n  ${BOLD}Testing Transmission connection...${NC}"
  local test_conn=$(docker exec "$TRANSMISSION_CONTAINER" transmission-remote ${TRANSMISSION_HOST}:${TRANSMISSION_PORT} $auth_string -l 2>&1)

  if echo "$test_conn" | grep -q "Unauthorized\|401"; then
    print_status "Auth Status" "Failed - Check credentials" "error"
    echo -e "${YELLOW}  Tip: Set TRANSMISSION_USER and TRANSMISSION_PASS variables${NC}"
    return 1
  elif echo "$test_conn" | grep -q "Couldn't connect\|Connection refused"; then
    print_status "Connection" "Failed - Service may be down" "error"
    return 1
  fi

  # Get Transmission session stats
  local trans_stats=$(docker exec "$TRANSMISSION_CONTAINER" transmission-remote ${TRANSMISSION_HOST}:${TRANSMISSION_PORT} $auth_string -st 2>&1)

  if [ ! -z "$trans_stats" ] && ! echo "$trans_stats" | grep -q "Couldn't connect\|Unauthorized"; then
    # Parse statistics - Updated parsing for better compatibility
    local active=$(echo "$trans_stats" | grep -i "active" | head -1 | sed 's/.*Active:[[:space:]]*//' | awk '{print $1}')

    # Get download/upload speed - More flexible parsing
    local download_line=$(echo "$trans_stats" | grep -i "download speed")
    local upload_line=$(echo "$trans_stats" | grep -i "upload speed")

    if [ ! -z "$download_line" ]; then
      local download_speed=$(echo "$download_line" | sed 's/.*:[[:space:]]*//')
    else
      # Alternative: get from torrent list
      local torrent_list=$(docker exec "$TRANSMISSION_CONTAINER" transmission-remote ${TRANSMISSION_HOST}:${TRANSMISSION_PORT} $auth_string -l 2>/dev/null | tail -1)
      local download_speed=$(echo "$torrent_list" | awk '{print $(NF-1), $NF}' | grep -oE '[0-9.]+ [KMG]?B/s' | head -1)
    fi

    if [ ! -z "$upload_line" ]; then
      local upload_speed=$(echo "$upload_line" | sed 's/.*:[[:space:]]*//')
    else
      # Alternative: get from torrent list
      local upload_speed=$(echo "$torrent_list" | awk '{print $(NF)}' | grep -oE '[0-9.]+ [KMG]?B/s' | head -1)
    fi

    # Get torrent count
    local torrent_count=$(docker exec "$TRANSMISSION_CONTAINER" transmission-remote ${TRANSMISSION_HOST}:${TRANSMISSION_PORT} $auth_string -l 2>/dev/null | grep -c "^[[:space:]]*[0-9]")

    print_status "Active Torrents" "${active:-$torrent_count}" ""
    print_status "Download Speed" "${download_speed:-0.0 KB/s}" ""
    print_status "Upload Speed" "${upload_speed:-0.0 KB/s}" ""

    # Additional stats
    echo -e "\n  ${BOLD}Session Statistics:${NC}"
    local uploaded=$(echo "$trans_stats" | grep -i "uploaded" | head -1 | sed 's/.*:[[:space:]]*//')
    local downloaded=$(echo "$trans_stats" | grep -i "downloaded" | head -1 | sed 's/.*:[[:space:]]*//')
    local ratio=$(echo "$trans_stats" | grep -i "ratio" | head -1 | sed 's/.*:[[:space:]]*//')

    [ ! -z "$uploaded" ] && print_status "  Total Uploaded" "$uploaded" ""
    [ ! -z "$downloaded" ] && print_status "  Total Downloaded" "$downloaded" ""
    [ ! -z "$ratio" ] && print_status "  Overall Ratio" "$ratio" ""

  else
    print_status "Stats" "Unable to retrieve" "error"
    echo -e "${YELLOW}  Debug Output:${NC}"
    echo "$trans_stats" | head -5
  fi
}

# =============================================================================
# VPN Health Checks
# =============================================================================

check_vpn_health() {
  local container="$1"

  print_header "VPN HEALTH CHECKS"

  # Check for IP leaks
  echo -e "\n  ${BOLD}Leak Tests:${NC}"

  # WebRTC leak test would require a browser, so we check local IPs
  local local_ips=$(hostname -I 2>/dev/null)
  print_status "  Local IPs" "$local_ips" ""

  # Check kill switch
  if docker exec "$container" iptables -L 2>/dev/null | grep -q "DROP\|REJECT" &>/dev/null; then
    print_status "  Kill Switch" "Active" "ok"
  else
    print_status "  Kill Switch" "Not detected" "warning"
  fi

  # Check VPN protocol
  local vpn_protocol=$(docker exec "$container" printenv VPN_TYPE 2>/dev/null)
  if [ ! -z "$vpn_protocol" ]; then
    print_status "VPN Protocol" "$vpn_protocol" ""
  fi

  # Check VPN server
  local vpn_server=$(docker exec "$container" printenv SERVER_HOSTNAMES 2>/dev/null)
  if [ ! -z "$vpn_server" ]; then
    print_status "VPN Server" "$vpn_server" ""
  fi
}

# =============================================================================
# Main Execution
# =============================================================================

clear
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            VPN SERVICES MONITORING DASHBOARD                 ║"
echo "║                  $(date '+%Y-%m-%d %H:%M:%S')                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"
check_command "docker" || exit 1
check_command "curl" || check_command "wget" || exit 1
check_command "jq" &>/dev/null || echo -e "${YELLOW}Warning: jq not installed (optional)${NC}"

# Check System IP (without VPN)
print_header "SYSTEM IP (WITHOUT VPN)"
get_ip_info "" "false"

# Check Gluetun
print_header "GLUETUN VPN STATUS"
if check_docker_service "$GLUETUN_CONTAINER"; then
  echo ""
  get_ip_info "$GLUETUN_CONTAINER" "true"
  echo ""
  check_port_forwarding "$GLUETUN_CONTAINER"
  check_vpn_health "$GLUETUN_CONTAINER"
  test_network_performance "$GLUETUN_CONTAINER"
fi

# Check Transmission
check_transmission

# Summary
print_header "SUMMARY"
echo -e "${GREEN}✓${NC} Script execution completed at $(date '+%H:%M:%S')"
echo -e "\n${CYAN}Tip: Run this script with watch for continuous monitoring:${NC}"
echo -e "${YELLOW}  watch -n 30 $0${NC}"

# Save results to log file (optional)
if [ "$1" = "--log" ]; then
  LOG_FILE="/var/log/vpn-monitor-$(date '+%Y%m%d-%H%M%S').log"
  echo -e "\n${YELLOW}Saving results to: $LOG_FILE${NC}"
  # Rerun script and save to log
  $0 | tee "$LOG_FILE"
fi

exit 0
