#!/bin/bash

# ufw allow $SERVER_PORT || :

PORTS_TO_FORWARD=(
  [80]=80
  [443]=443
  # [53]=53
  # [25]=25
  # [143]=143
  # [587]=587
  # [998]=998
  # [4190]=4190
)

#### ROUTING ####

# Enable IP forwarding
sysctl net.ipv4.ip_forward=1

# for KEY in "${!PORTS_TO_FORWARD[@]}"; do iptables -t nat -A PREROUTING -p tcp --dport "$KEY" -j DNAT --to-destination $CLIENT_ADDRESS:"${PORTS_TO_FORWARD[$KEY]}"; iptables -t nat -A POSTROUTING -p tcp -o wg0 -j DNAT --to-destination $SERVER_ADDRESS; done; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# for KEY in "${!PORTS_TO_FORWARD[@]}"; do iptables -t nat -D PREROUTING -p tcp --dport "$KEY" -j DNAT --to-destination $CLIENT_ADDRESS:"${PORTS_TO_FORWARD[$KEY]}"; iptables -t nat -D POSTROUTING -p tcp -o wg0 -j DNAT --to-destination $SERVER_ADDRESS; done; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

for KEY in ${!PORTS_TO_FORWARD[@]}
do
  iptables -t nat -A PREROUTING -p tcp --dport $KEY -j DNAT --to-destination $CLIENT_ADDRESS:${PORTS_TO_FORWARD[$KEY]}
  iptables -t nat -A POSTROUTING -p tcp -o wg0 -j SNAT --to-source $SERVER_ADDRESS
done

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# # Configure firewall rules on the server
# # Track VPN connection
# iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# # Allow incoming VPN traffic on the listening port
# iptables -A INPUT -p udp -m udp --dport $PORT -m conntrack --ctstate NEW -j ACCEPT

# # Allow both TCP and UDP recursive DNS traffic
# iptables -A INPUT -s $NETWORK_ADDRESS/24 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
# iptables -A INPUT -s $NETWORK_ADDRESS/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT

# # Allow forwarding of packets that stay in the VPN tunnel
# iptables -A FORWARD -i wg0 -o wg0 -m conntrack --ctstate NEW -j ACCEPT

# # Set up nat 
# iptables -t nat -A POSTROUTING -s $NETWORK_ADDRESS/24 -o eth0 -j MASQUERADE



# next installs won't work without an apt-get update on a droplet!
apt-get update

# for non-interactive installs
# source: https://gist.github.com/alonisser/a2c19f5362c2091ac1e7
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

# Persist iptable routing across reboots
apt-get install -y iptables-persistent
systemctl enable netfilter-persistent
netfilter-persistent save