## About

dddd doesn't do dd. It helps user who dont want to dd a livecd before installing OS.

## Usage

1. Manually partition the disk before using dddd.sh. The automatic partitioning function is not yet available.

2. Prepare an ISO file.

3. Execuate this `dddd.sh` as root.

## Example

```
chmod +x ./dddd.sh
./dddd.sh  -f dvd.iso -m /dev/nvme0n1p1:/boot/efi/  -m /dev/nvme0n1p2:/boot  -m /dev/nvme0n1p3:/ -m /dev/nvme0n1p4:/home -u ayden -p 123  -d /dev/nvme0n1
```
