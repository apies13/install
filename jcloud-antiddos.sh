#!/usr/bin/env bash
# jcloud-antiddos.sh
# Installer: Anti-DDoS Level 2-7 for SAMP (ports 7700-7800)
# Run as root. Interactive: Node Name, Webhook URL, GIF URL.
set -euo pipefail
IFS=$'\n\t'

echo
echo "=== JCloud Anti-DDoS Installer (Level 2-7) ==="
echo

# --- user input ---
read -rp "Masukkan Node Name (contoh: NODE-1): " NODE_NAME
read -rp "Masukkan Discord Webhook URL: " WEBHOOK_URL
read -rp "Masukkan GIF URL untuk embed (kosong = default): " GIF_URL

if [[ -z "$WEBHOOK_URL" ]]; then
  echo "ERROR: Webhook URL tidak boleh kosong. Batal."
  exit 1
fi

if [[ -z "$GIF_URL" ]]; then
  GIF_URL="https://cdn.discordapp.com/attachments/1381180064842121219/1404108294779437126/standard_2.gif"
fi

# --- configurable defaults (ubah bila perlu sebelum menjalankan) ---
PROTECTED_PORT_RANGE="${PROTECTED_PORT_RANGE:-7700:7800}"
IPSET_NAME="${IPSET_NAME:-ddos-ban}"
BAN_DURATION="${BAN_DURATION:-7200}"       # ban timeout (detik) default 2 jam
CHECK_INTERVAL="${CHECK_INTERVAL:-12}"     # deteksi loop sleep (detik)
REPORT_INTERVAL="${REPORT_INTERVAL:-3600}" # kirim laporan setiap 1 jam
MAX_ENDPOINTS="${MAX_ENDPOINTS:-180}"      # threshold per-IP endpoint count (tuneable)
# -------------------------------------------------------------------

echo "[INFO] Menginstall paket yang diperlukan..."
export DEBIAN_FRONTEND=noninteractive
apt update -y >/dev/null 2>&1 || true
apt install -y ipset iptables curl jq iproute2 procps conntrack ss >/dev/null 2>&1 || {
  echo "[WARN] `apt install` gagal atau membutuhkan interaksi. Coba jalankan 'apt install ipset iptables curl jq ss' secara manual."
}

# create folder & config
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
echo "[INFO] Konfigurasi tersimpan di /opt/ddos/config.env"

# write anti-ddos runner
cat >/opt/ddos/anti-ddos-node.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source /opt/ddos/config.env

LOG_PREFIX="JCD-LOG:"
declare -A SEEN_NOTIFIED
LAST_HOUR_TS=0

# ensure ipset
ipset create "${IPSET_NAME}" hash:ip timeout "${BAN_DURATION}" -exist

# base rules: allow loopback & established
iptables -C INPUT -i lo -j ACCEPT 2>/dev/null || iptables -A INPUT -i lo -j ACCEPT
iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ensure quick drop for banned ipset
iptables -C INPUT -m set --match-set "${IPSET_NAME}" src -j DROP 2>/dev/null || iptables -I INPUT 1 -m set --match-set "${IPSET_NAME}" src -j DROP

# create chain (idempotent)
iptables -N JCD_PROT 2>/dev/null || true
iptables -F JCD_PROT

# === LEVEL 6: drop invalid / fragments ===
iptables -A JCD_PROT -m conntrack --ctstate INVALID -j DROP
iptables -A JCD_PROT -f -j DROP

# === LEVEL 7: XMAS / NULL scan drop ===
iptables -A JCD_PROT -p tcp --tcp-flags ALL ALL -j DROP
iptables -A JCD_PROT -p tcp --tcp-flags ALL NONE -j DROP

# === LEVEL 5: SYN flood protection ===
# allow reasonable SYN rate, else log & ban
iptables -A JCD_PROT -p tcp --syn -m hashlimit --hashlimit 12/s --hashlimit-burst 40 --hashlimit-mode srcip --hashlimit-name jcd_syn -j RETURN
iptables -A JCD_PROT -p tcp --syn -j LOG --log-prefix "${LOG_PREFIX} SYN-FLOOD: " --log-level 4
iptables -A JCD_PROT -p tcp --syn -j SET --add-set "${IPSET_NAME}" src --timeout "${BAN_DURATION}"

# === LEVEL 4: connection limit & recent ===
iptables -A JCD_PROT -p tcp --dport ${PROTECTED_PORT_RANGE} -m connlimit --connlimit-above 120 --connlimit-mask 32 -j LOG --log-prefix "${LOG_PREFIX} CONNLIMIT: " --log-level 4
iptables -A JCD_PROT -p tcp --dport ${PROTECTED_PORT_RANGE} -m connlimit --connlimit-above 120 --connlimit-mask 32 -j SET --add-set "${IPSET_NAME}" src --timeout "${BAN_DURATION}"

iptables -A JCD_PROT -p tcp --dport ${PROTECTED_PORT_RANGE} -m conntrack --ctstate NEW -m recent --name JCD_TCP --set
iptables -A JCD_PROT -p tcp --dport ${PROTECTED_PORT_RANGE} -m conntrack --ctstate NEW -m recent --name JCD_TCP --update --seconds 10 --hitcount 200 -j LOG --log-prefix "${LOG_PREFIX} NEWTCP: " --log-level 4
iptables -A JCD_PROT -p tcp --dport ${PROTECTED_PORT_RANGE} -m conntrack --ctstate NEW -m recent --name JCD_TCP --update --seconds 10 --hitcount 200 -j SET --add-set "${IPSET_NAME}" src --timeout "${BAN_DURATION}"

