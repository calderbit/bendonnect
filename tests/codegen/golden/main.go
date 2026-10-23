// Golden-vector program for the protoc-gen-bend kitchen-sink test.
//
//	go run ./golden gen   <vectors-dir>   write binary (hex) + canonical protojson vectors
//	go run ./golden check <vectors-dir> <bend-output.txt>
//	                                      verify what Bend produced against the originals
//
// Bend's output file has lines "bin <name> <hex>" and "json <name> <json>".
package main

import (
	"bufio"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	kitchenv1 "bendonnect/codegen/gen/go"

	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
)

func f64(v float64) *float64                 { return &v }
func i32(v int32) *int32                     { return &v }
func i64(v int64) *int64                     { return &v }
func str(v string) *string                   { return &v }
func bl(v bool) *bool                        { return &v }
func col(v kitchenv1.Color) *kitchenv1.Color { return &v }

// Doubles are chosen exactly representable as float32: Bend maps double to F32.
func vectors() map[string]proto.Message {
	scalarsFull := &kitchenv1.Scalars{
		FDouble: 1.5, FFloat: -2.25, FInt32: -7, FInt64: -9000000000, FUint32: 4000000000,
		FUint64: 18446744073709551615, FSint32: -123456, FSint64: -9223372036854775808,
		FFixed32: 0xdeadbeef, FFixed64: 0x0123456789abcdef, FSfixed32: -2, FSfixed64: -3,
		FBool: true, FString: "héllo, 世界 \U0001F600", FBytes: []byte{0, 1, 2, 0xff, 0x80},
	}
	return map[string]proto.Message{
		"empty":   &kitchenv1.Scalars{},
		"scalars": scalarsFull,
		"scalars_small": &kitchenv1.Scalars{
			FInt32: 1, FInt64: 300, FUint32: 128, FUint64: 1 << 40, FString: "a\"b\\c\n", FFloat: 0.5,
		},
		"repeats": &kitchenv1.Repeats{
			PackedInts: []int32{1, -1, 300, 0}, UnpackedInts: []int32{5, 6, 7},
			Names: []string{"a", "", "ccc"}, Blobs: [][]byte{{1}, {}, {2, 3}},
			Longs: []int64{-1, 1 << 62, 0}, Doubles: []float64{0.5, -4, 1e10},
			Flags:  []bool{true, false, true},
			Colors: []kitchenv1.Color{kitchenv1.Color_COLOR_BLUE, kitchenv1.Color_COLOR_RED},
			Items:  []*kitchenv1.Scalars{{FInt32: 9}, {}, {FString: "x"}},
		},
		"outer": &kitchenv1.Outer{
			Inner: &kitchenv1.Outer_Inner{Label: "in", Kind: kitchenv1.Outer_KIND_BETA},
			Kind:  kitchenv1.Outer_KIND_ALPHA, Color: kitchenv1.Color_COLOR_GREEN,
			Inners: []*kitchenv1.Outer_Inner{{Label: "x"}, {Kind: kitchenv1.Outer_KIND_ALPHA}},
		},
		"tree": &kitchenv1.Tree{
			Name: "root", Weight: 3,
			Left:     &kitchenv1.Tree{Name: "l", Weight: -1, Left: &kitchenv1.Tree{Name: "ll"}},
			Right:    &kitchenv1.Tree{},
			Children: []*kitchenv1.Tree{{Name: "c1"}, {Name: "c2", Children: []*kitchenv1.Tree{{Weight: 2}}}},
		},
		"maps": &kitchenv1.Maps{
			Counts: map[string]int64{"a": 1, "b": -2, "zz": 1 << 40},
			ById:   map[int32]*kitchenv1.Scalars{1: {FString: "one"}, -5: {FInt32: 5}, 7: {}},
			Labels: map[string]string{"k": "v", "": "empty-key"},
			Flags:  map[bool]string{true: "yes", false: ""},
			Blobs:  map[uint64][]byte{0: {}, 18446744073709551615: {1, 2, 3}},
			Colors: map[int64]kitchenv1.Color{-1: kitchenv1.Color_COLOR_RED, 5: kitchenv1.Color_COLOR_BLUE},
		},
		"choice_none":     &kitchenv1.Choice{Tag: "none"},
		"choice_number":   &kitchenv1.Choice{Tag: "n", Value: &kitchenv1.Choice_Number{Number: -42}},
		"choice_zero":     &kitchenv1.Choice{Value: &kitchenv1.Choice_Number{Number: 0}},
		"choice_text":     &kitchenv1.Choice{Value: &kitchenv1.Choice_Text{Text: "hi"}},
		"choice_scalars":  &kitchenv1.Choice{Value: &kitchenv1.Choice_Scalars{Scalars: &kitchenv1.Scalars{FBool: true}}},
		"choice_color":    &kitchenv1.Choice{Value: &kitchenv1.Choice_Color{Color: kitchenv1.Color_COLOR_BLUE}},
		"choice_raw":      &kitchenv1.Choice{Value: &kitchenv1.Choice_Raw{Raw: []byte{9, 8, 7}}},
		"optionals_unset": &kitchenv1.Optionals{Plain: 4},
		"optionals_zero": &kitchenv1.Optionals{
			MaybeInt: i32(0), MaybeString: str(""), MaybeBool: bl(false),
			MaybeColor: col(kitchenv1.Color_COLOR_UNSPECIFIED), MaybeLong: i64(0), MaybeDouble: f64(0),
		},
		"optionals_set": &kitchenv1.Optionals{
			MaybeInt: i32(-3), MaybeString: str("s"), MaybeBool: bl(true),
			MaybeColor: col(kitchenv1.Color_COLOR_RED), MaybeLong: i64(-5000000000), Plain: 1,
			MaybeMsg: &kitchenv1.Scalars{}, MaybeBytes: []byte{}, MaybeDouble: f64(-0.75),
		},
		"keywords": &kitchenv1.Keywords{
			Type: "t", Match: 2, Def: true, Import: "i", For: 5, Data: "d", Kind: kitchenv1.Color_COLOR_GREEN,
		},
		"kitchen": &kitchenv1.Kitchen{
			Scalars:   scalarsFull,
			Repeats:   &kitchenv1.Repeats{PackedInts: []int32{1, 2}, Names: []string{"n"}},
			Outer:     &kitchenv1.Outer{Kind: kitchenv1.Outer_KIND_BETA},
			Tree:      &kitchenv1.Tree{Name: "t", Left: &kitchenv1.Tree{Name: "tl"}},
			Maps:      &kitchenv1.Maps{Counts: map[string]int64{"x": 7}},
			Choice:    &kitchenv1.Choice{Value: &kitchenv1.Choice_Text{Text: "z"}},
			Optionals: &kitchenv1.Optionals{MaybeInt: i32(1)},
			Keywords:  &kitchenv1.Keywords{Type: "k"},
		},
	}
}

