# Agent360 installer and uninstaller

This repository contains bash scripts for installing and removing the Agent360 monitoring agent on Linux hosts.

## Requirements

- Root access
- A supported Linux distribution
- A valid Agent360 token or user ID
- Bash available on the target host

## Install

```bash
sudo ./agent360.sh --token <token>
```

Additional options:

```bash
sudo ./agent360.sh --help
```

Common flags:

- --token <token> : Agent360 token or user ID
- --tags <tag1,tag2> : Optional comma-separated tags
- --use-venv : Install in /opt/agent360-venv
- --skip-deps : Skip OS package installation
- --force : Reinstall or continue despite existing install state
- --add-websites : Enable website auto-monitoring when supported by the target host

Example with a virtual environment:

```bash
sudo ./agent360.sh --token <token> --use-venv --tags prod,web
```

## Uninstall

```bash
sudo ./uninstall-agent360.sh
```

The uninstaller:

- stops and disables the installed service
- removes the agent360 symlinks created by a venv or system install
- removes the venv only when the user confirms it
- removes config and token files that belong to this install
- optionally removes the agent360 log files

## Notes

- The scripts manage both system-level installs and venv-based installs.
- Service setup covers systemd, SysV, and the FreeBSD branch when applicable.
- The venv install keeps the agent executable isolated under /opt/agent360-venv while still wiring the service to the correct binary.
- The project intentionally avoids recursive ownership changes of the whole venv; only the executable entrypoints are adjusted.

## Related warning

cPanel integrations may sometimes return 404 errors depending on the hosting environment. See the official cPanel documentation for platform-specific guidance:

https://support.cpanel.net/hc/en-us/articles/30814926304151-360-monitoring-plugin-error-404-Error-POST-https-api-monitoring360-io-metrics-get-metrics-data-404