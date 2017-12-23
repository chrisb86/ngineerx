#!/usr/bin/env bash

# ngineerx
# Copyright 2015 Christian Busch
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
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTI

## Set script name and config directory
ngineerx=`basename -- $0`
ngineerx_conf_dir="/usr/local/etc/ngineerx"

# Exit with errormessage
# Usage: exerr errormessage
exerr () { echo -e "$*" >&2 ; exit 1; }

# Pass command to init scripts
# Usage: start_stop_stack_by_script restart
start_stop_stack_by_script () {
  $nginx $@
  $phpfpm $@
}

# Check required dependencies
# Usage: check_dependencies binary errormessage
check_dependencies () {
  [ -x "$(command -v $1)" ] || exerr "$2"
}

# Show help screen
# Usage: help exitcode
help () {
  echo "Usage: $ngineerx command {params}"
  echo
  echo "install       Copy config files for nginx and php and create directory structure"
  echo "create        Create new site"
  echo "  -d DOMAINNAME               Domain that nginx should listen to and for that the certificate is created."
  echo "                              Use multiple times if you want to serve multiple domains"
  echo "  [-u PHP_USER]               The user that PHP should run as"
  echo "  [-f FLAVOUR]                Use a specific flavour for site creation"
  echo "  [-w]                        Define a non-standard sites webroot"
  echo "cert-create   Create certificates only"
  echo "  -d DOMAINNAME               Domain that the certificate is created for."
  echo "  [-k PRIVKEY]                Path where privkey.pem should be linked to."
  echo "  [-f FULLCHAIN]              Path where fullchain.pem should be linked to."
  echo "cert-renew    Renew certificates with letsencrypt"
  echo "htpasswd      Create htpasswd file for password authentication."
  echo "  -u USERNAME                 The user that should be added"
  echo "  -f FILE                     The file where credentials should be stored"
  echo "delete        Delete a site"
  echo "  -d DOMAINNAME               Domain that should be deleted"
  echo "list          Lists all avaliable sites and their webroots and php-fpm ports."
  echo "enable        Enables the nginx configs of the given domain"
  echo "  -d DOMAINNAME               Domain that should be enabled"
  echo "disable       Disables the nginx configs of the given domain"
  echo "  -d DOMAINNAME               Domain that should be disabled"
  echo "start         Start the nginx and php-fpm"
  echo "stop          Stop the nginx and php-fpm"
  echo "restart       Restart the nginx and php-fpm"
  echo "help          Show this screen"

  exit $1
}

# Replace @@VARIABLENAME@@ in inplace given default config file with $VARIABLENAME.
# Usage: write_config sourcefile
write_config() {

    conf_file=$1

    # Define the replacement patterns
    declare -A conf_replace
    conf_replace=(
        [@@dhkeysize@@]=dhkeysize
        [@@etc_dir@@]=$etc_dir
        [@@le_keysize@@]=$le_keysize
        [@@le_email@@]=$le_email
        [@@letsencrypt_conf_dir@@]=$letsencrypt_conf_dir
        [@@letsencrypt_webroot@@]=$letsencrypt_webroot
        [@@ngineerx_conf_dir@@]=$ngineerx_conf_dir
        [@@ngineerx_webroot@@]=$ngineerx_webroot
        [@@nginx@@]=]=$nginx
        [@@nginx_conf_dir@@]=$nginx_conf_dir
        [@@nginx_includes@@]=$nginx_includes
        [@@nginx_domains@@]=$nginx_domains
        [@@nginx_user@@]=$nginx_user
        [@@nginxpid@@]=$nginxpid
        [@@php_pool_port@@]=$php_pool_port
        [@@php_user@@]=$php_user
        [@@phpfpm@@]=$phpfpm
        [@@phpfpm_conf_dir@@]=$phpfpm_conf_dir
        [@@phppid@@]=$phppid
        [@@server_ip@@]=$server_ip
        [@@site_domain@@]=$site_domain
        [@@site_root@@]=$site_root
        [@@site_webroot@@]=$site_webroot
    )

    # Loop the config array
    for i in "${!conf_replace[@]}"
    do
        search=$i
        replace=${conf_replace[$i]}

        sed -i "" "s|${search}|${replace}|g" $conf_file
    done
}


