#!/usr/bin/env bash
# =============================================================
# fake-issues-prs.sh
#
# Creates realistic-looking GitHub Issues and/or Draft Pull Requests.
# Uses GitHub CLI (gh). No real code changes needed.
# Safe for hundreds of items (rate limits still apply).
# =============================================================

set -euo pipefail

# ────────────────────────────────────────────────
# Colors
# ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

ensure_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo -e "${RED}Missing required command: $1${NC}"
        exit 1
    fi
}

resolve_gh_cmd() {
    if command -v gh >/dev/null 2>&1; then
        command -v gh
        return 0
    fi

    local windows_gh="/c/Program Files/GitHub CLI/gh.exe"
    if [[ -x "$windows_gh" ]]; then
        echo "$windows_gh"
        return 0
    fi

    local powershell_gh="C:\\Program Files\\GitHub CLI\\gh.exe"
    if [[ -x "$powershell_gh" ]]; then
        echo "$powershell_gh"
        return 0
    fi

    return 1
}

GH_CMD="$(resolve_gh_cmd)" || {
    echo -e "${RED}Missing required command: gh${NC}"
    echo -e "${YELLOW}Install GitHub CLI or add its install folder to PATH.${NC}"
    exit 1
}

ensure_cmd git

prompt_yn() {
    local prompt="$1"
    local def="$2"
    local ans=""
    while true; do
        printf "%b" "$prompt"
        read -r ans
        ans="${ans:-$def}"
        case "$ans" in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO) return 1 ;;
            *) echo -e "${RED}Please enter y or n.${NC}" ;;
        esac
    done
}

prompt_with_default() {
    local prompt="$1"
    local def="$2"
    local out=""
    printf "%b" "$prompt" >&2
    read -r out
    out="${out:-$def}"
    echo "$out"
}

prompt_int_range() {
    local prompt="$1"
    local def="$2"
    local min="$3"
    local max="$4"
    local out=""
    while true; do
        printf "%b" "$prompt" >&2
        read -r out
        out="${out:-$def}"
        if [[ "$out" =~ ^[0-9]+$ ]] && [[ "$out" -ge "$min" ]] && [[ "$out" -le "$max" ]]; then
            echo "$out"
            return 0
        fi
        echo -e "${RED}Please enter a number between ${min} and ${max}.${NC}" >&2
    done
}

read_optional_file() {
    local path="$1"
    if [[ -z "$path" ]]; then
        echo ""
        return 0
    fi
    if [[ ! -f "$path" ]]; then
        echo -e "${RED}File not found: $path${NC}"
        exit 1
    fi
    cat "$path"
}

parse_csv_numbers() {
    local raw="$1"
    echo "$raw" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -E '^[0-9]+$' || true
}

# ────────────────────────────────────────────────
# Message pools (realistic-sounding)
# ────────────────────────────────────────────────
ISSUE_TITLES=(
    "Investigate Clarity storage optimization for deposit map"
    "Add comprehensive unit tests for pool deposit logic"
    "Handle edge case when deposit amount is exactly zero"
    "Improve error message for invalid owner principal"
    "Document owner withdrawal authorization flow"
    "Refactor validation checks into separate helper functions"
    "Support batch STX deposits in single transaction"
    "Add integration test for emergency drain scenario"
    "Fix calculation error in total-deposited tracking"
    "Optimize Clarity contract storage packing"
    "Add support for Stacks Testnet deployment"
    "Implement pool pause/unpause functionality"
    "Create dashboard metrics for pool statistics"
    "Resolve edge case in pause state management"
    "Add comprehensive event logging for audit trails"
)

PR_TITLES=(
    "feat: implement complete STX pool deposit system"
    "fix: correct balance calculation in owner-withdraw"
    "chore: upgrade to latest Clarity SDK version"
    "docs: improve pool deployment guide"
    "refactor: modularize pool authorization helpers"
    "test: add fuzz testing for deposit edge cases"
    "feat: support emergency drain functionality"
    "fix: prevent overflow in total-deposited tracking"
    "style: enforce consistent error code naming"
    "chore: add GitHub Actions for Clarinet tests"
)

ISSUE_AREAS=("contracts" "tests" "docs" "deployment" "performance" "security" "validation")
PR_TYPES=("feat" "fix" "refactor" "chore" "test" "docs" "perf")
PR_SCOPES=("contracts" "pool" "tests" "deployment" "error-handling" "docs" "validation")
PR_VALIDATIONS=(
    "clarinet check"
    "npm test"
    "vitest --coverage"
    "manual Simnet validation"
    "Testnet deployment test"
)
ISSUE_PRIORITIES=("P1" "P2" "P3")

