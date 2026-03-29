#!/bin/bash
# ─────────────────────────────────────────────
# 🥭 MangoLove — Banner Display
# Named after two Jindo dogs:
#   🥭 Mango  — white with yellowish patches, tongue out, happy
#   🤍 Sarang — pure white, calm and composed
# ─────────────────────────────────────────────

MANGOLOVE_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}"

R=$'\033[0m'
B=$'\033[1m'
DIM=$'\033[2m'
IT=$'\033[3m'

# Foreground only (no background = no alignment issues)
FO=$'\033[38;5;208m'    # Orange (frame)
FY=$'\033[38;5;220m'    # Yellow (mango title)
FP=$'\033[38;5;205m'    # Pink (hearts)
FG=$'\033[38;5;113m'    # Green
FC=$'\033[38;5;117m'    # Cyan
FW=$'\033[38;5;255m'    # White
FGR=$'\033[38;5;245m'   # Gray
FBW=$'\033[97m'         # Bright white

# Dog colors
MC=$'\033[38;5;230m'    # Mango cream body
MY=$'\033[38;5;180m'    # Mango yellow ear tips
MF=$'\033[38;5;223m'    # Mango face
ME=$'\033[38;5;137m'    # Mango ear inner
SW=$'\033[38;5;231m'    # Sarang pure white body
SE=$'\033[38;5;251m'    # Sarang ear inner
BK=$'\033[38;5;236m'    # Black (eyes, nose)
TG=$'\033[38;5;211m'    # Tongue pink
PK=$'\033[38;5;218m'    # Light pink

printf '\033c'

cat << 'TITLE'
    ╭──────────────────────────────────────────────────────────╮
TITLE

cat << EOF
    ${FO}${B}│${R}                                                          ${FO}${B}│${R}
    ${FO}${B}│${R}   ${FY}${B}  ╔╦╗╔═╗╔╗╔╔═╗╔═╗  ${FP}${B}╦  ╔═╗╦  ╦╔═╗${R}                  ${FO}${B}│${R}
    ${FO}${B}│${R}   ${FY}${B}  ║║║╠═╣║║║║ ╦║ ║  ${FP}${B}║  ║ ║╚╗╔╝║╣${R}                   ${FO}${B}│${R}
    ${FO}${B}│${R}   ${FY}${B}  ╩ ╩╩ ╩╝╚╝╚═╝╚═╝  ${FP}${B}╩═╝╚═╝ ╚╝ ╚═╝${R}                  ${FO}${B}│${R}
    ${FO}${B}│${R}                                                          ${FO}${B}│${R}
EOF

# ─── Jindo dogs ASCII art (foreground color only) ───
# Mango: happy face, tongue out, cream+yellow ears
# Sarang: calm face, mouth closed, pure white

