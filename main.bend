# Bendonnect: the Connect RPC protocol (https://connectrpc.com/docs/protocol/) for Bend 2.
#
# BETA (0.x): the API may change between releases and only connect-go interop is tested.
# Source, docs and issues: https://github.com/calderbit/bendonnect
#
# This entry file pulls in every public module so `--publish` ships them all.
# Import the module you need by path, for example:
#   import bendonnect-rpc@0.1.0.0/src/transport/server.bend as Srv
# Generated code (protoc-gen-bend, option runtime=bendonnect-rpc@0.1.0.0) imports these paths too.
# Guide: README.md. Module contracts: src/README-api.md, src/README-codegen.md.
import Base
import ./src/code.bend as Code
import ./src/b64.bend as B64
import ./src/error.bend as E
import ./src/metadata.bend as Md
import ./src/envelope.bend as Env
import ./src/protocol.bend as P
import ./src/pb.bend as Pbr
import ./src/pbjson.bend as Pj
import ./src/transport/server.bend as Srv
import ./src/transport/client.bend as Cli
import ./src/transport/rpc.bend as Rpc

# The library version, matching its BendHub name.
def version() -> String:
  "0.1.0.0"
