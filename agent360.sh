#!/bin/bash 

#: Variables :#
set -o nounset
export LC_ALL=C

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
requirements_file="requirements.txt"

# Version and hash for secure installation
agent360_version="1.3.1"

rhel_os_list=( "centos" "almalinux" "cloudlinux" "amazon" "fedora" "sangoma" "oracle" "scientific" "freepbx" "rhel" "virtuozzo" "rocky" )
deb_os_list=( "ubuntu" "debian" )
free_os_list=( "freebsd" )

default_pkgs=( "gcc" )
deb_py_pkgs=( "python3-dev" "python3-setuptools" "python3-venv" "python3-pip" )
rhel_py_pkgs=( "which" "python3" "python3-devel" "libevent-devel" )

#: Check root privilege :#
if [ "$(id -u)" != "0" ];
then
   echo -e "\\e[31m  [ERROR] Installer needs root permission to run, please run as root.\\e[m"
   exit 1
fi


usage() {
cat << EOF
Usage: Positional arguments for agents360.sh script. 

--help|-h 			Displays this information 

--skip-deps --skip-dep-install  Skip OS package instalation  				 

--user-venv 			Install agent in virtual environment 		 

--force 			Install even if agent360 is already instaled 

--token <token value> 		360 Monitoring account User ID:


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
      token="$2"
      shift
      shift
      ;;
    --tags)
      tags="$2"
      shift
      shift
      ;;
    # As I read it the older code just accept add-websites as an argument
	# This does not work. The function seems to be missing. probably because it is being added from the website directly
    add-websites|--add-websites)
      automon=1
      shift
      ;;
	--help|--h)
	  usage
	  exit 1
	;;
    *)
      positional_args+=("$1")
      shift;
      ;;
  esac
done



