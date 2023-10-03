# https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/deduplicating_and_compressing_logical_volumes_on_rhel/creating-a-deduplicated-and-compressed-logical-volume_deduplicating-and-compressing-logical-volumes-on-rhel#slab-size-in-vdo_creating-a-deduplicated-and-compressed-logical-volume




## 2023-10-01 - LATEST version of pre-built kvdo module is for 5.14.0-360.el9 - but latest kernel is 5.14.0-368.el9
## so we compile it from sources:

## https://wiki.centos.org/HowTos(2f)RebuildSRPM.html


dnf install gcc gcc-c++ kernel-devel make
dnf install rpm-build redhat-rpm-config 

dnf install libuuid-devel
dnf download --source kmod-kvdo

rpmbuild --rebuild kmod-kvdo-8.2.1.6-98.el9.src.rpm


## as an alternative, we can build from upstream:
git clone https://github.com/dm-vdo/kvdo.git
cd kvdo
make -C /usr/src/kernels/`uname -r` M=`pwd`
make -C /usr/src/kernels/`uname -r` M=`pwd` modules_install

########################################
########################################
########################################

dnf install lvm2
dnf localinstall rpmbuild/RPMS/x86_64/kmod-kvdo-8.2.1.6-98.el9.x86_64.rpm
dnf install vdo

########################################
########################################
########################################


		[root@node1 /]# lsblk
		NAME              MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
		sr0                11:0    1 1024M  0 rom
		nvme0n1           259:0    0   24G  0 disk
		├─nvme0n1p1       259:1    0  600M  0 part /boot/efi
		├─nvme0n1p2       259:2    0    1G  0 part /boot
		└─nvme0n1p3       259:3    0 22.4G  0 part
		  ├─cs_node1-root 253:0    0   20G  0 lvm  /
		  └─cs_node1-swap 253:1    0  2.4G  0 lvm  [SWAP]
		nvme0n2           259:4    0    2T  0 disk
		nvme0n3           259:5    0   10G  0 disk


  
pvcreate /dev/nvme0n2
pvcreate /dev/nvme0n3
vgcreate vg-vdo0 /dev/nvme0n2 /dev/nvme0n3





cat <<EOF > /etc/lvm/profile/vdo_create.profile
allocation {
	vdo_use_compression=1
	vdo_use_deduplication=1
	vdo_use_metadata_hints=1
	vdo_minimum_io_size=4096
	vdo_block_map_cache_size_mb=1024
	vdo_block_map_period=16380
	vdo_check_point_frequency=0
	vdo_use_sparse_index=0
	vdo_index_memory_size_mb=256
	vdo_slab_size_mb=2048
	vdo_ack_threads=1
	vdo_bio_threads=8
	vdo_bio_rotation=64
	vdo_cpu_threads=2
	vdo_hash_zone_threads=1
	vdo_logical_threads=4
	vdo_physical_threads=2
	vdo_write_policy="auto"
	vdo_max_discard=1
}
EOF



lvcreate --type vdo -n lv-vdo0 -l 100%FREE -V 8TB --metadataprofile vdo_create vg-vdo0 /dev/nvme0n2

			The VDO volume can address 1 TB in 1022 data slabs, each 2 GB.
			It can grow to address at most 16 TB of physical storage in 8192 slabs.
			If a larger maximum size might be needed, use bigger slabs.
		  Logical volume "lv-vdo0" created.


lvcreate --type cache-pool -n lv-vdo0cache -l 100%FREE vg-vdo0 /dev/nvme0n3

lvconvert --cache --cachepool vg-vdo0/lv-vdo0cache vg-vdo0/lv-vdo0
		Do you want wipe existing metadata of cache pool vg-vdo0/lv-vdo0cache? [y/n]: y
		  Logical volume vg-vdo0/lv-vdo0 is now cached.



mkfs.xfs -K /dev/vg-vdo0/lv-vdo0
			meta-data=/dev/vg-vdo0/lv-vdo0   isize=512    agcount=32, agsize=67108864 blks
					 =                       sectsz=4096  attr=2, projid32bit=1
					 =                       crc=1        finobt=1, sparse=1, rmapbt=0
					 =                       reflink=1    bigtime=1 inobtcount=1 nrext64=0
			data     =                       bsize=4096   blocks=2147483648, imaxpct=5
					 =                       sunit=16     swidth=16 blks
			naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
			log      =internal log           bsize=4096   blocks=521728, version=2
					 =                       sectsz=4096  sunit=1 blks, lazy-count=1
			realtime =none                   extsz=4096   blocks=0, rtextents=0




/dev/vg-vdo0/lv-vdo0 /mnt/vdo0 xfs defaults 0 0

		https://www.systutorials.com/docs/linux/man/5-xfs/
		discard|nodiscard
			Enable/disable the issuing of commands to let the block device reclaim space freed by the filesystem. This is useful for SSD devices, thinly provisioned LUNs and virtual machine images, but may have a performance impact.

			Note: It is currently recommended that you use the fstrim application to discard unused blocks rather than the discard mount option because the performance impact of this option is quite severe. For this reason, nodiscard is the default.
			
		https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/deduplicating_and_compressing_logical_volumes_on_rhel/trim-options-on-an-lvm-vdo-volume_deduplicating-and-compressing-logical-volumes-on-rhel
		Note that it is currently recommended to use fstrim application to discard unused blocks rather than the discard mount option because the performance impact of this option can be quite severe. For this reason, nodiscard is the default.
		

#remove cache
lvconvert --uncache vg-vdo0/lv-vdo0



###########################################################
