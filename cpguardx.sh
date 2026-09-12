#!/bin/bash


#workflow:
#checkRequirements() --> check root access,IP,OS info, Port conflicts, DB, Host, partition etc
#installMySQL() --> Install mysql/mariadb according to the selection
#installPHP() --> Install opsshield php packages
#installWebServer() -->  Install Apache - nginx stack and openlitespeed
#installpostfix() --> Installation and configuration related to Postfix
#setos --> cpguardX OS checks
#setconf --> cpguardX configuration files
#installfiles --> Installing cpguardX files
#csfwhitelitips --> whitelisting IP's through CSF firewall
#verifyLicense --> License Verification
#displayMsg() --> Display panel login details

clear
echo -e "\e[32m"
cat << "EOF"

                      ____   ____                      _  __  __
                  ___|  _ \ / ___| _   _  __ _ _ __ __| | \ \/ /
                 / __| |_) | |  _ | | | |/ _` | '__/ _` |  \  /
                | (__|  __/| |_| || |_| | (_| | | | (_| |  /  \
                 \___|_|    \____| \__,_|\__,_|_|  \__,_| /_/\_\


                      Welcome to the cPGuard X Panel Installer!
                      -----------------------------------------
EOF
echo -e "\e[0m"


OS_NAME=
OS_VERSION=
OS_CODE_NAME=
ARCH=
[[ -z "$DB_ENGINE" ]] && export DB_ENGINE="MYSQL_8.4"
OK="\e[32mOK\e[0m \n"

SECONDS=0
Server_IP=$(hostname -I | awk '{print $1}')
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
RESET=`tput sgr0`
MYSQL_ROOT_PASSWORD=


echo -e "\n${GREEN}Initializing...${RESET}"


sleep 1

info()
{
  /bin/echo -ne "\n\e[44;97m i \e[0m $* " >&2
}


die()
{
  /bin/echo -e "\n\e[91mX  $* \e[0m\n" >&2
  echo -e "\r${YELLOW} Please check the server requirements...${RESET}"
  echo -e "\nExiting..."
  exit 1
}


preCheck() {

  if [ -d /opt/cpguard/app ]; then
    die "cPGuard X app files still exists on this server. Please uninstall cPGuard X before attempting the installation"
          echo -ne '\n'
          exit
  fi

  if [ -z "$1" ]; then
    die "License key is missing...please add your license key into the installer command"
  else
    LICKEY=$1

    if [ "$LICKEY" = "LICENCE-KEY" ]; then
      die "Replace LICENCE-KEY with your actual license key when running the command"
    fi
  fi

  if [ ! -z "$2" ]; then
          if [ ! -f "$2" ]; then
                  die "Inavlid INI file path..."
          fi
  fi

}


checkRequirements()
{
  rootCheck
  detectPanel
  pkgUpdate
  checkOperatingSystem
  checkPortConflicts
  checkDatabaseEngine
  checkRootPartitionSize

}


rootCheck() {
  info "  Checking root access... "
  if [ "$EUID" -ne 0 ]; then
    die "Script must be run as root user to install cPGuard X Panel..." >&2
    exit 1
  else
    echo -e $OK
  fi
}


detectPanel() {
    info "  Checking for existing control panels... "

    if [ -d "/usr/local/cpanel/whostmgr/" ]; then
        die "Detected cPanel."
    elif [ -d "/usr/local/directadmin" ]; then
        die "Detected DirectAdmin."
    elif [ -f "/etc/psa/psa.conf" ]; then
        die "Detected Plesk."
    elif [ -d "/etc/webmin" ]; then
        die "Detected Webmin."
    elif [ -d "/var/webuzo" ]; then
        die "Detected Webuzo."
    elif [ -d "/var/local/enhance/" ]; then
        die "Detected Enhance."
    elif [ -f "/usr/bin/cyberpanel" ]; then
        die "Detected CyberPanel."
    elif [ -f "/scripts/cwp_api" ]; then
        die "Detected Control Web Panel."
    elif [ -f "/usr/bin/nodeworx" ]; then
        die "Detected InterWorx."
    else
        echo -e $OK
    fi

}



pkgUpdate() {
  info "  Updating packages... "
  DEBIAN_FRONTEND=noninteractive apt-get update -y > /dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y > /dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get -y install nftables cron lsof zip unzip lz4 pv fail2ban imagemagick libmemcached-dev zlib1g-dev ipset libpcre2-8-0 libpcre2-dev libltdl-dev libltdl7 wget rsync tar sqlite3 openssl curl libmhash2 lbzip2 net-tools libonig5 > /dev/null 2>&1
  systemctl enable cron > /dev/null 2>&1
  systemctl start cron > /dev/null 2>&1
  curl -s https://rclone.org/install.sh | sudo bash >/dev/null 2>&1
  wget -qO- https://deb.goaccess.io/gnugpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/goaccess.gpg >/dev/null 2>&1
  echo "deb [signed-by=/usr/share/keyrings/goaccess.gpg arch=$(dpkg --print-architecture)] https://deb.goaccess.io/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/goaccess.list  > /dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get update -y > /dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get install goaccess -y > /dev/null 2>&1
  echo -e $OK
}



checkOperatingSystem()
{
  ARCH=$(uname -m)
  if [ "$(uname -s)" != "Linux" ]; then
    die "Unsupported OS...please check the system requirements for cPGuard X"
  fi

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
  else
    die "Unsupported OS...please check the system requirements for cPGuard X"
  fi

  info "  System: $OS_NAME $OS_VERSION $ARCH detected... $OK\n"

  if [ "$OS_NAME" = "ubuntu" ] && [ "$OS_VERSION" = "24.04" ]; then
    return 0
  elif [ "$OS_NAME" = "ubuntu" ] && [ "$OS_VERSION" = "26.04" ]; then

    if [ "$DB_ENGINE" = "MYSQL_8.0" ]; then
        die "MySQL 8.0 is not supported on Ubuntu 26.04. Please select MySQL 8.4 or MariaDB."
    fi

    return 0
  else
    die "Unsupported OS...please check the system requirements for cPGuard X"
  fi

}



checkPortConflicts()
{
  info "  Checking Ports..."
  local OPEN_PORTS=$(lsof -i:80 -i:443 -i:3306 -P -n -sTCP:LISTEN)
  if [ -n "${OPEN_PORTS}" ]; then
    die "Your system already has services running on port 80, 443 or 3306."
  else
      echo -e $OK
  fi
}

checkDatabaseEngine() {
  info "  Checking Database..."
  case $DB_ENGINE in
          "MYSQL_8.0" | "MYSQL_8.4" | "MARIADB_10.11" | "MARIADB_11.4")
            echo -e $OK
            info "  Selected Database Engine: \e[32m$DB_ENGINE\e[0m\n\n"
          ;;
          *)
            die "Database Engine $DB_ENGINE not supported."
          ;;
  esac
}


checkRootPartitionSize()
{
  # In KB
  local ROOT_PARTITION=$(df --output=avail / | sed '1d')
  if [ $ROOT_PARTITION -lt 6000000 ]; then
    die "At least 6GB of free hard disk space is required"
  fi
}


installMySQL() {
  MYSQL_ROOT_PASSWORD=$(tr -dc 'A-Za-z0-9#$%*!?' < /dev/urandom | head -c20)
  if [ "$OS_NAME" = "ubuntu" ]; then
    case $OS_VERSION in
      24.04|26.04)
        case $DB_ENGINE in

          "MYSQL_8.0")
            info "  Installing Mysql 8.0... "
            DEBIAN_FRONTEND=noninteractive apt-get -y update > /dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install mysql-server-8.0 mysql-client-8.0 -y > /dev/null 2>&1
            mkdir -p /opt/cpguard
            ln -s /var/run/mysqld/mysqld.sock /opt/cpguard/mysql.sock
            sed -i '/^\[mysqld\]/a mysqlx = 0' /etc/mysql/mysql.conf.d/mysqld.cnf
            systemctl restart mysql > /dev/null 2>&1

            # Set root password and switch to mysql_native_password if needed
            mysql --silent --skip-column-names <<EOF > /dev/null 2>&1
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
ALTER USER 'root'@'localhost' IDENTIFIED WITH auth_socket;
FLUSH PRIVILEGES;
CREATE USER IF NOT EXISTS 'cpguard'@'localhost' IDENTIFIED WITH auth_socket; GRANT ALL PRIVILEGES ON *.* TO 'cpguard'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;
EOF
            mysqlStatus
            ;;


          "MYSQL_8.4")
            info "  Installing Mysql 8.4... "

            wget -q https://dev.mysql.com/get/mysql-apt-config_0.8.34-1_all.deb

            echo "mysql-apt-config mysql-apt-config/select-server select mysql-8.4-lts" | debconf-set-selections
            echo "mysql-apt-config mysql-apt-config/select-product select Ok" | debconf-set-selections

            DEBIAN_FRONTEND=noninteractive dpkg -i mysql-apt-config_0.8.34-1_all.deb > /dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get -y update > /dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server > /dev/null 2>&1

            mkdir -p /opt/cpguard
            ln -s /var/run/mysqld/mysqld.sock /opt/cpguard/mysql.sock
            sed -i '/^\[mysqld\]/a mysqlx = 0' /etc/mysql/mysql.conf.d/mysqld.cnf
            systemctl restart mysql > /dev/null 2>&1


            mysql --silent --skip-column-names <<EOF > /dev/null 2>&1
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
ALTER USER 'root'@'localhost' IDENTIFIED WITH auth_socket;
FLUSH PRIVILEGES;
CREATE USER IF NOT EXISTS 'cpguard'@'localhost' IDENTIFIED WITH auth_socket; GRANT ALL PRIVILEGES ON *.* TO 'cpguard'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;
EOF
            mysqlStatus
            ;;

          "MARIADB_10.11")
            info "  Installing MariaDB 10.11... "
            wget -qO- https://mariadb.org/mariadb_release_signing_key.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/mariadb.gpg
            echo "deb [arch=amd64,arm64] https://mirror.mariadb.org/repo/10.11/ubuntu noble main" > /etc/apt/sources.list.d/mariadb.list
            DEBIAN_FRONTEND=noninteractive apt-get -y update > /dev/null
            DEBIAN_FRONTEND=noninteractive apt-get install mariadb-server mariadb-client -y > /dev/null 2>&1

            mkdir -p /opt/cpguard
            ln -s /var/run/mysqld/mysqld.sock /opt/cpguard/mysql.sock
            systemctl restart mysql > /dev/null 2>&1


            mysql --silent --skip-column-names <<EOF > /dev/null 2>&1
