#!/bin/bash

echo "=== Configurando Frontend Orange Clock ==="

# Verificar si Node.js está instalado
if ! command -v node &> /dev/null; then
    echo "Instalando Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
else
    echo "Node.js ya está instalado: $(node --version)"
fi

# Verificar si npm está disponible
if ! command -v npm &> /dev/null; then
    echo "ERROR: npm no está disponible"
    exit 1
fi

# Crear directorio del frontend si no existe
FRONTEND_DIR="/home/orangepi/clock_frontend"
if [ ! -d "$FRONTEND_DIR" ]; then
    echo "Creando directorio del frontend..."
    mkdir -p $FRONTEND_DIR
    sudo chown -R orangepi:orangepi $FRONTEND_DIR
fi

cd $FRONTEND_DIR

# Inicializar proyecto React si no existe package.json
if [ ! -f "package.json" ]; then
    echo "Inicializando proyecto React..."
    npx create-react-app . --template typescript
else
    echo "Proyecto React ya existe"
fi

# Instalar dependencias adicionales
echo "Instalando dependencias..."
npm install axios react-router-dom @types/node

# Crear archivo de servicio para el frontend
echo "Creando servicio del frontend..."
sudo tee /etc/systemd/system/clock_frontend.service > /dev/null <<EOF
[Unit]
Description=Orange Clock Frontend
After=network.target
Wants=network.target

[Service]
Type=simple
User=orangepi
Group=orangepi
WorkingDirectory=/home/orangepi/clock_frontend
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=3000
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Configurar servicio
echo "Configurando servicio del frontend..."
sudo systemctl daemon-reload
sudo systemctl enable clock_frontend.service

# Crear script de construcción para producción
echo "Creando script de build..."
cat > build_frontend.sh << 'EOF'
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
EOF

chmod +x build_frontend.sh

echo ""
echo "=== Configuración completada ==="
echo "Directorio: $FRONTEND_DIR"
echo "Para desarrollo: sudo systemctl start clock_frontend.service"
echo "Para producción: ./build_frontend.sh"
echo "Frontend estará en: http://localhost:3000 (desarrollo) o http://localhost (producción con Caddy)"