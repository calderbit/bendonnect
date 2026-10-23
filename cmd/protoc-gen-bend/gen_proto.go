package main

import (
	"fmt"
	"strings"

	"google.golang.org/protobuf/reflect/protoreflect"
)

const fieldsT = "List<&1, Pb.Field>"
const itemsT = "List<&1, List<&1, Pb.Field>>"

func (m *message) rtype() string { return fmt.Sprintf("Result<&2, &1, String, %s>", m.Name) }

func (f *field) isNumericRepeated() bool {
	switch f.Kind {
	case protoreflect.StringKind, protoreflect.BytesKind, protoreflect.MessageKind:
		return false
	}
	return true
}

// ---------------------------------------------------------------- decode

func (u *unit) protoDecode(w *writer, m *message) {
	n := m.Name
	R := m.rtype()
	hasRev := false
	for _, f := range m.Decl {
		if f.isRepeatedLike() {
			hasRev = true
		}
	}
	// apply: read a non-message field into the accumulator
	for _, f := range m.Decl {
		s := m.slotOf(f)
		if f.isMsg() {
			w.f("def %s.attach.%s(sub: %s, m: %s) -> %s:", n, f.Name, f.Elem, n, n)
			w.f("  match m:")
			own := f.isRepeatedLike()
			w.f("    case %s:", m.pattern(func(x *slot) bool { return x != s || own }))
			var e string
			switch {
			case f.Card == cRepeated || f.Card == cMap:
				e = "Con{sub, " + s.Bind + "}"
			case f.Card == cOneof:
				e = f.Member + "{sub}"
			case m.IsEntry:
				e = "sub"
			default:
				e = "Some{sub}"
			}
			w.f("      %s", m.ctor(map[*slot]string{s: e}))
			w.blank()
			continue
		}
		w.f("def %s.apply.%s(v: Pb.Value, m: %s) -> %s:", n, f.Name, n, R)
		w.f("  match m:")
		own := f.Card == cRepeated
		w.f("    case %s:", m.pattern(func(x *slot) bool { return x != s || own }))
		w.f("      do %s:", R)
		var e string
		if f.Card == cRepeated {
			w.f("        r : List<&2, %s> <- Pbr.read.repeated.%s(v, %s)", f.Elem, f.RT, s.Bind)
			e = "r"
		} else {
			w.f("        r : %s <- Pbr.read.%s(v)", f.Elem, f.RT)
			switch f.Card {
			case cOptional:
				e = "Some{r}"
			case cOneof:
				e = f.Member + "{r}"
			default:
				e = "r"
			}
		}
		w.f("        return %s", m.ctor(map[*slot]string{s: e}))
		w.blank()
	}
	if hasRev {
		w.f("def %s.finish(m: %s) -> %s:", n, n, n)
		w.f("  match m:")
		w.f("    case %s:", m.pattern(func(*slot) bool { return true }))
		repl := map[*slot]string{}
		for _, f := range m.Decl {
			if f.isRepeatedLike() {
				repl[m.slotOf(f)] = fmt.Sprintf("Pbr.rev(%s, %s)", f.Elem, f.Bind)
			}
		}
		w.f("      %s", m.ctor(repl))
		w.blank()
	}
	fin := "acc"
	if hasRev {
		fin = n + ".finish(acc)"
	}
	w.f("def %s.dec(+fuel: Nat, fields: %s, acc: %s) -> %s:", n, fieldsT, n, R)
	w.f("  match fuel:")
	w.f("    case 0n:")
	w.f("      Fail{\"message nesting too deep\"}")
	w.f("    case 1n+p:")
	w.f("      match fields:")
	w.f("        case Nil{}:")
	w.f("          Done{%s}", fin)
	w.f("        case Con{Pb.Field{n, v}, rest}:")
	if len(m.Decl) == 0 {
		w.f("          %s.dec(fuel, rest, acc)", n)
	} else {
		w.f("          match n:")
		for _, f := range m.Fields {
			w.f("            case %d:", f.Num)
			w.f("              do %s:", R)
			if f.isMsg() {
				w.f("                fs : %s <- Pbr.read.message(v)", fieldsT)
				w.f("                sub : %s <- %s.dec(p, fs, %s.default())", f.Elem, f.Elem, f.Elem)
				w.f("                %s.dec(fuel, rest, %s.attach.%s(sub, acc))", n, n, f.Name)
			} else {
				w.f("                acc2 : %s <- %s.apply.%s(v, acc)", n, n, f.Name)
				w.f("                %s.dec(fuel, rest, acc2)", n)
			}
		}
		w.f("            case _:")
		w.f("              %s.dec(fuel, rest, acc)", n)
	}
	w.blank()
	if m.IsEntry {
		return
	}
	w.f("def %s.decode_proto(b: Bytes.Bytes) -> %s:", n, R)
	w.f("  do %s:", R)
	w.f("    fs : %s <- Pbr.decode(b)", fieldsT)
	w.f("    %s.dec(%s, fs, %s.default())", n, depthLimit, n)
	w.blank()
}

