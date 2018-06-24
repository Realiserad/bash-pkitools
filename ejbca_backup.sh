#!/bin/bash

#################################################################
###                                                           ###
###              EJBCA Backup Script for MariaDB              ###
###                                                           ###
#################################################################

# This script relies on Percona XtraBackup, and this package must
# be installed before making any backups. Also, if this script is
# executed by any other user than root, make sure this user is in
# the mysql group. You should also prepare a MariaDB user used for
# backing up data only. This user can be created as follows:
# mysql> CREATE USER 'backup'@'localhost' IDENTIFIED BY 'foo123';
# mysql> GRANT RELOAD, LOCK TABLES, REPLICATION CLIENT ON *.* TO 'backup'@'localhost';
# mysql> FLUSH PRIVILEGES;

# Location of the MariaDB configuration file with the username
# and passphrase for the backup user. This file should have the
# following contents:
# [client]
# user=backup
# password=foo123
#
# [mysqld]
# datadir=/var/lib/mysql
MYSQL_CNF='/opt/wildfly-10.1.0.Final/backup/mysql_backup.cnf'

# Backup directory, will be created if it does not exist. Can be
# mapped to e.g. an NFS share.
BACKUP_DIR='/var/opt/backups'

# The passphrase used to protect the backup, clear this variable
# to make the script ask for the passphrase.
PWD=

# Additional options passed to Percona XtraBackup. See this page
# for reference: https://goo.gl/EEgq4d
#XTRA_OPTIONS='--galera-info'

################################################################

if [ ! -f "$MYSQL_CNF" ]; then
  echo "The MySQL configuration file $MYSQL_CNF does not exist."
  exit 1
fi

# The user running this script must be in the wheel group, unless
# the script is running as root
if [ "$UID" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

if [ "$(id -u)" != "0" ]; then
  echo "Root access denied."
  exit 1
fi

# The MariaDB database files are only readable by the mysql user
# by default, make sure everyone in the mysql group can read them
chmod -R g=u /var/lib/mysql

if [ -z "$PWD" ]; then
  read -s -p 'Backup password: ' PWD
  echo ""
  read -s -p 'Repeat backup password: ' PWD2
  echo ""
  if [ "$PWD" != "$PWD2"  ]; then
    echo "Passwords do not match."
    exit 1
  fi
fi

# Create the backup directory if it does not already exist
if [ ! -d "$BACKUP_DIR" ]; then
  mkdir -p "$BACKUP_DIR"
fi

DATE=$(date '+%Y%m%d%H%M%S')
HOSTNAME=$(hostname)
BACKUP_NAME="xb_ejbca_${HOSTNAME}_${DATE}"
BACKUP_FILES_DIR_TMP="/tmp/$BACKUP_NAME"
ENC_KEY_PASS_FILE="/tmp/$BACKUP_NAME.pass"

# Write the backup encryption password to a temporary file, only
# readable by the current user. Writing the password to disk is
# not optimal, but we need to conceal it from ps.
echo -n "$PWD" > "$ENC_KEY_PASS_FILE"
chmod 600 "$ENC_KEY_PASS_FILE"

# Create the backup in the temporary backup files directory e.g.
# /tmp/xb_ejbca_hostname_20180101133700
innobackupex --defaults-extra-file="$MYSQL_CNF" \
  --no-timestamp \
  "$BACKUP_FILES_DIR_TMP"

innobackupex --apply-log \
  "$BACKUP_FILES_DIR_TMP"

echo 'Compressing and encrypting backup... (this may take some time)'

cd "$BACKUP_FILES_DIR_TMP"
tar cz * | \
  openssl enc -aes-256-cbc -pass "file:$ENC_KEY_PASS_FILE" -e \
  > "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz.enc"

rm -r "$ENC_KEY_PASS_FILE"
rm -rf "$BACKUP_FILES_DIR_TMP"
