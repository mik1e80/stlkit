// SPDX-License-Identifier: Apache-2.0

///|
fn json_requested() -> Bool {
  for arg in @env.args() {
    if arg == "--" {
      return false
    }
    if arg == "--json" {
      return true
    }
  }
  false
}

///|
fn json_failure(
  code : String,
  message : String,
  status : Int32,
) -> (Json, Int32) {
  (
    Json::object({
      "schema_version": Json(1),
      "ok": Json(false),
      "error": Json::object({
        "code": Json(code),
        "message": Json(message),
        "format": Json::null(),
        "location": Json::null(),
      }),
    }),
    status,
  )
}

///|
fn json_arg(matches : @argparse.Matches, key : String) -> String? {
  match matches.values.get(key) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
async fn json_execute(matches : @argparse.Matches) -> (Json, Int32) {
  for flag in ["bench", "stream-only", "help"] {
    if matches.flags.get(flag) == Some(true) {
      return json_failure(
        "invalid_arguments",
        "--json cannot be combined with --" + flag,
        2,
      )
    }
  }
  for name in ["fix", "svg"] {
    if json_arg(matches, name) is Some(_) {
      return json_failure(
        "invalid_arguments",
        "--json is inspection-only; cannot combine with --" + name,
        2,
      )
    }
  }
  let path = match json_arg(matches, "file") {
    Some(path) => path
    None =>
      return json_failure(
        "invalid_arguments", "--json requires an input file", 2,
      )
  }
  let limits = match cli_limits(matches) {
    Ok(value) => value
    Err(message) => return json_failure("invalid_arguments", message, 2)
  }
  let samples = match json_arg(matches, "samples") {
    Some(raw) => {
      let value = @string.parse_int(raw) catch {
        _ =>
          return json_failure(
            "invalid_arguments", "samples must be 1..100000", 2,
          )
      }
      if value < 1 || value > 100000 {
        return json_failure("invalid_arguments", "samples must be 1..100000", 2)
      }
      value
    }
    None => 1000
  }
  let minimum = match json_arg(matches, "min-thickness") {
    Some(raw) => {
      let value = @string.parse_double(raw) catch {
        _ =>
          return json_failure(
            "invalid_arguments", "min-thickness must be finite and nonnegative",
            2,
          )
      }
      if value.is_nan() || value.is_inf() || value < 0.0 {
        return json_failure(
          "invalid_arguments", "min-thickness must be finite and nonnegative", 2,
        )
      }
      value
    }
    None => 0.8
  }
  let nozzle = match json_arg(matches, "nozzle") {
    Some(raw) => {
      let value = @string.parse_double(raw) catch {
        _ =>
          return json_failure(
            "invalid_arguments", "nozzle must be finite and positive", 2,
          )
      }
      if value.is_nan() || value.is_inf() || value <= 0.0 {
        return json_failure(
          "invalid_arguments", "nozzle must be finite and positive", 2,
        )
      }
      Json(value)
    }
    None => Json::null()
  }
  let supports = json_arg(matches, "supports").unwrap_or("unknown")
  if !["on", "off", "unknown"].contains(supports) {
    return json_failure(
      "invalid_arguments", "supports must be on/off/unknown", 2,
    )
  }
  let data = match read_input(path, limits) {
    Ok(data) => data
    Err(message) =>
      return json_failure(
        if message.has_prefix("resource_limit: ") {
          "resource_limit"
        } else {
          "input_read_error"
        },
        message,
        3,
      )
  }
  let mesh = match @stlkit.parse_mesh_checked(data, limits~) {
    Ok(mesh) => mesh
    Err(error) =>
      return (
        Json::object({
          "schema_version": Json(1),
          "ok": Json(false),
          "error": error.to_json(),
        }),
        3,
      )
  }
  let report = match
    @stlkit.inspection_json(
      mesh,
      format=@stlkit.detect_format(data),
      min_thickness=minimum,
      samples~,
    ) {
    Ok(report) => report
    Err(message) => return json_failure("inspection_error", message, 5)
  }
  guard report is Object(fields) else {
    return json_failure("internal_error", "report is not an object", 5)
  }
  fields.set(
    "scenario",
    Json::object({
      "nozzle_mm": nozzle,
      "supports": Json(supports),
      "process_assessed": Json(false),
    }),
  )
  fields.set("path", Json(path))
  let review = match fields.get("review") {
    Some(Object(values)) =>
      match values.get("needs_review") {
        Some(True) => true
        Some(False) => false
        _ =>
          return json_failure(
            "internal_error", "report has no needs_review boolean", 5,
          )
      }
    _ => return json_failure("internal_error", "report has no review", 5)
  }
  let strict = matches.flags.get("strict") == Some(true)
  (report, if strict && review { 4 } else { 0 })
}

///|
async fn json_main() -> Unit {
  let matches = command().parse() catch {
    error => {
      println(
        json_failure("invalid_arguments", error.to_string(), 2).0.stringify(),
      )
      @sys.exit(2)
      return
    }
  }
  let (document, status) = json_execute(matches) catch {
    error => json_failure("internal_error", error.to_string(), 5)
  }
  // The serializer handles all quoting; computed non-finite values are removed
  // by inspection_json, so stdout is exactly one valid JSON document.
  println(@json.to_json(document).stringify())
  if status != 0 {
    @sys.exit(status)
  }
}
