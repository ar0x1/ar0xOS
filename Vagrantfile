# -*- mode: ruby -*-
# vi: set ft=ruby :
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/Vagrantfile
# -----------------------------------------------------------------------------
# Phase 2 — Vagrant option for building ar0x on a non-Arch host.
#
#   vagrant plugin install vagrant-libvirt      # libvirt provider
#   vagrant up --provider=libvirt
#   vagrant ssh
#   cd /ar0xOS && ./tools/setup-build-env.sh --check
#
# ⚠️ NOTES
#   * rsync synced folder: after editing files on the host, run `vagrant rsync`
#     (or leave `vagrant rsync-auto` running in a second terminal).
#   * A dedicated 60 GiB qcow2 data disk is attached; vagrant/provision.sh
#     formats and mounts it at /opt/ar0x-build. The box's root disk is ~10 GiB
#     and is far too small for mkarchiso's work/ directory.
#   * Nested KVM (host-passthrough + nested=true) is required so Phase 11's
#     QEMU tests are usable. Check on the OUTER host:
#       cat /sys/module/kvm_intel/parameters/nested
# -----------------------------------------------------------------------------

Vagrant.configure("2") do |config|
  config.vm.hostname = "ar0x-build"

  # libvirt is the recommended provider; VirtualBox uses a different box.
  config.vm.box = "archlinux/archlinux"
  config.vm.box_check_update = true

  # Portable synced folder (9p/vboxsf both need provider-specific guest tooling).
  # Excluding build/ avoids syncing 25 GiB of mkarchiso scratch data.
  config.vm.synced_folder ".", "/ar0xOS",
                          type: "rsync",
                          rsync__exclude: [".git/", "build/", "*.iso", "*.pkg.tar.zst"]

  # Do not provision the default /vagrant share.
  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.provision "shell",
                      path: "vagrant/provision.sh",
                      name: "ar0x-build-host",
                      privileged: true

  # --- libvirt provider (recommended) ----------------------------------------
  config.vm.provider "libvirt" do |lv, override|
    override.vm.box = "archlinux/archlinux"
    lv.memory = 12288
    lv.cpus = 8
    lv.cpu_mode = "host-passthrough"
    lv.nested = true
    lv.nic_model_type = "virtio"
    lv.disk_bus = "virtio"
    # Extra data disk -> /opt/ar0x-build (formatted by provision.sh).
    lv.storage :file, size: "60G", type: "qcow2", bus: "virtio"
  end

  # --- VirtualBox provider (fallback) ----------------------------------------
  # Nested virtualization is unreliable here; QEMU tests will be slow TCG runs.
  config.vm.provider "virtualbox" do |vb, override|
    override.vm.box = "generic/arch"
    vb.memory = 12288
    vb.cpus = 8
    vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
    vb.customize ["modifyvm", :id, "--graphicscontroller", "vboxsvga"]
  end
end
