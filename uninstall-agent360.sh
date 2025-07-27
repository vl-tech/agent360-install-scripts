#!/bin/bash
### Copyright 1999-2023. Plesk International GmbH.

###############################################################################
# The script uninstalls the 360 Monitoring agent and remove all the configuration
# Requirements : bash 3.x
# Version      : 2.0
#########

handle_cmd () {
  noservicestop="Unit agent360.service not loaded"
  noservicedisable="Unit file agent360.service does not exist"
  nomodule="Cannot uninstall requirement agent360, not installed"
  nouser="user 'agent360' does not exist"
  agent360_venv='/opt/agent360-venv'
  if result=$($1 2>&1) ; then
    echo -e "\\e[32m[SUCCESS] $2\\e[m"
  else
    if [[ $result = *$noservicestop* ]] ; then
      echo -e "\\e[33m[WARNING] Unable to stop the service agent360 because it was not found\n\t  Probably, it was removed earlier\\e[m"
    elif [[ $result = *$noservicedisable* ]] ; then
      echo -e "\\e[33m[WARNING] The service agent360 can not be disabled because it was not found\n\t  Probably, it was removed earlier\\e[m"
    elif [[ $result = *$nomodule* ]] ; then
      echo -e "\\e[33m[WARNING] The Python modules for 360 Monitoring are not found\n\t  Probably, it was removed earlier\\e[m"
    elif [[ $result = *$nouser* ]] ; then
      echo -e "\\e[33m[WARNING] The user agent360 does not exist\n\t  Probably, it was removed earlier\\e[m"
    else
      echo -e "\\e[31m[ERROR] $result\\e[m"
    fi
  fi
}

venv_dir="/opt/agent360-venv"
# remove_symlinks_venv(){

# if $venv_dir/bin/agent360 ;then
#   echo -e "Removing /usr/local/bin/agent360"
#   sleep 1
#   unlink /usr/local/bin/agent360
# fi

# if $venv_dir/bin/hello360 ;then
#   echo -e "Removing /usr/local/bin/hello360"
#   sleep 1
#   unlink /usr/local/bin/hello360
# fi
# }

