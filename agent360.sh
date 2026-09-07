#!/bin/bash

#: Variables :#
set -o nounset
# Some Python package build scripts read UTF-8 metadata.  `C` is ASCII-only.
export LC_ALL=C.UTF-8
# agent360_repo_source="https://github.com/plesk/agent360.git"
install_log="/var/log/agent360-install.log"
log_file="/var/log/agent360.log"
default_bin="/usr/local/bin/agent360"
agent_config_file="/etc/agent360.ini"
agent_token_file="/etc/agent360-token.ini"
config_tpl="https://monitoring.platform360.io/agent360.ini"
agent_sysd_service="/etc/systemd/system/agent360.service"
agent_sysv_service="/etc/init.d/agent360"
agent_bsd_service="/etc/rc.d/agent360"
venv_dir="/opt/agent360-venv"
requirements_file="/opt/agent360-requirements.txt"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bundled_requirements_file="$script_dir/requirements.txt"

rhel_os_list=( "centos" "almalinux" "cloudlinux" "amazon" "fedora" "sangoma" "oracle" "scientific" "freepbx" "rhel" "virtuozzo" "rocky" )
deb_os_list=( "ubuntu" "debian" )
free_os_list=( "freebsd" )
servers_tab_url="https://app.360monitoring.com/servers/overview"
default_pkgs=( "gcc" )
deb_py_pkgs=( "python3-dev" "python3-setuptools" "python3-venv" "python3-pip")
rhel_py_pkgs=( "which" "python3" "python3-devel" "libevent-devel" )

#: Check root privilege :#
if [ "$(id -u)" != "0" ];
then
   echo -e "\\e[31m[ERROR] Installer needs root permission to run, please run as root.\\e[m"
   exit 1
fi


usage() {
cat << EOF
Usage: ./agent360.sh [OPTIONS] <token> [tags]

Options:
  --help, --h, -h                 Display this information
  --skip-deps, --skip-dep-install Skip OS package installation
  --use-venv                      Install the agent in a virtual environment
  --force                         Install even if agent360 is already installed
  --token <token>                 360 Monitoring account user ID
  --tags <tags>                   Comma-separated tags for the server
  --add-websites                  Enable website auto-monitoring

EOF


}
#######################
## PROCESS ARGUMENTS ##
#######################

automon=0
skip_deps=0
use_venv=0
force=0
token=
tags=
declare -a positional_args=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-deps|--skip-dep-install)
      skip_deps=1
      shift
      ;;
    --use-venv)
      use_venv=1
      shift
      ;;
    --force)
      force=1
      shift
      ;;
    --token)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo -e "\\e[31m[ERROR] --token requires a value.\\e[m"
        usage
        exit 2
      fi
      token="$2"
      shift 2
      ;;
    --tags)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo -e "\\e[31m[ERROR] --tags requires a value.\\e[m"
        usage
        exit 2
      fi
      tags="$2"
      shift 2
      ;;
    # As I read it the older code just accept add-websites as an argument
	# This does not work. The function seems to be missing. probably because it is being added from the website directly
    add-websites|--add-websites)
      automon=1
      shift
      ;;
	--help|--h|-h)
	  usage
	  exit 0
	;;
    --)
      shift
      positional_args+=("$@")
      break
      ;;
    -*)
      echo -e "\\e[31m[ERROR] Unknown option: $1\\e[m"
      usage
      exit 2
      ;;
    *)
      positional_args+=("$1")
      shift;
      ;;
  esac
done



