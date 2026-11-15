#!/usr/bin/env bash
set -Eeuo pipefail
MODULE_INSTALL_STARTED=0
# Issabel 5 - Official Operator Panel installer
# Installs https://github.com/Ehsan-Movahedi/panel-issabel5
# Tested design target: Issabel 5 / Rocky Linux 8

REPO_URL="https://github.com/Ehsan-Movahedi/panel-issabel5.git"
MODULE_NAME="control_panel"
MODULES_DIR="/var/www/html/modules"
MODULE_DIR="${MODULES_DIR}/${MODULE_NAME}"
ACL_DB="/var/www/db/acl.db"
MENU_DB="/var/www/db/menu.db"
BACKUP_ROOT="/root/backup-panel-issabel5"
TMP_ROOT=""
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}"

log()  { printf '\n[INFO] %s\n' "$*"; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }
die() {
    printf '\n[ERROR] %s\n' "$*" >&2
    restore_on_error 1
}

cleanup() {
    if [[ -n "${TMP_ROOT}" && -d "${TMP_ROOT}" ]]; then
        rm -rf -- "${TMP_ROOT}"
    fi

    if [[ -n "${STAGED_MODULE:-}" && -d "${STAGED_MODULE}" ]]; then
        rm -rf -- "${STAGED_MODULE}"
    fi
}
restore_on_error() {
    local rc="${1:-$?}"

    if (( rc != 0 )); then
        if [[ -d "${BACKUP_DIR}/module-before-install" ]]; then
            warn "Installation failed; preserving failed module and restoring previous version."

            if [[ -e "${MODULE_DIR}" ]]; then
                mv "${MODULE_DIR}" "${BACKUP_DIR}/module-failed" || true
            fi

            if [[ ! -e "${MODULE_DIR}" ]]; then
                mv "${BACKUP_DIR}/module-before-install" "${MODULE_DIR}" || true
            fi

        elif [[ "${MODULE_INSTALL_STARTED:-0}" == "1" && -e "${MODULE_DIR}" ]]; then
            warn "Installation failed; removing the newly installed module."
            mv "${MODULE_DIR}" "${BACKUP_DIR}/module-failed" || true
        fi

        warn "Installation stopped. Backups: ${BACKUP_DIR}"
    fi

    exit "$rc"
}
trap cleanup EXIT
trap restore_on_error ERR

[[ "${EUID}" -eq 0 ]] || die "Run this installer as root."
[[ -d "${MODULES_DIR}" ]] || die "Issabel modules directory not found: ${MODULES_DIR}"
[[ -f "${ACL_DB}" ]] || die "ACL database not found: ${ACL_DB}"
[[ -f "${MENU_DB}" ]] || die "Menu database not found: ${MENU_DB}"

for cmd in git sqlite3 php cp mv install date chown grep find mktemp rm; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
done

sqlite3 "${ACL_DB}" "SELECT 1;" >/dev/null || die "Cannot read ACL database."
sqlite3 "${MENU_DB}" "SELECT 1;" >/dev/null || die "Cannot read menu database."

# Verify expected Issabel database structures before changing anything.
for table in acl_resource acl_group acl_action acl_group_permission; do
    sqlite3 "${ACL_DB}" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='${table}';" | grep -qx 1 \
        || die "Expected ACL table is missing: ${table}"
done
for table in menu; do
    sqlite3 "${MENU_DB}" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='${table}';" | grep -qx 1 \
        || die "Expected menu table is missing: ${table}"
done

ADMIN_ID="$(sqlite3 "${ACL_DB}" "SELECT id FROM acl_group WHERE lower(name)='administrator' LIMIT 1;")"
ACCESS_ACTION_ID="$(sqlite3 "${ACL_DB}" "SELECT id FROM acl_action WHERE lower(name)='access' LIMIT 1;")"
PARENT_MENU_ID="$(sqlite3 "${MENU_DB}" "SELECT id FROM menu WHERE id='pbxconfig' LIMIT 1;")"

[[ -n "${ADMIN_ID}" ]] || die "Administrator group was not found in acl_group."
[[ -n "${ACCESS_ACTION_ID}" ]] || die "The 'access' action was not found in acl_action."
[[ -n "${PARENT_MENU_ID}" ]] || die "The PBX Configuration parent menu (pbxconfig) was not found."

log "Creating timestamped backups in ${BACKUP_DIR}"
install -d -m 0700 "${BACKUP_DIR}"
sqlite3 "${ACL_DB}" ".backup '${BACKUP_DIR}/acl.db'"
sqlite3 "${MENU_DB}" ".backup '${BACKUP_DIR}/menu.db'"

TMP_ROOT="$(mktemp -d /tmp/issabel-panel-install.XXXXXX)"
log "Downloading the official Issabel panel repository"
git clone --depth 1 "${REPO_URL}" "${TMP_ROOT}/source" >/dev/null
[[ -d "${TMP_ROOT}/source/control_panel" ]] || die "Repository does not contain control_panel/."

