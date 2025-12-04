#!/usr/bin/env bash
# /usr/local/bin/crowdsec-monitor.sh
# CrowdSec Matrix TUI — designed to be run as a systemd service in a tmux session
# Requires: cscli, jq, tput, tmux (tmux only for the systemd service wrapper)

INTERVAL=2        # refresh seconds
SCENARIOS_MAX=12
DECISIONS_MAX=15
RECENT_DECISIONS_MAX=50
PARSERS_MAX=15
WHITELISTS_MAX=5

# Colors
CSI="\033["
RESET="${CSI}0m"
BOLD="${CSI}1m"
DIM="${CSI}2m"
FG_GREEN="${CSI}32m"
FG_BRIGHT_GREEN="${CSI}92m"
FG_YELLOW="${CSI}33m"
FG_RED="${CSI}31m"
FG_CYAN="${CSI}36m"
FG_MAGENTA="${CSI}35m"
FG_WHITE="${CSI}97m"

# Helpers
term_cols() { tput cols; }
term_lines(){ tput lines; }
hide_cursor(){ tput civis; }
show_cursor(){ tput cnorm; }
clear_line(){ printf "\033[2K"; }

# safe jq read with fallback (returns 0 / empty)
jq_or_zero() {
	local expr="$1"; local data="$2"
	echo "$data" | jq -r "$expr" 2>/dev/null || echo "0"
}
jq_or_empty() {
	local expr="$1"; local data="$2"
	echo "$data" | jq -r "$expr" 2>/dev/null || echo ""
}

