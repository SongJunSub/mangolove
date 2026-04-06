#!/bin/bash
# ─────────────────────────────────────────────
# 🥭 MangoLove Installer
# https://github.com/SongJunSub/mangolove
# ─────────────────────────────────────────────

set -e

# Colors
R='\033[0m'
B='\033[1m'
DIM='\033[2m'
Y='\033[38;5;220m'
O='\033[38;5;208m'
G='\033[38;5;113m'
P='\033[38;5;205m'
RED='\033[38;5;203m'

MANGOLOVE_DIR="$HOME/.mangolove"
BIN_DIR="$HOME/.local/bin"
REPO_URL="https://github.com/SongJunSub/mangolove.git"

echo ""
echo -e "${O}${B}"
cat << 'BANNER'
    ╔═══════════════════════════════════════════╗
    ║                                           ║
    ║   🥭 MangoLove Installer                  ║
    ║   Autonomous Development Agent            ║
    ║                                           ║
    ╚═══════════════════════════════════════════╝
BANNER
echo -e "${R}"

# ─── Check prerequisites ───
echo -e "${DIM}Checking prerequisites...${R}"

if ! command -v git &> /dev/null; then
    echo -e "${RED}✗ Git is required but not installed.${R}"
    exit 1
fi
echo -e "  ${G}✓${R} Git"

if ! command -v claude &> /dev/null; then
    echo -e "  ${RED}✗ Claude Code is required but not installed.${R}"
    echo -e "    Install from: ${Y}https://claude.ai/claude-code${R}"
    exit 1
fi
echo -e "  ${G}✓${R} Claude Code ($(claude --version 2>/dev/null))"

if command -v gh &> /dev/null; then
    echo -e "  ${G}✓${R} GitHub CLI (optional, for work logging)"
else
    echo -e "  ${Y}△${R} GitHub CLI not found (optional, for work logging)"
fi

echo ""

# ─── Install or Update ───
if [ -d "$MANGOLOVE_DIR/.git" ]; then
    echo -e "${Y}Existing installation found. Updating...${R}"
    cd "$MANGOLOVE_DIR"
    git pull origin main
    echo -e "${G}✓${R} Updated to latest version."
else
    if [ -d "$MANGOLOVE_DIR" ]; then
        # Existing non-git mangolove dir — back it up
        echo -e "${Y}Backing up existing ~/.mangolove...${R}"
        BACKUP_DIR="$MANGOLOVE_DIR.backup.$(date +%s)"
        mv "$MANGOLOVE_DIR" "$BACKUP_DIR"
        echo -e "  ${DIM}Backed up to: $BACKUP_DIR${R}"
    fi

    echo -e "Installing MangoLove..."
    git clone "$REPO_URL" "$MANGOLOVE_DIR"

    # Restore user data from backup if exists
    if [ -n "${BACKUP_DIR:-}" ] && [ -d "$BACKUP_DIR" ]; then
        # Restore projects
        if [ -d "$BACKUP_DIR/projects" ]; then
            cp -n "$BACKUP_DIR/projects"/*.md "$MANGOLOVE_DIR/projects/" 2>/dev/null || true
            echo -e "  ${G}✓${R} Restored project profiles"
        fi
        # Restore config
        if [ -f "$BACKUP_DIR/config.sh" ]; then
            cp "$BACKUP_DIR/config.sh" "$MANGOLOVE_DIR/config.sh"
            echo -e "  ${G}✓${R} Restored user config"
        fi
        # Restore logs
        if [ -d "$BACKUP_DIR/logs" ]; then
            cp -r "$BACKUP_DIR/logs" "$MANGOLOVE_DIR/logs"
            echo -e "  ${G}✓${R} Restored work logs"
        fi
    fi
fi

# ─── Create user directories ───
mkdir -p "$MANGOLOVE_DIR/projects"
mkdir -p "$MANGOLOVE_DIR/logs"

# ─── Create default config if not exists ───
if [ ! -f "$MANGOLOVE_DIR/config.sh" ]; then
    cp "$MANGOLOVE_DIR/config.sh.default" "$MANGOLOVE_DIR/config.sh" 2>/dev/null || true
fi

# ─── Make scripts executable ───
chmod +x "$MANGOLOVE_DIR/bin/mangolove"
chmod +x "$MANGOLOVE_DIR/lib/"*.sh

# ─── Symlink to PATH ───
mkdir -p "$BIN_DIR"
ln -sf "$MANGOLOVE_DIR/bin/mangolove" "$BIN_DIR/mangolove"
ln -sf "$MANGOLOVE_DIR/bin/mangolove" "$BIN_DIR/MangoLove"

# ─── Install shell completions ───
SHELL_NAME=$(basename "$SHELL")
case "$SHELL_NAME" in
    zsh)
        # Zsh completions
        ZSH_COMP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
        mkdir -p "$ZSH_COMP_DIR"
        ln -sf "$MANGOLOVE_DIR/completions/_mangolove" "$ZSH_COMP_DIR/_mangolove"
        echo -e "  ${G}✓${R} Zsh completions installed"
        ;;
    bash)
        # Bash completions
        BASH_COMP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
        mkdir -p "$BASH_COMP_DIR"
        ln -sf "$MANGOLOVE_DIR/completions/mangolove.bash" "$BASH_COMP_DIR/mangolove"
        echo -e "  ${G}✓${R} Bash completions installed"
        ;;
esac

# ─── Check PATH ───
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo -e "${Y}⚠️  $BIN_DIR is not in your PATH.${R}"
    echo ""

    SHELL_NAME=$(basename "$SHELL")
    RC_FILE=""
    case "$SHELL_NAME" in
        zsh)  RC_FILE="$HOME/.zshrc" ;;
        bash) RC_FILE="$HOME/.bashrc" ;;
        *)    RC_FILE="$HOME/.profile" ;;
    esac

    echo -e "  Add this line to ${B}${RC_FILE}${R}:"
    echo ""
    echo -e "    ${G}export PATH=\"\$HOME/.local/bin:\$PATH\"${R}"
    echo ""
    echo -e "  Then run: ${DIM}source ${RC_FILE}${R}"
fi

# ─── Version file ───
echo "0.2.0" > "$MANGOLOVE_DIR/.version"

# ─── Done ───
echo ""
echo -e "${DIM}──────────────────────────────────────${R}"
echo -e "${G}${B}✅ MangoLove installed successfully!${R}"
echo -e "${DIM}──────────────────────────────────────${R}"
echo ""
echo -e "  ${O}Quick start:${R}"
echo -e "    ${G}mangolove${R}              Start interactive session"
echo -e "    ${G}mangolove help${R}         Show all commands"
echo -e "    ${G}mangolove doctor${R}       Check installation"
echo -e "    ${G}mangolove log init${R}     Setup work logging"
echo ""
echo -e "  ${O}Config:${R} ${DIM}~/.mangolove/config.sh${R}"
echo -e "  ${O}Docs:${R}   ${DIM}https://github.com/SongJunSub/mangolove${R}"
echo ""
echo -e "  ${P}♥${R} ${Y}${B}Happy coding with MangoLove!${R} ${O}🥭${R}"
echo ""
