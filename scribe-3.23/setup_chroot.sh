#!/bin/sh
set -eu
export PATH=/sbin:/usr/sbin:/bin:/usr/bin
export HOME=/root
echo kindle > /etc/hostname

echo "### alpine release"
cat /etc/alpine-release
echo "### update/upgrade"
apk update
apk upgrade
cat /etc/alpine-release

echo "### base tools"
apk add xorg-server-xephyr xwininfo xdotool xinput dbus-x11 sudo bash nano git

echo "### mate base + themes"
# consolekit was replaced by elogind; gnome-themes-extra no longer exists in 3.23 armv7.
apk add desktop-file-utils gtk-engines gtk-murrine-engine caja caja-extensions marco elogind

echo "### all mate packages (repo method)"
apk add $(apk search -q mate | grep -v -- '-dev$' | grep -v -- '-lang$' | grep -v -- '-doc$')

echo "### all fonts (ttf-* packages no longer exist in 3.23 armv7)"
apk add font-noto-cjk font-noto-emoji

echo "### browser + onscreen keyboard"
apk add onboard chromium

echo "### bridge mode packages (host X is 8-bit, Chromium needs 24-bit)"
apk add xvfb xwd xdpyinfo py3-pillow

echo "### chromium version"
chromium --version 2>&1 || true
cat /etc/alpine-release

echo "### user"
adduser -D -s /bin/bash alpine
printf 'alpine\nalpine\n' | passwd alpine
addgroup sudo 2>/dev/null || true
addgroup alpine sudo
echo '%sudo ALL=(ALL) ALL' >> /etc/sudoers

echo "### dotfiles"
su - alpine -c '
set -e
cd "$HOME"
git init -q
git remote add origin https://github.com/schuhumi/alpine_kindle_dotfiles
git fetch -q --depth=1 origin master
git reset -q --hard FETCH_HEAD
ls -la .config | head
'

echo "### dconf"
su - alpine -c 'dbus-run-session -- sh -c "dconf load /org/mate/ < ~/.config/org_mate.dconf.dump && dconf load /org/onboard/ < ~/.config/org_onboard.dconf.dump && echo dconf-ok"'

echo "### lockscreen keyboard (alpine-mate-better reference)"
su - alpine -c 'dbus-run-session -- sh -c "gsettings set org.mate.screensaver embedded-keyboard-enabled true && gsettings set org.mate.screensaver embedded-keyboard-command onboard && echo gsettings-ok"'

echo "### chromium config"
mkdir -p /etc/chromium /usr/share/chromium/extensions /run/dbus
cat > /etc/chromium/chromium.conf <<'CHROMIUMCONF'
# Default settings for chromium. This file is sourced by /bin/sh from
# the chromium launcher.

# Options to pass to chromium.
mouseid="$(env DISPLAY=:1 xinput list --id-only "Xephyr virtual mouse" 2>/dev/null)"
CHROMIUM_FLAGS='--force-device-scale-factor=2 --pull-to-refresh=1 --disable-smooth-scrolling --enable-low-end-device-mode --disable-login-animations --disable-modal-animations --wm-window-animations-disabled --no-first-run --no-default-browser-check --start-maximized --user-agent=Mozilla%2F5.0%20%28Linux%3B%20Android%207.0%3B%20SM-G930V%20Build%2FNRD90M%29%20AppleWebKit%2F537.36%20%28KHTML%2C%20like%20Gecko%29%20Chrome%2F59.0.3071.125%20Mobile%20Safari%2F537.36'
[ -n "$mouseid" ] && CHROMIUM_FLAGS="$CHROMIUM_FLAGS --touch-devices=$mouseid"
CHROMIUMCONF

# uBlock Origin (MV2) is disabled by modern Chromium; use uBlock Origin Lite (MV3).
cat > /usr/share/chromium/extensions/ddkjiahejlhfcafbddmgiahcphecmpfh.json <<'UBLOCK'
{
	"external_update_url": "https://clients2.google.com/service/update2/crx"
}
UBLOCK

echo "### startgui + bridge assets"
mkdir -p /usr/local/bin /usr/local/lib/kindle-glibc
cp /tmp/assets/startgui.sh /startgui.sh
cp /tmp/assets/bridge.py /usr/local/bin/bridge.py
cp /tmp/assets/touch.py /usr/local/bin/touch.py
cp /tmp/assets/fbink.bin /usr/local/bin/fbink.bin
cp /tmp/assets/ld-linux-armhf.so.3 /tmp/assets/libc.so.6 /tmp/assets/libm.so.6 /usr/local/lib/kindle-glibc/
cat > /usr/local/bin/fbink <<'FBINK'
#!/bin/sh
exec /usr/local/lib/kindle-glibc/ld-linux-armhf.so.3 --library-path /usr/local/lib/kindle-glibc /usr/local/bin/fbink.bin "$@"
FBINK
chmod +x /startgui.sh /usr/local/bin/bridge.py /usr/local/bin/touch.py \
         /usr/local/bin/fbink /usr/local/bin/fbink.bin

echo "### package summary"
apk list --installed | wc -l
du -sh / 2>/dev/null || true
cat /etc/alpine-release
chromium --version 2>&1 || true
echo "### setup complete"
