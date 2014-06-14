$fsid = '29F46C63-4CDE-4266-BB0B-55DC0DF06A39'
$mon_secret = 'AQAW3ZpTwIbADBAA9SkhAtEs+xP0sRlNyC4Uew=='

Exec {
  path => '/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin'
}

class role_ceph (
  $fsid,
  $auth_type = 'cephx',
  $mon_host = 'ceph-mon,ceph-mon,ceph-mon',
  $mon_addr = '10.224.159.137:6789, 10.224.159.137:6790, 10.224.159.137:6791',
  $mon_init_members = 'mon.0, mon.1, mon.2',
  $pool_default_pg_num = 64,           # ref: https://ceph.com/docs/master/rados/configuration/pool-pg-config-ref/
  $pool_default_pgp_num = 64,    

) {

  class { 'ceph::conf':
    fsid            => $fsid,
    auth_type       => $auth_type,
    cluster_network => "${::network_eth0}/24",
    public_network  => "${::network_eth1}/24",
    mon_host        => $mon_host,
    mon_addr        => $mon_addr,
    mon_init_members => $mon_init_members
  }

  class{ 'ceph::yum::ceph':
    release   => 'firefly'
  }

}

define role_ceph_mon (
  $id,
  $port = 6789,
  $address = "${::network_eth1}",
  $mon_dev = undef
) {

  ceph::mon { $id:
    monitor_secret => $::mon_secret,
    mon_port       => $port,
    mon_addr       => $address,
    mon_dev        => $mon_dev
  }

}

class ceph_mon_preset {
    include 'ceph::package'
    ensure_packages( ['xfsprogs'] )

    file { "/var/lib/ceph/tmp":
      ensure  => 'directory',
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      require => Package['ceph']
    }
}

# we put 3 mon on one host
node 'ceph-mon' {
  if !empty($::ceph_admin_key) {
    @@ceph::key { 'admin':
      secret       => $::ceph_admin_key,
      keyring_path => '/etc/ceph/keyring',
    }
  }

  class { 'ceph_mon_preset': }

  class { 'role_ceph':
    fsid           => $::fsid,
    auth_type      => 'cephx',
  }
  role_ceph_mon { 'mon.0':
    id => 0,
    port => 6789,
    mon_dev => '/dev/vda4'
  }

  role_ceph_mon { 'mon.1': 
    id => 1,
    port => 6790,
    mon_dev => '/dev/vda3'
  }

  role_ceph_mon { 'mon.2':
    id => 2,
    port => 6791,
    mon_dev => undef      # use same dev as root
  }
}

# osd
node 'ceph-osd0' {
  
  class { 'role_ceph':
    fsid           => $::fsid,
    auth_type      => 'cephx',
  }

  class { 'ceph::osd' :
    public_address  => $ipaddress_eth1,
    cluster_address => $ipaddress_eth0,
  }

  ceph::osd::device { '/dev/vda4': 
    journalsize => 10000,     # ref: https://ceph.com/docs/master/rados/configuration/osd-config-ref/#journal-settings
    journal_dev => '/dev/vda3'
  }
  
}

node 'ceph-osd1' {
  
  class { 'role_ceph':
    fsid           => $::fsid,
    auth_type      => 'cephx',
  }

  class { 'ceph::osd' :
    public_address  => $ipaddress_eth1,
    cluster_address => $ipaddress_eth0,
  }

  ceph::osd::device { '/dev/vda4': 
    journalsize => 10000,
    journal_dev => '/dev/vda3'
  }

}


