package main

import "testing"

func TestSnake(t *testing.T) {
	for in, want := range map[string]string{
		"Greet": "greet", "GreetMany": "greet_many", "HTTPGet": "http_get", "GetV2": "get_v2",
		"Run": "run", "Match": "match_", "ListAPIKeys": "list_api_keys",
	} {
		if got := snake(in); got != want {
			t.Errorf("snake(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestRelPath(t *testing.T) {
	for _, c := range []struct{ fromDir, to, want string }{
		{".", "a_pb.bend", "./a_pb.bend"},
		{"app", "shared/common_pb.bend", "../shared/common_pb.bend"},
		{"app", "app/x_pb.bend", "./x_pb.bend"},
		{"a/b", "a/c/d_pb.bend", "../c/d_pb.bend"},
	} {
		if got := relPath(c.fromDir, c.to); got != c.want {
			t.Errorf("relPath(%q, %q) = %q, want %q", c.fromDir, c.to, got, c.want)
		}
	}
}

func TestBendFile(t *testing.T) {
	if got := bendFile("greet/v1/greet.api", "pb"); got != "greet/v1/greet_api_pb.bend" {
		t.Errorf("got %q", got)
	}
}
