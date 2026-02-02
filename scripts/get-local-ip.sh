#!/bin/bash
# Dynamic IP detection script for local development
# Works across different OSes and network configurations

set -euo pipefail

# Function to detect the primary network interface IP
get_primary_ip() {
    local ip=""
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # On macOS, iterate through network interfaces to find a private IP address.
        # This is more reliable than using the default route, which might be a VPN or other virtual interface.
        ip=$(ifconfig -a | grep -E 'inet ([0-9.]+)' | grep -v '127.0.0.1' | awk '{print $2}' | grep -E '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' | head -n1 || true)
        
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        else
            echo "Error: Could not automatically detect a valid LAN IP address on macOS." >&2
            echo "Please ensure you are connected to a network and have an IP address in a private range (192.168.x.x, 10.x.x.x, etc.)." >&2
            echo "You can also set the LOCAL_IP environment variable to your LAN IP." >&2
            return 1
        fi
    else
        # Linux and other Unix-like specific logic.
        # Method 1: Get IP of default route (often works in WSL2, Linux)
        if command -v ip >/dev/null 2>&1; then
            ip=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {print $7}' || true)
            if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
                echo "$ip"
                return 0
            fi
        fi
        
        # Method 2: Check common interface names
        local interfaces=("eth0" "en0" "wlan0" "wlp0s20f3" "enp0s3" "ens33")

        for iface in "${interfaces[@]}"; do
            if command -v ip >/dev/null 2>&1; then
                ip=$(ip addr show "$iface" 2>/dev/null | grep -E 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1 || true)
            elif command -v ifconfig >/dev/null 2>&1; then
                ip=$(ifconfig "$iface" 2>/dev/null | grep -E 'inet ' | awk '{print $2}' | head -n1 || true)
            fi
            
            if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
                echo "$ip"
                return 0
            fi
        done
        
        # Method 3: Use hostname -I (Linux-specific, often returns multiple IPs)
        if command -v hostname >/dev/null 2>&1 && [[ "$OSTYPE" == "linux-gnu"* ]]; then
            ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
            if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
                echo "$ip"
                return 0
            fi
        fi
        
        # Method 4: Fall back to checking all interfaces for the first non-loopback IP
        if command -v ip >/dev/null 2>&1; then
            ip=$(ip addr show | grep -E 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1 || true)
        elif command -v ifconfig >/dev/null 2>&1; then
            ip=$(ifconfig | grep -E 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1 || true)
        fi
        
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
        
        # If all methods for Linux fail, exit with an error.
        echo "Error: Could not automatically detect a valid LAN IP address." >&2
        return 1
    fi
}

# Main execution
main() {
    # The get_primary_ip function will echo the IP or an error message and will exit with a non-zero status on failure.
    # Because of `set -e`, the script will exit if get_primary_ip fails.
    get_primary_ip
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
