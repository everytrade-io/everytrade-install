#!/usr/bin/env bash
set -exo pipefail

IFS="" read -r -p "Enter license key: " -s key
if [[ ! "$key" =~ ^[0-9a-zA-Z]{64}$ ]]; then
    >&2 echo "Invalid license key."
    exit 1
fi

dockerComposeFile="docker-compose.yml"
dockerComposeFileSha256="52a131107cb93e20491566277514d8bce017b807ca0ba27ebfeef54a68fbf1eb"
if [[ -f "$dockerComposeFile" ]]; then
    >&2 echo "$dockerComposeFile already exists."
    exit 2
fi

username="user-${key:0:32}"
password="${key:32:32}"

sudo apt-get update
sudo apt-get -y install docker.io docker-compose nginx certbot python3-certbot-nginx
#sudo usermod -a -G docker "$USER"
echo "$password" | sudo docker login -u "$username" --password-stdin registry.everytrade.io
curl "https://raw.githubusercontent.com/everytrade-io/everytrade-install/7a45bf7e1b585af3cca8dcbf89061752958aabbf/docker-compose.yml" -o "$dockerComposeFile"
sha256sum "$dockerComposeFile" | grep "$dockerComposeFileSha256"
sudo docker-compose pull
sudo docker-compose up -d

sudo tee /etc/nginx/sites-available/everytrade > /dev/null <<'EOF'
limit_req_zone $binary_remote_addr zone=req_limit_per_ip:10m rate=10r/s;
limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;
server {
        listen 80 default_server;
        listen [::]:80 default_server;
        root /var/www/html;

        # Add index.php to the list if you are using PHP
        index index.html index.htm index.nginx-debian.html;

        server_name _;

        location / {
                include /etc/nginx/proxy_params;
                proxy_pass http://localhost:8080;

                limit_req zone=req_limit_per_ip burst=60 nodelay;
                limit_conn conn_limit_per_ip 60;
                client_max_body_size 50m;
                proxy_connect_timeout 300;
                proxy_send_timeout 300;
                proxy_read_timeout 300;
                send_timeout 300;
        }
}
EOF
sudo rm /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/everytrade /etc/nginx/sites-enabled/everytrade
sudo systemctl reload nginx.service