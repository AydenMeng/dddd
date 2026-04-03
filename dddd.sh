#!/bin/bash
# Copyright 2026 Ayden Meng (aydenmeng@yeah.net)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FILE_DDDD_SH="dddd.sh"
INCLUDE_DDDD_SH="include_$(basename $FILE_DDDD_SH | tr -cd '[:alnum:]_')"

if [[ -n "${!INCLUDE_DDDD_SH:-}" ]]; then
	return 0
fi

declare "$INCLUDE_DDDD_SH=1"

. ./debug_print.sh

export LANG=C

G_ISO_OUT_DIR="iso_out_dddd"
G_SQU_OUT_DIR="squashfs_out_dddd"
G_IMG_OUT_DIR="img_out_dddd"
G_DISK_MNT_DIR="disk_mount_dddd"
G_OS_BASE_DIR=("home" "boot" "boot/efi")

G_SYSROOT=""

usage_dddd()
{
	log_normal  'dddd.sh:'
	log_normal  '  dddd dont do dd. It helps user who dont want to dd a livecd before installing OS.'
	log_normal  ''
	log_normal  'Options:'
	log_normal  '  -h [help]            - Display the help message'
	log_normal  '  -f [iso filename]    - Target ISO filename'
	log_normal  '  -c [configure]       - Configuration of JSON for partation plan.'
	log_normal  '  -d [disk name]       - Disk specified to be as target system disk.'
	log_normal  '  -u [username]        - Set the username of the system'
	log_normal  '  -p [password]        - Set the user password of the system, the root password'
	log_normal  '  -t [test run]        - Only decompress iso and rootfs to the target directory'
	log_normal  '  -r [recovery]        - Recover all mount point even delete them'
	log_normal  '  -m [mount point]     - Mount point you planed'
	log_normal  '  -E [ESP size]        - GB'
	log_normal  '  -B [BOOTFS size]     - GB'
	log_normal  '  -R [ROOTFS size]     - GB'
	log_normal  '  -S [SWAP size]       - GB'
	log_normal  '  -H [HOME size]       - GB'
	log_normal  ''
	log_normal  '  eg:'
	log_normal  '     ./dind.sh  -f dvd.iso -m /dev/nvme0n1p1:/boot/efi/  -m /dev/nvme0n1p2:/boot  -m /dev/nvme0n1p3:/ -m /dev/nvme0n1p4:/home -u ayden -p 123  -d /dev/nvme0n1'
	log_normal  ''
	log_normal  'Author: Ayden Meng'
	log_normal  'Mail:   aydenmeng@yeah.net'
	log_normal  'Version: v0.1'
}

dir_has_system_dddd()
{
	local l_critical_dirs l_dir
	l_dir=$1

	l_critical_dirs=("bin" "etc" "usr" "proc" "sys" "root")

	for dir in "${l_critical_dirs[@]}"; do
		if [[ ! -d "${l_dir}/${dir}" ]]; then
			log_warn "$dir/ not exist in $l_dir"
			return 1
		fi
	done
	return 0
}

find_iso_rootfs_dddd()
{
	mount $G_DDDD_ISOFILE $G_ISO_OUT_DIR
	biggest_file=$(find ${G_ISO_OUT_DIR} -type f | xargs file | grep Squashfs | cut -d: -f1 | xargs ls -S | head -10)
	for f in ${biggest_file[@]}; do
		mount $f -t squashfs $G_SQU_OUT_DIR
		if dir_has_system_dddd ${G_SQU_OUT_DIR}; then
			sysroot=$G_SQU_OUT_DIR
			G_SYSROOT=$sysroot
			return 0
		else
			umount -i -l -R ${G_SQU_OUT_DIR}
		fi
	done
	mount ${biggest_file[0]} -t squashfs $G_SQU_OUT_DIR
	if dir_has_system_dddd ${G_SQU_OUT_DIR}; then
		sysroot=$G_SQU_OUT_DIR
	else
		biggest_file=$(find ${G_SQU_OUT_DIR} | xargs ls -S | head -1)
		mount $biggest_file $G_IMG_OUT_DIR
		if dir_has_system_dddd ${G_IMG_OUT_DIR}; then
			sysroot=$G_IMG_OUT_DIR
		fi
	fi

	if [[ -n "$sysroot" ]]; then
		G_SYSROOT=$sysroot
		return 0
	fi
	return 1
}

