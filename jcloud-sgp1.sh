sudo mkdir -p /opt/ddos
sudo tee /opt/ddos/anti-ddos-node.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
# Anti-DDoS Node script (L4-L7) for SAMP (ports 7700-7800)
# Place this on each Node (VPS 2 & VPS 3). Run as root via systemd.

# ---------- CONFIG ----------
NODE_NAME="JCLOUD-SGP1"                                  # ganti sesuai nama node
WEBHOOK_URL="https://discord.com/api/webhooks/1404332208273096736/Hcz2ocGOUH2R860CemEOaeP_d2kn_olLYiiJVsarZpK_iSvnH5ibtDw2pr5qULohntLv"  # ganti dengan webhook Discord (panel)
PORT_RANGE="7700:7800"
MAX_CONNECTIONS=18
TRACK_SECONDS=10
BAN_DURATION=86400          # seconds (24h)
IPSET_NAME="ddos-ban"
LOG_PREFIX="DDOS-BLOCK:"
# ----------------------------

# ensure required commands exist
for cmd in ipset iptables conntrack curl jq awk ss; do
  command -v $cmd >/dev/null 2>&1 || { echo "Perlu memasang paket yang berisi: $cmd"; exit 1; }
done

# create ipset (with default timeout)
ipset create $IPSET_NAME hash:ip timeout $BAN_DURATION 2>/dev/null || true

# create custom chain
iptables -N DDOS_IN 2>/dev/null || true
iptables -F DDOS_IN

# allow loopback & established
iptables -C INPUT -i lo -j ACCEPT 2>/dev/null || iptables -A INPUT -i lo -j ACCEPT
iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# make sure we drop quickly any ip in ipset
iptables -C INPUT -m set --match-set $IPSET_NAME src -j DROP 2>/dev/null || iptables -I INPUT 1 -m set --match-set $IPSET_NAME src -j DROP

# route SAMP ports to DDOS_IN chain (for all destination IPs on this server)
iptables -C INPUT -p udp --dport $PORT_RANGE -j DDOS_IN 2>/dev/null || iptables -A INPUT -p udp --dport $PORT_RANGE -j DDOS_IN
iptables -C INPUT -p tcp --dport $PORT_RANGE -j DDOS_IN 2>/dev/null || iptables -A INPUT -p tcp --dport $PORT_RANGE -j DDOS_IN

# ---- DDOS_IN rules ----
# TCP new connections tracking using recent
iptables -A DDOS_IN -p tcp --dport $PORT_RANGE -m conntrack --ctstate NEW -m recent --name SAMP --set
iptables -A DDOS_IN -p tcp --dport $PORT_RANGE -m conntrack --ctstate NEW -m recent --name SAMP --update --seconds $TRACK_SECONDS --hitcount $MAX_CONNECTIONS -j LOG --log-prefix "$LOG_PREFIX "
iptables -A DDOS_IN -p tcp --dport $PORT_RANGE -m conntrack --ctstate NEW -m recent --name SAMP --update --seconds $TRACK_SECONDS --hitcount $MAX_CONNECTIONS -j DROP

# SYN protection
iptables -A DDOS_IN -p tcp --syn --dport $PORT_RANGE -m limit --limit 6/s --limit-burst 10 -j ACCEPT
iptables -A DDOS_IN -p tcp --syn --dport $PORT_RANGE -j DROP

# UDP protection: allow burst then log/drop
iptables -A DDOS_IN -p udp --dport $PORT_RANGE -m limit --limit 15/s --limit-burst 30 -j ACCEPT
iptables -A DDOS_IN -p udp --dport $PORT_RANGE -j LOG --log-prefix "$LOG_PREFIX "
iptables -A DDOS_IN -p udp --dport $PORT_RANGE -j DROP

# optional: simple L7 for HTTP API on same host (tune or remove if unused)
iptables -C INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m recent --name HTTP --set 2>/dev/null || iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m recent --name HTTP --set
iptables -C INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m recent --name HTTP --update --seconds 10 --hitcount 60 -j DROP 2>/dev/null || iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m recent --name HTTP --update --seconds 10 --hitcount 60 -j DROP

echo "[INFO] Anti-DDoS rules active for ports $PORT_RANGE"

# ---------------- monitoring function & embed ----------------
get_memory_info() {
  # returns "used_gb total_gb" (rounded to 2 decimals)
  read total used <<< $(free -b | awk '/^Mem:/ {printf "%d %d", $2, $3}')
  used_gb=$(awk -v u="$used" 'BEGIN{printf "%.2f", u/1024/1024/1024}')
  total_gb=$(awk -v t="$total" 'BEGIN{printf "%.2f", t/1024/1024/1024}')
  echo "$used_gb $total_gb"
}

