// SPDX-License-Identifier: Apache-2.0

///|
// Resolve existing files and the nearest existing parent of a new output.
// This resolves symlinks/junctions, but does not identify hard-link aliases or
// eliminate races between checking and opening files.
async fn output_identity(raw : String) -> Result[String, String] {
  let absolute = @path.Path(raw).resolve()
  if @fs.path_exists(absolute.to_string()) {
    let resolved = @asyncfs.realpath(absolute.to_string()) catch {
      error =>
        return Err("无法解析真实文件路径：" + error.to_string())
    }
    return Ok(resolved)
  }
  let mut parent = absolute.dirname()
  let tail = [absolute.basename().to_owned()]
  while !@fs.path_exists(parent.to_string()) {
    let next = parent.dirname()
    if next.to_string() == parent.to_string() {
      return Err("无法定位输出路径的现有父目录")
    }
    tail.push(parent.basename().to_owned())
    parent = next
  }
  let resolved = @asyncfs.realpath(parent.to_string()) catch {
    error => return Err("无法解析输出父目录：" + error.to_string())
  }
  let mut result = resolved
  for i = tail.length() - 1; i >= 0; i = i - 1 {
    result = result + "/" + tail[i]
  }
  Ok(@path.Path(result).resolve().to_string())
}

///|
async fn output_paths_safe(
  input : String,
  fix : String,
  svg : String,
) -> Result[Unit, String] {
  if fix == "" && svg == "" {
    return Ok(())
  }
  let source = match output_identity(input) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let outputs : Array[String] = []
  for path in [fix, svg] {
    if path == "" {
      continue
    }
    let value = match output_identity(path) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if @path.Path(value).relative(base=@path.Path(source)).to_string() == "" {
      return Err(
        "输出真实路径与输入模型相同（含符号链接或目录链接）；请选择新文件名",
      )
    }
    for previous in outputs {
      if @path.Path(value).relative(base=@path.Path(previous)).to_string() == "" {
        return Err(
          "--fix 与 --svg 必须使用不同的输出路径（真实路径相同）",
        )
      }
    }
    outputs.push(value)
  }
  Ok(())
}
