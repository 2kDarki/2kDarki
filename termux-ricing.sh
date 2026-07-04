#!/data/data/com.termux/files/usr/bin/bash
#
# Termux Zsh + Powerlevel10k + Nerd Font + Fastfetch setup
#

set -e

TOTAL_STEPS=10
ZSHRC="$HOME/.zshrc"
SETUP_DIR="$HOME/.termux-setup"
FASTFETCH_CFG_DIR="$HOME/fastfetch"
FASTFETCH_LOGO="$HOME/fastfetch/logo.txt"

step() {
  echo ""
  echo "[$1/$TOTAL_STEPS] $2"
}

# ----------------------------------------------------------
# 1. Update package lists
# ----------------------------------------------------------
step 1 "Updating package lists..."
pkg update -y

# ----------------------------------------------------------
# 2. Upgrade existing packages (kept separate — this is the 
#    step most likely to prompt interactively about config 
#    file conflicts)
# ----------------------------------------------------------
step 2 "Upgrading existing packages..."
pkg upgrade -y

# ----------------------------------------------------------
# 3. Install dependencies
# ----------------------------------------------------------
step 3 "Installing dependencies..."
pkg install -y git zsh curl unzip fontconfig imagemagick chafa fastfetch python lsd

# ------------------------------------------------------------
# 4. Install Oh My Zsh (unattended)
# ----------------------------------------------------------
step 4 "Installing Oh My Zsh..."
if [ -d "$HOME/.oh-my-zsh" ]; then
  echo "Oh My Zsh already installed, skipping."
else
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# ----------------------------------------------------------
# 5. Install Powerlevel10k
# ----------------------------------------------------------
step 5 "Installing Powerlevel10k..."
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ -d "$P10K_DIR" ]; then
  echo "Powerlevel10k already cloned, skipping."
else
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

if grep -q '^ZSH_THEME=' "$ZSHRC"; then
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
else
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSHRC"
fi

# ----------------------------------------------------------
# 6. Install Nerd Font (FiraCode Mono)
# ----------------------------------------------------------
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

echo "Using font: $FONT_FILE"
mkdir -p ~/.termux
cp "$FONT_FILE" ~/.termux/font.ttf
rm -rf "$TMP_ZIP" "$TMP_DIR"

termux-reload-settings || true
chsh -s zsh

tmpfile=$(mktemp)
tac "$ZSHRC" | sed '4i alias ls="lsd"' | tac > "$tmpfile" && mv "$tmpfile" "$ZSHRC"

# ----------------------------------------------------------
# 7. Make sure `fastfetch` runs at the very top of .zshrc
#    (must come before Oh My Zsh / p10k instant prompt
#    logic, or it breaks it)
# ----------------------------------------------------------
step 7 "Wiring fastfetch into .zshrc..."
if ! grep -qx 'fastfetch' "$ZSHRC"; then
  sed -i '1i fastfetch' "$ZSHRC"
else
  echo "fastfetch already present in .zshrc, skipping."
fi

# ----------------------------------------------------------
# 8. Write the fastfetch config
# ----------------------------------------------------------
step 8 "Writing fastfetch config..."
mkdir -p "$FASTFETCH_CFG_DIR"
mkdir -p "$(dirname "$FASTFETCH_LOGO")"

cat > "$FASTFETCH_CFG_DIR/config.jsonc" << 'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json",
  "logo": {
    "source": "~/fastfetch/logo.txt",
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
      "folders": "/storage/emulated"
    },
    "localip",
    "locale",
    "break",
    "colors"
  ]
}
EOF

# ----------------------------------------------------------
# 9. Generate the fastfetch logo from a user-supplied image
# ----------------------------------------------------------
step 9 "Setting up fastfetch logo..."
mkdir -p "$SETUP_DIR"

cat > "$SETUP_DIR/generate_logo.py" << 'PYEOF'
#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys

FASTFETCH_LOGO = os.path.expanduser("~/fastfetch/logo.txt")


def check_dependencies():
    missing = [tool for tool in ("magick", "chafa") if shutil.which(tool) is None]
    if missing:
        print(f"Missing required tools: {', '.join(missing)}")
        print("Install them with: pkg install imagemagick chafa")
        sys.exit(1)


def prompt_for_image():
    while True:
        raw = input(
            "Enter path to image "
            "(e.g. ~/storage/shared/Pictures/logo.jpg): "
        ).strip().strip("'\"")
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
        print(f"Invalid number, using default {default}")
        return default


def prompt_for_size():
    raw = input("Chafa size as WIDTHxHEIGHT [default 31x50]: ").strip() or "31x50"
    return raw


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

python "$SETUP_DIR/generate_logo.py"

# ----------------------------------------------------------
# 10. Reload shell into zsh (this alone replaces the old 
#     manual instructions — sourcing .zshrc triggers the 
#     p10k first-run wizard automatically if no ~/.p10k.zsh 
#     exists yet)
# ----------------------------------------------------------
step 10 "Done. Reloading into zsh..."
exec zsh -l
