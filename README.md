_This repository contains all necessary files and instructions to perform on-premise installation of Everytrade product_.
# Everytrade Installation

1. Create a droplet at DigitalOcean. Select Ubuntu 20.04 as image. Choose at least 4GB RAM. Choose a password or SSH key (recommended) and give name to your droplet.
1. Go to your terminal and log into your droplet: `ssh root@droplet-ip` with the IP address of the droplet substituted for `droplet-ip`.
1. After you are in your root folder run this instalation command:
    ```shell
    curl -s -O https://raw.githubusercontent.com/everytrade-io/everytrade-install/master/install.sh && bash install.sh
    ```
1. Add your licence key when terminal ask. You received the key to your mailbox. 
1. When the script is finished (it takes few minutes) you can paste your droplet's IP address into your browser. The page will take a some time to load (the application is initializing data). After few more minutes the EveryTrade page will load and subsequent page loads will be almost instant.
1. Application is now up and running but not secured with HTTPS. To setup HTTPS (via https://letsencrypt.org/) follow optional procedure bellow.

### HTTPS setup (optional but recommended / advanced)

1. This guide assumes domain et.example.com. Use your actual domain name throughout the guide instead.
1. Create a DNS type A record pointing to your droplet's IP address at Digital Ocean (or other DNS provider in case you don't use Digital Ocean).
1. In terminal connected to your droplet, edit file `/etc/nginx/sites-enabled/everytrade`. You can use nano editor for example like this: `nano /etc/nginx/sites-enabled/everytrade`. Find line `server_name <droplet-ip-address>` and change it to `server_name et.example.com`. Save the file. Run `sudo nginx -t` to check the file is ok. If so, load the new configuration by running `sudo systemctl reload nginx.service`.
1. In terminal connected to your droplet, run `sudo certbot --nginx -d et.example.com`.
1. In terminal connected to your droplet, edit the file `/var/lib/docker/volumes/everytrade_webapp-data/_data/config/everytrade.properties`:
    1. Find the line starting `mail.from.name=` and change your IP address to your new domain (`et.example.com` in our case).
    1. Do the same for the line starting with `url=`
1. Restart your docker container by running `sudo docker restart everytrade_webapp_1`.
1. Use your browser to load et.example.com. From now on your connection should be secured using an HTTPS certificate from Let's Encrypt (depicted by a lock icon in your browser's address bar).

### Google login setup (optional / advanced)
1. Set up a Google Client ID for your Everytrade installation by using this guide: https://support.google.com/cloud/answer/6158849?hl=en
1. In terminal connected to your droplet, edit the file `/var/lib/docker/volumes/everytrade_webapp-data/_data/config/everytrade.properties`:
    1. Find the line starting `auth.google.clientId=` and insert your Google Client ID from previous step.
1. Restart your docker container by running `sudo docker restart everytrade_webapp_1`.
1. Use your browser to load et.example.com. From now on you should be able to use your Google accounts for signup or login.

# Everytrade upgrade
Upgrading everytrade is easy. All you need to do is to run following script and your installation will be upgraded to the latest version.
There is no need to backup any data.
```shell
curl -s https://raw.githubusercontent.com/everytrade-io/everytrade-install/master/upgrade.sh | bash
```
