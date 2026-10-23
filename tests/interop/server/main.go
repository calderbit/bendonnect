// Reference server for bendonnect.test.v1.TestService, built on connect-go.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

const svc = "/bendonnect.test.v1.TestService/"

func main() {
	addr := flag.String("addr", "127.0.0.1:8788", "listen address")
	flag.Parse()

	mux := http.NewServeMux()
	mux.Handle(svc+"Echo", connect.NewUnaryHandler(svc+"Echo", echo,
		connect.WithIdempotency(connect.IdempotencyNoSideEffects)))
	mux.Handle(svc+"Fail", connect.NewUnaryHandler(svc+"Fail", fail))
	mux.Handle(svc+"Count", connect.NewServerStreamHandler(svc+"Count", count))
	mux.Handle(svc+"Concat", connect.NewClientStreamHandler(svc+"Concat", concat))

	var protos http.Protocols
	protos.SetHTTP1(true)
	protos.SetUnencryptedHTTP2(true) // h2c
	srv := &http.Server{Addr: *addr, Handler: mux, Protocols: &protos}
	log.Printf("reference server listening on http://%s", *addr)
	log.Fatal(srv.ListenAndServe())
}

func echo(_ context.Context, req *connect.Request[wrapperspb.StringValue]) (*connect.Response[wrapperspb.StringValue], error) {
	res := connect.NewResponse(wrapperspb.String(req.Msg.GetValue()))
	if v := req.Header().Get("x-test"); v != "" {
		res.Header().Set("x-echo", v)
	}
	res.Trailer().Set("x-trail", "done")
	return res, nil
}

func fail(_ context.Context, req *connect.Request[wrapperspb.StringValue]) (*connect.Response[wrapperspb.StringValue], error) {
	var code connect.Code
	if err := code.UnmarshalText([]byte(req.Msg.GetValue())); err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("bad code name %q", req.Msg.GetValue()))
	}
	cerr := connect.NewError(code, errors.New("requested failure"))
	d, err := connect.NewErrorDetail(wrapperspb.String("detail"))
	if err != nil {
		return nil, err
	}
	cerr.AddDetail(d)
	return nil, cerr
}

func count(_ context.Context, req *connect.Request[wrapperspb.UInt32Value], st *connect.ServerStream[wrapperspb.StringValue]) error {
	n := req.Msg.GetValue()
	st.ResponseTrailer().Set("x-count", strconv.FormatUint(uint64(n), 10))
	if n == 0 {
		return connect.NewError(connect.CodeOutOfRange, errors.New("n must be > 0"))
	}
	for i := uint32(1); i <= n; i++ {
		if err := st.Send(wrapperspb.String(strconv.FormatUint(uint64(i), 10))); err != nil {
			return err
		}
	}
	return nil
}

func concat(_ context.Context, st *connect.ClientStream[wrapperspb.StringValue]) (*connect.Response[wrapperspb.StringValue], error) {
	var parts []string
	for st.Receive() {
		parts = append(parts, st.Msg().GetValue())
	}
	if err := st.Err(); err != nil {
		return nil, err
	}
	return connect.NewResponse(wrapperspb.String(strings.Join(parts, " "))), nil
}