# Validate PHP syntax before replacing an existing installation.
while IFS= read -r -d '' file; do
    php -l "$file" >/dev/null || die "PHP syntax validation failed: $file"
done < <(find "${TMP_ROOT}/source/control_panel" -type f -name '*.php' -print0)

STAGED_MODULE="${MODULES_DIR}/${MODULE_NAME}.new-${STAMP}"
cp -a "${TMP_ROOT}/source/control_panel" "${STAGED_MODULE}"
chown -R asterisk:asterisk "${STAGED_MODULE}"

if command -v restorecon >/dev/null 2>&1; then
    restorecon -RF "${STAGED_MODULE}" >/dev/null 2>&1 || true
fi

# Preserve an existing module before installing/upgrading.
if [[ -e "${MODULE_DIR}" ]]; then
    log "Existing module found; preserving it in the backup directory"
    mv "${MODULE_DIR}" "${BACKUP_DIR}/module-before-install"
fi

MODULE_INSTALL_STARTED=1
mv "${STAGED_MODULE}" "${MODULE_DIR}"
chown -R asterisk:asterisk "${MODULE_DIR}"
if command -v restorecon >/dev/null 2>&1; then
    restorecon -RF "${MODULE_DIR}" >/dev/null 2>&1 || true
fi

log "Registering the module, menu entry, and Administrator access"

# Values are resolved from the actual database; no numeric IDs are hard-coded.
sqlite3 "${ACL_DB}" <<SQL
.timeout 10000
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;

INSERT INTO acl_resource (name, description)
SELECT '${MODULE_NAME}', 'Issabel Panel'
WHERE NOT EXISTS (
    SELECT 1 FROM acl_resource WHERE name='${MODULE_NAME}'
);

INSERT INTO acl_group_permission (id_action, id_group, id_resource)
SELECT
    (SELECT id FROM acl_action WHERE lower(name)='access' LIMIT 1),
    (SELECT id FROM acl_group WHERE lower(name)='administrator' LIMIT 1),
    (SELECT id FROM acl_resource WHERE name='${MODULE_NAME}' LIMIT 1)
WHERE NOT EXISTS (
    SELECT 1
    FROM acl_group_permission gp
    JOIN acl_action a ON a.id=gp.id_action
    JOIN acl_group g ON g.id=gp.id_group
    JOIN acl_resource r ON r.id=gp.id_resource
    WHERE lower(a.name)='access'
      AND lower(g.name)='administrator'
      AND r.name='${MODULE_NAME}'
);

COMMIT;
SQL

sqlite3 "${MENU_DB}" <<SQL
.timeout 10000
BEGIN IMMEDIATE;
INSERT INTO menu (id, IdParent, Link, Name, Type, order_no)
SELECT '${MODULE_NAME}', 'pbxconfig', '', 'Issabel Panel', 'module', 8
WHERE NOT EXISTS (SELECT 1 FROM menu WHERE id='${MODULE_NAME}');
COMMIT;
SQL

# Verify all three registration/permission records.
RESOURCE_ID="$(sqlite3 "${ACL_DB}" "SELECT id FROM acl_resource WHERE name='${MODULE_NAME}' LIMIT 1;")"
PERMISSION_COUNT="$(sqlite3 "${ACL_DB}" "
SELECT COUNT(*)
FROM acl_group_permission gp
JOIN acl_action a ON a.id=gp.id_action
JOIN acl_group g ON g.id=gp.id_group
JOIN acl_resource r ON r.id=gp.id_resource
WHERE lower(a.name)='access'
  AND lower(g.name)='administrator'
  AND r.name='${MODULE_NAME}';")"
MENU_COUNT="$(sqlite3 "${MENU_DB}" "SELECT COUNT(*) FROM menu WHERE id='${MODULE_NAME}' AND IdParent='pbxconfig';")"

[[ -n "${RESOURCE_ID}" ]] || die "Module resource registration could not be verified."
[[ "${PERMISSION_COUNT}" == "1" ]] || die "Administrator access permission verification failed."
[[ "${MENU_COUNT}" == "1" ]] || die "PBX menu registration verification failed."
[[ -f "${MODULE_DIR}/index.php" ]] || die "Installed module index.php is missing."

log "Installation completed successfully."
printf '  Module directory : %s\n' "${MODULE_DIR}"
printf '  ACL resource ID  : %s\n' "${RESOURCE_ID}"
printf '  Administrator ID : %s\n' "${ADMIN_ID}"
printf '  Access action ID : %s\n' "${ACCESS_ACTION_ID}"
printf '  Backup directory : %s\n' "${BACKUP_DIR}"
printf '\n[INFO] No Asterisk, Apache, or PHP-FPM restart was performed.\n'
printf '[INFO] Sign out/in to the Issabel web interface if the menu does not appear immediately.\n'
