#!/usr/bin/env bash
# Uninstall agent360 without removing unrelated Python packages or user files.

set -o nounset

venv_dir="/opt/agent360-venv"
service_file="/etc/systemd/system/agent360.service"
requirements_file="/opt/agent360-requirements.txt"

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Uninstall must be run as root."
  exit 1
fi

run() {
  local description="$1"
  shift
  if "$@"; then
    echo "[SUCCESS] $description"
  else
    echo "[WARNING] $description could not be completed."
  fi
}

remove_link_to_venv() {
  local link_path="$1"
  local expected_target="$2"

  if [ -L "$link_path" ] && [ "$(readlink -f "$link_path")" = "$expected_target" ]; then
    run "Removed $link_path" rm -f "$link_path"
    return
  fi

  if [ -L "$link_path" ]; then
    run "Removed stale symlink $link_path" rm -f "$link_path"
  fi
}

pip_uninstall() {
  local python_bin="$1"
  local -a pip_args=(uninstall -y agent360)

  if "$python_bin" -c 'import os, sysconfig; raise SystemExit(not os.path.exists(os.path.join(sysconfig.get_path("stdlib"), "EXTERNALLY-MANAGED")))'; then
    pip_args+=(--break-system-packages)
  fi

  if "$python_bin" -m pip show agent360 >/dev/null 2>&1; then
    run "Removed the agent360 Python package" "$python_bin" -m pip "${pip_args[@]}"
  else
    echo "[INFO] agent360 is not installed for $python_bin."
  fi
}

if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files agent360.service >/dev/null 2>&1 || [ -f "$service_file" ]; then
    run "Stopped agent360 service" systemctl stop agent360.service
    run "Disabled agent360 service" systemctl disable agent360.service
  fi
  if [ -f "$service_file" ]; then
    run "Removed the systemd service definition" rm -f "$service_file"
    run "Reloaded systemd" systemctl daemon-reload
    systemctl reset-failed agent360.service >/dev/null 2>&1 || true
  fi
fi

if [ -x /etc/init.d/agent360 ]; then
  run "Stopped the SysV service" service agent360 stop
  run "Removed the SysV service definition" rm -f /etc/init.d/agent360
fi

# Remove the agent360 symlinks created by either a venv install or a pip install.
# This is intentionally broader than the old venv-only cleanup and avoids leaving
# dead command links behind on systems that installed the agent globally.
remove_link_to_venv /usr/local/bin/agent360 "$venv_dir/bin/agent360"
remove_link_to_venv /usr/local/bin/hello360 "$venv_dir/bin/hello360"
if [ -e /usr/local/bin/agent360 ] && [ "$(basename /usr/local/bin/agent360)" = "agent360" ]; then
  run "Removed /usr/local/bin/agent360" rm -f /usr/local/bin/agent360
fi
if [ -e /usr/local/bin/hello360 ] && [ "$(basename /usr/local/bin/hello360)" = "hello360" ]; then
  run "Removed /usr/local/bin/hello360" rm -f /usr/local/bin/hello360
fi

if [ -x "$venv_dir/bin/python" ]; then
  read -r -p "Remove the agent360 virtual environment at $venv_dir? [y/N] " remove_venv
  if [[ "$remove_venv" =~ ^[Yy]$ ]]; then
    run "Removed the agent360 virtual environment" rm -rf "$venv_dir"
  else
    pip_uninstall "$venv_dir/bin/python"
    echo "[INFO] Kept $venv_dir; its remaining packages were not removed."
  fi
fi

if command -v python3 >/dev/null 2>&1; then
  pip_uninstall python3
fi

if id agent360 >/dev/null 2>&1; then
  run "Deleted the agent360 system user" userdel agent360
fi

for path in /etc/agent360.ini /etc/agent360-token.ini "$requirements_file"; do
  if [ -e "$path" ]; then
    run "Removed $path" rm -f "$path"
  fi
done

if [ -d /root/.360monitoring ]; then
  run "Removed /root/.360monitoring" rm -rf /root/.360monitoring
fi

if [ -e /var/log/agent360.log ] || [ -e /var/log/agent360-install.log ]; then
  read -r -p "Remove agent360 logs? [y/N] " remove_logs
  if [[ "$remove_logs" =~ ^[Yy]$ ]]; then
    run "Removed agent360 logs" rm -f /var/log/agent360.log /var/log/agent360-install.log
  else
    echo "[INFO] Logs were kept."
  fi
fi

echo "[SUCCESS] agent360 uninstall is complete."
