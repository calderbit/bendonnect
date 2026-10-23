// Conformance-style interop client for a Connect server exposing
// bendonette.test.v1.TestService.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

const svc = "/bendonette.test.v1.TestService/"

var (
	baseURL = flag.String("url", "http://127.0.0.1:8787", "target server base URL")
	runFlag = flag.String("run", "", "only run cases whose name contains this substring")
	verbose = flag.Bool("v", false, "verbose dumps")
	lenient = flag.Bool("lenient", false, "skip cases marked [spec] (known connect-go deviations)")
)

type skip string

func (s skip) Error() string { return string(s) }

type tcase struct {
	name string
	spec bool // spec-mandated behaviour that connect-go deviates from
	fn   func(ctx context.Context) error
}

var cases []tcase

func add(name string, fn func(context.Context) error) { cases = append(cases, tcase{name: name, fn: fn}) }
func addSpec(name string, fn func(context.Context) error) {
	cases = append(cases, tcase{name: name, spec: true, fn: fn})
}

func vlog(f string, a ...any) {
	if *verbose {
		fmt.Printf("    | "+f+"\n", a...)
	}
}

var codecs = []string{"json", "proto"}

func opts(codec string, extra ...connect.ClientOption) []connect.ClientOption {
	o := append([]connect.ClientOption{}, extra...)
	if codec == "json" {
		o = append(o, connect.WithProtoJSON())
	}
	return o
}

func echoClient(codec string, extra ...connect.ClientOption) *connect.Client[wrapperspb.StringValue, wrapperspb.StringValue] {
	return connect.NewClient[wrapperspb.StringValue, wrapperspb.StringValue](http.DefaultClient, *baseURL+svc+"Echo", opts(codec, extra...)...)
}

var allCodes = []connect.Code{
	connect.CodeCanceled, connect.CodeUnknown, connect.CodeInvalidArgument, connect.CodeDeadlineExceeded,
	connect.CodeNotFound, connect.CodeAlreadyExists, connect.CodePermissionDenied, connect.CodeResourceExhausted,
	connect.CodeFailedPrecondition, connect.CodeAborted, connect.CodeOutOfRange, connect.CodeUnimplemented,
	connect.CodeInternal, connect.CodeUnavailable, connect.CodeDataLoss, connect.CodeUnauthenticated,
}

