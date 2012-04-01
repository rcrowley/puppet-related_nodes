require 'puppet/indirector/catalog/compiler'
require 'puppet/resource/catalog'

# Write the catalog to disk even if Puppet was invoked via `puppet apply`.
# This is required in order to use RelatedNodes without a Puppet master.
Puppet::Resource::Catalog.cache_class = :yaml

class Puppet::Resource::Catalog::MasterlessCompiler < Puppet::Resource::Catalog::Compiler
end
