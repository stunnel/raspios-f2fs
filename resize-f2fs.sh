#!/bin/bash

target_dev=${1}
partition_num=${2:-2}
if [[ -z "${target_dev}" ]]; then
    echo "Usage: $0 <target_dev>"
    exit 1
fi

echo "Target device: ${target_dev}"
lsblk -f "${target_dev}" || exit 1

echo "WARNING: Are you sure to resize ${target_dev} partition ${partition_num}? (YES/No)"
read -r answer
if [[ "${answer}" != "YES" ]]; then
    echo "Abort"
    exit 1
fi

block_name=${target_dev##*/}
partition_format=$(lsblk -f | grep "${block_name}${partition_num}" | awk '{print $2}')
if [[ "${partition_format}" == "f2fs" ]]; then
    sudo parted "${target_dev}" u s resizepart "${partition_num}" $(($(cat "/sys/block/${block_name}/size") - 1))
    sudo resize.f2fs "${target_dev}${partition_num}"
else
    echo "Device ${target_dev} partition ${partition_num} is not f2fs, skip"
fi
