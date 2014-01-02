# RelatedNodes, an alternative to Puppet's exported resources

require 'cgi'
require 'digest/sha1'
require 'fileutils'
require 'logger'
require 'set'
require 'yaml'

class RelatedNodes < Logger::Application

  include FileUtils

  # The RelatedNodes service speaks YAML.  This is only preferable to JSON
  # because Ruby speaks YAML but not JSON natively.
  HEADERS = {"Content-Type" => "application/x-yaml"}

  RE_REFERENCE = /^([A-Z][0-9a-z_-]*(?:::[A-Z][0-9a-z_-]+)*)\[([^\]]+)\]$/
  RE_TYPE = /^([A-Z][0-9a-z_-]*(?:::[A-Z][0-9a-z_-]+)*)$/

  # Initialize the RelatedNodes service directory structure.
  def initialize(dirname)
    super "RelatedNodes"
    mkdir_p dirname
    cd dirname
    mkdir "catalogs" rescue Errno::EEXIST
    mkdir "index" rescue Errno::EEXIST
  end

  # Implement the Rack contract by dispatching to other methods.
  def call(env)
    case env["REQUEST_METHOD"]
    when "DELETE" then delete(env)
    when "GET" then get(env)
    when "PUT" then put(env)
    else [405, HEADERS, ["---"]]
    end
  end

  # DELETE /#{hostname}
  def delete(env)
    hostname = env["PATH_INFO"][1..-1]
    return [400, HEADERS, ["---"]] unless hostname =~ /^[0-9a-z.-]+$/

    # Update the inverted index.
    File.open "catalogs/#{hostname}" do |f|
      catalog_references f do |reference|
        unindex hostname, reference
      end
      f.rewind
      catalog_types f do |type|
        unindex hostname, type
      end
    end

    # No need to save the catalog for later, anymore.
    log INFO, "rm -f catalogs/#{hostname}"
    rm_f "catalogs/#{hostname}"

    [204, {}, []]
  rescue Errno::ENOENT, NoMethodError
    [404, HEADERS, ["---"]]
  end

  # GET /?resource=#{reference}
  # GET /?parameters=1&resource=#{reference}
  def get(env)
    query = CGI.parse(env["QUERY_STRING"]) # FIXME Sanitize.
    reference = query["resource"][0]
    title = case reference
    when RE_REFERENCE then $2
    when RE_TYPE then nil
    else return [400, HEADERS, ["---"]]
    end

    # Get the list of hostnames that manage this resource.
    sha = Digest::SHA1.hexdigest(reference)
    hostnames = Dir.entries(
      "index/#{sha[0..1]}/#{sha[2..-1]}"
    ).reject do |filename|
      filename.start_with?(".")
    end

    io = StringIO.new

    # If parameters were requested, respond with a hash.
    if query["parameters"][0]
      hash = {}
      hostnames.each do |hostname|
        File.open("catalogs/#{hostname}") do |f|
          if title
            catalog_resources f do |r, p|
              if reference == r
                p.delete :name
                hash[title.end_with?(":") ? "#{title}#{hostname}" : title] = p
                break
              end
            end
          else
            catalog_resources f do |r, p|
              if r =~ RE_REFERENCE && reference == $1
                t = $2
                p.delete :name
                hash[t.end_with?(":") ? "#{t}#{hostname}" : t] = p
              end
            end
          end
        end
      end
      YAML.dump(hash, io)

    # Or respond with the list of hostnames.
    else
      YAML.dump(hostnames, io)

    end

    io.rewind

    [200, HEADERS, io]
  rescue Errno::ENOENT
    [404, HEADERS, ["---"]]
  end

  # PUT /#{hostname}
  def put(env)
    hostname = env["PATH_INFO"][1..-1]
    return [400, HEADERS, ["---"]] unless hostname =~ /^[0-9a-z.-]+$/

    # Recall the previously-uploaded catalog.
    references0 = begin
      catalog_references(File.open("catalogs/#{hostname}"))
    rescue Errno::ENOENT, NoMethodError
      []
    end
    types0 = begin
      catalog_types(File.open("catalogs/#{hostname}"))
    rescue Errno::ENOENT, NoMethodError
      []
    end

    # Update the inverted index.
    references1 = catalog_references(env["rack.input"])
    (references1 - references0).each do |reference|
      index hostname, reference
    end
    (references0 - references1).each do |reference|
      unindex hostname, reference
    end
    env["rack.input"].rewind
    types1 = catalog_types(env["rack.input"])
    (types1 - types0).each do |type|
      index hostname, type
    end
    (types0 - types1).each do |type|
      unindex hostname, type
    end

    # Save this catalog for later.
    env["rack.input"].rewind
    File.open("catalogs/#{hostname}", "w") do |f|
      copy_stream env["rack.input"], f
    end

    [204, {}, []]
  end

private

  # If a block is given, yield each resource reference and parameter hash pair
  # in this catalog.
  #
  # Otherwise, return a hash of resource references to their parameter hashes.
  def catalog_resources(io)
    if block_given?
      YAML.load(io).ivars["resource_table"].each_value do |resource|
        yield resource.ivars["reference"], resource.ivars["parameters"]
      end
    else
      hash = {}
      catalog_resources io, &hash.method(:[]=)
      hash
    end
  end

  # If a block is given, yield each resource reference in this catalog.
  #
  # Otherwise, return an array of resource references.
  def catalog_references(io)
    if block_given?
      YAML.load(io).ivars["resource_table"].each_value do |resource|
        if resource.ivars["reference"]
          yield resource.ivars["reference"]
        else
          yield "#{resource.ivars["type"]}[#{resource.ivars["title"]}]"
        end
      end
    else
      array = []
      catalog_references io, &array.method(:<<)
      array
    end
  end

  # If a block is given, yield each distinct type in this catalog.
  #
  # Otherwise, return an array of distinct type names.
  def catalog_types(io)
    set = Set.new
    YAML.load(io).ivars["resource_table"].each_value do |resource|
      set.add resource.ivars["type"]
    end
    if block_given?
      set.each do |type|
        yield type
      end
    else
      set.to_a
    end
  end

  # Add record of a host having a resource to the inverted index.
  def index(hostname, reference)
    sha = Digest::SHA1.hexdigest(reference)
    mkdir_p "index/#{sha[0..1]}/#{sha[2..-1]}"
    log INFO, "touch index/#{sha[0..1]}/#{sha[2..-1]}/#{hostname}"
    touch "index/#{sha[0..1]}/#{sha[2..-1]}/#{hostname}"
  end

  # Remove record of a host having a resource from the inverted index.
  def unindex(hostname, reference)
    sha = Digest::SHA1.hexdigest(reference)
    log INFO, "rm -f index/#{sha[0..1]}/#{sha[2..-1]}/#{hostname}"
    rm_f "index/#{sha[0..1]}/#{sha[2..-1]}/#{hostname}"
    rmdir "index/#{sha[0..1]}/#{sha[2..-1]}" rescue Errno::ENOENT
    rmdir "index/#{sha[0..1]}" rescue Errno::ENOENT
  rescue Errno::ENOTEMPTY
  end

end