func init() {
	for _, c := range codecs {
		c := c
		add("echo/post/"+c, func(ctx context.Context) error {
			res, err := echoClient(c).CallUnary(ctx, connect.NewRequest(wrapperspb.String("hello")))
			if err != nil {
				return err
			}
			vlog("response: %q headers=%v trailers=%v", res.Msg.GetValue(), res.Header(), res.Trailer())
			if res.Msg.GetValue() != "hello" {
				return fmt.Errorf("got %q want %q", res.Msg.GetValue(), "hello")
			}
			return nil
		})
		add("echo/headers-trailers/"+c, func(ctx context.Context) error {
			req := connect.NewRequest(wrapperspb.String("hdr"))
			req.Header().Set("x-test", "abc123")
			res, err := echoClient(c).CallUnary(ctx, req)
			if err != nil {
				return err
			}
			vlog("headers=%v trailers=%v", res.Header(), res.Trailer())
			if v := res.Header().Get("x-echo"); v != "abc123" {
				return fmt.Errorf("x-echo header = %q want abc123", v)
			}
			if v := res.Trailer().Get("x-trail"); v != "done" {
				return fmt.Errorf("x-trail trailer = %q want done", v)
			}
			return nil
		})
		add("echo/get/"+c, func(ctx context.Context) error {
			res, err := echoClient(c, connect.WithHTTPGet()).CallUnary(ctx, connect.NewRequest(wrapperspb.String("via get ünï")))
			if err != nil {
				return err
			}
			if res.Msg.GetValue() != "via get ünï" {
				return fmt.Errorf("got %q", res.Msg.GetValue())
			}
			return nil
		})
		for _, code := range allCodes {
			code := code
			add(fmt.Sprintf("fail/%s/%s", code, c), func(ctx context.Context) error {
				cl := connect.NewClient[wrapperspb.StringValue, wrapperspb.StringValue](http.DefaultClient, *baseURL+svc+"Fail", opts(c)...)
				_, err := cl.CallUnary(ctx, connect.NewRequest(wrapperspb.String(code.String())))
				if err == nil {
					return errors.New("expected error, got success")
				}
				var ce *connect.Error
				if !errors.As(err, &ce) {
					return fmt.Errorf("non-connect error: %v", err)
				}
				vlog("error: %v details=%d", ce, len(ce.Details()))
				if ce.Code() != code {
					return fmt.Errorf("code = %s want %s", ce.Code(), code)
				}
				if ce.Message() != "requested failure" {
					return fmt.Errorf("message = %q", ce.Message())
				}
				if len(ce.Details()) != 1 {
					return fmt.Errorf("details = %d want 1", len(ce.Details()))
				}
				d := ce.Details()[0]
				if d.Type() != "google.protobuf.StringValue" {
					return fmt.Errorf("detail type = %q", d.Type())
				}
				m, err := d.Value()
				if err != nil {
					return fmt.Errorf("detail decode: %v", err)
				}
				sv, ok := m.(*wrapperspb.StringValue)
				if !ok || sv.GetValue() != "detail" {
					return fmt.Errorf("detail value = %v", m)
				}
				return nil
			})
		}
		add("count/3/"+c, func(ctx context.Context) error {
			cl := connect.NewClient[wrapperspb.UInt32Value, wrapperspb.StringValue](http.DefaultClient, *baseURL+svc+"Count", opts(c)...)
			st, err := cl.CallServerStream(ctx, connect.NewRequest(wrapperspb.UInt32(3)))
			if err != nil {
				return err
			}
			var got []string
			for st.Receive() {
				got = append(got, st.Msg().GetValue())
			}
			if err := st.Err(); err != nil {
				return err
			}
			_ = st.Close()
			vlog("msgs=%v trailers=%v", got, st.ResponseTrailer())
			if strings.Join(got, ",") != "1,2,3" {
				return fmt.Errorf("messages = %v", got)
			}
			if v := st.ResponseTrailer().Get("x-count"); v != "3" {
				return fmt.Errorf("x-count = %q want 3", v)
			}
			return nil
		})
		add("count/0/"+c, func(ctx context.Context) error {
			cl := connect.NewClient[wrapperspb.UInt32Value, wrapperspb.StringValue](http.DefaultClient, *baseURL+svc+"Count", opts(c)...)
			st, err := cl.CallServerStream(ctx, connect.NewRequest(wrapperspb.UInt32(0)))
			if err != nil {
				return checkCode(err, connect.CodeOutOfRange)
			}
			n := 0
			for st.Receive() {
				n++
			}
			_ = st.Close()
			if n != 0 {
				return fmt.Errorf("got %d messages, want 0", n)
			}
			return checkCode(st.Err(), connect.CodeOutOfRange)
		})
		concat := func(in []string, want string) func(context.Context) error {
			return func(ctx context.Context) error {
				cl := connect.NewClient[wrapperspb.StringValue, wrapperspb.StringValue](http.DefaultClient, *baseURL+svc+"Concat", opts(c)...)
				st := cl.CallClientStream(ctx)
				for _, s := range in {
					if err := st.Send(wrapperspb.String(s)); err != nil {
						return err
					}
				}
				res, err := st.CloseAndReceive()
				if err != nil {
					return err
				}
				if res.Msg.GetValue() != want {
					return fmt.Errorf("got %q want %q", res.Msg.GetValue(), want)
				}
				return nil
			}
		}
		add("concat/abc/"+c, concat([]string{"a", "b", "c"}, "a b c"))
		add("concat/empty/"+c, concat(nil, ""))
	}

	// ---- raw HTTP cases ----
	add("raw/unknown-procedure-404", func(ctx context.Context) error {
		r, err := raw(ctx, "POST", svc+"Nope", "application/json", `{}`, nil)
		if err != nil {
			return err
		}
		return wantStatus(r, 404)
	})
	add("raw/wrong-content-type-415", func(ctx context.Context) error {
		r, err := raw(ctx, "POST", svc+"Echo", "text/plain", `"x"`, nil)
		if err != nil {
			return err
		}
		return wantStatus(r, 415)
	})
	add("raw/unsupported-content-encoding-501", func(ctx context.Context) error {
		r, err := raw(ctx, "POST", svc+"Echo", "application/json", `"x"`, map[string]string{"Content-Encoding": "zstd"})
		if err != nil {
			return err
		}
		if err := wantStatus(r, 501); err != nil {
			return err
		}
		return wantJSONCode(r, "unimplemented")
	})
	add("raw/protocol-version-2-400", func(ctx context.Context) error {
		r, err := raw(ctx, "POST", svc+"Echo", "application/json", `"x"`, map[string]string{"Connect-Protocol-Version": "2"})
		if err != nil {
			return err
		}
		return wantStatus(r, 400)
	})
	add("raw/timeout-invalid-400", func(ctx context.Context) error {
		r, err := raw(ctx, "POST", svc+"Echo", "application/json", `"x"`, map[string]string{"Connect-Timeout-Ms": "abc"})
		if err != nil {
			return err
		}
		if err := wantStatus(r, 400); err != nil {
			return err
		}
		return wantJSONCode(r, "invalid_argument")
	})
	add("raw/json-post-wire", func(ctx context.Context) error {
		r, err := raw(ctx, "POST", svc+"Echo", "application/json", `"wire"`, map[string]string{"Connect-Protocol-Version": "1"})
		if err != nil {
			return err
		}
		if err := wantStatus(r, 200); err != nil {
			return err
		}
		if strings.TrimSpace(string(r.body)) != `"wire"` {
			return fmt.Errorf("body = %s", r.body)
		}
		if ct := r.hdr.Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
			return fmt.Errorf("content-type = %q", ct)
		}
		if v := r.hdr.Get("Trailer-X-Trail"); v != "done" {
			return fmt.Errorf("Trailer-X-Trail = %q", v)
		}
		return nil
	})
}

