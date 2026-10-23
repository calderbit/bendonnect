package main

import (
	"fmt"
	"strings"

	"google.golang.org/protobuf/reflect/protoreflect"
)

const kvsT = "List<&1, String & Json.Val>"
const jvalsT = "List<&1, Json.Val>"
const jaccT = "List<&1, Bytes.Bytes & Json.Val>"

func (m *message) jstate() string { return kvsT + " & " + m.Name }
func (m *message) jres(t string) string {
	return fmt.Sprintf("Result<&2, &1, String, %s>", t)
}

func q(s string) string { return fmt.Sprintf("%q", s) }

// enum helpers used as templates: Color.json_name / Color.json_read.
func enumNameFn(f *field) string { return f.EnumRef + ".name" }

// scalar JSON value expression for a map value / key.
func (f *field) jsonVal(x string) string {
	switch {
	case f.isMsg():
		return fmt.Sprintf("%s.to_json(%s)", f.Elem, x)
	case f.Kind == protoreflect.EnumKind:
		return fmt.Sprintf("Pj.val.enum(~%s, %s)", enumNameFn(f), x)
	}
	return fmt.Sprintf("Pj.val.%s(%s)", f.RT, x)
}

// reader (a template-ready Json.Val -> R<T> function) for one element of the field.
func (f *field) jsonReader() string {
	switch {
	case f.isMsg():
		return f.Elem + ".from_json"
	case f.Kind == protoreflect.EnumKind:
		return f.EnumRef + ".read_json"
	}
	return "Pj.read." + f.RT
}

func (u *unit) jsonCodec(w *writer, m *message) {
	if m.IsEntry {
		return
	}
	n := m.Name
	u.jsonSetters(w, m)
	u.jsonWriters(w, m)
	u.jsonReaders(w, m)
	w.f("def %s.encode_json(m: %s) -> Bytes.Bytes:", n, n)
	w.f("  Pj.encode(%s.to_json(m))", n)
	w.blank()
	w.f("def %s.decode_json(b: Bytes.Bytes) -> %s:", n, m.rtype())
	w.f("  do %s:", m.rtype())
	w.f("    v : Json.Val <- Pj.parse(b)")
	w.f("    %s.from_json(v)", n)
	w.blank()
}

func (u *unit) jsonSetters(w *writer, m *message) {
	for _, s := range m.slots() {
		w.f("def %s.set.%s(x: %s, m: %s) -> %s:", m.Name, s.Name, s.Type, m.Name, m.Name)
		w.f("  match m:")
		w.f("    case %s:", m.pattern(func(o *slot) bool { return o != s }))
		w.f("      %s", m.ctor(map[*slot]string{s: "x"}))
		w.blank()
	}
	// "set the oneof member if the reader found one"
	for _, f := range m.Decl {
		if f.Card != cOneof {
			continue
		}
		s := m.slotOf(f)
		w.f("def %s.set.pick.%s(r: Maybe<&2, %s>, m: %s) -> %s:", m.Name, f.Name, f.Elem, m.Name, m.Name)
		w.f("  match r:")
		w.f("    case None{}:")
		w.f("      m")
		w.f("    case Some{x}:")
		w.f("      %s.set.%s(%s{x}, m)", m.Name, s.Name, f.Member)
		w.blank()
	}
}

// ---------------------------------------------------------------- writer

func (m *message) jputExpr(s *slot, acc string) string {
	n := m.Name
	if s.O != nil {
		return fmt.Sprintf("%s.j.%s(%s, %s)", n, s.Name, s.Bind, acc)
	}
	f := s.F
	x := s.Bind
	switch {
	case f.Card == cSingle && !f.isMsg():
		if f.Kind == protoreflect.EnumKind {
			return fmt.Sprintf("Pj.put.enum(~%s, %s, %s, %s)", enumNameFn(f), q(f.JSON), x, acc)
		}
		return fmt.Sprintf("Pj.put.%s(%s, %s, %s)", f.RT, q(f.JSON), x, acc)
	case f.Card == cRepeated && !f.isMsg():
		if f.Kind == protoreflect.EnumKind {
			return fmt.Sprintf("Pj.put.repeated.enum(~%s, %s, %s, %s)", enumNameFn(f), q(f.JSON), x, acc)
		}
		return fmt.Sprintf("Pj.put.repeated.%s(%s, %s, %s)", f.RT, q(f.JSON), x, acc)
	}
	return fmt.Sprintf("%s.j.%s(%s, %s)", n, f.Name, x, acc)
}

