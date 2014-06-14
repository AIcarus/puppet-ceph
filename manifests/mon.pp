# Configure a ceph mon
#
# == Name
#   This resource's name is the mon's id and must be numeric.
# == Parameters
# [*fsid*] The cluster's fsid.
#   Mandatory. Get one with `uuidgen -r`.
#
# [*mon_secret*] The cluster's mon's secret key.
#   Mandatory. Get one with `ceph-authtool /dev/stdout --name=mon. --gen-key`.
#
# [*mon_port*] The mon's port.
#   Optional. Defaults to 6789.
#
# [*mon_addr*] The mon's address.
#   Optional. Defaults to the $ipaddress fact.
#
# == Dependencies
#
# none
#
# == Authors
#
#  François Charlier francois.charlier@enovance.com
#
# == Copyright
#
# Copyright 2012 eNovance <licensing@enovance.com>
#
define ceph::mon (
  $monitor_secret,
  $mon_port = 6789,
  $mon_addr = $ipaddress,
  $mon_dev = undef
) {

  include 'ceph::package'
  include 'ceph::conf'
  include 'ceph::params'

  $mon_data_real = regsubst($::ceph::conf::mon_data, '\$id', $name)

  file { $mon_data_real:
    ensure  => 'directory',
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    require => Package['ceph']
  }

  if $mon_dev {
    
    $mon_devname = regsubst($mon_dev, '.*/', '')

    exec { "mkfs_${mon_devname}-${name}":
      command => "mkfs.xfs -f -d agcount=${::processorcount} -i size=2048 -b size=4096 -l size=1024m -n size=64k ${mon_dev}",
      unless  => "xfs_admin -l ${mon_dev}",
      require => [Package['xfsprogs']],
    }

    mount { $mon_data_real:
      ensure  => mounted,
      device  => "${mon_dev}",
      atboot  => true,
      fstype  => 'xfs',
      options => 'rw,noatime,inode64,logbsize=256k,delaylog',
      pass    => 2,
      before => Exec["ceph-mon-keyring-${name}"],
      require => [
        Exec["mkfs_${mon_devname}-${name}"],
        File[$mon_data_real]
      ],
    }
  }

  ceph::conf::mon { $name:
    mon_addr => $mon_addr,
    mon_port => $mon_port,
  }

  #FIXME: monitor_secret will appear in "ps" output …
  exec { "ceph-mon-keyring-${name}":
    command => "ceph-authtool /var/lib/ceph/tmp/keyring.mon.${name} \
--create-keyring \
--name=mon. \
--add-key='${monitor_secret}' \
--cap mon 'allow *'",
    creates => "/var/lib/ceph/tmp/keyring.mon.${name}",
    logoutput => true,
    before  => Exec["ceph-mon-mkfs-${name}"],
    require => [
      File["/var/lib/ceph/tmp"],
      Package['ceph']],
  }

  exec { "ceph-mon-mkfs-${name}":
    command => "ceph-mon --mkfs -i ${name} \
--keyring /var/lib/ceph/tmp/keyring.mon.${name}",
    creates => "${mon_data_real}/keyring",
    logoutput => true,
    require => [
      Package['ceph'],
      Concat['/etc/ceph/ceph.conf'],
      File[$mon_data_real]
    ],
  }

  service { "ceph-mon.${name}":
    ensure   => running,
    provider => $::ceph::params::service_provider,
    start    => "service ceph start mon.${name}",
    stop     => "service ceph stop mon.${name}",
    status   => "service ceph status mon.${name}",
    require  => Exec["ceph-mon-mkfs-${name}"],
  }

  exec { "ceph-admin-key-${name}":
    command => "ceph-authtool /etc/ceph/keyring \
--create-keyring \
--name=client.admin \
--add-key \
$(ceph --name mon. --keyring ${mon_data_real}/keyring \
  auth get-or-create-key client.admin \
    mon 'allow *' \
    osd 'allow *' \
    mds allow)",
    creates => '/etc/ceph/keyring',
    require => Package['ceph'],
    onlyif  => "ceph --admin-daemon /var/run/ceph/ceph-mon.${name}.asok \
mon_status|egrep -v '\"state\": \"(leader|peon)\"'",
  }

}