cat << EOF
    ${FO}${B}│${R}     ${MY}/\\${R}             ${MY}/\\${R}              ${SW}/\\${R}             ${SW}/\\${R}     ${FO}${B}│${R}
    ${FO}${B}│${R}    ${MY}/${ME}.${MY}\\${R}           ${MY}/${ME}.${MY}\\${R}            ${SW}/${SE}.${SW}\\${R}           ${SW}/${SE}.${SW}\\${R}    ${FO}${B}│${R}
    ${FO}${B}│${R}   ${MY}/${ME}...${MY}\\${R}  ${MF}___${R}  ${MY}/${ME}...${MY}\\${R}          ${SW}/${SE}...${SW}\\${R}  ${SW}___${R}  ${SW}/${SE}...${SW}\\${R}   ${FO}${B}│${R}
    ${FO}${B}│${R}   ${MY}‾‾${MF}‾‾‾/     \\${MY}‾‾‾‾${R}          ${SW}‾‾${SW}‾‾‾/     \\${SW}‾‾‾‾${R}   ${FO}${B}│${R}
    ${FO}${B}│${R}     ${MF}|  ${BK}◕${MF}     ${BK}◕${MF}  |${R}  ${PK}♥${R}        ${SW}|  ${BK}◕${SW}     ${BK}◕${SW}  |${R}   ${FO}${B}│${R}
    ${FO}${B}│${R}     ${MF}|     ${BK}▾${MF}     |${R} ${FP}${B}♥${R}${PK}♥${R}       ${SW}|     ${BK}▾${SW}     |${R}   ${FO}${B}│${R}
    ${FO}${B}│${R}     ${MF}\\  ${TG}\\${R} ${TG}ω${R} ${TG}/${R}  ${MF}/${R}  ${FP}${B}♥${R}        ${SW}\\   ${FGR}— ${SE}ω${FGR} —${SW}   /${R}   ${FO}${B}│${R}
    ${FO}${B}│${R}      ${MF}\\  ${TG}‿‿‿${R}  ${MF}/${R}              ${SW}\\    ‿    /${R}    ${FO}${B}│${R}
    ${FO}${B}│${R}       ${MF}\\${MC}_____${MF}/${R}                ${SW}\\_______/${R}     ${FO}${B}│${R}
    ${FO}${B}│${R}                                                          ${FO}${B}│${R}
    ${FO}${B}│${R}     ${FY}${IT}Mango${R} ${FGR}🥭${R}                   ${FBW}${IT}Sarang${R} ${FGR}🤍${R}             ${FO}${B}│${R}
    ${FO}${B}│${R}   ${FGR}${DIM}혀 내밀고 방긋!${R}              ${FGR}${DIM}차분하고 단정한 아이${R}      ${FO}${B}│${R}
    ${FO}${B}│${R}                                                          ${FO}${B}│${R}
    ${FO}${B}│${R}  ${FGR}${IT}    " Two Jindo dogs who inspired everything. "${R}          ${FO}${B}│${R}
    ${FO}${B}│${R}                                                          ${FO}${B}│${R}
EOF

cat << 'BOTTOM'
    ╰──────────────────────────────────────────────────────────╯
BOTTOM

# Version
VERSION="0.1.0"
[ -f "$MANGOLOVE_DIR/.version" ] && VERSION=$(cat "$MANGOLOVE_DIR/.version")

cat << EOF

    ${FP}${B}♥${R}  ${FO}${B}Mango${R}${FY}Love${R} ${FGR}v${VERSION}${R} ${DIM}— Autonomous Dev Agent${R}  ${FP}${B}♥${R}

    ${FGR}┌─────────────────────────────────────────┐${R}
EOF

CURRENT_DIR=$(pwd)
echo "    ${FGR}│${R} ${FC}${B}⟩${R} ${FW}${B}User${R}      ${FGR}·${R} ${FG}$(whoami)${R}"
echo "    ${FGR}│${R} ${FC}${B}⟩${R} ${FW}${B}Directory${R} ${FGR}·${R} ${FG}${CURRENT_DIR}${R}"
echo "    ${FGR}│${R} ${FC}${B}⟩${R} ${FW}${B}Date${R}      ${FGR}·${R} ${FG}$(date '+%Y-%m-%d %H:%M')${R}"

PROJECT_NAME=""
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
    echo "    ${FGR}│${R} ${FC}${B}⟩${R} ${FW}${B}Project${R}   ${FGR}·${R} ${FY}${B}${PROJECT_NAME}${R} ${FG}✓${R}"
else
    echo "    ${FGR}│${R} ${FC}${B}⟩${R} ${FW}${B}Project${R}   ${FGR}·${R} ${FGR}${IT}auto-detecting...${R}"
fi

if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
    CHANGES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    echo "    ${FGR}│${R} ${FC}${B}⟩${R} ${FW}${B}Branch${R}    ${FGR}·${R} ${FG}${BRANCH}${R} ${FGR}(${CHANGES} changes)${R}"
fi

cat << EOF
    ${FGR}└─────────────────────────────────────────┘${R}

      ${FO}🥭${R} ${FGR}Powered by Claude Code${R}  ${FP}♥${R}  ${FGR}Ready to build${R}

EOF