ALTER USER 'root'@'localhost' IDENTIFIED WITH unix_socket;
FLUSH PRIVILEGES;
CREATE USER IF NOT EXISTS 'cpguard'@'localhost' IDENTIFIED WITH unix_socket; GRANT ALL PRIVILEGES ON *.* TO 'cpguard'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;
EOF

            mysqlStatus
            ;;


          "MARIADB_11.4")
            info "  Installing MariaDB 11.4... "
            wget -qO- https://mariadb.org/mariadb_release_signing_key.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/mariadb.gpg
            echo "deb [arch=amd64,arm64] https://mirror.mariadb.org/repo/11.4/ubuntu noble main" > /etc/apt/sources.list.d/mariadb.list
            DEBIAN_FRONTEND=noninteractive apt-get -y update > /dev/null
            DEBIAN_FRONTEND=noninteractive apt-get install mariadb-server mariadb-client -y > /dev/null 2>&1

            mkdir -p /opt/cpguard
            ln -s /var/run/mysqld/mysqld.sock /opt/cpguard/mysql.sock
            systemctl restart mysql > /dev/null 2>&1

            mysql --silent --skip-column-names <<EOF > /dev/null 2>&1
ALTER USER 'root'@'localhost' IDENTIFIED WITH unix_socket;
FLUSH PRIVILEGES;
CREATE USER IF NOT EXISTS 'cpguard'@'localhost' IDENTIFIED WITH unix_socket; GRANT ALL PRIVILEGES ON *.* TO 'cpguard'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;
EOF
            mysqlStatus
            ;;

          *)
            die "Database Engine $DB_ENGINE not supported."
            ;;

        esac
        ;;
      esac

  elif [ "$OS_NAME" = "Debian" ]; then
    case $OS_VERSION in
      "12")
        case $DB_ENGINE in

          "MYSQL_8.4")
            apt -y update
            DEBIAN_FRONTEND=noninteractive apt install mysql-server-8.4 mysql-client-8.4 -y
            ;;

          "MARIADB_10.11")
            apt -y update
            apt -y install mariadb-server
            ;;

          "MARIADB_11.4")
            wget -qO- https://mariadb.org/mariadb_release_signing_key.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/mariadb.gpg
            echo "deb [arch=amd64,arm64] https://mirror.mariadb.org/repo/11.4/debian bookworm main" > /etc/apt/sources.list.d/mariadb.list
            apt -y update
            apt -y install mariadb-server
          ;;

          *)
            die "Database Engine $DB_ENGINE not supported."
            ;;
        esac
        ;;
      *)
        die "Unsupported Debian version: $OS_VERSION."
        ;;
    esac
  else
    die "Unsupported OS: $OS_NAME."
  fi
}


