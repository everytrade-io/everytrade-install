#!/usr/bin/env bash
set -eo pipefail

dockerComposeFile="docker-compose.yml"
dockerComposeFileCommit="3a4899b6f6d2cd487469f3c6b8dc10d84e664b22"
dockerComposeFileSha256="175bcfd2bfc651563781451140946b81bbb5dc1f8f71ba992b1a259e72b4bebf"
if [[ -f "$dockerComposeFile" ]]; then
    >&2 echo "$dockerComposeFile already exists."
    exit 1
fi
if [[ -f /etc/nginx/sites-enabled/everytrade ]]; then 
    >&2 echo "/etc/nginx/sites-enabled/everytrade already exists."
    exit 1
fi
if [[ -f /etc/nginx/sites-available/everytrade ]]; then 
    >&2 echo "/etc/nginx/sites-available/everytrade already exists."
    exit 1
fi
IFS="" read -r -p "Enter license key: " key
if [[ ! "$key" =~ ^[0-9a-zA-Z]{64}$ ]]; then
    >&2 echo "Invalid license key."
    exit 1
fi

host="$1"
if [[ -z "$host" ]]; then
    host=$(ip route get 8.8.8.8 | head -1 | awk '{print $7}')
fi
username="user-${key:0:32}"
password="${key:32:32}"

sudo apt-get update
sudo apt-get -y install docker.io docker-compose nginx certbot python3-certbot-nginx
#sudo usermod -a -G docker "$USER"

curl "https://raw.githubusercontent.com/everytrade-io/everytrade-install/$dockerComposeFileCommit/docker-compose.yml" -o "$dockerComposeFile"
sha256sum "$dockerComposeFile" | grep "$dockerComposeFileSha256"
echo "$password" | sudo docker login -u "$username" --password-stdin registry.everytrade.io
sudo docker-compose pull
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
                gzip_types *;

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
if [[ -f /etc/nginx/sites-enabled/default ]]; then
    sudo rm /etc/nginx/sites-enabled/default
fi
sudo ln -sf /etc/nginx/sites-available/everytrade /etc/nginx/sites-enabled/everytrade
sudo systemctl reload nginx.service

echo
echo
echo "Installation finished successfully."
echo
echo "Application is initializing exchange rate data. In a little while it'll be ready."
echo -e "Open \033[0;33mhttp://$host/\033[0m in your browser to continue."
echo
