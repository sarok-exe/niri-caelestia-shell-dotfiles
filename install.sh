#!/bin/bash

# Niri Dotfiles Installer

set -e

echo "╔════════════════════════════════════╗"
echo "║    Niri Caelestia Dotfiles         ║"
echo "║    Installation Started...         ║"
echo "╚════════════════════════════════════╝"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${BLUE}==>${NC} ${YELLOW}$1${NC}"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Check Arch
if [ ! -f /etc/arch-release ]; then
    print_error "This script is for Arch Linux only!"
    exit 1
fi

# Update system
print_step "Updating system..."
sudo pacman -Syu --noconfirm

# Install yay
if ! command -v yay &> /dev/null; then
    print_step "Installing yay..."
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd ~
fi

# Install Flatpak
if ! command -v flatpak &> /dev/null; then
    print_step "Installing Flatpak..."
    sudo pacman -S --noconfirm flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# Packages
PACMAN_PACKAGES=(
    fish starship kitty mpd mpv btop fastfetch cava fuzzel flameshot fcitx5
    git wget curl neovim unzip zip ripgrep fd tree
)

print_step "Installing pacman packages..."
sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

AUR_PACKAGES=(
    yazi niri obsidian rmpc blanket keypunch niri-caelestia-shell-git
    bibata-modern-ice-cursor-theme
)

print_step "Installing AUR packages..."
yay -S --needed --noconfirm "${AUR_PACKAGES[@]}"

FLATPAK_PACKAGES=(
    io.github.alainm23.planify com.github.PintaProject.Pinta
    com.brave.Browser org.telegram.desktop
)

print_step "Installing Flatpak packages..."
flatpak install -y flathub "${FLATPAK_PACKAGES[@]}"

# Backup
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
print_step "Creating backup in $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
[ -d "$HOME/.config" ] && cp -r "$HOME/.config"/* "$BACKUP_DIR/" 2>/dev/null || true

# Copy configs
DOTFILES_DIR="$PWD"
CONFIG_DIRS=(
    "btop" "cava" "fastfetch" "fish" "kitty" "mpd" "mpv" "niri"
    "niri_caelestia" "yazi"
)

for dir in "${CONFIG_DIRS[@]}"; do
    if [ -d "$DOTFILES_DIR/$dir" ]; then
        print_step "Copying $dir..."
        mkdir -p "$HOME/.config/$dir"
        cp -rf "$DOTFILES_DIR/$dir"/* "$HOME/.config/$dir/" 2>/dev/null || true
        print_success "Copied $dir"
    fi
done

# Copy starship.toml
[ -f "$DOTFILES_DIR/starship.toml" ] && cp "$DOTFILES_DIR/starship.toml" "$HOME/.config/"

# Setup cursor
print_step "Setting up cursor..."
mkdir -p "$HOME/.icons"
[ -d "/usr/share/icons/Bibata-Modern-Ice" ] && ln -sf /usr/share/icons/Bibata-Modern-Ice "$HOME/.icons/"

# Environment
print_step "Setting up environment..."
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/99-niri.conf" << 'EOF'
XDG_CURRENT_DESKTOP=niri
QT_QPA_PLATFORM=wayland
ELECTRON_OZONE_PLATFORM_HINT=auto
QT_QPA_PLATFORMTHEME=gtk3
QT_QPA_PLATFORMTHEME_QT6=gtk3
TERMINAL=kitty
EOF

# Change shell
if command -v fish &> /dev/null && [ "$SHELL" != "$(which fish)" ]; then
    print_step "Changing shell to Fish..."
    chsh -s "$(which fish)"
fi

# Enable MPD
systemctl --user enable mpd.service 2>/dev/null || true
systemctl --user start mpd.service 2>/dev/null || true

echo ""
echo "╔════════════════════════════════════╗"
echo "║    ✅ Installation Complete!        ║"
echo "╚════════════════════════════════════╝"
echo ""
echo "Backup: $BACKUP_DIR"
echo "Log out and select Niri from your display manager"
