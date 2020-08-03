#!/usr/bin/env bash
set -exo pipefail

host="$1"
IFS="" read -r -p "Enter license key: " -s key
if [[ ! "$key" =~ ^[0-9a-zA-Z]{64}$ ]]; then
    >&2 echo "Invalid license key."
    exit 1
fi

dockerComposeFile="docker-compose.yml"
dockerComposeFileSha256="0e59080b852118c3392da0ed9eb7f67abdb5885172c4060e9eedc1de9c68957e"
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

curl "https://raw.githubusercontent.com/everytrade-io/everytrade-install/01373871596d0e46d724b960fbadde73a0a79130/docker-compose.yml" -o "$dockerComposeFile"
sha256sum "$dockerComposeFile" | grep "$dockerComposeFileSha256"
sudo docker-compose pull

if [[ -z "$host" ]]; then
    host=$(ip route get 8.8.8.8 | head -1 | awk '{print $7}')
fi
sudo EVERYTRADE_INSTALL_HOST="$host" docker-compose up -d

sudo tee /etc/nginx/sites-available/everytrade > /dev/null <<EOF
limit_req_zone \$binary_remote_addr zone=req_limit_per_ip:10m rate=10r/s;
limit_conn_zone \$binary_remote_addr zone=conn_limit_per_ip:10m;
server {
        listen 80 default_server;
        listen [::]:80 default_server;
        root /var/www/html;

        # Add index.php to the list if you are using PHP
        index index.html index.htm index.nginx-debian.html;

        server_name $host;

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