get_temp_efi_dddd()
{
	local tmp
	for d in $G_ISO_OUT_DIR $G_SQU_OUT_DIR $G_IMG_OUT_DIR; do
		tmp=$(find ${d} -type f | grep -i "BOOT/boot.*\.efi$" | head -1 2>/dev/null)
		if [[ -n "$tmp" ]]; then
			G_LIVE_EFI_PATH=$(dirname $tmp)
			return 0
		fi
	done
	return 1
}

get_local_fedora_repo_dddd()
{
	local pkg_suffix=$1
	for d in $G_ISO_OUT_DIR $G_SQU_OUT_DIR $G_IMG_OUT_DIR; do
		if find ${d} | grep "\.${pkg_suffix}$" > /dev/null 2>&1; then
			G_LOCAL_REPO_DIR=${d}
			break
		fi
	done
}

set_passwd_if_chroot_fail_dddd()
{
	local l_enc l_passwd l_lastuid l_uid

	log "set passwd manually because chroot failed"
	l_enc=$(grep "^ENCRYPT_METHOD" ${G_DISK_MNT_DIR}/etc/login.defs | cut -d " " -f 2)
	l_passwd=$(openssl passwd -6 "$G_DDDD_PASSWORD")
	l_lastuid=$(awk -F: '$3 >= 1000 && $3 < 65534 {max=$3} END{print max+1}' "${G_DISK_MNT_DIR}/etc/passwd")
	l_uid=${l_lastuid:-1000}
	echo "${G_DDDD_USERNAME}:x:${l_uid}:${l_uid}:,,:/home/${G_DDDD_USERNAME}:/bin/bash" >> "${G_DISK_MNT_DIR}/etc/passwd"
	echo "${G_DDDD_USERNAME}:${l_passwd}:$(date +%s)/86400:0:99999:7:::" >> "${G_DISK_MNT_DIR}/etc/shadow"
	chmod 600 "${G_DISK_MNT_DIR}/etc/shadow"
	if [[ ! -f "${G_DISK_MNT_DIR}/home/$G_DDDD_USERNAME/.bashrc" ]]; then
		cp -r "${G_DISK_MNT_DIR}/etc/skel/." "${G_DISK_MNT_DIR}/home/$G_DDDD_USERNAME/" 2>/dev/null
		chown -R ${G_DDDD_USERNAME}:${G_DDDD_USERNAME} "${G_DISK_MNT_DIR}/home/$G_DDDD_USERNAME"
	fi
}

install_pkgs_fedora_dddd()
{
	if get_local_fedora_repo_dddd 'rpm'; then
		rm -rf ${G_DISK_MNT_DIR}/tmp/iso
		cp $G_LOCAL_REPO_DIR ${G_DISK_MNT_DIR}/tmp/iso -arf
	fi
	chroot $G_DISK_MNT_DIR <<- EOF
	dnf -y --disablerepo='*' \
		--repofrompath=local,file:///tmp/iso \
		--releasever=$(source /etc/os-release; echo $VERSION_ID 2>/dev/null || echo "8") \
		--nogpgcheck \
		install \
		$@
	exit
EOF
	rm -rf ${G_DISK_MNT_DIR}/tmp/iso
}

