#!/usr/bin/env bash
#
# Multi-Platform Zsh + Powerlevel10k + Nerd Font + Fetch Setup
# Supports: Termux, Debian/Ubuntu, Arch, Fedora, Alpine, macOS
#
# Fetch tool and fancy ls degrade gracefully by distro release:
# fastfetch -> neofetch -> none, lsd -> plain ls. Whatever resolves
# gets installed and wired; whatever is missing is skipped, never fatal
# (except the base set below, which every supported distro ships).
#

set -e

if [ -z "${BASH_VERSION:-}" ]; then
  echo "ERROR: this script needs bash, which is not installed here."
  echo "  Alpine:  apk add --no-cache bash curl"
  echo "Then re-run with:  bash termux-ricing.sh"
  exit 1
fi

TOTAL_STEPS=10
ZSHRC="$HOME/.zshrc"
SETUP_DIR="$HOME/.termux-setup"
FASTFETCH_CFG_DIR="$HOME/.config/fastfetch"
FASTFETCH_LOGO="$HOME/.config/fastfetch/logo.txt"

step() {
  echo ""
  echo "[$1/$TOTAL_STEPS] $2"
}

# --------------------------------------------------
# Environment & Binary Detection
# --------------------------------------------------
IS_TERMUX_NATIVE=false
IS_PROOT=false
HOST_TERMUX_HOME="/data/data/com.termux/files/home"
SUDO=""

if [ "$(id -u)" -eq 0 ]; then
  # Running as root: Either inside PRoot distro or root subshell
  if [ -d "$HOST_TERMUX_HOME" ] || [ -f "/data/data/com.termux/files/usr/bin/termux-reload-settings" ]; then
    IS_PROOT=true
  fi
else
  # Running as normal user
  if [ -n "$TERMUX_VERSION" ] || [[ "$PREFIX" == *com.termux* ]]; then
    IS_TERMUX_NATIVE=true
  elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  fi
fi

# Package manager execution based on privileges and native tools
install_packages() {
  local pkgs=("$@")

  # Use 'pkg' ONLY if non-root and running natively in Termux
  if [ "$IS_TERMUX_NATIVE" = true ] && command -v pkg >/dev/null 2>&1; then
    pkg update -y && pkg install -y "${pkgs[@]}"
  elif command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y "${pkgs[@]}"
  elif command -v pacman >/dev/null 2>&1; then
    $SUDO pacman -Sy --noconfirm "${pkgs[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf install -y "${pkgs[@]}"
  elif command -v apk >/dev/null 2>&1; then
    $SUDO apk add --no-cache "${pkgs[@]}"
  elif command -v brew >/dev/null 2>&1; then
    brew install "${pkgs[@]}"
  else
    echo "ERROR: No supported package manager found."
    exit 1
  fi
}

# --------------------------------------------------
# 1 & 2. Update and Upgrade
# --------------------------------------------------
step 1 "Updating package repositories..."
step 2 "Upgrading system packages..."
# Handled directly inside install_packages logic step

# --------------------------------------------------
# 3. Install dependencies
# --------------------------------------------------
step 3 "Installing dependencies..."
BASE_PKGS=(openssl git zsh curl unzip fontconfig imagemagick chafa)
if [ "$IS_TERMUX_NATIVE" = true ]; then
  # Termux names its Python package 'python', not 'python3'.
  BASE_PKGS+=(python)
else
  BASE_PKGS+=(python3)
fi

# Preference tiers, best first. Managers resolve the whole list before
# installing anything, so a tier with an unavailable package fails fast
# and cleanly, and we fall through to the next one.
FETCH_BIN=""
HAS_LSD=false
INSTALLED=false
for tier in "fastfetch lsd" "neofetch lsd" "fastfetch" "neofetch" ""; do
  if [ -z "$tier" ]; then
    echo "No fetch tool or lsd on this release; continuing with the base set."
    if install_packages "${BASE_PKGS[@]}"; then
      INSTALLED=true
      break
    fi
  # shellcheck disable=SC2086
  elif install_packages "${BASE_PKGS[@]}" $tier; then
    INSTALLED=true
    case " $tier " in
      *" fastfetch "*) FETCH_BIN="fastfetch" ;;
      *" neofetch "*) FETCH_BIN="neofetch" ;;
    esac
    case " $tier " in
      *" lsd "*) HAS_LSD=true ;;
    esac
    break
  fi
  echo "That combination is not fully available here; trying fallbacks..."
