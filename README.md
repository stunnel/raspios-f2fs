# raspios-f2fs - Flash Friendly Filesystem(f2fs) for the Raspberry Pi

This script converts the partition of Raspbian OS to F2FS and then can be flashed it to an TF card or USB flash drive.  
It can also be used to customize your image, such as configuring Wi-Fi, setting up a user account, and enabling headless setup, etc.  

## Requirements

- A Debian/Ubuntu with x86_64 or aarch64 architecture
- 6 GiB of free disk space for the lite image, 40 GiB for the full image

## Build
- Ensure that the user has root access
- Clone the repository: `git clone --depth 1 https://github.com/stunnel/raspios-f2fs`
- Run the script

### Parameters

`Usage: raspios-f2fs.sh -w working_dir -i source_image [-u username] [-p password] [-h]`

- `-w`: working directory, **required**, the location to place the image file and temporary files. It needs about 6 GiB of free disk space for the lite image, or 40 GiB for the full image.
- `-i`: source image, **required**, the Raspbian OS image file in xz or img format.
- `-u`: username, **optional**, create a user account during the first boot. If set, it will not prompt you to create a user on the first boot. It's useful for headless setups.
- `-p`: password, **optional**, the password for the user account.
- `-h`: help, **optional**, print this help information.

Example:

`bash raspios-f2fs.sh -w ~/raspios -i 2024-03-15-raspios-bookworm-arm64-lite.img.xz -u pi -p password-example`

## Customization

There are three ways to customize the build:

- **Custom config files**  
  Place your custom config files in `custom/etc/`, and the script will copy them to `/etc/` in the image.  
  For example, configure your Wi-Fi by creating `custom/etc/network/interfaces.d/wlan0`.
- **Custom script**  
  Write your script in `custom/custom-rootfs.sh`, and the script will run it when updating the rootfs.  
  You can use the variables defined in the `raspbian-f2fs.sh`.  
  **You can do anything you want in the script, SO BE CAREFUL.**  
  There is a simple example in `custom/custom-rootfs.sh`.
- **Custom packages**  
  Place your custom packages in `custom/packages.txt`, and the script will install them when updating the rootfs.  
  For example, I put `ifmetric` in `custom/packages.txt` because I configure the priority of my network interfaces in `custom/etc/network/interfaces.d/eth0`.

## Flashing

Use the `dd` command to write the image file to the SD card or USB flash drive.  
However, f2fs partition cannot be expanded during first boot.  
Run the script `resize-f2fs.sh` to expand the filesystem after flashing the image.  
It may take a few minutes to migrate ssa, nat and sit blocks.

## How It Works

### Directories

```
working_dir
├── 2024-03-15-raspios-bookworm-arm64-lite.img
├── 2024-03-15-raspios-bookworm-arm64-lite.img.xz
├── rootfs
└── tmp
     └── boot
          └── firmware
```

```
raspios-f2fs
├── custom
│    ├── custom-rootfs.sh
│    ├── etc
│    │    ├── network
│    │    │    └── interfaces.d
│    │    │        ├── eth0
│    │    │        └── wlan0
│    │    └── ssh
│    │        └── sshd_config.d
│    │            └── port.conf
│    └── packages.txt
└── raspios-f2fs.sh
```

To be completed...

## TODO

- Docker support
