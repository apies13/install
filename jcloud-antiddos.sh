#!/usr/bin/env bash
# jcloud-sgp1.sh
# Installer: Anti-DDoS Level 2-7 for SAMP (ports 7700-7800)
# Run as root. Interactive: Node Name, Webhook URL, GIF URL.

set -euo pipefail
IFS=$'\n\t'

echo "=== JCloud Anti-DDoS Installer (Level 2-7) ==="

read -rp "Masukkan Node Name (contoh: NODE-1): " NODE_NAME
read -rp "Masukkan Discord Webhook URL: " WEBHOOK_URL
read -rp "Masukkan GIF URL untuk embed (atau tekan enter untuk default): " GIF_URL

if [[ -z "$WEBHOOK_URL" ]]; then
  echo "Webhook kosong. Batal."
  exit 1
fi

# default GIF jika kosong
if [[ -z "$GIF_URL" ]]; then
  GIF_URL="https://cdn.discordapp.com/attachments/1381180064842121219/1404108294779437126/standard_2.gif"
fi

# Configurable params (ubah sesuai kebutuhan sebelum menjalankan jika perlu)
PROTECTED_PORT_RANGE="${PROTECTED_PORT_RANGE:-7700:7800}"
IPSET_NAME="${IPSET_NAME:-ddos-ban}"
BAN_DURATION="${BAN_DURATION:-7200}"       # seconds (2 hours default)
CHECK_INTERVAL="${CHECK_INTERVAL:-12}"     # detection loop sleep (seconds)
REPORT_INTERVAL="${REPORT_INTERVAL:-3600}" # hourly report (seconds)
MAX_ENDPOINTS="${MAX_ENDPOINTS:-180}"      # threshold per-IP endpoint count
SYSCTL_TWEAKS=false                        # false = do not change kernel sysctl

echo "[INFO] Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y ipset iptables curl jq iproute2 procps conntrack ss >/dev/null 2>&1 || \
  apt install -y ipset iptables curl jq iproute2 procps conntrack ss

# Create directory & config
mkdir -p /opt/ddos
cat >/opt/ddos/config.env <<EOF
NODE_NAME="${NODE_NAME}"
WEBHOOK_URL="${WEBHOOK_URL}"
GIF_URL="${GIF_URL}"
PROTECTED_PORT_RANGE="${PROTECTED_PORT_RANGE}"
IPSET_NAME="${IPSET_NAME}"
BAN_DURATION="${BAN_DURATION}"
CHECK_INTERVAL="${CHECK_INTERVAL}"
REPORT_INTERVAL="${REPORT_INTERVAL}"
MAX_ENDPOINTS="${MAX_ENDPOINTS}"
EOF
chmod 600 /opt/ddos/config.env

# Write anti-ddos script
cat >/opt/ddos/anti-ddos-node.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Load config
source /opt/ddos/config.env

LOG_PREFIX="JCD-LOG:"
LAST_HOURLY=0
# associative array to avoid flodding notifications for same IP in short time
declare -A SEEN_NOTIFIED

# optional sysctl tweaks (commented out by default)
if [[ "${SYSCTL_TWEAKS:-false}" == "true" ]]; then
  sysctl -w net.ipv4.tcp_syncookies=1
  sysctl -w net.ipv4.tcp_max_syn_backlog=2048
  sysctl -w net.ipv4.netfilter.ip_conntrack_max=200000
fi

# Ensure ipset exists
ipset create "${IPSET_NAME}" hash:ip timeout "${BAN_DURATION}" -exist

# Ensure essential accept rules
iptables -C INPUT -i lo -j ACCEPT 2>/dev/null || iptables -A INPUT -i lo -j ACCEPT
iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Highest priority: drop ips in ipset
iptables -C INPUT -m set --match-set "${IPSET_NAME}" src -j DROP 2>/dev/null || iptables -I INPUT 1 -m set --match-set "${IPSET_NAME}" src -j DROP

# Create chain
iptables -N JCD_PROT 2>/dev/null || true
iptables -F JCD_PROT

# ----------------------
# LEVEL 6: Drop invalid & fragments
# ----------------------
iptables -A JCD_PROT -m conntrack --ctstate INVALID -j DROP
iptables -A JCD_PROT -f -j DROP

# ----------------------
# LEVEL 7: XMAS / NULL scan drop
# ----------------------
iptables -A JCD_PROT -p tcp --tcp-flags ALL ALL -j DROP
iptables -A JCD_PROT -p tcp --tcp-flags ALL NONE -j DROP

# ----------------------
# LEVEL 5: SYN flood protection (rate limit & fallback ban)
# ----------------------
# allow reasonable SYN rate per source, else log & ban
iptables -A JCD_PROT -p tcp --syn -m hashlimit --hashlimit 12/s --hashlimit-burst 40 --hashlimit-mode srcip --hashlimit-name jcd_syn -j RETURN
iptables -A JCD_PROT -p tcp --syn -j LOG --log-prefix "${LOG_PREFIX} SYN-FLOOD: " --log-level 4
iptables -A JCD_PROT -p tcp --syn -j SET --add-set "${IPSET_NAME}" src --timeout "${BAN_DURATION}"

