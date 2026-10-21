///|
// 自制三角形：按给定声明编码正文，让坏 schema 也有完整、可消费的数据。
fn schema_ply(kind : String, properties : Array[String]) -> Bytes {
  let header = "ply\nformat \{kind} 1.0\nelement vertex 3\n" +
    properties.join("\n") +
    "\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n"
  let header_bytes = @utf8.encode(header)
  let out = Array::makei(header_bytes.length(), i => header_bytes[i])
  let big = kind == "binary_big_endian"
  for row = 0; row < 3; row = row + 1 {
    let words : Array[String] = []
    for property in properties {
      let is_list = property.has_prefix("property list")
      let value = if (property.has_suffix(" x") && row == 1) ||
        (property.has_suffix(" y") && row == 2) {
        1.0
      } else {
        0.0
      }
      if kind == "ascii" {
        if is_list {
          words.push("1")
        }
        words.push(value.to_string())
      } else {
        if is_list {
          out.push(b'\x01')
        }
        ply_push_u32(out, f32_bits(value), big)
      }
    }
    if kind == "ascii" {
      for b in @utf8.encode(words.join(" ") + "\n") {
        out.push(b)
      }
    }
  }
  if kind == "ascii" {
    for b in b"3 0 1 2\n" {
      out.push(b)
    }
  } else {
    out.push(b'\x03')
    for i in [0U, 1U, 2U] {
      ply_push_u32(out, i, big)
    }
  }
  Bytes::from_array(out)
}

///|
fn assert_schema_error(data : Bytes, message : String) -> Unit raise {
  for lenient in [false, true] {
    match parse_ply(data, lenient_ascii=lenient) {
      Ok(_) => fail("坏坐标声明不应被接受")
      Err(error) => assert_true(error.contains(message))
    }
  }
  assert_true(parse_mesh(data) is Err(_))
}

///|
test "PLY schema rejects each missing coordinate in every encoding and mode" {
  for kind in ["ascii", "binary_little_endian", "binary_big_endian"] {
    for coordinate in ["x", "y", "z"] {
      let properties = ["x", "y", "z"]
        .filter(c => c != coordinate)
        .map(c => "property float \{c}")
      assert_schema_error(schema_ply(kind, properties), "缺少 \{coordinate}")
    }
  }
}

///|
test "PLY schema rejects list coordinates instead of skipping them" {
  for kind in ["ascii", "binary_little_endian", "binary_big_endian"] {
    for coordinate in ["x", "y", "z"] {
      let properties = ["x", "y", "z"].map(c => {
        if c == coordinate {
          "property list uchar float \{c}"
        } else {
          "property float \{c}"
        }
      })
      assert_schema_error(
        schema_ply(kind, properties),
        "\{coordinate} 属性必须为标量",
      )
    }
  }
}

///|
test "PLY schema rejects repeated coordinates instead of last value wins" {
  for kind in ["ascii", "binary_little_endian", "binary_big_endian"] {
    for coordinate in ["x", "y", "z"] {
      let properties = [
        "property float x", "property float y", "property float z",
      ]
      properties.push("property float \{coordinate}")
      assert_schema_error(
        schema_ply(kind, properties),
        "重复声明 \{coordinate}",
      )
    }
  }
}

///|
test "PLY schema checks every vertex element before consuming body even with zero records" {
  let properties = ["property float x", "property float y", "property float z"]
  let valid = @utf8.decode_lossy(schema_ply("ascii", properties))
  let bad = valid.replace_all(
    old="end_header\n",
    new="element vertex 0\nproperty float x\nproperty float y\nend_header\n",
  )
  assert_schema_error(@utf8.encode(bad), "缺少 z")
  assert_schema_error(
    b"ply\nformat binary_little_endian 1.0\nelement vertex 3\nproperty float x\nproperty float y\nend_header\n",
    "缺少 z",
  )
}

///|
test "PLY schema permits reordered coordinates zero coordinates and unknown attributes" {
  let properties = [
    "property float z", "property list uchar float confidence", "property float y",
    "property float red", "property float x",
  ]
  for kind in ["ascii", "binary_little_endian", "binary_big_endian"] {
    let data = schema_ply(kind, properties)
    for lenient in [false, true] {
      let mesh = parse_ply(data, lenient_ascii=lenient).unwrap()
      assert_eq(mesh.triangle_count(), 1)
      assert_true((mesh.surface_area() - 0.5).abs() < 1.0e-9)
      assert_eq(mesh.bounding_box().unwrap().max.z, 0.0)
    }
  }
}
