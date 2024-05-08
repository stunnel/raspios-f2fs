#!/bin/bash

get_opts() {
    while getopts "w:i:u:p:h" opts
    do
        case $opts in
            w) working_dir=${OPTARG} ;;
            i) source_image=${OPTARG} ;;
            u) username=${OPTARG} ;;
            p) password=${OPTARG} ;;
            h) _usage; exit 0 ;;
            ?) _usage; exit 10 ;;
        esac
    done

    if [[ -z "${working_dir}" ]]; then
        echo "Error: working_dir is not specified"
        _usage;
        exit 1;
    fi

    if [[ -z "${source_image}" ]]; then
        echo "Error: source_image is not specified"
        _usage;
        exit 1;
    fi
}

_usage() {
    echo "Usage: $0 -w working_dir -i source_image [-u username] [-p password] [-h]"
}

init_env() {
    # Print header.
    echo "                                                 "
    echo "Raspbian OS F2FS Image Creation Tool"
    echo "-------------------------------------------------"
    echo "                                                 "

    rootfs_dir="${working_dir}/rootfs"
    tmp_dir="${working_dir}/tmp"
    boot_dir="${tmp_dir}/boot/firmware"
    script_dir=$(dirname "$0")

    echo "Working directory: ${working_dir}"
    echo "Source image: ${source_image}"
    echo "Script directory: ${script_dir}"
    if [[ -n "${username}" && -n "${password}" ]]; then
        echo "Will create user ${username}"
        echo "And enable SSH service when first boot"
        echo "Make sure you connect to the network via Ethernet or WiFi"
    fi
}

install_packages() {
    # install required packages
    echo "=== Installing required packages ==="
    local qemu_user_static
    qemu_user_static=""
    arch=$(uname -m)
    if [[ "${arch}" != "aarch64" && "${arch}" != x86_64 ]]; then
        echo "Error: unsupported architecture: ${arch}"
        echo "Supported architecture: aarch64, x86_64"
        exit 1;
    elif [[ "${arch}" == "x86_64" ]]; then
        qemu_user_static="qemu-user-static"
    fi
    sudo apt-get -qq install kpartx parted f2fs-tools rsync openssl \
        xz-utils util-linux coreutils bc ${qemu_user_static} >/dev/null;
}

_download() {
    wget -N --no-verbose --content-disposition "$@"
}

