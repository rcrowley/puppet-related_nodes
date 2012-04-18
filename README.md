RelatedNodes, an alternative to Puppet's exported resources
===========================================================

Many of my uses of Puppet's exported resources are hacks trying to get
a list of hostnames of interest.

I've had decent success with the following pattern: hosts that provide
some interesting service export `File["/etc/peers/$fqdn"]` tagged with
the service name; other hosts collect these resources to learn the
topology of the greater system.  This puts unnecessary burden on the
services themselves, which frequently have to post-process these files
to generate a useful configuration.

RelatedNodes is a Rack web service that provides the same data via a
friendlier API.  It is implemented as web service that accepts uploads
of Puppet catalogs and maintains an inverted index of resources to
hostnames and a Puppet function that queries that inverted index.

Usage
-----

Run the RelatedNodes server:

    RUBYLIB="lib" rackup -p"8141"

Push Puppet catalogs to it after Puppet runs:

    curl -T"/var/lib/puppet/client_yaml/$(hostname --fqdn)/catalog.yaml" \
         -X"PUT" -sv "http://localhost:8141/$(hostname --fqdn)"

Ask it questions from Puppet:

    $hostnames = related_nodes(Package["nginx"])

Use empty defined types to signal your intentions to other nodes:

    define sentinel {}
    sentinel { "api": }

	$related_nodes = "http://localhost:8141"
    $api_hostnames = related_nodes(Sentinel["api"])

Pass `true` as the second argument to `related_nodes` to get back a hash
suitable for use with the `create_resources` function:

    create_resources "nagios_service",
        related_nodes(Sentinel::Nagios_service["api"], true)

If a resource's title ends in `:`, the hostname that created it will be
appended to the title returned for use with `create_resources`.

`DELETE /#{hostname}`
---------------------

Remove resources managed on this host from the inverted index.  Resources
that are only managed on this host will also be removed from the index.

    curl -X"DELETE" -sv "http://localhost:8141/$(hostname --fqdn)"

`GET /?resource=#{reference}` or `GET /?parameters=1&resource=#{reference}`
---------------------------------------------------------------------------

In the first form, respond with the list of hostnames that manage this
resource or 404 if no hosts manage this resource.

In the second form, respond with a hash suitable for use with the
`create_resources` function.

For example, `GET /?resource=Package[nginx]` responds with a list of
hostnames that have installed Nginx.

    curl -X"GET" -sv "http://localhost:8141/?resource=Package%5bnginx%5d"

`PUT /#{hostname}`
------------------

Update the inverted index to reflect the supplied Puppet catalog.

If the host has uploaded a catalog before, a differential approach is
taken: resources in the uploaded catalog but not the stored catalog are
added to the inverted index; resources in the stored catalog but not
the uploaded catalog are removed from the index.  At the end, the
uploaded catalog is stored to be used when a later catalog is uploaded.

If the host has not uploaded a catalog before, the stored catalog is
treated as if it were empty.

    curl -T"/var/lib/puppet/client_yaml/$(hostname --fqdn)/catalog.yaml" \
         -X"PUT" -sv "http://localhost:8141/$(hostname --fqdn)"

If you're running Puppet via `puppet apply ...`, set `catalog_terminus` to
`masterless_compiler` on the command-line or in `puppet.conf` to force Puppet
to write the catalog to disk.