TRACK_MARKER="automation-seeded-item-v1"

pick_random() {
    local -n arr_ref=$1
    local size=${#arr_ref[@]}
    local idx=$(( RANDOM % size ))
    echo "${arr_ref[$idx]}"
}

slugify() {
    local s="$1"
    s="${s,,}"
    s="${s//:/ }"
    s="${s//&/ and }"
    s="${s//\// }"
    s="$(echo "$s" | tr -cd 'a-z0-9 _-')"
    s="$(echo "$s" | tr ' ' '-' | tr -s '-')"
    s="${s#-}"
    s="${s%-}"
    echo "$s"
}

TOTAL_ISSUES=${#ISSUE_TITLES[@]}
TOTAL_PRS=${#PR_TITLES[@]}

# ────────────────────────────────────────────────
# Arguments / Interactive input
# ────────────────────────────────────────────────
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   backlog-seeder.sh  —  GitHub workflow      ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

CREATE_ISSUES=false
CREATE_PRS=false
CLOSE_ISSUES=false
CLOSE_PRS=false
CLOSE_FILTER="$TRACK_MARKER"
PR_CLOSE_MODE="1"
PR_HEAD_PREFIX=""
PR_TITLE_KEYWORD=""
PR_AUTHOR=""
PR_NUMBERS_CSV=""
PR_CUSTOM_TEXT=""
ISSUE_CUSTOM_TEXT=""
DRAFT_PRS=true
PUSH_DELAY=2

echo -e "${YELLOW}Choose mode:${NC}"
echo "  1) Create fake items"
echo "  2) Close existing fake items"
MODE="$(prompt_with_default "${YELLOW}Mode [1/2, default: 1]: ${NC}" "1")"

if [[ "$MODE" != "1" && "$MODE" != "2" ]]; then
    echo -e "${RED}Invalid mode. Use 1 or 2.${NC}"
    exit 1
fi

if [[ "$MODE" == "1" ]]; then
    if prompt_yn "${YELLOW}Create Issues? [y/N]: ${NC}" "n"; then CREATE_ISSUES=true; fi

    if prompt_yn "${YELLOW}Create Pull Requests? [y/N]: ${NC}" "n"; then CREATE_PRS=true; fi

    if ! $CREATE_ISSUES && ! $CREATE_PRS; then
        echo -e "${RED}Nothing selected. Exiting.${NC}"
        exit 0
    fi

    if $CREATE_PRS; then
        if ! prompt_yn "${YELLOW}Create as draft PRs? [Y/n]: ${NC}" "y"; then DRAFT_PRS=false; fi
    fi

    ISSUE_FILE_PATH="$(prompt_with_default "${YELLOW}Optional issue body template file path [empty=none]: ${NC}" "")"
    ISSUE_CUSTOM_TEXT="$(read_optional_file "$ISSUE_FILE_PATH")"

    PR_FILE_PATH="$(prompt_with_default "${YELLOW}Optional PR body template file path [empty=none]: ${NC}" "")"
    PR_CUSTOM_TEXT="$(read_optional_file "$PR_FILE_PATH")"

    PUSH_DELAY="$(prompt_int_range "${YELLOW}Delay between items in seconds [1-10, default: 2]: ${NC}" "2" "1" "10")"
else
    if prompt_yn "${YELLOW}Close Issues? [y/N]: ${NC}" "n"; then CLOSE_ISSUES=true; fi

    if prompt_yn "${YELLOW}Close Pull Requests? [y/N]: ${NC}" "n"; then CLOSE_PRS=true; fi

    if ! $CLOSE_ISSUES && ! $CLOSE_PRS; then
        echo -e "${RED}Nothing selected. Exiting.${NC}"
        exit 0
    fi

    CLOSE_FILTER="$(prompt_with_default "${YELLOW}Close filter keyword [default: ${TRACK_MARKER}]: ${NC}" "$TRACK_MARKER")"

    if $CLOSE_PRS; then
        echo -e "${YELLOW}PR close filter mode:${NC}"
        echo "  1) Marker in body (default)"
        echo "  2) Branch prefix (head ref starts with)"
        echo "  3) Title keyword"
        echo "  4) Author login"
        echo "  5) All open PRs (use carefully)"
        PR_CLOSE_MODE="$(prompt_with_default "${YELLOW}Choose PR close mode [1-5, default: 1]: ${NC}" "1")"
        if ! [[ "$PR_CLOSE_MODE" =~ ^[1-5]$ ]]; then
            echo -e "${RED}Invalid PR close mode. Use 1-5.${NC}"
            exit 1
        fi

        case "$PR_CLOSE_MODE" in
            2)
                PR_HEAD_PREFIX="$(prompt_with_default "${YELLOW}Branch prefix (example: feat/): ${NC}" "")"
                if [[ -z "$PR_HEAD_PREFIX" ]]; then
                    echo -e "${RED}Branch prefix is required for mode 2.${NC}"
                    exit 1
                fi
                ;;
            3)
                PR_TITLE_KEYWORD="$(prompt_with_default "${YELLOW}Title keyword: ${NC}" "")"
                if [[ -z "$PR_TITLE_KEYWORD" ]]; then
                    echo -e "${RED}Title keyword is required for mode 3.${NC}"
                    exit 1
                fi
                ;;
            4)
                PR_AUTHOR="$(prompt_with_default "${YELLOW}Author login (example: kramu39): ${NC}" "")"
                if [[ -z "$PR_AUTHOR" ]]; then
                    echo -e "${RED}Author login is required for mode 4.${NC}"
                    exit 1
                fi
                ;;
        esac

        PR_NUMBERS_CSV="$(prompt_with_default "${YELLOW}Optional explicit PR numbers csv (example: 12,45) [empty=use search]: ${NC}" "")"
    fi