# Draw static frame (adaptive)
draw_frame() {
	cols=$(term_cols)
	lines=$(term_lines)

	clear
	hide_cursor

	# header (centered)
	#header="CROWDSEC — COMMAND CONSOLE"
	#tput cup 0 $(( (cols - ${#header}) / 2 ))
	#printf "%b%s%b\n" "$FG_BRIGHT_GREEN$BOLD" "$header" "$RESET"
	
	printf "%b" "$FG_GREEN"
	cat <<'EOF'
░▒▓███████▓▒░ ░▒▓██████▓▒░ ░▒▓██████▓▒░ ░▒▓██████▓▒░ ░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓███████▓▒░       ░▒▓██████▓▒░░▒▓███████▓▒░ ░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓███████▓▒░ ░▒▓███████▓▒░▒▓████████▓▒░▒▓██████▓▒░       ░▒▓██████████████▓▒░ ░▒▓██████▓▒░░▒▓███████▓▒░  
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░             ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░     ░▒▓█▓▒░░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░             ░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░     ░▒▓█▓▒░             ░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓████████▓▒░▒▓█▓▒░      ░▒▓████████▓▒░░▒▓██████▓▒░ ░▒▓██████▓▒░       ░▒▓█▓▒░      ░▒▓███████▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓██████▓▒░░▒▓██████▓▒░░▒▓█▓▒░             ░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░  ░▒▓█▓▒░          ░▒▓█▓▒░      ░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░      ░▒▓█▓▒░▒▓█▓▒░     ░▒▓█▓▒░             ░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░  ░▒▓█▓▒░          ░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░      ░▒▓█▓▒░▒▓█▓▒░     ░▒▓█▓▒░░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░░▒▓██████▓▒░ ░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░  ░▒▓█▓▒░   ░▒▓███████▓▒░        ░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░░▒▓██████▓▒░ ░▒▓█████████████▓▒░░▒▓███████▓▒░░▒▓███████▓▒░░▒▓████████▓▒░▒▓██████▓▒░       ░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░
EOF
	printf "%b" "$RESET"

	# top summary labels row (fixed)
	tput cup 11 2
	printf "%b┌%s┐%b\n" $((cols-4)) "$(printf '─%.0s' $(seq 1 $((cols-4))))" "$RESET"
	tput cup 12 2
	printf "%b│ %bDECISIONS:%b %27s   %bALERTS:%b %32s   %bLINES READ:%b %30s   %bPARSED:%b %20s   %bDB SIZE:%b %20s │%b\n" \
		"$FG_CYAN" "$FG_WHITE" "$RESET" "-" \
		"$FG_WHITE" "$RESET" "-" \
		"$FG_WHITE" "$RESET" "-" \
		"$FG_WHITE" "$RESET" "-" \
		"$FG_WHITE" "$RESET" "-" \
		"$RESET"

	# parse ratio bar line (fixed placeholder)
	tput cup 13 2
	printf "%b│ %bPARSE RATIO:%b [%-30s] %3s%%%*s│%b\n" "$FG_CYAN" "$FG_WHITE" "$RESET" "" "0" $((cols-80)) " " "$RESET"

	# split: left area = scenarios/parsers/whitelists, right = decisions/recent IPs / bouncers
	#	left column = 40%, right column = 60%
	left_width=$(( (cols - 6) * 37 / 100 ))
	right_width=$(( cols - 6 - left_width - 1 ))

	# left box header
	tput cup 15 2
	printf "%b│ %bTOP SCENARIOS (most hits)%s│%b" "$FG_CYAN" "$FG_WHITE" $((left_width - 28)) " " "$RESET"
	#tput cup 11 2
	#printf "%b│%s│%b\n" $((left_width)) "$(printf ' ')" "$RESET"
	
	#	1.	TOP DECISIONS
	tput cup 28 2
	printf "%b│ %bTOP DECISIONS (aggregated)%s│%b" "$FG_CYAN" "$FG_WHITE" $((right_width - 26)) " " "$RESET"
	#tput cup 26 2
	#printf "%b│%s│%b\n" $((right_width)) "$(printf ' ')" "$RESET"
	
	# parsers header under scenarios
	tput cup $((31 + SCENARIOS_MAX + 1)) 2
	printf "%b│ %bTOP PARSERS (top hits)%s│%b" "$FG_CYAN" "$FG_WHITE" $((left_width - 12)) " " "$RESET"

	# whitelist header
	tput cup $((32 + SCENARIOS_MAX + PARSERS_MAX + 1)) 2
	printf "%b│ %bWHITELISTS (whitelisted)%s│%b " "$FG_CYAN" "$FG_WHITE" $((left_width - 10)) " " "$RESET"
	
	# right box header
	# recent decisions header
	tput cup 14 $((left_width + 5))
	printf "%b│ %bRECENT DECISIONS (IPs)%s│%b " "$FG_CYAN" "$FG_WHITE" $((right_width - 22)) " " "$RESET"

	# footer separator & info line
	tput cup $((lines - 3)) 0
	printf "%b%s%b\n" $cols "$(printf '─%.0s' $(seq 1 $cols))" "$RESET"
	tput cup $((lines - 2)) 2
	printf "%b[ %b%s%b ]  Refresh every %ss  (Detach: tmux detach - to re-attach: tmux attach -t crowdsec_monitor)%b\n" \
	"$FG_MAGENTA" "$FG_GREEN" "$(date '+%Y-%m-%d %H:%M:%S')" "$FG_MAGENTA" "$INTERVAL" "$RESET"

	# save coordinates for dynamic fields (simple mapping)
	
	Y_DEC=12;
	X_DEC=32
	
	Y_ALERT=12;
	X_ALERT=76
	
	Y_READ=12;
	X_READ=116
	
	Y_PARSED=12;
	X_PARSED=152
	
	Y_DB=12;
	X_DB=192;
	
	Y_PARSE_BAR=13;
	X_PARSE_BAR=18;

	Y_SCEN_START=16;
	X_SCEN=4
	#	TOP PARSERS
	Y_PARS_START=$((32 + SCENARIOS_MAX + 1));
	X_PARS=4					
	#	WHITELIST
	Y_WHIT_START=$((33 + SCENARIOS_MAX + PARSERS_MAX + 1));
	X_WHIT=4	
	#	TOP DECISIONS
	Y_DEC_AGG_START=29;
	X_DEC_AGG=4					
	#	RECENT DECISIONS
	Y_DEC_REC_START=$((DECISIONS_MAX));
	X_DEC_REC=$((left_width + 7))
}

# fetch JSON blobs (run as root inside systemd)
fetch_json() {
	METRICS_JSON=$(cscli metrics show -o json 2>/dev/null || echo "{}")
	DEC_JSON=$(cscli decisions list -o json 2>/dev/null || echo "[]")
	ALERT_JSON=$(cscli alerts list -o json 2>/dev/null || echo "[]")
}