# Take the list of domains in array ${domain_args[@]} and echo them seperated by the specified separator as one string
# Usage: parse_domains sepereator
parse_domains () {
  for val in "${domain_args[@]}"; do
      domains="$domains $val "
  done

  echo $domains
}

# Create certificates
# Usage: create_cert privkey fullchain
create_cert () {
  ## Create certs with letsencrypt
  
  echo "+++ Creating certificates with letsencrypt"
  ## Add domains to domains.txt
  echo $nginx_domains >> $letsencrypt_conf_dir/domains.txt
  ## Run cron renewal and create new certs
  $letsencrypt -c

  cert_path="$letsencrypt_conf_dir/certs/$site_domain"

  # If a path was speciefied, link certs

  [ $2 ] || [ $3 ] && echo "+++ Linking the certificates to desired destination"
  [ $2 ] && ln -si $cert_path/privkey.pem $2
  [ $3 ] && ln -si $cert_path/fullchain.pem $3
}

## Let's make the magic happen...

# Set some defaults

dhkeysize="${dhkeysize:-4096}"
etc_dir="${etc_dir:-/usr/local/etc}"
le_email="${le_email:-}"
le_keysize="${le_keysize:-4096}"
le_options="${le_options:---agree-tos}"
letsencrypt_conf_dir="${letsencrypt_conf_dir:-$etc_dir/letsencrypt.sh}"
letsencrypt="${letsencrypt:-$letsencrypt_conf_dir/dehydrated}"
letsencrypt_webroot="${letsencrypt_webroot:-$letsencrypt_conf_dir/.acme-challenges}"
ngineerx_webroot="${ngineerx_webroot:-/usr/local/www}"
nginx="${nginx:-$etc_dir/rc.d/nginx}"
nginx_conf_dir="${nginx_conf_dir:-$etc_dir/nginx}"
nginx_includes="${nginx_includes:-$nginx_conf_dir/includes}"
nginx_user="${nginx_user:-www}"
nginxpid="${nginxpid:-/var/run/nginx.pid}"
php_pool_port="${php_pool_port:-9001}"
php_user="${php_user:-www_php}"
phpfpm="${phpfpm:-$etc_dir/rc.d/php-fpm}"
phpfpm_conf_dir="${phpfpm_conf_dir:-$etc_dir/php-fpm.d}"
phppid="${phppid:-/var/run/php-fpm.pid}"
server_ip="${server_ip:-}"
tmp_dir="${tmp_dir:-/tmp/ngineerx}"

# Synopsis messages
ngineerx_usage_ngineerx="Usage: $ngineerx [install|create|cert-create|cert-renew|delete|list|enable|disable|start|stop|restart|help] {params}"
ngineerx_usage_create="Usage: $ngineerx create -d DOMAINNAME [-d DOMAINNAME] [-u PHP_USER] [-f FLAVOUR] [-w WEBROOT]"
ngineerx_usage_delete="Usage: $ngineerx delete -d DOMAINNAME"
ngineerx_usage_enable="Usage: $ngineerx enable -d DOMAINNAME"
ngineerx_usage_disable="Usage: $ngineerx disable -d DOMAINNAME"
ngineerx_usage_cert_create="Usage: $ngineerx cert-create [-k PRIVKEY] [-f FULLCHAIN] -d DOMAINNAME"
ngineerx_usage_htpasswd="Usage: $ngineerx htpasswd -u USER -f FILE"
ngineerx_usage_list="Usage: $ngineerx list"

