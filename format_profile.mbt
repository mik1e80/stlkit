// SPDX-License-Identifier: Apache-2.0
// Shared lexical bounds for the documented geometry ingestion profile.

///|
fn profile_integer_token(raw : StringView) -> Bool {
  if raw.length() == 0 {
    return false
  }
  let start = if raw.code_unit_at(0) == 43 || raw.code_unit_at(0) == 45 {
    1
  } else {
    0
  }
  if start == raw.length() {
    return false
  }
  for i = start; i < raw.length(); i = i + 1 {
    let c = raw.code_unit_at(i)
    if c < 48 || c > 57 {
      return false
    }
  }
  true
}

///|
fn profile_decimal_int(
  raw : StringView,
  minimum : Int32,
) -> Result[Int32, String] {
  if !profile_integer_token(raw) {
    return Err("需要十进制整数字面量：\{raw}")
  }
  let value = @string.parse_int(raw) catch {
    _ =>
      return Err("整数超出当前实现的 32 位有符号范围：\{raw}")
  }
  if value < minimum {
    return Err("整数小于允许下界 \{minimum}：\{raw}")
  }
  Ok(value)
}

///|
fn ply_integer_range(ty : StringView) -> (Double, Double)? {
  match ty {
    "char" | "int8" => Some((-128.0, 127.0))
    "uchar" | "uint8" => Some((0.0, 255.0))
    "short" | "int16" => Some((-32768.0, 32767.0))
    "ushort" | "uint16" => Some((0.0, 65535.0))
    "int" | "int32" => Some((-2147483648.0, 2147483647.0))
    "uint" | "uint32" => Some((0.0, 4294967295.0))
    _ => None
  }
}
