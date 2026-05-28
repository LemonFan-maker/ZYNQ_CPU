#!/bin/sh

say() {
    echo "[zx32-stage] $*"
}

run() {
    tag="$1"
    shift
    say "$tag begin"
    "$@"
    rc=$?
    say "$tag rc=$rc"
    return "$rc"
}

say "00 start"
run "01 true" /bin/true
run "02 pwd" /bin/pwd
run "03 mount-proc" /bin/mount -t proc proc /proc
run "04 remount-root" /bin/mount -o remount,rw /
run "05 mkdir-dev" /bin/mkdir -p /dev/pts /dev/shm /run/lock/subsys /var/run /var/log /var/lock
run "06 mount-all" /bin/mount -a
run "07 dev-fd" /bin/ln -sf /proc/self/fd /dev/fd
run "08 stdin" /bin/ln -sf /proc/self/fd/0 /dev/stdin
run "09 stdout" /bin/ln -sf /proc/self/fd/1 /dev/stdout
run "10 stderr" /bin/ln -sf /proc/self/fd/2 /dev/stderr
run "11 hostname" /bin/hostname -F /etc/hostname
run "12 ls-root" /bin/ls /
run "13 ps" /bin/ps
run "14 seedrng" /etc/init.d/S01seedrng start
run "15 syslogd" /etc/init.d/S01syslogd start
run "16 klogd" /etc/init.d/S02klogd start
run "17a find-sysctl" /bin/sh -c "find /etc/sysctl.d /usr/local/lib/sysctl.d /usr/lib/sysctl.d /lib/sysctl.d /etc/sysctl.conf -maxdepth 1 -name '*.conf' -print 2>/dev/null"
run "17b readlink" /bin/sh -c "readlink -f /etc/hostname"
run "17c logger" /bin/sh -c "echo zx32-stage logger test | /usr/bin/logger -t zx32-stage"
run "17d sysctl-one" /sbin/sysctl -n kernel.hostname
run "17e sysctl-script" /etc/init.d/S02sysctl start
run "18 modules" /etc/init.d/S11modules start
run "19 network" /etc/init.d/S40network start
run "20 crond" /etc/init.d/S50crond start
say "99 idle"

while :; do
    sleep 60
done