func (u *unit) jsonWriters(w *writer, m *message) {
	n := m.Name
	if m.Rec {
		w.f("def %s.jput.one(name: String, ks: %s, acc: %s) -> %s:", n, jvalsT, jaccT, jaccT)
		w.f("  match ks:")
		w.f("    case Nil{}:")
		w.f("      acc")
		w.f("    case Con{v, t}:")
		w.f("      Pj.put.message(name, v, acc)")
		w.blank()
	}
	for _, f := range m.Decl {
		if f.Card == cOneof || f.SelfRec {
			continue
		}
		switch {
		case (f.Card == cSingle && !f.isMsg()) || (f.Card == cRepeated && !f.isMsg()):
			continue
		case f.Card == cSingle || f.Card == cOptional:
			w.f("def %s.j.%s(x: Maybe<&2, %s>, acc: %s) -> %s:", n, f.Name, f.Elem, jaccT, jaccT)
			w.f("  match x:")
			w.f("    case None{}:")
			w.f("      acc")
			w.f("    case Some{s}:")
			if f.isMsg() {
				w.f("      Pj.put.message(%s, %s.to_json(s), acc)", q(f.JSON), f.Elem)
			} else if f.Kind == protoreflect.EnumKind {
				w.f("      Pj.put.enum.always(~%s, %s, s, acc)", enumNameFn(f), q(f.JSON))
			} else {
				w.f("      Pj.put.%s.always(%s, s, acc)", f.RT, q(f.JSON))
			}
			w.blank()
		case f.Card == cRepeated: // repeated message
			w.f("def %s.j.%s.items(xs: List<&2, %s>) -> %s:", n, f.Name, f.Elem, jvalsT)
			w.f("  match xs:")
			w.f("    case Nil{}:")
			w.f("      Nil{}")
			w.f("    case Con{h, t}:")
			w.f("      Con{%s.to_json(h), %s.j.%s.items(t)}", f.Elem, n, f.Name)
			w.blank()
			w.f("def %s.j.%s(xs: List<&2, %s>, acc: %s) -> %s:", n, f.Name, f.Elem, jaccT, jaccT)
			w.f("  Pj.put.repeated.message(%s, %s.j.%s.items(xs), acc)", q(f.JSON), n, f.Name)
			w.blank()
		case f.Card == cMap:
			key, val := f.Msg.Decl[0], f.Msg.Decl[1]
			w.f("def %s.j.%s.items(es: List<&2, %s>) -> %s:", n, f.Name, f.Elem, jaccT)
			w.f("  match es:")
			w.f("    case Nil{}:")
			w.f("      Nil{}")
			w.f("    case Con{+e, t}:")
			w.f("      match e:")
			w.f("        case %s{k, v}:", f.Elem)
			w.f("          Con{Pj.entry(Pj.key.%s(k), %s), %s.j.%s.items(t)}", key.RT, val.jsonVal("v"), n, f.Name)
			w.blank()
			w.f("def %s.j.%s(es: List<&2, %s>, acc: %s) -> %s:", n, f.Name, f.Elem, jaccT, jaccT)
			w.f("  Pj.put.map(%s, %s.j.%s.items(es), acc)", q(f.JSON), n, f.Name)
			w.blank()
		}
	}
	for _, o := range m.Oneofs {
		hasSelf := false
		for _, f := range o.Members {
			if f.SelfRec {
				hasSelf = true
			}
		}
		if hasSelf {
			w.f("def %s.jput.%s(o: %s, k: %s, acc: %s) -> %s:", n, o.Name, o.Type, jvalsT, jaccT, jaccT)
		} else {
			w.f("def %s.j.%s(o: %s, acc: %s) -> %s:", n, o.Name, o.Type, jaccT, jaccT)
		}
		w.f("  match o:")
		w.f("    case %s.None{}:", o.Type)
		if hasSelf {
			w.f("      acc")
		} else {
			w.f("      acc")
		}
		for _, f := range o.Members {
			switch {
			case f.SelfRec:
				w.f("    case %s{s}:", f.Member)
				w.f("      %s.jput.one(%s, k, acc)", n, q(f.JSON))
			case f.isMsg():
				w.f("    case %s{s}:", f.Member)
				w.f("      Pj.put.message(%s, %s.to_json(s), acc)", q(f.JSON), f.Elem)
			case f.Kind == protoreflect.EnumKind:
				w.f("    case %s{s}:", f.Member)
				w.f("      Pj.put.enum.always(~%s, %s, s, acc)", enumNameFn(f), q(f.JSON))
			default:
				w.f("    case %s{s}:", f.Member)
				w.f("      Pj.put.%s.always(%s, s, acc)", f.RT, q(f.JSON))
			}
		}
		w.blank()
	}
	if !m.Rec {
		w.f("def %s.to_json(m: %s) -> Json.Val:", n, n)
		if len(m.slots()) == 0 {
			w.f("  Pj.obj(Nil{})")
		} else {
			w.f("  match m:")
			w.f("    case %s:", m.pattern(func(*slot) bool { return true }))
			acc := "Nil{}"
			for _, s := range m.slots() {
				acc = m.jputExpr(s, acc)
			}
			w.f("      Pj.obj(%s)", acc)
		}
		w.blank()
		return
	}
	// recursive: one def over lists of messages, depth counter first
	w.f("def %s.tj_all(+fuel: Nat, ms: List<&2, %s>) -> %s:", n, n, jvalsT)
	w.f("  match fuel:")
	w.f("    case 0n:")
	w.f("      Nil{}")
	w.f("    case 1n+p:")
	w.f("      match ms:")
	w.f("        case Nil{}:")
	w.f("          Nil{}")
	w.f("        case Con{+x, rest}:")
	w.f("          match x:")
	w.f("            case %s:", m.pattern(func(*slot) bool { return true }))
	var kvars, kcalls []string
	kOf := map[*slot]string{}
	for _, s := range m.slots() {
		var src string
		if s.O != nil {
			has := false
			for _, f := range s.O.Members {
				if f.SelfRec {
					has = true
				}
			}
			if !has {
				continue
			}
			src = fmt.Sprintf("%s.src.%s(%s)", n, s.Name, s.Bind)
		} else if s.F.SelfRec {
			if s.F.Card == cRepeated {
				src = s.Bind
			} else {
				src = fmt.Sprintf("%s.src.%s(%s)", n, s.F.Name, s.Bind)
			}
		} else {
			continue
		}
		kv := "k_" + s.Name
		kOf[s] = kv
		kvars = append(kvars, kv)
		kcalls = append(kcalls, fmt.Sprintf("%s.tj_all(p, %s)", n, src))
	}
	if len(kvars) == 1 {
		w.f("              %s = %s", kvars[0], kcalls[0])
	} else {
		w.f("              %s = %s", strings.Join(kvars, " "), strings.Join(kcalls, " "))
	}
	acc := "Nil{}"
	for _, s := range m.slots() {
		switch {
		case s.O != nil && kOf[s] != "":
			acc = fmt.Sprintf("%s.jput.%s(%s, %s, %s)", n, s.Name, s.Bind, kOf[s], acc)
		case s.F != nil && s.F.SelfRec && s.F.Card == cRepeated:
			acc = fmt.Sprintf("Pj.put.repeated.message(%s, %s, %s)", q(s.F.JSON), kOf[s], acc)
		case s.F != nil && s.F.SelfRec:
			acc = fmt.Sprintf("%s.jput.one(%s, %s, %s)", n, q(s.F.JSON), kOf[s], acc)
		default:
			acc = m.jputExpr(s, acc)
		}
	}
	w.f("              Con{Pj.obj(%s), %s.tj_all(fuel, rest)}", acc, n)
	w.blank()
	w.f("def %s.tj.first(xs: %s) -> Json.Val:", n, jvalsT)
	w.f("  match xs:")
	w.f("    case Nil{}:")
	w.f("      Pj.obj(Nil{})")
	w.f("    case Con{h, t}:")
	w.f("      h")
	w.blank()
	w.f("def %s.to_json(m: %s) -> Json.Val:", n, n)
	w.f("  %s.tj.first(%s.tj_all(%s, Con{m, Nil{}}))", n, n, depthLimit)
	w.blank()
}

