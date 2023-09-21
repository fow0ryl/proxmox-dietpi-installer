#!/bin/bash

# use defined temporary directory to avoid storing files everywhere around in filesystem
mkdir -p /tmp/dietpi
cd /tmp/dietpi

# Variables
IMAGE_URL=$(whiptail --inputbox 'Enter the URL for the DietPi image (default: https://dietpi.com/downloads/images/DietPi_Proxmox-x86_64-Bullseye.7z):' 8 78 'https://dietpi.com/downloads/images/DietPi_Proxmox-x86_64-Bullseye.7z' --title 'DietPi Installation' 3>&1 1>&2 2>&3)
RAM=$(whiptail --inputbox 'Enter the amount of RAM (in MB) for the new virtual machine (default: 2048):' 8 78 2048 --title 'DietPi Installation' 3>&1 1>&2 2>&3)
CORES=$(whiptail --inputbox 'Enter the number of cores for the new virtual machine (default: 2):' 8 78 2 --title 'DietPi Installation' 3>&1 1>&2 2>&3)

# Install p7zip if missing
dpkg-query -s p7zip &> /dev/null || { echo 'Installing p7zip for DietPi archive extraction'; apt-get update; apt-get -y install p7zip; }

# Get the next available VMID
ID=$(pvesh get /cluster/nextid)

touch "/etc/pve/qemu-server/$ID.conf"

# put all active storage names into an array
storage_Names=($(pvesm status | grep active | tr -s ' ' | cut -d ' ' -f1))

# get corresponding storage types into another array
storage_Types=($(pvesm status | grep active | tr -s ' ' | cut -d ' ' -f2))

# lets find how many names are in our array
storage_Count=${#storage_Names[@]}

# create a new arry suitable for use with whiptail radiobuttons
storage_Array=()
I=1
for STORAGE in "${storage_Names[@]}"; do
  storage_Array+=("$I" ":: $STORAGE " "off")
  I=$(( I + 1 ))
done

# lets choose a storage name by user
choice=""
while [ "$choice" == "" ]
do
  choice=$(whiptail --title "DietPi Installation" --radiolist "Select Storage Pool" 20 50 $storage_Count "${storage_Array[@]}" 3>&1 1>&2 2>&3 )
done
choice=$(( choice - 1 ))

# get name of choosen storage (element of array)
STORAGE=${storage_Names[$choice]}

# get corresponding type of choosen storage
FSType=${storage_Types[$choice]}

# echo 'Choice: '$choice'<-'
# echo 'Storage:: '$STORAGE'<-'
# echo 'FSType: ' $FSType'<-'

# prepare disk-parm depending on storage type
if [ "$FSType" = "btrfs" ]; then
   qm_disk_param="$STORAGE:$ID/vm-$ID-disk-0.raw"
elif [ "$FSType" = "dir" ]; then
   qm_disk_param="$STORAGE:$ID/vm-$ID-disk-0.raw"
elif [ "$FSType" = "zfspool" ]; then
   qm_disk_param="$STORAGE:vm-$ID-disk-0"
else
   qm_disk_param="$STORAGE/vm-$ID-disk-0"
fi

# echo 'QM Disk Parm: '$qm_disk_parm

# Download image, only if not found, or changeed on server
wget -N "$IMAGE_URL"

# Extract the image, if not yet done
if [ ! -f "$IMAGE_NAME.qcow2" ]; then
   IMAGE_NAME=${IMAGE_URL##*/}
   IMAGE_NAME=${IMAGE_NAME%.7z}
   7zr e "$IMAGE_NAME.7z" "$IMAGE_NAME.qcow2"
   sleep 3
fi

# import the qcow2 file to choosen virtual machine storage
qm importdisk "$ID" "$IMAGE_NAME.qcow2" "$STORAGE"

# modify vm settings
qm set "$ID" --name 'dietpi' >/dev/null
qm set "$ID" --description '### [DietPi Website](https://dietpi.com/)'
qm set "$ID" --cores "$CORES"
qm set "$ID" --memory "$RAM"
qm set "$ID" --net0 'virtio,bridge=vmbr0'
qm set "$ID" --scsihw virtio-scsi-pci
qm set "$ID" --scsi0 "$qm_disk_param"
qm set "$ID" --boot order='scsi0'
### [DietPi Docs](https://dietpi.com/docs/)  
### [DietPi Forum](https://dietpi.com/forum/)
### [DietPi Blog](https://dietpi.com/blog/)' >/dev/null

# Tell user the virtual machine is created  
echo "VM $ID Created."

# Start the virtual machine
qm start "$ID"