// ---------------------------------------------------------------- encode

// scalarExpr is the field-list expression for a field that needs no helper.
func (m *message) scalarExpr(f *field, x string) (string, bool) {
	switch {
	case f.Card == cSingle && !f.isMsg():
		if m.IsEntry {
			return fmt.Sprintf("Pbr.field.%s.always(%d, %s)", f.RT, f.Num, x), true
		}
		return fmt.Sprintf("Pbr.field.%s(%d, %s)", f.RT, f.Num, x), true
	case f.Card == cSingle && f.isMsg() && m.IsEntry:
		return fmt.Sprintf("Pbr.field.message(%d, %s.fields(%s))", f.Num, f.Elem, x), true
	case f.Card == cRepeated && !f.isMsg():
		if f.isNumericRepeated() && !f.Packed {
			return fmt.Sprintf("Pbr.rep.each(~%s, ~Pbr.value.%s, %d, %s)", f.Elem, f.RT, f.Num, x), true
		}
		return fmt.Sprintf("Pbr.field.repeated.%s(%d, %s)", f.RT, f.Num, x), true
	}
	return "", false
}

// payload encodes one oneof/optional payload value x.
func (f *field) payloadExpr(x string) string {
	if f.isMsg() {
		return fmt.Sprintf("Pbr.field.message(%d, %s.fields(%s))", f.Num, f.Elem, x)
	}
	return fmt.Sprintf("Pbr.field.%s.always(%d, %s)", f.RT, f.Num, x)
}

func (u *unit) encHelpers(w *writer, m *message) {
	n := m.Name
	for _, f := range m.Decl {
		if f.Card == cOneof || f.SelfRec {
			continue
		}
		if _, ok := m.scalarExpr(f, "x"); ok {
			continue
		}
		switch f.Card {
		case cOptional, cSingle:
			w.f("def %s.f.%s(x: Maybe<&2, %s>) -> %s:", n, f.Name, f.Elem, fieldsT)
			w.f("  match x:")
			w.f("    case None{}:")
			w.f("      Nil{}")
			w.f("    case Some{s}:")
			w.f("      %s", f.payloadExpr("s"))
			w.blank()
		case cRepeated, cMap:
			w.f("def %s.f.%s.items(xs: List<&2, %s>) -> %s:", n, f.Name, f.Elem, itemsT)
			w.f("  match xs:")
			w.f("    case Nil{}:")
			w.f("      Nil{}")
			w.f("    case Con{h, t}:")
			w.f("      Con{%s.fields(h), %s.f.%s.items(t)}", f.Elem, n, f.Name)
			w.blank()
			w.f("def %s.f.%s(xs: List<&2, %s>) -> %s:", n, f.Name, f.Elem, fieldsT)
			w.f("  Pbr.field.repeated.message(%d, %s.f.%s.items(xs))", f.Num, n, f.Name)
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
			w.f("def %s.src.%s(o: %s) -> List<&2, %s>:", n, o.Name, o.Type, n)
			w.f("  match o:")
			for _, f := range o.Members {
				if f.SelfRec {
					w.f("    case %s{s}:", f.Member)
					w.f("      Con{s, Nil{}}")
				}
			}
			w.f("    case _:")
			w.f("      Nil{}")
			w.blank()
			w.f("def %s.put.%s(o: %s, k: %s) -> %s:", n, o.Name, o.Type, itemsT, fieldsT)
			w.f("  match o:")
			w.f("    case %s.None{}:", o.Type)
			w.f("      Nil{}")
			for _, f := range o.Members {
				if f.SelfRec {
					w.f("    case %s{s}:", f.Member)
					w.f("      Pbr.field.repeated.message(%d, k)", f.Num)
				} else {
					w.f("    case %s{s}:", f.Member)
					w.f("      %s", f.payloadExpr("s"))
				}
			}
			w.blank()
			continue
		}
		w.f("def %s.f.%s(o: %s) -> %s:", n, o.Name, o.Type, fieldsT)
		w.f("  match o:")
		w.f("    case %s.None{}:", o.Type)
		w.f("      Nil{}")
		for _, f := range o.Members {
			w.f("    case %s{s}:", f.Member)
			w.f("      %s", f.payloadExpr("s"))
		}
		w.blank()
	}
	// Maybe-valued self-recursive fields need a list view
	for _, f := range m.Decl {
		if f.SelfRec && (f.Card == cSingle || f.Card == cOptional) {
			w.f("def %s.src.%s(x: Maybe<&2, %s>) -> List<&2, %s>:", n, f.Name, n, n)
			w.f("  match x:")
			w.f("    case None{}:")
			w.f("      Nil{}")
			w.f("    case Some{s}:")
			w.f("      Con{s, Nil{}}")
			w.blank()
		}
	}
}

