package main

import (
	"fmt"
	"path"
	"sort"
	"strings"

	"google.golang.org/protobuf/compiler/protogen"
	"google.golang.org/protobuf/reflect/protoreflect"
)

// Bend keywords that cannot be used as names; they get a trailing '_'.
var reserved = map[string]bool{
	"type": true, "match": true, "case": true, "def": true, "law": true, "for": true,
	"exs": true, "import": true, "as": true, "is": true, "do": true, "return": true,
	"where": true, "Kind": true, "Type": true, "Data": true,
}

// Top-level names already taken by Base (types, constructors) or by the module aliases the
// generated files use; a message called one of these gets a trailing '_'.
var topReserved = map[string]bool{}

func init() {
	for _, n := range []string{
		"Empty", "Unit", "Bool", "Cmp", "Either", "Sigma", "Nat", "Maybe", "Result", "Poll", "List",
		"Word", "U32", "F32", "Char", "String", "Array", "Image", "Event", "Map", "IO", "App", "Pair",
		"Exists", "Or", "Set", "ALeaf", "ANode", "Chr", "Close", "Con", "Done", "Emit", "EQ", "Exit",
		"Fail", "False", "GT", "Halt", "Inl", "Inr", "Key", "Look", "LT", "MLeaf", "MNode", "Mouse",
		"Move", "MTip", "Nil", "None", "Pix", "Qua", "Ready", "SCon", "Scroll", "SNil", "Some", "Succ",
		"Text", "True", "Tuple", "Wait", "WCon", "WNil", "Zero", "Base", "Bytes", "Json", "Pb", "Pbr",
		"Pj", "Code", "E", "P", "Msgs", "Rpc", "Srv", "Cli", "Enc", "Http",
	} {
		topReserved[n] = true
	}
}

func esc(s string) string {
	if reserved[s] {
		return s + "_"
	}
	return s
}

type card int

const (
	cSingle card = iota
	cOptional
	cRepeated
	cMap
	cOneof
)

// scalar kind table: runtime kind name, Bend type, Bend default expression.
type scalarInfo struct{ rt, bend, def string }

var scalars = map[protoreflect.Kind]scalarInfo{
	protoreflect.DoubleKind:   {"double", "F32", "0.0"},
	protoreflect.FloatKind:    {"float", "F32", "0.0"},
	protoreflect.Int32Kind:    {"int32", "U32", "0"},
	protoreflect.Sint32Kind:   {"sint32", "U32", "0"},
	protoreflect.Sfixed32Kind: {"sfixed32", "U32", "0"},
	protoreflect.Uint32Kind:   {"uint32", "U32", "0"},
	protoreflect.Fixed32Kind:  {"fixed32", "U32", "0"},
	protoreflect.Int64Kind:    {"int64", "Pb.Word64", "Pb.Word64{0, 0}"},
	protoreflect.Sint64Kind:   {"sint64", "Pb.Word64", "Pb.Word64{0, 0}"},
	protoreflect.Sfixed64Kind: {"sfixed64", "Pb.Word64", "Pb.Word64{0, 0}"},
	protoreflect.Uint64Kind:   {"uint64", "Pb.Word64", "Pb.Word64{0, 0}"},
	protoreflect.Fixed64Kind:  {"fixed64", "Pb.Word64", "Pb.Word64{0, 0}"},
	protoreflect.BoolKind:     {"bool", "Bool", "False{}"},
	protoreflect.StringKind:   {"string", "String", `""`},
	protoreflect.BytesKind:    {"bytes", "List<&2, U32>", "Nil{}"},
	protoreflect.EnumKind:     {"enum", "U32", "0"},
}

type field struct {
	m       *message
	Name    string // Bend field name (escaped)
	Bind    string // pattern binder
	Proto   string
	JSON    string
	Num     int
	Kind    protoreflect.Kind
	RT      string // runtime kind: double ... enum, message
	Card    card
	Packed  bool
	Elem    string   // Bend type of one element
	Msg     *message // target message (same file) for message-kind (or map entry) fields
	MsgRef  string   // Bend name of the message type (qualified when from another file)
	EnumRef string   // Bend name of the enum
	Oneof   *oneof
	Member  string // oneof constructor name (qualified)
	SelfRec bool   // message-kind field whose type is the enclosing recursive message
	GoName  string
}

