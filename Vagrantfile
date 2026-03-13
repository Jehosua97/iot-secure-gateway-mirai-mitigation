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

    # Default NAT interface (enp0s3) is automatically created
    # This gives real Internet access to the gateway.

    fw.vm.provider "virtualbox" do |vb|
      vb.name = "fw-gateway"
      vb.memory = 1024
      vb.cpus = 1
    end

    fw.vm.provision "shell", path: "scripts/provision-fw.sh"
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

    iot.vm.provision "shell", path: "scripts/provision-iot.sh"
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

    atk.vm.provision "shell", path: "scripts/provision-atk.sh"
  end

end
