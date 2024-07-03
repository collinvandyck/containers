#!/usr/bin/env bash

set -euo pipefail

run() {
    addgroup -g 1000 collin
    adduser -D -H -G collin -s /bin/false -u 1000 collin
    (echo $(cat ${SMB_PASSWORD_FILE}); echo $(cat ${SMB_PASSWORD_FILE})) | smbpasswd -s -a collin
    cat /config/supervisord.conf
    chown collin:collin /shared
    chmod u+w /shared
    chmod 775 /shared
    supervisord -c "/config/supervisord.conf"
}

run 2>&1 | tee /entrypoint.log