fi

if [[ "$MODE" == "1" ]]; then
    COUNT="$(prompt_int_range "${YELLOW}How many total items? [1-500, default: 20]: ${NC}" "20" "1" "500")"
else
    COUNT="$(prompt_int_range "${YELLOW}How many to close? [1-500, default: 20]: ${NC}" "20" "1" "500")"
fi

# Optional: target repo (default = current repo)
TARGET_REPO="$(prompt_with_default "${YELLOW}Repo [owner/repo] (leave empty = current): ${NC}" "")"

REPO_ARGS=()
[[ -n "$TARGET_REPO" ]] && REPO_ARGS+=(--repo "$TARGET_REPO")

if ! "$GH_CMD" auth status >/dev/null 2>&1; then
    echo -e "${RED}gh is not authenticated. Run: gh auth login${NC}"
    exit 1
fi

BASE_BRANCH=""
if [[ "$MODE" == "1" && "$CREATE_PRS" == "true" ]]; then
    BASE_BRANCH="$(prompt_with_default "${YELLOW}Base branch for PRs [default: main]: ${NC}" "main")"

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo -e "${RED}Not inside a git repository.${NC}"
        exit 1
    fi

    if ! git remote get-url origin >/dev/null 2>&1; then
        echo -e "${RED}Git remote 'origin' is missing. Set it first.${NC}"
        exit 1
    fi
fi

echo ""
if [[ "$MODE" == "1" ]]; then
    echo -e "${YELLOW}→ Will create up to $COUNT item(s)${NC}"
    if $CREATE_ISSUES; then echo -e "${YELLOW}→ Issues : yes${NC}"; fi
    if $CREATE_PRS; then echo -e "${YELLOW}→ Draft PRs: yes${NC}"; fi
    if $CREATE_PRS; then echo -e "${YELLOW}→ Base branch: $BASE_BRANCH${NC}"; fi
else
    echo -e "${YELLOW}→ Will close up to $COUNT item(s)${NC}"
    if $CLOSE_ISSUES; then echo -e "${YELLOW}→ Close Issues : yes${NC}"; fi
    if $CLOSE_PRS; then echo -e "${YELLOW}→ Close PRs    : yes${NC}"; fi
fi
echo ""

if ! prompt_yn "${YELLOW}Proceed? [y/N]: ${NC}" "n"; then
    echo
    echo -e "${RED}Aborted.${NC}"
    exit 1
fi
echo

# ────────────────────────────────────────────────
# Create or close items
# ────────────────────────────────────────────────
echo -e "${BLUE}Starting...${NC}"
echo ""

START_TIME=$SECONDS
CREATED_ISSUES=0
CREATED_PRS=0
CLOSED_ISSUES=0
CLOSED_PRS=0
FAILED=0