# Check for command. If none is given, show help and exit with error.
[ $# -gt 0 ] || help 1;

# Load ngineerx.config if it exists. Otherwise exit with error message.
[ -f $ngineerx_conf_dir/ngineerx.conf ] || exerr "ERROR: Could not load $ngineerx_conf_dir/ngineerx.conf. \nSee $ngineerx_conf_dir/ngineerx.conf.dist for instructions."

source $ngineerx_conf_dir/ngineerx.conf

# When command is not help, source config
if [ "$1" != "help" ]; then
  ## Load ngineerx.config if it exists. Otherwise exit with error message.
  [ -f $ngineerx_conf_dir/ngineerx.conf ] || exerr "ERROR: Could not load $ngineerx_conf_dir/ngineerx.conf. \nSee $ngineerx_conf_dir/ngineerx.conf.dist for instructions."
  
  source $ngineerx_conf_dir/ngineerx.conf
fi

case "$1" in
######################## ngineerx INSTALL ########################
install)
  # Check if IP address is set.
  [ -z $server_ip ] && exerr "ERROR: We need an IP address for creating the neccessary config files.\n Please specify one in ngineerx.conf."
  
  echo "+++ Checking dependencies"
  check_dependencies $nginx "ERROR: nginx not found. Please install nginx and/or define its path in ngineerx.conf"
  check_dependencies $phpfpm "ERROR: php-fpm not found. Please install php-fpm and/or define its path in ngineerx.conf"
  check_dependencies $openssl "ERROR: openssl not found. Please install openssl and/or define its path in ngineerx.conf"

  #[TODO]: Implement a prompt to overwrite existing files and create backups
  echo "+++ Creating directory structure"
  mkdir -p $nginx_conf_dir/{sites-avaliable,sites-enabled}
  mkdir -p $ngineerx_webroot
  mkdir -p $ngineerx_conf_dir/selfsigned-certs
  mkdir -p $phpfpm_conf_dir
  mkdir -p $letsencrypt_webroot
  mkdir -p $etc_dir/letsencrypt.sh

  echo "+++ Creating neccessary config files"

  ## Copy template files to tmp
  mkdir -p $tmp_dir
  cp -r /usr/local/share/ngineerx/letsencrypt.sh $tmp_dir
  cp -r /usr/local/share/ngineerx/nginx $tmp_dir
  cp -r /usr/local/share/ngineerx/php* $tmp_dir

  ## modify template files for concrete usage scenario
  find $tmp_dir -type f | while read f; do
    write_config $f
  done

  ## Copy config files to /usr/local/etc and delete tmp files
  cp -r $tmp_dir/* $etc_dir && rm -r $tmp_dir

  cp -r /usr/local/share/ngineerx/ngineerx/* $ngineerx_conf_dir

  touch $letsencrypt_conf_dir/domains.txt

  ## Create php-fpm.ports.db if it doesn't exist.
  if [ ! -f "$ngineerx_conf_dir/php-fpm.ports.db" ]; then
    echo $php_pool_port > $ngineerx_conf_dir/php-fpm.ports.db
  fi
  
  ## Create dhparam.pem only if it doesn't exist.
  if [ ! -f "$nginx_conf_dir/dhparam.pem" ]; then
    echo "+++ Creating diffie hellman parameters with $dhkeysize bit keysize. This may take a long time."
    $openssl dhparam -out $nginx_conf_dir/dhparam.pem $dhkeysize;
  fi

  echo "+++ Enabling logrotation"
  echo "<include> $ngineerx_conf_dir/ngineerx.newsyslog.conf" >> /etc/newsyslog.conf
  touch $ngineerx_conf_dir/ngineerx.newsyslog.conf

  start_stop_stack_by_script start
  ;;
######################## ngineerx CREATE ########################
create)
  shift; while getopts :d:uc:f:w: arg; do case ${arg} in
    d) domain_args+=("$OPTARG");;
    u) php_user=${OPTARG};;
    f) site_flavour=${OPTARG};;
    w) site_webroot=${OPTARG};;
    ?) exerr ${ngineerx_usage_create};;
    :) exerr ${ngineerx_usage_create};;
  esac; done; shift $(( ${OPTIND} - 1 ))

  # Get the first domain name. It's used for naming the files and directories
  site_domain=${domain_args[0]}

  site_root="${site_root:-$ngineerx_webroot/$site_domain}"
  site_webroot="${site_webroot:-$site_root/www}"

  # we need at least one domain name
  [ ! -d $site_domain ] || exerr ${ngineerx_usage_create}

  # Create domain list string for nginx config and cert creation
  nginx_domains=`parse_domains`

  #[TODO]: Implement a prompt to overwrite existing files and create backups
  
  ## if no flavour is specified take default
  site_flavour="${site_flavour:-default}"

  ## Check if flavour directory exists, otherwise exit
  [ -d "$ngineerx_conf_dir/flavours/$site_flavour" ] && site_flavour_dir="$ngineerx_conf_dir/flavours/$site_flavour" || exerr "ERROR: flavour $site_flavour not found in $ngineerx_conf_dir/flavours."

  ## Check if nginx and php config files exist in flavour directory
  [ -f $site_flavour_dir/nginx.server.conf ] && site_flavour_nginx_conf="$site_flavour_dir/nginx.server.conf"
  [ -f $site_flavour_dir/php-fpm.pool.conf ] && site_flavour_phpfpm_pool_conf="$site_flavour_dir/php-fpm.pool.conf"

  ## Otherwise take them from default flavour
  site_flavour_nginx_conf="${site_flavour_nginx_conf:-$ngineerx_conf_dir/flavours/default/nginx.server.conf}"
  site_flavour_phpfpm_pool_conf="${site_flavour_phpfpm_pool_conf:-$ngineerx_conf_dir/flavours/default/php-fpm.pool.conf}"

  echo "+++ Creating directory structure"
  mkdir -p $site_root/{www,log,tmp,certs,sessions}

  # Create the certs
  create_cert $site_root/certs/privkey.pem $site_root/certs/fullchain.pem

  # Determine the next usable port number for the php-fpm pool
  php_pool_port=`cat $ngineerx_conf_dir/php-fpm.ports.db`

  # Create user and group $php_user and add $nginx_user to the group $php_user
  echo "+++ Creating user and adding user $nginx_user to group $php_user"
  pw user add $php_user -s /sbin/nologin
  pw group mod $php_user -m $nginx_user

  echo "+++ Creating config files"
  cp $site_flavour_nginx_conf $nginx_conf_dir/sites-avaliable/$site_domain.conf
  cp $site_flavour_phpfpm_pool_conf $phpfpm_conf_dir/$site_domain.conf 
  
  write_config $nginx_conf_dir/sites-avaliable/$site_domain.conf
  write_config $phpfpm_conf_dir/$site_domain.conf 

  echo "+++ Copying sample files"
  cp -r $site_flavour_dir/www/* $site_webroot

  # Set strong permissions to files and directories
  chown -R $php_user:$php_user $site_root/
  chmod 750 $site_root
  chmod 750 $site_root/*
  chmod 400 $site_root/certs/*

  # Link nginx config file from sites-avaliable to sites-enabled
  echo "+++ Enabling Server $site_domain"
  ln -sf $nginx_conf_dir/sites-avaliable/$site_domain.conf $nginx_conf_dir/sites-enabled/$site_domain.conf

  # Add config files to newsyslog config 
  echo "+++ Enabling logrotation"
  echo "$site_root/log/nginx.access.log 644 12 * \$W0D23 J $nginxpid 30" >> $ngineerx_conf_dir/ngineerx.newsyslog.conf
  echo "$site_root/log/nginx.error.log 644 12 * \$W0D23 J $nginxpid 30" >> $ngineerx_conf_dir/ngineerx.newsyslog.conf
  echo "$site_root/log/phpfpm.slow.log 644 12 * \$W0D23 J $phppid 30" >> $ngineerx_conf_dir/ngineerx.newsyslog.conf
  echo "$site_root/log/phpfpm.error.log 644 12 * \$W0D23 J $phppid 30" >> $ngineerx_conf_dir/ngineerx.newsyslog.conf

  # Increment php-fpm pool port and store in file
  echo "$(expr "$php_pool_port" + 1)" > $ngineerx_conf_dir/php-fpm.ports.db

  # Restart stack
  start_stop_stack_by_script restart
  ;;
######################## ngineerx CERT-CREATE ########################
cert-create)
  shift; while getopts :d:c:f:w: arg; do case ${arg} in
    d) domain_args+=("$OPTARG");;
    k) cert_privkey=${OPTARG};;
    f) cert_fullchain=${OPTARG};;
    ?) exerr ${ngineerx_usage_cert-create};;
    :) exerr ${ngineerx_usage_cert-create};;
  esac; done; shift $(( ${OPTIND} - 1 ))

  # Get the first domain name. It's used for naming the files and directories
  site_domain=${domain_args[0]}

  # we need at least one domain name
  [ ! -d $site_domain ] || exerr ${ngineerx_usage_cert_create}

  echo "+++ Creating certificates"
  create_cert $cert_privkey $cert_fullchain
  ;;
######################## ngineerx CERT-RENEW ########################
cert-renew)

  echo "+++ Renewing certificates with letsencrypt"
  $letsencrypt -c

  start_stop_stack_by_script restart
  ;;
######################## ngineerx HTPASSWD ########################
htpasswd)
  shift; while getopts :u:f: arg; do case ${arg} in
    u) htpasswd_user=${OPTARG};;
    f) htpasswd_file=${OPTARG};;
    ?) exerr ${ngineerx_usage_htpasswd};;
    :) exerr ${ngineerx_usage_htpasswd};;
  esac; done; shift $(( ${OPTIND} - 1 ))

  echo "+++ Adding user $htpasswd_user to file $htpasswd_file."
  printf "$htpasswd_user:`$openssl passwd -apr1`\n" >> $htpasswd_file
  ;;
######################## ngineerx DELETE ########################
delete)
  shift; while getopts :d: arg; do case ${arg} in
    d) site_domain=${OPTARG};;
    ?) exerr ${ngineerx_usage_delete};;
    :) exerr ${ngineerx_usage_delete};;
  esac; done; shift $(( ${OPTIND} - 1 ))

  # we need at least a domain name
  [ ! -d $site_domain ] || exerr ${ngineerx_usage_delete}

  # Delete config files
  echo "+++ Deleting nginx config for $site_domain"
  rm $nginx_conf_dir/sites-enabled/$site_domain.conf
  rm $nginx_conf_dir/sites-avaliable/$site_domain.conf

  echo "+++ Deleting php-fpm config for $site_domain"
  rm $etc_dir/php-fpm.d/$site_domain.conf

  # Ditch config files of given domain from nginx config
  echo "+++ Deleting newsyslog config for $site_domain"
  echo "$(grep -v "$site_domain" $ngineerx_conf_dir/ngineerx.newsyslog.conf)" > $ngineerx_conf_dir/ngineerx.newsyslog.conf
  
  #[TODO]: Implement a flag for toggeling deletion of content
  # Delete content from webroot
  echo "+++ Deleting files for $site_domain"
  rm -r $site_root

  # Restart stack
  start_stop_stack_by_script restart
  ;;
######################## ngineerx LIST ########################
list)
  shift; while getopts : arg; do case ${arg} in
    ?) exerr ${ngineerx_usage_list};;
    :) exerr ${ngineerx_usage_list};;
  esac; done; shift $(( ${OPTIND} - 1 ))

  # get pids for nginx and php-fpm
  list_nginxpid=$(cat "$nginxpid")
  list_phppid=$(cat "$phppid")

  [ -z $list_nginxpid ] && list_nginxpid="not running"
  [ -z $list_phppid ] && list_phppid="not running"

  # set formating options
  list_header=" %-35s %8s %4s\n"
  list_format=" %-35s %8s %4s\n"
  list_data=""
  list_divider="------------------------------------ -------- ----"
  
  printf "$list_header" "SITENAME" "STATUS" "POOL"

  echo $list_divider

  for list_file in $nginx_conf_dir/sites-avaliable/*; do

    unset list_phpport
    
    # format filename
    list_filename=$(basename "$list_file")
    list_displayname=$(basename "$list_file" .conf)
    
    # if config is linked to sites-enabled set status to enabled
    list_status=`[ -f $nginx_conf_dir/sites-enabled/$list_filename ] && echo "ENABLED" || echo "DISABLED"`

    # grep php-fpm port from config file if it exists
    if [ -f $phpfpm_conf_dir/$list_filename ] ; then
      list_phpport=`grep "listen " $phpfpm_conf_dir/$list_filename | cut -d ":" -f2-`;
    fi

    list_pool="${list_phpport:-N/A}"
    
    # populate data for printf
    list_data="$list_data$list_displayname $list_status $list_pool "
  done
  
  # Print list
  printf "$list_format" $list_data
  echo $list_divider
  echo "ngineerx Status: nginx PID=$list_nginxpid | php-fpm PID=$list_phppid"

  ;;
######################## ngineerx ENABLE ########################
enable)
  shift; while getopts :d: arg; do case ${arg} in
    d) site_domain=${OPTARG};;
    ?) exerr ${ngineerx_usage_enable};;
    :) exerr ${ngineerx_usage_enable};;
  esac; done; shift $(( ${OPTIND} - 1 ))

  # we need at least a domain name
  [ ! -d $site_domain ] || exerr ${ngineerx_usage_enable}

  # Link nginx config file from sites-avaliable to sites-enabled
  echo "+++ Enabeling $site_domain"
  ln -sf $nginx_conf_dir/sites-avaliable/$site_domain.conf $nginx_conf_dir/sites-enabled/$site_domain.conf

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

  # we need at least a domain name
  [ ! -d $site_domain ] || exerr ${ngineerx_usage_disable}

  # Delete link  to nginx config file from sites-enabled
  echo "+++ Disabeling $site_domain"
  rm $nginx_conf_dir/sites-enabled/$site_domain.conf

  # Restart stack
  start_stop_stack_by_script restart
  ;;
######################## ngineerx SHORTCUT ########################
*start|*stop|*status|*restart)
  start_stop_stack_by_script $@
  ;;
help)
  help 0
  ;;
:)
  help 1
  ;;
esac

# Reset Variables
unset cert_path
unset cert_privkey
unset cert_fullchain
unset counter
unset dhkeysize
unset conf_replace
unset domain_args
unset domains
unset etc_dir
unset le_email
unset le_keysize
unset le_options
unset letsencrypt
unset letsencrypt_conf_dir
unset letsencrypt_webroot
unset list_data
unset list_displayname
unset list_displayname
unset list_divider
unset list_file
unset list_filename
unset list_filename
unset list_format
unset list_header
unset list_nginxpid
unset list_phppid
unset list_phpport
unset list_status
unset list_status
unset list_webroot
unset ngineerx
unset ngineerx_conf_dir
unset ngineerx_usage_create
unset ngineerx_usage_delete
unset ngineerx_usage_disable
unset ngineerx_usage_enable
unset ngineerx_usage_ngineerx
unset ngineerx_webroot
unset nginx
unset nginx_conf_dir
unset nginx_includes
unset nginx_domains
unset nginx_user
unset nginxpid
unset openssl
unset openssl_subj
unset openssl_subj_c
unset openssl_subj_emailaddress
unset openssl_subj_l
unset openssl_subj_o
unset openssl_subj_ou
unset openssl_subj_st
unset php_pool_port
unset php_user
unset phpfpm
unset phpfpm_conf_dir
unset phppid
unset htpasswd_file
unset htpasswd_user
unset server_ip
unset site_domain
unset site_root
unset site_webroot
unset site_flavour
unset site_flavour_dir
unset site_flavour_nginx_conf
unset site_flavour_phpfpm_pool_conf
unset val
unset tmp_dir
unset sed_replace

exit 0