# these parameters need to be accessed from several locations and
# should be considered to be constant
class ceph::params {

  case $::osfamily {
    'Debian': {
      case $::operatingsystem {
        'Ubuntu': {
          $service_provider = 'init'
        }
        default: {
          $service_provider = undef
        }
      }
    }

    'RedHat': {
      case $::operatingsystem {
        'CentOS': {
          $service_provider = 'redhat'
        }
        default: {
          $service_provider = undef
        }
      } 
    }
    
  }
}
