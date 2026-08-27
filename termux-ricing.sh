#!/usr/bin/env bash
#
# Multi-Platform Zsh + Powerlevel10k + Nerd Font + Fastfetch Setup
# Supports: Termux, Debian/Ubuntu, Arch, Fedora, Alpine, macOS
#

set -e

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
PKGS=(openssl git zsh curl unzip fontconfig imagemagick chafa fastfetch python3 lsd)
[ "$IS_TERMUX" = true ] && PKGS=(openssl git zsh curl unzip fontconfig imagemagick chafa fastfetch python lsd)

install_packages "${PKGS[@]}"

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

# Set lsd alias cross-platform
if ! grep -q 'alias ls="lsd"' "$ZSHRC"; then
  echo 'alias ls="lsd"' >> "$ZSHRC"
fi

# --------------------------------------------------
# 7. Wire fastfetch into .zshrc
# --------------------------------------------------
step 7 "Wiring fastfetch into .zshrc..."
if ! grep -qx 'fastfetch' "$ZSHRC"; then
  echo -e "fastfetch\n$(cat "$ZSHRC")" > "$ZSHRC"
else
  echo "fastfetch already present in .zshrc, skipping."
fi

# --------------------------------------------------
# 8. Write fastfetch config
# --------------------------------------------------
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

# --------------------------------------------------
# 9. Fastfetch logo generator
# --------------------------------------------------
step 9 "Setting up fastfetch logo..."
mkdir -p "$SETUP_DIR"

cat > "$SETUP_DIR/generate_logo.py" << PYEOF
#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys

FASTFETCH_LOGO = os.path.expanduser("$FASTFETCH_LOGO")

def check_dependencies():
    missing = [tool for tool in ("magick", "chafa") if shutil.which(tool) is None]
    if missing:
        print(f"Missing required tools: {', '.join(missing)}")
        sys.exit(1)

def prompt_for_image():
    while True:
        raw = input("Enter path to image: ").strip().strip("'\"")
        path = os.path.expanduser(raw)
        if os.path.isfile(path):
            return path
        print(f"File not found: {path}\n")

def prompt_for_gamma():
    default = "1.5"
    raw = input(f"Gamma correction value [default {default}]: ").strip() or default
    try:
        float(raw)
        return raw
    except ValueError:
        return default

def prompt_for_size():
    return input("Chafa size as WIDTHxHEIGHT [default 31x50]: ").strip() or "31x50"

def convert_and_render(image_path, gamma, size):
    os.makedirs(os.path.dirname(FASTFETCH_LOGO), exist_ok=True)
    convert_cmd = ["magick", image_path, "-gamma", gamma, "png:-"]
    chafa_cmd = ["chafa", f"--size={size}", "--symbols=block+quad", "-"]

    with open(FASTFETCH_LOGO, "w") as out_file:
        p1 = subprocess.Popen(convert_cmd, stdout=subprocess.PIPE)
        p2 = subprocess.Popen(chafa_cmd, stdin=p1.stdout, stdout=out_file)
        p1.stdout.close()
        p2.communicate()

    if p2.returncode != 0:
        print("chafa conversion failed.")
        sys.exit(1)

    print(f"Logo saved to {FASTFETCH_LOGO}")

def main():
    check_dependencies()
    print("=== Fastfetch Logo Generator ===")
    image_path = prompt_for_image()
    gamma = prompt_for_gamma()
    size = prompt_for_size()
    convert_and_render(image_path, gamma, size)

if __name__ == "__main__":
    main()
PYEOF

PYTHON_BIN=$(command -v python3 || command -v python)
$PYTHON_BIN "$SETUP_DIR/generate_logo.py"

touch "$HOME/.hushlogin"

# --------------------------------------------------
# 10. Reload into Zsh
# --------------------------------------------------
step 10 "Done. Reloading into zsh..."
exec "$ZSH_PATH" -l
