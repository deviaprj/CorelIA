#!/bin/bash
# Build Corely AppImage for Linux
# Usage: bash scripts/build_appimage.sh [version]
set -euo pipefail

VERSION="${1:-1.0.0}"
APP_NAME="Corely"
BUILD_DIR="build/linux/x64/release/bundle"
APPDIR="/tmp/${APP_NAME}-AppDir"

echo "=== Corely AppImage Builder v${VERSION} ==="

# Clean previous
rm -rf "${APPDIR}" "${APP_NAME}-${VERSION}-x86_64.AppImage"

# Create AppDir structure
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"
mkdir -p "${APPDIR}/usr/lib"

# Copy Flutter bundle
echo "Copying Flutter bundle..."
cp -r "${BUILD_DIR}/data" "${APPDIR}/usr/bin/"
cp -r "${BUILD_DIR}/lib" "${APPDIR}/usr/lib/"
cp "${BUILD_DIR}/corely" "${APPDIR}/usr/bin/corely"

# Create .desktop file
cat > "${APPDIR}/usr/share/applications/com.corelia.app.desktop" << DESKTOPEOF
[Desktop Entry]
Version=${VERSION}
Name=Corely
Comment=AI Desktop Assistant — Chat, Agent & Productivity
Exec=corely
Terminal=false
Type=Application
Icon=corely
Categories=Office;Utility;ArtificialIntelligence;
Keywords=AI;Assistant;Chat;Agent;Productivity;
StartupWMClass=corely
DESKTOPEOF

# Copy icon (placeholder — replace with actual icon PNG)
cp web/icons/Icon-192.png "${APPDIR}/usr/share/icons/hicolor/256x256/apps/corely.png" 2>/dev/null || true
cp "${APPDIR}/usr/share/icons/hicolor/256x256/apps/corely.png" "${APPDIR}/corely.png" 2>/dev/null || true

# Create AppRun
cat > "${APPDIR}/AppRun" << 'APPRUNEOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export LD_LIBRARY_PATH="${HERE}/usr/lib:$LD_LIBRARY_PATH"
exec "${HERE}/usr/bin/corely" "$@"
APPRUNEOF
chmod +x "${APPDIR}/AppRun"

# Download linuxdeploy if needed
if ! command -v linuxdeploy-x86_64.AppImage &> /dev/null; then
    echo "Downloading linuxdeploy..."
    wget -q "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage" -O /tmp/linuxdeploy.AppImage
    chmod +x /tmp/linuxdeploy.AppImage
    LINUXDEPLOY="/tmp/linuxdeploy.AppImage"
else
    LINUXDEPLOY="linuxdeploy-x86_64.AppImage"
fi

# Build AppImage
echo "Building AppImage..."
${LINUXDEPLOY} --appdir "${APPDIR}" --output appimage 2>/dev/null || {
    echo "linuxdeploy failed, creating AppImage manually..."
    # Manual fallback
    mksquashfs "${APPDIR}" "/tmp/${APP_NAME}.squashfs" -root-owned -noappend
    cat /tmp/runtime-x86_64 "/tmp/${APP_NAME}.squashfs" > "${APP_NAME}-${VERSION}-x86_64.AppImage"
    chmod +x "${APP_NAME}-${VERSION}-x86_64.AppImage"
}

echo ""
echo "=== Done ==="
echo "Package: ${APP_NAME}-${VERSION}-x86_64.AppImage"
echo "  or:    build/linux/x64/release/corely-${VERSION}-Linux.deb (via CPack)"
ls -lh *.AppImage 2>/dev/null || ls -lh build/linux/x64/release/*.deb 2>/dev/null || echo "(no package built — run on a Flutter build machine)"
