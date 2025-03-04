#!/bin/bash
exec > >(tee /tmp/port_changer.log) 2>&1  # Output to both log file and terminal
set -x  # Enable debug mode to print each command
YOURNAME=$(whoami)
echo "Starting script..."
echo $YOURNAME
######## MANDATORY ##########
####  USER CHANGES HERE  ####
# Are you using a flatpak for qbitorrent or not?

#Option1 IF you ARE using Flatpak
# uncomment the 3 lines(that means deleting "#" at the start of each 3 lines below):
#config_file="/home/$YOURNAME/.var/app/org.qbittorrent.qBittorrent/config/qBittorrent/qBittorrent.conf"
#kill_qbit="flatpak kill org.qbittorrent.qBittorrent"
#launch_qbit="flatpak run org.qbittorrent.qBittorrent"

#Option2 NOT fltapak
config_file="/home/$YOURNAME/.config/qBittorrent/qBittorrent.conf"
kill_qbit="pkill qbittorrent"
launch_qbit="qbittorrent"
#############################
#############################
# Wait for PIA client process to launch
while ! pgrep -x "pia-client" > /dev/null; do
  echo "Waiting for PIA client..."
  sleep 1
done
echo "PIA client detected."

# Wait for the wgpia0 interface to connect
while ! ip link show wgpia0 > /dev/null 2>&1; do
  echo "Waiting for wgpia0 interface..."
  sleep 1
done
echo "Interface wgpia0 is up."

sleep 3

# Initial VPN connection and VPN IP validation
echo "Performing initial VPN connection and IP checks..."
connection_state=$(piactl get connectionstate)
vpn_ip=$(piactl get vpnip)

if [[ "$connection_state" != "Connected" || "$vpn_ip" == "Unknown" ]]; then
  echo "Initial VPN connection or VPN IP not ready. Establishing connection..."
  while true; do
    connection_state=$(piactl get connectionstate)
    vpn_ip=$(piactl get vpnip)

    if [[ "$connection_state" == "Connected" && "$vpn_ip" != "Unknown" ]]; then
      echo "VPN connection established, VPN IP: $vpn_ip"
      break
    else
      echo "Waiting for VPN connection or VPN IP..."
      sleep 5
    fi
  done
fi

# Main loop for Public IP, Port, and VPN IP
while true; do
  echo "Checking for Public IP..."
  pubip=$(piactl get pubip)
  if [[ "$pubip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Public IP: $pubip"
    break
  else
    echo "Public IP not detected, retrying..."
    sleep 3

    # Inner loop for VPN connection and IP
    while true; do
      echo "Checking PIA connection state and VPN IP..."
      connection_state=$(piactl get connectionstate)
      vpn_ip=$(piactl get vpnip)

      if [[ "$connection_state" == "Connected" ]]; then
        if [[ "$vpn_ip" != "Unknown" ]]; then
          echo "VPN IP assigned: $vpn_ip"
          break
        else
          echo "VPN IP not yet assigned, waiting..."
          sleep 5
        fi
      else
        echo "PIA not connected, attempting reconnect..."
        piactl disconnect && piactl connect
        sleep 6

        # Restart PIA client if reconnect fails
        connection_state=$(piactl get connectionstate)
        if [[ "$connection_state" != "Connected" ]]; then
          echo "Reconnection failed. Restarting PIA client."
          killall pia-client
          nohup env XDG_SESSION_TYPE=X11 /opt/piavpn/bin/pia-client %u &
          sleep 5

          while ! ip link show wgpia0 > /dev/null 2>&1; do
            echo "Waiting for wgpia0 interface..."
            sleep 1
          done
          echo "Interface wgpia0 is up."
        fi
      fi
    done

    # Ensure PIA client is reopened if closed
    while ! pgrep -x "pia-client" > /dev/null; do
      echo "Reopening PIA client..."
      nohup env XDG_SESSION_TYPE=X11 /opt/piavpn/bin/pia-client %u &
      sleep 1
    done
    echo "PIA client reopened and detected."

    # Re-check for Public IP after reconnect and before killing PIA client
    pubip=$(piactl get pubip)
    if [[ "$pubip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Public IP: $pubip"
      break
    else
      echo "Public IP not detected after reconnect attempt, restarting PIA client..."
      killall pia-client
      nohup env XDG_SESSION_TYPE=X11 /opt/piavpn/bin/pia-client %u &
      sleep 5
    fi
  fi
done

sleep 3
$kill_qbit
# Retrieve the forwarded port using piactl
port=$(piactl get portforward)
echo "Retrieved port: $port"

# Update qBittorrent configuration file
#config_file="/home/$YOURNAME/.config/qBittorrent/qBittorrent.conf"
sudo sed -i "s/Session\\\\Port=.*/Session\\\\Port=$port/" $config_file
$launch_qbit
echo "Configuration file updated."

# Define the path for old ports
old_port_path="/home/$YOURNAME/PortSync_Config"
mkdir -p "$old_port_path"
old_port_file="$old_port_path/old.port.check.txt"
touch $old_port_file 
# Check if old.port.check.txt exists
if [ ! -f "$old_port_file" ]; then
  echo $port > "$old_port_file"
  echo "Created old.port.check.txt with port: $port"
fi

# Read the file and compare the port
old_port=$(head -n 1 "$old_port_file")
if [ "$old_port" != "$port" ]; then
  echo -e "$port\nold.$old_port" > "$old_port_file"
  echo "Updated old.port.check.txt with new port: $port"
fi

# Check if the port is already allowed in UFW
if ! sudo ufw status | grep -q "$port"; then
  sudo ufw allow $port
  echo "Port $port has been added to UFW."
fi
$old_port_rule=$($old_port)"*"
# Remove old port if different
if [ "$old_port" != "$port" ]; then
  attempts=0
  while [ $attempts -lt 3 ]; do
    if sudo ufw status | grep -q "$old_port"; then
      sudo ufw delete allow $old_port
      if ! sudo ufw status | grep -q "$old_port"; then
        echo "Successfully deleted old port $old_port from UFW."
        break
      else
        echo "Retrying deletion of old port $old_port..."
      fi
    else
      break
    fi
    ((attempts++))
    sleep 1
  done
fi

#echo $old_port_rule
