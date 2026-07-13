# Pi-hole Ad-Blocking & Protocol Logging

Pi-hole runs on the **Pi2/PeachPi** (10.42.1.109) and provides DNS-level ad blocking, query logging, and full packet capture for the entire SageSMP cluster.

## Architecture

```
                        Pi-hole (Pi2 10.42.1.109)
                        ├── pihole-FTL (DNS server port 53)
                        ├── pihole-capture (tcpdump packet capture)
                        └── /var/log/pihole/pihole.log (DNS queries)

OrangePi (192.168.254.44)
  └── DNS → 10.42.1.109 (direct to Pi-hole)
  └── dnsmasq on end0/end1 relays DHCP + DNS to subnets

Pi4 (10.42.0.141)
  └── DNS → 10.42.0.1 (OrangePi end1 relay)
  └── OrangePi dnsmasq forwards → Pi2 Pi-hole
```

## DNS Routing

| Device | DNS Server | Route | Notes |
|--------|-----------|-------|-------|
| Pi2 | 127.0.0.1:53 | Local | Uses its own Pi-hole instance |
| OrangePi | 10.42.1.109:53 | Direct | Reaches Pi2 via end0 interface |
| Pi4 | 10.42.0.1:53 | Via OrangePi | OrangePi's NM dnsmasq on end1 forwards to Pi2 |

## Ad-Blocking

Pi-hole ad blocking is enabled with `pihole enable`. The blocklist is updated via:

```bash
pihole updateGravity
```

Blocking status is captured every 5 minutes by `scripts/sagesmp-pihole.sh` and reported via the heartbeat system to the dashboard.

## Query Logging

DNS query logging is enabled with `pihole logging on`. The privacy level is set to **0** (log all domains). Logs are written to:

- `/var/log/pihole/pihole.log` — real-time DNS query log
- `/var/log/pihole/pihole-FTL.log` — FTL daemon log

FTL configuration in `/etc/pihole/pihole-FTL.conf`:

```ini
QUERY_LOGGING=true
MAXLOGAGE=365
VERBOSE=true
PRIVACYLEVEL=0
```

## Packet Capture (tcpdump)

A systemd service `pihole-capture` runs tcpdump on **all interfaces**, capturing traffic for all protocols.

**Service:** `/etc/systemd/system/pihole-capture.service`

```ini
[Unit]
Description=Pi-hole Full Packet Capture (SageSMP)
After=network.target
Wants=pihole-FTL.service

[Service]
ExecStart=/usr/bin/tcpdump -i any -G 86400 \
  -w /var/log/pihole_traffic/capture_%Y%m%d.pcap \
  -z /usr/bin/gzip -C 5000 not port 22
Restart=always
```

- **Rotation:** 7-day rolling via logrotate (`/etc/logrotate.d/pihole-capture`)
- **Excludes:** SSH (port 22) to avoid capturing management traffic
- **File size:** ~5000MB per daily capture file before rotation
- **Output:** Compressed `.pcap.gz` files in `/var/log/pihole_traffic/`

### Protocol Classification

Dashboard live console shows tagged protocol logs:

| Tag | Protocols |
|-----|-----------|
| `[DNS]` | DNS queries/responses |
| `[TCP]` | General TCP traffic |
| `[UDP]` | General UDP traffic |
| `[HTTP]` | Port 80 traffic |
| `[HTTPS]` | Port 443 traffic |
| `[ICMP]` | Ping/traceroute |

## Monitoring Script

`scripts/sagesmp-pihole.sh` (cron every 5 minutes on Pi2) captures:

```json
{
  "pihole_active": "active",
  "blocking": "enabled",
  "logging": "enabled",
  "privacy_level": 0,
  "queries_today": 1234,
  "listening": 1,
  "ftl_pid": 1255,
  "pcap_active": "active"
}
```

This JSON is written to `/tmp/sagesmp_pihole.json` and read by the RPi2 Sage client during each 60-second heartbeat to the OrangePi relay.

## Dashboard Integration

The dashboard (`dashboard/app.py`) streams Pi-hole logs to the live console:

1. **Pi-hole query log** — SSH `tail -f /var/log/pihole/pihole.log` on Pi2, prefixed with `[Pi-hole]`
2. **DNS syslog** — SSH `tail -f /var/log/syslog` on Pi2, filtered for `[Pi-Hole]` entries, prefixed with `[DNS]`
3. **Packet capture** — SSH `tcpdump -l -n` on Pi2, with protocol classification tags
4. **Service telemetry** — Parsed from heartbeat `[SERVICES]` lines in the relay output

## Maintenance

```bash
# Check Pi-hole status
ssh OrangePi "ssh pi2 'pihole status'"

# Check packet capture service
ssh OrangePi "ssh pi2 'systemctl status pihole-capture'"

# View live DNS queries
ssh OrangePi "ssh pi2 'pihole tail'"

# View capture files
ssh OrangePi "ssh pi2 'ls -lh /var/log/pihole_traffic/'"

# Restart capture service
ssh OrangePi "ssh pi2 'systemctl restart pihole-capture'"
```
