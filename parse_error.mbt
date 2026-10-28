// SPDX-License-Identifier: Apache-2.0

///|
/// Stable categories for the additive checked entry point. Syntax details stay
/// in the diagnostic; they are not inferred from localized error messages.
pub(all) enum ParseError {
  InvalidLimits(String)
  ResourceLimitExceeded(String)
  UnknownFormat(String)
  InvalidData(MeshFormat, String)
}

///|
pub fn ParseError::code(self : ParseError) -> String {
  match self {
    InvalidLimits(_) => "invalid_limits"
    ResourceLimitExceeded(_) => "resource_limit"
    UnknownFormat(_) => "unknown_format"
    InvalidData(_, _) => "invalid_data"
  }
}

///|
pub fn ParseError::message(self : ParseError) -> String {
  match self {
    InvalidLimits(message)
    | ResourceLimitExceeded(message)
    | UnknownFormat(message)
    | InvalidData(_, message) => message
  }
}

///|
pub fn MeshFormat::id(self : MeshFormat) -> String {
  match self {
    Ascii => "stl-ascii"
    Binary => "stl-binary"
    Obj => "obj"
    ThreeMF => "3mf"
    Ply => "ply"
    Unknown => "unknown"
  }
}

///|
pub fn ParseError::to_json(self : ParseError) -> Json {
  let format = match self {
    InvalidData(format, _) => Json(format.id())
    _ => Json::null()
  }
  Json::object({
    "code": Json(self.code()),
    "message": Json(self.message()),
    "format": format,
    "location": Json::null(),
  })
}

///|
/// Content-routed parsing with stable coarse error categories. Existing string
/// APIs remain available. InvalidIndex/InvalidHeader are deliberately not
/// guessed from diagnostic prose; location is currently unavailable.
///
/// ```moonbit nocheck
/// match @stlkit.parse_mesh_checked(data) {
///   Ok(mesh) => println(mesh.triangle_count())
///   Err(error) => println(error.code())
/// }
/// ```
pub fn parse_mesh_checked(
  data : Bytes,
  limits~ : ParseLimits = ParseLimits::default(),
) -> Result[Mesh, ParseError] {
  if parse_limits_error(limits) is Some(message) {
    return Err(InvalidLimits(message))
  }
  if input_limit_error(data, limits) is Some(message) {
    return Err(ResourceLimitExceeded(message))
  }
  let format = detect_format(data)
  match parse_mesh(data, limits~) {
    Ok(mesh) => Ok(mesh)
    Err(message) =>
      // This reserved leading marker is emitted only by resource_error(), not
      // by copied user tokens or localized syntax diagnostics.
      if message.has_prefix("resource_limit: ") {
        Err(ResourceLimitExceeded(message))
      } else if format is Unknown {
        Err(UnknownFormat(message))
      } else {
        Err(InvalidData(format, message))
      }
  }
}
