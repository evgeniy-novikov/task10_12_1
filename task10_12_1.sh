#!/bin/bash

dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $dir
source "$dir/config"
MAC=52:54:00:`(date; cat /proc/interrupts) | md5sum | sed -r 's/^(.{6}).*$/\1/; s/([0-9a-f]{2})/\1:/g; s/:$//;'`
mkdir -p $dir/networks
mkdir -p $dir/config-drives/$VM1_NAME-config
mkdir -p $dir/config-drives/$VM2_NAME-config

############################ NETWORKS ################################
#External
echo "<network>
  <name>${EXTERNAL_NET_NAME}</name>
  <forward mode='nat'/>
  <ip address='${EXTERNAL_NET_HOST_IP}' netmask='${EXTERNAL_NET_MASK}'>
    <dhcp>
      <range start='${EXTERNAL_NET}.2' end='${EXTERNAL_NET}.254'/>
      <host mac='${MAC}' name='${VM1_NAME}' ip='${VM1_EXTERNAL_IP}'/>
    </dhcp>
  </ip>
</network>" > $dir/networks/external.xml

#Inaternal
echo "<network>
  <name>${INTERNAL_NET_NAME}</name>
#  <ip address='$INTERNAL_NET_IP' netmask='$INTERNAL_NET_MASK'/>
</network>" > $dir/networks/internal.xml

#Management
echo "<network>
  <name>${MANAGEMENT_NET_NAME}</name>
  <ip address='${MANAGEMENT_HOST_IP}' netmask='${MANAGEMENT_NET_MASK}'/>
</network>" > $dir/networks/management.xml

# Create networks from XML templates

virsh net-define networks/external.xml
virsh net-define networks/internal.xml
virsh net-define networks/management.xml

# Start networks

virsh net-start external
virsh net-start internal
virsh net-start management

##################################################################################

IMG_DESTINATION="/var/lib/libvirt/images/ubunut-server-16.04.qcow2"
IMG_SOURCE_URL="https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img"
wget -O "$IMG_DESTINATION" "$IMG_SOURCE_URL"

echo "Create meta-data for VMs"
envsubst < templates/meta-data_VM1_template > config-drives/vm1-config/meta-data
envsubst < templates/meta-data_VM2_template > config-drives/vm2-config/meta-data

echo "Create user-data for VM1"
envsubst < templates/user-data_VM1_template > config-drives/vm1-config/user-data
cat <<EOT >> config-drives/vm1-config/user-data
ssh_authorized_keys:
 - $(cat $SSH_PUB_KEY)
EOT

echo "Create user-data for VM2"
envsubst < templates/user-data_VM2_template > config-drives/vm2-config/user-data
cat <<EOT >> config-drives/vm2-config/user-data
ssh_authorized_keys:
 - $(cat $SSH_PUB_KEY)
EOT

echo "Create VM1.xml and VM2.xml from template"
#envsubst < templates/vm1_template.xml > vm1.xml
#envsubst < templates/vm2_template.xml > vm2.xml

echo "<domain type='kvm'>
  <name>vm1</name>
  <memory unit='MiB'>${VM1_MB_RAM}</memory>
  <vcpu placement='static'>${VM1_NUM_CPU}</vcpu>
  <os>
    <type>${VM_TYPE}</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='${VM1_HDD}'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='${VM1_CONFIG_ISO}'/>
      <target dev='hdc' bus='ide'/>
      <readonly/>
    </disk>
    <interface type='network'>
      <mac address='$MAC'/>
      <source network='${EXTERNAL_NET_NAME}'/>
      <model type='virtio'/>
    </interface>
    <interface type='network'>
      <source network='${INTERNAL_NET_NAME}'/>
      <model type='virtio'/>
      <protocol family='ipv4'>
      <ip address='192.168.124.101' prefix='24'/>
      <route gateway='192.168.124.1'/>
      </protocol>
    </interface>
    <interface type='network'>
      <source network='${MANAGEMENT_NET_NAME}'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'>
      <source path='/dev/pts/0'/>
      <target port='0'/>
    </serial>
    <console type='pty' tty='/dev/pts/0'>
      <source path='/dev/pts/0'/>
      <target type='serial' port='0'/>
    </console>
    <graphics type='vnc' port='-1' autoport='yes'/>
  </devices>
</domain>" > $dir/vm1.xml


echo "<domain type='kvm'>
  <name>${VM2_NAME}</name>
  <memory unit='MiB'>${VM2_MB_RAM}</memory>
  <vcpu placement='static'>${VM2_NUM_CPU}</vcpu>
  <os>
    <type>${VM_TYPE}</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='${VM2_HDD}'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='${VM2_CONFIG_ISO}'/>
      <target dev='hdc' bus='ide'/>
      <readonly/>
    </disk>
    <interface type='network'>
      <source network='${INTERNAL_NET_NAME}'/>
      <model type='virtio'/>
        <protocol family='ipv4'>
        <ip address='192.168.124.102' prefix='24'/>
        <route gateway='192.168.124.1'/>
        </protocol>
    </interface>
    <interface type='network'>
      <source network='${MANAGEMENT_NET_NAME}'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'>
      <source path='/dev/pts/0'/>
      <target port='0'/>
    </serial>
    <console type='pty' tty='/dev/pts/0'>
      <source path='/dev/pts/0'/>
      <target type='serial' port='0'/>
    </console>
    <graphics type='vnc' port='-1' autoport='yes'/>
  </devices>
</domain>" > $dir/vm2.xml


echo "Create config drives"

mkdir -p $(dirname "$VM1_HDD")
mkdir -p $(dirname "$VM2_HDD")

cp $IMG_DESTINATION $VM1_HDD
cp $IMG_DESTINATION $VM2_HDD

mkisofs -o "$VM1_CONFIG_ISO" -V cidata -r -J --quiet $dir/config-drives/vm1-config
mkisofs -o "$VM2_CONFIG_ISO" -V cidata -r -J --quiet $dir/config-drives/vm2-config

echo "Define VMs from XML templates"
virsh define vm1.xml
virsh define vm2.xml

echo "Start VMs"
virsh start vm1
virsh start vm2



