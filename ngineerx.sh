#!/usr/bin/env sh

# ngineerx.sh
# Configure and manage an nginx and php-fpm stack with letsencrypt certs on FreeBSD systems.

# Copyright 2015 Christian Baer
# http://github.com/chrisb86/

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

ngineerx=`basename -- $0`
ngineerx_pid=$$

VERBOSE="${VERBOSE:-false}"
DEBUG="${DEBUG:-false}"

basedir="${BASEDIR:-/usr/local}"
ngineerx_conf_dir="${NGINEERX_CONF_DIR:-$basedir/etc/ngineerx}"
ngineerx_conf_file="${NGINEERX_CONF_FILE:-$ngineerx_conf_dir/ngineerx.conf}"
ngineerx_pid_file="${NGINEERX_PID_FILE:-/var/run/ngineerx.pid}"
log_date_format="${LOG_DATE_FORMAT:-%Y-%m-%d %H:%M:%S}"
ngineerx_log_dir="${NGINEERX_LOG_DIR:-/var/log}"
ngineerx_log_file="${NGINEERX_LOG_FILE:-ngineerx.log}"

# Synopsis messages
ngineerx_usage_create="Usage: $ngineerx create -d DOMAINS [-u PHP_USER -f FLAVOUR -c -p]"
ngineerx_usage_delete="Usage: $ngineerx delete -d DOMAIN"
ngineerx_usage_enable="Usage: $ngineerx enable -d DOMAIN"
ngineerx_usage_disable="Usage: $ngineerx disable -d DOMAIN"

# Show help screen
# Usage: help exitcode
help () {
  echo "Usage: $ngineerx command {params}"
  echo
  echo "install         Copy config files for nginx and php and create directory structure"
  echo "create          Create new site"
  echo " -d \"DOMAINS\"     Domains that should be served by a site"
  echo " [-u PHP_USER]    User that should be used for PHP"
  echo " [-f FLAVOUR]     Flavour that should be used to create a site"
  echo " [-c]             Only create certificates without directory structure"
  echo " [-p]             Create a site wothout a PHP handler."
  echo "delete          Delete a site"
  echo " -d DOMAIN        Main domain of a site that should be deleted"
  echo "enable          Enable a site in nginx"
  echo " -d DOMAIN        Main domain of a site that should be enabled"
  echo "disable         Disable a site in nginx"
  echo " -d DOMAIN        Main domain of a site that should be disabled"
  echo "cert-renew      Renew certificates"
  echo "list            List all sites"
  echo "help            Show this screen"
  exit $1
}

# Print and log messages when verbose mode is on
# Usage: chat [0|1|2|3] MESSAGE
## 0 = regular output
## 1 = error messages
## 2 = verbose messages
## 3 = debug messages

chat () {
  messagetype=$1
  message=$2
  log=$ngineerx_log_dir/$ngineerx_log_file
  log_date=$(date "+$log_date_format")

  if [ $messagetype = 0 ]; then
    echo "[$log_date] [INFO] $message" | tee -a $log ;
  fi
  #
  if [ $messagetype = 1 ]; then
    echo "[$log_date] [ERROR] $message" | tee -a $log ; exit 1;
  fi

  if [ $messagetype = 2 ] && [ "$VERBOSE" = true ]; then
    echo "[$log_date] [INFO] $message" | tee -a $log
  fi

  if [ $messagetype = 3 ] && [ "$DEBUG" = true ]; then
    echo "[$log_date] [DEBUG] $message" | tee -a $log
  fi
}