# compute safe aggregates from METRICS_JSON
compute_metrics() {
	# lines read and parsed -> sum across acquisition map (your actual JSON uses "acquisition")
	LINES_READ=$(echo "$METRICS_JSON" | jq -r '[ .acquisition? | to_entries[]?.value.reads // 0 ] | add // 0')
	LINES_PARSED=$(echo "$METRICS_JSON" | jq -r '[ .acquisition? | to_entries[]?.value.parsed // 0 ] | add // 0')

	# parse ratio
	if [ "$LINES_READ" -gt 0 ]; then
	PARSE_RATIO=$(( LINES_PARSED * 100 / LINES_READ ))
	else
	PARSE_RATIO=0
	fi

	# DB size: storage may be absent; fallback
	DB_BYTES=$(echo "$METRICS_JSON" | jq -r '(.bouncers? | to_entries[]? | .value[""]?.processed.byte?) // 0' 2>/dev/null || echo 0)

	# aggregated decisions (counts) from metrics.decisions struct
	DECISION_AGG_TOTAL=$(echo "$METRICS_JSON" | jq -r '[ .decisions? | .. | numbers ] | add // 0' 2>/dev/null || echo 0)

	# alerts total (map values)
	ALERTS_TOTAL=$(echo "$METRICS_JSON" | jq -r '[ .alerts? | to_entries[]?.value // 0 ] | add // 0' 2>/dev/null || echo 0)
}

