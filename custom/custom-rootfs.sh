#!/bin/bash

# AVOID to DEFINE the function name or UPDATE the variables in raspios-f2fs.sh

# Useful variables from raspios-f2fs.sh:
#   working_dir: the directory where the image will be created
#   tmp_dir: the directory where the files of roots will be copied, changing the files in this directory will copy them to the image
#   boot_dir: the directory of partition 1 of the image
#   script_dir: the directory where this script is located, the `custom` is included in it

custom_rootfs() {
    update_hostname;
    update_localtime;
    list_copied_files;
}

update_hostname() {
    echo "=== Updating hostname ==="
    echo "Update the hostname to pi"
    # Update /etc/hosts
    #sudo sed -i "s/raspberrypi/pi/g" "${tmp_dir}/etc/hosts";
    # Update /etc/hostname
    #echo pi | sudo tee "${tmp_dir}/etc/hostname" > /dev/null;
}

update_localtime() {
    echo "=== Updating localtime ==="
    # update the localtime to America/Chicago
    #sudo ln -sf /usr/share/zoneinfo/America/Chicago "${tmp_dir}/etc/localtime";
    # Or use the timezone of host server
    #sudo cp -a /etc/localtime "${tmp_dir}/etc/localtime";
}

list_copied_files() {
    echo "=== Listing copied files ==="
    if [[ -d "${script_dir}/custom/etc" ]]; then
        file_list=$(find "${script_dir}/custom/etc" -type f -printf "%P\n")
        for file in ${file_list}; do
            ls -l "${script_dir}/custom/etc/${file}" "${tmp_dir}/etc/${file}";
        done
    fi
}