# Accept positional syntax too
token=${token:=${positional_args[0]}}
tags=${tags:=${positional_args[1]:-}}
if [[ $# -eq 0 ]];then
echo "No argumens provided "
echo "Exitting the program! "
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




error_handling(){
	rc=$?
	if [ "$rc" != "0" ]; then
		if [ $# -eq 0 ]; then
			echo -e "\\e[31m  [ERROR] An error occurred. Please check the log ${install_log} for details\\e[m"
		else
			echo -e "\\e[31m  [CRITICAL] A critical error occurred!\\e[m"
			echo -e "\\e[31m  The installation aborted, please check the log ${install_log}\\e[m"
			exit 1
		fi
	fi
}

create_requirements_file() {
    echo "> Creating requirements.txt with hash verification for agent360..."
    cat <<EOF > $requirements_file
agent360==$agent360_version \
    --hash=sha256:e14e54e98bda3baea204f625056a55788c942cc6e94aa19d1f97f40b864ca5dd \
    --hash=sha256:56b7ddfa08c7bb3cf92ec48a7be47126bb387bcebae22e477f225ad02f58de85

psutil==6.1.0 \
    --hash=sha256:ff34df86226c0227c52f38b919213157588a678d049688eded74c76c8ba4a5d0 \
    --hash=sha256:c0e0c00aa18ca2d3b2b991643b799a15fc8f0563d2ebb6040f64ce8dc027b942 \
    --hash=sha256:000d1d1ebd634b4efb383f4034437384e44a6d455260aaee2eca1e9c1b55f047 \
    --hash=sha256:5cd2bcdc75b452ba2e10f0e8ecc0b57b827dd5d7aaffbc6821b2a9a242823a76 \
    --hash=sha256:045f00a43c737f960d273a83973b2511430d61f283a44c96bf13a6e829ba8fdc \
    --hash=sha256:9118f27452b70bb1d9ab3198c1f626c2499384935aaf55388211ad982611407e \
    --hash=sha256:a8506f6119cff7015678e2bce904a4da21025cc70ad283a53b099e7620061d85 \
    --hash=sha256:6e2dcd475ce8b80522e51d923d10c7871e45f20918e027ab682f94f1c6351688 \
    --hash=sha256:0895b8414afafc526712c498bd9de2b063deaac4021a3b3c34566283464aff8e \
    --hash=sha256:9dcbfce5d89f1d1f2546a2090f4fcf87c7f669d1d90aacb7d7582addece9fb38 \
    --hash=sha256:498c6979f9c6637ebc3a73b3f87f9eb1ec24e1ce53a7c5173b8508981614a90b \
    --hash=sha256:d905186d647b16755a800e7263d43df08b790d709d575105d419f8b6ef65423a \
    --hash=sha256:6d3fbbc8d23fcdcb500d2c9f94e07b1342df8ed71b948a2649b5cb060a7c94ca \
    --hash=sha256:1209036fbd0421afde505a4879dee3b2fd7b1e14fee81c0069807adcbbcca747 \
    --hash=sha256:1ad45a1f5d0b608253b11508f80940985d1d0c8f6111b5cb637533a0e6ddc13e \
    --hash=sha256:a8fb3752b491d246034fa4d279ff076501588ce8cbcdbb62c32fd7a377d996be \
    --hash=sha256:353815f59a7f64cdaca1c0307ee13558a0512f6db064e92fe833784f08539c7a

netifaces==0.11.0 \
    --hash=sha256:eb4813b77d5df99903af4757ce980a98c4d702bbcb81f32a0b305a1537bdf0b1 \
    --hash=sha256:5f9ca13babe4d845e400921973f6165a4c2f9f3379c7abfc7478160e25d196a4 \
    --hash=sha256:08e3f102a59f9eaef70948340aeb6c89bd09734e0dca0f3b82720305729f63ea \
    --hash=sha256:c03fb2d4ef4e393f2e6ffc6376410a22a3544f164b336b3a355226653e5efd89 \
    --hash=sha256:7dbb71ea26d304e78ccccf6faccef71bb27ea35e259fb883cfd7fd7b4f17ecb1 \
    --hash=sha256:0f6133ac02521270d9f7c490f0c8c60638ff4aec8338efeff10a1b51506abe85 \
    --hash=sha256:73ff21559675150d31deea8f1f8d7e9a9a7e4688732a94d71327082f517fc6b4 \
    --hash=sha256:815eafdf8b8f2e61370afc6add6194bd5a7252ae44c667e96c4c1ecf418811e4 \
    --hash=sha256:50721858c935a76b83dd0dd1ab472cad0a3ef540a1408057624604002fcfb45b \
    --hash=sha256:c9a3a47cd3aaeb71e93e681d9816c56406ed755b9442e981b07e3618fb71d2ac \
    --hash=sha256:aab1dbfdc55086c789f0eb37affccf47b895b98d490738b81f3b2360100426be \
    --hash=sha256:c37a1ca83825bc6f54dddf5277e9c65dec2f1b4d0ba44b8fd42bc30c91aa6ea1 \
    --hash=sha256:28f4bf3a1361ab3ed93c5ef360c8b7d4a4ae060176a3529e72e5e4ffc4afd8b0 \
    --hash=sha256:2650beee182fed66617e18474b943e72e52f10a24dc8cac1db36c41ee9c041b7 \
    --hash=sha256:cb925e1ca024d6f9b4f9b01d83215fd00fe69d095d0255ff3f64bffda74025c8 \
    --hash=sha256:84e4d2e6973eccc52778735befc01638498781ce0e39aa2044ccfd2385c03246 \
    --hash=sha256:18917fbbdcb2d4f897153c5ddbb56b31fa6dd7c3fa9608b7e3c3a663df8206b5 \
    --hash=sha256:48324183af7f1bc44f5f197f3dad54a809ad1ef0c78baee2c88f16a5de02c4c9 \
    --hash=sha256:8f7da24eab0d4184715d96208b38d373fd15c37b0dafb74756c638bd619ba150 \
    --hash=sha256:2479bb4bb50968089a7c045f24d120f37026d7e802ec134c4490eae994c729b5 \
    --hash=sha256:3ecb3f37c31d5d51d2a4d935cfa81c9bc956687c6f5237021b36d6fdc2815b2c \
    --hash=sha256:96c0fe9696398253f93482c84814f0e7290eee0bfec11563bd07d80d701280c3 \
    --hash=sha256:c92ff9ac7c2282009fe0dcb67ee3cd17978cffbe0c8f4b471c00fe4325c9b4d4 \
    --hash=sha256:d07b01c51b0b6ceb0f09fc48ec58debd99d2c8430b09e56651addeaf5de48048 \
    --hash=sha256:469fc61034f3daf095e02f9f1bbac07927b826c76b745207287bc594884cfd05 \
    --hash=sha256:5be83986100ed1fdfa78f11ccff9e4757297735ac17391b95e17e74335c2047d \
    --hash=sha256:54ff6624eb95b8a07e79aa8817288659af174e954cca24cdb0daeeddfc03c4ff \
    --hash=sha256:841aa21110a20dc1621e3dd9f922c64ca64dd1eb213c47267a2c324d823f6c8f \
    --hash=sha256:e76c7f351e0444721e85f975ae92718e21c1f361bda946d60a214061de1f00a1 \
    --hash=sha256:043a79146eb2907edf439899f262b3dfe41717d34124298ed281139a8b93ca32

configparser==5.2.0 \
    --hash=sha256:e8b39238fb6f0153a069aa253d349467c3c4737934f253ef6abac5fe0eca1e5d \
    --hash=sha256:1b35798fdf1713f1c3139016cfcbc461f09edbf099d1fb658d4b7479fcaa3daa

future==1.0.0 \
    --hash=sha256:929292d34f5872e70396626ef385ec22355a1fae8ad29e1a734c3e43f9fbc216 \
    --hash=sha256:bd2968309307861edae1458a4f8a4f3598c03be43b97521076aebf5d94c07b05

distro==1.9.0 \
    --hash=sha256:7bffd925d65168f85027d8da9af6bddab658135b840670a223589bc0c8ef02b2 \
    --hash=sha256:2fa77c6fd8940f116ee1d6b94a2f90b13b5ea8d019b98bc8bafdcabcdd9bdbed

certifi==2024.8.30 \
    --hash=sha256:922820b53db7a7257ffbda3f597266d435245903d80737e34f8a45ff3e3230d8 \
    --hash=sha256:bec941d2aa8195e248a60b31ff9f0558284cf01a52591ceda73ea9afffd69fd9
EOF
}

get_os_release(){
	RELEASE=$(cat /etc/os-release | grep ^NAME | head -1 | cut -d'"' -f2 | cut -d' ' -f1)
	if [[ -n $RELEASE ]]; then
		OS_RELEASE=$RELEASE
		OS_NAME=$(echo "$OS_RELEASE" | tr '[:upper:]' '[:lower:]')
	else
		OS_RELEASE=""
		echo -e "\\e[31m  [ERROR] Unable to find the Linux distribution name\\e[m"
		exit 1
	fi

	if [ $OS_RELEASE == "Red" ]; then
		OS_RELEASE="RHEL"
		OS_NAME=$(echo "$OS_RELEASE" | tr '[:upper:]' '[:lower:]')
	fi
}


get_os_version(){
	# VERSION=$(cat /etc/os-release | grep ^VERSION | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
	# if [[ -n $VERSION ]];then
	# 	OS_VERSION=$VERSION
	# elif [[ $VERSION == "7 (Core)" ]];then
	# 	OS_VERSION="7"
	# else
	# 	OS_VERSION=""
	# 	echo -e "\\e[31m  [ERROR] Unable to find the Linux distribution version\\e[m"
	# 	exit 1
	# fi
	
	VERSION=$(cat /etc/os-release | grep -E "^VERSION" | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
	if [[ -n $VERSION ]];then
		OS_VERSION=$VERSION

        if [[ $OS_VERSION == '7 (Core)' ]];then
        OS_VERSION=$(cat /etc/os-release | grep ^VERSION | head -1 | cut -d'"' -f2 | awk '{print $1}')
        fi
	else
		OS_VERSION=""
		echo -e "\\e[31m  [ERROR] Unable to find the Linux distribution version\\e[m"
		exit 1
	fi


}

get_installer(){
	if [[ "${rhel_os_list[*]}" == *"$OS_NAME"* ]]; then
		installer="yum"
	elif [[ "${deb_os_list[*]}" == *"$OS_NAME"* ]]; then
		installer="apt-get"
		logging apt-get update
	elif [[ "${free_os_list[*]}" == *"$OS_NAME"* ]]; then
		installer="pkg"
	fi
	error_handling
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
	program=${@:2}
	logging $pkg_mng install -y $program && echo -e "\\e[32m  [SUCCESS] All the necessary packages were installed\\e[m" || error_handling fatal
}

prepare_pkgs(){
	os_n=$1
	os_v=$2
	if [[ ($os_n == "debian" && $os_v -ge 10) || ($os_n == "ubuntu"  && $os_v -ge 18) ]]; then
		pkg_list="${default_pkgs[*]} ${deb_py_pkgs[*]}"
	elif [[ $os_n =~ ^(centos|almalinux|cloudlinux|rhel|virtuozzo|rocky|fedora)$ && $os_v -ge 7 ]]; then
		pkg_list="${default_pkgs[*]} ${rhel_py_pkgs[*]}"
	else
		echo -e "\\e[31m  [ERROR] Could not prepare the list of packages for installation\\e[m"
	fi
}

install_agent360(){
	ins_state=$1
	if [ ! $ins_state ]; then
		echo "> Installing agent360..."
	else
		echo "> Upgrading agent360..."
	fi

  create_requirements_file

	if [ "$use_venv" -eq 1 ]; then
		# Create and activate virtual environment
		logging python3 -m venv $venv_dir && echo -e "\\e[32m  [SUCCESS] Virtual environment has been created\\e[m" || error_handling fatal
		logging source $venv_dir/bin/activate && echo -e "\\e[32m  [SUCCESS] Virtual environment has been activated\\e[m" || error_handling fatal
		# Install agent360 in virtual environment
		logging pip3 install --ignore-installed -r $requirements_file --upgrade && echo -e "\\e[32m  [SUCCESS] Finished with agent360\\e[m" || error_handling fatal
		echo "Before deactivate!"
		## Disabled deactivation of venv because it exists the script
		# logging Deactivate
		echo "Creating Symlinks $venv_dir/bin/agent360 /usr/local/bin/agent360"
		# Create a symlink for global access
		logging ln -sf $venv_dir/bin/agent360 /usr/local/bin/agent360
		logging ln -sf $venv_dir/bin/hello360 /usr/local/bin/hello360
	else
		# Install agent360 globally
		if [[ $(python3 -V | cut -d' ' -f 2 | cut -d'.' -f 2) -ge 11 ]]; then
			logging pip3 install --ignore-installed --break-system-packages -r $requirements_file --upgrade && echo -e "\\e[32m  [SUCCESS] Finished with agent360\\e[m" || error_handling fatal
		else
			logging pip3 install --ignore-installed -r $requirements_file --upgrade && echo -e "\\e[32m  [SUCCESS] Finished with agent360\\e[m" || error_handling fatal
		fi
	fi
	echo -e "\\e[32m  [SUCCESS] agent360 installed\\e[m"
}

prepare_conf(){
	echo "> Preparing the agent360 configuration..."
	if [[ !(-f $agent_config_file) || !($(cat ${agent_config_file} | wc -l) -gt 1) ]]; then
		logging wget -qO $agent_config_file $config_tpl && echo -e "\\e[32m  [SUCCESS] The default template for agent360 has been installed\\e[m" || error_handling
	fi

	echo "> Generating a server ID..."
	if [ ! -f $agent_token_file ]; then
		logging hello360 $token $agent_token_file --automon=$automon --tags=$tags
		error_handling
		server_id=$(grep server ${agent_token_file} | cut -f2 -d '=' | tr -d ' ')
		echo -e "\\e[32m  [SUCCESS] The server token has been generated: ${server_id}\\e[m"
	else
		server_id=$(agent360 info | grep 'Server:' | cut -d':' -f2 | tr -d ' ')
		echo -e "\\e[33m  [NOTE] The server already has the ID in ${agent_token_file}: ${server_id}\\e[m"
	fi
}

create_user(){
	if id agent360 &>/dev/null; then
		echo -e "\\e[33m  [NOTE] The user already exists\\e[m"
	else
		logging useradd --system --user-group --key USERGROUPS_ENAB=yes -M agent360 --shell /bin/false
		error_handling
		if id agent360 &>/dev/null; then
			echo -e "\\e[32m  [SUCCESS] The user has been created\\e[m"
		else
			echo -e "\\e[31m  [ERROR] Failed to create the user\\e[m"
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
		echo -e "\\e[32m  [SUCCESS] The service has been created\\e[m"
		echo "> Trying to enable and start the service..."
		if [ $srv_type == $agent_sysd_service ]; then
			logging chmod 644 $agent_sysd_service &&
			logging systemctl daemon-reload &&
			logging systemctl enable agent360 &&
			logging systemctl start agent360 &&
			echo -e "\\e[32m  [SUCCESS] The service has been configured\\e[m"
		elif [ $srv_type == $agent_sysv_service ]; then
			logging chmod +x $agent_sysv_service &&
			logging chkconfig --add agent360 &&
			logging chkconfig agent360 on &&
			logging service agent360 start &&
			echo -e "\\e[32m  [SUCCESS] The service has been configured\\e[m"
		elif [ ]; then
			logging chmod +x $agent_bsd_service &&
			logging echo $'\n'"agent360_enable=\"YES\"" >> /etc/rc.conf &&
			logging service agent360 start &&
			echo -e "\\e[32m  [SUCCESS] The service has been configured\\e[m"
		fi
		error_handling
	else
		echo -e "\\e[31m  [ERROR] The service has not been created.\\e[m"
	fi
}

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
}



systemD_config_venv(){
	venv_command_path='/opt/agent360-venv/bin/agent360'
	create_user
	echo "Setting up user agent360 permissions"
	chown -R agent360:agent360 $venv_command_path

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
	elif [[ $use_venv -eq 1 ]];then
		systemD_config_venv
	elif [[ ("${rhel_os_list[*]}" == *"$OS_NAME"* && $OS_VERSION -ge 7) || ($OS_NAME == 'ubuntu' && $OS_VERSION -ge 18) || ($OS_NAME == 'debian' && $OS_VERSION -ge 10) ]]; then
		systemD_config
	else
		echo -e "\\e[31m  [ERROR] The script could not found a way to configure the service\\e[m"
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
get_os_release && get_os_version && echo -e "\\e[32m  [SUCCESS] Found ${OS_RELEASE} ${OS_VERSION}\\e[m" || echo -e "\\e[31m  [ERROR] Failed to find which Linux distribution is used"

if [ $skip_deps -eq 0 ]; then
  echo "> Installing the necessary packages..."
  get_installer &&
  check_agent360 &&
  prepare_pkgs $OS_NAME $OS_VERSION &&
  install $installer $pkg_list &&
  install_agent360 $agent360_installed &&
  prepare_conf
else
  echo "> Skipping package installation as per –skip-dep-install flag."
  check_agent360 &&
  install_agent360 $agent360_installed &&
  prepare_conf
fi

echo "> Adding the user..."
create_user

echo "> Creating the service..."
system_init

echo "In case you need to uninstall the agent360 completely you can run the following script"
echo "sh <(curl https://raw.githubusercontent.com/plesk/kb-scripts/master/360-monitoring-uninstall/360-monitoring-uninstall.sh || wget -O - https://raw.githubusercontent.com/plesk/kb-scripts/master/360-monitoring-uninstall/360-monitoring-uninstall.sh)" 
echo "Agent is Configured! Enjoy!"
