# !/bin/bash
# Name: Rsync Migration for TORO Integrate
# Summary: Migrates your TORO Integrate data from one server to another using rsync
# Author: DevOps Team | devops@torocloud.com

trap "CONTROL_C" SIGINT
trap "EXIT_ERROR Line Number: ${LINENO} Exit Code: $?" ERR

# Set modes
set -u
set -e

# Root user check for install
# =============================================================================
function CHECKFORROOT() {
  USERCHECK=$( whoami  )
  if [ "$(id -u)" != "0" ]; then
    echo -e "This script must be run as ROOT
You have attempted to run this as ${USERCHECK}
use sudo $0 or change to root.
"
    exit 1
  fi
}


# Root user check for install
# =============================================================================
function CREATE_SWAP() {

  cat > /tmp/swap.sh <<EOF
#!/usr/bin/env bash
if [ ! "\$(swapon -s | grep -v Filename)" ];then
  SWAPFILE="/SwapFile"
  if [ -f "\${SWAPFILE}" ];then
    swapoff -a
    rm \${SWAPFILE}
  fi
  dd if=/dev/zero of=\${SWAPFILE} bs=1M count=1024
  chmod 600 \${SWAPFILE}
  mkswap \${SWAPFILE}
  swapon \${SWAPFILE}
fi
EOFCREATE_SWAP

  cat > /tmp/swappiness.sh <<EOF
#!/usr/bin/env bash
SWAPPINESS=\$(sysctl -a | grep vm.swappiness | awk -F' = ' '{print \$2}')

if [ "\${SWAPPINESS}" != 60 ];then
  sysctl vm.swappiness=60
fi
EOF

  if [ ! "$(swapon -s | grep -v Filename)" ];then
    chmod +x /tmp/swap.sh
    chmod +x /tmp/swappiness.sh
    /tmp/swap.sh && /tmp/swappiness.sh
  fi
}


