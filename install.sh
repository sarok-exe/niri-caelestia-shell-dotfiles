#!/bin/bash

# Niri Dotfiles Installer
# This script will install all configurations from ~/Documents/ff

set -e

echo "╔════════════════════════════════════╗"
echo "║    Niri Caelestia Dotfiles         ║"
echo "║    Installation Started...         ║"
echo "╚════════════════════════════════════╝"

# Colors for formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Print functions
print_step() {
    echo -e "${BLUE}==>${NC} ${YELLOW}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if running on Arch Linux
if [ ! -f /etc/arch-release ]; then
    print_error "This script is for Arch Linux only!"
    exit 1
fi

# Update system
print_step "Updating system..."
sudo pacman -Syu --noconfirm

# Install yay if not present
if ! command -v yay &> /dev/null; then
    print_step "Installing yay (AUR helper)..."
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd ~
fi

# Install Flatpak if not present
if ! command -v flatpak &> /dev/null; then
    print_step "Installing Flatpak..."
    sudo pacman -S --noconfirm flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# Required packages list
print_step "Installing required packages..."

# Packages from official repos
PACMAN_PACKAGES=(
    fish
    starship
    kitty
    mpd
    mpv
    btop
    fastfetch
    cava
    fuzzel
    flameshot
    fcitx5
    git
    wget
    curl
    neovim
    unzip
    zip
    ripgrep
    fd
    tree
)

print_step "Installing pacman packages..."
sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

# Packages from AUR
AUR_PACKAGES=(
    yazi
    niri
    obsidian
    rmpc
    blanket
    keypunch
    niri-caelestia-shell-git
    bibata-modern-ice-cursor-theme
)

print_step "Installing AUR packages..."
yay -S --needed --noconfirm "${AUR_PACKAGES[@]}"

# Flatpak packages
FLATPAK_PACKAGES=(
    io.github.alainm23.planify
    com.github.PintaProject.Pinta
    com.brave.Browser
    org.telegram.desktop
)

print_step "Installing Flatpak packages..."
flatpak install -y flathub "${FLATPAK_PACKAGES[@]}"

# Source directory (where your configs are)
SOURCE_DIR="$HOME/Documents/ff"

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    print_error "Source directory $SOURCE_DIR not found!"
    exit 1
fi

print_step "Found configs in: $SOURCE_DIR"
print_step "Contents:"
ls -la "$SOURCE_DIR"

# Create backup of existing configs
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
print_step "Creating backup in $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
if [ -d "$HOME/.config" ]; then
    cp -r "$HOME/.config"/* "$BACKUP_DIR/" 2>/dev/null || true
    print_success "Backup created"
fi

# Copy configurations from ff folder
print_step "Copying configurations from ff folder..."

# List of configs to copy (exactly as in your ff folder)
CONFIG_DIRS=(
    "btop"
    "cava"
    "fastfetch"
    "kitty"
    "mpd"
    "mpv"
    "niri"
    "niri_caelestia"
    "quickshell"
    "yazi"
)

for dir in "${CONFIG_DIRS[@]}"; do
    if [ -d "$SOURCE_DIR/$dir" ]; then
        print_step "Copying $dir..."
        mkdir -p "$HOME/.config/$dir"
        cp -rf "$SOURCE_DIR/$dir"/* "$HOME/.config/$dir/" 2>/dev/null || true
        print_success "Copied $dir to ~/.config/"
    else
        print_error "Directory $dir not found in $SOURCE_DIR"
    fi
done

# Copy starship.toml if exists
if [ -f "$SOURCE_DIR/starship.toml" ]; then
    print_step "Copying starship.toml..."
    cp "$SOURCE_DIR/starship.toml" "$HOME/.config/"
    print_success "Copied starship.toml"
fi

# Setup Niri Caelestia
print_step "Setting up Niri Caelestia..."
mkdir -p "$HOME/.local/share/quickshell"

# Setup cursor
print_step "Setting up mouse cursor..."
mkdir -p "$HOME/.icons"
if [ ! -d "$HOME/.icons/Bibata-Modern-Ice" ] && [ -d "/usr/share/icons/Bibata-Modern-Ice" ]; then
    ln -sf /usr/share/icons/Bibata-Modern-Ice "$HOME/.icons/"
    print_success "Cursor symlink created"
fi

# Add spawn-at-startup to niri config if not already there
if [ -f "$HOME/.config/niri/config.kdl" ]; then
    print_step "Checking niri startup applications..."
    if ! grep -q "spawn-at-startup.*fcitx5" "$HOME/.config/niri/config.kdl"; then
        cat >> "$HOME/.config/niri/config.kdl" << 'EOF'

# Startup applications
spawn-at-startup "fcitx5" "-d"
spawn-at-startup "flameshot"
spawn-at-startup "qs" "-c" "caelestia"
spawn-at-startup "io.github.alainm23.planify"

# Cursor settings
cursor { 
   xcursor-theme "Bibata-Modern-Ice"
   xcursor-size 30
}
EOF
        print_success "Added startup applications to niri config"
    fi
fi

# Setup environment variables
print_step "Setting up environment variables..."
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/99-niri.conf" << 'EOF'
# Niri environment variables
XDG_CURRENT_DESKTOP=niri
QT_QPA_PLATFORM=wayland
ELECTRON_OZONE_PLATFORM_HINT=auto
QT_QPA_PLATFORMTHEME=gtk3
QT_QPA_PLATFORMTHEME_QT6=gtk3
TERMINAL=kitty
EOF
print_success "Environment variables set"

# Change default shell to Fish
if [ "$SHELL" != "$(which fish 2>/dev/null)" ]; then
    print_step "Changing default shell to Fish..."
    if command -v fish &> /dev/null; then
        chsh -s "$(which fish)"
        print_success "Shell changed to Fish (you may need to log out)"
    else
        print_error "Fish shell not found"
    fi
fi

# Create symlinks
print_step "Creating additional symlinks..."
if [ -f "$HOME/.config/starship.toml" ]; then
    ln -sf "$HOME/.config/starship.toml" "$HOME/.starship.toml"
    print_success "Starship symlink created"
fi

# Enable services
print_step "Enabling services..."
systemctl --user enable mpd.service 2>/dev/null || true
systemctl --user start mpd.service 2>/dev/null || true
print_success "MPD service enabled"

echo "╔════════════════════════════════════╗"
echo "║    ✅ Installation Complete!        ║"
echo "╚════════════════════════════════════╝"
echo ""
echo "📝 Important Notes:"
echo "   • Backup created at: $BACKUP_DIR"
echo "   • Source configs from: $SOURCE_DIR"
echo "   • Please log out and log back in"
echo "   • Select Niri from your display manager"
echo ""
echo "🚀 Important Niri Shortcuts:"
echo "   • Mod+Return - Open Kitty"
echo "   • Mod+D - Open quick toggles"
echo "   • Mod+X - Open control center"
echo "   • Mod+V - Open clipboard"
echo "   • Mod+T - Open Telegram"
echo "   • Mod+E - Open Yazi"
echo "   • Mod+O - Open Obsidian"
echo "   • Mod+S - Toggle overview"
echo ""
echo "📋 For full shortcuts: Mod+Shift+/"
echo ""
echo "🔗 Helpful Links:"
echo "   • Niri GitHub: https://github.com/YaLTeR/niri"
echo "   • Caelestia GitHub: https://github.com/caelestia-dots/shell"
echo "   • niri Caelestia: https://github.com/AyushKr2003/niri-caelestia-shell"