secureInstall() {




  mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "DELETE FROM mysql.user WHERE User='';"  > /dev/null 2>&1


  mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"  > /dev/null 2>&1


  mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "DROP DATABASE IF EXISTS test;"  > /dev/null 2>&1
  mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"  > /dev/null 2>&1


  mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "FLUSH PRIVILEGES;"  > /dev/null 2>&1




cat > ~/.my.cnf <<EOF
[client]
user=root
password="$MYSQL_ROOT_PASSWORD"
EOF

chmod 600 ~/.my.cnf

}

mysqlStatus() {
 # Check if MySQl/Mriadb is active
  mysql_status=$(systemctl is-active mysql)

  if [[ "$mysql_status" == "active" ]]; then
      echo -e $OK
  else
  check_status_and_exit $? "Failed to start MySQL/Mariadb"
  fi
}




check_status_and_exit() {
    local status=$1
    local error_message=$2

    if [[ $status -ne 0 ]]; then
        die "Error: $error_message"
        exit $status
    fi
}


installPHP() {

  info "  Installing PHP versions..."

  LINK="/usr/bin/php"


  if [ -e "$LINK" ] || [ -L "$LINK" ]; then
    rm -f "$LINK"
  fi


  if ! id "cpguard" &>/dev/null; then


    useradd cpguard -s /bin/false -M -d /opt/cpguard -r > /dev/null 2>&1
#    chown -R cpguard:cpguard /opt/cpguard/app > /dev/null 2>&1

  fi


  mkdir -p /tmp/cpg
  cd /tmp/cpg
  case "$OS_VERSION" in
    24.04)

        DEBIAN_FRONTEND=noninteractive apt-get install -y libxml2 libssl-dev libsqlite3-dev zlib1g libgmp10 libldap2 libsasl2-2 libedit-dev libpng-dev libbz2-dev libxslt1-dev libcurl4 libenchant-2-2  libonig5 libzip4 > /dev/null 2>&1

        wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs24/ops-php-fpm74_7.4.33-1_x86_64.deb > /dev/null 2>&1
        dpkg --force-all -i ops-php-fpm74_7.4.33-1_x86_64.deb > /dev/null 2>&1
        wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs24/ops-php-fpm81_8.1.34-1_x86_64.deb > /dev/null 2>&1
        dpkg --force-all -i ops-php-fpm81_8.1.34-1_x86_64.deb > /dev/null 2>&1
        wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs24/ops-php-fpm82_8.2.33-1_x86_64.deb > /dev/null 2>&1
        dpkg --force-all -i ops-php-fpm82_8.2.33-1_x86_64.deb > /dev/null 2>&1
        wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs24/ops-php-fpm83_8.3.33-1_x86_64.deb > /dev/null 2>&1
        dpkg --force-all -i ops-php-fpm83_8.3.33-1_x86_64.deb > /dev/null 2>&1
        wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs24/ops-php-fpm84_8.4.24-1_x86_64.deb  > /dev/null 2>&1
        dpkg --force-all -i ops-php-fpm84_8.4.24-1_x86_64.deb > /dev/null 2>&1
        wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs24/ops-php-fpm85_8.5.9-1_x86_64.deb  > /dev/null 2>&1
        dpkg --force-all -i ops-php-fpm85_8.5.9-1_x86_64.deb > /dev/null 2>&1
        ;;

    26.04)

        DEBIAN_FRONTEND=noninteractive apt-get install -y libssl-dev libsqlite3-dev zlib1g libgmp10 libldap2 libsasl2-2 libedit-dev libpng-dev libbz2-dev libxslt1-dev libcurl4 libenchant-2-2  libonig5 libzip5 libargon2-1 > /dev/null 2>&1

        wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs26/ops-php-fpm81_8.1.34-1_x86_64.deb > /dev/null 2>&1
        dpkg --force-all -i ops-php-fpm81_8.1.34-1_x86_64.deb > /dev/null 2>&1
        wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs26/ops-php-fpm82_8.2.33-1_x86_64.deb > /dev/null 2>&1
        dpkg --force-all -i ops-php-fpm82_8.2.33-1_x86_64.deb  > /dev/null 2>&1
        wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs26/ops-php-fpm83_8.3.33-1_x86_64.deb > /dev/null 2>&1
        dpkg --force-all -i ops-php-fpm83_8.3.33-1_x86_64.deb > /dev/null 2>&1
        wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs26/ops-php-fpm84_8.4.24-1_x86_64.deb  > /dev/null 2>&1
        dpkg --force-all -i ops-php-fpm84_8.4.24-1_x86_64.deb > /dev/null 2>&1
        wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs26/ops-php-fpm85_8.5.9-1_x86_64.deb  > /dev/null 2>&1
        dpkg --force-all -i ops-php-fpm85_8.5.9-1_x86_64.deb > /dev/null 2>&1
        ;;

  esac

  cp /opt/cpguard/packages/php74/etc/php74-fpm.service /etc/systemd/system/php74-fpm.service > /dev/null 2>&1
  cp /opt/cpguard/packages/php81/etc/php81-fpm.service /etc/systemd/system/php81-fpm.service > /dev/null 2>&1
  cp /opt/cpguard/packages/php82/etc/php82-fpm.service /etc/systemd/system/php82-fpm.service > /dev/null 2>&1
  cp /opt/cpguard/packages/php83/etc/php83-fpm.service /etc/systemd/system/php83-fpm.service > /dev/null 2>&1
  cp /opt/cpguard/packages/php84/etc/php84-fpm.service /etc/systemd/system/php84-fpm.service > /dev/null 2>&1
  cp /opt/cpguard/packages/php85/etc/php85-fpm.service /etc/systemd/system/php85-fpm.service > /dev/null 2>&1

  systemctl enable  php74-fpm > /dev/null 2>&1
  systemctl enable  php81-fpm > /dev/null 2>&1
  systemctl enable  php82-fpm > /dev/null 2>&1
  systemctl enable  php83-fpm > /dev/null 2>&1
  systemctl enable  php84-fpm > /dev/null 2>&1
  systemctl enable  php85-fpm > /dev/null 2>&1

  ln -sf /opt/cpguard/packages/php74/openssl/lib/libssl.so.1.1 /lib/x86_64-linux-gnu/libssl.so.1.1  > /dev/null 2>&1
  ln -sf /opt/cpguard/packages/php74/openssl/lib/libcrypto.so.1.1 /lib/x86_64-linux-gnu/libcrypto.so.1.1  > /dev/null 2>&1
  ln -s /opt/cpguard/packages/php85/bin/php /usr/bin/ > /dev/null 2>&1

  systemctl daemon-reload

  cd /tmp
  rm -rf /tmp/cpg