done
if [ "$INSTALLED" != true ]; then
  echo "ERROR: Could not install even the base dependency set."
  exit 1
fi
echo "Fetch tool: ${FETCH_BIN:-none}; lsd: $HAS_LSD."

# --------------------------------------------------
# 4. Install Oh My Zsh
# --------------------------------------------------
step 4 "Installing Oh My Zsh..."
if [ -d "$HOME/.oh-my-zsh" ]; then
  echo "Oh My Zsh already installed, skipping."
else
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# --------------------------------------------------
# 5. Install Powerlevel10k
# --------------------------------------------------
step 5 "Installing Powerlevel10k..."
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ -d "$P10K_DIR" ]; then
  echo "Powerlevel10k already cloned, skipping."
else
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

touch "$ZSHRC"
if grep -q '^ZSH_THEME=' "$ZSHRC"; then
  sed -i.bak 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC" && rm -f "$ZSHRC.bak"
else
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSHRC"
fi

# --------------------------------------------------
# 6. Install Nerd Font (FiraCode Mono)
# --------------------------------------------------
step 6 "Installing Nerd Font (FiraCode Mono)..."
TMP_ZIP="$HOME/nerdfont.zip"
TMP_DIR="$HOME/nerdfont_tmp"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

curl -L -o "$TMP_ZIP" \
  https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip

unzip -q "$TMP_ZIP" -d "$TMP_DIR"

FONT_FILE=$(find "$TMP_DIR" -type f -name "*Mono-Regular.ttf" | head -n 1)

if [ -z "$FONT_FILE" ]; then
  echo "ERROR: Mono Nerd Font not found"
  exit 1
fi

if [ "$IS_TERMUX_NATIVE" = true ]; then
  mkdir -p ~/.termux
  cp "$FONT_FILE" ~/.termux/font.ttf
  termux-reload-settings || true
elif [ "$IS_PROOT" = true ] && [ -d "$HOST_TERMUX_HOME" ]; then
  mkdir -p "$HOME/.local/share/fonts"
  cp "$FONT_FILE" "$HOME/.local/share/fonts/"
  mkdir -p "$HOST_TERMUX_HOME/.termux"
  cp "$FONT_FILE" "$HOST_TERMUX_HOME/.termux/font.ttf"
  HOST_RELOAD="/data/data/com.termux/files/usr/bin/termux-reload-settings"
  if [ -x "$HOST_RELOAD" ]; then
    "$HOST_RELOAD" || true
  fi
elif [ "$IS_MACOS" = true ]; then
  mkdir -p "$HOME/Library/Fonts"
  cp "$FONT_FILE" "$HOME/Library/Fonts/"
else
  FONT_DEST="$HOME/.local/share/fonts"
  mkdir -p "$FONT_DEST"
  cp "$FONT_FILE" "$FONT_DEST/"
  command -v fc-cache >/dev/null 2>&1 && fc-cache -fv "$FONT_DEST" || true
fi

rm -rf "$TMP_ZIP" "$TMP_DIR"

# Change Default Shell safely
ZSH_PATH=$(which zsh)
if [ "$SHELL" != "$ZSH_PATH" ]; then
  chsh -s "$ZSH_PATH" || echo "Warning: Could not automatically set default shell to Zsh."
fi

# Set lsd alias when it installed; plain ls otherwise.
if [ "$HAS_LSD" = true ] && command -v lsd >/dev/null 2>&1; then
  if ! grep -q 'alias ls="lsd"' "$ZSHRC"; then
    echo 'alias ls="lsd"' >> "$ZSHRC"
  fi
else
  echo "Note: lsd is unavailable on this distro release; skipping the ls alias."
fi

# --------------------------------------------------
# 7. Wire fetch tool into .zshrc
# --------------------------------------------------
if [ -z "$FETCH_BIN" ]; then
  step 7 "No fetch tool available; skipping."
else
  step 7 "Wiring $FETCH_BIN into .zshrc..."
  if ! grep -qx "$FETCH_BIN" "$ZSHRC"; then
    echo -e "$FETCH_BIN\n$(cat "$ZSHRC")" > "$ZSHRC"
  else
    echo "$FETCH_BIN already present in .zshrc, skipping."
  fi
fi

# --------------------------------------------------
# 8. Write fastfetch config (fastfetch only; neofetch ships sane defaults)
# --------------------------------------------------
if [ "$FETCH_BIN" = "fastfetch" ]; then
step 8 "Writing fastfetch config..."
mkdir -p "$FASTFETCH_CFG_DIR"

