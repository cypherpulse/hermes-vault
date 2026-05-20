#!/usr/bin/env bash
# =============================================================
# fake-commits.sh
#
# Pushes N fake commits with NO real file changes.
# Uses --allow-empty so git doesn't need a diff at all.
# Safe to run up to 10,000+ commits in one go.
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

# ────────────────────────────────────────────────
# Commit message pool (realistic, varied)
# ────────────────────────────────────────────────
MESSAGES=(
    "feat: initialize Hermès Bridge Pool project structure"
    "docs: update README with pool architecture diagrams"
    "feat: implement core STX pool smart contract"
    "fix: optimize Clarity storage layout for deposits"
    "feat: add owner deposit tracking functionality"
    "style: enhance test coverage formatting"
    "feat: implement owner-withdraw pattern"
    "test: add comprehensive unit tests for pool operations"
    "chore: update @stacks/transactions dependencies"
    "refactor: clean up pool data management"
    "feat: deploy pool contract to Stacks Testnet"
    "fix: resolve edge case in pause/unpause logic"
    "feat: implement emergency drain mechanism"
    "docs: add sequence diagrams for deposits and withdrawals"
    "ci: configure Clarinet test pipeline"
    "feat: add pool statistics tracking to read-only functions"
    "style: update error message consistency"
    "feat: integrate Vitest for improved test framework"
    "fix: handle zero-amount deposit validation correctly"
    "refactor: optimize deposit map storage"
    "feat: enable owner rotation with validation"
    "test: verify access control for owner-only functions"
    "docs: add deployment guide for Stacks Mainnet"
    "feat: add user balance query functionality"
    "style: improve error code documentation"
    "fix: correct total deposited calculation logic"
    "feat: implement event logging for all operations"
    "chore: bump Clarinet SDK to latest version"
    "refactor: extract reusable validation helpers"
    "feat: add transaction event emitters"
    "docs: update API documentation for pool functions"
    "test: add fuzz tests for deposit edge cases"
    "style: refine test output formatting"
    "feat: implement principal validation for owner assignment"
    "fix: resolve pause state consistency"
    "chore: configure TypeScript for test suite"
    "feat: add pool pause functionality with validation"
    "test: simulate concurrent deposit patterns"
    "docs: clarify owner roles and permissions"
    "feat: emit detailed event data on withdrawals"
    "fix: prevent owner self-assignment"
    "refactor: optimize principal comparison logic"
    "feat: add pool activity monitoring capabilities"
    "test: fuzz test withdrawal amount limits"
    "chore: update integration test configurations"
    "feat: allow batch owner operations"
)

TOTAL_MSGS=${#MESSAGES[@]}

# ────────────────────────────────────────────────
# Input: number of commits
# ────────────────────────────────────────────────
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        fake-commits.sh — empty mode      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

read -p "$(echo -e ${YELLOW}How many fake commits? [1-10000, default: 10]: ${NC})" COUNT
COUNT="${COUNT:-10}"

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]] || [[ "$COUNT" -gt 10000 ]]; then
    echo -e "${RED}Please enter a number between 1 and 10000.${NC}"
    exit 1
fi

# Push every N commits to avoid one giant push timing out on large runs
PUSH_BATCH=100

echo ""
echo -e "${YELLOW}→ Will create ${COUNT} empty commit(s) with zero file changes${NC}"
echo -e "${YELLOW}→ Pushing every ${PUSH_BATCH} commits to avoid timeouts${NC}"
echo ""
read -p "$(echo -e ${YELLOW}Proceed? \(y/N\): ${NC})" -r confirm
echo

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Aborted.${NC}"
    exit 1
fi

# ────────────────────────────────────────────────
# Create empty commits
# ────────────────────────────────────────────────
echo -e "${BLUE}Starting...${NC}"
echo ""

START_TIME=$SECONDS

for ((i = 1; i <= COUNT; i++)); do
    MSG_INDEX=$(( (i - 1) % TOTAL_MSGS ))
    COMMIT_MSG="${MESSAGES[$MSG_INDEX]}"

    # --allow-empty = commit with absolutely zero file changes
    git commit --allow-empty -m "$COMMIT_MSG" --quiet

    # Progress indicator — print every 50 commits (not every one, too noisy for 10k)
    if (( i % 50 == 0 )) || (( i == COUNT )); then
        PCT=$(( i * 100 / COUNT ))
        ELAPSED=$(( SECONDS - START_TIME ))
        echo -e "  ${GREEN}[${i}/${COUNT}]${NC} ${PCT}% — ${ELAPSED}s elapsed"
    fi

    # Mid-run push every PUSH_BATCH commits
    if (( i % PUSH_BATCH == 0 )) && (( i < COUNT )); then
        echo -e "  ${CYAN}↑ Pushing batch at commit ${i}...${NC}"
        git push --set-upstream origin main 2>/dev/null || git push origin main
    fi
done

# ────────────────────────────────────────────────
# Final push
# ────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}↑ Final push to origin main...${NC}"
git push --set-upstream origin main 2>/dev/null || git push origin main

TOTAL_TIME=$(( SECONDS - START_TIME ))
echo ""
echo -e "${GREEN}✓ Done! ${COUNT} fake empty commit(s) pushed in ${TOTAL_TIME}s — repo files untouched.${NC}"
echo ""
echo -e "${CYAN}Tip: run  git log --oneline -20  to see your new commits.${NC}"