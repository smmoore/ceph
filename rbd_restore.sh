#!/bin/sh
#
# AUTHORS
# Shawn Moore <smmoore@catawba.edu>
# Rodney Rymer <rrr@catawba.edu>
#
#
# REQUIREMENTS
# GNU Awk (gawk)
#
#
# NOTES
# This utility assumes one copy of all object files needed to construct the rbd
# are located in the present working direcory at the time of execution.  
# For example all the rb.0.1032.5e69c215.* files.
#
# When listing the "RBD_SIZE_IN_BYTES", be sure you list the full potential size, 
# not just what it appears to be. If you do not know the true size of the rbd,
# you can input a size in bytes that you know is larger than the disk could be
# and it will be a large sparse file with un-partioned space at the end of the
# disk.  In our tests, this doesn't occupy any more space/objects in the cluster
# but the rbd could be resized from within the rbd (VM) to grow.  Once you bring
# it up and are able to find the true size, you can resize with "rbd resize ..".
#
# To obtain needed utility input information if not already known run:
# rbd info RBD
#
# To find needed files we run the following command on all nodes that might have
# copies of the rbd objects:
# find /${CEPH} -type f -name rb.0.1032.5e69c215.*
# Then copy the files to a single location from all nodes.  If using btrfs be
# sure to pay attention to the btrfs snapshots that ceph takes on it's own.
# You may want the "current" or one of the "snaps".
#
# We are actually taking our own btrfs snapshots cluster osd wide at the same
# time with parallel ssh and then using "btrfs subvolume find-new" command to
# merge them all together for disaster recovery and also outside of ceph rbd
# versioning.
#
# Hopefully once the btrfs send/recv functionality is stable we can switch to it.
#
#
# This utility works for us but may not for you.  Always test with non-critical
# data first.
#

# Rados object size
obj_size=4194304

# DD bs value
rebuild_block_size=512

rbd="${1}"
base="${2}"
rbd_size="${3}"
if [ "${1}" = "-h" -o "${1}" = "--help" -o "${rbd}" = "" -o "${base}" = "" -o "${rbd_size}" = "" ]; then
  echo "USAGE: $(echo ${0} | awk -F/ '{print $NF}') RESTORE_RBD BLOCK_PREFIX RBD_SIZE_IN_BYTES"
  exit 1
fi
base_files=$(ls -1 ${base}.* 2>/dev/null | wc -l | awk '{print $1}')
if [ ${base_files} -lt 1 ]; then
  echo "COULD NOT FIND FILES FOR ${base} IN $(pwd)"
  exit
fi

# Create full size sparse image.  Could use truncate, but wanted
# as few required files and dd what a must.
dd if=/dev/zero of=${rbd} bs=1 count=0 seek=${rbd_size} 2>/dev/null

for file_name in $(ls -1 ${base}.* 2>/dev/null); do
  seek_loc=$(echo ${file_name} | awk -F_ '{print $1}' | awk -v os=${obj_size} -v rs=${rebuild_block_size} -F. '{print os*strtonum("0x" $NF)/rs}')
  dd conv=notrunc if=${file_name} of=${rbd} seek=${seek_loc} bs=${rebuild_block_size} 2>/dev/null
done
