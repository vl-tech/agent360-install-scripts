## Agent 360 script for installation of 360 monitoring
- Available usage options

```bash
./agent360.sh --help
Usage: Positional arguments for agents360.sh script.

./agent360.sh [--args| ARG..] [--args| ARG..]

--help|--h                       Displays this information

--skip-deps --skip-dep-install  Skip OS package instalation

--user-venv                     Install agent in virtual environment

--force                         Install even if agent360 is already instaled

--token <token value>           360 Monitoring account User ID:

```

- Positional argument error handling
```bash
./agent360.sh -h
[CRITICAL] Invalid Token. Please enter valid User ID

[WARNING] You can check it at 360monitoring.com -> Servers -> Add server

Direct page URL: https://app.360monitoring.com/servers/overview
```


- Installation example with token and virtual environment
```bash
./agent360.sh token --use-venv 

```

![Installation](/screenshots/Installation.png)




- Agent service working with venv

![usage](screenshots/service.png)


## Regular installation requires only a token to run.

```bash
/agent360.sh token
```

## uninstallation script works for both venv version and non-venv

```bash
./uninstall-agent360.sh
```

![uninstallation](screenshots/uninstalation.png)