// ---------------------------------------------------------------- reader

// steps are the per-field reading steps in a fixed order (self-recursive ones last).
func (u *unit) jsonReaders(w *writer, m *message) {
	n := m.Name
	KS := m.jstate()
	RS := m.jres(KS)
	var normal, self []*field
	for _, f := range m.Decl {
		if f.SelfRec {
			self = append(self, f)
		} else {
			normal = append(normal, f)
		}
	}
	if m.Rec {
		w.f("def %s.first(ms: List<&2, %s>) -> Maybe<&2, %s>:", n, n, n)
		w.f("  match ms:")
		w.f("    case Nil{}:")
		w.f("      None{}")
		w.f("    case Con{h, t}:")
		w.f("      Some{h}")
		w.blank()
		w.f("def %s.head(ms: List<&2, %s>) -> %s:", n, n, n)
		w.f("  match ms:")
		w.f("    case Nil{}:")
		w.f("      %s.default()", n)
		w.f("    case Con{h, t}:")
		w.f("      h")
		w.blank()
	}
	for _, f := range normal {
		s := m.slotOf(f)
		w.f("def %s.jf.%s.k(t: Json.Val & %s, m: %s) -> %s:", n, f.Name, kvsT, n, RS)
		w.f("  match t:")
		w.f("    case Tuple{v, rest}:")
		w.f("      do %s:", RS)
		var set string
		switch {
		case f.Card == cMap:
			key, val := f.Msg.Decl[0], f.Msg.Decl[1]
			w.f("        r : %s <- Pj.read.map(~%s, ~%s, ~%s, ~Pj.read.key.%s, ~%s, ~%s.mk, v)", s.Type, key.Elem, val.Elem, f.Elem, key.RT, val.jsonReader(), f.Elem)
			set = fmt.Sprintf("%s.set.%s(r, m)", n, s.Name)
		case f.Card == cRepeated:
			if f.isMsg() || f.Kind == protoreflect.EnumKind {
				w.f("        r : %s <- Pj.read.repeated(~%s, ~%s, v)", s.Type, f.Elem, f.jsonReader())
			} else {
				w.f("        r : %s <- Pj.read.repeated.%s(v)", s.Type, f.RT)
			}
			set = fmt.Sprintf("%s.set.%s(r, m)", n, s.Name)
		case f.Card == cOneof:
			w.f("        r : Maybe<&2, %s> <- Pj.read.opt(~%s, ~%s, v)", f.Elem, f.Elem, f.jsonReader())
			set = fmt.Sprintf("%s.set.pick.%s(r, m)", n, f.Name)
		case f.Card == cOptional || f.isMsg():
			w.f("        r : Maybe<&2, %s> <- Pj.read.opt(~%s, ~%s, v)", f.Elem, f.Elem, f.jsonReader())
			set = fmt.Sprintf("%s.set.%s(r, m)", n, s.Name)
		default:
			w.f("        r : %s <- %s(v)", f.Elem, readerCall(f))
			set = fmt.Sprintf("%s.set.%s(r, m)", n, s.Name)
		}
		w.f("        return (rest, %s)", set)
		w.blank()
		w.f("def %s.jf.%s(st: %s) -> %s:", n, f.Name, KS, RS)
		w.f("  match st:")
		w.f("    case Tuple{kvs, m}:")
		w.f("      %s.jf.%s.k(Pj.take(kvs, %s, %s), m)", n, f.Name, q(f.JSON), q(f.Proto))
		w.blank()
	}
	recT := fmt.Sprintf("%s -> %s", jvalsT, m.jres("List<&2, "+n+">"))
	for _, f := range self {
		s := m.slotOf(f)
		w.f("def %s.jf.%s.k(rec: %s, t: Json.Val & %s, m: %s) -> %s:", n, f.Name, recT, kvsT, n, RS)
		w.f("  match t:")
		w.f("    case Tuple{v, rest}:")
		w.f("      do %s:", RS)
		if f.Card == cRepeated {
			w.f("        vs : %s <- json_items(v)", jvalsT)
			w.f("        ms : List<&2, %s> <- rec(vs)", n)
			w.f("        return (rest, %s.set.%s(ms, m))", n, s.Name)
		} else {
			w.f("        ms : List<&2, %s> <- rec(json_single(v))", n)
			if f.Card == cOneof {
				w.f("        return (rest, %s.set.pick.%s(%s.first(ms), m))", n, f.Name, n)
			} else {
				w.f("        return (rest, %s.set.%s(%s.first(ms), m))", n, s.Name, n)
			}
		}
		w.blank()
		w.f("def %s.jf.%s(rec: %s, st: %s) -> %s:", n, f.Name, recT, KS, RS)
		w.f("  match st:")
		w.f("    case Tuple{kvs, m}:")
		w.f("      %s.jf.%s.k(rec, Pj.take(kvs, %s, %s), m)", n, f.Name, q(f.JSON), q(f.Proto))
		w.blank()
	}
	w.f("def %s.jf.finish(st: %s) -> %s:", n, KS, n)
	w.f("  match st:")
	w.f("    case Tuple{kvs, m}:")
	w.f("      m")
	w.blank()
	if m.Rec {
		// fj_all
		w.f("def %s.fj_all(+fuel: Nat, vs: %s) -> %s:", n, jvalsT, m.jres("List<&2, "+n+">"))
		w.f("  match fuel:")
		w.f("    case 0n:")
		w.f("      Fail{\"message nesting too deep\"}")
		w.f("    case 1n+p:")
		w.f("      match vs:")
		w.f("        case Nil{}:")
		w.f("          Done{Nil{}}")
		w.f("        case Con{v, rest}:")
		w.f("          do %s:", m.jres("List<&2, "+n+">"))
		w.f("            kvs : %s <- Pj.fields(v)", kvsT)
		prev := fmt.Sprintf("(kvs, %s.default())", n)
		i := 0
		bind := func(call string) {
			i++
			w.f("            s%d : %s <- %s", i, KS, call)
		}
		for idx, f := range normal {
			if idx == 0 {
				bind(fmt.Sprintf("%s.jf.%s(%s)", n, f.Name, prev))
			} else {
				bind(fmt.Sprintf("%s.jf.%s(s%d)", n, f.Name, i))
			}
		}
		cur := prev
		if i > 0 {
			cur = fmt.Sprintf("s%d", i)
		}
		for _, f := range self {
			bind(fmt.Sprintf("%s.jf.%s(xs => %s.fj_all(p, xs), %s)", n, f.Name, n, cur))
			cur = fmt.Sprintf("s%d", i)
		}
		w.f("            tail : List<&2, %s> <- %s.fj_all(fuel, rest)", n, n)
		w.f("            return Con{%s.jf.finish(%s), tail}", n, cur)
		w.blank()
		w.f("def %s.from_json(v: Json.Val) -> %s:", n, m.rtype())
		w.f("  do %s:", m.rtype())
		w.f("    ms : List<&2, %s> <- %s.fj_all(%s, Con{v, Nil{}})", n, n, depthLimit)
		w.f("    return %s.head(ms)", n)
		w.blank()
		return
	}
	w.f("def %s.from_json(v: Json.Val) -> %s:", n, m.rtype())
	w.f("  do %s:", m.rtype())
	w.f("    kvs : %s <- Pj.fields(v)", kvsT)
	cur := fmt.Sprintf("(kvs, %s.default())", n)
	for i, f := range normal {
		w.f("    s%d : %s <- %s.jf.%s(%s)", i+1, KS, n, f.Name, cur)
		cur = fmt.Sprintf("s%d", i+1)
	}
	w.f("    return %s.jf.finish(%s)", n, cur)
	w.blank()
}

func readerCall(f *field) string {
	if f.Kind == protoreflect.EnumKind {
		return f.EnumRef + ".read_json"
	}
	return "Pj.read." + f.RT
}
