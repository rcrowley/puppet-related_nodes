require 'puppet/indirector/catalog/compiler'
require 'puppet/parameter/value'
require 'puppet/resource/catalog'

# Suppress Proc objects in Puppet::Parameter::Value YAML.
# <http://projects.puppetlabs.com/issues/4506>
class Puppet::Parameter::Value
  def to_yaml_properties
    [:@aliases, :@method, :@name]
  end
end

# Write the catalog to disk even if Puppet was invoked via `puppet apply`.
# This is required in order to use RelatedNodes without a Puppet master.
Puppet::Resource::Catalog.indirection.cache_class = :yaml

class Puppet::Resource::Catalog::MasterlessCompiler < Puppet::Resource::Catalog::Compiler
end
