#!/bin/bash
set -euo pipefail

exec > >(tee -a /var/log/user-data.log) 2>&1
echo "=== init started: $(date -Is) ==="

DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
DB_NAME="${db_name}"
DB_HOST="${db_host}"
AWS_REGION="${aws_region}"
S3_BUCKET_NAME="${s3_bucket}"
S3_AVATAR_PREFIX="${s3_prefix}"
USE_S3_STORAGE="${use_s3}"
CW_LOG_GROUP="${cw_log_group}"

REPO_URL="${repo_url}"
REPO_BRANCH="${repo_branch}"
APP_DIR="/home/ubuntu/AWS_grocery"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y ca-certificates curl git gnupg software-properties-common nginx postgresql-client awscli

# Create 2GB swap file
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile swap swap defaults 0 0' >> /etc/fstab

# Verify swap
free -h

# Install Docker
apt-get install -y ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl start docker
systemctl enable docker

# Allow ubuntu to run docker
usermod -aG docker ubuntu

add-apt-repository ppa:deadsnakes/ppa -y
apt-get update -y
apt-get install -y python3.11
curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

echo "Python: $(python3.11 --version)"
echo "Pip: $(python3.11 -m pip --version)"
echo "Node: $(node -v)"
echo "NPM: $(npm -v)"

# Clone/update repo
if [ -d "$APP_DIR/.git" ]; then
  cd "$APP_DIR"
  git fetch --all
  git checkout "$REPO_BRANCH"
  git pull
else
  rm -rf "$APP_DIR"
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$APP_DIR"
fi
chown -R ubuntu:ubuntu "$APP_DIR"

if [ "$USE_S3_STORAGE" = "true" ]; then
  DEFAULT_AVATAR_LOCAL="$APP_DIR/backend/avatar/user_default.png"
  if [ -f "$DEFAULT_AVATAR_LOCAL" ]; then
    aws s3 cp "$DEFAULT_AVATAR_LOCAL" "s3://$S3_BUCKET_NAME/$S3_AVATAR_PREFIX/user_default.png" --region "$AWS_REGION"
    echo "Default avatar uploaded to s3://$S3_BUCKET_NAME/$S3_AVATAR_PREFIX/user_default.png"
  else
    echo "WARN: Default avatar not found at $DEFAULT_AVATAR_LOCAL"
  fi
fi

# Backend setup with Docker
if [ -f "$APP_DIR/backend/Dockerfile" ]; then
  docker build -t grocery-backend -f "$APP_DIR/backend/Dockerfile" "$APP_DIR/backend"
elif [ -f "$APP_DIR/Dockerfile" ]; then
  docker build -t grocery-backend -f "$APP_DIR/Dockerfile" "$APP_DIR"
else
  echo "ERROR: No Dockerfile found in $APP_DIR/backend or $APP_DIR" >&2
  exit 1
fi

JWT_SECRET="$(python3.11 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)"

# Start backend container
# Docker awslogs driver schreibt Container-Logs direkt nach CloudWatch.
docker run -d --name grocery-backend \
  -p 5000:5000 \
  -e JWT_SECRET_KEY="$JWT_SECRET" \
  -e POSTGRES_USER="$DB_USER" \
  -e POSTGRES_PASSWORD="$DB_PASSWORD" \
  -e POSTGRES_DB="$DB_NAME" \
  -e POSTGRES_HOST="$DB_HOST" \
  -e POSTGRES_URI="postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME" \
  -e USE_S3_STORAGE="$USE_S3_STORAGE" \
  -e S3_BUCKET_NAME="$S3_BUCKET_NAME" \
  -e S3_REGION="$AWS_REGION" \
  -e S3_AVATAR_PREFIX="$S3_AVATAR_PREFIX" \
  --log-driver=awslogs \
  --log-opt awslogs-region="$AWS_REGION" \
  --log-opt awslogs-group="$CW_LOG_GROUP" \
  --log-opt awslogs-stream="backend" \
  grocery-backend

# Wait for DB (max 5 minutes)
echo "Waiting for DB $DB_HOST:5432 ..."
for i in {1..60}; do
  PGPASSWORD="$DB_PASSWORD" pg_isready -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1 && break
  echo "Waiting for DB... ($i/60)"
  sleep 5
done
PGPASSWORD="$DB_PASSWORD" pg_isready -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1 \
  || { echo "ERROR: DB not reachable. Check RDS SG allows 5432 from EC2 SG." >&2; exit 1; }

# Import dump once
MARKER="/var/lib/aws_grocery_dump_imported"
DUMP_FILE="$APP_DIR/backend/app/sqlite_dump_clean.sql"
if [ -f "$DUMP_FILE" ] && [ ! -f "$MARKER" ]; then
  echo "Importing dump (one-time)..."
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$DUMP_FILE"
  touch "$MARKER"
fi

# Frontend build
cd "$APP_DIR/frontend"
if [ -f package-lock.json ]; then
  sudo -u ubuntu npm ci
else
  sudo -u ubuntu npm install
fi
export NODE_OPTIONS="--max-old-space-size=2048"
sudo -u ubuntu npm run build

rm -rf /var/www/html/*
cp -r build/* /var/www/html/

# Nginx reverse proxy for backend (optional but usually needed)
cat > /etc/nginx/sites-available/default <<'EOF'
server {
  listen 80 default_server;
  listen [::]:80 default_server;

  root /var/www/html;
  index index.html;

  location / {
    try_files $uri $uri/ /index.html;
  }

  location /api/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
}
EOF

nginx -t
systemctl enable --now nginx

echo "=== init finished: $(date -Is) ==="
docker ps || true
systemctl --no-pager status nginx || true
