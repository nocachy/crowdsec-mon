#!/usr/bin/env bash
# CrowdSec monitor - adaptive layout version
# Run as root (or a user allowed to run cscli). Works nicely inside tmux.

# ───────────────────────── config ─────────────────────────
INTERVAL=2                                   # refresh seconds
BANNER_FILE="${BANNER_FILE:-$(dirname "$0")/crowdsec-banner.txt}"   # optional ASCII-art banner (shown only if it fits)
DB_PATH="/var/lib/crowdsec/data/crowdsec.db" # sqlite db (DB SIZE shows n/a if not found)
WHITELIST_ROWS=5                             # rows inside the whitelist panel
LEFT_PCT=27                                  # left column width as % of terminal (raise if names get cut off)
LEFT_MIN=60                                  # ...but at least this many columns
MIN_COLS=100
MIN_LINES=30

# Make ${#var} / ${var:0:n} count characters, not bytes (needed for box drawing)
export LC_ALL=C.UTF-8

# ───────────────────────── colors ─────────────────────────
CSI=$'\033['
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

NEED_REDRAW=0
TOO_SMALL=0

# ───────────────────────── helpers ─────────────────────────
at()  { printf '%s%d;%dH' "$CSI" "$(( $1 + 1 ))" "$(( $2 + 1 ))"; }   # 0-based row, col

rep() {                                       # rep CHAR COUNT
	local n=$2 s
	(( n > 0 )) || return 0
	printf -v s '%*s' "$n" ''
	printf '%s' "${s// /$1}"
}

fit() {                                       # fit TEXT WIDTH -> cut or pad to exactly WIDTH chars
	local t="${1//$'\t'/ }" w=$2
	(( w > 0 )) || return 0
	t="${t:0:w}"
	printf '%s%*s' "$t" $(( w - ${#t} )) ''
}

hnum() {                                      # 1234567 -> 1.2M
	awk -v n="${1:-0}" 'BEGIN {
		if (n >= 1e9) printf "%.1fG", n/1e9;
		else if (n >= 1e6) printf "%.1fM", n/1e6;
		else if (n >= 1e4) printf "%.1fk", n/1e3;
		else printf "%d", n }'
}

hbytes() {                                    # bytes -> 12.3MB
	awk -v n="${1:-0}" 'BEGIN {
		if (n <= 0) { printf "n/a"; exit }
		split("B KB MB GB TB", u, " "); i = 1;
		while (n >= 1024 && i < 5) { n /= 1024; i++ }
		printf (i == 1 ? "%d%s" : "%.1f%s"), n, u[i] }'
}

box() {                                       # box Y X W H TITLE
	local y=$1 x=$2 w=$3 h=$4 title=" $5 " i
	at "$y" "$x"
	printf '%s┌─%s%s%s%s┐%s' "$FG_CYAN" "$FG_WHITE$BOLD" "$title" "$RESET$FG_CYAN" \
		"$(rep ─ $(( w - 3 - ${#title} )))" "$RESET"
	for (( i = 1; i < h - 1; i++ )); do
		at $(( y + i )) "$x"
		printf '%s│%*s│%s' "$FG_CYAN" $(( w - 2 )) '' "$RESET"
	done
	at $(( y + h - 1 )) "$x"
	printf '%s└%s┘%s' "$FG_CYAN" "$(rep ─ $(( w - 2 )))" "$RESET"
}

# fill Y X W H  -- reads lines from stdin; first char of each line is a color code:
#   r=red  y=yellow  g=green  d=dim  n=normal
fill() {
	local y=$1 x=$2 w=$3 h=$4 n=0 line c t col
	local rows=$(( h - 2 )) iw=$(( w - 4 ))
	while (( n < rows )) && IFS= read -r line; do
		c=${line:0:1}; t=${line:1}
		case $c in
			r) col="$FG_RED$BOLD" ;;
			y) col="$FG_YELLOW"   ;;
			g) col="$FG_GREEN"    ;;
			d) col="$DIM"         ;;
			*) col=""             ;;
		esac
		at $(( y + 1 + n )) $(( x + 2 ))
		printf '%s%s%s' "$col" "$(fit "$t" "$iw")" "$RESET"
		(( n++ ))
	done
	while (( n < rows )); do                  # blank leftover rows
		at $(( y + 1 + n )) $(( x + 2 ))
		printf '%*s' "$iw" ''
		(( n++ ))
	done
}

