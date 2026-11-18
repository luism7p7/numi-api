#!/usr/bin/env bash
# Verificación en vivo por SSH para el video de Numi (sección 4 del enunciado).
# Uso, ya conectado por SSH a la VM:   bash ~/numi/verificacion_ssh.sh
# Cada pantalla ejecuta los comandos en vivo y espera Enter para seguir (SEG=15 avanza solo cada 15 s).
# No muestra contraseñas, claves ni tokens: el .env se lista con los valores tapados.

cd "$HOME/numi" || exit 1
DNS=numi-g01.northcentralus.cloudapp.azure.com
DC="sudo docker compose"
N=0
TOTAL=10

ocultar() { sed -E 's/181\.58\.[0-9]{1,3}\.[0-9]{1,3}/<ip-admin>/g'; }
pantalla() {
  N=$((N + 1)); clear
  printf '\033[1;37;46m  %02d/%02d  \033[0m \033[1;36m%s\033[0m\n' "$N" "$TOTAL" "$1"
}
paso() { printf '\n\033[1;33m# %s\033[0m\n' "$1"; }
cmd() {
  printf '\033[1;32mazureuser@vm-numi-g01\033[0m:\033[1;34m~/numi\033[0m$ %s\n' "$1"
  eval "$1" 2>&1 | ocultar
}
fin() {
  if [ -n "$SEG" ]; then printf '\n\033[2m--- siguiente en %s s ---\033[0m' "$SEG"; sleep "$SEG"
  else printf '\n\033[2m--- Enter para continuar ---\033[0m'; read -r _; fi
}
sql() { $DC exec -T mysql sh -c "MYSQL_PWD=\"\$MYSQL_PASSWORD\" mysql --table --user=\"\$MYSQL_USER\" --database=\"\$MYSQL_DATABASE\" -e \"$1\""; }

# 1 ---------------------------------------------------------------------------
pantalla "Identidad del servidor y del usuario"
paso "¿Quién soy y en qué máquina estoy?"
cmd "whoami && id"
cmd "hostname && grep PRETTY_NAME /etc/os-release"
paso "IP privada de la VM (la pública la tiene Azure en la NIC)"
cmd "ip -4 -brief addr show eth0"
paso "Datos de la VM según el servicio de metadatos de Azure"
cmd "curl -s -H Metadata:true 'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(f\"{k:18} {d[k]}\") for k in (\"name\",\"resourceGroupName\",\"location\",\"vmSize\")]'"
fin

# 2 ---------------------------------------------------------------------------
pantalla "Archivos y código del proyecto"
cmd "ls -la ~/numi"
paso "Secretos: el .env solo lo lee azureuser (600) y aquí se ven solo los nombres"
cmd "ls -l .env && sed -E 's/=.*/=********/' .env"
paso "Backend: una sola API Flask organizada por dominios (controladores, DTOs, servicios, repositorios)"
cmd "ls backend backend/api/app && ls backend/api/app/dominios"
paso "Frontends: dos SPA de Vite (api/, auth/, router/, components/, pages/, utils/)"
cmd "ls frontend-admin frontend-admin/src/js && ls frontend-docente/src/js"
fin

# 3 ---------------------------------------------------------------------------
pantalla "Repositorios Git (Backend y Frontend)"
for r in backend frontend-admin frontend-docente; do
  paso "$r"
  cmd "git -C $r remote get-url origin && git -C $r log -1 --format='%h %ad %s' --date=short && git -C $r status -sb | head -1"
done
fin

# 4 ---------------------------------------------------------------------------
pantalla "Docker y Docker Compose"
cmd "sudo systemctl is-active docker && sudo systemctl is-enabled docker"
cmd "docker --version && docker compose version"
paso "Servicios del compose.yaml y quién publica puertos"
cmd "$DC config --services"
cmd "grep -nE '^  [a-z-]+:$|image:|context:|VITE_API_URL:|- \"[0-9]+:[0-9]+\"|expose:' compose.yaml"
fin

# 5 ---------------------------------------------------------------------------
pantalla "Imágenes y contenedores"
cmd "sudo docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | grep -E 'REPOSITORY|numi|mysql|certbot'"
paso "Estado de la base de datos, el backend y los dos frontends"
cmd "$DC ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
paso "Últimas peticiones que atendió el backend (Gunicorn)"
cmd "$DC logs --tail 4 backend"
fin

