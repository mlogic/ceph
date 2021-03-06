#!/bin/bash
#
# Copyright (C) 2014 Cloudwatt <libre.licensing@cloudwatt.com>
# Copyright (C) 2014, 2015 Red Hat <contact@redhat.com>
#
# Author: Loic Dachary <loic@dachary.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU Library Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Library Public License for more details.
#
source ../qa/workunits/ceph-helpers.sh

function run() {
    local dir=$1
    shift

    export CEPH_MON="127.0.0.1:7102"
    export CEPH_ARGS
    CEPH_ARGS+="--fsid=$(uuidgen) --auth-supported=none "
    CEPH_ARGS+="--mon-host=$CEPH_MON "

    local funcs=${@:-$(set | sed -n -e 's/^\(TEST_[0-9a-z_]*\) .*/\1/p')}
    for func in $funcs ; do
        $func $dir || return 1
    done
}

TEST_POOL=rbd

function TEST_osd_pool_get_set() {
    local dir=$1

    setup $dir || return 1
    run_mon $dir a || return 1

    local flag
    for flag in hashpspool nodelete nopgchange nosizechange; do
        if [ $flag = hashpspool ]; then
	    ./ceph osd dump | grep 'pool ' | grep $flag || return 1
        else
	    ! ./ceph osd dump | grep 'pool ' | grep $flag || return 1
        fi
	./ceph osd pool set $TEST_POOL $flag 0 || return 1
	! ./ceph osd dump | grep 'pool ' | grep $flag || return 1
	./ceph osd pool set $TEST_POOL $flag 1 || return 1
	./ceph osd dump | grep 'pool ' | grep $flag || return 1
	./ceph osd pool set $TEST_POOL $flag false || return 1
	! ./ceph osd dump | grep 'pool ' | grep $flag || return 1
	./ceph osd pool set $TEST_POOL $flag false || return 1
        # check that setting false twice does not toggle to true (bug)
	! ./ceph osd dump | grep 'pool ' | grep $flag || return 1
	./ceph osd pool set $TEST_POOL $flag true || return 1
	./ceph osd dump | grep 'pool ' | grep $flag || return 1
	# cleanup
	./ceph osd pool set $TEST_POOL $flag 0 || return 1
    done

    local size=$(./ceph osd pool get $TEST_POOL size|awk '{print $2}')
    local min_size=$(./ceph osd pool get $TEST_POOL min_size|awk '{print $2}')
    #replicated pool size restrict in 1 and 10
    ! ./ceph osd pool set $TEST_POOL 11 || return 1
    #replicated pool min_size must be between in 1 and size
    ! ./ceph osd pool set $TEST_POOL min_size $(expr $size + 1) || return 1
    ! ./ceph osd pool set $TEST_POOL min_size 0 || return 1

    local ecpool=erasepool
    ./ceph osd pool create $ecpool 12 12 erasure default || return 1
    #erasue pool size=k+m, min_size=k
    local size=$(./ceph osd pool get $ecpool size|awk '{print $2}')
    local k=$(./ceph osd pool get $ecpool min_size|awk '{print $2}')
    #erasure pool size can't change
    ! ./ceph osd pool set $ecpool size  $(expr $size + 1) || return 1
    #erasure pool min_size must be between in k and size
    ./ceph osd pool set $ecpool min_size $(expr $k + 1) || return 1
    ! ./ceph osd pool set $ecpool min_size $(expr $k - 1) || return 1
    ! ./ceph osd pool set $ecpool min_size $(expr $size + 1) || return 1

    teardown $dir || return 1
}

function TEST_mon_add_to_single_mon() {
    local dir=$1

    fsid=$(uuidgen)
    MONA=127.0.0.1:7117
    MONB=127.0.0.1:7118
    CEPH_ARGS_orig=$CEPH_ARGS
    CEPH_ARGS="--fsid=$fsid --auth-supported=none "
    CEPH_ARGS+="--mon-initial-members=a "
    CEPH_ARGS+="--mon-host=$MONA "

    setup $dir || return 1
    run_mon $dir a --public-addr $MONA || return 1
    # wait for the quorum
    timeout 120 ceph -s > /dev/null || return 1
    run_mon $dir b --public-addr $MONB || return 1
    teardown $dir || return 1

    setup $dir || return 1
    run_mon $dir a --public-addr $MONA || return 1
    # without the fix of #5454, mon.a will assert failure at seeing the MMonJoin
    # from mon.b
    run_mon $dir b --public-addr $MONB || return 1
    # wait for the quorum
    timeout 120 ceph -s > /dev/null || return 1
    local num_mons
    num_mons=$(ceph mon dump --format=xml 2>/dev/null | $XMLSTARLET sel -t -v "count(//mons/mon)") || return 1
    [ $num_mons == 2 ] || return 1
    # no reason to take more than 120 secs to get this submitted
    timeout 120 ceph mon add b $MONB || return 1
    teardown $dir || return 1
}

main misc "$@"

# Local Variables:
# compile-command: "cd ../.. ; make -j4 && test/mon/misc.sh"
# End:
