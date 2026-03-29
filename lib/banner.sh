#!/bin/bash
# ─────────────────────────────────────────────
# 🥭 MangoLove — Banner Display
# Named after two Jindo dogs:
#   🥭 Mango  — white with yellowish patches
#   🤍 Sarang — pure white
# ─────────────────────────────────────────────

MANGOLOVE_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}"

# Colors
R='\033[0m'
B='\033[1m'
DIM='\033[2m'
Y='\033[38;5;220m'    # Yellow (mango patches)
O='\033[38;5;208m'    # Orange
G='\033[38;5;113m'    # Green
P='\033[38;5;205m'    # Pink (love/heart)
W='\033[38;5;255m'    # White (sarang)
C='\033[38;5;117m'    # Cyan
BW='\033[97m'         # Bright white (sarang fur)
YB='\033[38;5;178m'   # Darker yellow (mango spots)

clear

echo ""
echo -e "${O}${B}"
cat << 'BANNER'
    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║   ███╗   ███╗ █████╗ ███╗   ██╗ ██████╗  ██████╗            ║
    ║   ████╗ ████║██╔══██╗████╗  ██║██╔════╝ ██╔═══██╗           ║
    ║   ██╔████╔██║███████║██╔██╗ ██║██║  ███╗██║   ██║           ║
    ║   ██║╚██╔╝██║██╔══██║██║╚██╗██║██║   ██║██║   ██║           ║
    ║   ██║ ╚═╝ ██║██║  ██║██║ ╚████║╚██████╔╝╚██████╔╝           ║
    ║   ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚═════╝           ║
    ║                                                              ║
    ║          ██╗      ██████╗ ██╗   ██╗███████╗                  ║
    ║          ██║     ██╔═══██╗██║   ██║██╔════╝                  ║
    ║          ██║     ██║   ██║██║   ██║█████╗                    ║
    ║          ██║     ██║   ██║╚██╗ ██╔╝██╔══╝                   ║
    ║          ███████╗╚██████╔╝ ╚████╔╝ ███████╗                 ║
    ║          ╚══════╝ ╚═════╝   ╚═══╝  ╚══════╝                 ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
BANNER
echo -e "${R}"

# ─── Mango & Sarang (two Jindo dogs) ───
echo -e "${DIM}          🥭 Mango                          🤍 Sarang${R}"
echo -e "        ${Y}╱▔▔╲${R}  ${Y}╱▔▔╲${R}                      ${BW}╱▔▔╲${R}  ${BW}╱▔▔╲${R}"
echo -e "       ${Y}╱${R}${YB}◆${R}${Y}▔▔${R}${YB}◆${R}${Y}▔▔╲${R}                    ${BW}╱${R}${W}◇${R}${BW}▔▔${R}${W}◇${R}${BW}▔▔╲${R}"
echo -e "      ${Y}│${R}  ${YB}●${R}  ${YB}●${R}  ${Y}│${R}      ${P}${B}♥${R}          ${BW}│${R}  ${C}●${R}  ${C}●${R}  ${BW}│${R}"
echo -e "      ${Y}│${R}   ${O}▽${R}    ${Y}│${R}    ${P}${B}♥${R} ${P}${B}♥${R}         ${BW}│${R}   ${P}▽${R}    ${BW}│${R}"
echo -e "       ${Y}╲▁${R}${YB}◠${R}${Y}▁▁╱${R}       ${P}${B}♥${R}            ${BW}╲▁${R}${W}◠${R}${BW}▁▁╱${R}"
echo -e "     ${Y}╱▔▔${R}${YB}░░${R}${Y}▔▔▔▔╲${R}                  ${BW}╱▔▔▔▔▔▔▔▔╲${R}"
echo -e "    ${Y}│${R} ${YB}░${R}${Y}│${R}        ${Y}│${R}                 ${BW}│${R}          ${BW}│${R}"
echo -e "    ${Y}╱  ╲${R}      ${Y}╱  ╲${R}                ${BW}╱  ╲${R}      ${BW}╱  ╲${R}"
echo -e "   ${Y}╱▔╲╱▔╲${R}    ${Y}╱▔╲╱▔╲${R}              ${BW}╱▔╲╱▔╲${R}    ${BW}╱▔╲╱▔╲${R}"
echo ""

# Version
VERSION="0.1.0"
if [ -f "$MANGOLOVE_DIR/.version" ]; then
    VERSION=$(cat "$MANGOLOVE_DIR/.version")
fi

echo -e "    ${P}${B}♥${R}  ${Y}${B}MangoLove${R} ${DIM}v${VERSION}${R}  ${P}${B}♥${R}"
echo -e "    ${DIM}Named after two Jindo dogs: ${Y}Mango${R}${DIM} & ${BW}Sarang${R}"
echo -e "    ${DIM}────────────────────────────────────────────${R}"
echo ""

# Session info
echo -e "    ${C}▸${R} ${W}${B}User${R}      ${DIM}:${R} ${G}$(whoami)${R}"
echo -e "    ${C}▸${R} ${W}${B}Directory${R} ${DIM}:${R} ${G}$(pwd)${R}"
echo -e "    ${C}▸${R} ${W}${B}Date${R}      ${DIM}:${R} ${G}$(date '+%Y-%m-%d %H:%M')${R}"

# Detect project
PROJECT_NAME=""
CURRENT_DIR=$(pwd)

for profile in "$MANGOLOVE_DIR/projects"/*.md; do
    [ "$(basename "$profile")" = "README.md" ] && continue
    [ ! -f "$profile" ] && continue
    PROFILE_PATH=$(grep "^path:" "$profile" 2>/dev/null | sed 's/^path: *//')
    if [ -n "$PROFILE_PATH" ] && [[ "$CURRENT_DIR" == "$PROFILE_PATH"* ]]; then
        PROJECT_NAME=$(grep "^name:" "$profile" 2>/dev/null | sed 's/^name: *//')
        break
    fi
done

if [ -n "$PROJECT_NAME" ]; then
    echo -e "    ${C}▸${R} ${W}${B}Project${R}   ${DIM}:${R} ${Y}${B}${PROJECT_NAME}${R} ${G}✓ Profile loaded${R}"
else
    echo -e "    ${C}▸${R} ${W}${B}Project${R}   ${DIM}:${R} ${DIM}New project — will auto-analyze${R}"
fi

# Git info
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
    CHANGES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    echo -e "    ${C}▸${R} ${W}${B}Branch${R}    ${DIM}:${R} ${G}${BRANCH}${R} ${DIM}(${CHANGES} changes)${R}"
fi

echo ""
echo -e "    ${DIM}────────────────────────────────────────────${R}"
echo -e "    ${O}🥭${R} ${DIM}Powered by Claude Code${R} ${P}♥${R} ${DIM}Ready to build${R}"
echo -e "    ${DIM}────────────────────────────────────────────${R}"
echo ""