# ----------------------
# LEVEL 4: TCP connection limit (connlimit) + recent burst detection
# ----------------------
# connection limit (simultaneous)
iptables -A JCD_PROT -p tcp --dport ${PROTECTED_PORT_RANGE} -m connlimit --connlimit-above 120 --connlimit-mask 32 -j LOG --log-prefix "${LOG_PREFIX} CONNLIMIT: " --log-level 4
iptables -A JCD_PROT -p tcp --dport ${PROTECTED_PORT_RANGE} -m connlimit --connlimit-above 120 --connlimit-mask 32 -j SET --add-set "${IPSET_NAME}" src --timeout "${BAN_DURATION}"

# recent new-connection bursts
iptables -A JCD_PROT -p tcp --dport ${PROTECTED_PORT_RANGE} -m conntrack --ctstate NEW -m recent --name JCD_TCP --set
iptables -A JCD_PROT -p tcp --dport ${PROTECTED_PORT_RANGE} -m conntrack --ctstate NEW -m recent --name JCD_TCP --update --seconds 10 --hitcount 200 -j LOG --log-prefix "${LOG_PREFIX} NEWTCP: " --log-level 4
iptables -A JCD_PROT -p tcp --dport ${PROTECTED_PORT_RANGE} -m conntrack --ctstate NEW -m recent --name JCD_TCP --update --seconds 10 --hitcount 200 -j SET --add-set "${IPSET_NAME}" src --timeout "${BAN_DURATION}"

# ----------------------
# LEVEL 3: UDP rate limiting for SAMP (heavy UDP usage)
# ----------------------
# allow reasonable burst per-source; if exceeded, log and ban
iptables -A JCD_PROT -p udp --dport ${PROTECTED_PORT_RANGE} -m hashlimit --hashlimit 300/s --hashlimit-burst 600 --hashlimit-mode srcip --hashlimit-name jcd_udp -j RETURN
iptables -A JCD_PROT -p udp --dport ${PROTECTED_PORT_RANGE} -j LOG --log-prefix "${LOG_PREFIX} UDP-FLOOD: " --log-level 4
iptables -A JCD_PROT -p udp --dport ${PROTECTED_PORT_RANGE} -j SET --add-set "${IPSET_NAME}" src --timeout "${BAN_DURATION}"

# ----------------------
# LEVEL 2: basic blacklist check already at top (ipset)
# ----------------------

# mild ICMP protection (level7-related)
iptables -A JCD_PROT -p icmp -m limit --limit 1/s --limit-burst 3 -j RETURN
iptables -A JCD_PROT -p icmp -j DROP

# Attach chain to INPUT for both UDP and TCP to protected range
iptables -C INPUT -p udp --dport ${PROTECTED_PORT_RANGE} -j JCD_PROT 2>/dev/null || iptables -A INPUT -p udp --dport ${PROTECTED_PORT_RANGE} -j JCD_PROT
iptables -C INPUT -p tcp --dport ${PROTECTED_PORT_RANGE} -j JCD_PROT 2>/dev/null || iptables -A INPUT -p tcp --dport ${PROTECTED_PORT_RANGE} -j JCD_PROT

# ----------------------
# helper: send embed to Discord
# ----------------------
send_embed() {
  local title="$1"
  local color="${2:-16711680}"
  local extra_fields_json="${3:-null}" # JSON array of fields or null

  local ts
  ts=$(date -Iseconds)

  payload=$(jq -n --arg title "$title" --arg node "$NODE_NAME" --arg ts "$ts" --arg gif "$GIF_URL" --argjson color "$color" '{
    "username":"JCloud Security",
    "embeds":[
      {
        "title": $title,
        "color": $color,
        "fields": [],
        "image": { "url": $gif },
        "footer": { "text": ("Monitored By JCloud • " + ($ts|sub("T.*$";"")) ) },
        "timestamp": $ts
      }
    ]
  }')

  if [[ "$extra_fields_json" != "null" ]]; then
    payload=$(echo "$payload" | jq --argjson extra "$extra_fields_json" '.embeds[0].fields += $extra')
  fi

  # send (non-blocking)
  curl -s -H "Content-Type: application/json" -X POST -d "$payload" "${WEBHOOK_URL}" >/dev/null 2>&1 || true
}

