#!/usr/bin/env bash
# =============================================================
# fake-dated-commits.sh
#
# Creates fake empty commits for a specific date or date range.
# No file changes required (uses --allow-empty).
# =============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

MESSAGES=(
    "feat: refine HermesVault deposit flow"
    "fix: enforce lock period validation"
    "chore: sync Clarinet settings for simnet"
    "docs: update HermesVault usage walkthrough"
    "refactor: simplify reward settlement math"
    "test: add coverage for lock expiry checks"
    "feat: improve vault owner control flow"
    "fix: prevent zero-amount deposits"
    "chore: clean up local test artifacts"
    "docs: clarify reward multiplier table"
    "feat: add guardrails for pause state"
    "fix: improve error copy for invalid owner"
    "refactor: isolate reward-per-token helpers"
    "test: validate withdraw boundary cases"
    "chore: refresh test workflow scripts"
    "feat: improve event print consistency"
    "fix: handle unallocated rewards carryover"
    "refactor: optimize map lookups in withdraw"
    "docs: expand deployment notes for simnet"
    "test: add regression scenario for reward debt"
)

TOTAL_MSGS=${#MESSAGES[@]}

ensure_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo -e "${RED}Missing required command: $1${NC}"
        exit 1
    fi
}

ensure_cmd git
ensure_cmd date

normalize_date() {
    local input="$1"
    date -d "$input" +%Y-%m-%d 2>/dev/null || return 1
}

rand_ts_for_date() {
    local d="$1"
    local h m s
    h=$(printf "%02d" $((RANDOM % 9 + 9)))
    m=$(printf "%02d" $((RANDOM % 60)))
    s=$(printf "%02d" $((RANDOM % 60)))
    printf "%sT%s:%s:%s" "$d" "$h" "$m" "$s"
}

usage() {
    cat <<'EOF'
Usage:
  ./fake-dated-commits.sh --date YYYY-MM-DD --count N [--branch BRANCH] [--no-push]
  ./fake-dated-commits.sh --start YYYY-MM-DD --end YYYY-MM-DD --per-day N [--branch BRANCH] [--no-push]

Examples:
  ./fake-dated-commits.sh --date 2026-04-10 --count 15
  ./fake-dated-commits.sh --start 2026-04-01 --end 2026-04-25 --per-day 3 --branch main
EOF
}

single_date=""
start_date=""
end_date=""
count=0
per_day=0
branch=""
no_push=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --date)
            single_date="${2:-}"
            shift 2
            ;;
        --count)
            count="${2:-0}"
            shift 2
            ;;
        --start)
            start_date="${2:-}"
            shift 2
            ;;
        --end)
            end_date="${2:-}"
            shift 2
            ;;
        --per-day)
            per_day="${2:-0}"
            shift 2
            ;;
        --branch)
            branch="${2:-}"
            shift 2
            ;;
        --no-push)
            no_push=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown argument: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

is_int() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo -e "${RED}Run this script inside a git repository.${NC}"
    exit 1
fi

mode=""
if [[ -n "$single_date" ]]; then
    mode="single"
    if [[ -n "$start_date" || -n "$end_date" ]]; then
        echo -e "${RED}Use either --date or --start/--end, not both.${NC}"
        exit 1
    fi
    single_date="$(normalize_date "$single_date")" || {
        echo -e "${RED}Invalid --date value.${NC}"
        exit 1
    }
    if ! is_int "$count" || [[ "$count" -lt 1 ]]; then
        echo -e "${RED}--count must be a positive integer.${NC}"
        exit 1
    fi
else
    if [[ -z "$start_date" || -z "$end_date" ]]; then
        echo -e "${RED}Provide either --date/--count or --start/--end/--per-day.${NC}"
        usage
        exit 1
    fi
    mode="range"
    start_date="$(normalize_date "$start_date")" || {
        echo -e "${RED}Invalid --start value.${NC}"
        exit 1
    }
    end_date="$(normalize_date "$end_date")" || {
        echo -e "${RED}Invalid --end value.${NC}"
        exit 1
    }
    if [[ "$start_date" > "$end_date" ]]; then
        echo -e "${RED}--start must be <= --end.${NC}"
        exit 1
    fi
    if ! is_int "$per_day" || [[ "$per_day" -lt 1 ]]; then
        echo -e "${RED}--per-day must be a positive integer.${NC}"
        exit 1
    fi
fi

if [[ -z "$branch" ]]; then
    branch="$(git branch --show-current)"
    if [[ -z "$branch" ]]; then
        branch="main"
    fi
fi

echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     fake-dated-commits.sh — date mode     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"

if [[ "$mode" == "single" ]]; then
    total="$count"
    echo -e "${YELLOW}Mode: single date${NC}"
    echo -e "${YELLOW}Date: $single_date${NC}"
    echo -e "${YELLOW}Commits: $count${NC}"
else
    day_span=$(( ( $(date -d "$end_date" +%s) - $(date -d "$start_date" +%s) ) / 86400 + 1 ))
    total=$(( day_span * per_day ))
    echo -e "${YELLOW}Mode: date range${NC}"
    echo -e "${YELLOW}Range: $start_date -> $end_date${NC}"
    echo -e "${YELLOW}Commits/day: $per_day${NC}"
fi
echo -e "${YELLOW}Branch: $branch${NC}"
if $no_push; then
    echo -e "${YELLOW}Push: disabled (--no-push)${NC}"
else
    echo -e "${YELLOW}Push: enabled${NC}"
fi
echo -e "${YELLOW}Total commits planned: $total${NC}"

read -r -p "$(echo -e "${YELLOW}Proceed? (y/N): ${NC}")" confirm
echo
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Aborted.${NC}"
    exit 1
fi

echo -e "${BLUE}Starting...${NC}"
start_seconds=$SECONDS
made=0

commit_one() {
    local d="$1"
    local idx ts msg
    idx=$((RANDOM % TOTAL_MSGS))
    msg="${MESSAGES[$idx]}"
    ts="$(rand_ts_for_date "$d")"
    GIT_AUTHOR_DATE="$ts" GIT_COMMITTER_DATE="$ts" git commit --allow-empty -m "$msg" --quiet
    made=$((made + 1))

    if (( made % 25 == 0 )) || (( made == total )); then
        elapsed=$((SECONDS - start_seconds))
        pct=$((made * 100 / total))
        echo -e "  ${GREEN}[${made}/${total}]${NC} ${pct}% — ${elapsed}s elapsed"
    fi
}

if [[ "$mode" == "single" ]]; then
    for ((i = 1; i <= count; i++)); do
        commit_one "$single_date"
    done
else
    current="$start_date"
    while [[ "$current" < "$end_date" || "$current" == "$end_date" ]]; do
        for ((i = 1; i <= per_day; i++)); do
            commit_one "$current"
        done
        current="$(date -d "$current +1 day" +%Y-%m-%d)"
    done
fi

if ! $no_push; then
    echo
    echo -e "${YELLOW}↑ Pushing to origin/$branch...${NC}"
    git push --set-upstream origin "$branch" 2>/dev/null || git push origin "$branch"
fi

total_time=$((SECONDS - start_seconds))
echo
echo -e "${GREEN}✓ Done! Created ${made} dated empty commit(s) in ${total_time}s.${NC}"