echo -e $OK

}



setos() {
info "  Installing dependency packages..."
mkdir /opt/cpguard > /dev/null 2>&1
rm -rf /usr/local/src/cpg  > /dev/null 2>&1
mkdir /usr/local/src/cpg  > /dev/null 2>&1


  if  [ "$OS_NAME" = "ubuntu" ]; then
          echo "fs.inotify.max_user_watches = 10000000" > /etc/sysctl.d/cpguard.conf
          sysctl -p /etc/sysctl.d/cpguard.conf > /dev/null 2>&1

          case "$OS_VERSION" in
              24.04|26.04)

          cd /usr/local/src/cpg
          wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs24/cpg-nginx_1.30.3_x86_64.deb  > /dev/null 2>&1
          wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs24/cpg-php-fpm_8.1.32_x86_64.deb  > /dev/null 2>&1
          wget https://get-cpg.nyc3.cdn.digitaloceanspaces.com/debs24/cpg-clamav-libs_1.0_x86_64.deb  > /dev/null 2>&1
          ;;

  esac


  dpkg --force-all -i cpg-nginx_1.30.3_x86_64.deb  > /dev/null 2>&1
  dpkg --force-all -i cpg-php-fpm_8.1.32_x86_64.deb  > /dev/null 2>&1
  dpkg --force-all -i cpg-clamav-libs_1.0_x86_64.deb  > /dev/null 2>&1

  sed -i -e "s/proc_get_status,//g" /opt/cpguard/cpg-php-fpm/etc/php.ini

  if [ -f /opt/cpguard/cpg-php-fpm/sbin/php-fpm ] && [ -f /opt/cpguard/cpg-nginx/sbin/nginx ] && [ -f /opt/cpguard/cpg-clamav/lib/libclamav.so ]; then
    echo -e $OK
  else
    die "Could not install dependency packages... please contact support."

  fi

