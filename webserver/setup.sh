#!/usr/bin/env bash

set -euo pipefail

GREEN='\e[0;92m'
RED='\e[0;91m'
NC='\e[0m'

log() {
        echo -e "${GREEN}$1${NC}"
}

# ----------------------------------------------------------------------
# Instalace potřebných programů
# ----------------------------------------------------------------------

# === Instalace rsync ===
if ! command -v rsync >/dev/null 2>&1; then
	log "\nSpouštím instalaci rsync..."
	sudo apt-get install rsync -y
fi

# === Instalace Dockeru ===
# (https://docs.docker.com/engine/install/debian/)
if ! command -v docker >/dev/null 2>&1; then
	log "\nSpouštím instalaci Dockeru..."
	sleep 1

	# Uninstall old versions
	sudo apt-get remove $(dpkg --get-selections docker.io docker-compose docker-doc podman-docker containerd runc | cut -f1)

	# Add Docker's official GPG key:
	sudo apt-get update
	sudo apt-get install ca-certificates curl -y
	sudo install -m 0755 -d /etc/apt/keyrings
	sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
	sudo chmod a+r /etc/apt/keyrings/docker.asc

	# Add the repository to Apt sources:
	sudo tee /etc/apt/sources.list.d/docker.sources <<-EOF
	Types: deb
	URIs: https://download.docker.com/linux/debian
	Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
	Components: stable
	Signed-By: /etc/apt/keyrings/docker.asc
	EOF

	sudo apt-get update

	# Install Docker Engine
	sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

	# Add your user to the docker group
	REAL_USER=$(logname 2>/dev/null || echo "$SUDO_USER")
	sudo usermod -aG docker "$REAL_USER"
	

	log "\nHotovo. Instalace Dockeru je kompletní."
	log "Restartujte počítač. Po restartu spusťte skript znovu.\n"
	
    	sleep 3
fi


# ----------------------------------------------------------------------
# Proměnné
# ----------------------------------------------------------------------

