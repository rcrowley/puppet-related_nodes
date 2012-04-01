all:

run:
	RUBYLIB="lib" rackup -p"8141"

test: test-http test-puppet

test-http: test/catalog.yaml
	curl -T"test/catalog.yaml" -X"PUT" -sv "http://localhost:8141/$$(hostname --fqdn)"
	curl -X"GET" -sv "http://localhost:8141"
	curl -X"GET" -sv "http://localhost:8141/?resource=invalid"
	curl -X"GET" -sv "http://localhost:8141/?resource=File%5B%2Ftmp%2Fpuppet-related_nodes.txt%5D"
	curl -X"GET" -sv "http://localhost:8141/?parameters=1&resource=File%5B%2Ftmp%2Fpuppet-related_nodes.txt%5D"
	#curl -X"DELETE" -sv "http://localhost:8141/$$(hostname --fqdn)"

test-puppet:
	puppet apply --modulepath=".." "test/function.pp"

test/catalog.yaml: test/catalog.pp
	puppet apply --catalog_terminus="masterless_compiler" --clientyamldir="test" --modulepath=".." "$<"
	mv "test/catalog/$$(hostname --fqdn).yaml" "$@"
	rmdir "test/catalog"

.PHONY: all run test test-http test-puppet
