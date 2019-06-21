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

basedir="${BASEDIR:-/usr/local/etc}"
ngineerx_conf_dir="${NGINEERX_CONF_DIR:-$basedir/ngineerx}"
ngineerx_conf_file="${NGINEERX_CONF_FILE:-$ngineerx_conf_dir/ngineerx.conf}"
ngineerx_pid_file="${NGINEERX_PID_FILE:-/var/run/ngineerx.pid}"
log_date_format="${LOG_DATE_FORMAT:-%Y-%m-%d %H:%M:%S}"
ngineerx_log_dir="${NGINEERX_LOG_DIR:-/var/log}"
ngineerx_log_file="${NGINEERX_LOG_FILE:-ngineerx.log}"

# Synopsis messages
ngineerx_usage_create="Usage: $ngineerx create -d DOMAINS [-u PHP_USER -f FLAVOUR]"
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
  echo "delete          Delete a site"
  echo " -d DOMAIN        Main domain of a site that should be deleted"
  echo "enable          Enable a site in nginx"
  echo " -d DOMAIN        Main domain of a site that should be enabled"
  echo "disable         Disable a site in nginx"
  echo " -d DOMAIN        Main domain of a site that should be disabled"
  echo "cert-renew      Renew certificates"
  echo "list            List all sites"
  echo "help            Show this screen"
# [TODO] aktualisieren
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

  ngineerx_host_ip="${NGINEERX_HOST_IP:-127.0.0.1}"
  ngineerx_php_pool_port="${NGINEERX_PHP_POOL_PORT:-9001}"
  ngineerx_php_ports_db="${NGINEERX_PHP_PORTS_DB:-$ngineerx_conf_dir/php-fpm_ports.db}"
  ngineerx_php_user="${NGINEERX_PHP_USER:-www_php}"
  ngineerx_nginx_user="${NGINEERX_NGINX_USER:-www}"
  ngineerx_flavour_dir="${NGINEERX_FLAVOUR_DIR:-$ngineerx_conf_dir/flavours}"
  ngineerx_webroot="${NGINEERX_WEBROOT:-/usr/local/www}"
  ngineerx_temp_dir="${NGINEERX_TEMP_DIR:-/tmp/ngineerx}"
  dehydrated="${DEHYDRATED:-/usr/local/bin/dehydrated}"
  dehydrated_conf_file="${DEHYDRATED_CONF_FILE:-$ngineerx_conf_dir/dehydrated_config}"
  dehydrated_hook_file="${dehydrated_hook_file:-$ngineerx_conf_dir/dehydrated_hook.sh}"
  dehydrated_domains_txt="${DEHYDRATED_DOMAINS_TXT:-$ngineerx_conf_dir/dehydrated_domains.txt}"
  dehydrated_webroot="${DEHYDRATED_WEBROOT:-$ngineerx_conf_dir/.acme-challenges}"
  dehydrated_args="${DEHYDRATED_ARGS:--f $dehydrated_conf_file}"
  dehydrated_args_install="${DEHYDRATED_ARGS:---register --accept-terms}"
  newsyslog_conf_d="${NEWSYSLOG_CONF_D:-$basedir/newsyslog.conf.d}"
  cron_conf_d="${CRON_CONF_D:-$basedir/cron.d}"
  nginx_rc="${NGINX_RC:-$basedir/rc.d/nginx}"
  nginx_conf_dir="${NGINX_CONF_DIR:-$basedir/nginx}"
  nginx_dhkeysize="${NGINX_DHKEYSIZE:-2048}"
  nginx_dh_file="${NGINX_DH_FILE:-$nginx_conf_dir/dhparam.pem}"
  nginx_pid_file="${NGINX_PID_FILE:-/var/run/nginx.pid}"
  nginx_includes_dir="${NGINX_INCLUDES_DIR:-$nginx_conf_dir/includes}"
  nginx_sites_avaliable="${NGINX_SITES_AVALIABLE:-$nginx_conf_dir/sites-avaliable}"
  nginx_sites_enabled="${NGINX_SITES_ENABLED:-$nginx_conf_dir/sites-enabled}"
  phpfpm_rc="${PHPFPM_RC:-$basedir/rc.d/php-fpm}"
  phpfpm_conf_d="${PHPFPM_CONF_D:-$basedir/php-fpm.d}"
  phpfpm_pid_file="${PHPFPM_PID_FILE:-/var/run/php-fpm.pid}"
  openssl="${OPENSSL:-/usr/bin/openssl}"

  ## Check if ngineerx is installed properly by checking if default flavour exists.
  [ "$COMMAND_INSTALL" != true ] && [ ! -d "$ngineerx_flavour_dir/default" ] && chat 1 "It seems that ngineerx is not installed properly. Please run $ngineerx install."

  chat 2 "Starting $ngineerx with PID $ngineerx_pid."

  chat 3 "ngineerx_host_ip: $ngineerx_host_ip"
  chat 3 "ngineerx_php_pool_port: $ngineerx_php_pool_port"
  chat 3 "ngineerx_php_ports_db: $ngineerx_php_ports_db"
  chat 3 "ngineerx_php_user: $ngineerx_php_user"
  chat 3 "ngineerx_nginx_user: $ngineerx_nginx_user"
  chat 3 "ngineerx_flavour_dir: $ngineerx_flavour_dir"
  chat 3 "ngineerx_webroot: $ngineerx_webroot"
  chat 3 "ngineerx_temp_dir: $ngineerx_temp_dir"
  chat 3 "dehydrated: $dehydrated"
  chat 3 "dehydrated_conf_file: $dehydrated_conf_file"
  chat 3 "dehydrated_hook_file: $dehydrated_hook_file"
  chat 3 "dehydrated_domains_txt: $dehydrated_domains_txt"
  chat 3 "dehydrated_webroot: $dehydrated_webroot"
  chat 3 "dehydrated_args: $dehydrated_args"
  chat 3 "dehydrated_args_install: $dehydrated_args_install"
  chat 3 "newsyslog_conf_d: $newsyslog_conf_d"
  chat 3 "cron_conf_d: $cron_conf_d"
  chat 3 "nginx_rc: $nginx_rc"
  chat 3 "nginx_conf_dir: $nginx_conf_dir"
  chat 3 "nginx_dhkeysize: $nginx_dhkeysize"
  chat 3 "nginx_dh_file: $nginx_dh_file"
  chat 3 "nginx_pid_file: $nginx_pid_file"
  chat 3 "nginx_includes_dir: $nginx_includes_dir"
  chat 3 "nginx_sites_avaliable: $nginx_sites_avaliable"
  chat 3 "nginx_sites_enabled: $nginx_sites_enabled"
  chat 3 "phpfpm_rc: $phpfpm_rc"
  chat 3 "phpfpm_conf_d: $phpfpm_conf_d"
  chat 3 "phpfpm_pid_file: $phpfpm_pid_file"
  chat 3 "openssl: $openssl"

}

