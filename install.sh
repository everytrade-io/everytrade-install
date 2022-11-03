#!/usr/bin/env bash
set -eo pipefail

while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
        --host)
            host="$2"
            shift # past argument
            shift # past value
        ;;
        --image)
            image="$2"
            shift # past argument
            shift # past value
        ;;
        --version)
            version="$2"
            shift # past argument
            shift # past value
        ;;
    esac
done

if [[ -z "$host" ]]; then
    host=$(ip route get 8.8.8.8 | head -1 | awk '{print $7}')
fi

if [[ -z "$image" ]]; then
    image="everytrade-webapp"
fi

dockerComposeFile="docker-compose.yml"
dockerComposeFileCommit="master"
#dockerComposeFileSha256="f789db6d327d0664e452cca266fb197d3d6baa3d4c5899ef5b2d78af2b052052"
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

username="user-${key:0:32}"
password="${key:32:32}"

sudo apt-get update
sudo apt-get -y install docker.io docker-compose nginx certbot python3-certbot-nginx
#sudo usermod -a -G docker "$USER"

PG_PASSWORD_DIR=/run/secrets
PG_PASSWORD_FILE=${PG_PASSWORD_DIR}/pg
function check_password() {
  if [ ! -f "${PG_PASSWORD_FILE}" ]; then
    echo "!!! Be sure to make backup of your database password. We have no way how to get to your data without your password !!!"
    echo "Please enter your new database password:"
    read -s -r PASSWORD
    mkdir -p ${PG_PASSWORD_DIR}
    touch ${PG_PASSWORD_FILE}
    echo "${PASSWORD}" >${PG_PASSWORD_FILE}
  else
    echo "Using existing password from ${PG_PASSWORD_FILE}"
  fi

  touch .env
  echo "POSTGRES_PASSWORD=$(cat $PG_PASSWORD_FILE)" >.env
}

curl "https://raw.githubusercontent.com/everytrade-io/everytrade-install/$dockerComposeFileCommit/docker-compose.yml" | \
  (
      if [[ -z "$version" ]]; then
          sed -e "s/^\(\s*image: registry\.everytrade\.io\/\)everytrade-webapp:\(.*\)$/\1$image:\2/"
      else
          sed -e "s/^\(\s*image: registry\.everytrade\.io\/\)everytrade-webapp:\(.*\)$/\1$image:$version/"
      fi
  ) > "$dockerComposeFile"
#sha256sum "$dockerComposeFile" | grep "$dockerComposeFileSha256"
echo "$password" | sudo docker login -u "$username" --password-stdin registry.everytrade.io
sudo docker-compose -p everytrade pull
check_password
sudo EVERYTRADE_INSTALL_HOST="$host" docker-compose -p everytrade up -d

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

        add_header X-Frame-Options DENY always;

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
rm .env docker-compose.yml

echo
echo
echo "Installation finished successfully."
echo
echo "Application is initializing exchange rate data. In a little while it'll be ready."
echo -e "Open \033[0;33mhttp://$host/\033[0m in your browser to continue."
echo