get_os_version(){

  VERSION=$(cat /etc/os-release | grep -E "^VERSION" | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
	if [[ -n $VERSION ]];then
		OS_VERSION=$VERSION

        if [[ $OS_VERSION == '7 (Core)' ]];then
        OS_VERSION=$(cat /etc/os-release | grep ^VERSION | head -1 | cut -d'"' -f2 | awk '{print $1}')
        return "$OS_VERSION"
        fi
	else
		OS_VERSION=""
		echo -e "\\e[31m  [ERROR] Unable to find the Linux distribution version\\e[m"
		return "$OS_VERSION"
	fi
}

check_ubuntu_release(){
  # OS_VERSION=$(cat /etc/os-release  | grep ^VERSION | head -1 | cut -d'"' -f2 | cut -d '.' -f1)
  OS_VERSION=get_os_version
  if [[ $OS_VERSION -gt 22 ]];then
      echo -e "\\e[33m[WARNING] System version is ${OS_VERSION} applying arguments to pip3 --break-system-packages for package removal\\e[m"
      handle_cmd 'systemctl stop agent360' 'The service agent360 has been stopped'
      handle_cmd 'systemctl disable agent360' 'The service agent360 has been disabled'
      handle_cmd 'pip3 uninstall -y --break-system-packages agent360' 'The Python modules for 360 Monitoring have been removed'
      handle_cmd 'userdel agent360' 'The user agent360 has been deleted'

  else
      handle_cmd 'systemctl stop agent360' 'The service agent360 has been stopped'
      handle_cmd 'systemctl disable agent360' 'The service agent360 has been disabled'
      handle_cmd 'pip3 uninstall -y  agent360' 'The Python modules for 360 Monitoring have been removed'
      handle_cmd 'userdel agent360' 'The user agent360 has been deleted'
  fi
}
## Added this function to check for the ubuntu version. Ubunu23+ requites --break-system-packages argument to install modules
## Alternatively can be done via apt-get install python-agent360 but it is not yet added to any ubuntu repos
check_ubuntu_release

if [[ -f /etc/systemd/system/agent360.service ]] || [[ -f /etc/systemd/system/agent360 ]] ; then
  handle_cmd 'rm -f /etc/systemd/system/agent360*' 'The configuration of the service agent360 has been removed'
  handle_cmd 'systemctl reset-failed' 'The systemd data has been updated'
else
  echo -e "\\e[33m[WARNING] The configuration file of the service agent360 is not found\n\t  Probably, it was removed earlier\\e[m"
fi

if [[ -f /etc/agent360.ini ]] || [[ -f /etc/agent360-token.ini ]] || [[ -d /root/.360monitoring ]] ; then
  handle_cmd 'rm -f /etc/agent360*' "The 360 Monitoring configuration files have been deleted `echo`"
  handle_cmd 'rm -rf /root/.360monitoring' "The /root/.360monitoring folder have been deleted `echo`"
  echo -e "\\e[33m[INFO] To install agent360 on cPanel Run the initialization script -> /scripts/initialize_360monitoring\\e[m"
else
  echo -e "\\e[33m[WARNING] The 360 Monitoring configuration files are not found\n\t  Probably, they were removed earlier\\e[m"
fi
#if test -d /usr/local/cpanel/ 2>/dev/null;then
 # echo -e "\\e[34m[NOTE] This is cPanel server. Skipping removal of /etc/agent360.ini file !\\e[m"
  #echo -e "\\e[34m[NOTE] Removing file /etc/agent360-token.ini and /root/.360monitoring/ folder !\\e[m"
  #handle_cmd 'rm -rf /etc/agent360-token.ini || rm -rf /root/.360monitoring/'
#else
 # echo -e "\\e[34m[NOTE] This is not cPanel server. Removing all agent360 ini files from /etc folder !\\e[m"
  if [[ -f /etc/agent360-token.ini ]] ; then
    handle_cmd 'rm -f /etc/agent360*' "The 360 Monitoring configuration files have been deleted `echo`"
  else
    echo -e "\\e[33m[WARNING] The 360 Monitoring configuration files are not found\n\t  Probably, they were removed earlier\\e[m"
  fi
#fi
if [[ -f /var/log/agent360.log ]] || [[ -f /var/log/agent360-install.log ]]; then
  echo
  read -r -p "Do you want to remove agent360 logs (y/n)? " choice
  case "$choice" in
    y|Y ) handle_cmd 'rm -f /var/log/agent360*' 'The logs have been removed';;
    n|N ) echo -e "\\e[32m[SUCCESS] The logs remain on the server\n\t  You might remove them manually later\\e[m";;
    * ) echo -e "\\e[31m[ERROR] The input is invalid! The logs have not been removed\\e[m";;
  esac
fi

if [[ -d $agent360_venv ]];then
  echo -e "\\e[33m[INFO]Removing agent360 and hello360 symlinks\\e[m"
  handle_cmd unlink /usr/local/bin/agent360
  handle_cmd unlink /usr/local/bin/hello360
  echo
  echo -e "\\e[33m[INFO] Python Virtual environment folder  $venv_dir  exists\\e[m "
  read -r -p "[Q] Do you want to delete it (y/n)? " venv_choice
  echo
if [[ $venv_choice == "y" ]];then
  rm -rf $agent360_venv
  echo -e "\\e[32m[SUCCESS] Python virtual environment $agent360_venv was removed\\e[m"
  # echo -e "\\e[32m[SUCCESS] Removing venv symlinks\\e[m"
  # No need to call remove symlinks because we are removing the venv folder anyway
  # remove_symlinks_venv
  sleep 1
  echo -e "\\e[32m[SUCCESS] /usr/local/bin/hello360 and /usr/local/bin/agent360 removed\\e[m"
fi
fi

echo
echo -e "\\e[33m[INFO] Please wait for 15 minutes and, then, remove the server from 360 Monitoring > Servers\\e[m"
