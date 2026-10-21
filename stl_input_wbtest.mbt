///|
fn assert_binary_rejected_everywhere(data : Bytes) -> Unit raise {
  assert_true(parse_stl_binary(data) is Err(_))
  assert_true(stream_stl_binary(data) is Err(_))
  assert_true(parse_stl(data) is Err(_))
  assert_true(parse_mesh(data) is Err(_))
  for chunk in [1, 3, 7, 49, 50, 83, 84, 85, 134, 4096] {
    assert_true(scan_in_chunks(data, chunk) is Err(_))
  }
}

///|
fn assert_ascii_rejected_everywhere(text : String) -> Unit raise {
  let full_error = match parse_stl_ascii(text) {
    Err(message) => message
    Ok(_) => fail("全量 ASCII 入口不应接受坏输入")
  }
  match stream_stl_ascii(text) {
    Err(message) => assert_eq(message, full_error)
    Ok(_) => fail("流式 ASCII 入口不应接受坏输入")
  }
  assert_true(parse_stl(@utf8.encode(text)) is Err(_))
  assert_true(parse_mesh(@utf8.encode(text)) is Err(_))
}

///|
test "STL contract: binary trailing bytes are rejected by every entry" {
  let original = single_triangle_binary()
  for size in [1, 2, 49, 50, 51, 100] {
    for byte in [b'\x00', b'x'] {
      let bytes = Array::makei(original.length() + size, i => {
        if i < original.length() {
          original[i]
        } else {
          byte
        }
      })
      assert_binary_rejected_everywhere(Bytes::from_array(bytes))
    }
  }
}

///|
test "STL contract: truncated headers records and zero triangles are rejected" {
  let original = single_triangle_binary()
  for size in [0, 1, 79, 80, 83, 84, 85, 100, 133] {
    assert_binary_rejected_everywhere(slice_bytes(original, 0, size))
  }
  assert_binary_rejected_everywhere(Bytes::from_array(Array::make(84, b'\x00')))
  let bytes = Array::makei(original.length(), i => original[i])
  for i in [80, 81, 82, 83] {
    bytes[i] = b'\xff'
  }
  assert_binary_rejected_everywhere(Bytes::from_array(bytes))
}

///|
test "STL contract: finite normals and vertices are required even in statistics" {
  let original = single_triangle_binary()
  for offset in [84, 88, 92, 96, 108, 120] {
    for last in [b'\x80', b'\xc0'] {
      let bytes = Array::makei(original.length(), i => original[i])
      bytes[offset] = b'\x00'
      bytes[offset + 1] = b'\x00'
      bytes[offset + 2] = last
      bytes[offset + 3] = b'\x7f'
      assert_binary_rejected_everywhere(Bytes::from_array(bytes))
    }
  }
}

///|
test "STL contract: every split boundary preserves valid binary statistics" {
  let bytes = single_triangle_binary()
  let mesh = parse_stl_binary(bytes).unwrap()
  assert_same_as_full(
    stream_stl_binary(bytes).unwrap(),
    mesh,
    "完整二进制",
  )
  for split = 0; split <= bytes.length(); split = split + 1 {
    let scanner = StlScanner::new()
    scanner.feed(slice_bytes(bytes, 0, split))
    scanner.feed(b"")
    scanner.feed(slice_bytes(bytes, split, bytes.length()))
    assert_same_as_full(scanner.finish().unwrap(), mesh, "分割点 \{split}")
    assert_eq(scanner.storage().pending_bytes, 0)
  }
}

///|
test "STL contract: late trailing bytes invalidate a previously complete scanner" {
  let scanner = StlScanner::new()
  scanner.feed(single_triangle_binary())
  assert_true(scanner.finish() is Ok(_))
  scanner.feed(b"x")
  assert_true(scanner.finish() is Err(_))
}

///|
test "STL contract: bad ASCII facet vertex counts cannot be skipped" {
  let valid = "facet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\n"
  for count in [0, 1, 2, 4, 5] {
    let bad = StringBuilder()
    bad.write_string(valid + "facet normal 0 0 1\nouter loop\n")
    for i = 0; i < count; i = i + 1 {
      bad.write_string("vertex \{i} 0 0\n")
    }
    bad.write_string("endloop\nendfacet\n")
    assert_ascii_rejected_everywhere(bad.to_string())
  }
}

///|
test "STL contract: ASCII incomplete nested and unknown records fail consistently" {
  let valid = "facet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\n"
  for
    suffix in [
      "facet normal 0 0 1\n", "facet normal 0 0 1\nouter loop\nvertex 0 0 0\n", "facet normal 0 0 1\nfacet normal 0 0 1\n",
      "vertex 0 0 0\n", "endfacet\n", "trailing garbage\n", "facet normal 0 0 nan\n",
      "facet normal 0 0 1 extra\n",
    ] {
    assert_ascii_rejected_everywhere(valid + suffix)
  }
  assert_ascii_rejected_everywhere(valid.replace_all(old="endloop\n", new=""))
  assert_ascii_rejected_everywhere(valid.replace_all(old="endfacet\n", new=""))
  assert_ascii_rejected_everywhere(
    valid.replace_all(old="vertex 1 0 0", new="vertex inf 0 0"),
  )
}

///|
test "STL contract: tabs CRLF zero normals and degenerate geometry remain readable" {
  let text = "solid example\nfacet normal 0 0 0\nouter loop\nvertex 0 0 0\nvertex 0 0 0\nvertex 0 0 0\nendloop\nendfacet\nendsolid example\n"
  let spaced = to_crlf(text.replace_all(old=" ", new="\t"))
  let mesh = parse_stl_ascii(spaced).unwrap()
  assert_eq(mesh.triangle_count(), 1)
  assert_eq(validate_default(mesh).degenerate_count, 1)
  assert_same_as_full(
    stream_stl_ascii(spaced).unwrap(),
    mesh,
    "合法退化面",
  )
  assert_eq(parse_mesh(@utf8.encode(spaced)).unwrap().triangle_count(), 1)
  assert_eq(parse_stl(@utf8.encode(spaced)).unwrap().triangle_count(), 1)
}