# === Název domény ===
while true; do
	log "\nZadejte název vaší domény (např. domena.cz):"
	read -r DOMENA

	# === Validace domény ===
	if [[ "$DOMENA" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        	break
   	else
        	echo -e "\e[0;91mNeplatný název domény. Povolené znaky: a-z, A-Z, 0-9, tečka a pomlčka.\e[0m"
    	fi
done

DB_NAME=$(echo "$DOMENA" | tr -cd '[:alnum:]_' | tr '[:upper:]' '[:lower:]')
PROJECT_NAME="${DB_NAME}"

# === Heslo pro databázi ===
# Délka hesla
PASS_LENGTH=25

# Generování bezpečného hesla obsahujícího malá, velká písmena a čísla
HESLO=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c $PASS_LENGTH)

# Zobrazit uživateli
# log "\nBylo vygenerováno bezpečné heslo pro databázi:\n$HESLO\n"
# sleep 2

# === Vygenerování čísla portu ===
generate_port() {
  while :; do
    PORT=$(shuf -i 20000-30000 -n 1)
    if ! ss -ltnH | awk '{print $4}' | grep -q ":$PORT$"; then
      echo "$PORT"
      return
    fi
  done
}

PORT=$(generate_port)


# ----------------------------------------------------------------------
# Vytvoření adresářů
# ----------------------------------------------------------------------

USER_HOME=$(eval echo ~$USER)

SERVICES_DIR="$USER_HOME/docker/services"
WEBSITES_DIR="$USER_HOME/docker/websites/$PROJECT_NAME"

if [ ! -d "$SERVICES_DIR" ]; then
    mkdir -p "$SERVICES_DIR"
fi

if [ ! -d "$WEBSITES_DIR" ]; then
    mkdir -p "$WEBSITES_DIR"
    log "\nByl vytvořen adresář $WEBSITES_DIR.\n"
else
    log "\nProjekt $DOMENA již zřejmě existuje."
    exit 1
fi


# ----------------------------------------------------------------------
# Vytvoření souborů
# ----------------------------------------------------------------------

# === SERVICES ===
if [ ! -f "$SERVICES_DIR/.env" ]; then
cat > "$SERVICES_DIR/.env" <<EOF
TOKEN=zadej_vlastni_cloudflared_token
EOF

chmod 600 "$SERVICES_DIR/.env"
fi

if [ ! -f "$SERVICES_DIR/docker-compose.yaml" ]; then
cat > "$SERVICES_DIR/docker-compose.yaml" <<EOF
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    ports:
      - 9443:9443
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./portainer_data:/data

  # cloudflared:
  #   image: cloudflare/cloudflared:latest
  #   container_name: cloudflared
  #   command: tunnel --no-autoupdate run --token \${TOKEN}
  #   restart: always

  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: always
    environment:
      WATCHTOWER_CLEANUP: "true"
      WATCHTOWER_INCLUDE_STOPPED: "true"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
EOF
fi

# === WEBSITES ===
if [ ! -f "$WEBSITES_DIR/.env" ]; then
cat > "$WEBSITES_DIR/.env" <<EOF
DB_NAME=$DB_NAME
DB_PASSWORD=$HESLO
PORT=$PORT
EOF

chmod 600 "$WEBSITES_DIR/.env"
fi

if [ ! -f "$WEBSITES_DIR/docker-compose.yaml" ]; then
cat > "$WEBSITES_DIR/docker-compose.yaml" <<EOF
services:
  wordpress:
    image: wordpress:latest
    restart: always
    ports:
      - \${PORT}:80
    environment:
      WORDPRESS_DB_HOST: mysql
      WORDPRESS_DB_USER: sysadmin
      WORDPRESS_DB_PASSWORD: \${DB_PASSWORD}
      WORDPRESS_DB_NAME: \${DB_NAME}
    volumes:
      - ./wordpress_data:/var/www/html
    networks:
      - websites

  mysql:
    image: mysql:8
    restart: always
    environment:
      MYSQL_DATABASE: \${DB_NAME}
      MYSQL_USER: sysadmin
      MYSQL_PASSWORD: \${DB_PASSWORD}
      MYSQL_RANDOM_ROOT_PASSWORD: '1'
    volumes:
      - ./mysql_data:/var/lib/mysql
    networks:
      - websites

networks:
  websites:
    external: true
EOF
fi

# === WEBSITES BACKUP ===
if [ ! -f "$USER_HOME/docker/backup_websites.sh" ]; then
cat > "$USER_HOME/docker/backup_websites.sh" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

GREEN='\e[0;92m'
RED='\e[0;91m'
NC='\e[0m'

DNES=$(date +"%Y-%m-%d")
BKPSRC="$HOME/docker/websites"
BKPDST="/mnt/backup"

log() {
        echo -e "${GREEN}$1${NC}"
}


# Zastavení webů

log "\nZastavuji všechny weby"

for dir in "$HOME"/docker/websites/*; do
  if [ -f "$dir/docker-compose.yaml" ]; then
    name=$(basename "$dir")
    echo "Zastavuji $name"
    sudo docker compose -p "$name" --project-directory "$dir" down -v
  fi
done

log "\nWeby zastaveny.\n"

sleep 1


# Provedení zálohy

if mountpoint -q "$BKPDST"; then
#if [ -d "$BKPDST" ]; then
        log "\nZálohovací disk nalezen, spouštím zálohu..."
        sudo mkdir -p "$BKPDST"/websites_"$DNES"
        sudo rsync -ah --numeric-ids --info=progress2 "$BKPSRC"/ "$BKPDST"/websites_"$DNES"/
        log "\nZáloha dokončena.\n"
        sleep 1
else
        log "${RED}Zálohovací disk není připojen na $BKPDST.${NC}"
fi


# Odstranění záloh starších než 1 rok (365 dní)
# log "Mazání záloh starších než 1 rok..."
# sudo find "$BKPDST"/ -maxdepth 1 -type d -name "websites_*" -mtime +365 -exec rm -rf {} \;
# log "Hotovo."
# sleep 1

# Doporučení: Nejprve doporučuji vyzkoušet bez -exec rm -rf, abys viděl, co by bylo smazáno:
# sudo find "$BKPDST"/ -maxdepth 1 -type d -name "websites_*" -mtime +365

	# -maxdepth 1 - jen první úroveň (nezahrnuje podsložky)
	# -type d - hledá pouze složky
	# -name "websites_*" - jen složky začínající na websites_
	# -mtime +365 - změněné před více než 365 dny (tedy starší než rok)
	# -exec rm -rf {} \; - smaže nalezené složky


# Spuštění webů

log "\nSpouštím všechny weby"

for dir in "$HOME"/docker/websites/*; do
  if [ -f "$dir/docker-compose.yaml" ]; then
    name=$(basename "$dir")
    echo "Spouštím $name"
    sudo docker compose -p "$name" --project-directory "$dir" up -d
  fi
done

log "\nHotovo. Weby zálohovány a spuštěny.\n"

sleep 2
EOF

chmod +x $USER_HOME/docker/backup_websites.sh
fi


# ----------------------------------------------------------------------
# Vytvoření sítě 
# ----------------------------------------------------------------------

log "\nVytvařím síť websites."
docker network inspect websites >/dev/null 2>&1 || \
docker network create --driver bridge --subnet=172.20.0.0/24 websites


# ----------------------------------------------------------------------
# Spuštění webu
# ----------------------------------------------------------------------

log "\nSpouštím web $DOMENA"
docker compose -p "$PROJECT_NAME" --project-directory "$USER_HOME"/docker/websites/"$PROJECT_NAME"/ up -d


# ----------------------------------------------------------------------
# Zobrazení informací
# ----------------------------------------------------------------------

SERVER_IP=$(hostname -I | awk '{print $1}')

log "\nWeb je dostupný na: http://$SERVER_IP:$PORT\n"

sleep 2