func (f *field) isMsg() bool {
	return f.Kind == protoreflect.MessageKind || f.Kind == protoreflect.GroupKind
}

// Bend type of the field as stored in the message.
func (f *field) Type() string {
	switch f.Card {
	case cRepeated, cMap:
		return "List<&2, " + f.Elem + ">"
	case cOptional:
		return "Maybe<&2, " + f.Elem + ">"
	case cOneof:
		return f.Oneof.Type
	}
	if f.isMsg() && !f.m.IsEntry {
		return "Maybe<&2, " + f.Elem + ">"
	}
	return f.Elem
}

func (f *field) Default() string {
	switch f.Card {
	case cRepeated, cMap:
		return "Nil{}"
	case cOptional:
		return "None{}"
	case cOneof:
		return f.Oneof.Type + ".None{}"
	}
	if f.isMsg() {
		if f.m.IsEntry {
			return f.Elem + ".default()"
		}
		return "None{}"
	}
	return scalars[f.Kind].def
}

type oneof struct {
	Name    string // Bend field name
	Type    string
	Members []*field
	Bind    string
}

type enumValue struct {
	Name string
	Num  int32
}

type enum struct {
	Name   string
	Values []enumValue
}

type message struct {
	Name      string // Bend type name, e.g. Outer.Inner
	Desc      protoreflect.MessageDescriptor
	Fields    []*field // in field-number order (proto binary order)
	Decl      []*field // in declaration order (JSON order)
	Oneofs    []*oneof
	IsEntry   bool
	Rec       bool
	deps      []*message
	slotCache []*slot
	index     int
}

type unit struct {
	f        *protogen.File
	g        *protogen.Plugin
	messages []*message // declaration order, entries included, nested after parent
	byName   map[protoreflect.FullName]*message
	enums    []*enum
	order    []*message        // dependency order
	aliases  map[string]string // proto file path -> alias
	imports  []depImport
	names    map[string]string // defined Bend type names -> what
}

type depImport struct {
	Alias string
	Path  string // import path relative to the generated file
}

func (u *unit) define(name, what string) error {
	if prev, ok := u.names[name]; ok {
		return fmt.Errorf("Bend name %q is defined twice (%s and %s)", name, prev, what)
	}
	u.names[name] = what
	return nil
}

// relName is the name of a declaration relative to its proto package.
func relName(d protoreflect.Descriptor) string {
	full := string(d.FullName())
	pkg := string(d.ParentFile().Package())
	if pkg != "" {
		full = strings.TrimPrefix(full, pkg+".")
	}
	parts := strings.Split(full, ".")
	for i, p := range parts {
		parts[i] = esc(p)
		if i == 0 && topReserved[p] {
			parts[i] = p + "_"
		}
	}
	return strings.Join(parts, ".")
}

// refName is the Bend name used from the current file for a message or enum descriptor.
func (u *unit) refName(d protoreflect.Descriptor) string {
	if d.ParentFile().Path() == u.f.Desc.Path() {
		return relName(d)
	}
	return u.aliases[d.ParentFile().Path()] + "." + relName(d)
}

func relImport(from, to string) string {
	fromDir := path.Dir(from)
	rel := relPath(fromDir, to)
	return rel
}

func relPath(fromDir, to string) string {
	fp := strings.Split(path.Clean(fromDir), "/")
	if fromDir == "." || fromDir == "" {
		fp = nil
	}
	tp := strings.Split(to, "/")
	i := 0
	for i < len(fp) && i < len(tp)-1 && fp[i] == tp[i] {
		i++
	}
	var parts []string
	for j := i; j < len(fp); j++ {
		parts = append(parts, "..")
	}
	parts = append(parts, tp[i:]...)
	r := strings.Join(parts, "/")
	if !strings.HasPrefix(r, "../") {
		r = "./" + r
	}
	return r
}

