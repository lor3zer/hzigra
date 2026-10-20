#!/usr/bin/env bash
# Установка или обновление сервера Nitro Rush на Armbian / Debian / Ubuntu.
# Запуск из папки с распакованным архивом:  sudo ./install.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
	echo "Запустите через sudo: sudo ./install.sh"
	exit 1
fi
DIR="$(cd "$(dirname "$0")" && pwd)"

case "$(uname -m)" in
	aarch64 | arm64) BIN=NitroRushServer.arm64 ;;
	armv7l | armv8l | armhf) BIN=NitroRushServer.armhf ;;
	x86_64 | amd64) BIN=NitroRushServer.x86_64 ;;
	*) echo "Архитектура $(uname -m) не поддерживается"; exit 1 ;;
esac
if [ ! -f "$DIR/$BIN" ]; then
	echo "Рядом со скриптом нет файла $BIN — скачайте архив для своей архитектуры ($(uname -m))"
	exit 1
fi

# отдельный системный пользователь без входа в систему
if ! id nitrorush > /dev/null 2>&1; then
	useradd --system --home-dir /var/lib/nitrorush --create-home --shell /usr/sbin/nologin nitrorush
fi

install -d -m 755 /opt/nitrorush
install -m 755 "$DIR/$BIN" /opt/nitrorush/NitroRushServer
# настройки не перезаписываем при обновлении
if [ ! -f /etc/default/nitrorush ]; then
	install -m 644 "$DIR/nitrorush.conf" /etc/default/nitrorush
fi
install -m 644 "$DIR/nitrorush-server.service" /etc/systemd/system/nitrorush-server.service

systemctl daemon-reload
systemctl enable nitrorush-server > /dev/null
systemctl restart nitrorush-server

# открыть порт в ufw, если он включён
# shellcheck disable=SC1091
. /etc/default/nitrorush
if command -v ufw > /dev/null && ufw status | grep -q "Status: active"; then
	ufw allow "${PORT:-24680}/udp" > /dev/null
	ufw allow 24681/udp > /dev/null
	echo "ufw: открыты UDP ${PORT:-24680} и 24681"
fi

sleep 2
systemctl --no-pager --lines=8 status nitrorush-server || true
echo
echo "Готово. Логи:      journalctl -u nitrorush-server -f"
echo "Настройки:         sudo nano /etc/default/nitrorush  (потом sudo systemctl restart nitrorush-server)"
echo "Адреса этой платы: $(hostname -I 2> /dev/null || true)"