# ───────────────────────── layout ─────────────────────────
layout() {
	cols=$(tput cols); lines=$(tput lines)

	# header: optional banner, otherwise one title line
	hdr_h=1; banner_on=0
	if [[ -r $BANNER_FILE ]]; then
		banner_w=$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' "$BANNER_FILE")
		banner_h=$(wc -l < "$BANNER_FILE")
		if (( banner_w <= cols && banner_h < lines / 3 )); then
			banner_on=1; hdr_h=$(( banner_h + 1 ))
		fi
	fi

	stats_y=$hdr_h                            # overview box is 4 rows tall
	by=$(( hdr_h + 4 ))                       # body start
	bh=$(( lines - by - 1 ))                  # body height (last row = footer)

	lw=$(( (cols - 1) * LEFT_PCT / 100 ))     # left column width
	(( lw < LEFT_MIN )) && lw=$LEFT_MIN       # never narrower than the longest names need
	(( lw > cols * 45 / 100 )) && lw=$(( cols * 45 / 100 ))   # ...but leave room for the right side on small terminals
	rx=$(( lw + 1 ))                          # right column x (1-col gap)
	rw=$(( cols - rx ))                       # right column width

	# left column: scenarios / parsers / whitelists
	wl_h=$(( WHITELIST_ROWS + 2 ))
	local rest=$(( bh - wl_h ))
	sc_h=$(( rest * 55 / 100 )); pa_h=$(( rest - sc_h ))
	sc_y=$by; pa_y=$(( sc_y + sc_h )); wl_y=$(( pa_y + pa_h ))

	# right column: aggregated / recent
	ag_h=$(( bh * 40 / 100 )); rc_h=$(( bh - ag_h ))
	ag_y=$by; rc_y=$(( ag_y + ag_h ))
}

