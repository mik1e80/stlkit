///|
fn format_long_header_stl() -> String {
  let header = StringBuilder()
  for i = 0; i < 2048; i = i + 1 {
    header.write_string("x")
  }
  let name = header.to_string()
  let out = StringBuilder()
  for line in unit_cube_ascii().split("\n") {
    if line.has_prefix("solid ") {
      out.write_string("solid \{name}\n")
    } else if line.has_prefix("endsolid") {
      out.write_string("endsolid \{name}\n")
    } else {
      out.write_string("\{line}\n")
    }
  }
  out.to_string()
}

///|
test "format: long ASCII STL headers survive automatic routing" {
  let data = @utf8.encode(format_long_header_stl())
  assert_true(detect_format(data) is Ascii)
  assert_eq(parse_stl(data).unwrap().triangle_count(), 12)
  assert_eq(parse_mesh(data).unwrap().triangle_count(), 12)
}

///|
test "format: OBJ comments containing STL keywords are not STL" {
  let data = @utf8.encode(
    "# solid facet normal vertex\no vertex_solid\n" + cube_obj(),
  )
  assert_true(detect_format(data) is Obj)
  assert_eq(parse_mesh(data).unwrap().triangle_count(), 12)
}

///|
test "format: OBJ is explicit and the STL-only entry rejects it" {
  let input = @utf8.encode(cube_obj())
  assert_true(detect_format(input) is Obj)
  assert_true(parse_stl(input) is Err(_))
  assert_eq(parse_mesh(input).unwrap().triangle_count(), 12)
}

///|
test "format: delayed text records and CRLF do not depend on a sniff window" {
  let prefix = StringBuilder()
  for i = 0; i < 128; i = i + 1 {
    prefix.write_string("# a long comment mentioning solid facet vertex\n")
  }
  let obj = @utf8.encode(to_crlf(prefix.to_string() + cube_obj()))
  assert_true(detect_format(obj) is Obj)
  assert_eq(parse_mesh(obj).unwrap().triangle_count(), 12)
  let stl = @utf8.encode(to_crlf(format_long_header_stl()))
  assert_true(detect_format(stl) is Ascii)
  assert_eq(parse_mesh(stl).unwrap().triangle_count(), 12)
}

///|
test "format: missing solid headers still route to the ASCII STL parser" {
  let text = "facet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\n"
  let data = @utf8.encode(text)
  assert_true(detect_format(data) is Ascii)
  assert_eq(parse_mesh(data).unwrap().triangle_count(), 1)
}

///|
test "format: recognized malformed text retains its parser diagnostic" {
  let obj = @utf8.encode("v bad 0 0\nf 1 2 3\n")
  assert_true(detect_format(obj) is Obj)
  assert_true(parse_mesh(obj) is Err(_))
  let stl = @utf8.encode("solid a\nfacet normal 0 0 bad\nendsolid a\n")
  assert_true(detect_format(stl) is Ascii)
  assert_true(parse_mesh(stl) is Err(_))
  assert_true(detect_format(@utf8.encode("# solid facet vertex\n")) is Unknown)
}

///|
test "format: text-like binary headers do not override STL length evidence" {
  let bytes = single_triangle_binary().to_fixedarray()
  let header = @utf8.encode("solid v facet vertex").to_fixedarray()
  for i = 0; i < header.length(); i = i + 1 {
    bytes[i] = header[i]
  }
  let data = Bytes::from_array(bytes)
  assert_true(detect_format(data) is Binary)
  assert_eq(parse_mesh(data).unwrap().triangle_count(), 1)
}

///|
test "format: arbitrary text has an unknown-format diagnostic" {
  match parse_mesh(@utf8.encode("This is not a mesh file\n")) {
    Ok(_) => fail("Unrecognized text must not be accepted")
    Err(message) => assert_true(message.contains("无法识别网格格式"))
  }
}
