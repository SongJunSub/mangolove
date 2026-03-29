# 🥭 MangoLove

**Your Autonomous Development Agent** — Powered by [Claude Code](https://claude.ai/claude-code)

MangoLove는 Claude Code 위에 구축된 자율형 개발 에이전트입니다. 프로젝트별 컨텍스트를 기억하고, 분석부터 코딩까지 알아서 처리합니다.

> **Why "MangoLove"?**
> 두 마리 진돗개의 이름에서 영감을 받았습니다.
> - 🥭 **Mango (망고)** — 하얀 털에 군데군데 누런 반점이 있는 진돗개
> - 🤍 **Sarang (사랑)** — 새하얀 털의 진돗개
>
> 망고(Mango) + 사랑(Love) = **MangoLove** 🐕🐕

## ✨ Features

- **🤖 Autonomous Execution** — 작업을 주면 분석 → 계획 → 실행 → 검증까지 자율 수행
- **📁 Project Profiles** — 프로젝트별 기술 스택, 컨벤션, 아키텍처를 기억하고 자동 적용
- **📝 Work Logging** — 작업 내역을 자동으로 GitHub private repo에 기록
- **🎨 Beautiful UI** — 터미널에서 실행 시 프로젝트 정보와 함께 깔끔한 배너 표시
- **🔌 Claude Code Compatible** — Claude Code의 모든 기능(`/commands`, MCP, hooks 등) 그대로 사용

## 📦 Installation

### Prerequisites

- [Claude Code](https://claude.ai/claude-code) 설치 필요 (`claude` 명령어가 PATH에 있어야 함)
- [GitHub CLI](https://cli.github.com/) (`gh`) — 작업 로그 기능 사용 시 필요
- Git

### Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/SongJunSub/mangolove/main/install.sh | bash
```

### Manual Install

```bash
git clone https://github.com/SongJunSub/mangolove.git ~/.mangolove
chmod +x ~/.mangolove/bin/mangolove
ln -sf ~/.mangolove/bin/mangolove ~/.local/bin/mangolove
```

> `~/.local/bin`이 PATH에 포함되어 있어야 합니다.
> 없다면: `export PATH="$HOME/.local/bin:$PATH"` 를 `~/.zshrc` 또는 `~/.bashrc`에 추가하세요.

### Verify Installation

```bash
mangolove --version
mangolove help
```

## 🚀 Usage

### Basic

```bash
# 인터랙티브 세션 시작
mangolove

# 바로 태스크 실행
mangolove "예약 API 리팩토링해줘"

# 마지막 세션 이어하기
mangolove -c

# 프린트 모드 (파이프용)
mangolove -p "이 코드 리뷰해줘"
```

### Project Profiles

```bash
# 등록된 프로젝트 목록 보기
mangolove projects

# 프로필 추가 (수동)
mangolove profile add

# 프로젝트 디렉토리에서 실행하면 자동으로 프로필 생성 제안
cd ~/my-project && mangolove
```

### Work Logging

```bash
# 작업 로그 저장소 초기화 (최초 1회)
mangolove log init

# 작업 로그 브라우저에서 보기
mangolove log view
```

### All Options

```bash
mangolove help
```

Claude Code의 모든 옵션을 그대로 전달할 수 있습니다:

```bash
mangolove --model opus           # 모델 선택
mangolove --effort max           # 최대 노력 모드
mangolove -r                     # 세션 선택하여 재개
mangolove --worktree             # 별도 worktree에서 작업
```

## 📁 Directory Structure

```
~/.mangolove/
├── bin/
│   └── mangolove              # Main executable
├── lib/
│   ├── banner.sh              # UI banner
│   ├── work-logger.sh         # GitHub work logger
│   └── profile-manager.sh     # Project profile manager
├── prompts/
│   └── system-prompt.md       # Core system prompt
├── projects/                  # Project profiles (auto-generated)
│   └── my-project.md
├── logs/                      # Local work logs
└── config.sh                  # User configuration
```

## ⚙️ Configuration

`~/.mangolove/config.sh`에서 설정을 커스터마이즈할 수 있습니다:

```bash
# GitHub 작업 로그 저장소 (기본: {your-username}/mangolove-work-logs)
MANGOLOVE_LOG_REPO=""

# 작업 로그 자동 기록 (기본: true)
MANGOLOVE_AUTO_LOG=true

# 배너 표시 (기본: true)
MANGOLOVE_SHOW_BANNER=true

# 시스템 프롬프트 커스터마이즈 (추가 프롬프트)
MANGOLOVE_EXTRA_PROMPT=""
```

## 🛠 Creating Project Profiles

프로젝트 디렉토리에서 `mangolove`를 처음 실행하면 자동으로 프로필 생성을 제안합니다.

수동으로 만들려면 `~/.mangolove/projects/{name}.md` 파일을 생성하세요:

```markdown
---
name: My Awesome Project
path: /Users/me/projects/awesome
tech_stack: [Java, Spring Boot, MySQL, Redis]
build_cmd: ./gradlew build
test_cmd: ./gradlew test
---

## Architecture
- Spring Boot multi-module project
- Hexagonal architecture

## Conventions
- Google Java Style Guide
- Conventional Commits
```

## 🔄 Update

```bash
mangolove update
```

또는:

```bash
cd ~/.mangolove && git pull origin main
```

## 🤝 Contributing

1. Fork this repository
2. Create your feature branch (`git checkout -b feat/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feat/amazing-feature`)
5. Open a Pull Request

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

<p align="center">
  🥭 <strong>MangoLove</strong> — Built with ♥ and Claude Code
</p>