get_disk_info() {
  # pick root mount
  read used total <<< $(df --output=used,size -B1G / | awk 'NR==2{print $1" "$2}')
  # used/total are in GB integers; keep as-is
  echo "$used $total"
}

get_servers_count() {
  # estimate number of SAMP servers by counting udp listeners on ports 7700-7800
  # requires ss
  cnt=$(ss -u -n state listening '( sport >= :7700 && sport <= :7800 )' 2>/dev/null | tail -n +2 | wc -l)
  echo "$cnt"
}

get_uptime_seconds() {
  awk '{print int($1)}' /proc/uptime
}

# function to create and send Discord embed
send_discord_embed() {
  local ip="$1"
  local target_ip="$2"
  local ban_duration="$3"

  # collect metrics
  read mem_used mem_total <<< $(get_memory_info)
  read disk_used disk_total <<< $(get_disk_info)
  servers_count=$(get_servers_count)
  uptime_seconds=$(get_uptime_seconds)
  node_status=true

  # create JSON payload using jq for safety
  payload=$(jq -n --arg title "🚨 DDoS Alert - SAMP Server" \
                   --arg node "$NODE_NAME" \
                   --arg ip "$ip" \
                   --arg target "$target_ip" \
                   --arg ports "$PORT_RANGE" \
                   --arg ban "${ban_duration}" \
                   --arg mem "${mem_used} GB" \
                   --arg memtot "${mem_total} GB" \
                   --arg disk "${disk_used} GB" \
                   --arg disktot "${disk_total} GB" \
                   --arg servers "$servers_count" \
                   --arg uptime "$uptime_seconds" \
                   '{
                     "username":"JCloud Shield",
                     "embeds":[
                       {
                         "title": $title,
                         "color": 16711680,
                         "fields":[
                           { "name": ($node|ascii_upcase), "value": (if $node then "🟥 - **Flood Detected**" else "🔴 - **Offline**" end), "inline": false },
                           { "name": "\u200B", "value": ("Memory : " + $mem + " / " + $memtot + "\nDisk   : " + $disk + " / " + $disktot + "\nServers : " + $servers + "\nTotal Uptime : " + ($uptime|tostring)), "inline": false },
                           { "name": "IP Attacker", "value": ("\`"+$ip+"\`"), "inline": true },
                           { "name": "Target IP", "value": ("\`"+$target+"\`"), "inline": true },
                           { "name": "Port Range", "value": ("\`"+$ports+"\`"), "inline": true },
                           { "name": "Ban Duration", "value": ($ban + \" seconds\"), "inline": true }
                         ],
                         "image": { "url": "https://cdn.discordapp.com/attachments/1381180064842121219/1404108294779437126/standard_2.gif" },
                         "footer": { "text": ("Monitored By JCloud • " + (strftime(\"%H:%M\", now))) },
                         "timestamp": (now|todate)
                       }
                     ]
                   }')

  # send
  curl -s -H "Content-Type: application/json" -X POST -d "$payload" "$WEBHOOK_URL" >/dev/null 2>&1
}

# ---------------- logging monitor ----------------
# Use journalctl live if available, else fallback to /var/log/kern.log
monitor_logs() {
  if command -v journalctl >/dev/null 2>&1; then
    # monitor kernel messages; filter by LOG_PREFIX
    journalctl -kf -o cat | while read -r line; do
      if [[ "$line" == *"$LOG_PREFIX"* ]]; then
        IP=$(echo "$line" | grep -oP '(?<=SRC=)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
        DST=$(echo "$line" | grep -oP '(?<=DST=)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
        if [[ -n "$IP" ]]; then
          ipset add $IPSET_NAME "$IP" timeout $BAN_DURATION 2>/dev/null || true
          echo "[INFO] Added $IP to $IPSET_NAME for $BAN_DURATION seconds"
          send_discord_embed "$IP" "${DST:-unknown}" "$BAN_DURATION"
        fi
      fi
    done &
  else
    tail -F /var/log/kern.log | while read -r line; do
      if [[ "$line" == *"$LOG_PREFIX"* ]]; then
        IP=$(echo "$line" | grep -oP '(?<=SRC=)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
        DST=$(echo "$line" | grep -oP '(?<=DST=)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
        if [[ -n "$IP" ]]; then
          ipset add $IPSET_NAME "$IP" timeout $BAN_DURATION 2>/dev/null || true
          echo "[INFO] Added $IP to $IPSET_NAME for $BAN_DURATION seconds"
          send_discord_embed "$IP" "${DST:-unknown}" "$BAN_DURATION"
        fi
      fi
    done &
  fi
}

# run monitor
monitor_logs

# keep running (so systemd supervises it)
while true; do sleep 3600; done
EOF
sudo chmod +x /opt/ddos/anti-ddos-node.sh
