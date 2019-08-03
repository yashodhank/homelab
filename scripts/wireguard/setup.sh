#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "You need to run this script as root"
    exit 1
fi

HOME="/root"
: ${PORT:=1194}
: ${INSTALL_SCRIPT_PATH:="$HOME/wireguard/install.sh"}

##### INSTALL #####

if [ -f $INSTALL_SCRIPT_PATH ]; then
  source $INSTALL_SCRIPT_PATH
fi

if ! [ -x "$(command -v wg)" ]; then
  echo 'Error: WireGuard is not installed.' >&2
  exit 1
fi

##### SETUP #####

# Detect public IPv4 address
SERVER_PUB_IPV4=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
# SERVER_PUB_IPV4=$(dig +short myip.opendns.com @resolver1.opendns.com)
# CLIENT_PUB_IPV4=$(printf $SSH_CLIENT | awk '{ print $1}')
# TODO: parse ipv6 addr if available
# SERVER_PUB_IPV6=$(ip -6 addr)
SERVER_PUB_IP=$SERVER_PUB_IPV4

# Detect public interface and pre-fill for the user
SERVER_PUB_NIC="$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)"
SERVER_WG_NIC="wg0"

#### ADDRESSES ####

get_ipv4_address () {
  echo "10.0.0.$1"
}

get_ipv6_address () {
  echo "fd42:42:42::$1"
}

# NETWORK_ADDR_IPV4=$(get_ipv4_address 0)
# NETWORK_ADDR_IPV6=$(get_ipv6_address 0)

SERVER_WG_IPV4=$(get_ipv4_address 1)
SERVER_WG_IPV6=$(get_ipv6_address 1)


CLIENT_WG_IPV4=$(get_ipv4_address 2)
CLIENT_WG_IPV6=$(get_ipv6_address 2)

MOBILE_WG_IPV4=$(get_ipv4_address 3)
MOBILE_WG_IPV6=$(get_ipv6_address 3)

# Non-routable address https://en.wikipedia.org/wiki/0.0.0.0
# Represents routing all traffic to WireGuard server endpoint
INADDR_ANY_IPV4="0.0.0.0"
INADDR_ANY_IPV6="::"

# Adguard DNS

# Use $PORT declared (or default) or declared value for precision
: ${SERVER_PORT:=$PORT}

CLIENT_PERSISTENT_KEEPALIVE=25

CLIENT_DNS_1="176.103.130.130"
CLIENT_DNS_2="176.103.130.131"

if [[ $SERVER_PUB_IP =~ .*:.* ]]
then
  echo "IPv6 Detected"
  SERVER_ENDPOINT="[$SERVER_PUB_IP]:$SERVER_PORT"
else
  echo "IPv4 Detected"
  SERVER_ENDPOINT="$SERVER_PUB_IP:$SERVER_PORT"
fi

CLIENT_CONFIG_PATH="$HOME/wireguard/$SERVER_WG_NIC-client.conf"
MOBILE_CONFIG_PATH="$HOME/wireguard/$SERVER_WG_NIC-mobile.conf"

# Make sure the directory exists (this does not seem the be the case on fedora)
mkdir /etc/wireguard > /dev/null 2>&1

# Generate key pair for the server
SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | wg pubkey)

# Generate key pair for the server
CLIENT_PRIV_KEY=$(wg genkey)
CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)

# Generate key pair for the server
MOBILE_PRIV_KEY=$(wg genkey)
MOBILE_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)

# Add server configuration
cat <<EOT > /etc/wireguard/$SERVER_WG_NIC.conf
[Interface]
Address = $SERVER_WG_IPV4/24,$SERVER_WG_IPV6/64
ListenPort = $SERVER_PORT
PrivateKey = $SERVER_PRIV_KEY
PostUp = iptables -t nat -A POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE; ip6tables -t nat -A POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE; ip6tables -t nat -D POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE

[Peer]
PublicKey = $CLIENT_PUB_KEY
AllowedIPs = $CLIENT_WG_IPV4/32,$CLIENT_WG_IPV6/128" >> "/etc/wireguard/$SERVER_WG_NIC.conf"

[Peer]
PublicKey = $MOBILE_PUB_KEY
AllowedIPs = $CLIENT_WG_IPV4/32,$CLIENT_WG_IPV6/128" >> "/etc/wireguard/$SERVER_WG_NIC.conf"
EOT

# Add client configuration
cat <<EOT > $CLIENT_CONFIG_PATH
[Interface]
PrivateKey = $CLIENT_PRIV_KEY
Address = $CLIENT_WG_IPV4/24,$CLIENT_WG_IPV6/64
DNS = $CLIENT_DNS_1,$CLIENT_DNS_2

[Peer]
PublicKey = $SERVER_PUB_KEY
Endpoint = $SERVER_ENDPOINT
AllowedIPs = $SERVER_WG_IPV4/32,$SERVER_WG_IPV6/128
PersistentKeepalive = $CLIENT_PERSISTENT_KEEPALIVE
EOT

# Add mobile configuration
cat <<EOT > $MOBILE_CONFIG_PATH
[Interface]
PrivateKey = $MOBILE_PRIV_KEY
Address = $MOBILE_WG_IPV4/24,$MOBILE_WG_IPV6/64
DNS = $CLIENT_DNS_1,$CLIENT_DNS_2

[Peer]
PublicKey = $SERVER_PUB_KEY
Endpoint = $SERVER_ENDPOINT
AllowedIPs = $INADDR_ANY_IPV4/0,$INADDR_ANY_IPV6/0
EOT

chmod 600 -R /etc/wireguard/

##### ROUTING #####

# Enable routing on the server
cat <<EOT > /etc/sysctl.d/wg.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOT

sysctl --system

systemctl start "wg-quick@$SERVER_WG_NIC"
systemctl enable "wg-quick@$SERVER_WG_NIC"

##### GENERATE QR CODE FOR MOBILE CONFIGURATIONM #####

MOBILE_QR_SCRIPT_PATH=${3:-$HOME/wireguard/mobile_qr.sh}

if [ -f $MOBILE_QR_SCRIPT_PATH ]; then
  MOBILE_CONFIG_PATH=$MOBILE_CONFIG_PATH source $MOBILE_QR_SCRIPT_PATH
fi