// fieldCall is the expression producing a slot's field list in the non-recursive form.
func (m *message) slotExpr(s *slot) string {
	if s.O != nil {
		return fmt.Sprintf("%s.f.%s(%s)", m.Name, s.Name, s.Bind)
	}
	f := s.F
	if e, ok := m.scalarExpr(f, s.Bind); ok {
		return e
	}
	return fmt.Sprintf("%s.f.%s(%s)", m.Name, f.Name, s.Bind)
}

func (u *unit) protoEncode(w *writer, m *message) {
	n := m.Name
	u.encHelpers(w, m)
	if !m.Rec {
		w.f("def %s.fields(m: %s) -> %s:", n, n, fieldsT)
		slots := m.slotsByNumber()
		if len(slots) == 0 {
			w.f("  Nil{}")
		} else {
			w.f("  match m:")
			w.f("    case %s:", m.pattern(func(*slot) bool { return true }))
			var parts []string
			for _, s := range slots {
				parts = append(parts, m.slotExpr(s))
			}
			w.f("      Pbr.cat.all([%s])", strings.Join(parts, ", "))
		}
		w.blank()
	} else {
		u.encRec(w, m)
	}
	if m.IsEntry {
		return
	}
	w.f("def %s.encode_proto(m: %s) -> Bytes.Bytes:", n, n)
	w.f("  Pbr.encode(%s.fields(m))", n)
	w.blank()
}

// encRec: a self-recursive message is encoded by one def over lists of messages whose first
// argument is a depth counter, so Bend's termination checker accepts the recursion.
func (u *unit) encRec(w *writer, m *message) {
	n := m.Name
	w.f("def %s.enc_all(+fuel: Nat, ms: List<&2, %s>) -> %s:", n, n, itemsT)
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
		kcalls = append(kcalls, fmt.Sprintf("%s.enc_all(p, %s)", n, src))
	}
	if len(kvars) == 1 {
		w.f("              %s = %s", kvars[0], kcalls[0])
	} else {
		w.f("              %s = %s", strings.Join(kvars, " "), strings.Join(kcalls, " "))
	}
	var parts []string
	for _, s := range m.slotsByNumber() {
		switch {
		case s.O != nil && kOf[s] != "":
			parts = append(parts, fmt.Sprintf("%s.put.%s(%s, %s)", n, s.Name, s.Bind, kOf[s]))
		case s.F != nil && s.F.SelfRec:
			parts = append(parts, fmt.Sprintf("Pbr.field.repeated.message(%d, %s)", s.F.Num, kOf[s]))
		default:
			parts = append(parts, m.slotExpr(s))
		}
	}
	w.f("              Con{Pbr.cat.all([%s]), %s.enc_all(fuel, rest)}", strings.Join(parts, ", "), n)
	w.blank()
	w.f("def %s.fields.first(xs: %s) -> %s:", n, itemsT, fieldsT)
	w.f("  match xs:")
	w.f("    case Nil{}:")
	w.f("      Nil{}")
	w.f("    case Con{h, t}:")
	w.f("      h")
	w.blank()
	w.f("def %s.fields(m: %s) -> %s:", n, n, fieldsT)
	w.f("  %s.fields.first(%s.enc_all(%s, Con{m, Nil{}}))", n, n, depthLimit)
	w.blank()
}
