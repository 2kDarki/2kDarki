#!/data/data/com.termux/files/usr/bin/bash

set -e

echo "[1/6] Updating packages..."
pkg update -y && pkg upgrade -y

echo "[2/6] Installing dependencies..."
pkg install -y git zsh curl unzip fontconfig

echo "[3/6] Installing Oh My Zsh..."
RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

echo "[4/6] Installing Powerlevel10k..."
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

echo "[5/6] Setting up Powerlevel10k theme..."

ZSHRC="$HOME/.zshrc"

if grep -q '^ZSH_THEME=' "$ZSHRC"; then
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
else
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSHRC"
fi

echo "[6/6] Installing Nerd Font (FiraCode Mono)..."

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

echo ""
echo "Reloading Termux settings..."
termux-reload-settings || true

echo ""
echo "DONE."
echo ""
echo "Next step (IMPORTANT):"
echo "1. restart Termux fully (not reload)"
echo "2. run: p10k configure"
echo "3. test: echo '   '"