fi

}


setconf() {

  info "  Configuring cPGuard X packages..."

  TMEZONE=`timedatectl | grep -oP 'zone\: \K\w[^\s]+'`
        if [ $TMEZONE = "n/a" ] || [ $TMEZONE = "Host" ]; then
    DTMZONE=`date +%:z | awk -F":" {'print $1'}`
    if [[ "$DTMZONE" == +* ]]; then
      DTMZONE1=`echo "${DTMZONE:1:1}"`
      DTMZONE2=`echo "${DTMZONE:2:1}"`
      if [ $DTMZONE1 -eq "0" ]; then
        TMEZONE=Etc/GMT"+"$DTMZONE2
      else
        TMEZONE=Etc/GMT$DTMZONE
      fi

    elif [[ "$DTMZONE" == -* ]]; then
        DTMZONE1=`echo "${DTMZONE:1:1}"`
        DTMZONE2=`echo "${DTMZONE:2:1}"`
        if [ $DTMZONE1 -eq "0" ]; then
         TMEZONE=Etc/GMT"-"$DTMZONE2
        else
           TMEZONE=Etc/GMT$DTMZONE
        fi
    else
        die "Cannot find the system timezone...please contact support..."

    fi

        fi

  sed -i -e "s#; http://php.net/date.timezone#date.timezone = "$TMEZONE"#g" /opt/cpguard/cpg-php-fpm/etc/php.ini
  sed -i -e "s/readlink,//g" /opt/cpguard/cpg-php-fpm/etc/php.ini

  echo -e $OK


}


