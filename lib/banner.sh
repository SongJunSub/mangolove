#!/bin/bash
# ─────────────────────────────────────────────
# 🥭 MangoLove — Banner Display
# Mango:  happy Jindo, cream face, yellowish ear tips, tongue out
# Sarang: calm Jindo, pure white, mouth closed, composed
# ─────────────────────────────────────────────

MANGOLOVE_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}"

# Reset / styles
R=$'\033[0m'
B=$'\033[1m'
DIM=$'\033[2m'
IT=$'\033[3m'

# UI foreground
FO=$'\033[38;5;208m'
FY=$'\033[38;5;220m'
FP=$'\033[38;5;205m'
FG=$'\033[38;5;113m'
FC=$'\033[38;5;117m'
FW=$'\033[38;5;255m'
FGR=$'\033[38;5;245m'
FBW=$'\033[97m'

# ── Mango (background fills) ──
mE=$'\033[48;5;180m'    # ear outer (warm cream-yellow)
mI=$'\033[48;5;138m'    # ear inner (rosy brown)
mF=$'\033[48;5;230m'    # face (cream ivory)
mY=$'\033[48;5;223m'    # cheek patches (soft yellow)
mT=$'\033[48;5;218m'    # tongue (pink)

# ── Sarang (background fills) ──
sE=$'\033[48;5;255m'    # ear outer (bright white)
sI=$'\033[48;5;181m'    # ear inner (light mauve)
sF=$'\033[48;5;231m'    # face (pure white)

# ── Shared (foreground for features on bg) ──
fK=$'\033[38;5;16m'     # black — eyes
fN=$'\033[38;5;52m'     # dark brown — nose
fT=$'\033[38;5;211m'    # deep pink — tongue ω / ‿
fG=$'\033[38;5;245m'    # gray — sarang closed mouth

# ── Build mango rows (each = exactly 11 visible chars) ──
#     Col: 0  1  2  3  4  5  6  7  8  9  10

# Row 0: ear tips — _  E  _  _  _  _  _  _  _  E  _
M0=" ${mE} ${R}       ${mE} ${R} "

# Row 1: ears — E  I  E  _  _  _  _  _  E  I  E
M1="${mE} ${mI} ${mE} ${R}     ${mE} ${mI} ${mE} ${R}"

# Row 2: ears + face top — E  I  F  F  F  F  F  F  F  I  E
M2="${mE} ${mI} ${mF}       ${mI} ${mE} ${R}"

# Row 3: forehead — _  F  F  F  F  F  F  F  F  F  _
M3=" ${mF}         ${R} "

# Row 4: eyes — _  F  ◕  F  F  F  F  F  ◕  F  _
M4=" ${mF} ${fK}◕     ◕ ${R} "

# Row 5: nose + yellow patches — _  Y  F  F  F  ▾  F  F  F  Y  _
M5=" ${mY} ${mF}   ${fN}▾   ${mY} ${R} "

# Row 6: mouth — _  _  F  T  T  ω  T  T  F  _  _
M6="  ${mF} ${mT}  ${fT}ω  ${mF} ${R}  "

# Row 7: tongue — _  _  _  T  ‿  ‿  ‿  T  _  _  _
M7="   ${mT} ${fT}‿‿‿ ${R}   "

# Row 8: chin — _  _  _  _  F  F  F  _  _  _  _
M8="    ${mF}   ${R}    "

# ── Build sarang rows (each = exactly 11 visible chars) ──

# Row 0: ear tips
S0=" ${sE} ${R}       ${sE} ${R} "

# Row 1: ears
S1="${sE} ${sI} ${sE} ${R}     ${sE} ${sI} ${sE} ${R}"

# Row 2: ears + face top
S2="${sE} ${sI} ${sF}       ${sI} ${sE} ${R}"

# Row 3: forehead
S3=" ${sF}         ${R} "

# Row 4: eyes
S4=" ${sF} ${fK}◕     ◕ ${R} "

# Row 5: nose (no yellow patches)
S5=" ${sF}    ${fN}▾    ${R} "

# Row 6: closed mouth — _  _  F  F  F  ω  F  F  F  _  _
S6="  ${sF}   ${fG}ω   ${R}  "

# Row 7: lower face — _  _  _  F  F  F  F  F  _  _  _
S7="   ${sF}     ${R}   "

# Row 8: chin
S8="    ${sF}   ${R}    "