# Load config file and set default variables
# Usage: init [CONFIGFILE]
init () {

  [ -f "$ngineerx_conf_file" ] && chat 2 "Config file $ngineerx_conf_file found. Loading." && . $ngineerx_conf_file

  if [ "$DEBUG" = true ]; then
     set -x
  fi

  ngineerx_host_ip="${NGINEERX_HOST_IP:-127.0.0.1}"
  ngineerx_php_pool_port="${NGINEERX_PHP_POOL_PORT:-9001}"
  ngineerx_php_ports_db="${NGINEERX_PHP_PORTS_DB:-$ngineerx_conf_dir/php-fpm_ports.db}"
  ngineerx_php_user="${NGINEERX_PHP_USER:-www_php}"
  ngineerx_nginx_user="${NGINEERX_NGINX_USER:-www}"
  ngineerx_flavour_dir="${NGINEERX_FLAVOUR_DIR:-$ngineerx_conf_dir/flavours}"
  ngineerx_webroot="${NGINEERX_WEBROOT:-$basedir/www/ngineerx}"
  ngineerx_temp_dir="${NGINEERX_TEMP_DIR:-/tmp/ngineerx}"
  dehydrated="${DEHYDRATED:-$basedir/bin/dehydrated}"
  dehydrated_conf_file="${DEHYDRATED_CONF_FILE:-$ngineerx_conf_dir/dehydrated_config}"
  dehydrated_hook_file="${dehydrated_hook_file:-$ngineerx_conf_dir/dehydrated_hook.sh}"
  dehydrated_domains_txt="${DEHYDRATED_DOMAINS_TXT:-$ngineerx_conf_dir/dehydrated_domains.txt}"
  dehydrated_webroot="${DEHYDRATED_WEBROOT:-$ngineerx_conf_dir/.acme-challenges}"
  dehydrated_ca="${DEHYDRATED_CA:-https://acme-v02.api.letsencrypt.org/directory}"
  dehydrated_args="${DEHYDRATED_ARGS:--f $dehydrated_conf_file}"
  dehydrated_args_install="${DEHYDRATED_ARGS:---register --accept-terms}"
  newsyslog_conf_d="${NEWSYSLOG_CONF_D:-$basedir/etc/newsyslog.conf.d}"
  cron_conf_d="${CRON_CONF_D:-$basedir/etc/cron.d}"
  nginx_rc="${NGINX_RC:-$basedir/etc/rc.d/nginx}"
  nginx_conf_dir="${NGINX_CONF_DIR:-$basedir/etc/nginx}"
  nginx_dhkeysize="${NGINX_DHKEYSIZE:-2048}"
  nginx_dh_file="${NGINX_DH_FILE:-$nginx_conf_dir/dhparam.pem}"
  nginx_pid_file="${NGINX_PID_FILE:-/var/run/nginx.pid}"
  nginx_includes_dir="${NGINX_INCLUDES_DIR:-$nginx_conf_dir/includes}"
  nginx_sites_avaliable="${NGINX_SITES_AVALIABLE:-$nginx_conf_dir/sites-avaliable}"
  nginx_sites_enabled="${NGINX_SITES_ENABLED:-$nginx_conf_dir/sites-enabled}"
  phpfpm_rc="${PHPFPM_RC:-$basedir/etc/rc.d/php-fpm}"
  phpfpm_conf_d="${PHPFPM_CONF_D:-$basedir/etc/php-fpm.d}"
  phpfpm_pid_file="${PHPFPM_PID_FILE:-/var/run/php-fpm.pid}"
  openssl="${OPENSSL:-/usr/bin/openssl}"
  site_flavour="${SITE_FLAVOUR:-default}"
  cert_only="${CERT_ONLY:-false}"
  no_php="${NO_PHP:-false}"

  ## Check if ngineerx is installed properly by checking if default flavour exists.
  [ "$COMMAND_INSTALL" != true ] && [ ! -d "$ngineerx_flavour_dir/default" ] && chat 1 "It seems that ngineerx is not installed properly. Please run $ngineerx install."

  chat 2 "Starting $ngineerx with PID $ngineerx_pid."
}

# Check if script is already running
# Usage: checkpid
checkPID () {

  touch $ngineerx_pid_file

  # Get stored PID from file
  ngineerx_stored_pid=`cat $ngineerx_pid_file`

  # Check if stored PID is in use
  ngineerx_pid_is_running=`ps aux | awk '{print $2}' | grep $ngineerx_stored_pid`

  if [ "$ngineerx_pid_is_running" ]; then
    # If stored PID is already in use, skip execution
    chat 1 "Skipping because $ngineerx is running (PID: $ngineerx_stored_pid)."
  else
    # Update PID file
    echo $ngineerx_pid > $ngineerx_pid_file
    chat 2 "Starting work."
  fi
}

# Check required dependencies
# Usage: check_dependencies binary
check_dependencies () {
  [ -x "$(command -v $1)" ] || chat 1 "$1 not found. Please install it and/or define its path in $ngineerx_conf_file. Exiting"
}

