// SPDX-License-Identifier: Apache-2.0

///|
fn mutate(seed : Bytes, index : Int32, word : UInt32) -> Bytes {
  let operation = index / 5 % 10
  let at = (word % seed.length().reinterpret_as_uint()).reinterpret_as_int()
  if operation == 0 {
    return seed[:at].to_owned()
  }
  if operation == 5 {
    return seed + seed
  }
  if operation == 7 {
    return @utf8.encode("#" + "x".repeat(1200) + "\n") + seed
  }
  if operation == 8 {
    return seed
  }
  let out : Array[Byte] = []
  for i in 0..<seed.length() {
    if operation == 3 && i == at {
      out.push((word >> 16).to_byte())
    }
    if operation == 2 && i == at {
      continue
    }
    out.push(
      if operation == 1 && i == at {
        (word >> 8).to_byte()
      } else {
        seed[i]
      },
    )
  }
  if operation == 4 {
    out.push(b'\xff')
  }
  if operation == 9 {
    for b in b"\n-2147483648 nan inf 1e309 4294967295\n" {
      out.push(b)
    }
  }
  Bytes::from_array(out)
}

///|
fn direct(
  data : Bytes,
  kind : Int32,
  limits : @stlkit.ParseLimits,
) -> Result[@stlkit.Mesh, String] {
  match kind {
    0 => @stlkit.parse_stl_binary(data, limits~)
    1 => @stlkit.parse_stl_ascii(@utf8.decode_lossy(data), limits~)
    2 => @stlkit.parse_obj(@utf8.decode_lossy(data), limits~)
    3 => @stlkit.parse_ply(data, limits~)
    _ => @stlkit.parse_3mf(data, limits~)
  }
}

///|
fn main raise {
  let args = @env.args()
  let offset = argument_offset()
  let count = if args.length() > offset {
    @string.parse_int(args[offset])
  } else {
    1000
  }
  let start = if args.length() > offset + 1 {
    @string.parse_int(args[offset + 1])
  } else {
    0
  }
  guard count > 0 && count <= 10000 && start >= 0 && start <= 10000 else {
    fail("count 1..10000; start 0..10000")
  }
  let limits : @stlkit.ParseLimits = {
    max_input_bytes: 8192,
    max_vertices: 256,
    max_triangles: 128,
    max_list_items: 2048,
    max_polygon_vertices: 64,
    max_uncompressed_bytes: 32768,
    max_zip_entries: 16,
    max_component_depth: 8,
    max_component_instances: 256,
    max_records: 8192,
    max_line_bytes: 1024,
    max_xml_depth: 32,
  }
  let seeds = seeds()
  let mut random = 0x53544c4bU
  let mut digest = 2166136261U
  let mut accepted = 0
  let mut rejected = 0
  for index in 0..<(start + count) {
    random = random * 1664525U + 1013904223U
    if index < start {
      continue
    }
    let kind = index % 5
    let input = if index / 5 % 10 == 6 {
      targeted_seed(kind, index)
    } else {
      mutate(seeds[kind], index, random)
    }
    // Last line before a crash identifies the exact reproducible case.
    println("CASE \{index} kind=\{kind} word=\{random} bytes=\{input.length()}")
    let result = direct(input, kind, limits)
    let automatic = @stlkit.parse_mesh(input, limits~)
    match (automatic, @stlkit.parse_mesh_checked(input, limits~)) {
      (Ok(mesh), Ok(checked)) =>
        assert_eq(mesh.triangle_count(), checked.triangle_count())
      (Err(_), Err(error)) => assert_true(error.code().length() > 0)
      _ => fail("checked and legacy parser acceptance differ")
    }
    let value = match result {
      Ok(mesh) => {
        accepted += 1
        assert_true(mesh.triangle_count() <= limits.max_triangles)
        assert_true(
          automatic is Ok(_),
          msg="automatic routing rejected a directly accepted seed",
        )
        for triangle in mesh.triangles {
          for vertex in [triangle.a, triangle.b, triangle.c] {
            assert_true(!vertex.x.is_nan() && !vertex.x.is_inf())
            assert_true(!vertex.y.is_nan() && !vertex.y.is_inf())
            assert_true(!vertex.z.is_nan() && !vertex.z.is_inf())
          }
        }
        mesh.triangle_count() + 1
      }
      Err(message) => {
        assert_true(message.length() > 0)
        rejected += 1
        0
      }
    }
    if kind == 0 {
      let scanner = @stlkit.StlScanner::new(limits~)
      let split = input.length() / 2
      scanner.feed(input[:split].to_owned())
      scanner.feed(input[split:].to_owned())
      match (result, scanner.finish()) {
        (Ok(mesh), Ok(scan)) =>
          assert_eq(mesh.triangle_count(), scan.triangle_count)
        (Err(_), Err(_)) => ()
        _ => fail("binary full/chunked acceptance differs")
      }
    }
    digest = (digest ^ value.reinterpret_as_uint()) * 16777619U
  }
  println(
    "FUZZ_RESULT start=\{start} cases=\{count} accepted=\{accepted} rejected=\{rejected} digest=\{digest}",
  )
}

///|
#cfg(target="js")
fn argument_offset() -> Int32 {
  2
}

///|
#cfg(not(target="js"))
fn argument_offset() -> Int32 {
  1
}
