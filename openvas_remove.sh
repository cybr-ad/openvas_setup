#!/bin/bash
# ============================================================
# remove_openvas.sh - Completely purge OpenVAS/Greenbone (GVM)
# from Kali Linux. Use with caution.
# ============================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}⚠️  WARNING: This script will completely remove OpenVAS/Greenbone"
echo -e "and all its data from your system. This action is irreversible.${NC}"
read -p "Are you sure you want to continue? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Aborting."
    exit 0
fi

echo -e "${GREEN}Step 1: Stopping all GVM services...${NC}"
systemctl stop gvmd ospd-openvas gsad 2>/dev/null || true
pkill -f gvmd 2>/dev/null || true
pkill -f ospd-openvas 2>/dev/null || true
pkill -f gsad 2>/dev/null || true
pkill -f redis-server 2>/dev/null || true

echo -e "${GREEN}Step 2: Removing packages...${NC}"
apt remove --purge -y gvm openvas greenbone* ospd* gvmd gsad 2>/dev/null || true
# Optionally remove Redis and PostgreSQL if not used by other services
read -p "Do you also want to remove Redis and PostgreSQL packages? (yes/no): " remove_db
if [[ "$remove_db" == "yes" ]]; then
    apt remove --purge -y redis-server postgresql* 
else
    echo "Skipping removal of Redis and PostgreSQL packages."
fi
apt autoremove --purge -y
apt autoclean
apt clean

echo -e "${GREEN}Step 3: Deleting configuration and data directories...${NC}"
rm -rf /var/lib/gvm /var/lib/openvas
rm -rf /var/log/gvm /var/log/openvas
rm -rf /etc/gvm /etc/openvas
rm -rf /var/cache/gvm /var/cache/openvas
rm -rf /tmp/openvas* /tmp/gvm*

echo -e "${GREEN}Step 4: Dropping PostgreSQL database...${NC}"
if command -v psql &> /dev/null; then
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS gvmd;" 2>/dev/null || true
    sudo -u postgres psql -c "DROP USER IF EXISTS gvm;" 2>/dev/null || true
    if [[ "$remove_db" == "yes" ]]; then
        rm -rf /var/lib/postgresql
    fi
else
    echo "PostgreSQL not found, skipping database drop."
fi

echo -e "${GREEN}Step 5: Removing Redis data...${NC}"
if [[ "$remove_db" != "yes" ]]; then
    # Only delete Redis data if we are not removing the package (to avoid breaking other services)
    rm -rf /var/lib/redis/*
    rm -rf /etc/redis
else
    rm -rf /var/lib/redis /etc/redis
fi

echo -e "${GREEN}Step 6: Removing user and group...${NC}"
userdel -r _gvm 2>/dev/null || true
userdel -r gvm 2>/dev/null || true
groupdel gvm 2>/dev/null || true

echo -e "${GREEN}Step 7: Removing systemd service files...${NC}"
rm -f /etc/systemd/system/gvmd.service /etc/systemd/system/ospd-openvas.service /etc/systemd/system/gsad.service
rm -f /lib/systemd/system/gvmd.service /lib/systemd/system/ospd-openvas.service /lib/systemd/system/gsad.service
systemctl daemon-reload

echo -e "${GREEN}Step 8: Removing user-specific files...${NC}"
rm -rf ~/.gvm ~/.openvas

# Optional: find and remove any leftover files (commented for safety)
# echo -e "${YELLOW}Searching for leftover GVM/OpenVAS files...${NC}"
# find / -name "*gvm*" -o -name "*openvas*" 2>/dev/null | grep -v "^/proc" | grep -v "^/sys" | while read -r file; do
#     echo "Found: $file"
# done

echo -e "${GREEN}Step 9: Verification...${NC}"
if dpkg -l | grep -q -E "gvm|openvas|greenbone"; then
    echo -e "${YELLOW}Some packages may still remain. Please check manually.${NC}"
else
    echo -e "${GREEN}All packages removed.${NC}"
fi

echo -e "${GREEN}✅ Cleanup complete. It is recommended to reboot your system.${NC}"
