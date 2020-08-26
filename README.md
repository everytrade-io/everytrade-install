# everytrade installation

1. Create a droplet at DigitalOcean. Select Ubuntu 20.04 as image. Choose at least 4GB RAM. Choose a password or SSH key (recommended) and give name to your droplet.
2. Go to your terminal and log into your droplet: `ssh root@<droplet-ip>` with the IP address of the droplet substituted for `<droplet-ip>`.
3. After you are in your root folder run this instalation command:

```shell
curl -s -O https://raw.githubusercontent.com/everytrade-io/everytrade-install/master/install.sh && bash install.sh
```
4. Add your licence key when terminal ask. You received the key to your mailbox. 
5. When the script is finished (it takes few minutes) you can paste your droplet's IP address into your browser. The page will take a some time to load (the application is initializing data). After few more minutes the EveryTrade page will load and subsequent subsequent page loads will be almost instant.
6. Application is now up and running but not secured with HTTPS. To setup HTTPS (via https://letsencrypt.org/) follow optional procedure bellow.

### HTTPS setup (optional / advanced)

1. This guide assumes domain et.example.com. Use your actual domain name throughout the guide instead.
2. Create a DNS type A record pointing to your droplet's IP address at Digital Ocean (or other DNS provider in case you don't use Digital Ocean).
3. In terminal connected to your droplet, edit file `/etc/nginx/sites-enabled/everytrade`. You can use nano editor for example like this: `nano /etc/nginx/sites-enabled/everytrade`. Find line `server_name <droplet-ip-address>` and change it to `server_name et.example.com`. Save the file. Run `sudo nginx -t` to check the file is ok. If so, load the new configuration by running `sudo systemctl reload nginx.service`.
4. In terminal connected to your droplet, run `sudo certbot --nginx -d et.example.com`.
5. In terminal connected to your droplet, edit the file `/var/lib/docker/volumes/root_webapp-data/_data/config/everytrade.properties`:
  5a. Find the line starting `mail.from.name=` and change your IP address to your new domain (`et.example.com` in our case).
  5b. Do the same for the line starting with `url=`
6. Restart your docker container by running `sudo docker restart root_webapp_1`.
7. Use your browser to load et.example.com. From now on your connection should be securew using an HTTPS certificate from Let's Encrypt (depicted by a lock icon in your browser's address bar).

# everytrade upgrade

```shell
curl -s https://raw.githubusercontent.com/everytrade-io/everytrade-install/master/upgrade.sh | bash
```
