#ngineerx

## Changelog:
**2018-04-01:**
- Renamed letsencrypt.sh to it's new project name dehydrated

**2017-12-24:**
- Removed some unused variables.
- write_config() is rewritten and much more readable now.

**2017-12-23:**
- Fixed a bug where php-fpm config wasn't deleted when deleting a site
- removed support for selfsigned certs.

**2017-01-25:**
- Added functionality to create htpasswd files for password authentication.

**2016-05-24:**
- Added a Makefile. Run ``make install`` to update the repository and all submodules and install all the stuff where it belongs.

**2016-05-23:**
- Splitted nginx config to several files.

**2016-05-10:**
- Hardened nginx SSL config
- Switched nginx to HTTP2
- Changed default dhparams key size for nginx to 4096 bit

**2016-03-12:**
- Fixed a bug in php-fpm.conf that prevented it to work with PHP7

**2016-01-07:**
- Renamed command renew to cert-renew
- Added command cert-create to create certs without createing a site in nginx
- Added flavour for wordpress multisites

**2016-01-06:**
- Adedd an option to use flavours
- Fixed permissions for certs
- Added flavour for owncloud configuration
- Implemented letsencrypt.sh as acme client for certificate creation with letsencrypt
- Implemented renew command for renewing certs via cron
- Updated instructions in README

**2016-01-05:**
- Optimized nginx config
- Disabled display of webroot in list command
- Put CHANGELOG in separate file and out of README

**2015-12-29:**
- Modified nginx config for letsencrypt renewal
- Fixed some errors in structure of nginx config files

**2015-12-28:**
- Added a switch to toggle creation of sample files
- Implemented help screen 
- Implemented a switch to define a non-standard webroot

**2015-12-27:**
- Fixed a bug in storage of the next usable port for the php-fpm pools
- Added the list command
- Fixed a bug where no self-signed certificate is created, when only one domain is given
- Made creation of self-signed cert configurable
- Added a switch to set type of cert creation (selfsigned or letsencrypt; default: selfsigned)

**2015-12-26:**
- Added comments and TODOs to the script
- Added check for config file
- Added initalization of some decent defaults
- Added check for dependencies

**2015-12-24:**
- Added a lot of comments to the config files
- Modified the default config for nginx
- Implemented a more robust templating system

**2015-12-23:**
- Refactored some code and cleaned up variable names

**2015-12-22:**
- Implemented certificate creation with letsencrypt
- Activated OCSP stapling
- Implemented possibility to create server and certs for multiple domains
- SHA256 will be used for creation of self-signed certs now 

**2015-12-20:**
- Implemented usage of custom Diffie Hellman parameters for TLS/SSL.

**2015-12-19:**
- Added setup instructions to README

**2015-12-18:**
- Enabled log rotation with newsyslog
- Enabled SPDY in site specific configs (until nginx 1.9 is default version in FreeBSD so we can switch to HTTPS/2)

**2015-12-17:**
- First commit