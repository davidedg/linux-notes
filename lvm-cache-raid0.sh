##########################################################
# Notes on creating a dm-cache volume
##########################################################

lsblk
		NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
		sda           8:0    0 447.1G  0 disk	<<< SSD
		sdb           8:16   0 447.1G  0 disk	<<< SSD
		sdc           8:32   0   9.1T  0 disk	<<< SLOW BIG SATAe
		nvme0n1     259:0    0 476.9G  0 disk	<<< NVMe
		├─nvme0n1p1 259:1    0    30G  0 part /
		└─nvme0n1p2 259:2    0 446.9G  0 part	<<<<<<	type LVM



# wipe disks before starting
wipefs --all /dev/nvme0n1p2
wipefs --all /dev/sda
wipefs --all /dev/sdb
wipefs --all /dev/sdc


# Create PVs
pvcreate /dev/nvme0n1p2
pvcreate /dev/sda
pvcreate /dev/sdb
pvcreate /dev/sdc # 10 TB slow

# Create VG, initially only with solid state disks

vgcreate vg-data /dev/nvme0n1p2 /dev/sda /dev/sdb


# SSD raid 0 cache metadata (~1/1000th of cache size)
CACHEMETASIZE=$( pvdisplay /dev/nvme0n1p2 /dev/sda /dev/sdb | grep  "Free PE" | awk '{print $3}' | awk '{n += $1}; END{print n}' | awk '{print int($1/1000)}' )
lvcreate -n ssdcachemeta --type raid0  --stripes 3 --stripesize 4 -l $CACHEMETASIZE  vg-data /dev/nvme0n1p2 /dev/sda /dev/sdb


# SSD raid 0 cache - pick a size that will fit all the 3 ssd devices
CACHEMINSIZE=$( pvdisplay /dev/nvme0n1p2 /dev/sda /dev/sdb | grep  "Free PE" | awk '{print $3}' | awk 'NR == 1 || $3 < min {line = $0; min = $3}END{print line}' )
CACHESIZE=`expr 3 \* $CACHEMINSIZE - 512`  # 3 = num of devices - 512 ... or it kept saying no free ext...
lvcreate -n ssdcache     --type raid0  --stripes 3 --stripesize 4 -l $CACHESIZE  vg-data /dev/nvme0n1p2 /dev/sda /dev/sdb


# Assemble cache pool
lvconvert --type cache-pool --cachemode writeback --poolmetadata vg-data/ssdcachemeta vg-data/ssdcache


# Use slow disk as the base one
vgextend vg-data /dev/sdc
lvcreate -n data -l100%FREE vg-data /dev/sdc


# Assemble with CACHE disk
lvconvert --type cache --cachemode writeback  --cachepool ssdcache vg-data/data


# Final result:
lvs --all --options +devices

			  LV                              VG      Attr       LSize   Pool             Origin       Data%  Meta%  Move Log Cpy%Sync Convert Devices
			  data                            vg-data Cwi-a-C---  <9.10t [ssdcache_cpool] [data_corig] 0.01   0.40            0.00             data_corig(0)
			  [data_corig]                    vg-data owi-aoC---  <9.10t                                                                       /dev/sdc(0)
			  [lvol0_pmspare]                 vg-data ewi-------  <1.35g                                                                       /dev/sda(114246)
			  [lvol0_pmspare]                 vg-data ewi-------  <1.35g                                                                       /dev/nvme0n1p2(114246)
			  [ssdcache_cpool]                vg-data Cwi---C---  <1.31t                               0.01   0.40            0.00             ssdcache_cpool_cdata(0)
			  [ssdcache_cpool_cdata]          vg-data Cwi-aor---  <1.31t                                                                       ssdcache_cpool_cdata_rimage_0(0),ssdcache_cpool_cdata_rimage_1(0),ssdcache_cpool_cdata_rimage_2(0)
			  [ssdcache_cpool_cdata_rimage_0] vg-data iwi-aor--- 445.82g                                                                       /dev/nvme0n1p2(115)
			  [ssdcache_cpool_cdata_rimage_1] vg-data iwi-aor--- 445.82g                                                                       /dev/sda(115)
			  [ssdcache_cpool_cdata_rimage_2] vg-data iwi-aor--- 445.82g                                                                       /dev/sdb(115)
			  [ssdcache_cpool_cmeta]          vg-data ewi-aor---  <1.35g                                                                       ssdcache_cpool_cmeta_rimage_0(0),ssdcache_cpool_cmeta_rimage_1(0),ssdcache_cpool_cmeta_rimage_2(0)
			  [ssdcache_cpool_cmeta_rimage_0] vg-data iwi-aor--- 460.00m                                                                       /dev/nvme0n1p2(0)
			  [ssdcache_cpool_cmeta_rimage_1] vg-data iwi-aor--- 460.00m                                                                       /dev/sda(0)
			  [ssdcache_cpool_cmeta_rimage_2] vg-data iwi-aor--- 460.00m                                                                       /dev/sdb(0)



## if need to start over:
## lvconvert --uncache vg-data/data ## to unlink and destroy cache LVs
## vgremove vg-data



# Create FS
mkfs.xfs -K /dev/vg-data/data
			meta-data=/dev/vg-data/data      isize=512    agcount=32, agsize=76300288 blks
					 =                       sectsz=4096  attr=2, projid32bit=1
					 =                       crc=1        finobt=1, sparse=1, rmapbt=0
					 =                       reflink=1    bigtime=1 inobtcount=1 nrext64=0
			data     =                       bsize=4096   blocks=2441608192, imaxpct=5
					 =                       sunit=512    swidth=512 blks
			naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
			log      =internal log           bsize=4096   blocks=521728, version=2
					 =                       sectsz=4096  sunit=1 blks, lazy-count=1
			realtime =none                   extsz=4096   blocks=0, rtextents=0



# Append to /etc/fstab (defaults includes nodiscard)
/dev/vg-data/data /mnt/data xfs defaults 0 0