# Pass command to init scripts
# Usage: start_stop_stack_by_script COMMAND
start_stop_stack_by_script () {
  $nginx_rc $@
  $phpfpm_rc $@
}

# Create certificates
# Usage: create_cert domains DOMAINNAME [DOMAINNAME DOMAINNAME]
create_cert () {
  chat 2 "Creating certificates with $dehydrated"
  ## Add domains to domains.txt
  echo "$@" >> $dehydrated_domains_txt
  ## Run cron renewal and create new certs
  $dehydrated ${dehydrated_args} -c
}

# Replace @@VARIABLENAME@@ inplace given default config file with $VARIABLENAME.
# Usage: write_config sourcefile
write_config() {

  conf_file=$1

  chat 2 "Writing config file $conf_file"

  # Define the replacement patterns
  replacements="@@nginx_dhkeysize@@=$nginx_dhkeysize @@basedir@@=$basedir @@dehydrated_webroot@@=$dehydrated_webroot @@dehydrated_domains_txt@@=$dehydrated_domains_txt @@dehydrated_hook_file@@=$dehydrated_hook_file @@dehydrated_ca@@=$dehydrated_ca @@ngineerx_conf_dir@@=$ngineerx_conf_dir @@ngineerx_webroot@@=$ngineerx_webroot @@nginx_rc@@=$nginx_rc @@nginx_conf_dir@@=$nginx_conf_dir @@nginx_includes_dir@@=$nginx_includes_dir @@nginx_user@@=$ngineerx_nginx_user @@nginx_pid_file@@=$nginx_pid_file @@php_pool_port@@=$ngineerx_php_pool_port @@phpfpm_user@@=$ngineerx_php_user @@phpfpm_rc@@=$phpfpm_rc @@phpfpm_conf_dir@@=$phpfpm_conf_d @@phpfpm_pid_file@@=$phpfpm_pid_file @@ngineerx_host_ip@@=$ngineerx_host_ip @@site_domain@@=$site_domain @@site_root@@=$site_root @@site_webroot@@=$site_webroot @@nginx_dh_file@@=$nginx_dh_file"

  for f in ${replacements}; do
    search=`echo $f | cut -f 1 -d "="`
    replace=`echo $f | cut -f 2 -d "="`
    sed -i "" "s|"${search}"|"${replace}"|g" $conf_file
    unset search replace
  done

  ## Small hack because of whitespaces between domain names
  search="@@domains@@"
  replace=${domains}
  sed -i "" "s|${search}|${replace}|g" $conf_file
  unset replacements search replace
}