# Accept both positional and named token/tag syntax.
positional_index=0
if [[ -z "$token" && ${#positional_args[@]} -gt 0 ]]; then
    token="${positional_args[0]}"
    positional_index=1
fi
if [[ -z "$tags" && ${#positional_args[@]} -gt "$positional_index" ]]; then
    tags="${positional_args[$positional_index]}"
    ((positional_index++))
fi
if [[ ${#positional_args[@]} -gt "$positional_index" ]]; then
    echo -e "\\e[31m[ERROR] Too many positional arguments.\\e[m"
    usage
    exit 2
fi

if [[ -z "$token" ]]; then
    echo -e "\\e[31m[WARNING] Please provide User ID or Token to register your server\\e[m"
	echo
	echo -e "\\e[31m[WARNING] You can check it at 360monitoring.com -> Servers -> Add server\\e[m"
	echo
	echo -e "\\e[31mDirect page URL: ${servers_tab_url}\\e[m"
	usage
    exit 1
fi

# Checking for valid token. From what I see so far token is 24 characters in length 
if [[ ${#token} -lt 24 ]];then
	echo -e "\\e[31m[CRITICAL] Invalid Token. Please enter valid User ID\\e[m"
	echo
	echo -e "\\e[31m[WARNING] You can check it at 360monitoring.com -> Servers -> Add server\\e[m"
	echo
	echo -e "\\e[31mDirect page URL: ${servers_tab_url}\\e[m"
	exit 1
fi


#######################
## Library functions ##
#######################

#: Functions :#
logging(){
	dt=`date "+%Y-%m-%d %H:%M:%S"`
	echo -e '['$dt'] Executing: '$@ >> "$install_log" 2>&1
    "$@" >> "$install_log" 2>&1
}
## Checking if wget is installed. If not will activate below script to install it.
## This is due to an error that occurs when its not installed
check_wget(){
	get_installer
	if ! command -v wget &> /dev/null;then
		echo -e "\\e[31m[CRITICAL] Wget command not found\\e[m"
		echo -e "Installing wget"
		install "$installer" wget
	else
		echo -e "\\e[33m[NOTE] Wget already installed. Continuing Agent360 installation\\e[m"
	fi
}


error_handling(){
	rc=$?
	if [ "$rc" != "0" ]; then
		if [ $# -eq 0 ]; then
			echo -e "\\e[31m[ERROR] An error occurred. Please check the log ${install_log} for details\\e[m"
		else
			echo -e "\\e[31m[CRITICAL] A critical error occurred!\\e[m"
			echo -e "\\e[31mThe installation aborted, please check the log ${install_log}\\e[m"
			exit 1
		fi
	fi
}


create_requirements_file() {
    # Let pip resolve the newest mutually compatible release set on every run.
    if [ -r "$bundled_requirements_file" ]; then
        cp "$bundled_requirements_file" "$requirements_file"
        return
    fi
    # Keep the installer usable when it has been downloaded without the repo.
    cat > "$requirements_file" <<'CURRENT_REQUIREMENTS'
# Keep agent360 and all compatible transitive dependencies current.
agent360
# Python 3.6 is shipped by AlmaLinux/RHEL 8.  psutil 7 no longer supports it.
psutil<7; python_version < "3.7"
CURRENT_REQUIREMENTS
}
get_os_release(){
	if [[ ! -r /etc/os-release ]]; then
		echo -e "\\e[31m  [ERROR] Unable to read /etc/os-release\\e[m"
		exit 1
	fi

	# os-release provides machine-readable ID and VERSION_ID values.
	. /etc/os-release
	OS_RELEASE="${NAME:-}"
	OS_NAME="${ID:-}"
	if [[ -z "$OS_RELEASE" || -z "$OS_NAME" ]]; then
		echo -e "\\e[31m  [ERROR] Unable to determine the Linux distribution name\\e[m"
		exit 1
	fi
}

## Changed the behaviour ofthis check due to issue with Cento 7 that has (core) in its name 
## Reported error: (Core): syntax error in expression (error token is "(Core)")
get_os_version(){
	VERSION="${VERSION_ID:-${VERSION:-}}"
	OS_VERSION="${VERSION%%.*}"
	OS_VERSION="${OS_VERSION%% *}"
	if [[ ! "$OS_VERSION" =~ ^[0-9]+$ ]]; then
		echo -e "\\e[31m  [ERROR] Unable to determine a numeric distribution version\\e[m"
		exit 1
	fi
}


check_cagefs_status_and_cofiguration(){
	agent360GID=$(getent group agent360 | cut -d: -f3)
	STATUS=$(cagefsctl --cagefs-status 2>/dev/null)
	if [[ $STATUS ]]
	then 
	echo -e "\\e[33m[INFO]Cagefs is Enabled\\e[m"
	echo -e "\\e[33m[INFO]Configuring agent360 for cagefs\\e[m"
	logging echo -e "fs.proc_super_gid=$agent360GID" >> /etc/sysctl.conf && sysctl -p && echo -e "\\e[32m[SUCCESS]Configuring /etc/sysctl.conf  \\e[m" || error_handling fatal

	echo -e "\\e[33m[INFO]Configuring agent360 exclude file (/etc/cagefs/exclude/systemuserlist) for cagefs\\e[m"
	logging echo -e "agent360" >> /etc/cagefs/exclude/systemuserlist && cagefsctl --force-update || error_handling fatal

	logging systemctl restart lve_namespaces && echo -e "\\e[32m[SUCCESS]Configuring agent360 for cagefs\\e[m" || error_handling fatal
	else
	echo -e "\\e[33m[INFO]CageFS is not enabled. No need to configure it for agent360 user\\e[m"
	fi
}

get_installer(){
	case "$OS_NAME" in
		centos|almalinux|cloudlinux|amazon|fedora|sangoma|oracle|scientific|freepbx|rhel|virtuozzo|rocky)
			installer="yum"
			;;
		ubuntu|debian)
			installer="apt-get"
			logging apt-get update || error_handling fatal
			;;
		freebsd)
			installer="pkg"
			;;
		*)
			echo -e "\\e[31m  [ERROR] Unsupported operating system: ${OS_NAME}\\e[m"
			exit 1
			;;
	esac
}

check_agent360(){
   if command -v agent360 &> /dev/null; then
      agent360_installed=true
	  
   else
       if [[ $force == 0 ]]; then
         if id agent360 &>/dev/null; then
           echo -e "\\e[33m  [ERROR] The user agent360 already exists, aborting installation\\e[m"
           exit 1
         fi
      fi
      agent360_installed=false
   fi
}

get_agent_path(){
	if command -v agent360 &> /dev/null; then
		agent360_path=$(command -v agent360)
	else
		agent360_path=$default_bin
	fi
}

install(){
	pkg_mng=$1
	shift
	logging "$pkg_mng" install -y "$@" && echo -e "\\e[32m[SUCCESS] All the necessary packages were installed\\e[m" || error_handling fatal
}

prepare_pkgs(){
	os_n=$1
	os_v=$2
	if [[ ($os_n == "debian" && $os_v -ge 10) || ($os_n == "ubuntu"  && $os_v -ge 18) ]]; then
		pkg_list=( "${default_pkgs[@]}" "${deb_py_pkgs[@]}" )
	elif [[ "${rhel_os_list[*]}" == *"$os_n"* && $os_v -ge 7 ]]; then
		pkg_list=( "${default_pkgs[@]}" "${rhel_py_pkgs[@]}" )
	else
		echo -e "\\e[31m  [ERROR] Could not prepare the list of packages for installation\\e[m"
		exit 1
	fi
}



install_agent360(){
	ins_state=$1
	if [ "$ins_state" = "false" ]; then
		echo "> Installing agent360..."
	else
		echo "> Upgrading agent360..."
	fi
	
  

	if [ "$use_venv" -eq 1 ]; then
		# Activating a venv inside logging would affect only its child process.
		if [ ! -x "$venv_dir/bin/python" ]; then
			logging python3 -m venv "$venv_dir" && echo -e "\\e[32m[SUCCESS] Virtual environment has been created\\e[m" || error_handling fatal
		fi
		# EL8 ships Python 3.6 and pip 9.  Upgrade to the newest pip that still
		# supports it before resolving modern package metadata.
		if "$venv_dir/bin/python" -c 'import sys; raise SystemExit(not (sys.version_info < (3, 7)))'; then
			logging "$venv_dir/bin/python" -m pip install --upgrade 'pip<22' || error_handling fatal
		else
			logging "$venv_dir/bin/python" -m pip install --upgrade pip || error_handling fatal
		fi
		logging "$venv_dir/bin/python" -m pip install --upgrade --upgrade-strategy eager -r "$requirements_file" && echo -e "\\e[32m[SUCCESS] Finished with agent360\\e[m" || error_handling fatal
		## Disabled deactivation of venv because it exists the script
		## And we need to setup the systemd service regardless if it is using venv or not
		# logging Deactivate
		echo "Creating Symlinks $venv_dir/bin/agent360 /usr/local/bin/agent360"
		# Create a symlink for global access
		logging ln -sf "$venv_dir/bin/agent360" /usr/local/bin/agent360
		logging ln -sf "$venv_dir/bin/hello360" /usr/local/bin/hello360
	else
		if python3 -c 'import sys; raise SystemExit(not (sys.version_info < (3, 7)))'; then
			logging python3 -m pip install --upgrade 'pip<22' || error_handling fatal
		else
			logging python3 -m pip install --upgrade pip || error_handling fatal
		fi
		pip_args=(install --upgrade --upgrade-strategy eager -r "$requirements_file")
		# PEP 668 is signalled by this marker; it is not tied to an Ubuntu release.
		if python3 -c 'import os, sysconfig; raise SystemExit(not os.path.exists(os.path.join(sysconfig.get_path("stdlib"), "EXTERNALLY-MANAGED")))'; then
			pip_args+=(--break-system-packages)
		fi
		logging python3 -m pip "${pip_args[@]}" && echo -e "\\e[32m[SUCCESS] Finished with agent360\\e[m" || error_handling fatal
	fi
	echo -e "\\e[32m[SUCCESS] agent360 installed\\e[m"
}

prepare_conf(){
	## Placed the wget check here because it is where it fails when preparing the installation
	## This will later be called after install_agent360 function at the Run script section
	check_wget
	echo "> Preparing the agent360 configuration..."
	if [[ !(-f $agent_config_file) || !($(cat ${agent_config_file} | wc -l) -gt 1) ]]; then
		logging wget -qO $agent_config_file $config_tpl && echo -e "\\e[32m[SUCCESS] The default template for agent360 has been installed\\e[m" || error_handling
	fi

	echo "> Generating a server ID..."
	if [ ! -f $agent_token_file ]; then
		
		logging hello360 $token $agent_token_file --automon=$automon --tags=$tags
		error_handling
		server_id=$(grep server ${agent_token_file} | cut -f2 -d '=' | tr -d ' ')
		echo -e "\\e[32m[SUCCESS] The server token has been generated: ${server_id}\\e[m"
	else
		server_id=$(agent360 info | grep 'Server:' | cut -d':' -f2 | tr -d ' ')
		echo -e "\\e[33m[NOTE] The server already has the ID in ${agent_token_file}: ${server_id}\\e[m"
	fi
}

create_user(){
	if id agent360 &>/dev/null; then
		echo -e "\\e[33m[NOTE] The user already exists\\e[m"
	else
		logging useradd --system --user-group --key USERGROUPS_ENAB=yes -M agent360 --shell /bin/false
		error_handling
		if id agent360 &>/dev/null; then
			echo -e "\\e[32m[SUCCESS] The user has been created\\e[m"
		else
			echo -e "\\e[31m[ERROR] Failed to create the user\\e[m"
		fi
	fi

  logging chown agent360 $agent_config_file
  logging chown agent360 $agent_token_file
  logging chown agent360 $log_file
  logging chown agent360 $install_log
  logging chmod 640 $agent_config_file
  logging chmod 640 $agent_token_file
  logging chmod 640 $log_file
  logging chmod 640 $install_log
}

service_check(){
	srv_type=$1
	if [ $(cat ${srv_type} | wc -l) -gt 0 ]; then
		echo -e "\\e[32m[SUCCESS] The service has been created\\e[m"
		echo "> Trying to enable and start the service..."
		if [ $srv_type == $agent_sysd_service ]; then
			logging chmod 644 $agent_sysd_service &&
			logging systemctl daemon-reload &&
			logging systemctl enable agent360 &&
			logging systemctl start agent360 &&
			echo -e "\\e[32m[SUCCESS] The service has been configured\\e[m"
		elif [ $srv_type == $agent_sysv_service ]; then
			logging chmod +x $agent_sysv_service &&
			logging chkconfig --add agent360 &&
			logging chkconfig agent360 on &&
			logging service agent360 start &&
			echo -e "\\e[32m  [SUCCESS] The service has been configured\\e[m"
		elif [ "$srv_type" == "$agent_bsd_service" ]; then
			logging chmod +x $agent_bsd_service &&
			logging echo $'\n'"agent360_enable=\"YES\"" >> /etc/rc.conf &&
			logging service agent360 start &&
			echo -e "\\e[32m[SUCCESS] The service has been configured\\e[m"
		fi
		error_handling
	else
		echo -e "\\e[31m[ERROR] The service has not been created.\\e[m"
	fi
}
## Added Restart on failure and another function to setup systemd service with venv
systemD_config(){
	cat <<EOF >$agent_sysd_service
		[Unit]
		Description=agent360

		[Service]
		ExecStart=$agent360_path
		Restart=on-failure
		User=root

		[Install]
		WantedBy=multi-user.target
EOF
	service_check $agent_sysd_service
	echo -e "\\e[33m[NOTE] Restarting the Agent service\\e[m"
	systemctl restart agent360.service
}

## Systemd service working with agent360 user and venv. I'v set it for better security.
## Needs testing if it will be able to report all metrics . Possible permission denied errors

systemD_config_venv(){
	venv_command_path='/opt/agent360-venv/bin/agent360'
	create_user
	echo "Setting up user agent360 permissions"
	# Only adjust the actual executable entrypoints. A recursive chown on the full
	# venv can break packages or libraries installed in the same environment.
	for executable in "$venv_command_path" "$venv_dir/bin/hello360"; do
		if [ -e "$executable" ]; then
			chown agent360:agent360 "$executable"
			chmod 755 "$executable"
		fi
	done
	cat <<EOF >$agent_sysd_service
		[Unit]
		Description=agent360

		[Service]
		ExecStart=$venv_command_path
		Restart=on-failure

		User=agent360

		[Install]
		WantedBy=multi-user.target
EOF
service_check $agent_sysd_service
echo -e "\\e[33m[NOTE] Restarting the Agent service\\e[m"
systemctl restart agent360.service
}

bsd_config(){
	cat <<EOF >$agent_bsd_service
		#!/bin/sh
		#
		# PROVIDE: agent360
		# REQUIRE: networking
		# KEYWORD: shutdown

		. /etc/rc.subr

		name="agent360"
		rcvar="\${name}_enable"

		load_rc_config \$name
		: \${agent360_enable:=no}
		: \${agent360_bin_path="/usr/local/bin/agent360"}
		: \${agent360_run_user="agent360"}

		pidfile="/var/run/agent360.pid"
		logfile="/var/log/agent360.log"

		command="\${agent360_bin_path}"

		start_cmd="agent360_start"
		status_cmd="agent360_status"
		stop_cmd="agent360_stop"

		agent360_start() {
			echo "Starting \${name}..."
			/usr/sbin/daemon -u \${agent360_run_user} -c -p \${pidfile} -f \${command}
		}

		agent360_status() {
			if [ -f \${pidfile} ]; then
			   echo "\${name} is running as \$(cat \$pidfile)."
			else
			   echo "\${name} is not running."
			   return 1
			fi
		}

		agent360_stop() {
			if [ ! -f \${pidfile} ]; then
			  echo "\${name} is not running."
			  return 1
			fi

			echo -n "Stopping \${name}..."
			kill -KILL \$(cat \$pidfile) 2> /dev/null && echo "stopped"
			rm -f \${pidfile}
		}

		run_rc_command "\$1"
EOF
	service_check $agent_bsd_service
}

system_init(){
	get_agent_path
	if [ $OS_NAME == 'freebsd' ]; then
		bsd_config
		## Added this to trigger service configuration with venv setup
	elif [[ $use_venv -eq 1 ]];then
		systemD_config_venv
	elif [[ ("${rhel_os_list[*]}" == *"$OS_NAME"* && $OS_VERSION -ge 7) || ($OS_NAME == 'ubuntu' && $OS_VERSION -ge 18) || ($OS_NAME == 'debian' && $OS_VERSION -ge 10) ]]; then
		systemD_config
	else
		echo -e "\\e[31m[ERROR] The script could not found a way to configure the service\\e[m"
		 echo "Debugging mode OS NAME IS - $OS_NAME, OS VERSION IS $OS_VERSION"
	fi
}

################
## Run script ##
################

touch $install_log
touch $log_file

#: MAIN BODY :#
echo "> Getting the Linux distribution name and version..."
get_os_release && get_os_version && echo -e "\\e[32m[SUCCESS] Found ${OS_RELEASE} ${OS_VERSION}\\e[m" || echo -e "\\e[31m[ERROR] Failed to find which Linux distribution is used"
if [ $skip_deps -eq 0 ]; then
  echo "> Installing the necessary packages..."
  create_requirements_file &&
  get_installer &&
  check_agent360 &&
  prepare_pkgs $OS_NAME $OS_VERSION &&
  install $installer $pkg_list &&
  install_agent360 $agent360_installed &&
  check_cagefs_status_and_cofiguration &&
  prepare_conf
else
  echo "> Skipping package installation as per –skip-dep-install flag."
  create_requirements_file
  get_installer &&
  check_agent360 &&
  install_agent360 $agent360_installed &&
  check_cagefs_status_and_cofiguration &&
  prepare_conf
fi

echo "> Adding the user..."
create_user

echo "> Creating the service..."
system_init

## Will add the uninstall script reference later
echo -e "\\e[32m[SUCCESS] Agent is Configured! Enjoy!\\e[m"
