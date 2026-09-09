set -eu
# ACA projects the bootstrap file read-only. Bifrost still needs a writable
# application directory even with external stores. No secrets are expanded here.
mkdir -p "$APP_DIR"
cp /mnt/bootstrap/config.json "$APP_DIR/config.json"
exec /app/docker-entrypoint.sh