# === LEVEL 3: UDP rate limiting (SAMP heavy) ===
# allow burst, then log & ban
iptables -A JCD_PROT -p udp --dport ${PROTECTED_PORT_RANGE} -m hashlimit --hashlimit 300/s --hashlimit-burst 600 --hashlimit-mode srcip --hashlimit-name jcd_udp -j RETURN
iptables -A JCD_PROT -p udp --dport ${PROTECTED_PORT_RANGE} -j LOG --log-prefix "${LOG_PREFIX} UDP-FLOOD: " --log-level 4
iptables -A JCD_PROT -p udp --dport ${PROTECTED_PORT_RANGE} -j SET --add-set "${IPSET_NAME}" src --timeout "${BAN_DURATION}"

# mild ICMP control
iptables -A JCD_PROT -p icmp -m limit --limit 1/s --limit-burst 3 -j RETURN
iptables -A JCD_PROT -p icmp -j DROP

# attach chain to INPUT
iptables -C INPUT -p udp --dport ${PROTECTED_PORT_RANGE} -j JCD_PROT 2>/dev/null || iptables -A INPUT -p udp --dport ${PROTECTED_PORT_RANGE} -j JCD_PROT
iptables -C INPUT -p tcp --dport ${PROTECTED_PORT_RANGE} -j JCD_PROT 2>/dev/null || iptables -A INPUT -p tcp --dport ${PROTECTED_PORT_RANGE} -j JCD_PROT

# helper: send embed (uses jq to build payload)
send_embed() {
  local title="$1"; local color="${2:-16711680}"; local fields_json="${3:-null}"
  local ts; ts=$(date -Iseconds)
  local payload
  payload=$(jq -n --arg title "$title" --arg node "$NODE_NAME" --arg gif "$GIF_URL" --arg ts "$ts" --argjson color "$color" '{
    "username":"JCloud Shield",
    "embeds":[
      {
        "title": $title,
        "color": $color,
        "fields": [],
        "image": { "url": $gif },
        "footer": { "text": ("SAMP Protect By JCloud Shield • " + ($ts|sub("T.*$";"")) ) },
        "timestamp": $ts
      }
    ]
  }')
  if [[ "$fields_json" != "null" ]]; then
    payload=$(echo "$payload" | jq --argjson extra "$fields_json" '.embeds[0].fields += $extra')
  fi
  curl -s -H "Content-Type: application/json" -X POST -d "$payload" "${WEBHOOK_URL}" >/dev/null 2>&1 || true
}

notify_attack() {
  local ip="$1"; local reason="$2"
  local fields
  fields=$(jq -n --arg ip "$ip" --arg reason "$reason" --arg pr "${PROTECTED_PORT_RANGE}" --arg ban "${BAN_DURATION}" '[
    { "name":"IP Attacker", "value":("`"+$ip+"`"), "inline": true },
    { "name":"Reason", "value": $reason, "inline": true },
    { "name":"Port Range", "value": $pr, "inline": true },
    { "name":"Ban Duration", "value": ($ban + " seconds"), "inline": true }
  ]')
  send_embed ("🚨 DDoS Detected - " + "${NODE_NAME}") 16711680 "$fields"
}

send_hourly_ok() {
  local ban_count
  ban_count=$(ipset list "${IPSET_NAME}" 2>/dev/null | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {c++} END{print c+0}')
  fields=$(jq -n --arg bans "$ban_count" --arg pr "${PROTECTED_PORT_RANGE}" --arg node "${NODE_NAME}" '[
    { "name":"Node", "value": $node, "inline": false },
    { "name":"Status", "value": "🟢 No attacker detected", "inline": false },
    { "name":"Banned IPs", "value": $bans, "inline": true },
    { "name":"Port Range", "value": $pr, "inline": true }
  ]')
  send_embed ("✅ JCloud Shield - " + "${NODE_NAME}") 65280 "$fields"
}

# detection: fast count of UDP/TCP endpoints in port-range
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

  # parse recent kernel logs for our LOG_PREFIX (non-blocking)
  if command -v journalctl >/dev/null 2>&1; then
    # we look back for short time window; spawn a background grep to avoid blocking
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
while true; do
  detect_and_ban

  NOW_TS=$(date +%s)
  if (( NOW_TS - LAST_HOUR_TS >= REPORT_INTERVAL )); then
    send_hourly_ok
    LAST_HOUR_TS=$NOW_TS
    SEEN_NOTIFIED=()
  fi

  sleep "${CHECK_INTERVAL}"
done
EOF

chmod +x /opt/ddos/anti-ddos-node.sh
echo "[INFO] Wrote /opt/ddos/anti-ddos-node.sh"

# create systemd unit
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

systemctl daemon-reload
systemctl enable --now anti-ddos-node.service

echo "[DONE] Installation complete."
echo "Lihat log realtime: sudo journalctl -u anti-ddos-node.service -f"
echo "Cek banned IPs: sudo ipset list ${IPSET_NAME}"
