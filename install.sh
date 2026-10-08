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

# 옛 게이트가 설치본의 .gitignore 에 덧붙여 둔 줄을 되돌린다. 남아 있으면 .gitignore 를 바꾸는
# 버전으로 올라가지 못하고, 자동 업데이트가 막힌 설치본을 푸는 길이 이 스크립트다.
# 아래 두 정의는 bin/mangolove 의 것과 글자 그대로 같다(이 스크립트는 설치 전에도 돌아 그 파일을
# 못 쓴다). 같은지는 tests/mangolove.bats 가 고정한다.
GATE_IGNORE_LINES='\.gitignore|dod\.sh|\.dod-gate-attempts|\.review-ledger|\.review-ledger\.base|\.review-skip|\.review-covered'
_ml_heal_install_gitignore() {
    local dir="${1:-$MANGOLOVE_DIR}" changes extra
    [ -e "$dir/.git" ] && [ -f "$dir/.gitignore" ] || return 0
    # 수정이 없거나 추적하지 않는 파일이면 diff 가 조용히 0 을 낸다
    git -C "$dir" diff --quiet -- .gitignore 2>/dev/null && return 0
    # 로컬 수정이 "게이트 줄이 더해진 것"뿐일 때만 되돌린다. 지워진 줄이 하나라도 있거나, 더해진 줄
    # 중에 게이트 줄이 아닌 것이 있으면 사용자가 손댄 파일이므로 건드리지 않는다.
    changes="$(git -C "$dir" diff --unified=0 -- .gitignore 2>/dev/null \
        | grep -E '^[+-]' | grep -vE '^(\+\+\+ b/|--- a/)' || true)"
    case $'\n'"$changes" in *$'\n'-*) return 0 ;; esac
    extra="$(printf '%s\n' "$changes" | sed -n 's/^+//p' | grep -vxE "$GATE_IGNORE_LINES" || true)"
    [ -z "$(printf '%s' "$extra" | tr -d '[:space:]')" ] || return 0
    git -C "$dir" checkout -q -- .gitignore 2>/dev/null || true
}

# ─── Install or Update ───
if [ -d "$MANGOLOVE_DIR/.git" ]; then
    echo -e "${Y}Existing installation found. Updating...${R}"
    cd "$MANGOLOVE_DIR"
    _ml_heal_install_gitignore "$MANGOLOVE_DIR"
    # FETCH_HEAD: 추적 참조(origin/main)는 클론 설정에 따라 갱신되지 않을 수 있다.
    # --ff-only: 올릴 수 없으면 설치본을 건드리지 않고 실패한다. autostash 는 전역 설정에 켜져
    # 있어도 끈다: 되돌리다 충돌하면 성공으로 끝나면서 파일에 충돌 표시를 남긴다.
    if ! git fetch origin main; then
        echo ""
        echo -e "${Y}원격에서 받아 오지 못했습니다. 네트워크와 인증을 확인하세요.${R}"
        exit 1
    fi
    if ! git -c merge.autostash=false merge --ff-only FETCH_HEAD; then
        echo ""
        echo -e "${Y}받아 온 버전으로 올리지 못했습니다. 위의 git 메시지가 원인입니다.${R}"
        echo "  직접 고친 파일이 있으면 옮겨 두거나 되돌린 뒤 다시 실행하세요: git -C \"$MANGOLOVE_DIR\" status"
        exit 1
    fi
    echo -e "${G}✓${R} Updated to latest version."
else
    if [ -d "$MANGOLOVE_DIR" ]; then
        # Existing non-git mangolove dir: back it up
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
# Extract version from the main script
INSTALL_VERSION=$(grep -m1 '^MANGOLOVE_VERSION=' "$MANGOLOVE_DIR/bin/mangolove" | cut -d'"' -f2)
echo "${INSTALL_VERSION:-0.5.0}" > "$MANGOLOVE_DIR/.version"

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