installfiles() {
info "  Installing Files..."

cd /usr/local/src/cpg

URL="get-cpg.nyc3.cdn.digitaloceanspaces.com"
if curl -s --head  --request GET  https://get-cpg.nyc3.cdn.digitaloceanspaces.com/test.txt | grep "200" > /dev/null; then
        URL="get-cpg.nyc3.cdn.digitaloceanspaces.com"
else
        URL="get-cpg.nyc3.digitaloceanspaces.com"
fi

wget https://$URL/latest/panel/app.tar.gz > /dev/null 2>&1
wget https://$URL/latest/etc_cpguard.tar.gz > /dev/null 2>&1
wget https://$URL/latest/3rdparty.tar.gz > /dev/null 2>&1


tar -xvzf app.tar.gz > /dev/null 2>&1
tar -xvzf etc_cpguard.tar.gz > /dev/null 2>&1
tar -xvzf 3rdparty.tar.gz > /dev/null 2>&1

mv 3rdparty /opt/cpguard/
chown cpguard:cpguard /opt/cpguard/3rdparty/ > /dev/null 2>&1
chown -R cpguard:cpguard /opt/cpguard/3rdparty/ > /dev/null 2>&1

mv app /opt/cpguard/app
mkdir /etc/cpguard
rsync -avz cpguard/ /etc/cpguard/ > /dev/null 2>&1

ln -s /opt/cpguard/app/cpguard/cpgcli.php /usr/bin/cpgcli  > /dev/null 2>&1
chmod 755 /opt/cpguard/app/cpguard/cpgcli.php
ln -s /opt/cpguard/app/panel/webcli.php /usr/bin/webcli  > /dev/null 2>&1
chmod 755 /opt/cpguard/app/panel/webcli.php

ln -s /opt/cpguard/app/scripts/php /usr/local/bin/php > /dev/null 2>&1
ln -s /opt/cpguard/app/scripts/composer /usr/local/bin/composer > /dev/null 2>&1
ln -s /opt/cpguard/app/scripts/wp-cli /usr/local/bin/wp > /dev/null 2>&1

rsync -az /etc/cpguard/cpglfd /opt/cpguard/ > /dev/null 2>&1

if [ -f /etc/debian_version ]; then
                mv /etc/cpguard/scripts/cpguard_deb /etc/cpguard/scripts/cpguard
                mv /etc/cpguard/scripts/fscan_deb /etc/cpguard/scripts/fscan
                mv /etc/cpguard/scripts/fscanfile_deb /etc/cpguard/scripts/fscanfile
                mv /etc/cpguard/scripts/mscan_deb /etc/cpguard/scripts/mscan
                mv /etc/cpguard/scripts/daily_deb /etc/cpguard/scripts/daily
                mv /etc/cpguard/scripts/weekly_deb /etc/cpguard/scripts/weekly
                chmod 755 /etc/cpguard/scripts/cpguard
                chmod 755 /etc/cpguard/scripts/fscan
                chmod 755 /etc/cpguard/scripts/fscanfile
                chmod 755 /etc/cpguard/scripts/mscan
                chmod 755 /etc/cpguard/scripts/daily
                chmod 755 /etc/cpguard/scripts/weekly
fi

mv /etc/cpguard/tmp/cpguard_modsec100.conf_sample /etc/cpguard/cpguard_modsec100.conf
mv /etc/cpguard/tmp/cpguard_modsec101.conf_sample /etc/cpguard/cpguard_modsec101.conf

mv /etc/cpguard/tmp/wafurls.txt_sample /etc/cpguard/wafurls.txt
mv /etc/cpguard/tmp/bfurls.txt_sample /etc/cpguard/bfurls.txt

touch /etc/cpguard/whitelistusers.txt
touch /etc/cpguard/userwatch.txt
touch /etc/cpguard/whitelistfiles.txt
touch /etc/cpguard/blacklistfiles.txt
touch /etc/cpguard/watchlist.txt
touch  /etc/cpguard/plusscanplus.txt


echo "mysql.sock" >> /etc/cpguard/whitelistfiles.txt
echo "1.sh" >> /etc/cpguard/blacklistfiles.txt
echo "libworker.so" >> /etc/cpguard/blacklistfiles.txt



mkdir -p /opt/cpguard/common
touch /opt/cpguard/tmpdb.txt
touch /opt/cpguard/blacklistips.txt
touch /opt/cpguard/whitelistips.txt
touch /opt/cpguard/whitelistdomains.txt
touch /etc/cpguard/conf/location.dat
touch /opt/cpguard/blacklist-userips.txt

chmod 755 /etc/cpguard/scripts/meSamples.php
chmod 755 /etc/cpguard/scripts/bforce.php


chown cpguard:cpguard /etc/cpguard/wafurls.txt
chown cpguard:cpguard /etc/cpguard/blacklistfiles.txt
chown cpguard:cpguard /etc/cpguard/whitelistfiles.txt
chown cpguard:cpguard /etc/cpguard/bfurls.txt
chown cpguard:cpguard /etc/cpguard/whitelistusers.txt
chown cpguard:cpguard /opt/cpguard/blacklist-userips.txt
chown cpguard:cpguard /opt/cpguard/whitelistdomains.txt
chown cpguard:cpguard /opt/cpguard/whitelistips.txt
chown cpguard:cpguard /opt/cpguard/blacklistips.txt


/opt/cpguard/cpg-php-fpm/bin/php /opt/cpguard/app/setup/install.php > /dev/null 2>&1
mv /etc/cpguard/cron /etc/cron.d/cpguard

cp -p  /opt/cpguard/app/resources/badbots.txt /etc/cpguard/
chown cpguard:cpguard /etc/cpguard/badbots.txt

chown -R cpguard:cpguard /opt/cpguard/app

chown cpguard:cpguard /etc/cpguard/conf/main.conf
chmod 750 /opt/cpguard/app/data


chmod 750 /opt/cpguard/app/setup/install_node.sh
/opt/cpguard/app/setup/install_node.sh > /dev/null 2>&1


if [ -f /usr/sbin/getenforce ]; then
        CPGSE=`/usr/sbin/getenforce`
        if [ $CPGSE = "Enforcing" ]; then
                semanage fcontext -a -t system_cron_spool_t "/etc/cron.d/cpguard"
                restorecon -RFv /etc/cron.d/cpguard
        fi
fi

echo -e $OK

}


