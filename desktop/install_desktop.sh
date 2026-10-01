#!/usr/bin/env bash
# Install/uninstall the Spotifice desktop entry, wrapper, and icon from the desktop/ directory.
# Installs to user-local paths by default (~/.local), no sudo required.
set -euo pipefail

PREFIX_DEFAULT="$HOME/.local"
PREFIX="${PREFIX:-$PREFIX_DEFAULT}"
APP_ID="es.uclm.spotifice"
APP_NAME="Spotifice Control"

# Paths
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DESKTOP_SRC="$SCRIPT_DIR/${APP_ID}.desktop"
APPLICATIONS_DIR="$PREFIX/share/applications"
DESKTOP_DEST="$APPLICATIONS_DIR/${APP_ID}.desktop"
BIN_DIR="$PREFIX/bin"
WRAPPER_DEST="$BIN_DIR/spotifice-control"
ICON_THEME_DIR="$PREFIX/share/icons/hicolor"
ICON_DIR="$ICON_THEME_DIR/scalable/apps"
ICON_SRC="$SCRIPT_DIR/${APP_ID}.svg"
ICON_DEST="$ICON_DIR/${APP_ID}.svg"

# Where to look for control.config in the wrapper
CONFIG_CANDIDATES=("${XDG_CONFIG_HOME:-$HOME/.config}/spotifice/control.config" "$REPO_ROOT/control.config" "/etc/spotifice/control.config")

DRY_RUN=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [install|uninstall|print-dirs] [--prefix DIR] [--dry-run]

Commands:
  install       Install desktop entry, wrapper and icon (default)
  uninstall     Remove desktop entry and wrapper (icon optional)
  print-dirs    Print computed directories and paths

Options:
  -p, --prefix DIR  Installation prefix (default: $PREFIX_DEFAULT or env PREFIX)
  -n, --dry-run     Show what would be done without making changes
  -h, --help        Show this help
EOF
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] %s\n' "$*"
  else
    eval "$@"
  fi
}

print_dirs() {
  cat <<EOF
PREFIX=$PREFIX
APP_ID=$APP_ID
REPO_ROOT=$REPO_ROOT
DESKTOP_SRC=$DESKTOP_SRC
DESKTOP_DEST=$DESKTOP_DEST
BIN_DIR=$BIN_DIR
WRAPPER_DEST=$WRAPPER_DEST
ICON_SRC=$ICON_SRC
ICON_DEST=$ICON_DEST
EOF
}

install_icon() {
  if [ ! -f "$ICON_SRC" ]; then
    echo "Error: icon source not found: $ICON_SRC" >&2
    exit 1
  fi
  run mkdir -p "$ICON_DIR"
  run cp "$ICON_SRC" "$ICON_DEST"
  printf 'Installed icon: %s\n' "$ICON_DEST"
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    run gtk-update-icon-cache -f "$ICON_THEME_DIR"
  fi
}

make_wrapper() {
  run mkdir -p "$BIN_DIR"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] write wrapper: %s\n' "$WRAPPER_DEST"
    return 0
  fi
  REPO_EMBED="$REPO_ROOT"
  cat > "$WRAPPER_DEST" <<WRAP
#!/usr/bin/env bash
set -euo pipefail
# Wrapper to launch Spotifice Control using repo installed at install-time path
REPO_ROOT="$REPO_EMBED"

# Determine config file
CFG=""
for c in "$HOME/.config/spotifice/control.config" "$REPO_ROOT/control.config" "/etc/spotifice/control.config"; do
  if [ -f "$c" ]; then CFG="$c"; break; fi
done
if [ -z "$CFG" ]; then
  echo "No control.config found in: $HOME/.config/spotifice, $REPO_ROOT, /etc/spotifice" >&2
  exit 2
fi

exec python3 "$REPO_ROOT/media_control_v1.py" "$CFG"
WRAP
  chmod +x "$WRAPPER_DEST"
  printf 'Installed wrapper: %s\n' "$WRAPPER_DEST"
}

install_all() {
  # Install desktop entry
  if [ ! -f "$DESKTOP_SRC" ]; then
    echo "Error: desktop file not found: $DESKTOP_SRC" >&2
    exit 1
  fi
  run mkdir -p "$APPLICATIONS_DIR"
  run cp "$DESKTOP_SRC" "$DESKTOP_DEST"
  printf 'Installed desktop: %s\n' "$DESKTOP_DEST"
  # Ensure Exec/TryExec point to absolute wrapper path
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] sed -i -e s|^Exec=.*|Exec=%s| -e s|^TryExec=.*|TryExec=%s| %s\n' "$WRAPPER_DEST" "$WRAPPER_DEST" "$DESKTOP_DEST"
  else
    sed -i \
      -e "s|^Exec=.*|Exec=$WRAPPER_DEST|" \
      -e "s|^TryExec=.*|TryExec=$WRAPPER_DEST|" \
      "$DESKTOP_DEST"
  fi

  # Install icon and wrapper
  install_icon
  make_wrapper

  # Refresh desktop database if available
  if command -v update-desktop-database >/dev/null 2>&1; then
    run update-desktop-database "$APPLICATIONS_DIR"
  fi
}

uninstall_all() {
  run rm -f "$WRAPPER_DEST"
  printf 'Removed wrapper (if existed): %s\n' "$WRAPPER_DEST"
  run rm -f "$DESKTOP_DEST"
  printf 'Removed desktop (if existed): %s\n' "$DESKTOP_DEST"
  if command -v update-desktop-database >/dev/null 2>&1; then
    run update-desktop-database "$APPLICATIONS_DIR"
  fi
}

CMD="install"
while [ $# -gt 0 ]; do
  case "$1" in
    install|uninstall|print-dirs) CMD="$1"; shift ;;
    -p|--prefix) [ $# -ge 2 ] || { echo "--prefix requires a value" >&2; exit 2; }; PREFIX="$2"; shift 2 ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

# Recompute dependent dirs for new prefix (in case --prefix was provided)
APPLICATIONS_DIR="$PREFIX/share/applications"
DESKTOP_DEST="$APPLICATIONS_DIR/${APP_ID}.desktop"
BIN_DIR="$PREFIX/bin"
WRAPPER_DEST="$BIN_DIR/spotifice-control"
ICON_THEME_DIR="$PREFIX/share/icons/hicolor"
ICON_DIR="$ICON_THEME_DIR/scalable/apps"
ICON_DEST="$ICON_DIR/${APP_ID}.svg"

case "$CMD" in
  install)   install_all ;;
  uninstall) uninstall_all ;;
  print-dirs) print_dirs ;;
esac
