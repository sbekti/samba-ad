#!/bin/bash
set -e

# Default variables
: "${REALM:=EXAMPLE.COM}"
: "${DOMAIN:=EXAMPLE}"
: "${ADMIN_PASS:=Pa\$\$w0rd}"
: "${DNS_FORWARDER:=8.8.8.8}"
: "${RPC_PORT_START:=50000}"
: "${RPC_PORT_END:=50010}"
: "${DNS_UPDATE_MODE:=nonsecure and secure}"
: "${NETBIOS_NAME:=DC1}"
: "${EXTERNAL_IP:=127.0.0.1}"

# Set the system hostname to match the NetBIOS name
# This requires CAP_SYS_ADMIN or privileged: true
echo "Setting system hostname to ${NETBIOS_NAME}..."
hostname "${NETBIOS_NAME}"

# External IP Hack
# Ensure the hostname resolves to the External/NodePort IP, not the Pod IP.
if grep -q "${EXTERNAL_IP}" /etc/hosts; then
    echo "Host entry already exists."
else
    echo "Injecting External IP into /etc/hosts..."
    # Map the NetBIOS name and FQDN to the external IP
    echo "${EXTERNAL_IP} ${NETBIOS_NAME}.${REALM} ${NETBIOS_NAME}" >> /etc/hosts
fi

# Check if domain is already provisioned
if [ -f /var/lib/samba/private/secrets.keytab ]; then
    echo "Domain already provisioned."
else
    echo "Provisioning domain..."
    rm -f /etc/samba/smb.conf
    
    samba-tool domain provision \
        --server-role=dc \
        --use-rfc2307 \
        --dns-backend=SAMBA_INTERNAL \
        --realm="${REALM}" \
        --domain="${DOMAIN}" \
        --adminpass="${ADMIN_PASS}" \
        --option="dns forwarder = ${DNS_FORWARDER}" \
        --option="netbios name = ${NETBIOS_NAME}" \
        --option="rpc server port = ${RPC_PORT_START}-${RPC_PORT_END}" \
        --option="allow dns updates = ${DNS_UPDATE_MODE}" \
        --option="ldap server require strong auth = no"
fi

echo "Starting Samba AD DC..."
exec samba -i --no-process-group