# ── Gap / hearts (each = exactly 10 visible chars) ──
GE="          "
GH1="    ${FP}♥♥${R}    "
GH2="   ${FP}♥${R}  ${FP}♥${R}   "
GH3="    ${FP}♥♥${R}    "
GH4="     ${FP}♥${R}    "

# ── Layout: 8 left + 11 mango + 10 gap + 11 sarang + 18 right = 58 ──
L="        "   # 8 spaces left
T="                  "  # 18 spaces right
V="${FO}${B}│${R}"  # vertical border

printf '\033c'

# ── Title ──
cat << 'FRAME_TOP'
    ╭──────────────────────────────────────────────────────────╮
FRAME_TOP

cat << EOF
    ${V}                                                          ${V}
    ${V}   ${FY}${B}  ╔╦╗╔═╗╔╗╔╔═╗╔═╗  ${FP}${B}╦  ╔═╗╦  ╦╔═╗${R}                       ${V}
    ${V}   ${FY}${B}  ║║║╠═╣║║║║ ╦║ ║  ${FP}${B}║  ║ ║╚╗╔╝║╣${R}                        ${V}
    ${V}   ${FY}${B}  ╩ ╩╩ ╩╝╚╝╚═╝╚═╝  ${FP}${B}╩═╝╚═╝ ╚╝ ╚═╝${R}                       ${V}
    ${V}                                                          ${V}
EOF

# ── Dog art (9 rows) ──
echo "    ${V}${L}${M0}${GE}${S0}${T}${V}"
echo "    ${V}${L}${M1}${GE}${S1}${T}${V}"
echo "    ${V}${L}${M2}${GE}${S2}${T}${V}"
echo "    ${V}${L}${M3}${GH1}${S3}${T}${V}"
echo "    ${V}${L}${M4}${GH2}${S4}${T}${V}"
echo "    ${V}${L}${M5}${GH3}${S5}${T}${V}"
echo "    ${V}${L}${M6}${GH4}${S6}${T}${V}"
echo "    ${V}${L}${M7}${GE}${S7}${T}${V}"
echo "    ${V}${L}${M8}${GE}${S8}${T}${V}"

cat << EOF
    ${V}                                                          ${V}
    ${V}     ${FY}${IT}Mango${R} ${FGR}🥭${R}                      ${FBW}${IT}Sarang${R} ${FGR}🤍${R}              ${V}
    ${V}   ${FGR}${DIM}혀 내밀고 방긋!${R}           ${FGR}${DIM}차분하고 단정한 아이${R}         ${V}
    ${V}                                                          ${V}
    ${V}  ${FGR}${IT}    " Two Jindo dogs who inspired everything. "${R}         ${V}
    ${V}                                                          ${V}
EOF

cat << 'FRAME_BOT'
    ╰──────────────────────────────────────────────────────────╯
FRAME_BOT

# ── Version ──
VERSION="0.1.0"
[ -f "$MANGOLOVE_DIR/.version" ] && VERSION=$(cat "$MANGOLOVE_DIR/.version")

cat << EOF

    ${FP}${B}♥${R}  ${FO}${B}Mango${R}${FY}Love${R} ${FGR}v${VERSION}${R} ${DIM}— Autonomous Dev Agent${R}  ${FP}${B}♥${R}

    ${FGR}┌─────────────────────────────────────────┐${R}
EOF

# ── Session info ──
CURRENT_DIR=$(pwd)
echo "    ${FGR}│${R} ${FC}${B}⟩${R} ${FW}${B}User${R}      ${FGR}·${R} ${FG}$(whoami)${R}"
echo "    ${FGR}│${R} ${FC}${B}⟩${R} ${FW}${B}Directory${R} ${FGR}·${R} ${FG}${CURRENT_DIR}${R}"
echo "    ${FGR}│${R} ${FC}${B}⟩${R} ${FW}${B}Date${R}      ${FGR}·${R} ${FG}$(date '+%Y-%m-%d %H:%M')${R}"

PROJECT_NAME=""
for profile in "$MANGOLOVE_DIR/projects"/*.md; do
    [ "$(basename "$profile")" = "README.md" ] && continue
    [ ! -f "$profile" ] && continue
    PROFILE_PATH=$(grep "^path:" "$profile" 2>/dev/null | sed 's/^path: *//')
    if [ -n "$PROFILE_PATH" ] && [[ "$CURRENT_DIR" == "$PROFILE_PATH" || "$CURRENT_DIR" == "$PROFILE_PATH"/* ]]; then
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