case "$1" in
  ######################## ngineerx.sh HELP ########################
  help)
  help 0
  ;;
  ######################## ngineerx INSTALL ########################
  install)
  COMMAND_INSTALL=true

  init
  checkPID

  dependencies="$nginx_rc $phpfpm_rc $openssl $dehydrated"

  chat 2 "Checking dependencies"
  for f in ${dependencies}; do check_dependencies $f; done && chat 2 "Everyting is fine."

  chat 0 "Creating directory structure"
  mkdir -p $nginx_conf_dir/sites-avaliable
  mkdir -p $nginx_conf_dir/sites-enabled
  mkdir -p $ngineerx_webroot
  mkdir -p  $phpfpm_conf_d
  rm -rf $phpfpm_conf_d/*
  mkdir -p $dehydrated_webroot

  chat 0 "Creating neccessary config files"
  chat 2 "Copying template files to tmp"
  mkdir -p $ngineerx_temp_dir
  mkdir -p $ngineerx_temp_dir/ngineerx
  cp $basedir/share/ngineerx/ngineerx/dehydrated_config $ngineerx_temp_dir/ngineerx/
  cp $basedir/share/ngineerx/ngineerx/dehydrated_hook.sh $ngineerx_temp_dir/ngineerx/
  cp -r $basedir/share/ngineerx/nginx $ngineerx_temp_dir/
  cp -r $basedir/share/ngineerx/php* $ngineerx_temp_dir/

  ## modify all template files for concrete usage scenario

  for f in $(find $ngineerx_temp_dir -type f); do
    write_config "$f"
  done

  ## Copy config files to $basedir and delete tmp files
  cp -rf $ngineerx_temp_dir/ngineerx/* $ngineerx_conf_dir/
  cp -rf $ngineerx_temp_dir/nginx/* $nginx_conf_dir/
  cp -rf $ngineerx_temp_dir/php* $basedir/etc/
  rm -r $ngineerx_temp_dir
  cp -r $basedir/share/ngineerx/ngineerx/flavours $ngineerx_conf_dir
  chmod +x $dehydrated_hook_file
  touch $dehydrated_domains_txt

  ## Create php-fpm.ports.db if it doesn't exist.
  if [ ! -f "$ngineerx_php_ports_db" ]; then
    chat 2 "$ngineerx_php_ports_db doesn't exist. I'll create it."
    echo $ngineerx_php_pool_port > $ngineerx_php_ports_db
  fi

  ## Create dhparam.pem only if it doesn't exist.
  if [ ! -f "$nginx_conf_dir/dhparam.pem" ]; then
    chat 2 "Creating diffie hellman parameters with $nginx_dhkeysize bit keysize. This may take a long time."
    $openssl dhparam -out $nginx_dh_file $nginx_dhkeysize
  fi

  chat 0 "Enabling logrotation"
  mkdir -p $newsyslog_conf_d

  chat 0 "Setting up cron"
  mkdir -p $cron_conf_d
  echo "0 0 * * * root $0 cert-renew > /dev/null 2>&1" > $cron_conf_d/ngineerx

  chat 0 "Registering account at letsencrypt"
  $dehydrated ${dehydrated_args} ${dehydrated_args_install}

  start_stop_stack_by_script start
  ;;

  ######################## ngineerx CREATE ########################
  create)
  shift; while getopts :d:u:cpf: arg; do case ${arg} in
    d) domains=${OPTARG};;
    u) NGINEERX_PHP_USER=${OPTARG};;
    c) CERT_ONLY=true;;
    p) NO_PHP=true;;
    f) SITE_FLAVOUR=${OPTARG};;
    ?) chat 1 ${ngineerx_usage_create};;
    :) chat 1 ${ngineerx_usage_create};;
  esac; done; shift $(( ${OPTIND} - 1 ))

  init
  checkPID

  # Get the first domain name. It's used for naming the files and directories of a site
  site_domain=`echo ${domains} | cut -f 1 -d " "`
  chat 2 "Domain name that is used for the directory structure is $site_domain."

  # we need at least one domain name
  [ ! -d $site_domain ] || chat 1 ${ngineerx_usage_create}

  ## Check if cert_only is set. If not, create site directories and configs.
  if [ "$cert_only" != true ]; then
    site_root="$ngineerx_webroot/$site_domain"
    site_webroot="$site_root/www"

    ## if no flavour is specified take default

    chat 2 "Flavour $site_flavour will be used for site creation."

    ## Check if flavour directory exists, otherwise exit
    [ -d "$ngineerx_conf_dir/flavours/$site_flavour" ] && site_flavour_dir="$ngineerx_conf_dir/flavours/$site_flavour" || chat 1 "ERROR: flavour $site_flavour not found in $ngineerx_flavour_dir."

    ## Check if nginx config file exist in flavour directory. Otherwise take it from default flavour
    [ -f $site_flavour_dir/nginx.server.conf ] && site_flavour_nginx_conf="$site_flavour_dir/nginx.no-php.conf"
    site_flavour_nginx_conf="${site_flavour_nginx_conf:-$ngineerx_flavour_dir/default/nginx.no-php.conf}"

    chat 2 "Creating directory structure in $site_root."
    mkdir -p $site_root/www
    mkdir -p $site_root/log
    mkdir -p $site_root/tmp
    mkdir -p $site_root/certs
    mkdir -p $site_root/sessions

    # Create user and group $ngineerx_php_user and add $ngineerx_nginx_user to the $ngineerx_php_user group
    chat 2 "Creating user and adding user $ngineerx_nginx_user to group $ngineerx_php_user"
    pw user add $ngineerx_php_user -s /sbin/nologin
    pw group mod $ngineerx_php_user -m $ngineerx_nginx_user

    if [ "$no_php" != true ]; then
      [ -f $site_flavour_dir/nginx.conf ] && site_flavour_nginx_conf="$site_flavour_dir/nginx.conf"
      site_flavour_nginx_conf="${site_flavour_nginx_conf:-$ngineerx_flavour_dir/default/nginx.conf}"

      ## Check if php config file exist in flavour directory. Otherwise take it from default flavour
      [ -f $site_flavour_dir/php-fpm.pool.conf ] && site_flavour_phpfpm_pool_conf="$site_flavour_dir/php-fpm.pool.conf"
      site_flavour_phpfpm_pool_conf="${site_flavour_phpfpm_pool_conf:-$ngineerx_flavour_dir/default/php-fpm.pool.conf}"

      # Determine the next usable port number for the php-fpm pool
      chat 2 "Getting port for php-fpm-pool"
      ngineerx_php_pool_port=`cat $ngineerx_php_ports_db`

      chat 0 "Creating php config files"
      cp $site_flavour_phpfpm_pool_conf $phpfpm_conf_d/$site_domain.conf
      write_config $phpfpm_conf_d/$site_domain.conf

      # Increment php-fpm pool port and store in file
      echo "$(expr "$ngineerx_php_pool_port" + 1)" > $ngineerx_php_ports_db
    fi

    chat 0 "Creating nginx config files"
    cp $site_flavour_nginx_conf $nginx_sites_avaliable/$site_domain.conf
    write_config $nginx_sites_avaliable/$site_domain.conf

    # Copy sample files if they exist in flavour
    if [ -d "$site_flavour_dir/www" ]; then
      chat 0 "Copying sample files"
      cp -r $site_flavour_dir/www/* $site_webroot
    fi

    # Link nginx config file from sites-avaliable to sites-enabled
    chat 0 "Enabling site $site_domain"
    ln -sf "$nginx_sites_avaliable/$site_domain.conf" "$nginx_sites_enabled/$site_domain.conf"

    # Add config files to newsyslog config
    chat 0 "Enabling logrotation"
    echo "$site_root/log/nginx.access.log 644 12 * \$W0D23 J $nginx_pid_file 30" >> $newsyslog_conf_d/$site_domain.conf
    echo "$site_root/log/nginx.error.log 644 12 * \$W0D23 J $nginx_pid_file 30" >> $newsyslog_conf_d/$site_domain.conf

    if [ "$no_php" != true ]; then
      echo "$site_root/log/phpfpm.slow.log 644 12 * \$W0D23 J $phpfpm_pid_file 30" >> $newsyslog_conf_d/$site_domain.conf
      echo "$site_root/log/phpfpm.error.log 644 12 * \$W0D23 J $phpfpm_pid_file 30" >> $newsyslog_conf_d/$site_domain.conf
      echo "$site_root/log/phpfpm.access.log 644 12 * \$W0D23 J $phpfpm_pid_file 30" >> $newsyslog_conf_d/$site_domain.conf
    fi
  fi

  # Create the certs
  create_cert $domains

  # Set strong permissions to files and directories
  chat 0 "Setting strong permissions to files and directories."
  chown -R $ngineerx_php_user:$ngineerx_php_user $site_root
  chmod 750 $site_root
  chmod -R 750 $site_root/*
  chmod 400 $site_root/certs/*

  # Restart stack
  start_stop_stack_by_script restart
  ;;
  ######################## ngineerx DELETE ########################
  delete)
  shift; while getopts :d: arg; do case ${arg} in
    d) site_domain=${OPTARG};;
    ?) exerr ${ngineerx_usage_delete};;
    :) exerr ${ngineerx_usage_delete};;
  esac; done; shift $(( ${OPTIND} - 1 ))

  checkPID
  init

  # we need at least a domain name
  [ ! -d $site_domain ] || chat 1 ${ngineerx_usage_delete}

  site_root="$ngineerx_webroot/$site_domain"

  # Delete config files
  chat 0 "Deleting nginx config for $site_domain"
  rm "$nginx_sites_enabled/$site_domain.conf"
  rm "$nginx_sites_avaliable/$site_domain.conf"

  chat 0 "Deleting php-fpm config for $site_domain"
  rm "$phpfpm_conf_d/$site_domain.conf"

  chat 0 "Deleting newsyslog config for $site_domain"
  rm "$newsyslog_conf_d/$site_domain.conf"

  chat 0 "Deleting $site_domain from $dehydrated_domains_txt."
  sed -i "" "/"${site_domain}"/d" ${dehydrated_domains_txt}

  chat 0 "Moving certs to archive."
  $dehydrated ${dehydrated_args} -gc

  # Delete content from webroot
  chat 0 "Deleting files for $site_domain"
  rm -rI $site_root

  # Restart stack
  start_stop_stack_by_script restart
  ;;
  ######################## ngineerx ENABLE ########################
  enable)
  shift; while getopts :d: arg; do case ${arg} in
    d) site_domain=${OPTARG};;
    ?) exerr ${ngineerx_usage_enable};;
    :) exerr ${ngineerx_usage_enable};;
  esac; done; shift $(( ${OPTIND} - 1 ))

  checkPID
  init

  # we need at least a domain name
  [ ! -d $site_domain ] || chat 1 ${ngineerx_usage_enable}

  # Link nginx config file from sites-avaliable to sites-enabled
  chat 0 "Enabling $site_domain"
  ln -sf $nginx_sites_avaliable/$site_domain.conf $nginx_sites_enabled/$site_domain.conf

  # Restart stack
  start_stop_stack_by_script restart
  ;;
  ######################## ngineerx DISABLE ########################
  disable)
  shift; while getopts :d: arg; do case ${arg} in
    d) site_domain=${OPTARG};;
    ?) exerr ${ngineerx_usage_disable};;
    :) exerr ${ngineerx_usage_disable};;
  esac; done; shift $(( ${OPTIND} - 1 ))

  checkPID
  init

  # we need at least a domain name
  [ ! -d $site_domain ] || chat 1 ${ngineerx_usage_disable}

  # Delete link  to nginx config file from sites-enabled
  chat 0 "Disabling $site_domain"
  rm $nginx_sites_enabled/$site_domain.conf

  # Restart stack
  start_stop_stack_by_script restart
  ;;
  ######################## ngineerx CERT-RENEW ########################
  cert-renew)
  checkPID
  init

  chat 0 "Renewing certificates."
  $dehydrated ${dehydrated_args} -c

  start_stop_stack_by_script restart
  ;;
  ######################## ngineerx LIST ########################
  list)
  init

  # get pids for nginx and php-fpm
  nginx_pid=`touch "$nginx_pid_file" && cat "$nginx_pid_file"`
  phpfpm_pid=`touch "$phpfpm_pid_file" && cat "$phpfpm_pid_file"`

  [ -z $nginx_pid ] && nginx_pid="not running"
  [ -z $phpfpm_pid ] && phpfpm_pid="not running"

  if [ "$(ls -A $nginx_sites_avaliable)" ]; then
    # rest of the logic
    # set formating options
    list_header=" %-35s %8s %4s\n"
    list_format=" %-35s %8s %4s\n"
    list_data=""
    list_divider="------------------------------------ -------- ----"

    printf "$list_header" "SITENAME" "STATUS" "POOL"

    echo $list_divider

    for list_file in $nginx_sites_avaliable/*; do

      unset list_phpfpm_pool_port

      # format filename
      list_filename=$(basename "$list_file")
      list_displayname=$(basename "$list_file" .conf)

      # if config is linked to sites-enabled set status to enabled
      list_status=`[ -f $nginx_sites_enabled/$list_filename ] && echo "ENABLED" || echo "DISABLED"`

      # grep php-fpm port from config file if it exists
      if [ -f $phpfpm_conf_d/$list_filename ] ; then
        list_phpfpm_pool_port=`grep "listen " $phpfpm_conf_d/$list_filename | cut -d ":" -f2-`;
      fi

      list_pool="${list_phpfpm_pool_port:-N/A}"

      # populate data for printf
      list_data="$list_data$list_displayname $list_status $list_pool "
    done
  else
    chat 0 ""
    chat 0 "No sites defined yet."
    chat 0 "Run $ngineerx create -d \"DOMAINS\" to create one."
  fi

  # Print list
  printf "$list_format" $list_data
  echo $list_divider
  echo "ngineerx Status: nginx PID=$nginx_pid | php-fpm PID=$phpfpm_pid"
  ;;
  *)
  help 1
  ;;
esac