# build attack notification fields and call send_embed
notify_attack() {
  local ip="$1"
  local reason="$2"
  local fields
  fields=$(jq -n --arg ip "$ip" --arg reason "$reason" --arg pr "${PROTECTED_PORT_RANGE}" --arg ban "${BAN_DURATION}" '[
    { "name":"IP Attacker", "value":("`"+$ip+"`"), "inline": true },
    { "name":"Reason", "value": $reason, "inline": true },
    { "name":"Port Range", "value": $pr, "inline": true },
    { "name":"Ban Duration", "value": ($ban + " seconds"), "inline": true }
  ]')
  send_embed ("🚨 DDoS Detected - " + "${NODE_NAME}") 16711680 "$fields"
}

# hourly "no attack" report
send_hourly_ok() {
  local ban_count
  ban_count=$(ipset list "${IPSET_NAME}" 2>/dev/null | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {c++} END{print c+0}')
  fields=$(jq -n --arg bans "$ban_count" --arg pr "${PROTECTED_PORT_RANGE}" --arg node "${NODE_NAME}" '[
    { "name":"Node", "value": $node, "inline": false },
    { "name":"Status", "value": "🟢 No attacker detected", "inline": false },
    { "name":"Banned IPs", "value": $bans, "inline": true },
    { "name":"Port Range", "value": $pr, "inline": true }
  ]')
  send_embed ("✅ Hourly DDoS Log - " + "${NODE_NAME}") 65280 "$fields"
}

# detection: fast count of UDP endpoints and TCP endpoints in protected range
detect_and_ban() {
  ss -u -n | awk -v pr="${PROTECTED_PORT_RANGE}" '
    {
      for(i=1;i<=NF;i++){
        if ($i ~ ":"pr) {
          split($i,a,":"); ip=a[1]; if (ip=="*") next; cnt[ip]++
        }
      }
    }
    END { for (k in cnt) print cnt[k], k }' | sort -rn | while read -r cnt ip; do
      if [[ -z "$ip" || -z "$cnt" ]]; then continue; fi
      if (( cnt > MAX_ENDPOINTS )); then
        ipset add "${IPSET_NAME}" "$ip" timeout "${BAN_DURATION}" 2>/dev/null || true
        if [[ -z "${SEEN_NOTIFIED[$ip]:-}" ]]; then
          SEEN_NOTIFIED["$ip"]=1
          notify_attack "$ip" "endpoints>$MAX_ENDPOINTS ($cnt)"
        fi
      fi
  done

  # parse recent kernel logs for our LOG_PREFIX to catch connlimit/hashlimit triggers
  if command -v journalctl >/dev/null 2>&1; then
    # look back a few seconds to find matching logs (non-blocking)
    journalctl -kf -o cat --since "1s" | grep --line-buffered "${LOG_PREFIX}" 2>/dev/null | while read -r line; do
      IP=$(echo "$line" | grep -oP '(?<=SRC=)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
      if [[ -n "$IP" ]]; then
        ipset add "${IPSET_NAME}" "$IP" timeout "${BAN_DURATION}" 2>/dev/null || true
        if [[ -z "${SEEN_NOTIFIED[$IP]:-}" ]]; then
          SEEN_NOTIFIED["$IP"]=1
          notify_attack "$IP" "kernel-log"
        fi
      fi
    done &
  else
    # fallback: parse last N lines of /var/log/kern.log (best-effort)
    if [[ -f /var/log/kern.log ]]; then
      grep "${LOG_PREFIX}" /var/log/kern.log | tail -n 200 | while read -r line; do
        IP=$(echo "$line" | grep -oP '(?<=SRC=)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
        if [[ -n "$IP" ]]; then
          ipset add "${IPSET_NAME}" "$IP" timeout "${BAN_DURATION}" 2>/dev/null || true
          if [[ -z "${SEEN_NOTIFIED[$IP]:-}" ]]; then
            SEEN_NOTIFIED["$IP"]=1
            notify_attack "$IP" "kern-log"
          fi
        fi
      done
    fi
  fi
}

# main loop
LAST_HOUR_TS=0
while true; do
  detect_and_ban

  NOW_TS=$(date +%s)
  if (( NOW_TS - LAST_HOUR_TS >= REPORT_INTERVAL )); then
    send_hourly_ok
    LAST_HOUR_TS=$NOW_TS
    # clear seen notifications periodically to allow rerun notifications later
    SEEN_NOTIFIED=()
  fi

  sleep "${CHECK_INTERVAL}"
done
EOF

chmod +x /opt/ddos/anti-ddos-node.sh

# Create systemd unit (format you requested)
cat >/etc/systemd/system/anti-ddos-node.service <<'UNIT'
[Unit]
Description=Anti-DDoS Node Service (SAMP)
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /opt/ddos/anti-ddos-node.sh
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
UNIT

# Start service
systemctl daemon-reload
systemctl enable --now anti-ddos-node.service

echo "Installation complete. Service: anti-ddos-node.service"
echo "Follow logs: sudo journalctl -u anti-ddos-node.service -f"
echo "Check banned IPs: sudo ipset list ${IPSET_NAME}"