# Check if script is already running
# Usage: checkpid
checkPID () {

	touch $ngineerx_pid_file

	# Get stored PID from file
	ngineerx_stored_pid=`cat $ngineerx_pid_file`

	# Check if stored PID is in use
	ngineerx_pid_is_running=`ps aux | awk '{print $2}' | grep $ngineerx_stored_pid`

  chat 3 "rmbackup_pid: $ngineerx_pid"
  chat 3 "rmbackup_stored_pid: $ngineerx_stored_pid"
  chat 3 "rmbackup_pid_is_running: $ngineerx_pid_is_running"

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
  chat 3 "echo \"$@\" >> $dehydrated_domains_txt"
  echo "$@" >> $dehydrated_domains_txt
  ## Run cron renewal and create new certs
  chat 3 "$dehydrated ${dehydrated_args} -c"
  $dehydrated ${dehydrated_args} -c
}

# Replace @@VARIABLENAME@@ inplace given default config file with $VARIABLENAME.
# Usage: write_config sourcefile
write_config() {

  conf_file=$1

  chat 2 "Writing config file $conf_file"

  # Define the replacement patterns
  replacements="@@nginx_dhkeysize@@=$nginx_dhkeysize @@basedir@@=$basedir @@dehydrated_webroot@@=$dehydrated_webroot @@dehydrated_domains_txt@@=$dehydrated_domains_txt @@dehydrated_hook_file@@=$dehydrated_hook_file @@ngineerx_conf_dir@@=$ngineerx_conf_dir @@ngineerx_webroot@@=$ngineerx_webroot @@nginx_rc@@=$nginx_rc @@nginx_conf_dir@@=$nginx_conf_dir @@nginx_includes_dir@@=$nginx_includes_dir @@nginx_user@@=$ngineerx_nginx_user @@nginx_pid_file@@=$nginx_pid_file @@php_pool_port@@=$ngineerx_php_pool_port @@phpfpm_user@@=$ngineerx_php_user @@phpfpm_rc@@=$phpfpm_rc @@phpfpm_conf_dir@@=$phpfpm_conf_d @@phpfpm_pid_file@@=$phpfpm_pid_file @@ngineerx_host_ip@@=$ngineerx_host_ip @@site_domain@@=$site_domain @@site_root@@=$site_root @@site_webroot@@=$site_webroot @@nginx_dh_file@@=$nginx_dh_file"

  chat 3 "replacements: $replacements"

  for f in ${replacements}; do
    search=`echo $f | cut -f 1 -d "="`
    replace=`echo $f | cut -f 2 -d "="`

    chat 3 "sed -i "" \"s|${search}|${replace}|g\" $conf_file"
    sed -i "" "s|"${search}"|"${replace}"|g" $conf_file
    unset search replace
  done

  ## Small hack because of whitespaces between domain names
  search="@@domains@@"
  replace=${domains}
  chat 3 "sed -i \"\" \"s|${search}|${replace}|g\" $conf_file"
  sed -i "" "s|${search}|${replace}|g" $conf_file
  chat 3 "unset replacements search replace"
  unset replacements search replace
}

