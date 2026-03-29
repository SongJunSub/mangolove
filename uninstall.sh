#!/bin/bash
# ─────────────────────────────────────────────
# 🥭 MangoLove Uninstaller
# ─────────────────────────────────────────────

set -e

R='\033[0m'
B='\033[1m'
DIM='\033[2m'
Y='\033[38;5;220m'
G='\033[38;5;113m'
RED='\033[38;5;203m'

MANGOLOVE_DIR="$HOME/.mangolove"
BIN_LINK="$HOME/.local/bin/mangolove"

echo ""
echo -e "${Y}${B}🥭 MangoLove Uninstaller${R}"
echo ""

read -p "Are you sure you want to uninstall MangoLove? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""

# Remove symlink
if [ -L "$BIN_LINK" ]; then
    rm "$BIN_LINK"
    echo -e "  ${G}✓${R} Removed symlink: $BIN_LINK"
fi

# Remove installation
if [ -d "$MANGOLOVE_DIR" ]; then
    # Ask about preserving user data
    read -p "Keep project profiles and work logs? [Y/n] " keep_data
    if [[ "$keep_data" == [nN] ]]; then
        rm -rf "$MANGOLOVE_DIR"
        echo -e "  ${G}✓${R} Removed: $MANGOLOVE_DIR (all data)"
    else
        # Remove only program files, keep user data
        rm -rf "$MANGOLOVE_DIR/bin"
        rm -rf "$MANGOLOVE_DIR/lib"
        rm -rf "$MANGOLOVE_DIR/prompts"
        rm -rf "$MANGOLOVE_DIR/docs"
        rm -f "$MANGOLOVE_DIR/.git" 2>/dev/null
        rm -rf "$MANGOLOVE_DIR/.git" 2>/dev/null
        echo -e "  ${G}✓${R} Removed program files"
        echo -e "  ${DIM}  Kept: projects/, logs/, config.sh${R}"
    fi
fi

echo ""
echo -e "${G}${B}✅ MangoLove uninstalled.${R}"
echo ""
