# ngineerx

``ngineerx`` is a low dependency tool to configure and manage an encrypted nginx and php-fpm stack on FreeBSD systems.

It creates a nginx server config, the neccessary directory structure and a php-fpm pool for every site that nginx delivers. Every site that's created will be listening on IPv4 and IPv6 and will encrypt all traffic by default with certificates created with letsencrypt. All the logs are rotated by default. The nginx config is created with privacy and security in mind.

```text
Usage: ngineerx command {params}

install         Copy config files for nginx and php and create directory structure
create          Create new site
 -d "DOMAINS"     Domains that should be served by a site
 [-u PHP_USER]    User that should be used for PHP
 [-f FLAVOUR]     Flavour that should be used to create a site
 [-c]             Only create certificates without directory structure
 [-p]             Create a site wothout a PHP handler.
delete          Delete a site
 -d DOMAIN        Main domain of a site that should be deleted
enable          Enable a site in nginx
 -d DOMAIN        Main domain of a site that should be enabled
disable         Disable a site in nginx
 -d DOMAIN        Main domain of a site that should be disabled
cert-renew      Renew certificates
list            List all sites
help            Show this screen
```

## Setup:

### Install nginx and PHP

The first step is to compile ``nginx``.

```bash
$ cd /usr/ports/www/nginx
$ make install clean
```
You need to enable SSL and HTTP2. Set the other options at your will.

After that you can install ``PHP``. I like to compile ``php*-extensions`` because I can configure all needed modules and PHP will be installed as well.
```bash
$ cd /usr/ports/lang/php74-extensions
$ make install clean
```

PHP-FPM is required. Set all other options at your will.

Put nginx and php-fpm in /etc/rc.conf so they will be startet at boot time.
```bash
$ sysrc nginx_enable="YES"
$ sysrc php_fpm_enable="YES"
```

The last step is to install ``dehydrated``.

```bash
$ cd /usr/ports/security/dehydrated
$ make install clean
```

That's it.

### Install ngineerx

Now we can install ngineerx.

Clone the git repository to your machine.

```bash
$ git clone https://git.debilux.org/ngineerx
```

Install ngineerx:

```bash
$ cd ngineerx
$ make install
```

You may change settings in _/usr/local/etc/ngineerx/ngineerx.conf_ but it's not necessary. If you run ngineerx in a jail with a shared IP, you should set _$NGINEERX_HOST_IP_ to the IP of your Jail.

Bootstrap ngineerx with:

```bash
$ ngineerx install
```

### Create a site

Now you can create your first site with a letsencrypt certificate.

```bash
$ ngineerx create -d "example.com www.example.com"
```

That's it. If your DNS records are set up correctly, you should be able to reach https://example.com. To check if PHP is working, open https://example.com/info.php.

#### Flavours

ngineerx is able to use flavours as templates for new sites.

you can find the default flavour at ``/usr/local/etc/ngineerx/flavours/default``. Flavours can contain a special nginx and PHP config  template. You also can put files in a subdirectory called ``www`` and put all files in there that you want to copy to the sites webroot at creation.

If the files ``nginx.server.conf`` or ``php-fpm.pool.conf`` are not found in the flavour directory, the default ones will be used.

### Create just a certificate
If you want to create just a certificate without directory structure beacause you want to use it for e.g. your mail oder ftp server you can run ```$ ngineerx create -c -d "mail.example.com"```.

### Certificate renewal

You can renew your letsencrypt certificates with
```bash
$ ngineerx cert-renew
```

At installation ``ngineerx``creates a cronjob in /usr/local/etc/cron.d/ngineerx. Feel free to edit it.
