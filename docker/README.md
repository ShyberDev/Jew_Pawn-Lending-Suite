# Running the suite with Docker (optional / advanced)

> **Status:** these files are written and syntactically correct, but **were not
> executed** in the build environment because Docker is not installed there.
> Treat this as a tested-by-design recipe: the image build is standard, and the
> orchestration uses the maintained [frappe_docker](https://github.com/frappe/frappe_docker)
> project rather than a hand-rolled compose file.

Docker is the easiest way to run the suite on **Windows**, **macOS** or a clean
Linux server without installing Frappe by hand. It uses the official
`frappe/erpnext` image and adds the three suite apps.

---

## What's here

| File | Purpose |
|------|---------|
| `Containerfile` | Builds a custom image = official `frappe/erpnext` + our 3 apps |
| `build.sh` | Convenience wrapper to build that image |

---

## 1. Install Docker

- **Linux:** `curl -fsSL https://get.docker.com | sh` then `sudo usermod -aG docker $USER` (re-login).
- **Windows / macOS:** install **Docker Desktop** (enable WSL2 backend on Windows).

Verify: `docker run --rm hello-world`

---

## 2. Build the suite image

From the **bundle root**:

```bash
cd Jew_Pawn-Lending-Suite
./docker/build.sh
# or explicitly:
# docker build -t shyberdev/jew-pawn-lending:latest -f docker/Containerfile .
```

This produces an image that already contains **ERPNext + jewellery_management +
lending + pawn_shop**.

> The base image only publishes a `develop` tag for Frappe v17, so this image
> tracks upstream `develop`. For byte-exact parity with the pinned commits, use
> the native `./install.sh`.

---

## 3. Run the stack (frappe_docker)

The community-maintained `frappe_docker` project provides the database, redis,
workers and web front-end:

```bash
git clone https://github.com/frappe/frappe_docker
cd frappe_docker

# Point the stack at our custom image
cat > .env <<'EOF'
CUSTOM_IMAGE=shyberdev/jew-pawn-lending
CUSTOM_TAG=latest
PULL_POLICY=missing
DB_PASSWORD=admin
ADMIN_PASSWORD=admin
EOF

# Start MariaDB + Redis + our app image
docker compose \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d
```

---

## 4. Create the site and install the apps

```bash
# create the site (name it library.local to match the docs)
docker compose exec backend bench new-site library.local \
  --mariadb-root-password admin \
  --admin-password admin

# install the suite apps (order matters)
docker compose exec backend bench --site library.local install-app jewellery_management
docker compose exec backend bench --site library.local install-app lending
docker compose exec backend bench --site library.local install-app pawn_shop

docker compose exec backend bench --site library.local set-config developer_mode 1
```

---

## 5. Open it

The front-end listens on **port 8080** by default.

- Add the site name to your hosts file:
  - Linux/macOS: `echo "127.0.0.1 library.local" | sudo tee -a /etc/hosts`
  - Windows (Admin PowerShell): `Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 library.local"`
- Browse to **http://library.local:8080/desk** (or http://localhost:8080 and use
  the site header `library.local`).

Login: `Administrator` / `admin`.

---

## Stop / start

```bash
docker compose down          # stop (keeps data volumes)
docker compose up -d         # start again
docker compose down -v       # DESTROY data (careful)
```

## If you see a grey desk / missing sidebar

That is the known Frappe workspace issue — apply the fix in the main
[`README_FIRST.md`](../README_FIRST.md) §7, then hard-refresh.