install_os_dddd()
{
	local l_os_version l_hostname l_rootuuid l_grubinstall l_grubmkcfg l_passwd l_pkg l_group l_kver
	local tmp1 tmp2 tmp3

	l_os_version=$(grep '^VERSION_ID=' ${G_SYSROOT}/etc/os-release | grep -o "[0-9].*[0-9]")
	l_hostname=$(grep '^ID=' ${G_SYSROOT}/etc/os-release | cut -d'=' -f2)
	l_hostname=$(echo "${l_hostname}-${l_os_version}" | sed 's/"//g' | sed 's/ /-/g')
	l_grubinstall=$(basename $(find ${G_SYSROOT}/{bin,sbin}/ | grep grub | grep install | head -1) 2>/dev/null)
	l_grubmkcfg=$(basename $(find ${G_SYSROOT}/{bin,sbin}/ | grep grub | grep mkconfig | head -1) 2>/dev/null)
	l_passwd=$(basename $(find ${G_SYSROOT}/{bin,sbin}/ | grep -w chpasswd | head -1) 2>/dev/null)
	l_pkg=$(basename $(find ${G_SYSROOT}/bin/ | grep -Pwo "dpkg|apt|yum|dnf|rpm" | head -1) 2>/dev/null)
	if grep sudo -w ${G_SYSROOT}/etc/group > /dev/null 2>&1; then
		l_group="sudo"
	else
		l_group="wheel"
	fi

	case "$l_pkg" in
		dpkg|apt)
			l_pkg=debian
			;;
		yum|dnf|rpm)
			l_pkg=fedora
			;;
		*)
			l_pkg=debian
			log_warn "OS will install as debian"
			;;
	esac

	if get_temp_efi_dddd; then
		log_normal "cp live EFI to $G_DISK_MNT_DIR/boot/efi/EFI/${l_hostname}"
		mkdir -p $G_DISK_MNT_DIR/boot/efi/EFI/${l_hostname}
		cp $G_LIVE_EFI_PATH/* $G_DISK_MNT_DIR/boot/efi/EFI/${l_hostname}/ -a
	fi
	log "cp ${G_SYSROOT}/* $G_DISK_MNT_DIR/ -a ..."
	tar --acls --selinux --xattrs -cf - -C ${G_SYSROOT}/ . | tar --acls --selinux --xattrs -xf - -C $G_DISK_MNT_DIR/
	if find $G_DISK_MNT_DIR/{etc,usr,bin,sbin}/ | grep -iw anaconda | xargs rm -rf > /dev/null 2>&1; then
		cp $G_DISK_MNT_DIR/etc/os-release $G_DISK_MNT_DIR/etc/initrd-release
	fi
	log "cp ${G_SYSROOT}/* $G_DISK_MNT_DIR/ -a ...done"
	sync

	mount --types proc /proc $G_DISK_MNT_DIR/proc
	mount --rbind /dev $G_DISK_MNT_DIR/dev
	mount --make-rslave $G_DISK_MNT_DIR/dev
	mount --rbind /sys $G_DISK_MNT_DIR/sys
	mount --make-rslave $G_DISK_MNT_DIR/sys
	mount --bind /run $G_DISK_MNT_DIR/run
	mount --make-rslave $G_DISK_MNT_DIR/run
	log "mount host file system to ${G_DISK_MNT_DIR} ...done"

	cp /etc/hostname $G_DISK_MNT_DIR/etc/hostname -a
	echo $l_hostname > $G_DISK_MNT_DIR/etc/hostname
	cp /etc/hosts $G_DISK_MNT_DIR/etc/hosts -a
	mkdir -p ${G_DISK_MNT_DIR}/home/${G_DDDD_USERNAME}


	log "chroot to install..."
	timeout 20 chroot "$G_DISK_MNT_DIR" /bin/sh -c 'touch /dddd.sh'

	if [[ -f $G_DISK_MNT_DIR/dddd.sh ]]; then
		if [[ "$l_pkg" == "fedora" ]]; then
			log "install pkgs from local iso ..."
			install_pkgs_${l_pkg}_dddd @core @server-product
		fi

		log "generate initramfs ..."
		chroot $G_DISK_MNT_DIR <<- EOF
		ls /lib/modules/ | xargs dracut --force --kver
		ls /lib/modules/ | xargs -I N mkinitramfs -o /boot/initrd.img-N N
		exit
EOF

		log "generate grub ..."
		chroot $G_DISK_MNT_DIR <<- EOF
			ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
			${l_grubinstall} ${G_DDDD_DISK} --efi-directory=/boot/efi --bootloader-id=${l_hostname} --no-nvram
			env GRUB_DISABLE_OS_PROBER=true ${l_grubmkcfg} -o /boot/${l_grubmkcfg%-*}/grub.cfg
			exit
		EOF
		log "generate user ..."
		if [[ -z "$l_passwd" ]]; then
			chroot $G_DISK_MNT_DIR <<- EOF
				useradd -M -d /home/${G_DDDD_USERNAME} -G ${l_group} -s /bin/bash ${G_DDDD_USERNAME}
				chown ${G_DDDD_USERNAME}:${G_DDDD_USERNAME} /home/${G_DDDD_USERNAME}
				echo "${G_DDDD_USERNAME}:${G_DDDD_PASSWORD}" | chpasswd
				echo "root:${G_DDDD_PASSWORD}" | chpasswd
				passwd ${G_DDDD_USERNAME}
				${G_DDDD_PASSWORD}
				${G_DDDD_PASSWORD}
				passwd root
				${G_DDDD_PASSWORD}
				${G_DDDD_PASSWORD}
				exit
		EOF
		else
			chroot $G_DISK_MNT_DIR <<- EOF
				useradd -M -d /home/${G_DDDD_USERNAME} -G ${l_group} -s /bin/bash ${G_DDDD_USERNAME}
				chown ${G_DDDD_USERNAME}:${G_DDDD_USERNAME} /home/${G_DDDD_USERNAME}
				echo "${G_DDDD_USERNAME}:${G_DDDD_PASSWORD}" | chpasswd
				echo "root:${G_DDDD_PASSWORD}" | chpasswd
				exit
		EOF
		fi
		rm -rf ${G_DISK_MNT_DIR}/dddd.sh
	else
		if ! mountpoint ${G_DISK_MNT_DIR}/boot; then
			tmp1="/boot"
		fi
		mkdir -p ${G_DISK_MNT_DIR}/boot/${l_grubmkcfg%-*}
		cat <<-EOF | sudo tee ${G_DISK_MNT_DIR}/boot/${l_grubmkcfg%-*}/grub.cfg
		set timeout=5
		set default=0
EOF
		l_kver=$(ls ${G_DISK_MNT_DIR}/lib/modules/)
		for k in ${l_kver[@]}; do
			tmp2=$(ls ${G_DISK_MNT_DIR}/boot/vm*${k} | head -1)
			tmp2=$(basename $tmp2)
			tmp3=$(ls ${G_DISK_MNT_DIR}/boot/init*${k} | head -1)
			tmp3=$(basename $tmp3)
			cat <<-EOF | tee -a ${G_DISK_MNT_DIR}/boot/${l_grubmkcfg%-*}/grub.cfg

			menuentry "${l_hostname}-${k}" {
			linux $tmp1/$tmp2 root=UUID=${G_DDDD_ROOT_UUID} ro splash
			initrd $tmp1/$tmp3
			}
EOF
		done
		set_passwd_if_chroot_fail_dddd
	fi

	ln -sf /etc/machine-id ${G_DISK_MNT_DIR}/var/lib/dbus/machine-id

	log "generate fstab ..."
	chmod +x ./genfstab/genfstab
	./genfstab/genfstab -U $G_DISK_MNT_DIR > $G_DISK_MNT_DIR/etc/fstab

	sed -i "s/\S*\(\s*none\s*swap.*\)/UUID=${G_DDDD_SWAP_UUID}\1/g" $G_DISK_MNT_DIR/etc/fstab
	#l_rootuuid=$(cat $G_DISK_MNT_DIR/etc/fstab | grep -w "/" | grep -v "^#" | awk '{print $1}')
	#find $G_DISK_MNT_DIR/boot/ -name grub.cfg | xargs -I N sed -i "s/root=UUID=\S*/root=${l_rootuuid}/g" N
	sed -i "/^\s*linux.*root/s/$/ ${G_DDDD_BOOT_ARGS}/" $G_DISK_MNT_DIR/boot/${l_grubmkcfg%-*}/grub.cfg

	rm -rf $G_DISK_MNT_DIR/etc/initrd-release
	log "all done ... umount all..."
	umount -l -i -R $G_DISK_MNT_DIR/dev
	umount -l -i -R $G_DISK_MNT_DIR/proc
	umount -l -i -R $G_DISK_MNT_DIR/sys
	umount -l -i -R $G_DISK_MNT_DIR/run

	rm -rf ${G_DISK_MNT_DIR}/dev/*
	rm -rf ${G_DISK_MNT_DIR}/sys/*
	rm -rf ${G_DISK_MNT_DIR}/run/*
	rm -rf ${G_DISK_MNT_DIR}/proc/*
}

MB_TO_GB_DDDD()
{
	local l_mb

	l_mb=$1
	echo $l_mb | grep -o "[0-9]*" | awk '{printf "%.2f", $1/1000}'
}

get_disk_size_dddd()
{
	local l_disk l_disk_size_gb
	l_disk=$1
	l_disk_size_gb=$(parted -s "$l_disk" unit GB print | grep "^Disk $DISK" | awk '{print $3}' | tr -d 'GB')
	echo $l_disk_size_gb
}

disk_suggestion_dddd()
{
	local l_disk_size_gb l_disk l_gb l_tmp l_sum

	l_disk_size_gb=$(get_disk_size_dddd)

	if (( $l_disk_size_gb < 70 )); then
		G_DDDD_ESP_SIZE="0.3"
		G_DDDD_BOOTFS_SIZE="0"
		G_DDDD_HOME_SIZE="0"
		G_DDDD_SWAP_SIZE="0"
		G_DDDD_ROOTFS_SIZE=$(awk 'BEGIN {printf "%.2f", $l_disk_size_gb - $G_DDDD_ESP_SIZE - $G_DDDD_BOOTFS_SIZE - $G_DDDD_HOME_SIZE - $G_DDDD_SWAP_SIZE}')
	elif (( $l_disk_size_gb < 140 )); then
		G_DDDD_ESP_SIZE="0.3"
		G_DDDD_BOOTFS_SIZE="0.7"
		G_DDDD_ROOTFS_SIZE="80"
		G_DDDD_SWAP_SIZE="8"
		G_DDDD_HOME_SIZE=$(awk 'BEGIN {printf "%.2f", $l_disk_size_gb - $G_DDDD_ESP_SIZE - $G_DDDD_BOOTFS_SIZE - $G_DDDD_ROOTFS_SIZE - $G_DDDD_SWAP_SIZE}')
	elif (( $l_disk_size_gb < 280 )); then
		G_DDDD_ESP_SIZE="0.3"
		G_DDDD_BOOTFS_SIZE="0.7"
		G_DDDD_ROOTFS_SIZE="100"
		G_DDDD_SWAP_SIZE="8"
		G_DDDD_HOME_SIZE=$(awk 'BEGIN {printf "%.2f", $l_disk_size_gb - $G_DDDD_ESP_SIZE - $G_DDDD_BOOTFS_SIZE - $G_DDDD_ROOTFS_SIZE - $G_DDDD_SWAP_SIZE}')
	elif (( $l_disk_size_gb < 560 )); then
		G_DDDD_ESP_SIZE="0.3"
		G_DDDD_BOOTFS_SIZE="0.7"
		G_DDDD_ROOTFS_SIZE="100"
		G_DDDD_SWAP_SIZE="8"
		G_DDDD_HOME_SIZE=$(awk 'BEGIN {printf "%.2f", $l_disk_size_gb - $G_DDDD_ESP_SIZE - $G_DDDD_BOOTFS_SIZE - $G_DDDD_ROOTFS_SIZE - $G_DDDD_SWAP_SIZE}')
	fi
}

format_partation_dddd()
{
	local l_disk l_fstype l_target_format
	l_partation=$1
	l_fstype=$2
	l_target_format=$3
	if lsblk -o FSTYPE $l_partation -n | grep "$l_fstype" > /dev/null 2>&1; then
		return 0
	fi

	case "$l_target_format" in
		esp|fat|fat32|vfat)
			mkfs.vfat -F 32 $l_partation
			fsck -y $l_partation
			;;
		ext2|ext3|ext4)
			mkfs.ext4 -F $l_partation
			fsck -y $l_partation
			;;
		xfs)
			mkfs.xfs -f $l_partation
			xfs_repair -L $l_partation
			xfs_repair  $l_partation
			;;
		swap)
			mkswap        $l_partation
			;;
		*)
			log_error "$l_target_format not supported by dddd"
			;;
	esac

}

make_partation_dddd()
{
	local l_partation l_mnt

	for p in "${G_DDDD_MNT_CFG[@]}"; do
		l_partation=${p%:*}
		l_mnt=${p#:*}
		if echo $l_mnt | grep "efi" > /dev/null; then
			format_partation_dddd $l_partation fat fat32
		elif echo $l_mnt | grep "boot" > /dev/null; then
			format_partation_dddd $l_partation ext4 ext4
		elif echo $l_mnt | grep "swap" > /dev/null; then
			format_partation_dddd $l_partation swap swap
		elif echo $l_mnt | grep "home" > /dev/null; then
			format_partation_dddd $l_partation ext4 ext4
		elif echo $l_mnt | grep "^/$" > /dev/null; then
			format_partation_dddd $l_partation ext4 ext4
		fi
	done
}

mount_partation_dddd()
{
	local l_partation l_mnt

	if ! rm -rf $G_DISK_MNT_DIR; then
		log_error "$G_DISK_MNT_DIR is busy, rm error"
		return 1
	fi
	for p in "${G_DDDD_MNT_CFG[@]}"; do
		l_partation=${p%:*}
		l_mnt=${p#*:}
		if echo $l_mnt | grep -w "/"; then
			G_DDDD_ROOT_UUID=$(blkid -s UUID -o value $l_partation)
			mkdir -p ${G_DISK_MNT_DIR}
			mount $l_partation $G_DISK_MNT_DIR
			log_normal "mount $l_partation $G_DISK_MNT_DIR"
			break
		fi
	done
	for p in "${G_DDDD_MNT_CFG[@]}"; do
		l_partation=${p%:*}
		l_mnt=${p#*:}
		if echo $l_mnt | grep -w "/"; then
			continue
		fi
		mkdir -p ${G_DISK_MNT_DIR}/${l_mnt}
		if ! echo $l_mnt | grep "swap"; then
			mount $l_partation $G_DISK_MNT_DIR/$l_mnt
			log_normal "mount $l_partation $G_DISK_MNT_DIR/$l_mnt"
		else
			G_DDDD_SWAP_UUID=$(blkid -s UUID -o value $l_partation)
			log "G_DDDD_SWAP_UUID = ${G_DDDD_SWAP_UUID}"
		fi
	done
}

rootfs_mount_point_dddd()
{
	rm -rf $G_DISK_MNT_DIR
	mkdir -p $G_DISK_MNT_DIR
	cd $G_DISK_MNT_DIR
	mkdir -p "${G_OS_BASE_DIR[@]}"
	cd -
}

umount_dddd()
{
	local l_dir=$1
	if mount -v | grep "${l_dir}"; then
		umount -i -l -R ${l_dir}
		umount -i -l -R ${l_dir} # double check
		if mount -v | grep "${l_dir}"; then
			return 0
		fi
		return $?
	fi
	return 0
}

post_umount_dddd()
{
	local l_mnt

	for dir in ${G_IMG_OUT_DIR} ${G_SQU_OUT_DIR} ${G_ISO_OUT_DIR} ${G_DISK_MNT_DIR}; do
		if ! umount_dddd ${dir} > /dev/null 2>&1; then
			log_error "$dir umount error, please check it."
		fi
	done
	for p in "${G_DDDD_MNT_CFG[@]}"; do
		l_mnt=${p#*:}
		if ! echo $l_mnt | grep "swap"; then
			if ! umount_dddd ${G_DISK_MNT_DIR}${l_mnt} > /dev/null 2>&1; then
				log_error "$G_DISK_MNT_DIR/$l_mnt umount error, please check it."
			fi
		fi
	done
}

rootfs_mount_point_recover_dddd()
{
	for dir in ${G_IMG_OUT_DIR} ${G_SQU_OUT_DIR} ${G_ISO_OUT_DIR} ${G_DISK_MNT_DIR}; do
		if ! umount_dddd ${dir} > /dev/null 2>&1; then
			log_error "$dir umount error, please check it."
			return 1
		fi
	done
	rm -rf ${G_IMG_OUT_DIR} ${G_SQU_OUT_DIR} ${G_ISO_OUT_DIR} ${G_DISK_MNT_DIR} > /dev/null 2>&1
	mkdir -p ${G_IMG_OUT_DIR} ${G_SQU_OUT_DIR} ${G_ISO_OUT_DIR} ${G_DISK_MNT_DIR}
	return 0
}

disk_check_dddd()
{
	G_DISK_BASENAME=$(basename $G_DDDD_DISK)
	if mount -v | grep -wE "\/" | grep "${G_DISK_BASENAME}"; then
		log_error "$G_DDDD_DISK is the current system disk, cannot be installed!"
		return 1
	fi
	if ! cat /sys/block/${G_DISK_BASENAME}/device/model; then
		log_warn "$G_DISK_BASENAME seems like a partation but not a disk!"
		return 1
	fi
	if mount -v | grep "${G_DISK_BASENAME}"; then
		log_warn "$G_DISK_BASENAME is already mounted, umount it to continue!"
		return 1
	fi
	return 0
}

args_parse_dddd()
{
	local l_nvme_suffix l_tmp
	if [[ -n "$G_DDDD_ISOFILE" && ! -f $G_DDDD_ISOFILE ]]; then
		log_error "$G_DDDD_ISOFILE is not a file!"
		exit 1
	fi
	if [[ -n "$G_DDDD_CONFIG" && ! -f $G_DDDD_CONFIG ]]; then
		log_error "$G_DDDD_CONFIG is not a file!"
		exit 1
	fi
	if [[ -n "$G_DDDD_DISK" ]]; then
		if [[ ! -b $G_DDDD_DISK ]]; then
			log_error "$G_DDDD_DISK is not a block device!"
			exit 1
		else
			if ! disk_check_dddd; then
				exit 1
			fi
			if echo $G_DDDD_DISK | grep nvme; then
				l_nvme_suffix="p"
			fi
		fi
	fi
	if [[ -z $G_DDDD_USERNAME ]]; then
		G_DDDD_USERNAME=mxd
	fi
	if [[ -z $G_DDDD_PASSWORD ]]; then
		G_DDDD_PASSWORD=123
	fi
	if [[ -z $G_DDDD_ESP_SIZE ]]; then
		G_DDDD_ESP_SIZE="0.3"
	fi
	if [[ -z $G_DDDD_BOOTFS_SIZE ]]; then
		G_DDDD_BOOTFS_SIZE="0.7"
	fi
	if [[ -z $G_DDDD_SWAP_SIZE ]]; then
		G_DDDD_SWAP_SIZE="8"
	fi
	if [[ -z $G_DDDD_BOOT_ARGS ]]; then
		G_DDDD_BOOT_ARGS="console=ttyS0,115200 earlycon=uart,mmio,0x1fe001e0"
	fi
	if [[ -z "${G_DDDD_MNT_CFG[@]}" ]]; then
		G_DDDD_MNT_CFG+=("${G_DDDD_DISK}${l_nvme_suffix}1:/boot/efi")
		G_DDDD_MNT_CFG+=("${G_DDDD_DISK}${l_nvme_suffix}2:/boot")
		G_DDDD_MNT_CFG+=("${G_DDDD_DISK}${l_nvme_suffix}3:/")
		G_DDDD_MNT_CFG+=("${G_DDDD_DISK}${l_nvme_suffix}4:/home")
		G_DDDD_MNT_CFG+=("${G_DDDD_DISK}${l_nvme_suffix}5:swap")
	else
		for m in "${G_DDDD_MNT_CFG[@]}"; do
			if echo $m | grep "/$"; then
				l_tmp=1
			fi
		done
		if [[ -z "$l_tmp" ]]; then
			log_error "rootfs / not specified!"
			exit 1
		fi
	fi
}

main_dddd()
{
	if [[ $# -eq 0  ]]; then
		usage_dddd
		exit 0
	fi
	ARGS=$(getopt -o hrta:f:c:d:u:p:m:E:B:R:S:H: -- "$@")
	if [ $? != 0 ]; then
		log "Terminating..."
		exit 1
	fi
	eval set -- "${ARGS}"

	while true
	do
		case "$1" in
			-h)
				usage_dddd
				exit 0
				;;
			-r)
				G_DDDD_RECOVER=1
				shift
				;;
			-t)
				G_DDDD_TEST=1
				shift
				;;
			-f)
				G_DDDD_ISOFILE=$2
				log "Target ISO file: ${G_DDDD_ISOFILE}";
				shift 2
				;;
			-a)
				G_DDDD_BOOT_ARGS=$2
				log "Append boot args: ${G_DDDD_BOOT_ARGS}";
				shift 2
				;;
			-c)
				G_DDDD_CONFIG=$2
				log "Configuration: ${G_DDDD_CONFIG}";
				shift 2
				;;
			-d)
				G_DDDD_DISK=$2
				log "Target disk: ${G_DDDD_DISK}";
				shift 2
				;;
			-u)
				G_DDDD_USERNAME=$2
				log "Preset username: ${G_DDDD_USERNAME}";
				shift 2
				;;
			-p)
				G_DDDD_PASSWORD=$2
				log "Preset password: ${G_DDDD_PASSWORD}";
				shift 2
				;;
			-m)
				G_DDDD_MNT_CFG+=($2)
				log "mount point: $2";
				shift 2
				;;
			-E)
				G_DDDD_ESP_SIZE=$2
				log "ESP size will be: ${G_DDDD_ESP_SIZE}";
				shift 2
				;;
			-B)
				G_DDDD_BOOTFS_SIZE=$2
				log "BOOTFS size will be: ${G_DDDD_BOOTFS_SIZE}";
				shift 2
				;;
			-R)
				G_DDDD_ROOTFS_SIZE=$2
				log "ROOTFS size will be: ${G_DDDD_ROOTFS_SIZE}";
				shift 2
				;;
			-S)
				G_DDDD_SWAP_SIZE=$2
				log "SWAP size will be: ${G_DDDD_SWAP_SIZE}";
				shift 2
				;;
			-H)
				G_DDDD_HOME_SIZE=$2
				log "HOME size will be: ${G_DDDD_HOME_SIZE}";
				shift 2
				;;
			--)
				shift
				break
				;;
			*)
				usage_dddd
				exit 0 # input error
				;;
		esac
	done

	if [[ -n ${G_DDDD_RECOVER} ]]; then
		rootfs_mount_point_recover_dddd
		exit $?
	fi

	args_parse_dddd
	if ! rootfs_mount_point_recover_dddd; then
		exit 1
	fi
	if find_iso_rootfs_dddd; then
		log_normal "sysroot: ${G_SYSROOT}"
		make_partation_dddd
		if mount_partation_dddd; then
			install_os_dddd
		fi
	fi
	post_umount_dddd
}

CALL_WHERE_DDDD_SH=$(basename $0)

if [[ "$CALL_WHERE_DDDD_SH" == "$FILE_DDDD_SH" ]]; then
	if ! main_dddd $@; then
		log_error "run error!!!"
		exit 1
	fi
fi