# Trap a CTRL-C Command
# =============================================================================
function CONTROL_C() {
  set +e
  echo -e "
\033[1;31mThe Migration script was stopped. \033[0m
\033[1;36mYou Pressed [ CTRL C ] \033[0m
"
  QUIT
  echo "I quit and deleted all of the temp files I made."
  EXIT_ERROR
}


# Tear down
# =============================================================================
function QUIT() {
  set +e
  set -v

  echo 'Removing Temp Files'
  GENFILES="/tmp/intsalldeps.sh /tmp/known_hosts /tmp/postopfix.sh /tmp/swap.sh"

  for temp_file in ${EXCLUDE_FILE} ${GENFILES} ${SSH_KEY_TEMP};do
    [ -f ${temp_file} ] && rm ${temp_file}
  done

  set +v
}

function EXIT_ERROR() {
  # Print Messages
  echo -e "ERROR! Sorry About that...
"
  QUIT
  exit 1
}


# Say  something nice and exit
# =============================================================================
function ALLDONE() {
  echo "All Done. Please verify the migration."
 }



# Set the Source and Origin Drives
# =============================================================================

function GETORGNAME() {
  echo -e "
Here you Must Specify the \033[1;33mTarget\033[0m mount point.  
This is \033[1;33mA MOUNT\033[0m Point. 
Under normal circumstances this drive would be \"/datastore/clients/ORGNAME/apps/integrate/ORGNAME1/assets\". 
Remember, there is no way to check that the directory or drive exists. 
This means we are relying on \033[1;33mYOU\033[0m to type correctly.
"
  read -p "Please specify your organization name. This was set during the Cloudformation setup: " ORGNAME
  echo "Please verify that /datastore/clients/${ORGNAME}/apps/integrate/${ORGNAME}1/assets exists..."
  sleep 5
  read -p "Please verify your organization name. Type your organization name again: " ORGNAME
  echo "Setting mount target to /datastore/clients/${ORGNAME}/apps/integrate/${ORGNAME}1/assets..."
  MOUNTPOINT=/datastore/clients/${ORGNAME}/apps/integrate/${ORGNAME}1/assets
}


function GETDATA() {
  read -e -p "Please specify the /data directory of your TORO Integrate Instance: " DATA
  if [ ! -d "${DATA}" ];then
  echo "The path or Device you specified does not exist."
  GETDATA
fi
}

function GETJDBC () {
    read -e -p "Please specify the /jdbc-pool directory of your TORO Integrate Instance: " JDBC
  if [ ! -d "${JDBC}" ];then
  echo "The path or Device you specified does not exist."
  GETJDBC
fi
}

function GETLOGS () {
    read -e -p "Please specify the /logs directory of your TORO Integrate Instance: " LOGS
  if [ ! -d "${LOGS}" ];then
  echo "The path or Device you specified does not exist."
  GETLOGS
fi
}

function GETPACKAGES () {
  read -e -p "Please specify the /packages directory of your TORO Integrate Instance: " PACKAGES
   if [ ! -d "${PACKAGES}" ];then
  echo "The path or Device you specified does not exist."
  GETPACKAGES
fi
}

function GETSYSTEMP () {
  read -e -p "Please specify the /system-temp directory of your TORO Integrate Instance.
  This is optional, you may leave this blank if there is none: " SYSTEMP
}

function GETCODE() {
  read -e -p "Please specify the /code directory of your TORO Integrate Instance: " CODE
  if [ ! -d "${CODE}" ];then
  echo "The path or Device you specified does not exist."
  GETCODE
fi

}

function GETTEMP () {
  read -e -p "Please specify the /tmp directory of your TORO Integrate Instance: " TEMP
   if [ ! -d "${TEMP}" ];then
  echo "The path or Device you specified does not exist."
  #read -p "Please specify the /tmp directory of your TORO Integrate Instance" TMP
  GETTEMP
fi
}


# Get the Target IP
# =============================================================================
function GETTIP() {
  MAX_RETRIES=${MAX_RETRIES:-5}
  RETRY_COUNT=0
  read -p "If you are ready to proceed enter your Target IP address : " TIP
  TIP=${TIP:-""}
  if [ -z "${TIP}" ];then
    echo "No IP was provided, please try again"
    unset TIP
    RETRY_COUNT=$((${RETRY_COUNT}+1))
    if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ];then
      EXIT_ERROR "Hit maximum number of retries, giving up."
    else
      GETTIP
    fi
  else
    unset MAX_RETRIES
  fi
}


# When RHEL-ish Distros are detected
# =============================================================================
function WHENRHEL() {
  echo -e "\033[1;31mRHEL Based System Detected\033[0m Installing rsync."

  yum -y install rsync

  cat > /tmp/intsalldeps.sh <<EOF
#!/usr/bin/env bash
# RHEL Dep Script
yum -y install rsync
EOF

}

# When Debian based distros
# =============================================================================
function WHENDEBIAN() {
  echo -e "\033[1;31mDebian Based System Detected\033[0m"

  echo "Performing Package Update"
  apt-get update > /dev/null 2>&1

  echo "Installing rsync Package."
  apt-get -y install rsync > /dev/null 2>&1

  cat > /tmp/intsalldeps.sh <<EOF
#!/usr/bin/env bash
# Debian Dep Script
apt-get update > /dev/null 2>&1
apt-get -y install rsync > /dev/null 2>&1
EOF

}

# When SUSE
# =============================================================================
function WHENSUSE() {
  echo -e "\033[1;31mSUSE Based System Detected\033[0m"
  zypper in rsync
  cat > /tmp/intsalldeps.sh <<EOF
#!/usr/bin/env bash
# SUSE Dep Script
zypper -n in rsync
EOF

}

# When Gentoo
# =============================================================================
function WHENGENTOO() {
  echo -e "\033[1;31mGentoo Based System Detected\033[0m"

}

# When Arch
# =============================================================================
function WHENARCH() {
  echo -e "\033[1;31mArch Based System Detected\033[0m"

}

# When UNKNOWN
# =============================================================================
function WHENUNKNOWN() {
    echo -e "
\033[1;31mWARNING! \033[0m
I could not determine your OS Type. This Application has only been tested on :
\033[1;31mDebian\033[0m, \
\033[1;31mUbuntu\033[0m, \
\033[1;31mFedora\033[0m, \
\033[1;31mCentOS\033[0m, \
\033[1;31mRHEL\033[0m, \
\033[1;31mSUSE\033[0m, \
\033[1;31mGentoo\033[0m, \
and \033[1;31mArch\033[0m.
You may need to edit the file '\033[1;31m/etc/issue\033[0m' in an effort to
correct the OS detection issues
"
  exit 1
}

# Do Distro Check
# =============================================================================
function DISTROCHECK() {
  # Check the Source Distro
  if [ -f /etc/issue ];then
    if [ "$(grep -i '\(centos\)\|\(red\)\|\(scientific\)' /etc/redhat-release)"  ]; then
      WHENRHEL
    elif [ "$(grep -i '\(fedora\)\|\(amazon\)' /etc/issue)"  ]; then
      WHENRHEL
    elif [ "$(grep -i '\(debian\)\|\(ubuntu\)' /etc/issue)" ];then
      WHENDEBIAN
    elif [ "$(grep -i '\(suse\)' /etc/issue)" ];then
      WHENSUSE
    elif [ "$(grep -i '\(arch\)' /etc/issue)" ];then
      WHENARCH
    else
      WHENUNKNOWN
    fi
  elif [ -f /etc/gentoo-release ];then
    WHENGENTOO
  else
    WHENUNKNOWN
  fi
}


# RSYNC Check for Version and Set Flags
# =============================================================================
function RSYNCCHECKANDSET() {
  if [ ! $(which rsync) ];then
    echo -e "The \033[1;36m\"rsync\"\033[0m command was not found. The automatic
  Installation of rsync failed so that means you NEED to install it."
    exit 1
  else
    RSYNC_VERSION_LINE=$(rsync --version | grep -E "version\ [0-9].[0-9].[0-9]")
    RSYNC_VERSION_NUM=$(echo ${RSYNC_VERSION_LINE} | awk '{print $3}')
    RSYNC_VERSION=$(echo ${RSYNC_VERSION_NUM} | awk -F'.' '{print $1}')
    if [ "${RSYNC_VERSION}" -ge "3" ];then
      RSYNC_VERSION_COMP="yes"
    fi
  fi

  # Set RSYNC Flags
  if [ "${RSYNC_VERSION_COMP}" == "yes" ];then
    RSYNC_FLAGS='ravHEAXSzx'
    echo "Using RSYNC <= 3.0.0 Flags."
  else
    RSYNC_FLAGS='ravHSzx'
    echo "Using RSYNC >= 2.0.0 but < 3.0.0 Flags."
  fi
}


# Dep Scripts
# =============================================================================
function KEYANDDEPSEND() {
  echo -e "\033[1;36mBuilding Key Based Access for the target host\033[0m"
  ssh-keygen -t rsa -f ${SSH_KEY_TEMP} -N ''

  # Making backup of known_host
  if [ -f "/root/.ssh/known_hosts" ];then
    cp /root/.ssh/known_hosts /root/.ssh/known_hosts.${DATE}.bak
  fi

  echo -e "Please Enter the Password of the \033[1;33mTARGET\033[0m Server."
  ssh-copy-id -i ${SSH_KEY_TEMP} root@${TIP}

  if [ -f /tmp/intsalldeps.sh ];then
    echo -e "Passing RSYNC Dependencies to the \033[1;33mTARGET\033[0m Server."
    scp -i ${SSH_KEY_TEMP} /tmp/intsalldeps.sh root@${TIP}:/root/
  fi

  if [ -f /tmp/swap.sh ];then
    echo -e "Passing  Swap script to the \033[1;33mTARGET\033[0m Server."
    scp -i ${SSH_KEY_TEMP} /tmp/swap.sh root@${TIP}:/root/
  fi

  if [ -f /tmp/swappiness.sh ];then
    echo -e "Passing  Swappiness script to the \033[1;33mTARGET\033[0m Server."
    scp -i ${SSH_KEY_TEMP} /tmp/swappiness.sh root@${TIP}:/root/
  fi
}


# Commands
# =============================================================================
function RUNPREPROCESS() {
  echo -e "Running Dependency Scripts on the \033[1;33mTARGET\033[0m Server."
  SCRIPTS='[ -f "swap.sh" ] && bash swap.sh;
           [ -f "swappiness.sh" ] && bash swappiness.sh;
           [ -f "intsalldeps.sh" ] && bash intsalldeps.sh'
  ssh -i ${SSH_KEY_TEMP} -o UserKnownHostsFile=/dev/null \
                         -o StrictHostKeyChecking=no root@${TIP} \
                         "${SCRIPTS}" > /dev/null 2>&1
}

function RUNRSYNCCOMMANDDATA() {
  set +e
  MAX_RETRIES=${MAX_RETRIES:-5}
  RETRY_COUNT=0

  # Set the initial return value to failure
  false

  while [ $? -ne 0 -a ${RETRY_COUNT} -lt ${MAX_RETRIES} ];do
    RETRY_COUNT=$((${RETRY_COUNT}+1))
    ${RSYNC} -e "${RSSH}" -${RSYNC_FLAGS} --progress \
                                          --exclude-from="${EXCLUDE_FILE}" \
                                          --exclude "${SSHAUTHKEYFILE}" \
                                          $DATA root@${TIP}:$MOUNTPOINT/data
    echo "Copying data directory. Resting for a few seconds..."
    sleep 2
  done

  if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ];then
    EXIT_ERROR "Hit maximum number of retries, giving up."
  fi

  unset MAX_RETRIES
  set -e
}

function RUNRSYNCCOMMANDJDBC() {
  set +e
  MAX_RETRIES=${MAX_RETRIES:-5}
  RETRY_COUNT=0

  # Set the initial return value to failure
  false

  while [ $? -ne 0 -a ${RETRY_COUNT} -lt ${MAX_RETRIES} ];do
    RETRY_COUNT=$((${RETRY_COUNT}+1))
    ${RSYNC} -e "${RSSH}" -${RSYNC_FLAGS} --progress \
                                          --exclude-from="${EXCLUDE_FILE}" \
                                          --exclude "${SSHAUTHKEYFILE}" \
                                          $JDBC root@${TIP}:$MOUNTPOINT/jdbc-pool
    echo "Copying jdbc-pool directory. Resting for a few seconds..."
    sleep 2
  done

  if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ];then
    EXIT_ERROR "Hit maximum number of retries, giving up."
  fi

  unset MAX_RETRIES
  set -e
}

function RUNRSYNCCOMMANDLOGS() {
  set +e
  MAX_RETRIES=${MAX_RETRIES:-5}
  RETRY_COUNT=0

  # Set the initial return value to failure
  false

  while [ $? -ne 0 -a ${RETRY_COUNT} -lt ${MAX_RETRIES} ];do
    RETRY_COUNT=$((${RETRY_COUNT}+1))
    ${RSYNC} -e "${RSSH}" -${RSYNC_FLAGS} --progress \
                                          --exclude-from="${EXCLUDE_FILE}" \
                                          --exclude "${SSHAUTHKEYFILE}" \
                                          $LOGS root@${TIP}:$MOUNTPOINT/logs
    echo "Copying log files. Resting for a few seconds..."
    sleep 2
  done

  if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ];then
    EXIT_ERROR "Hit maximum number of retries, giving up."
  fi

  unset MAX_RETRIES
  set -e
}


function RUNRSYNCCOMMANDPACKAGES() {
  set +e
  MAX_RETRIES=${MAX_RETRIES:-5}
  RETRY_COUNT=0

  # Set the initial return value to failure
  false

  while [ $? -ne 0 -a ${RETRY_COUNT} -lt ${MAX_RETRIES} ];do
    RETRY_COUNT=$((${RETRY_COUNT}+1))
    ${RSYNC} -e "${RSSH}" -${RSYNC_FLAGS} --progress \
                                          --exclude-from="${EXCLUDE_FILE}" \
                                          --exclude "${SSHAUTHKEYFILE}" \
                                          $PACKAGES root@${TIP}:$MOUNTPOINT/packages
    echo "Copying packages. Resting for a few seconds..."
    sleep 2
  done

  if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ];then
    EXIT_ERROR "Hit maximum number of retries, giving up."
  fi

  unset MAX_RETRIES
  set -e
}

function RUNRSYNCCOMMANDSYSTEMP() {
  set +e
  MAX_RETRIES=${MAX_RETRIES:-5}
  RETRY_COUNT=0

  # Set the initial return value to failure
  false

  while [ $? -ne 0 -a ${RETRY_COUNT} -lt ${MAX_RETRIES} ];do
    RETRY_COUNT=$((${RETRY_COUNT}+1))
    ${RSYNC} -e "${RSSH}" -${RSYNC_FLAGS} --progress \
                                          --exclude-from="${EXCLUDE_FILE}" \
                                          --exclude "${SSHAUTHKEYFILE}" \
                                          $SYSTEMP root@${TIP}:$MOUNTPOINT/system-tmp
    echo "Copying system-temp files. Resting for a few seconds..."
    sleep 2
  done

  if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ];then
    EXIT_ERROR "Hit maximum number of retries, giving up."
  fi

  unset MAX_RETRIES
  set -e
}

function RUNRSYNCCOMMANDTEMP() {
  set +e
  MAX_RETRIES=${MAX_RETRIES:-5}
  RETRY_COUNT=0

  # Set the initial return value to failure
  false

  while [ $? -ne 0 -a ${RETRY_COUNT} -lt ${MAX_RETRIES} ];do
    RETRY_COUNT=$((${RETRY_COUNT}+1))
    ${RSYNC} -e "${RSSH}" -${RSYNC_FLAGS} --progress \
                                          --exclude-from="${EXCLUDE_FILE}" \
                                          --exclude "${SSHAUTHKEYFILE}" \
                                          $TEMP root@${TIP}:$MOUNTPOINT/tmp
    echo "Copying temp files. Resting for a few seconds..."
    sleep 2
  done

  if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ];then
    EXIT_ERROR "Hit maximum number of retries, giving up."
  fi

  unset MAX_RETRIES
  set -e
}

function RUNRSYNCCOMMANDCODE() {
  set +e
  MAX_RETRIES=${MAX_RETRIES:-5}
  RETRY_COUNT=0

  # Set the initial return value to failure
  false

  while [ $? -ne 0 -a ${RETRY_COUNT} -lt ${MAX_RETRIES} ];do
    RETRY_COUNT=$((${RETRY_COUNT}+1))
    ${RSYNC} -e "${RSSH}" -${RSYNC_FLAGS} --progress \
                                          --exclude-from="${EXCLUDE_FILE}" \
                                          --exclude "${SSHAUTHKEYFILE}" \
                                          $CODE root@${TIP}:$MOUNTPOINT/code
    echo "Copying code directory. Resting for a few seconds..."
    sleep 2
  done

  if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ];then
    EXIT_ERROR "Hit maximum number of retries, giving up."
  fi

  unset MAX_RETRIES
  set -e
}


function RUNMAINPROCESS() {

  echo -e "\033[1;36mNow performing the Copy\033[0m"

  RSYNC="$(which rsync)"
  RSSH_OPTIONS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
  RSSH="ssh -i ${SSH_KEY_TEMP} ${RSSH_OPTIONS}"

  RUNRSYNCCOMMANDCODE
  RUNRSYNCCOMMANDDATA
  RUNRSYNCCOMMANDJDBC
  RUNRSYNCCOMMANDLOGS
  RUNRSYNCCOMMANDPACKAGES
  RUNRSYNCCOMMANDSYSTEMP
  RUNRSYNCCOMMANDTEMP

  echo -e "\033[1;36mNow performing Final Sweep\033[0m"

  RSYNC_FLAGS="${RSYNC_FLAGS} --checksum"
  
  RUNRSYNCCOMMANDCODE
  RUNRSYNCCOMMANDDATA
  RUNRSYNCCOMMANDJDBC
  RUNRSYNCCOMMANDLOGS
  RUNRSYNCCOMMANDPACKAGES
  RUNRSYNCCOMMANDSYSTEMP
  RUNRSYNCCOMMANDTEMP
}

# Run Script
# =============================================================================
VERBOSE=${VERBOSE:-"False"}
DEBUG=${DEBUG:-"False"}

# The Date as generated by the Source System
DATE=$(date +%y%m%d%H)

# The Temp Working Directory
TEMPDIR='/tmp'

# Name of the Temp SSH Key we will be using.
SSH_KEY_TEMP="${TEMPDIR}/tempssh.${DATE}"

# ROOT SSH Key File
SSHAUTHKEYFILE='/root/.ssh/authorized_keys'

# General Exclude List; The exclude list is space Seperated
EXCLUDE_LIST='/boot /dev/ /etc/conf.d/net /etc/fstab /etc/hostname
/etc/HOSTNAME /etc/hosts /etc/issue /etc/init.d/nova-agent* /etc/mdadm*
/etc/mtab /etc/network* /etc/network/* /etc/networks* /etc/network.d/*
/etc/rc.conf /etc/resolv.conf /etc/selinux/config /etc/sysconfig/network*
/etc/sysconfig/network-scripts/* /etc/ssh/ssh_host_*
/etc/udev/rules.d/* /lock /net /sys /tmp
/usr/sbin/nova-agent* /usr/share/nova-agent* /var/cache/yum/* /SwapFile'

# Allow the user to add excludes to the general Exclude list
USER_EXCLUDES=${USER_EXCLUDES:-""}

# Extra Exclude File
EXCLUDE_FILE='/tmp/excludeme.file'

# Building Exclude File - DONT TOUCH UNLESS YOU KNOW WHAT YOU ARE DOING
# =============================================================================
if [ "${VERBOSE}" == "True" ];then
  set -v
fi

if [ "${DEBUG}" == "True" ];then
  set -x
fi

if [ "${USER_EXCLUDES}" ];then
  EXCLUDE_LIST+=${USER_EXCLUDES}
fi

EXCLUDEVAR=$(echo ${EXCLUDE_LIST} | sed 's/\ /\\n/g')

if [ -f ${EXCLUDE_FILE} ];then
  rm ${EXCLUDE_FILE}
fi

echo -e "${EXCLUDEVAR}" | tee -a ${EXCLUDE_FILE}

# Check that we are the root User
CHECKFORROOT

# Clear the screen to get ready for work
clear


  echo -e "This Utility Moves a \033[1;36mLIVE\033[0m System to an other System.
This application will work on \033[1;36mAll\033[0m Linux systems using RSYNC.
Before performing this action you \033[1;35mSHOULD\033[0m be in a screen
session.
"

sleep 1

# If the Target IP is not set, ask for it
GETTIP

# Allow the user to specify the source directories of the assets and the destination
GETCODE
GETDATA
GETJDBC
GETLOGS
GETPACKAGES
GETSYSTEMP
GETTEMP
GETORGNAME

# check what distro we are running on
DISTROCHECK

# Make sure we can swap
CREATE_SWAP

# Check RSYNC version and set the in use flags
RSYNCCHECKANDSET

# Create a Key for target access and send over a dependency script
KEYANDDEPSEND



# Removing known_host entry made by script
if [ -f "/root/.ssh/known_hosts" ];then
  cp /root/.ssh/known_hosts /tmp/known_hosts
  sed '$ d' /tmp/known_hosts > /root/.ssh/known_hosts
fi

RUNPREPROCESS

RUNMAINPROCESS


echo -e "
You may need to ensure that your setting are correct, and that the target is healthy
"

echo -e "Afterwhich, you should be good to go. If all is well, you should now be able to enjoy your newly cloned
server.
"

# Say something nice
ALLDONE

# Teardown what I setup on the source node and exit
QUIT

exit 0