case "$1" in
  ######################## rmbackup.sh HELP ########################
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

    chat 2 "Creating directory structure"
    chat 3 "mkdir -p $nginx_conf_dir/sites-avaliable"
    mkdir -p $nginx_conf_dir/sites-avaliable
    chat 3 "mkdir -p $nginx_conf_dir/sites-enabled"
    mkdir -p $nginx_conf_dir/sites-enabled
    chat 3 "mkdir -p $ngineerx_webroot"
    mkdir -p $ngineerx_webroot
    chat 3 "mkdir -p  $phpfpm_conf_d"
    mkdir -p  $phpfpm_conf_d
    chat 3 "mkdir -p $dehydrated_webroot"
    mkdir -p $dehydrated_webroot

    chat 2 "Creating neccessary config files"
    chat 3 "Copying template files to tmp"
    chat 3 "mkdir -p $ngineerx_temp_dir"
    mkdir -p $ngineerx_temp_dir
    chat 3 "mkdir -p $ngineerx_temp_dir/ngineerx"
    mkdir -p $ngineerx_temp_dir/ngineerx
    chat 3 "cp /usr/local/share/ngineerx/ngineerx/dehydrated_config $ngineerx_temp_dir/ngineerx/"
    cp /usr/local/share/ngineerx/ngineerx/dehydrated_config $ngineerx_temp_dir/ngineerx/
    chat 3 "cp /usr/local/share/ngineerx/ngineerx/dehydrated_hook.sh $ngineerx_temp_dir/ngineerx/"
    cp /usr/local/share/ngineerx/ngineerx/dehydrated_hook.sh $ngineerx_temp_dir/ngineerx/
    chat 3 "cp -r /usr/local/share/ngineerx/nginx $ngineerx_temp_dir/"
    cp -r /usr/local/share/ngineerx/nginx $ngineerx_temp_dir/
    chat 3 "cp -r /usr/local/share/ngineerx/php* $ngineerx_temp_dir/"
    cp -r /usr/local/share/ngineerx/php* $ngineerx_temp_dir/

    ## modify all template files for concrete usage scenario

    for f in $(find $ngineerx_temp_dir -type f); do
      chat 3 "write_config $f"
      write_config "$f"
    done

    ## Copy config files to $basedir and delete tmp files
    chat 3 "cp -rf $ngineerx_temp_dir/* $basedir"
    cp -rf $ngineerx_temp_dir/* $basedir
    chat 3 "rm -r $ngineerx_temp_dir"
    rm -r $ngineerx_temp_dir

    chat 3 "cp -r /usr/local/share/ngineerx/ngineerx/flavours $ngineerx_conf_dir"
    cp -r /usr/local/share/ngineerx/ngineerx/flavours $ngineerx_conf_dir
    chat 3 "chmod +x $dehydrated_hook_file"
    chmod +x $dehydrated_hook_file

    chat 3 "touch $dehydrated_domains_txt"
    touch $dehydrated_domains_txt

    ## Create php-fpm.ports.db if it doesn't exist.
    if [ ! -f "$ngineerx_php_ports_db" ]; then
      chat 2 "$ngineerx_php_ports_db doesn't exist. I'll create it."
      chat 3 "echo $ngineerx_php_pool_port > $ngineerx_php_ports_db"
      echo $ngineerx_php_pool_port > $ngineerx_php_ports_db
    fi

    ## Create dhparam.pem only if it doesn't exist.
    if [ ! -f "$nginx_conf_dir/dhparam.pem" ]; then
      chat 2 "Creating diffie hellman parameters with $nginx_dhkeysize bit keysize. This may take a long time."
      chat 3 "$openssl dhparam -out $nginx_dh_file $nginx_dhkeysize"
      $openssl dhparam -out $nginx_dh_file $nginx_dhkeysize
    fi

    chat 2 "Enabling logrotation"
    chat 3 "mkdir -p $newsyslog_conf_d"
    mkdir -p $newsyslog_conf_d

    chat 2 "Setting up cron"
    chat 3 "mkdir -p $cron_conf_d"
    mkdir -p $cron_conf_d
    chat 3 "echo \"0 0 * * * root $0 cert-renew > /dev/null 2>&1\" > $cron_conf_d/ngineerx"
    echo "0 0 * * * root $0 cert-renew > /dev/null 2>&1" > $cron_conf_d/ngineerx

    chat 2 "Registering account at letsencrypt"
    chat 3 "$dehydrated ${dehydrated_args} ${dehydrated_args_install}"
    $dehydrated ${dehydrated_args} ${dehydrated_args_install}

    start_stop_stack_by_script start
  ;;
  ######################## ngineerx CREATE ########################
  create)
    shift; while getopts :d:uc:f: arg; do case ${arg} in
      d) domains=${OPTARG};;
      u) php_user=${OPTARG};;
      f) site_flavour=${OPTARG};;
      ?) chat 1 ${ngineerx_usage_create};;
      :) chat 1 ${ngineerx_usage_create};;
    esac; done; shift $(( ${OPTIND} - 1 ))

    init
    checkPID

    # Get the first domain name. It's used for naming the files and directories
    chat 3 site_domain=`echo ${domains} | cut -f 1 -d " "`
    site_domain=`echo ${domains} | cut -f 1 -d " "`
    chat 3 "site_domain=`echo ${domains} | cut -f 1 -d " "`"
    chat 3 "site_domain: $site_domain"
    chat 2 "Domain name that is used for the directory structure is $site_domain."

    site_root="$ngineerx_webroot/$site_domain"
    chat 3 "site_root: $site_root"
    site_webroot="$site_root/www"
    chat 3 "site_webroot: $site_webroot"

    # we need at least one domain name
    [ ! -d $site_domain ] || chat 1 ${ngineerx_usage_create}

    ## if no flavour is specified take default
    site_flavour="${site_flavour:-default}"
    chat 2 "Flavour $site_flavour will be used for site creation."
    chat 3 "site_flavour: $site_flavour"

    ## Check if flavour directory exists, otherwise exit
    [ -d "$ngineerx_conf_dir/flavours/$site_flavour" ] && site_flavour_dir="$ngineerx_conf_dir/flavours/$site_flavour" || chat 1 "ERROR: flavour $site_flavour not found in $ngineerx_flavour_dir."

    ## Check if nginx and php config files exist in flavour directory
    [ -f $site_flavour_dir/nginx.server.conf ] && site_flavour_nginx_conf="$site_flavour_dir/nginx.server.conf"
    [ -f $site_flavour_dir/php-fpm.pool.conf ] && site_flavour_phpfpm_pool_conf="$site_flavour_dir/php-fpm.pool.conf"

    ## Otherwise take them from default flavour
    site_flavour_nginx_conf="${site_flavour_nginx_conf:-$ngineerx_flavour_dir/default/nginx.server.conf}"
    site_flavour_phpfpm_pool_conf="${site_flavour_phpfpm_pool_conf:-$ngineerx_flavour_dir/default/php-fpm.pool.conf}"

    chat 2 "Creating directory structure."
    chat 3 "mkdir -p $site_root/www"
    mkdir -p $site_root/www
    chat 3 "mkdir -p $site_root/log"
    mkdir -p $site_root/log
    chat 3 "mkdir -p $site_root/tmp"
    mkdir -p $site_root/tmp
    chat 3 "mkdir -p $site_root/certs"
    mkdir -p $site_root/certs
    chat 3 "mkdir -p $site_root/sessions"
    mkdir -p $site_root/sessions

    # Create the certs
    chat 3 "create_cert $domains"
    create_cert $domains

    # Determine the next usable port number for the php-fpm pool
    chat 2 "Getting port for php-fpm-pool"
    chat 3 "ngineerx_php_pool_port=`cat $ngineerx_php_ports_db`"
    ngineerx_php_pool_port=`cat $ngineerx_php_ports_db`
    chat 3 "ngineerx_php_pool_port: $ngineerx_php_pool_port"

    # Create user and group $php_user and add $nginx_user to the group $php_user
    chat 2 "Creating user and adding user $ngineerx_nginx_user to group $ngineerx_php_user"
    chat 3 "pw user add $ngineerx_php_user -s /sbin/nologin"
    pw user add $ngineerx_php_user -s /sbin/nologin
    chat 3 "pw group mod $ngineerx_php_user -m $ngineerx_nginx_user"
    pw group mod $ngineerx_php_user -m $ngineerx_nginx_user

    chat 2 "Creating config files"
    chat 3 "cp $site_flavour_nginx_conf $nginx_sites_avaliable/$site_domain.conf"
    cp $site_flavour_nginx_conf $nginx_sites_avaliable/$site_domain.conf
    chat 3 "write_config $nginx_sites_avaliable/$site_domain.conf"
    write_config $nginx_sites_avaliable/$site_domain.conf
    chat 3 "cp $site_flavour_phpfpm_pool_conf $phpfpm_conf_d/$site_domain.conf"
    cp $site_flavour_phpfpm_pool_conf $phpfpm_conf_d/$site_domain.conf
    chat 3 "write_config $phpfpm_conf_d/$site_domain.conf"
    write_config $phpfpm_conf_d/$site_domain.conf

    # Copy sample files if they exist in flavour
    if [ -d "$site_flavour_dir/www" ]; then
      chat 2 "Copying sample files"
      chat 3 "cp -r $site_flavour_dir/www/* $site_webroot"
      cp -r $site_flavour_dir/www/* $site_webroot
    fi

    # Set strong permissions to files and directories
    chat 2 "Setting strong permissions to files and directories."
    chat 3 "chown -R $phpfpm_user:$phpfpm_user $site_root/"
    chown -R $phpfpm_user:$phpfpm_user $site_root/
    chat 3 "chmod 750 $site_root"
    chmod 750 $site_root
    chat 3 "chmod 750 $site_root/*"
    chmod 750 $site_root/*
    chat 3 "chmod 400 $site_root/certs/*"
    chmod 400 $site_root/certs/*

    # Link nginx config file from sites-avaliable to sites-enabled
    chat 2 "Enabling Server $site_domain"
    chat 3 "ln -sf $nginx_sites_avaliable/$site_domain.conf $nginx_sites_enabled/$site_domain.conf"
    ln -sf "$nginx_sites_avaliable/$site_domain.conf" "$nginx_sites_enabled/$site_domain.conf"

    # Add config files to newsyslog config
    chat 2 "Enabling logrotation"
    chat 3 "echo \"$site_root/log/nginx.access.log 644 12 * \$W0D23 J $nginx_pid_file 30\" >> $newsyslog_conf_d/$site_domain.conf"
    echo "$site_root/log/nginx.access.log 644 12 * \$W0D23 J $nginx_pid_file 30" >> $newsyslog_conf_d/$site_domain.conf
    chat 3 "echo \"$site_root/log/nginx.error.log 644 12 * \$W0D23 J $nginx_pid_file 30\" >> $newsyslog_conf_d/$site_domain.conf"
    echo "$site_root/log/nginx.error.log 644 12 * \$W0D23 J $nginx_pid_file 30" >> $newsyslog_conf_d/$site_domain.conf
    chat 3 "echo \"$site_root/log/phpfpm.slow.log 644 12 * \$W0D23 J $phpfpm_pid_file 30\" >> $newsyslog_conf_d/$site_domain.conf"
    echo "$site_root/log/phpfpm.slow.log 644 12 * \$W0D23 J $phpfpm_pid_file 30" >> $newsyslog_conf_d/$site_domain.conf
    chat 3 "echo \"$site_root/log/phpfpm.error.log 644 12 * \$W0D23 J $phpfpm_pid_file 30\" >> $newsyslog_conf_d/$site_domain.conf"
    echo "$site_root/log/phpfpm.error.log 644 12 * \$W0D23 J $phpfpm_pid_file 30" >> $newsyslog_conf_d/$site_domain.conf

    # Increment php-fpm pool port and store in file
    echo "$(expr "$ngineerx_php_pool_port" + 1)" > $ngineerx_php_ports_db

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
    chat 2 "Deleting nginx config for $site_domain"
    chat 3 "rm \"$nginx_sites_enabled/$site_domain.conf\""
    rm "$nginx_sites_enabled/$site_domain.conf"
    chat 3 "rm \"$nginx_sites_avaliable/$site_domain.conf\""
    rm "$nginx_sites_avaliable/$site_domain.conf"

    chat 2 "Deleting php-fpm config for $site_domain"
    chat 3 "rm \"$phpfpm_conf_d/$site_domain.conf\""
    rm "$phpfpm_conf_d/$site_domain.conf"

    chat 2 "Deleting newsyslog config for $site_domain"
    chat 3 "rm \"$newsyslog_conf_d/$site_domain.conf\""
    rm "$newsyslog_conf_d/$site_domain.conf"

    chat 2 "Deleting $site_domain from $dehydrated_domains_txt."
    chat 3 "sed -i \"\" \"/\"${site_domain}\"/d\" ${dehydrated_domains_txt}"
    sed -i "" "/"${site_domain}"/d" ${dehydrated_domains_txt}
    chat 2 "Moving certs to archive."
    chat 3 "$dehydrated ${dehydrated_args} --gc"
    $dehydrated ${dehydrated_args} -gc

    #[TODO]: Implement a flag for toggeling deletion of content
    # Delete content from webroot
    echo "+++ Deleting files for $site_domain"
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
    chat 2 "Enabeling $site_domain"
    chat 3 "ln -sf $nginx_sites_avaliable/$site_domain.conf $nginx_sites_enabled/$site_domain.conf"
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
    chat 2 "Disabeling $site_domain"
    chat 3 "rm $nginx_sites_enabled/$site_domain.conf"
    rm $nginx_sites_enabled/$site_domain.conf

    # Restart stack
    start_stop_stack_by_script restart
  ;;
  ######################## ngineerx CERT-RENEW ########################
  cert-renew)
    checkPID
    init

    chat 2 "Renewing certificates."
    chat 3 "$dehydrated ${dehydrated_args} -c"
    $dehydrated ${dehydrated_args} -c

    start_stop_stack_by_script restart
  ;;
  ######################## ngineerx LIST ########################
  list)
    init

    # get pids for nginx and php-fpm
    list_nginx_pid=`touch "$ngineerx_pid_file" && cat "$ngineerx_pid_file"`
    list_phpfpm_pid=`touch "$phpfpm_pid_file" && cat "$phpfpm_pid_file"`

    [ -z $list_nginx_pid ] && list_nginx_pid="not running"
    [ -z $list_phpfpm_pid ] && list_phpfpm_pid="not running"

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
        if [ -f $phpfpm_conf_dir/$list_filename ] ; then
          list_phpfpm_pool_port=`grep "listen " $phpfpm_conf_dir/$list_filename | cut -d ":" -f2-`;
        fi

        list_pool="${list_phpfpm_pool_port:-N/A}"

        # populate data for printf
        list_data="$list_data$list_displayname $list_status $list_pool "
      done
    else
        echo ""
        echo "No sites defined yet."
        echo "Run $ngineerx install -d \"DOMAINS\" to create one."
    fi

    # Print list
    printf "$list_format" $list_data
    echo $list_divider
    echo "ngineerx Status: nginx PID=$list_nginx_pid | php-fpm PID=$list_phpfpm_pid"
  ;;
  *)
  help 1
  ;;
esac
