///|
fn assert_ply_header_error(data : Bytes, expected : String) -> Unit raise {
  for lenient in [false, true] {
    match parse_ply(data, lenient_ascii=lenient) {
      Ok(_) => fail("坏 PLY 声明 / 尾部不应被接受")
      Err(message) => assert_true(message.contains(expected))
    }
  }
  assert_true(parse_mesh(data) is Err(_))
}

///|
fn header_triangle() -> String {
  @utf8.decode_lossy(
    schema_ply("ascii", [
      "property float x", "property float y", "property float z",
    ]),
  )
}

///|
test "PLY header requires an explicit format instead of default ASCII" {
  let missing = header_triangle().replace_all(old="format ascii 1.0\n", new="")
  assert_ply_header_error(@utf8.encode(missing), "缺少 format")
}

///|
test "PLY header rejects duplicate format including conflicting encodings" {
  for
    declaration in [
      "format ascii 1.0", "format binary_big_endian 1.0", "format ascii",
    ] {
    let bad = header_triangle().replace_all(
      old="format ascii 1.0\n",
      new="format ascii 1.0\n\{declaration}\n",
    )
    assert_ply_header_error(@utf8.encode(bad), "重复声明 format")
    let late = header_triangle().replace_all(
      old="end_header\n",
      new="\{declaration}\nend_header\n",
    )
    assert_ply_header_error(@utf8.encode(late), "重复声明 format")
  }
}

///|
test "PLY format needs exactly an encoding and version" {
  for declaration in ["format", "format ascii", "format ascii 1.0 extra"] {
    let bad = header_triangle().replace_all(
      old="format ascii 1.0",
      new=declaration,
    )
    assert_ply_header_error(@utf8.encode(bad), "完整声明")
  }
}

///|
test "PLY accepts only literal version 1.0 and recognized encodings" {
  for kind in ["ascii", "binary_little_endian", "binary_big_endian"] {
    for version in ["0.9", "1", "1.00", "2.0", "9.9", "nan"] {
      let bad = header_triangle().replace_all(
        old="format ascii 1.0",
        new="format \{kind} \{version}",
      )
      assert_ply_header_error(@utf8.encode(bad), "只支持 PLY 1.0")
    }
  }
  assert_ply_header_error(
    @utf8.encode(
      header_triangle().replace_all(
        old="format ascii 1.0",
        new="format binary_unknown 1.0",
      ),
    ),
    "format 认不出来",
  )
}

///|
test "PLY format must follow magic before comments or elements" {
  for prefix in ["element ignored 0\n", "comment before format\n", "\n"] {
    let bad = header_triangle().replace_all(old="ply\n", new="ply\n\{prefix}")
    assert_ply_header_error(@utf8.encode(bad), "必须紧跟 ply")
  }
  let late = header_triangle()
    .replace_all(old="format ascii 1.0\n", new="")
    .replace_all(old="end_header\n", new="format ascii 1.0\nend_header\n")
  assert_ply_header_error(@utf8.encode(late), "位于 element 之前")
}

///|
test "PLY valid declarations retain tabs CRLF comments and all three encodings" {
  let (verts, faces) = cube_ply_parts()
  let ascii = @utf8.decode_lossy(ascii_ply("", "", verts, faces)).replace_all(
    old="format ascii 1.0\n",
    new="format\tascii\t1.0\ncomment format binary_big_endian 9.9\n",
  )
  for
    data in [
      @utf8.encode(to_crlf(ascii)),
      binary_ply(false, verts, faces),
      binary_ply(true, verts, faces),
    ] {
    let mesh = parse_ply(data).unwrap()
    assert_eq(mesh.triangle_count(), 12)
    assert_true((mesh.volume() - 1.0).abs() < 1.0e-9)
    assert_eq(parse_mesh(data).unwrap().triangle_count(), 12)
  }
}

///|
test "PLY binary rejects every extra byte including padding and complete scalars" {
  let (verts, faces) = cube_ply_parts()
  for big in [false, true] {
    let original = binary_ply(big, verts, faces)
    for size in [1, 2, 3, 4, 12, 50] {
      for byte in [b'\x00', b' ', b'x', b'\xff'] {
        let input = Bytes::from_array(
          Array::makei(original.length() + size, i => {
            if i < original.length() {
              original[i]
            } else {
              byte
            }
          }),
        )
        assert_ply_header_error(input, "多余尾部字节")
      }
    }
  }
}

///|
test "PLY binary consumes declared unknown scalar and list elements before EOF" {
  let (verts, faces) = cube_ply_parts()
  for big in [false, true] {
    let original = binary_ply(big, verts, faces)
    let at = find_header_end(original).unwrap()
    let header = @utf8.decode_lossy(original[:at]).replace_all(
      old="end_header\n",
      new="element metadata 1\nproperty int code\nproperty list uchar int values\nelement empty 0\nproperty float value\nend_header\n",
    )
    let header_bytes = @utf8.encode(header)
    let bytes = Array::makei(header_bytes.length(), i => header_bytes[i])
    for b in original[at:] {
      bytes.push(b)
    }
    ply_push_u32(bytes, 7U, big)
    bytes.push(b'\x02')
    ply_push_u32(bytes, 1U, big)
    ply_push_u32(bytes, 2U, big)
    let input = Bytes::from_array(bytes)
    assert_eq(parse_ply(input).unwrap().triangle_count(), 12)
    bytes.push(b'\x00')
    assert_ply_header_error(Bytes::from_array(bytes), "多余尾部字节")
  }
}

///|
test "PLY binary truncation remains an error instead of an EOF success" {
  let (verts, faces) = cube_ply_parts()
  for big in [false, true] {
    let data = binary_ply(big, verts, faces)
    for missing in [1, 2, 4, 12, 49] {
      let cut = slice_bytes(data, 0, data.length() - missing)
      assert_true(parse_ply(cut) is Err(_))
      assert_true(parse_ply(cut, lenient_ascii=true) is Err(_))
      assert_true(parse_mesh(cut) is Err(_))
    }
  }
}