extract_image() {
    echo "=== Extracting image ==="

    # if source_image is a url, download it.
    if [[ "${source_image}" =~ ^https?:// ]]; then
        echo "Downloading ${source_image}"
        _download -O "${working_dir}/${source_image##*/}" "${source_image}";
        source_image="${working_dir}/${source_image##*/}";
    fi

    # if source_image is xz file, extract it.
    if [[ "${source_image}" =~ \.xz$ ]]; then
        echo "Extracting ${source_image}"
        if [[ ! -f "${working_dir}/${source_image%.xz}" ]]; then
            echo "Extracting to ${source_image%.xz}"
            xz -d "${working_dir}/${source_image}" -c > "${working_dir}/${source_image%.xz}";
            echo "Extracted image: ${source_image}"
        else
            echo "File ${working_dir}/${source_image%.xz} already exists, skip extract"
        fi
        source_image="${source_image%.xz}";
    fi

    if [[ "${source_image}" != *.img ]]; then
        echo "Error: source_image is not a valid image file"
        exit 1;
    fi
}

mount_image() {
    echo "=== Mounting image ==="
    # mount image to loop device
    echo "Mounting image ${source_image} to loop device"
    sudo kpartx -av "${working_dir}/${source_image}";

    # mount image
    echo "Mounting image partitions"
    sudo mkdir -p "${rootfs_dir}";
    sudo mount /dev/mapper/loop0p2 "${rootfs_dir}";
}

create_tmpfs() {
    echo "=== Creating tmpfs ==="
    current_sector=$(sudo kpartx -l "${working_dir}/${source_image}" | awk '/loop0p2/ {print $4}')
    # for example
    # loop0p1 : 0 1048576 /dev/loop0 8192
    # loop0p2 : 0 4349952 /dev/loop0 1056768
    current_size=$(echo "scale=0; ${current_sector} * 512 / (1024 * 1024)" | bc)
    target_sector=$((current_sector * 120 / 100))         # f2fs requires more disk space than ext4
    target_sector=$(((target_sector / 8192 + 1) * 8192))  # Rounded up to the nearest multiple of 8192 (4 MiB)
    target_size=$(echo "scale=0; ${target_sector} * 512 / (1024 * 1024)" | bc)

    echo "Current sector: ${current_sector}, size: ${current_size}M"
    echo "Target sector: ${target_sector}, size: ${target_size}M"
    echo "Creating tmpfs with size ${target_size}M"

    # dd if=/dev/zero of=tmp.fs bs=1024k count="${target_size}";
    truncate -s "${target_size}M" "${working_dir}/tmp.fs";
    sudo mkfs.f2fs "${working_dir}/tmp.fs";
    sudo mkdir -p "${tmp_dir}";

    echo "Mount tmpfs to ${tmp_dir}."
    sudo mount "${working_dir}/tmp.fs" "${tmp_dir}";
}

copy_rootfs() {
    echo "=== Copying rootfs ==="
    echo "Copying the files from ${rootfs_dir} to ${tmp_dir}"
    sudo rsync -a --stats "${rootfs_dir}/" "${tmp_dir}";
}

update_bootfs() {
    echo "=== Updating bootfs ==="
    sudo mount /dev/mapper/loop0p1 "${boot_dir}";
    sudo cp -a "${boot_dir}/cmdline.txt" "${boot_dir}/cmdline.txt.bak";
    sudo sed -i "s/rootfstype=ext4/rootfstype=f2fs/g" "${boot_dir}/cmdline.txt";

    if [[ -n "${username}" && -n "${password}" ]]; then
        # enable SSH service when first boot
        echo "Adding user ${username} and enable SSH service when first boot"
        hashed_password=$(echo "${password}" | openssl passwd -6 -stdin);  # generate SHA512 password
        userconf="${username}:${hashed_password}";
        # userconf format: username:hashed-password

        echo "${userconf}" | sudo tee "${boot_dir}/userconf.txt" >/dev/null;
        sudo touch "${boot_dir}/ssh.txt";
    fi
}

update_rootfs() {
    echo "=== Updating rootfs ==="
    # update /etc/fstab
    echo "Updating /etc/fstab"
    sudo sed -i "s/ext4/f2fs/g" "${tmp_dir}/etc/fstab";
    if [[ -f "${script_dir}/custom/fstab" ]]; then
        echo "Found custom fstab, append to /etc/fstab"
        # mount your additional devices
        cat "${script_dir}/custom/fstab" | sudo tee -a "${tmp_dir}/etc/fstab" >/dev/null;
    fi

    if [[ -d "${script_dir}/custom/etc" ]]; then
        echo "Found custom etc, copying them to /etc"
        sudo rsync -axv "${script_dir}/custom/etc/" "${tmp_dir}/etc/";
    fi

    # run custom script
    if [[ -f "${script_dir}/custom/custom-rootfs.sh" ]]; then
        echo "Found custom-rootfs.sh, run it"
        source "${script_dir}/custom/custom-rootfs.sh";
        if [ "$(type -t custom_rootfs)" == "function" ]; then
            custom_rootfs;
        else
            echo "custom_rootfs function does not exist, skip custom rootfs script."
        fi
    fi
}

install_f2fs_tools() {
    echo "=== Installing f2fs-tools ==="
    packages=""
    if [[ -f "${script_dir}/custom/packages.txt" ]]; then
        packages=$(grep -v '^#' packages.txt | sed '/^\s*$/d' | tr '\n' ' ');
        echo "Found custom packages.txt, will install these packages: f2fs-tools ${packages}"
    fi

    cat << EOF | sudo chroot "${tmp_dir}" env -i \
TERM=$TERM HOME=/root /bin/bash --login
echo "Stopping automatic ext4 filesystem expansion."
update-rc.d resize2fs_once remove
test -r /etc/init.d/resize2fs_once && rm -f /etc/init.d/resize2fs_once

echo "Installing f2fs-tools."
apt-get -qq install f2fs-tools ${packages}
apt-get -qq clean

exit 0
EOF
}

create_resize_script() {
    # not working yet
    echo "=== Creating resize script ==="
    cat << 'EOF' | sudo tee "${tmp_dir}/etc/initramfs-tools/scripts/init-premount/f2fsresize" >/dev/null
#!/bin/sh
# F2FS Resize

. /scripts/functions

# Begin real processing below this line
if [ ! -x "/sbin/resize.f2fs" ]; then
	panic "Resize.F2FS Executable Not Found"
fi

log_begin_msg "Expanding F2FS Filesystem"
/sbin/resize.f2fs /dev/mmcblk0p2

if [ $? -eq 0 ]; then
	log_begin_msg "Clean up script"
  rm -f /etc/initramfs-tools/scripts/init-premount/f2fsresize
else
  panic "F2FS Resize Failed"
fi

log_end_msg

exit 0

EOF

    sudo chmod +x "${tmp_dir}/etc/initramfs-tools/scripts/init-premount/f2fsresize"
    echo "Added resize script to initramfs-tools"
}

format_rootfs() {
    echo "=== Formatting rootfs ==="
    # umount boot and root partitions then format root partition
    sudo sync;

    echo "Unmounting boot and root partitions then format root partition"
    sudo umount "${boot_dir}" "${rootfs_dir}";
    sudo wipefs -a /dev/mapper/loop0p2;  # wipe the partition table
    echo "Creating f2fs partition in /dev/mapper/loop0p2"
    sudo mkfs.f2fs -f /dev/mapper/loop0p2;  # format the partition
    echo "Remounting /dev/mapper/loop0p2 to ${rootfs_dir}"
    sudo mount /dev/mapper/loop0p2 "${rootfs_dir}";  # remount the partition
}

copy_back_rootfs() {
    echo "=== Copying back rootfs ==="
    sudo rsync -a --stats "${tmp_dir}/" "${rootfs_dir}";
}

umount_image() {
    echo "=== Unmounting image ==="
    # umount image
    sudo sync;
    sudo umount "${rootfs_dir}" "${tmp_dir}";
    echo "Deleting tmpfs"
    sudo rm -f "${working_dir}/tmp.fs";

    echo "Unmounting image partitions from loop device"
    sudo kpartx -dv "${working_dir}/${source_image}";
}

finish() {
    echo "=== Finished ==="
    echo "Your image is ready: ${working_dir}/${source_image}"
    echo "Now you can flash it to the TF card or SD card"
}

main() {
    get_opts "$@";
    init_env;
    install_packages;

    # extract image and mount
    extract_image;
    mount_image;
    create_tmpfs;

    # copy rootfs
    copy_rootfs;
    # update bootfs
    update_bootfs;

    # update rootfs
    update_rootfs;
    install_f2fs_tools;
    # create_resize_script;  # not working, to be fixed

    # format rootfs to f2fs and copy files back
    format_rootfs;
    copy_back_rootfs;

    umount_image;
    finish;
}

if [[ "$1" != "--source-only" ]]; then
    main "$@";
fi
