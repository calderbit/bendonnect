// Calls the Bend GreetService (examples/greet/server.bend) with connect-go, over both the
// proto and the json codecs: unary (POST and GET), server stream, client stream.
//
//	go run . -url http://127.0.0.1:8787
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"bendonette/greet/goclient/greetv1"
	"bendonette/greet/goclient/greetv1/greetv1connect"

	"connectrpc.com/connect"
)

var failed bool

func check(name string, err error) {
	if err != nil {
		failed = true
		fmt.Printf("FAIL %s: %v\n", name, err)
		return
	}
	fmt.Printf("PASS %s\n", name)
}

func expect(name, got, want string) {
	if got != want {
		check(name, fmt.Errorf("got %q, want %q", got, want))
		return
	}
	check(name, nil)
}

func run(ctx context.Context, label string, client greetv1connect.GreetServiceClient) {
	// unary
	res, err := client.Greet(ctx, connect.NewRequest(&greetv1.GreetRequest{Name: "Ada"}))
	check(label+"/greet", err)
	if err == nil {
		expect(label+"/greet/body", res.Msg.GetGreeting(), "Hello, Ada!")
	}
	// unary with the default (zero) message
	res, err = client.Greet(ctx, connect.NewRequest(&greetv1.GreetRequest{}))
	check(label+"/greet-empty", err)
	if err == nil {
		expect(label+"/greet-empty/body", res.Msg.GetGreeting(), "Hello, !")
	}
	// unicode survives both codecs
	res, err = client.Greet(ctx, connect.NewRequest(&greetv1.GreetRequest{Name: "世界 \U0001F600"}))
	check(label+"/greet-unicode", err)
	if err == nil {
		expect(label+"/greet-unicode/body", res.Msg.GetGreeting(), "Hello, 世界 \U0001F600!")
	}
	// server stream
	stream, err := client.GreetMany(ctx, connect.NewRequest(&greetv1.GreetRequest{Name: "Grace"}))
	check(label+"/greet_many/open", err)
	if err == nil {
		var got []string
		for stream.Receive() {
			got = append(got, stream.Msg().GetGreeting())
		}
		check(label+"/greet_many/end", stream.Err())
		expect(label+"/greet_many/body", strings.Join(got, "|"), "Hello, Grace (1)!|Hello, Grace (2)!|Hello, Grace (3)!")
		stream.Close()
	}
	// client stream
	cs := client.GreetAll(ctx)
	for _, n := range []string{"Ada", "Grace", "Edsger"} {
		if err := cs.Send(&greetv1.GreetRequest{Name: n}); err != nil && !errors.Is(err, io.EOF) {
			check(label+"/greet_all/send", err)
		}
	}
	all, err := cs.CloseAndReceive()
	check(label+"/greet_all", err)
	if err == nil {
		expect(label+"/greet_all/body", all.Msg.GetGreeting(), "Hello, Ada, Grace, Edsger!")
	}
}

func main() {
	url := flag.String("url", "http://127.0.0.1:8787", "server base URL")
	flag.Parse()
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	hc := &http.Client{}
	run(ctx, "proto", greetv1connect.NewGreetServiceClient(hc, *url))
	run(ctx, "json", greetv1connect.NewGreetServiceClient(hc, *url, connect.WithProtoJSON()))
	// Greet is NO_SIDE_EFFECTS: connect-go may call it with GET.
	for label, opts := range map[string][]connect.ClientOption{
		"get-proto": {connect.WithHTTPGet()},
		"get-json":  {connect.WithHTTPGet(), connect.WithProtoJSON()},
	} {
		c := greetv1connect.NewGreetServiceClient(hc, *url, opts...)
		res, err := c.Greet(ctx, connect.NewRequest(&greetv1.GreetRequest{Name: "Ada"}))
		check(label+"/greet", err)
		if err == nil {
			expect(label+"/greet/body", res.Msg.GetGreeting(), "Hello, Ada!")
		}
	}
	// unimplemented procedure -> 404 / unimplemented
	if failed {
		fmt.Println("SUMMARY: FAIL")
		os.Exit(1)
	}
	fmt.Println("SUMMARY: ok")
}
