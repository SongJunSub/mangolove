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

# ── Braille Jindo dog art (from mangolove.png) ──
# Mango (left, yellow) — standing, tongue out
MANGO_ART=(
"⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⠢⣀⠀⠀⢀⣀⣠⣾⠁⢠⣶"
"⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⣿⣿⣿⣿⣿⣿⣷⣿⠋"
"⠀⠀⣀⣴⣶⣿⣶⣦⣄⠀⠀⠀⠀⠀⠀⠀⢨⣿⣿⣏⣹⣿⣿⣿⣴⣿⣿⠀"
"⠀⢴⣿⣿⠿⢿⣿⣿⣿⣧⣀⣀⣀⣀⣀⡀⣾⣿⣿⣿⣿⣿⠉⠉⢻⣿⣿⠃"
"⠀⣿⣿⣿⣦⡌⣻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡛⢀⣀⣸⣿⣿⠀"
"⠀⠻⣿⣿⠋⣷⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣯⡉⠙⠠⠈⣲⢭⣾⣿⡟⠀"
"⠀⠀⠉⠁⣸⣿⣿⣿⣿⣻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣦⢀⡀⠈⠉⣽⡇⠀"
"⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⠋⠹⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣇⣀⣿⠇⠀"
"⠀⠀⠀⠀⠸⣿⣿⣿⣿⢇⠀⠀⠈⠙⠻⠿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀"
"⠀⠀⠀⠀⠀⠻⣿⣿⠋⠀⠀⠀⠀⠀⠀⠀⠸⣿⣿⣿⣿⡟⠉⣿⣿⠃⠀⠀"
"⠀⠀⠀⠀⠀⠠⡉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⣿⣿⠏⠀⢰⣿⡟⠀⠀⠀"
"⠀⠀⠀⠀⠀⢸⡃⠀⠀⠀⠀⣆⠀⠀⠀⠀⠀⢸⣿⣿⠀⠀⣿⣿⠁⠀⠀⠀"
"⠀⠀⠀⠀⠀⢸⣧⠀⠀⠀⠀⠹⠶⠄⠀⠀⠀⠘⣟⣿⡆⠀⡸⠟⠀⠀⠀⠀"
"⠀⠀⠀⠀⠀⠘⠻⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢹⡏⡇⠀⠠⣄⠀⠀⠀⠀"
"⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣶⣶⢀⡐⠿⢶⢀⣀⣀"
)

# Sarang (right, white) — sitting, calm
SARANG_ART=(
"⣴⣶⡶⠾⠿⢿⣶⣶⣶⣶⣶⣶⣶⣶⣶⣶⣶⣶⣶⣦⣤⣤⣤⡀⠀⠀⠀⠀"
"⠉⠀⢷⣶⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣮⣽⣿⣿⣿⣿⣿⠀⠀⠀⠀"
"⠀⠀⠀⢹⣿⣿⣷⣤⣿⣿⣿⣿⣿⣥⣀⣨⣿⣿⣿⣻⡀⠉⠉⠋⠀⠀⠀⠀"
"⠀⠀⠀⢻⣿⣿⣿⣿⡏⠉⠉⠉⢻⣿⣿⣿⣿⣿⣿⣿⣷⠀⠀⠀⠀⠀⠀⠀"
"⠀⠀⠀⢿⣿⣿⣿⣿⣯⣄⣀⣠⣽⣿⣿⣿⣿⣿⣿⣿⣿⡄⠀⠀⠀⠀⠀⠀"
"⠀⠀⢠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣆⠀⠀⠀⠀⠀"
"⠀⢀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣄⠀⠀⠀"
"⠀⠀⢹⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣄⠀"
"⠀⠀⠈⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷"
"⠀⠀⠀⠘⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿"
"⠀⠀⠀⠀⠈⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿"
"⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿"
"⠀⠀⠀⠀⠀⠀⣿⣿⣻⣿⣽⣿⣿⣿⣿⣿⢧⣿⣿⣿⣿⠇⠟⠻⢿⣛⣿⣿"
"⠀⠀⠀⠀⠀⠀⣿⣿⣼⣿⣿⡿⣿⣿⣉⡽⣾⣿⣿⣿⡏⣴⣶⣿⣿⣿⣿⣿"
"⠀⣀⣀⣀⣀⡀⣿⣿⣾⣯⣭⣥⣶⣿⣿⢳⣿⣿⣿⡟⢺⣿⣿⣿⣿⣿⣿⣿"
)

V="${FO}${B}│${R}"  # vertical border

printf '\033c'

# ── Title (frame inner width: 68) ──
cat << 'FRAME_TOP'
    ╭────────────────────────────────────────────────────────────────────╮
FRAME_TOP

cat << EOF
    ${V}                                                                    ${V}
    ${V}            ${FY}${B}  ╔╦╗╔═╗╔╗╔╔═╗╔═╗  ${FP}${B}╦  ╔═╗╦  ╦╔═╗${R}                        ${V}
    ${V}            ${FY}${B}  ║║║╠═╣║║║║ ╦║ ║  ${FP}${B}║  ║ ║╚╗╔╝║╣${R}                         ${V}
    ${V}            ${FY}${B}  ╩ ╩╩ ╩╝╚╝╚═╝╚═╝  ${FP}${B}╩═╝╚═╝ ╚╝ ╚═╝${R}                        ${V}
    ${V}                                                                    ${V}
EOF

# ── Braille dog art (16 rows, 28+4+28=60 chars, centered in 68-char frame) ──
for i in "${!MANGO_ART[@]}"; do
    echo "    ${V}    ${FY}${MANGO_ART[$i]}${R}    ${FBW}${SARANG_ART[$i]}${R}    ${V}"
done

cat << EOF
    ${V}                                                                    ${V}
    ${V}          ${FY}${IT}Mango${R} ${FGR}🥭${R}    ${FGR}&${R}    ${FBW}${IT}Sarang${R} ${FGR}🤍${R}                                ${V}
    ${V}                                                                    ${V}
    ${V}     ${FGR}${IT}    " Two Jindo dogs who inspired everything. "${R}                ${V}
    ${V}                                                                    ${V}
EOF

cat << 'FRAME_BOT'
    ╰────────────────────────────────────────────────────────────────────╯
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