draw_frame() {
	layout
	printf '%s2J' "$CSI"
	tput civis

	if (( cols < MIN_COLS || lines < MIN_LINES )); then
		TOO_SMALL=1
		at 0 0
		printf 'Terminal too small (%dx%d) - need at least %dx%d' "$cols" "$lines" "$MIN_COLS" "$MIN_LINES"
		return
	fi
	TOO_SMALL=0

	if (( banner_on )); then
		local i=0 pad=$(( (cols - banner_w) / 2 )) l
		while IFS= read -r l; do
			at "$i" "$pad"; printf '%s%s%s' "$FG_GREEN" "$l" "$RESET"
			(( i++ ))
		done < "$BANNER_FILE"
	else
		local t="CROWDSEC - COMMAND CONSOLE"
		at 0 $(( (cols - ${#t}) / 2 ))
		printf '%s%s%s' "$FG_BRIGHT_GREEN$BOLD" "$t" "$RESET"
	fi

	box "$stats_y" 0   "$cols" 4      "OVERVIEW"
	box "$sc_y"    0   "$lw"   "$sc_h" "TOP SCENARIOS (most hits)"
	box "$pa_y"    0   "$lw"   "$pa_h" "TOP PARSERS (most hits)"
	box "$wl_y"    0   "$lw"   "$wl_h" "WHITELISTS"
	box "$ag_y"    "$rx" "$rw" "$ag_h" "TOP DECISIONS (aggregated)"
	box "$rc_y"    "$rx" "$rw" "$rc_h" "RECENT DECISIONS (IPs)"
}

# ───────────────────────── data ─────────────────────────
fetch_json() {
	METRICS_JSON=$(cscli metrics show -o json 2>/dev/null); [[ -z $METRICS_JSON ]] && METRICS_JSON='{}'
	DEC_JSON=$(cscli decisions list -o json 2>/dev/null);   [[ -z $DEC_JSON ]] && DEC_JSON='[]'
}

num() {                                       # num JQ_EXPR -> integer from METRICS_JSON (0 on failure)
	local v
	v=$(jq -r "$1" <<<"$METRICS_JSON" 2>/dev/null)
	[[ $v =~ ^[0-9]+$ ]] && echo "$v" || echo 0
}

compute_metrics() {
	LINES_READ=$(num   '[.acquisition // {} | to_entries[] | .value.reads  // 0] | add // 0 | floor')
	LINES_PARSED=$(num '[.acquisition // {} | to_entries[] | .value.parsed // 0] | add // 0 | floor')

	if (( LINES_READ > 0 )); then PARSE_RATIO=$(( LINES_PARSED * 100 / LINES_READ )); else PARSE_RATIO=0; fi
	(( PARSE_RATIO > 100 )) && PARSE_RATIO=100

	DECISION_AGG_TOTAL=$(num '[.decisions // {} | .. | numbers] | add // 0 | floor')

	if jq -e '.alerts' <<<"$METRICS_JSON" >/dev/null 2>&1; then
		ALERTS_TOTAL=$(num '[.alerts // {} | .. | numbers] | add // 0 | floor')
	else   # metrics has no alerts block: fall back to the alerts list (cscli caps it at 50 by default)
		ALERTS_TOTAL=$(cscli alerts list -o json 2>/dev/null | jq 'length' 2>/dev/null)
		ALERTS_TOTAL=${ALERTS_TOTAL:-0}
	fi

	if [[ -r $DB_PATH ]]; then DB_BYTES=$(stat -c %s "$DB_PATH" 2>/dev/null || echo 0); else DB_BYTES=0; fi
}

# ───────────────────────── panel content ─────────────────────────
scen_block() {   # $1 = interior width
	jq -r '(.scenarios // {}) | to_entries
		| map({n: (.key | gsub("\u001b\\[[0-9;]*[A-Za-z]"; "")),
		       p: (.value.pour // .value.poured // 0),
		       c: (.value.curr_count // 0)})
		| sort_by(-.p) | .[] | [.n, .p, .c] | @tsv' <<<"$METRICS_JSON" 2>/dev/null |
	awk -F'\t' -v w="$1" '
		BEGIN { nw = w - 14; fmt = "%-" nw "s %7s %5s"; printf "d" fmt "\n", "SCENARIO", "POURED", "CURR" }
		{ c = "g"; if ($2 >= 100) c = "y"; if ($2 >= 1000) c = "r"; if (tolower($1) ~ /bf/) c = "r";
		  printf "%s" fmt "\n", c, substr($1, 1, nw), $2, $3 }'
}

pars_block() {
	jq -r '(.parsers // {}) | to_entries
		| map({n: .key, h: (.value.hits // 0), p: (.value.parsed // 0)})
		| sort_by(-.h) | .[] | [.n, .h, .p] | @tsv' <<<"$METRICS_JSON" 2>/dev/null |
	awk -F'\t' -v w="$1" '
		BEGIN { nw = w - 16; fmt = "%-" nw "s %7s %7s"; printf "d" fmt "\n", "PARSER", "HITS", "PARSED" }
		{ printf "n" fmt "\n", substr($1, 1, nw), $2, $3 }'
}

wl_block() {
	jq -r '(.whitelists // {}) | to_entries[]
		| [.key, ([.value | .. | numbers] | add // 0)] | @tsv' <<<"$METRICS_JSON" 2>/dev/null |
	awk -F'\t' -v w="$1" '
		BEGIN { nw = w - 8; fmt = "%-" nw "s %7s"; printf "d" fmt "\n", "WHITELIST", "HITS" }
		{ printf "n" fmt "\n", substr($1, 1, nw), $2 }'
}

agg_block() {
	jq -r '(.decisions // {})
		| [paths(numbers) as $p | {k: ($p | map(tostring) | join(" / ")), v: getpath($p)}]
		| sort_by(-.v) | .[] | [.k, .v] | @tsv' <<<"$METRICS_JSON" 2>/dev/null |
	awk -F'\t' -v w="$1" '
		BEGIN { nw = w - 8; fmt = "%-" nw "s %7s"; printf "d" fmt "\n", "REASON / ORIGIN / ACTION", "COUNT" }
		{ c = "n"; if (tolower($1) ~ /cve/) c = "r";
		  printf "%s" fmt "\n", c, substr($1, 1, nw), $2 }'
}

rec_block() {
	jq -r '.[]? | if ((.decisions // []) | length) > 0
			then (.decisions[] | [(.value // ""), (.scenario // ""), (.duration // "")])
			else [(.message // ""), "", ""] end
		| @tsv' <<<"$DEC_JSON" 2>/dev/null | head -n 300 |
	awk -F'\t' -v w="$1" '
		BEGIN { sw = w - 30; fmt = "%-18s %-" sw "s %10s"; printf "d" fmt "\n", "IP", "SCENARIO", "EXPIRES" }
		{ c = "n"; if (tolower($0) ~ /cve/) c = "r";
		  if ($2 == "" && $3 == "") printf "%s%s\n", c, substr($1, 1, w);
		  else printf "%s" fmt "\n", c, substr($1, 1, 18), substr($2, 1, sw), substr($3, 1, 10) }'
}

# ───────────────────────── rendering ─────────────────────────
render_stats() {
	local cell=$(( (cols - 2) / 5 )) k plain pad y=$(( stats_y + 1 ))
	local -a labels=("DECISIONS" "ALERTS" "LINES READ" "PARSED" "DB SIZE")
	local -a vals=("$(hnum "$DECISION_AGG_TOTAL")" "$(hnum "$ALERTS_TOTAL")" \
	               "$(hnum "$LINES_READ")" "$(hnum "$LINES_PARSED")" "$(hbytes "$DB_BYTES")")
	local -a colors=("$FG_BRIGHT_GREEN" "$FG_YELLOW" "$FG_CYAN" "$FG_CYAN" "$FG_MAGENTA")

	for (( k = 0; k < 5; k++ )); do
		plain="${labels[k]} ${vals[k]}"
		pad=$(( cell - 1 - ${#plain} )); (( pad < 0 )) && pad=0
		at "$y" $(( 2 + k * cell ))
		printf '%s%s%s %s%s%s%*s' "$FG_WHITE" "${labels[k]}" "$RESET" "${colors[k]}" "${vals[k]}" "$RESET" "$pad" ''
	done

	# parse ratio bar
	local bw=$(( cols - 24 )); (( bw > 60 )) && bw=60; (( bw < 10 )) && bw=10
	local filled=$(( bw * PARSE_RATIO / 100 )) bc="$FG_GREEN"
	(( PARSE_RATIO < 80 )) && bc="$FG_YELLOW"
	(( PARSE_RATIO < 50 )) && bc="$FG_RED"
	at $(( y + 1 )) 2
	printf '%sPARSE RATIO%s [%s%s%s%s%s%s] %s%3d%%%s' \
		"$FG_WHITE" "$RESET" "$bc" "$(rep █ "$filled")" "$RESET" "$DIM$FG_GREEN" \
		"$(rep ░ $(( bw - filled )))" "$RESET" "$bc" "$PARSE_RATIO" "$RESET"
}

render_footer() {
	local msg
	msg="[ $(date '+%Y-%m-%d %H:%M:%S') ]  refresh ${INTERVAL}s  |  detach: Ctrl-b d  |  re-attach: tmux attach -t crowdsec_monitor"
	at $(( lines - 1 )) 1
	printf '%s%s%s' "$FG_MAGENTA" "$(fit "$msg" $(( cols - 2 )))" "$RESET"
}

render_all() {
	render_stats
	fill "$sc_y" 0    "$lw" "$sc_h" <<<"$(scen_block $(( lw - 4 )))"
	fill "$pa_y" 0    "$lw" "$pa_h" <<<"$(pars_block $(( lw - 4 )))"
	fill "$wl_y" 0    "$lw" "$wl_h" <<<"$(wl_block   $(( lw - 4 )))"
	fill "$ag_y" "$rx" "$rw" "$ag_h" <<<"$(agg_block $(( rw - 4 )))"
	fill "$rc_y" "$rx" "$rw" "$rc_h" <<<"$(rec_block $(( rw - 4 )))"
	render_footer
}

# ───────────────────────── main ─────────────────────────
cleanup() { tput cnorm; printf '%s' "$RESET"; tput cup "$(tput lines)" 0; echo; }
trap cleanup EXIT
trap 'exit 0' INT TERM
trap 'NEED_REDRAW=1' WINCH

main() {
	draw_frame
	while true; do
		if (( NEED_REDRAW )); then NEED_REDRAW=0; draw_frame; fi
		if (( ! TOO_SMALL )); then
			fetch_json
			compute_metrics
			render_all
		fi
		sleep "$INTERVAL" & wait $!           # wait lets the resize trap fire immediately
	done
}

main