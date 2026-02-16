#!/bin/bash
set -e

# Default variables
: "${REALM:=EXAMPLE.COM}"
: "${DOMAIN:=EXAMPLE}"
: "${ADMIN_PASS:=Change-Me-123}"
: "${DNS_FORWARDER:=8.8.8.8}"
: "${RPC_PORT_START:=50000}"
: "${RPC_PORT_END:=50010}"
: "${DNS_UPDATE_MODE:=nonsecure and secure}"
: "${NETBIOS_NAME:=DC1}"
: "${EXTERNAL_IP:=127.0.0.1}"

# Set the system hostname to match the NetBIOS name
echo "Setting system hostname to ${NETBIOS_NAME}..."
hostname "${NETBIOS_NAME}"

# Clean up /etc/hosts to remove Docker's internal IP entry for the hostname
# This ensures local resolution uses the External IP we inject
if grep -q "${EXTERNAL_IP}" /etc/hosts; then
    echo "Host entry already exists."
else
    echo "Patching /etc/hosts..."
    cp /etc/hosts /etc/hosts.bak
    # Remove lines matching the hostname to clear internal IP mapping
    grep -v -i "[[:space:]]${NETBIOS_NAME}$" /etc/hosts.bak > /etc/hosts.new || true
    # Prepend our External IP mapping
    echo "${EXTERNAL_IP} ${NETBIOS_NAME}.${REALM} ${NETBIOS_NAME}" | cat - /etc/hosts.new > /etc/hosts
    rm /etc/hosts.new
fi

# Check if domain is already provisioned
if [ -f /var/lib/samba/private/secrets.keytab ]; then
    echo "Domain already provisioned."
else
    echo "Provisioning domain..."
    rm -f /etc/samba/smb.conf
    
    # Run provisioning
    # --host-ip: Forces the initial DNS A record to the External IP
    samba-tool domain provision \
        --server-role=dc \
        --use-rfc2307 \
        --dns-backend=SAMBA_INTERNAL \
        --realm="${REALM}" \
        --domain="${DOMAIN}" \
        --adminpass="${ADMIN_PASS}" \
        --host-ip="${EXTERNAL_IP}" \
        --option="dns forwarder = ${DNS_FORWARDER}" \
        --option="netbios name = ${NETBIOS_NAME}" \
        --option="rpc server port = ${RPC_PORT_START}-${RPC_PORT_END}" \
        --option="allow dns updates = ${DNS_UPDATE_MODE}" \
        --option="ldap server require strong auth = no" \
        --option="dns update command = /usr/bin/true"
    
    # "dns update command = /usr/bin/true" prevents samba_dnsupdate from 
    # overwriting our External IP with the Pod IP on scheduled runs.
fi

echo "Starting Samba AD DC..."
exec samba -i --no-process-group