type rawResp struct {
	status int
	hdr    http.Header
	body   []byte
}

func raw(ctx context.Context, method, path, ctype, body string, hdr map[string]string) (*rawResp, error) {
	req, err := http.NewRequestWithContext(ctx, method, *baseURL+path, bytes.NewBufferString(body))
	if err != nil {
		return nil, err
	}
	if ctype != "" {
		req.Header.Set("Content-Type", ctype)
	}
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	vlog("%s %s -> %d %v body=%q", method, path, res.StatusCode, res.Header, b)
	return &rawResp{res.StatusCode, res.Header, b}, nil
}

func wantStatus(r *rawResp, want int) error {
	if r.status != want {
		return fmt.Errorf("HTTP %d want %d (body %q)", r.status, want, r.body)
	}
	return nil
}

func wantJSONCode(r *rawResp, want string) error {
	var e struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal(r.body, &e); err != nil {
		return fmt.Errorf("body not JSON: %q", r.body)
	}
	if e.Code != want {
		return fmt.Errorf("error code = %q want %q", e.Code, want)
	}
	return nil
}

func checkCode(err error, want connect.Code) error {
	if err == nil {
		return fmt.Errorf("expected %s, got success", want)
	}
	if c := connect.CodeOf(err); c != want {
		return fmt.Errorf("code = %s want %s (%v)", c, want, err)
	}
	return nil
}

func main() {
	flag.Parse()
	*baseURL = strings.TrimRight(*baseURL, "/")
	var pass, fail, skipped int
	for _, tc := range cases {
		if *runFlag != "" && !strings.Contains(tc.name, *runFlag) {
			continue
		}
		if tc.spec && *lenient {
			fmt.Printf("SKIP %s: [spec] lenient\n", tc.name)
			skipped++
			continue
		}
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		err := tc.fn(ctx)
		cancel()
		var sk skip
		switch {
		case err == nil:
			fmt.Println("PASS " + tc.name)
			pass++
		case errors.As(err, &sk):
			fmt.Printf("SKIP %s: %s\n", tc.name, sk)
			skipped++
		default:
			fmt.Printf("FAIL %s: %v\n", tc.name, err)
			fail++
		}
	}
	fmt.Printf("SUMMARY: %d passed, %d failed, %d skipped\n", pass, fail, skipped)
	if fail > 0 {
		os.Exit(1)
	}
}