func newUnit(gen *protogen.Plugin, f *protogen.File) (*unit, error) {
	if f.Desc.Syntax() != protoreflect.Proto3 {
		return nil, fmt.Errorf("only proto3 files are supported by protoc-gen-bend v1 (syntax is %q); proto2 and editions are rejected", f.Desc.Syntax())
	}
	u := &unit{f: f, g: gen, byName: map[protoreflect.FullName]*message{}, aliases: map[string]string{}, names: map[string]string{}}
	imps := f.Desc.Imports()
	usedAlias := map[string]string{}
	for i := 0; i < imps.Len(); i++ {
		imp := imps.Get(i)
		if imp.IsPublic || imp.IsWeak {
			return nil, fmt.Errorf("public/weak import %q is not supported", imp.Path())
		}
		// Only dependencies that define something we may reference matter, but the import
		// is harmless and keeps Bend's module graph equal to the proto one. Skip files
		// that declare nothing (e.g. only options).
		dep := imp.FileDescriptor
		if dep.Messages().Len() == 0 && dep.Enums().Len() == 0 {
			continue
		}
		alias := strings.ReplaceAll(string(dep.Package()), ".", "_")
		stem := strings.TrimSuffix(path.Base(dep.Path()), ".proto")
		alias = alias + "_" + strings.ReplaceAll(stem, "-", "_")
		alias = strings.TrimPrefix(alias, "_")
		if alias == "" {
			alias = "dep"
		}
		if prev, ok := usedAlias[alias]; ok && prev != dep.Path() {
			return nil, fmt.Errorf("imports %q and %q map to the same Bend alias %q", prev, dep.Path(), alias)
		}
		usedAlias[alias] = dep.Path()
		u.aliases[dep.Path()] = alias
		dst := bendFile(strings.TrimSuffix(dep.Path(), ".proto"), "pb")
		u.imports = append(u.imports, depImport{Alias: alias, Path: relImport(bendFile(strings.TrimSuffix(f.Desc.Path(), ".proto"), "pb"), dst)})
	}
	for _, m := range f.Messages {
		if err := u.addMessage(m); err != nil {
			return nil, err
		}
	}
	for _, e := range f.Enums {
		if err := u.addEnum(e); err != nil {
			return nil, err
		}
	}
	for _, m := range u.messages {
		if err := u.fill(m); err != nil {
			return nil, err
		}
	}
	if err := u.sortMessages(); err != nil {
		return nil, err
	}
	return u, nil
}

func (u *unit) addEnum(e *protogen.Enum) error {
	en := &enum{Name: relName(e.Desc)}
	if err := u.define(en.Name, "enum "+string(e.Desc.FullName())); err != nil {
		return err
	}
	seen := map[string]bool{}
	for _, v := range e.Values {
		name := string(v.Desc.Name())
		if seen[name] || name == "name" || name == "from_name" {
			return fmt.Errorf("enum %s: value name %q collides with a generated helper", e.Desc.FullName(), name)
		}
		seen[name] = true
		en.Values = append(en.Values, enumValue{Name: name, Num: int32(v.Desc.Number())})
	}
	u.enums = append(u.enums, en)
	return nil
}

func (u *unit) addMessage(m *protogen.Message) error {
	msg := &message{Name: relName(m.Desc), Desc: m.Desc, IsEntry: m.Desc.IsMapEntry(), index: len(u.messages)}
	if err := u.define(msg.Name, "message "+string(m.Desc.FullName())); err != nil {
		return err
	}
	u.messages = append(u.messages, msg)
	u.byName[m.Desc.FullName()] = msg
	for _, e := range m.Enums {
		if err := u.addEnum(e); err != nil {
			return err
		}
	}
	for _, c := range m.Messages {
		if err := u.addMessage(c); err != nil {
			return err
		}
	}
	return nil
}

