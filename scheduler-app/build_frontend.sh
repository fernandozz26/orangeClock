#!/bin/bash
echo "Construyendo frontend desde /scheduler-app..."
if [ -d "/scheduler-app" ]; then
    cd /scheduler-app
    npm run build
    echo "Build generado en /scheduler-app/build"
    
    echo "Copiando build a directorio de despliegue..."
    mkdir -p /home/orangepi/clock_frontend/build
    cp -r /scheduler-app/build/* /home/orangepi/clock_frontend/build/
    echo "Build copiado a /home/orangepi/clock_frontend/build"
else
    echo "Error: /scheduler-app no encontrado"
    exit 1
fi

echo "Instalando Caddy..."
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy

echo "Preparando permisos..."
sudo chmod 755 /home/orangepi
sudo chmod -R 755 /home/orangepi/clock_frontend/build
sudo chown -R caddy:caddy /home/orangepi/clock_frontend/build

echo "Configurando Caddyfile..."
sudo tee /etc/caddy/Caddyfile > /dev/null <<CADDY_EOF
:80 {
    root * /home/orangepi/clock_frontend/build

    handle /api/* {
        reverse_proxy 127.0.0.1:5000
    }

    handle /favicon.ico {
        file_server
    }

    handle {
        try_files {path} /index.html
        file_server {
            hide .git
        }
    }
}
CADDY_EOF

echo "Reiniciando Caddy..."
sudo systemctl restart caddy
sudo systemctl enable caddy

echo "Verificando configuración..."
curl -I http://localhost

echo "Frontend configurado en http://localhost"