func newMsg(name string) proto.Message {
	switch {
	case name == "empty", strings.HasPrefix(name, "scalars"):
		return &kitchenv1.Scalars{}
	case name == "repeats":
		return &kitchenv1.Repeats{}
	case name == "outer":
		return &kitchenv1.Outer{}
	case name == "tree":
		return &kitchenv1.Tree{}
	case name == "maps":
		return &kitchenv1.Maps{}
	case strings.HasPrefix(name, "choice"):
		return &kitchenv1.Choice{}
	case strings.HasPrefix(name, "optionals"):
		return &kitchenv1.Optionals{}
	case name == "keywords":
		return &kitchenv1.Keywords{}
	case name == "kitchen":
		return &kitchenv1.Kitchen{}
	}
	return nil
}

func sortedNames(m map[string]proto.Message) []string {
	names := make([]string, 0, len(m))
	for n := range m {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

func gen(dir string) error {
	vs := vectors()
	idx, err := os.Create(filepath.Join(dir, "index.txt"))
	if err != nil {
		return err
	}
	defer idx.Close()
	var bend strings.Builder
	bend.WriteString("# Code generated by tests/codegen/golden. DO NOT EDIT.\n# Golden vectors as Bend values: one def per vector (name, binary hex, protojson).\nimport Base\n\n")
	bend.WriteString("type Vec is Data:\n  Vec{name: String, hex: String, json: String}\n\n")
	for _, n := range sortedNames(vs) {
		m := vs[n]
		bin, err := proto.MarshalOptions{Deterministic: true}.Marshal(m)
		if err != nil {
			return err
		}
		js, err := protojson.MarshalOptions{}.Marshal(m)
		if err != nil {
			return err
		}
		// protojson output is intentionally unstable in whitespace; normalise to compact.
		js = compact(js)
		if err := os.WriteFile(filepath.Join(dir, n+".bin.hex"), []byte(hex.EncodeToString(bin)+"\n"), 0o644); err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(dir, n+".json"), append(js, '\n'), 0o644); err != nil {
			return err
		}
		fmt.Fprintln(idx, n)
		fmt.Fprintf(&bend, "def vec.%s() -> Vec:\n  Vec{%q, %q, %s}\n\n", n, n, hex.EncodeToString(bin), bendString(string(js)))
	}
	return os.WriteFile(filepath.Join(dir, "vectors.bend"), []byte(bend.String()), 0o644)
}

func compact(js []byte) []byte {
	var m map[string]any
	_ = m
	// re-parse via protojson is not possible without type; strip insignificant ws outside strings.
	var out []byte
	inStr, esc := false, false
	for _, c := range js {
		if inStr {
			out = append(out, c)
			if esc {
				esc = false
			} else if c == '\\' {
				esc = true
			} else if c == '"' {
				inStr = false
			}
			continue
		}
		switch c {
		case ' ', '\n', '\t', '\r':
		case '"':
			inStr = true
			out = append(out, c)
		default:
			out = append(out, c)
		}
	}
	return out
}

// bendString renders s as a Bend string literal. JSON text may contain quotes and
// backslashes; escape them.
func bendString(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for _, r := range s {
		switch r {
		case '"':
			b.WriteString(`\"`)
		case '\\':
			b.WriteString(`\\`)
		case '\n':
			b.WriteString(`\n`)
		default:
			b.WriteRune(r)
		}
	}
	b.WriteByte('"')
	return b.String()
}

func check(dir, out string) error {
	f, err := os.Open(out)
	if err != nil {
		return err
	}
	defer f.Close()
	vs := vectors()
	seenBin, seenJSON := map[string]bool{}, map[string]bool{}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<24)
	bad := 0
	for sc.Scan() {
		parts := strings.SplitN(sc.Text(), " ", 3)
		if len(parts) != 3 || (parts[0] != "bin" && parts[0] != "json") {
			continue
		}
		kind, name, payload := parts[0], parts[1], parts[2]
		want, ok := vs[name]
		if !ok {
			fmt.Printf("FAIL %s %s: unknown vector\n", kind, name)
			bad++
			continue
		}
		got := newMsg(name)
		if kind == "bin" {
			raw, err := hex.DecodeString(strings.TrimSpace(payload))
			if err == nil {
				err = proto.Unmarshal(raw, got)
			}
			if err != nil {
				fmt.Printf("FAIL bin %s: %v\n", name, err)
				bad++
				continue
			}
			seenBin[name] = true
		} else {
			if err := (protojson.UnmarshalOptions{}).Unmarshal([]byte(payload), got); err != nil {
				fmt.Printf("FAIL json %s: %v (%s)\n", name, err, payload)
				bad++
				continue
			}
			seenJSON[name] = true
		}
		if !proto.Equal(want, got) {
			fmt.Printf("FAIL %s %s: not equal\n  want %v\n  got  %v\n", kind, name, want, got)
			bad++
			continue
		}
		fmt.Printf("PASS go-parses-bend %s %s\n", kind, name)
	}
	for n := range vs {
		if !seenBin[n] || !seenJSON[n] {
			fmt.Printf("FAIL %s: missing bin=%v json=%v in Bend output\n", n, !seenBin[n], !seenJSON[n])
			bad++
		}
	}
	if bad > 0 {
		return fmt.Errorf("%d failures", bad)
	}
	return nil
}

func main() {
	var err error
	switch {
	case len(os.Args) == 3 && os.Args[1] == "gen":
		err = gen(os.Args[2])
	case len(os.Args) == 4 && os.Args[1] == "check":
		err = check(os.Args[2], os.Args[3])
	default:
		err = fmt.Errorf("usage: golden gen <dir> | golden check <dir> <bend-output>")
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