DISK_FOLDER="/"
if [ "$IS_TERMUX_NATIVE" = true ] || [ -d "/storage/emulated" ]; then
  DISK_FOLDER="/storage/emulated"
fi

cat > "$FASTFETCH_CFG_DIR/config.jsonc" << EOF
{
  "\$schema": "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json",
  "logo": {
    "source": "$FASTFETCH_LOGO",
    "type": "file"
  },
  "modules": [
    {
      "type": "custom",
      "format": "   {#1;32}darki{#}{#37}@{#}{#1;36}DARKIAN-OS{#}"
    },
    "separator",
    "os",
    "host",
    "uptime",
    "packages",
    "shell",
    "terminal",
    "terminalfont",
    "cpu",
    "gpu",
    "memory",
    "swap",
    {
      "type": "disk",
      "key": "Disk",
      "folders": "$DISK_FOLDER"
    },
    "localip",
    "locale",
    "break",
    "colors"
  ]
}
EOF
else
  step 8 "No fastfetch here; skipping its config."
fi

# --------------------------------------------------
# 9. Fastfetch logo generator (needs fastfetch; neofetch has its own art)
# --------------------------------------------------
if [ "$FETCH_BIN" = "fastfetch" ]; then
step 9 "Setting up fastfetch logo..."
mkdir -p "$SETUP_DIR"

cat > "$SETUP_DIR/generate_logo.py" << 'PYEOF'
#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys

FASTFETCH_LOGO = os.path.expanduser("~/.config/fastfetch/logo.txt")

# ImageMagick 7 ships `magick`; 6 (Debian/Ubuntu) only `convert`.
CONVERT_BIN = shutil.which("magick") or shutil.which("convert")

def check_dependencies():
    missing = []
    if CONVERT_BIN is None:
        missing.append("magick/convert (ImageMagick)")
    if shutil.which("chafa") is None:
        missing.append("chafa")
    if missing:
        print(f"Missing required tools: {', '.join(missing)}")
        return False
    return True

def prompt_for_image():
    print("Enter path to image (or press Enter to skip):")
    try:
        if not sys.stdin.isatty():
            try:
                sys.stdin = open('/dev/tty', 'r')
            except (OSError, PermissionError):
                print("No controlling terminal available. Skipping logo setup.")
                return None

        raw = input("> ").strip().strip("'\"")
        if not raw:
            return None
        path = os.path.expanduser(raw)
        if os.path.isfile(path):
            return path
        print(f"File not found: {path}. Skipping logo setup.")
        return None
    except (EOFError, KeyboardInterrupt, OSError):
        print("\nSkipping logo setup.")
        return None

def prompt_for_gamma():
    try:
        default = "1.5"
        raw = input(f"Gamma correction value [default {default}]: ").strip() or default
        float(raw)
        return raw
    except Exception:
        return "1.5"

def prompt_for_size():
    try:
        return input("Chafa size as WIDTHxHEIGHT [default 31x50]: ").strip() or "31x50"
    except Exception:
        return "31x50"

def convert_and_render(image_path, gamma, size):
    os.makedirs(os.path.dirname(FASTFETCH_LOGO), exist_ok=True)
    convert_cmd = [CONVERT_BIN, image_path, "-gamma", gamma, "png:-"]
    chafa_cmd = ["chafa", f"--size={size}", "--symbols=block+quad", "-"]

    with open(FASTFETCH_LOGO, "w") as out_file:
        p1 = subprocess.Popen(convert_cmd, stdout=subprocess.PIPE)
        p2 = subprocess.Popen(chafa_cmd, stdin=p1.stdout, stdout=out_file)
        p1.stdout.close()
        p2.communicate()

    if p2.returncode == 0:
        print(f"Logo successfully saved to {FASTFETCH_LOGO}")

def main():
    if not check_dependencies():
        return
    print("=== Fastfetch Logo Generator ===")
    image_path = prompt_for_image()
    if not image_path:
        return
    gamma = prompt_for_gamma()
    size = prompt_for_size()
    convert_and_render(image_path, gamma, size)

if __name__ == "__main__":
    main()
PYEOF

PYTHON_BIN=$(command -v python3 || command -v python)
$PYTHON_BIN "$SETUP_DIR/generate_logo.py" || true
else
  step 9 "No fastfetch here; skipping logo setup."
fi

touch "$HOME/.hushlogin"

# --------------------------------------------------
# 10. Reload into Zsh
# --------------------------------------------------
step 10 "Done. Reloading into zsh..."
exec "$ZSH_PATH" -l
