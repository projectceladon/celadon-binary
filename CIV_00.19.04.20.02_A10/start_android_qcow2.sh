#!/bin/bash

work_dir=$PWD
caas_image=$work_dir/android.qcow2

ovmf_file="./OVMF.fd"
[ ! -f $ovmf_file ] && ovmf_file="/usr/share/qemu/OVMF.fd"

GVTg_DEV_PATH="/sys/bus/pci/devices/0000:00:02.0"
GVTg_VGPU_UUID="4ec1ff92-81d7-11e9-aed4-5bf6a9a2bb0a"
function setup_vgpu(){
	res=0
	if [ ! -d $GVTg_DEV_PATH/$GVTg_VGPU_UUID ]; then
		echo "Creating VGPU..."
		sudo sh -c "echo $GVTg_VGPU_UUID > $GVTg_DEV_PATH/mdev_supported_types/i915-GVTg_V5_8/create"
		res=$?
	fi
	return $res
}

common_options="\
 -m 2048 -smp 2 -M q35 \
 -name caas-vm \
 -enable-kvm \
 -vga none \
 -display gtk,gl=on \
 -k en-us \
 -machine kernel_irqchip=off \
 -global PIIX4_PM.disable_s3=1 -global PIIX4_PM.disable_s4=1 \
 -cpu host \
 -device qemu-xhci,id=xhci,addr=0x8 \
 -device usb-host,vendorid=0x046d,productid=0x082d \
 -device usb-host,vendorid=0x046d,productid=0x085c \
 -device usb-host,vendorid=0x03eb,productid=0x8a6e \
 -device usb-host,vendorid=0x0eef,productid=0x7200 \
 -device usb-host,vendorid=0x222a,productid=0x0141 \
 -device usb-host,vendorid=0x222a,productid=0x0088 \
 -device usb-host,vendorid=0x8087,productid=0x0a2b \
 -device usb-mouse \
 -device usb-kbd \
 -drive file=$ovmf_file,format=raw,if=pflash \
 -chardev socket,id=charserial0,path=./kernel-console,server,nowait \
 -device isa-serial,chardev=charserial0,id=serial0 \
 -device intel-hda -device hda-duplex \
 -drive file=$caas_image,if=none,id=disk1 \
 -device virtio-blk-pci,drive=disk1,bootindex=1 \
 -device e1000,netdev=net0 \
 -netdev user,id=net0,hostfwd=tcp::5555-:5555 \
 -device intel-iommu,device-iotlb=off \
 -full-screen \
 -nodefaults
"

function launch_hwrender(){
	qemu-system-x86_64 \
	  -device vfio-pci,sysfsdev=$GVTg_DEV_PATH/$GVTg_VGPU_UUID,display=on,x-igd-opregion=on \
	  $common_options
}

function launch_swrender(){
	qemu-system-x86_64 \
	  -device qxl-vga,xres=1280,yres=720 \
	  $common_options
}

function check_nested_vt(){
	nested=$(cat /sys/module/kvm_intel/parameters/nested)
	if [[ $nested != 1 && $nested != 'Y' ]]; then
		echo "E: Nested VT is not enabled!"
		exit -1
	fi
}

version=`cat /proc/version`

vno=$(echo $version | \
	awk '{
		for(i=0;i<NF;i++) { if ($i == "Linux" && $(i+1) == "version") { print $(i+2); next; } }
	}'
)
if [[ "$vno" > "5.0.0" ]]; then
	check_nested_vt
	setup_vgpu
	if [[ $? == 0 ]]; then
		launch_hwrender
	else
		echo "W: Failed to create vgpu, fall to software rendering"
		launch_swrender
	fi
else
	echo "E: Detected linux version $vno"
	echo "E: Please upgrade kernel version newer than 5.0.0!"
	exit -1
fi

