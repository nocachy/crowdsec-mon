# CrowdSec-mon.sh

**CrowdSec-mon.sh** is a hacker-style, real-time terminal dashboard for [CrowdSec](https://crowdsec.net).  
It provides a full-screen text user interface (TUI) that visualizes CrowdSec metrics, scenarios, decisions, alerts, parsers, whitelists activity in a terminal console.

---

## ✨ Features

- Real-time monitoring of CrowdSec metrics (`cscli metrics show -o json`, `cscli decisions list -o json`, `cscli alerts list -o json`)
- Aggregated decisions and recent decisions with IP + scenario messages
- Top scenarios, top decisions, parsers, and whitelists displayed in a left column
- Recent decisions in a right column (left column width configurable via LEFT_PCT / LEFT_MIN)
- Parse ratio progress bar with colored visualization
- ANSI color output for readability (green/yellow/red highlights)
- Designed to run inside a **tmux session** as a **systemd service**
- Adaptive layout based on terminal size
- Optional ASCII banner is read from crowdsec-banner.txt (or BANNER_FILE=...) and shown only if it fits.

---

## 📦 Requirements

- **Linux** with Bash ≥ 4
- [CrowdSec](https://docs.crowdsec.net/) installed and configured
- `cscli` (requires `sudo` for JSON output)
- `jq` for JSON parsing
- `tput` (usually part of `ncurses`)
- `tmux` (recommended for running as a service)

---

## 🚀 Installation

1. Copy the script to `/usr/local/bin`:

   ```bash
   sudo cp crowdsec-monitor.sh /usr/local/bin/crowdsec-monitor.sh
   sudo chmod +x /usr/local/bin/crowdsec-monitor.sh
