# Webserver pro domácí/self-hosting

Testováno na **Debian 13**

Tento projekt poskytuje **automatizovaný skript** pro instalaci Dockeru a vytvoření izolovaného WordPress + MySQL prostředí pro jednu nebo více domén. Součástí je také **backup skript**, který zastaví všechny weby, provede zálohu a opět je spustí.

---

## Co skript dělá

1. **Instalace Dockeru a rsync**
   - Pokud Docker není nainstalován, skript jej automaticky nainstaluje.
   - Přidá aktuálního uživatele do skupiny `docker` (pro spuštění kontejnerů bez `sudo`).
   - Po instalaci Dockeru skript automaticky **restartuje počítač**, aby se změny skupiny projevily.

2. **Vytvoření složek a docker-compose souborů**
   - `services/docker-compose.yaml` – Portainer, Cloudflared a Watchtower. **Nespouští se automaticky.**
   - `websites/<VASE_DOMENA>/docker-compose.yaml` – WordPress + MySQL.

3. **Generování náhodného portu pro WordPress**
   - Port se automaticky vybere z rozsahu `20000–30000`.
   - Slouží pro přístup k WordPressu přes prohlížeč.

4. **Vytvoření sítě `websites`**
   - Skript ověří, zda síť existuje, a pokud ne, vytvoří ji.

5. **Spuštění webu**
   - WordPress a MySQL kontejnery jsou spuštěny pomocí Docker Compose.
   - Po spuštění skript zobrazí URL, na kterém je web dostupný.

---

## Backup skript

Součástí instalace je skript `backup_websites.sh`:

- **Umístění:** `~/docker/backup_websites.sh`
- **Co dělá:**
  1. Zastaví všechny WordPress + MySQL kontejnery ve složce `websites`.
  2. Provádí **zálohu všech webů do `/mnt/backup`**, proto **je nutné připojit externí zálohovací disk k tomuto místu**.
  3. Odstranění zálohy starší než 1 rok - **VOLITELNÉ** (nutno odkomentovat)
  4. Opět spustí všechny weby.

- **Spuštění:**

  ```bash
  ./backup_websites.sh
  ```

* **Poznámky:**

  * Zálohování se provádí jen pokud je disk připojen na `/mnt/backup`.
  * Doporučujeme pravidelně kontrolovat dostupný prostor na zálohovacím disku.

---

## Přidání nového webu

1. Spusť skript znovu.
2. Zadej novou doménu.
3. Skript vygeneruje nový volný port a vytvoří nový docker-compose soubor.
4. Všechny weby sdílejí stejnou Docker síť `websites`.

---

## Služby (services)

Složka `~/docker/services/` obsahuje doplňkové kontejnery, které **nejsou nutné pro běh WordPressu** a **nespouští se automaticky**.  
Jsou volitelné a můžeš je používat podle potřeby.

### Obsažené služby

#### Portainer
Webové rozhraní pro správu Dockeru.

Umožňuje:
- Přehled kontejnerů, sítí, volume
- Spouštění / zastavování kontejnerů
- Zobrazení logů
- Jednoduchou správu Docker prostředí přes web

Po spuštění je dostupný na:

```
https://IP_SERVERU:9443
```

#### Cloudflared

Klient pro Cloudflare Tunnel.

Umožňuje:

- Bezpečné vystavení webu do internetu bez veřejné IP
- Přístup přes Cloudflare doménu
- Ochranu pomocí Cloudflare služeb (WAF, SSL, Zero Trust)

> Pro použití je nutné doplnit vlastní Cloudflare token v `~/docker/services/.env`.

#### Watchtower

Automatická aktualizace Docker kontejnerů.

Umožňuje:

- Pravidelně kontrolovat nové verze image
- Automaticky aktualizovat běžící kontejnery
- Odstraňovat staré image

Díky tomu zůstávají WordPress a další služby aktuální bez manuálního zásahu.

> Doporučení:
>
> * Portainer je vhodný pro pohodlnou správu Dockeru.
> * Watchtower doporučujeme mít spuštěný trvale.
> * Cloudflared používej pouze pokud chceš web vystavit do internetu přes Cloudflare.

### Jak spustit služby

Služby se spouští ručně pomocí Docker Compose:

```bash
docker compose -p services --project-directory ~/docker/services/ up -d
```

### Jak služby zastavit

```bash
docker compose -p services --project-directory ~/docker/services/ down -v
```

---

## Quick Start – stažení a spuštění skriptu

Pokud chceš skript stáhnout přímo do PC a nastavit oprávnění ke spuštění:

```bash
# Stáhnout skript
curl -o setup.sh https://raw.githubusercontent.com/sitarik/public/refs/heads/main/webserver/setup.sh

# Přidělit oprávnění pro spuštění
chmod +x setup.sh

# Spustit skript
./setup.sh
```

> **Poznámka:** Po prvním spuštění a instalaci Dockeru **se počítač autormaticky restartuje**, aby bylo možné spouštět kontejnery bez `sudo`.

---

## Struktura složek a souborů

Po spuštění skriptu se vytvoří následující struktura:

```
~/docker/
├─ services/
│  └─ docker-compose.yaml      # Portainer, Cloudflared a Watchtower
├─ websites/
│  └─ <VASE_DOMENA>/                # složka pro každou doménu
│     ├─ docker-compose.yaml   # WordPress + MySQL
│     ├─ wordpress_data/       # data WordPress
│     └─ mysql_data/           # data MySQL
└─ backup_websites.sh          # skript pro zálohu všech webů
```

### Poznámky:

- `<VASE_DOMENA>` je název domény.
- `backup_websites.sh` provádí zálohu všech webů do `/mnt/backup`. Je nutné ručně připojit externí zálohovací disk.
- Složky `wordpress_data` a `mysql_data` jsou svázány s kontejnery a obsahují všechny data webů a databází.

---

## Kontakt a podpora

Pokud narazíte na chybu nebo budete mít návrh na vylepšení, otevřete **issue** v repozitáři GitHub.
