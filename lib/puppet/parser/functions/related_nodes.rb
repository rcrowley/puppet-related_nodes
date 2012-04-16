# RelatedNodes, an alternative to Puppet's exported resources

require 'cgi'
require 'net/http'
require 'net/https'
require 'puppet'
require 'puppet/parser/functions'
require 'uri'
require 'yaml'

# Return the list of hostnames that manage this resource, which may be empty,
# or the resources themselves if the second argument is true.
Puppet::Parser::Functions.newfunction :related_nodes, :type => :rvalue do |args|

  # The RelatedNodes service is on the Puppet master at port 8141 over SSL
  # by default but may be overridden by setting the $related_nodes variable.
  uri = URI.parse(lookupvar("related_nodes"))
  uri.host ||= lookupvar("settings::server")
  uri.port ||= 8141
  uri.scheme ||= "http"

  # Setup an HTTP client for the RelatedNodes service.
  http = Net::HTTP.new(uri.host, uri.port)
  if "https" == uri.scheme
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE # FIXME
  end

  # Return the list of hostnames that manage this resource, which may be empty,
  # or the resources themselves if the second argument is true.
  query = {:resource => args[0]}
  query[:parameters] = 1 if args[1]
  query_string = query.map do |name, value|
    "#{CGI.escape(name.to_s)}=#{CGI.escape(value.to_s)}"
  end.join("&")
  response = http.get("/?#{query_string}")
  YAML.load(response.body)

end
