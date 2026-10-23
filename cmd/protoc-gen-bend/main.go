// protoc-gen-bend generates Bend 2 code (messages, proto binary and proto3 JSON codecs,
// Connect service stubs) for Bendonnect. See README.md in this directory.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path"

	"google.golang.org/protobuf/compiler/protogen"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/descriptorpb"
	"google.golang.org/protobuf/types/pluginpb"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "protoc-gen-bend: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	in, err := io.ReadAll(os.Stdin)
	if err != nil {
		return err
	}
	req := &pluginpb.CodeGeneratorRequest{}
	if err := proto.Unmarshal(in, req); err != nil {
		return err
	}
	// protogen insists on a Go import path for every file; Bend has no use for one, so
	// invent a placeholder when go_package is absent.
	for _, fd := range req.ProtoFile {
		if fd.GetOptions().GetGoPackage() == "" {
			if fd.Options == nil {
				fd.Options = &descriptorpb.FileOptions{}
			}
			fd.Options.GoPackage = proto.String("bendonnect/unused/" + path.Dir(fd.GetName()))
		}
	}
	var flags flag.FlagSet
	runtime := flags.String("runtime", "", "path to the Bendonnect root, relative to the output directory (e.g. ../..)")
	gen, err := protogen.Options{ParamFunc: flags.Set}.New(req)
	if err != nil {
		return err
	}
	gen.SupportedFeatures = uint64(pluginpb.CodeGeneratorResponse_FEATURE_PROTO3_OPTIONAL)
	for _, f := range gen.Files {
		if !f.Generate {
			continue
		}
		if err := generate(gen, f, *runtime); err != nil {
			gen.Error(fmt.Errorf("%s: %w", f.Desc.Path(), err))
			break
		}
	}
	resp := gen.Response()
	if resp.Error != nil {
		fmt.Fprintf(os.Stderr, "protoc-gen-bend: %s\n", *resp.Error)
	}
	out, err := proto.Marshal(resp)
	if err != nil {
		return err
	}
	_, err = os.Stdout.Write(out)
	return err
}