if [[ "$MODE" == "1" ]]; then
    ORIGINAL_BRANCH="$(git branch --show-current)"
    PR_DRAFT_ARGS=()
    if $DRAFT_PRS; then
        PR_DRAFT_ARGS+=(--draft)
    fi

    for ((i = 1; i <= COUNT; i++)); do
        ISSUE_IDX=$(( (i - 1) % TOTAL_ISSUES ))
        PR_IDX=$(( (i - 1) % TOTAL_PRS ))

        if $CREATE_ISSUES; then
            TITLE="${ISSUE_TITLES[$ISSUE_IDX]}"
            AREA="$(pick_random ISSUE_AREAS)"
            PRIORITY="$(pick_random ISSUE_PRIORITIES)"
            BODY=$"Summary\n- Observed an inconsistency in ${AREA}.\n- Needs investigation and a stable fix path.\n\nPriority\n- ${PRIORITY}\n\nAcceptance Criteria\n- Reproduction steps documented\n- Root cause identified\n- Tests added or updated"

            if [[ -n "$ISSUE_CUSTOM_TEXT" ]]; then
                BODY+=$"\n\nAdditional Context\n${ISSUE_CUSTOM_TEXT}"
            fi

            BODY+=$"\n\n<!-- ${TRACK_MARKER} -->"

            if "$GH_CMD" issue create "${REPO_ARGS[@]}" \
                --title "$TITLE" \
                --body "$BODY" >/dev/null 2>&1; then
                ((CREATED_ISSUES+=1))
            else
                ((FAILED+=1))
            fi
        fi

        if $CREATE_PRS; then
            TITLE="${PR_TITLES[$PR_IDX]}"
            SLUG="$(slugify "$TITLE")"
            KIND="$(pick_random PR_TYPES)"
            SCOPE="$(pick_random PR_SCOPES)"
            RAND="$(printf '%04d' $(( RANDOM % 10000 )))"
            BRANCH="${KIND}/${SLUG}-${RAND}"
            VALIDATION="$(pick_random PR_VALIDATIONS)"

            BODY=$"## Summary\n- Improves ${SCOPE} reliability and developer workflow.\n- Includes a focused and low-risk change set.\n\n## What Changed\n- Refined implementation details in ${SCOPE}.\n- Added/update notes for maintainability.\n\n## Validation\n- ${VALIDATION}\n- No intentional breaking changes."

            if [[ -n "$PR_CUSTOM_TEXT" ]]; then
                BODY+=$"\n\n## Additional Notes\n${PR_CUSTOM_TEXT}"
            fi

            BODY+=$"\n\n<!-- ${TRACK_MARKER} -->"

            NOTE_DIR=".automation/seed-notes"
            NOTE_FILE="${NOTE_DIR}/${BRANCH//\//_}.md"
            mkdir -p "$NOTE_DIR"
            {
                echo "# Seed note"
                echo ""
                echo "PR: $TITLE"
                echo "Scope: $(pick_random ISSUE_AREAS)"
                echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
            } > "$NOTE_FILE"

            if git checkout -q -B "$BRANCH" "$BASE_BRANCH" \
                && git add "$NOTE_FILE" \
                && git commit -m "$TITLE" --quiet \
                && git push -u origin "$BRANCH" --quiet \
                && "$GH_CMD" pr create "${REPO_ARGS[@]}" \
                    --title "$TITLE" \
                    --body "$BODY" \
                    --base "$BASE_BRANCH" \
                    --head "$BRANCH" \
                    "${PR_DRAFT_ARGS[@]}" >/dev/null 2>&1; then
                ((CREATED_PRS+=1))
            else
                ((FAILED+=1))
            fi

            git checkout -q "$ORIGINAL_BRANCH" || true
        fi

        if (( i % 10 == 0 )) || (( i == COUNT )); then
            PCT=$(( i * 100 / COUNT ))
            ELAPSED=$(( SECONDS - START_TIME ))
            echo -e "  ${GREEN}[${i}/${COUNT}]${NC} ${PCT}% — ${ELAPSED}s  (issues: $CREATED_ISSUES | prs: $CREATED_PRS | failed: $FAILED)"
        fi

        sleep "$PUSH_DELAY"
    done

    git checkout -q "$ORIGINAL_BRANCH" || true
