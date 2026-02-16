# IoT Secure Gateway - 3 VM Lab (Attacker Outside)

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.ssh.insert_key = false

  # Networks:
  # IoT LAN:        10.20.0.0/24
  # WAN Simulated:  192.168.56.0/24

  # ===============================
  # VM1 - Firewall / Gateway
  # ===============================
  config.vm.define "fw" do |fw|
    fw.vm.hostname = "fw-gateway"

    # IoT LAN interface
    fw.vm.network "private_network", ip: "10.20.0.1"

    # WAN simulated (external attacker network)
    fw.vm.network "private_network", ip: "192.168.56.2"

    # Default NAT interface (eth0) is automatically created
    # This gives real Internet access to the gateway.

    fw.vm.provider "virtualbox" do |vb|
      vb.name = "fw-gateway"
      vb.memory = 1024
      vb.cpus = 1
    end

    fw.vm.provision "shell", inline: <<-SHELL
      set -eux

      apt-get update -y
      apt-get install -y nftables tcpdump

      # Enable IP forwarding
      echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ipforward.conf
      sysctl -p /etc/sysctl.d/99-ipforward.conf

      # Configure nftables
      cat <<'EOF' > /etc/nftables.conf
      flush ruleset

      define IOT_NET = 10.20.0.0/24
      define WAN_SIM_NET = 192.168.56.0/24

      define WAN_IF = "eth0"   # NAT to real internet
      define IOT_IF = "eth1"   # IoT LAN
      define EXT_IF = "eth2"   # Simulated WAN (attacker)

      table inet filter {
        chain input {
          type filter hook input priority 0;
          policy drop;

          iif lo accept
          ct state established,related accept

          # Allow ping from lab networks
          iif $IOT_IF icmp type echo-request accept
          iif $EXT_IF icmp type echo-request accept

          # Allow SSH to firewall from WAN simulated only
          iif $EXT_IF ip saddr $WAN_SIM_NET tcp dport 22 accept
        }

        chain forward {
          type filter hook forward priority 0;
          policy drop;

          ct state established,related accept

          # BLOCK any traffic from outside -> IoT (Mirai mitigation)
          iif $EXT_IF oif $IOT_IF drop

          # Allow IoT -> Internet only for required services
          iif $IOT_IF oif $WAN_IF udp dport {53,123} accept
          iif $IOT_IF oif $WAN_IF tcp dport {443} accept
        }
      }

      table ip nat {
        chain postrouting {
          type nat hook postrouting priority 100;
          oif $WAN_IF ip saddr $IOT_NET masquerade
        }
      }
      EOF

      systemctl enable nftables
      systemctl restart nftables

      nft list ruleset
    SHELL
  end


  # ===============================
  # VM2 - IoT Device (Internal)
  # ===============================
  config.vm.define "iot" do |iot|
    iot.vm.hostname = "iot-device"
    iot.vm.network "private_network", ip: "10.20.0.10"

    iot.vm.provider "virtualbox" do |vb|
      vb.name = "iot-device"
      vb.memory = 768
      vb.cpus = 1
    end

    iot.vm.provision "shell", inline: <<-SHELL
      set -eux
      apt-get update -y
      apt-get install -y curl dnsutils netcat-traditional

      # Route through firewall
      ip route replace default via 10.20.0.1 dev eth1 || true

      echo "IoT VM ready."
      echo "Test: curl https://example.com"
    SHELL
  end


  # ===============================
  # VM3 - Attacker (External)
  # ===============================
  config.vm.define "atk" do |atk|
    atk.vm.hostname = "attacker-outside"
    atk.vm.network "private_network", ip: "192.168.56.10"

    atk.vm.provider "virtualbox" do |vb|
      vb.name = "attacker-outside"
      vb.memory = 1024
      vb.cpus = 1
    end

    atk.vm.provision "shell", inline: <<-SHELL
      set -eux
      apt-get update -y
      apt-get install -y nmap netcat-traditional

      # Optional route through firewall simulated WAN
      ip route replace default via 192.168.56.2 dev eth1 || true

      echo "Attacker VM ready."
      echo "Test: nmap -p 22,23,2323 10.20.0.10"
    SHELL
  end

end