# render dynamic fields (use tput cup to overwrite only the values)
render_dynamic() {
	# header / top summary
	tput cup $Y_DEC $X_DEC; printf "%b%12s%b" "$FG_BRIGHT_GREEN$DIM" "$DECISION_AGG_TOTAL" "$RESET"
	tput cup $Y_ALERT $X_ALERT; printf "%b%8s%b" "$FG_YELLOW" "$ALERTS_TOTAL" "$RESET"
	tput cup $Y_READ $X_READ; printf "%b%10s%b" "$FG_CYAN" "$LINES_READ" "$RESET"
	tput cup $Y_PARSED $X_PARSED; printf "%b%10s%b" "$FG_CYAN" "$LINES_PARSED" "$RESET"
	tput cup $Y_DB $X_DB; printf "%b%12s%b" "$FG_MAGENTA" "$DB_BYTES" "$RESET"

	# parse ratio bar
	BAR_W=40
	filled=$(( BAR_W * PARSE_RATIO / 100 ))
	empty=$(( BAR_W - filled ))
	bar="$(printf '%0.s█' $(seq 1 $filled))$(printf '%0.s░' $(seq 1 $empty))"
	tput cup $Y_PARSE_BAR $X_PARSE_BAR; printf "%b%-*s %3s%% %b" "$FG_GREEN" "$BAR_W" "$bar" "$PARSE_RATIO" "$RESET"

	# Top Scenarios (left)
	scenarios=$(echo "$METRICS_JSON" | jq -r '.scenarios? // {} | to_entries[] | "\(.key)|\(.value.pour // .value.poured // 0)|\(.value.curr_count // 0)"' 2>/dev/null || echo "")
	# Strip ANSI escapes from ALL fields
	scenarios_clean=$(printf '%s\n' "$scenarios" | sed 's/\\\[033\[[0-9;]*[mKG]\?//g')
	# convert to "name|poured|curr" and sort by poured desc
	scenarios_sorted=$(printf "%s\n" "$scenarios" | awk -F'|' '{print $2 "\t" $3 "\t" $1}' | sort -nr | awk -F'\t' '{print $3 "|" $1 "|" $2}' | head -n $SCENARIOS_MAX)
	
	idx=0
	while IFS='|' read -r sname spour scurr; do
		y=$((Y_SCEN_START + idx))
		tput cup $y $X_SCEN
		color="$FG_GREEN"
		[ -n "$spour" ] && [ "$spour" -ge 1000 ] && color="$FG_RED$DIM"
		[ -n "$spour" ] && [ "$spour" -ge 100 ] && color="$FG_YELLOW"
		#printf "%-50s %b%6s poured %s curr:%s%b" "$sname" "$color" "$spour" "$RESET" "$scurr" "$RESET"
		# Color red if "CVE" anywhere in msg
		# BF check first (highest priority, red)
		if [[ "${sname,,}" == *"bf"* ]]; then
			color="$FG_RED$BOLD"
		else
			color="$FG_GREEN"
			[ -n "$spour" ] && [ "$spour" -ge 1000 ] && color="$FG_RED$BOLD"
			[ -n "$spour" ] && [ "$spour" -ge 100 ] && color="$FG_YELLOW"
		fi
		
		printf "%b%-50s%b %b%6s poured%b curr:%s%b" \
			"$color" "$sname" "$RESET" \
			"$color" "$spour" "$RESET" \
			"$scurr" "$RESET"
		((idx++))
	done <<< "$scenarios_sorted"
	# blank remaining lines
	for i in $(seq $idx $SCENARIOS_MAX); do
		y=$((Y_SCEN_START + i - 1))
		tput cup $y $X_SCEN
		printf "%-80s" " "
	done
	
	# Aggregated decisions 
	dec_agg=$(echo "$METRICS_JSON" | jq -r '.decisions? // {} | to_entries[] | "\(.key)|\(.value | to_entries[] | .key):\(.value | to_entries[] | .value)"' 2>/dev/null || echo "")
	# Format better: reason | origin:count (may have multiple origins)
	idx=0
	while IFS='|' read -r reason origcounts; do
		y=$((Y_DEC_AGG_START + idx))
		tput cup $y $X_DEC_AGG
		#printf "%-60s %s" "$reason" "$origcounts"
		# Color red if "CVE" anywhere in reason
		if [[ "${reason,,}" == *cve* ]]; then
			printf "%b%-60s%b %s\n" "$FG_RED$BOLD" "$reason" "$RESET" "$origcounts"
		else
			printf "%-60s %s\n" "$reason" "$origcounts"
		fi
		((idx++))
		[ $idx -ge $DECISIONS_MAX ] && break
	done <<< "$dec_agg"
	for i in $(seq $idx $DECISIONS_MAX); do
		y=$((Y_DEC_AGG_START + i - 1))
		tput cup $y $X_DEC_AGG;
		printf "%-80s" " "
	done
	
	# Top Parsers (under scenarios)
	parsers=$(echo "$METRICS_JSON" | jq -r '.parsers? // {} | to_entries[] | "\(.key)|\(.value.hits // 0)|\(.value.parsed // 0)"' 2>/dev/null || echo "")
	parsers_sorted=$(printf "%s\n" "$parsers" | awk -F'|' '{print $2 "\t" $1 "\t" $3}' | sort -nr | awk -F'\t' '{print $2 "|" $1 "|" $3}' | head -n $PARSERS_MAX)
	idx=0
	while IFS='|' read -r pname phits pparsed; do
		y=$((Y_PARS_START + idx))
		tput cup $y $X_PARS
		printf "%-48s hits:%6s parsed:%6s" "$pname" "$phits" "$pparsed"
		((idx++))
	done <<< "$parsers_sorted"
	for i in $(seq $idx $PARSERS_MAX); do
		y=$((Y_PARS_START + i - 1))
		tput cup $y $X_PARS;
		printf "%-80s" " "
	done

	# Whitelists
	whits=$(echo "$METRICS_JSON" | jq -r '.whitelists? // {} | to_entries[] | "\(.key)|\(.value[]? // {} | to_entries[] | .key):\(.value.hits // 0)"' 2>/dev/null || echo "")
	# Simple format: show name and hits sum per whitelist
	idx=0
	while IFS='|' read -r wname winfo; do
		y=$((Y_WHIT_START + idx))
		tput cup $y $X_WHIT
		printf "%-48s %s" "$wname" "$winfo"
		((idx++))
		[ $idx -ge $WHITELISTS_MAX ] && break
	done <<< "$whits"
	for i in $(seq $idx $WHITELISTS_MAX); do
		y=$((Y_WHIT_START + i - 1))
		tput cup $y $X_WHIT; printf "%-80s" " "
	done

	#	Recent decisions	(right)
	recent_ips=$(echo "$DEC_JSON" | jq -r '.[]? | .message' 2>/dev/null || echo "")
	idx=0
	while IFS= read -r msg && [ $idx -lt $RECENT_DECISIONS_MAX ]; do
		y=$((Y_DEC_REC_START + idx))
		tput cup $y $X_DEC_REC
		#printf "%-72s" "$msg"
		# Color red if "CVE" anywhere in msg
		if [[ "${msg,,}" == *cve* ]]; then
			printf "%b%-60s%b %s\n" "$FG_RED$BOLD" "$msg" "$RESET"
		else
			printf "%-60s %s\n" "$msg"
		fi
		((idx++))
	done <<< "$recent_ips"

	# Blank out remaining lines if fewer than RECENT_DECISIONS_MAX
	for i in $(seq $idx $RECENT_DECISIONS_MAX); do
		y=$((Y_DEC_REC_START + i - 1))
		tput cup $y $X_DEC_REC
		printf "%-80s" " "
	done

	# footer time
	lines=$(term_lines)
	tput cup $((lines - 2)) 2
	printf "%b[ %b%s%b ]  Refresh every %ss  (tmux attach -t crowdsec_monitor)%b" \
	"$FG_MAGENTA" "$FG_GREEN" "$(date '+%Y-%m-%d %H:%M:%S')" "$FG_MAGENTA" "$INTERVAL" "$RESET"
}

# main
main() {
	draw_frame
	while true; do
		fetch_json
		compute_metrics
		render_dynamic
		sleep "$INTERVAL"
	done
}

main