else
    if $CLOSE_ISSUES; then
        echo -e "${BLUE}Preview issues to close:${NC}"
        "$GH_CMD" issue list "${REPO_ARGS[@]}" --state open --limit "$COUNT" --search "${CLOSE_FILTER} in:body" --json number,title --jq '.[] | "#\(.number)  \(.title)"' || true
        mapfile -t ISSUE_NUMS < <("$GH_CMD" issue list "${REPO_ARGS[@]}" --state open --limit "$COUNT" --search "${CLOSE_FILTER} in:body" --json number --jq '.[].number')
        if [[ ${#ISSUE_NUMS[@]} -eq 0 ]]; then
            echo -e "${YELLOW}No matching open issues found.${NC}"
        fi
        if [[ ${#ISSUE_NUMS[@]} -gt 0 ]] && ! prompt_yn "${YELLOW}Close these ${#ISSUE_NUMS[@]} issue(s)? [y/N]: ${NC}" "n"; then
            ISSUE_NUMS=()
        fi
        for n in "${ISSUE_NUMS[@]}"; do
            if "$GH_CMD" issue close "${REPO_ARGS[@]}" "$n" >/dev/null 2>&1; then
                ((CLOSED_ISSUES+=1))
            else
                ((FAILED+=1))
            fi
        done
    fi

    if $CLOSE_PRS; then
        PR_QUERY=""
        if [[ -n "$PR_NUMBERS_CSV" ]]; then
            mapfile -t PR_NUMS < <(parse_csv_numbers "$PR_NUMBERS_CSV")
            echo -e "${BLUE}Using explicit PR numbers:${NC} ${PR_NUMS[*]:-none}"
        else
            case "$PR_CLOSE_MODE" in
                1) PR_QUERY="${CLOSE_FILTER} in:body" ;;
                2) PR_QUERY="" ;;
                3) PR_QUERY="${PR_TITLE_KEYWORD} in:title" ;;
                4) PR_QUERY="author:${PR_AUTHOR}" ;;
                5) PR_QUERY="" ;;
            esac

            echo -e "${BLUE}Preview PRs to close:${NC}"
            if [[ "$PR_CLOSE_MODE" == "2" ]]; then
                "$GH_CMD" pr list "${REPO_ARGS[@]}" --state open --limit 200 --json number,title,headRefName --jq --arg p "$PR_HEAD_PREFIX" '.[] | select(.headRefName | startswith($p)) | "#\(.number)  \(.title)  [\(.headRefName)]"' || true
                mapfile -t PR_NUMS < <("$GH_CMD" pr list "${REPO_ARGS[@]}" --state open --limit 200 --json number,headRefName --jq --arg p "$PR_HEAD_PREFIX" '.[] | select(.headRefName | startswith($p)) | .number')
            elif [[ -n "$PR_QUERY" ]]; then
                "$GH_CMD" pr list "${REPO_ARGS[@]}" --state open --limit "$COUNT" --search "$PR_QUERY" --json number,title,headRefName --jq '.[] | "#\(.number)  \(.title)  [\(.headRefName)]"' || true
                mapfile -t PR_NUMS < <("$GH_CMD" pr list "${REPO_ARGS[@]}" --state open --limit "$COUNT" --search "$PR_QUERY" --json number --jq '.[].number')
            else
                "$GH_CMD" pr list "${REPO_ARGS[@]}" --state open --limit "$COUNT" --json number,title,headRefName --jq '.[] | "#\(.number)  \(.title)  [\(.headRefName)]"' || true
                mapfile -t PR_NUMS < <("$GH_CMD" pr list "${REPO_ARGS[@]}" --state open --limit "$COUNT" --json number --jq '.[].number')
            fi
        fi

        if [[ ${#PR_NUMS[@]} -eq 0 ]]; then
            echo -e "${YELLOW}No matching open PRs found.${NC}"
        fi
        if [[ ${#PR_NUMS[@]} -gt 0 ]] && ! prompt_yn "${YELLOW}Close these ${#PR_NUMS[@]} PR(s)? [y/N]: ${NC}" "n"; then
            PR_NUMS=()
        fi
        for n in "${PR_NUMS[@]}"; do
            if "$GH_CMD" pr close "${REPO_ARGS[@]}" "$n" --delete-branch >/dev/null 2>&1; then
                ((CLOSED_PRS+=1))
            else
                ((FAILED+=1))
            fi
        done
    fi
fi

TOTAL_TIME=$(( SECONDS - START_TIME ))

echo ""
echo -e "${GREEN}✓ Done!${NC}"
if [[ "$MODE" == "1" ]]; then
    echo -e "  Created ${GREEN}$CREATED_ISSUES${NC} issues"
    echo -e "  Created ${GREEN}$CREATED_PRS${NC} draft PRs"
else
    echo -e "  Closed ${GREEN}$CLOSED_ISSUES${NC} issues"
    echo -e "  Closed ${GREEN}$CLOSED_PRS${NC} PRs"
fi
echo -e "  Failed  ${RED}$FAILED${NC} operations"
echo -e "  Total time: ${TOTAL_TIME}s"
echo ""
echo -e "${CYAN}Tip:${NC}  gh issue list --search \"${TRACK_MARKER} in:body\""
echo -e "${CYAN}      gh pr list   --search \"${TRACK_MARKER} in:body\"${NC}"
echo ""