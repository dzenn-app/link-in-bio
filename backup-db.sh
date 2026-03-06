#!/bin/bash

# === 1. DEFINISI PATH (Wajib untuk Cron) ===
DOCKER="/usr/bin/docker"
RCLONE="/usr/bin/rclone"
CURL="/usr/bin/curl"
GZIP="/usr/bin/gzip"
NICE="/usr/bin/nice"
IONICE="/usr/bin/ionice"
DU="/usr/bin/du"
FIND="/usr/bin/find"

# === 2. LOAD CONFIGURATION ===
ENV_FILE="/root/dzenn/.env"
if [ -f "$ENV_FILE" ]; then
    # Menggunakan 'source' agar variabel terbaca dengan benar oleh script
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "❌ Error: File .env tidak ditemukan di $ENV_FILE"
    exit 1
fi

# === 3. MAPPING VARIABLES ===
# Pastikan nama variabel ini sesuai dengan di file .env kamu
DB_USER=${DB_USER:-"dzenn"}
DB_NAME=${DB_NAME:-"dzenn_db"}
DB_PASSWORD=${DB_PASSWORD:-$POSTGRES_PASSWORD}
CONTAINER_NAME="dzenn-postgres"
RCLONE_REMOTE="s3-backup:brokarim-link-bio/backups"
BACKUP_DIR="/root/backups"

# Format Nama File
DATE=$(date +%Y-%m-%d_%H-%M-%S)
FILENAME="backup_${DB_NAME}_${DATE}.sql.gz"
LOCAL_PATH="$BACKUP_DIR/$FILENAME"

mkdir -p "$BACKUP_DIR"

# === 4. NOTIFICATION FUNCTION ===
send_notification() {
    local color=$1
    local status=$2
    local msg=$3
    if [ ! -z "$DISCORD_WEBHOOK" ]; then
        $CURL -H "Content-Type: application/json" -X POST -d "{
            \"embeds\": [{
                \"title\": \"Database Backup $status\",
                \"description\": \"$msg\",
                \"color\": $color,
                \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
            }]
        }" "$DISCORD_WEBHOOK"
    fi
}

echo "�� Starting backup for $DB_NAME..."

# === 5. DUMP & COMPRESS ===
# Proses dumping langsung di-pipe ke gzip agar hemat disk VPS
if $NICE -n 19 $IONICE -c 3 $DOCKER exec -i -e PGPASSWORD="$DB_PASSWORD" "$CONTAINER_NAME" pg_dump -U "$DB_USER" "$DB_NAME" | $GZIP > "$LOCAL_PATH"; then
    SIZE=$($DU -h "$LOCAL_PATH" | cut -f1)
    echo "✅ Backup lokal sukses: $SIZE"
    
    # === 6. UPLOAD TO S3 (RCLONE) ===
    echo "☁️ Moving file to S3..."
    if $RCLONE move "$LOCAL_PATH" "$RCLONE_REMOTE" --s3-no-check-bucket; then
        echo "🎉 Sukses upload dan hapus file lokal."
        send_notification 3066993 "SUCCESS" "Database **$DB_NAME** berhasil di-backup ke S3.\nSize: **$SIZE**"
    else
        echo "❌ Gagal upload ke S3!"
        send_notification 15158332 "FAILURE" "Backup lokal sukses ($SIZE), tapi **GAGAL UPLOAD** ke S3."
    fi
else
    echo "❌ Gagal melakukan pg_dump!"
    rm -f "$LOCAL_PATH"
    send_notification 15158332 "FAILURE" "Proses \`pg_dump\` gagal. Periksa koneksi database!"
    exit 1
fi

# === 7. CLEANUP ===
# Hapus sisa backup di folder lokal yang lebih dari 7 hari (jika ada yang gagal ter-upload)
$FIND "$BACKUP_DIR" -type f -name "*.sql.gz" -mtime +7 -delete