# 6 ---------------------------------------------------------------------------
pantalla "Base de datos y almacenamiento persistente"
paso "Conexión a MySQL con el usuario de la app (la clave sale del .env, no se muestra)"
cmd "sql 'SELECT DATABASE() AS base, CURRENT_USER() AS usuario, VERSION() AS version;'"
cmd "sql 'SELECT COUNT(*) AS tablas FROM information_schema.tables WHERE table_schema = DATABASE();'"
cmd "sql 'SELECT rol, estado, COUNT(*) AS cuentas FROM usuarios GROUP BY rol, estado;'"
paso "Volúmenes: los datos sobreviven aunque se borren los contenedores"
cmd "sudo docker volume ls | grep numi"
cmd "sudo docker volume inspect numi_mysql_data --format 'numi_mysql_data -> {{.Mountpoint}}'"
fin

# 7 ---------------------------------------------------------------------------
pantalla "Servidor web y proxy inverso (Nginx de cada frontend + HTTPS)"
cmd "$DC exec -T frontend-admin nginx -t && $DC exec -T frontend-docente nginx -t"
paso "Archivos compilados por Vite que entrega Nginx"
cmd "$DC exec -T frontend-admin ls /usr/share/nginx/html /usr/share/nginx/html/assets"
paso "Qué escucha, qué entrega y a dónde reenvía"
cmd "grep -nE 'listen|server backend|root |location|proxy_pass|try_files|return 301' nginx/admin.conf"
paso "Certificado de Let's Encrypt (solo la parte pública)"
cmd "echo | openssl s_client -connect $DNS:443 -servername $DNS 2>/dev/null | openssl x509 -noout -subject -issuer -enddate"
fin

# 8 ---------------------------------------------------------------------------
pantalla "Comunicación interna entre los servicios"
paso "Puertos abiertos en la VM: SSH y los de Nginx. MySQL (3306) y el backend (5000) no se publican"
cmd "sudo ss -tlnp | awk 'NR==1 || /:(22|80|443|8080|8443|3306|5000) /' | awk '{print \$1, \$4, \$6}' | column -t"
paso "Red interna de Docker"
cmd "sudo docker network inspect numi_default --format '{{range .Containers}}{{.Name}}  {{.IPv4Address}}{{println}}{{end}}'"
paso "Cada frontend llega al backend por su nombre de servicio"
cmd "$DC exec -T frontend-admin wget -qO- http://backend:5000/api/v1/salud; echo"
cmd "$DC exec -T frontend-docente wget -qO- http://backend:5000/api/v1/salud; echo"
paso "El backend llega a MySQL por la red interna"
cmd "$DC exec -T backend python -c \"import socket; socket.create_connection(('mysql', 3306), 3); print('backend -> mysql:3306 OK')\""
fin

# 9 ---------------------------------------------------------------------------
pantalla "Respuestas HTTP de la aplicación y del backend"
paso "HTTP redirige a HTTPS"
cmd "curl -sI http://$DNS/ | grep -iE '^HTTP|^location'"
cmd "curl -sI http://$DNS:8080/ | grep -iE '^HTTP|^location'"
paso "Frontends (SPA) por HTTPS"
cmd "curl -s -o /dev/null -w '%{http_code}  https://$DNS/  (%{content_type})\n' https://$DNS/"
cmd "curl -s -o /dev/null -w '%{http_code}  https://$DNS:8443/  (%{content_type})\n' https://$DNS:8443/"
paso "Backend a través del proxy: salud pública y rutas protegidas con token JWT"
cmd "curl -s https://$DNS/api/v1/salud; echo"
cmd "curl -s -o /dev/null -w '%{http_code}  /api/v1/admin/inicio sin token\n' https://$DNS/api/v1/admin/inicio"
cmd "curl -s https://$DNS:8443/api/v1/docente/me | python3 -m json.tool --no-ensure-ascii"
fin

# 10 --------------------------------------------------------------------------
pantalla "Lo que NO está expuesto"
paso "Desde afuera solo responden 80/443/8080/8443; MySQL (3306) y el backend (5000) no"
for p in 3306 5000; do
  cmd "timeout 4 bash -c '</dev/tcp/$DNS/$p' && echo 'puerto $p ABIERTO' || echo 'puerto $p cerrado desde afuera'"
done
paso "SSH: solo con llave (sin contraseña) y el NSG solo lo deja pasar desde la IP del administrador"
cmd "sudo sshd -T 2>/dev/null | grep -E '^(passwordauthentication|pubkeyauthentication|permitrootlogin) '"
paso "Un token falso no sirve: la API lo rechaza"
cmd "curl -s -o /dev/null -w '%{http_code}  token inventado\n' -H 'Authorization: Bearer abc.def.ghi' https://$DNS/api/v1/admin/inicio"
printf '\n\033[1;32mFin de la verificación.\033[0m\n'