installWebServer() {


  info "  Installing Nginx..."

  DEBIAN_FRONTEND=noninteractive apt update > /dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt install -y nginx > /dev/null 2>&1

  cp -rf /opt/cpguard/app/setup/panel/files/nginx/nginx.conf /etc/nginx/nginx.conf
  ln -s /opt/cpguard/app/resources/templates/nginx-cpguard.conf /etc/nginx/conf.d/cpguard.conf

  mkdir -p /var/cache/nginx
  chown -R www-data:www-data /var/cache/nginx
  chmod 700 /var/cache/nginx


  systemctl restart nginx  > /dev/null 2>&1


  nginx_status=$(systemctl is-active nginx)

  if [[ "$nginx_status" == "active" ]]; then
      echo -e $OK
  else
  check_status_and_exit $? "Failed to start Nginx"
  fi


  info "  Installing Apache..."

  DEBIAN_FRONTEND=noninteractive apt install -y apache2 libapache2-mod-security2 > /dev/null 2>&1

  cp -rf /opt/cpguard/app/setup/panel/files/apache2/apache2.conf /etc/apache2/apache2.conf
  cp -rf /opt/cpguard/app/setup/panel/files/apache2/ports.conf /etc/apache2/ports.conf 
  cp -rf /opt/cpguard/app/setup/panel/files/apache2/modsecurity.conf /etc/modsecurity/modsecurity.conf 
  cp -rf /opt/cpguard/app/setup/panel/files/apache2/security2.conf /etc/apache2/mods-enabled/security2.conf 
  cp -rf /opt/cpguard/app/setup/panel/files/apache2/remoteip.conf /etc/apache2/mods-available/remoteip.conf
  cp -rf /opt/cpguard/app/setup/panel/files/apache2/security.conf /etc/apache2/conf-enabled/security.conf

  a2enmod rewrite remoteip proxy proxy_fcgi setenvif proxy_http headers ssl > /dev/null 2>&1
  a2dismod status > /dev/null 2>&1
  rm /etc/apache2/sites-available/*
  rm /etc/apache2/sites-enabled/*


if [ "$OS_NAME" = "ubuntu" ] && [ "$OS_VERSION" = "26.04" ]; then

mkdir -p /etc/systemd/system/apache2.service.d

cat <<EOF | sudo tee /etc/systemd/system/apache2.service.d/override.conf > /dev/null
[Service]
ProtectHome=no
EOF

fi


  systemctl daemon-reload > /dev/null 2>&1
  systemctl restart apache2 > /dev/null 2>&1


  apache_status=$(systemctl is-active apache2)

  if [[ "$apache_status" == "active" ]]; then
      echo -e $OK
  else
    check_status_and_exit $? "Failed to start Apache"
  fi

  info "  Installing OpenLiteSpeed..."
  wget -qO- https://repo.litespeed.sh 2>/dev/null | bash >/dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt install openlitespeed ols-modsecurity -y  > /dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt install lsphp81 lsphp81-curl lsphp81-mysql lsphp81-intl lsphp81-imagick lsphp81-ldap lsphp81-memcached lsphp81-redis lsphp81-ioncube -y  > /dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt install lsphp82 lsphp82-curl lsphp82-mysql lsphp82-intl lsphp82-imagick lsphp82-ldap lsphp82-memcached lsphp82-redis lsphp82-ioncube -y  > /dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt install lsphp83 lsphp83-curl lsphp83-mysql lsphp83-intl lsphp83-imagick lsphp83-ldap lsphp83-memcached lsphp83-redis lsphp83-ioncube -y  > /dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt install lsphp84 lsphp84-curl lsphp84-mysql lsphp84-intl lsphp84-imagick lsphp84-ldap lsphp84-memcached lsphp84-redis lsphp84-ioncube -y  > /dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt install lsphp85 lsphp85-curl lsphp85-mysql lsphp85-intl lsphp85-imagick lsphp85-ldap lsphp85-memcached lsphp85-redis -y  > /dev/null 2>&1

  sleep 3
  systemctl stop openlitespeed.service >/dev/null 2>&1
  systemctl stop lshttpd.service >/dev/null 2>&1
  systemctl disable openlitespeed.service >/dev/null 2>&1
  systemctl disable lshttpd.service >/dev/null 2>&1
  echo -e $OK


}


installPostfix() {
  info "  Installing Postfix..."

  export DEBIAN_FRONTEND=noninteractive


  echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
  echo "postfix postfix/mailname string $(hostname -f)" | debconf-set-selections


  apt-get install -y postfix > /dev/null 2>&1


  postconf -e "inet_interfaces = loopback-only"
  postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost"


  systemctl enable postfix > /dev/null 2>&1
  systemctl restart postfix > /dev/null 2>&1

  echo -e $OK

}






csfwhitelitips () {




if [ -f /usr/sbin/ufw ]; then
  info "  Whitelisting OPSSHIELD IPs in UFW..."
        /usr/sbin/ufw allow from 137.184.200.210 to any proto tcp port 9098 > /dev/null 2>&1
        /usr/sbin/ufw allow from 159.89.87.35 to any proto tcp port 9098 > /dev/null 2>&1
        /usr/sbin/ufw allow from 167.99.149.179 to any proto tcp port 9098 > /dev/null 2>&1
        echo -e $OK
fi

}


verifyLicense() {

  info "  Verifying License..."
  sleep 2

  LICENSE_OUTPUT=$(cpgcli license --key "$LICKEY" 2>&1)

  if echo "$LICENSE_OUTPUT" | grep -qi "New license saved and applied"; then
    echo -e "$OK"
  else
    echo -e "${RED} X ${RESET}\n"
    echo -e "\n\n${YELLOW} Invalid license Key ${RESET}\n"
  fi

}


displayMsg() {
  Elapsed_Time="$((SECONDS / 3600)) hrs $(((SECONDS / 60) % 60)) min $((SECONDS % 60)) sec"
  echo -e "\n"
  echo "###################################################################"
  echo "                                                                   "
  echo "              ${GREEN}cPGuard X Successfully Installed${RESET}      "
  echo "              --------------------------------                     "
  echo "                                                                   "
  echo "                                                                   "
  /opt/cpguard/cpg-php-fpm/bin/php /opt/cpguard/app/setup/summary.php
  echo "                                                                   "
  echo "                                                                   "
  echo "                                                                   "
  echo "              Installation time: $Elapsed_Time                    "
  echo "                                                                   "
  echo "###################################################################"
  echo -ne '\n'
  echo -ne "\r${GREEN} If you need any assistance, please feel free to reach our support team ${RESET}"
  echo -ne '\n'
  echo -ne '\n'

}

preCheck "$@"
checkRequirements
installMySQL
secureInstall
installPHP
setos
setconf
installfiles
installWebServer
installPostfix
csfwhitelitips
verifyLicense
displayMsg
