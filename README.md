# everytrade installation

1. Create a droplet at digital ocean. Select Ubuntu 20.04. Choose at least 4GB RAM. Choose a password or SSH and give name to your droplet.
2. Go to your terminal and ```ssh root@xxx.xx.xxx.x``` with the IP address of the droplet.
3. After you are in your root folder run this instalation command:

```shell
curl -s -O https://raw.githubusercontent.com/everytrade-io/everytrade-install/master/install.sh && bash install.sh
```
4. Add your licence key when terminal ask. You received the key to your email. 
5. When the script is finished (it takes few minutes) in your browser copy and paste IP address of your droplet. After few more minutes the EveryTrade application will start.

6. Application is now up and running but not secured with HTTPS via https://letsencrypt.org/. To setup HTTPS follow optional procedure bellow.

### HTTPS setup (optional / advanced)

1. We're assuming domain et.example.com
2. In your digital ocean create a DNS A record pointing to your droplet.
3. In your droplet in terminal, edit file /etc/nginx/sites-enabled/everytrade. You can use nano editor for example like this: ```nano /etc/nginx/sites-enabled/everytrade```. Find line "server_name <droplet ip address>" and change it to "server_name et.example.com". Save the file. Run "sudo nginx -t" to check the file is ok. If so, load the new configuration by running "sudo systemctl reload nginx.service".
4. In droplet in terminal, run "sudo certbot --nginx -d et.example.com".
5. In droplet in terminal, edit the file /var/lib/docker/volumes/root_webapp-data/_data/config/everytrade.properties:
  5a. Find the line starting "mail.from.name=" and change your IP address to your new domain (et.example.com in our case).
  5b. Do the same for the line starting with "url="
6. Restart your docker container by running "sudo docker restart root_webapp_1".
7. Copy and paste et.example.com into your browser. From now on you should be using HTTPS certificate.  

# everytrade upgrade

```shell
curl -s -O https://raw.githubusercontent.com/everytrade-io/everytrade-install/master/upgrade.sh && bash upgrade.sh
```