func (u *unit) fill(msg *message) error {
	md := msg.Desc
	// find the protogen message for GoName
	var pm *protogen.Message
	var find func(ms []*protogen.Message)
	find = func(ms []*protogen.Message) {
		for _, m := range ms {
			if m.Desc.FullName() == md.FullName() {
				pm = m
				return
			}
			find(m.Messages)
			if pm != nil {
				return
			}
		}
	}
	find(u.f.Messages)
	byOneof := map[string]*oneof{}
	for _, pf := range pm.Fields {
		fd := pf.Desc
		f := &field{m: msg, Name: esc(string(fd.Name())), Proto: string(fd.Name()), JSON: fd.JSONName(), Num: int(fd.Number()), Kind: fd.Kind(), GoName: pf.GoName}
		f.Bind = "f_" + string(fd.Name())
		if fd.Kind() == protoreflect.GroupKind {
			return fmt.Errorf("%s: groups are not supported", fd.FullName())
		}
		if fd.IsMap() {
			f.Card = cMap
			ent := fd.Message()
			f.Msg = u.byName[ent.FullName()]
			f.Elem = relName(ent)
			f.RT = "message"
			msg.deps = append(msg.deps, f.Msg)
		} else {
			switch {
			case fd.IsList():
				f.Card = cRepeated
			case pf.Oneof != nil && !pf.Oneof.Desc.IsSynthetic():
				f.Card = cOneof
			case fd.HasOptionalKeyword():
				f.Card = cOptional
			default:
				f.Card = cSingle
			}
			if f.Kind == protoreflect.MessageKind {
				f.RT = "message"
				f.MsgRef = u.refName(fd.Message())
				f.Elem = f.MsgRef
				if t, ok := u.byName[fd.Message().FullName()]; ok {
					f.Msg = t
					msg.deps = append(msg.deps, t)
				}
			} else {
				si := scalars[f.Kind]
				f.RT = si.rt
				f.Elem = si.bend
				if f.Kind == protoreflect.EnumKind {
					f.EnumRef = u.refName(fd.Enum())
					if fd.Enum().Syntax() != protoreflect.Proto3 {
						return fmt.Errorf("%s: field uses a non-proto3 (closed) enum %s", fd.FullName(), fd.Enum().FullName())
					}
				}
			}
			if f.Card == cRepeated {
				f.Packed = fd.IsPacked()
			}
		}
		if f.Card == cOneof {
			od := pf.Oneof
			o := byOneof[string(od.Desc.Name())]
			if o == nil {
				o = &oneof{Name: esc(string(od.Desc.Name())), Bind: "f_" + string(od.Desc.Name())}
				o.Type = msg.Name + "." + od.GoName
				if err := u.define(o.Type, "oneof "+string(od.Desc.FullName())); err != nil {
					return err
				}
				byOneof[string(od.Desc.Name())] = o
				msg.Oneofs = append(msg.Oneofs, o)
			}
			f.Oneof = o
			f.Member = o.Type + "." + pf.GoName
			o.Members = append(o.Members, f)
		}
		msg.Decl = append(msg.Decl, f)
	}
	// message fields are in declaration order; one binder/field per oneof for the message body
	msg.Fields = append([]*field(nil), msg.Decl...)
	sort.SliceStable(msg.Fields, func(i, j int) bool { return msg.Fields[i].Num < msg.Fields[j].Num })
	return nil
}

// sortMessages orders messages so every message comes after those it embeds, and marks
// self-recursive messages. Mutually recursive messages are rejected.
func (u *unit) sortMessages() error {
	// Tarjan SCC
	index, low := map[*message]int{}, map[*message]int{}
	onStack := map[*message]bool{}
	var stack []*message
	counter := 0
	var sccs [][]*message
	var strong func(v *message)
	strong = func(v *message) {
		index[v], low[v] = counter, counter
		counter++
		stack = append(stack, v)
		onStack[v] = true
		for _, w := range v.deps {
			if _, seen := index[w]; !seen {
				strong(w)
				if low[w] < low[v] {
					low[v] = low[w]
				}
			} else if onStack[w] && index[w] < low[v] {
				low[v] = index[w]
			}
		}
		if low[v] == index[v] {
			var comp []*message
			for {
				w := stack[len(stack)-1]
				stack = stack[:len(stack)-1]
				onStack[w] = false
				comp = append(comp, w)
				if w == v {
					break
				}
			}
			sccs = append(sccs, comp)
		}
	}
	for _, m := range u.messages {
		if _, seen := index[m]; !seen {
			strong(m)
		}
	}
	// Tarjan emits SCCs in reverse topological order of the condensation: dependencies first.
	for _, comp := range sccs {
		if len(comp) > 1 {
			var names []string
			for _, m := range comp {
				names = append(names, string(m.Desc.FullName()))
			}
			sort.Strings(names)
			return fmt.Errorf("mutually recursive messages are not supported in v1 (Bend forbids mutual recursion): %s", strings.Join(names, ", "))
		}
		m := comp[0]
		for _, d := range m.deps {
			if d == m {
				m.Rec = true
			}
		}
		u.order = append(u.order, m)
	}
	for _, m := range u.messages {
		for _, f := range m.Decl {
			if m.Rec && f.isMsg() && f.Msg == m && f.Card != cMap {
				f.SelfRec = true
			}
		}
	}
	return nil
}
