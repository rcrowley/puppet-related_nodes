file { "/tmp/puppet-related_nodes.txt":
  content => "THIS IS ONLY A TEST\n",
  ensure => present,
  group => "root",
  mode => 0644,
  owner => "root",
}
