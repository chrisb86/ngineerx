# ngineerx

``ngineerx`` is a bash script to configure and manage an nginx and php-fpm stack on FreeBSD systems.

It creates an nginx server config, the neccessary directory structure and a php-fpm pool for every site that nginx delivers. Every site that's created will be listening on IPv4 and IPv6 and will encrypt traffic by default with certificates created with letsencrypt. All the logs are rotated by default. The nginx config is created with privacy in mind. The default configuration results in an A+ rating by [Qualys SSL Labs](https://www.ssllabs.com/ssltest/).

```text
Usage: ngineerx command {params}

install       Copy config files for nginx and php and create directory structure
create        Create new site
  -d DOMAINNAME               Domain that nginx should listen to and for that the certificate is created.
                              Use multiple times if you want to serve multiple domains
  [-u PHP_USER]               The user that PHP should run as
  [-c letsencrypt|selfsigned] Certificate type. "letsencrypt" or "selfsigned".
  [-f FLAVOUR]                Use a specific flavour for site creation
  [-w]                        Define a non-standard sites webroot
cert-create   Create certificates only
  -d DOMAINNAME               Domain that the certificate is created for.
  [-c letsencrypt|selfsigned] Certificate type. "letsencrypt" or "selfsigned".
  [-k PRIVKEY]                Path where privkey.pem should be linked to.
  [-f FULLCHAIN]              Path where fullchain.pem should be linked to.
cert-renew    Renew certificates with letsencrypt"
delete        Delete a site
  -d DOMAINNAME               Domain that should be deleted
list          Lists all avaliable sites and their webroots and php-fpm ports.
enable        Enables the nginx configs of the given domain
  -d DOMAINNAME               Domain that should be enabled
disable       Disables the nginx configs of the given domain
  -d DOMAINNAME               Domain that should be disabled
start         Start the nginx and php-fpm
stop          Stop the nginx and php-fpm
restart       Restart the nginx and php-fpm
help          Show this screen
```

## Setup:

### Install nginx and PHP

The first step is to compile nginx.

```bash
$ cd /usr/ports/www/nginx
$ make install clean
```
You need to enable SSL and HTTP2. Set the other options at your will.

After that you can install PHP. I like to compile ``php*-extensions`` because I can configure all needed modules and PHP will be installed as well.
```bash
$ cd /usr/ports/lang/php56-extensions
$ make install clean
```

When there comes the time to configure PHP itself, you have to enable FPM. Set all other options at your will.

Put nginx and php-fpm in /etc/rc.conf so they will be startet at boot time.
```bash
$ echo 'nginx_enable="YES"' >> /etc/rc.conf
$ echo 'php_fpm_enable="YES"' >> /etc/rc.conf
```

That's it.

### Install letsencrypt

ngineerx uses [letsencrypt.sh by Lukas Schauer](https://github.com/lukas2511/letsencrypt.sh) as ACME client for certificate creation with letsencrypt. It's bundled so you have to do nothing here. If you used the official python client from letsencrypt, see the [README of letsencrypt.sh](https://github.com/lukas2511/letsencrypt.sh/blob/master/README.md) for learning how to import your settings. You can find the script, the settings and the certificates at ``/usr/local/etc/letsencrypt.sh``.

### Install ngineerx

Now we can install ngineerx.

Clone the git repository to your machine.

```bash
$ git clone https://github.com/chrisb86/ngineerx.git
```

Put everything where it belongs:

```bash
$ cd ngineerx
$ cp -R etc/* /usr/local/etc/
$ cp ngineerx.sh /usr/local/bin/ngineerx
```

Check that all the settings in ``/usr/local/etc/ngineerx/ngineerx.conf`` are as you intend it (especially the server IP).

Bootstrap ngineerx with:

```bash
$ ngineerx install
```

### Create a site

Now you can create your first site with a letsencrypt certificate.

```bash
$ ngineerx create -d example.com -d www.example.com -c letsencrypt
```

That's it. If your DNS records are set up correctly, you should be able to reach https://example.com. To check if PHP is working, open https://example.com/info.php.

#### Flavours

ngineerx is able to use flavours as templates for new sites.

you can find the default flavour at ``/usr/local/etc/ngineerx/flavours/default``. Flavours can contain a special nginx and php template. You also can put files in a subdirectory called ``www`` and put all files that you want to copy to the sites webroot when creating.

If the files ``nginx.server.conf`` or ``php-fpm.pool.conf`` are not found in the flavour directory, the default ones will be used.

### Create just certificates

The command ``cert-create`` creates certificates only and won't create a site in nginx.

```bash
ngineerx cert-create -c selfsigned -d test.example.com
ngineerx cert-create -c letsencrypt -d xmpp.example.com -k /usr/local/etc/prosody/privkey.pem -f /usr/local/etc/prosody/fullchain.pem
```

The first example would create a selfsigned cert for ``test.example.com``. It would be stored in ``/usr/local/etc/ngineerx/certs/test.example.com/`` and won't be linked anywhere.
The second example would create a letsencrypt certificate for ``xmpp.example.com``. We use the options ``-k`` and ``-f`` to link ``privkey.pem`` and ``fullchain.pem`` to ``/usr/local/etc/prosody/``.


### Certificate renewal

You can renew your letsencrypt certificates with
```bash
$ ngineerx cert-renew
```

If you want to automate this process and run the renewal every day at 00:30 put the following in your ``crontab``:

```cron
30 0 * * * /usr/local/bin/ngineerx cert-renew > /dev/null 2>&1
```

