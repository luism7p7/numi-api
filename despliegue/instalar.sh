#!/usr/bin/env bash
# Despliega (o actualiza) Numi en la VM de Azure: 1 backend (numi-api) + 2 frontends (Vite) + MySQL.
# Uso, en la VM como azureuser:   bash ~/numi/backend/despliegue/instalar.sh
# Requisitos: Docker + Compose, ~/numi/.env (chmod 600), volúmenes numi_mysql_data y numi_uploads
# y el certificado de Let's Encrypt en ~/numi/certbot (se saca solo si falta; necesita el puerto 80 abierto).
set -euo pipefail

DNS=numi-g01.northcentralus.cloudapp.azure.com
BASE="$HOME/numi"
GITHUB=https://github.com/luism7p7

cd "$BASE"
test -f .env || { echo "Falta $BASE/.env"; exit 1; }
chmod 600 .env

echo "== 1. Repositorios (Backend y Frontends desde GitHub por HTTPS)"
clonar() {  # repo  carpeta
  if [ -d "$2/.git" ]; then git -C "$2" pull --ff-only; else git clone "$GITHUB/$1.git" "$2"; fi
}
[ -d repos ] && mv repos "anterior-$(date +%Y%m%d)"   # los 4 repos de la versión anterior
clonar numi-api backend
clonar numi-admin-frontend frontend-admin
clonar numi-docente-frontend frontend-docente

echo "== 2. Variables: la API firma los tokens con SECRET_KEY (se genera sin mostrarla)"
if ! grep -q '^SECRET_KEY=.' .env; then
  printf 'SECRET_KEY=%s\n' "$(python3 -c 'import secrets; print(secrets.token_hex(32))')" >> .env
fi
grep -o '^[A-Z_]*=' .env | tr -d '='

echo "== 3. Volúmenes (los datos de MySQL y los archivos subidos no se pierden)"
docker volume create numi_mysql_data >/dev/null
docker volume create numi_uploads >/dev/null

echo "== 4. Certificado HTTPS (Let's Encrypt)"
mkdir -p certbot/conf certbot/www nginx
if [ ! -f "certbot/conf/live/$DNS/fullchain.pem" ]; then
  docker compose down 2>/dev/null || true   # certbot necesita el puerto 80 libre un momento
  docker run --rm -p 80:80 -v "$BASE/certbot/conf:/etc/letsencrypt" certbot/certbot \
    certonly --standalone -d "$DNS" --agree-tos --register-unsafely-without-email --non-interactive
fi

echo "== 5. Configuración de Compose y Nginx"
D=backend/despliegue
if [ -f compose.yaml ] && ! cmp -s compose.yaml "$D/compose.yaml"; then
  cp compose.yaml "compose.yaml.antes-$(date +%Y%m%d-%H%M%S).bak"
  docker compose down --remove-orphans      # apaga la versión anterior (los volúmenes externos se conservan)
fi
cp "$D/compose.yaml" compose.yaml
cp "$D/nginx/admin.conf" "$D/nginx/docente.conf" nginx/
cp "$D/verificacion_ssh.sh" verificacion_ssh.sh
docker compose config --quiet && echo "Configuración válida"

echo "== 6. Construir e iniciar los contenedores"
docker compose up -d --build --remove-orphans
for i in $(seq 1 30); do docker compose exec -T backend true 2>/dev/null && break; sleep 2; done

echo "== 7. Base de datos: actualizar la estructura sin borrar datos"
docker compose exec -T backend python ../database/init_db.py --migrar

echo "== 8. Validar Nginx de los dos frontends"
docker compose exec -T frontend-admin nginx -t
docker compose exec -T frontend-docente nginx -t

echo "== 9. Renovación automática del certificado (todos los días a las 03:15)"
LINEA="15 3 * * * cd $BASE && docker compose run --rm certbot renew --webroot -w /var/www/certbot --quiet && docker compose exec -T frontend-admin nginx -s reload && docker compose exec -T frontend-docente nginx -s reload"
{ crontab -l 2>/dev/null | grep -v 'certbot renew' || true; echo "$LINEA"; } | crontab -

docker compose ps
echo "Listo: https://$DNS  (administrativo)   https://$DNS:8443  (docente)"
