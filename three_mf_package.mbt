// SPDX-License-Identifier: Apache-2.0
// Strict OPC checks used by the documented Core geometry ingestion subset.

///|
fn mf_xml_text(raw : FixedArray[Byte]) -> Result[String, String] {
  let bytes = Bytes::from_array(raw)
  Ok(@utf8.decode(bytes[:])) catch {
    _ => Err("3MF XML 部件必须为有效 UTF-8")
  }
}

///|
fn mf_opc_nodes(
  text : String,
  root_name : String,
  ns_uri : String,
) -> Result[Array[@xml.XmlElement], String] {
  let reader = @xml.Reader::from_string(text)
  let scopes : Array[MfXmlScope] = []
  let inherited : Map[String, String] = Map([])
  let nodes : Array[@xml.XmlElement] = []
  let mut seen = false
  while !reader.is_eof() {
    let event = reader.read_event() catch {
      _ => return Err("3MF OPC XML 结构非法")
    }
    match event.kind {
      @xml.EventKind::Start(e) | @xml.EventKind::Empty(e) => {
        let parent = if scopes.is_empty() {
          inherited
        } else {
          scopes[scopes.length() - 1].bindings
        }
        let bindings = mf_bindings(e, parent)
        let uri = match bindings.get(prefix_of(e.name)) {
          Some(v) => v
          None => ""
        }
        let name = local_name(e.name)
        if scopes.is_empty() {
          if seen || name != root_name || uri != ns_uri {
            return Err("3MF OPC 根元素或命名空间不正确")
          }
          seen = true
        } else if scopes.length() == 1 && uri == ns_uri {
          nodes.push(e)
        } else {
          return Err("3MF OPC 中存在不支持的嵌套结构")
        }
        if event.kind is @xml.EventKind::Start(_) {
          scopes.push({ name: e.name, tag: name, bindings, })
        }
      }
      @xml.EventKind::End(name) =>
        if scopes.is_empty() || scopes.pop().unwrap().name != name {
          return Err("3MF OPC XML 标签不匹配")
        }
      @xml.EventKind::Text(t) | @xml.EventKind::CData(t) =>
        if obj_words(t).length() > 0 {
          return Err("3MF OPC 中不接受非空文本")
        }
      @xml.EventKind::DocType(_) => return Err("3MF OPC 不接受 DTD")
      @xml.EventKind::Decl(encoding~, ..) =>
        match encoding {
          Some(e) =>
            if e.to_lower() != "utf-8" {
              return Err("3MF OPC 必须使用 UTF-8")
            }
          None => ()
        }
      _ => ()
    }
  }
  if !seen || !scopes.is_empty() {
    return Err("3MF OPC 缺少完整根元素")
  }
  Ok(nodes)
}

///|
fn mf_package_path(raw : String) -> Result[String, String] {
  if raw == "" ||
    raw.contains("\\") ||
    raw.contains(":") ||
    raw.contains("?") ||
    raw.contains("#") {
    return Err(
      "3MF 模型关系 Target 不是当前支持的内部部件路径",
    )
  }
  let name = normalize_part_path(raw)
  for segment in name.split("/") {
    if segment == "" || segment == "." || segment == ".." {
      return Err("3MF 部件路径包含空段或点段")
    }
  }
  Ok(name)
}

///|
fn mf_strict_model_part(
  entries : Array[(String, FixedArray[Byte])],
) -> Result[String, String] {
  let names : Map[String, Bool] = Map([])
  for (name, _) in entries {
    if name.contains("\\") {
      return Err(
        "严格 3MF 包条目必须使用正斜杠；旧导出器需显式 compatibility=true",
      )
    }
    let key = normalize_entry_name(name)
    if names.contains(key) {
      return Err("3MF 包含重复部件名：\{name}")
    }
    names.set(key, true)
  }
  let rels = match find_entry(entries, "_rels/.rels") {
    Some(raw) =>
      match mf_xml_text(raw) {
        Ok(s) => s
        Err(e) => return Err(e)
      }
    None =>
      return Err("严格 3MF 缺少 _rels/.rels，不能猜测 .model 文件")
  }
  let links = match
    mf_opc_nodes(
      rels, "Relationships", "http://schemas.openxmlformats.org/package/2006/relationships",
    ) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let ids : Map[String, Bool] = Map([])
  let mut target : String? = None
  for e in links {
    if local_name(e.name) != "Relationship" {
      return Err("3MF 关系表包含未知声明")
    }
    let id = match e.get("Id") {
      Some(v) => v
      None => return Err("3MF Relationship 缺少 Id")
    }
    if id == "" || ids.contains(id) {
      return Err("3MF Relationship Id 为空或重复")
    }
    ids.set(id, true)
    let kind = match e.get("Type") {
      Some(v) => v
      None => return Err("3MF Relationship 缺少 Type")
    }
    let raw = match e.get("Target") {
      Some(v) => v
      None => return Err("3MF Relationship 缺少 Target")
    }
    if kind != "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" {
      continue
    }
    if target is Some(_) {
      return Err("3MF 必须有唯一的 3D model 关系")
    }
    match e.get("TargetMode") {
      Some(mode) =>
        if mode != "Internal" {
          return Err("3MF 3D model 关系必须为内部 Target")
        }
      None => ()
    }
    target = Some(
      match mf_package_path(raw) {
        Ok(p) => p
        Err(e) => return Err(e)
      },
    )
  }
  let part = match target {
    Some(p) => p
    None =>
      return Err(
        "严格 3MF 缺少唯一 3D model 关系，不回退猜测 .model",
      )
  }
  let types_text = match find_entry(entries, "[Content_Types].xml") {
    Some(raw) =>
      match mf_xml_text(raw) {
        Ok(s) => s
        Err(e) => return Err(e)
      }
    None => return Err("严格 3MF 缺少 [Content_Types].xml")
  }
  let types = match
    mf_opc_nodes(
      types_text, "Types", "http://schemas.openxmlformats.org/package/2006/content-types",
    ) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let defaults : Map[String, String] = Map([])
  let overrides : Map[String, String] = Map([])
  for e in types {
    let mime = match e.get("ContentType") {
      Some(v) => v
      None => return Err("3MF 内容类型缺少 ContentType")
    }
    match local_name(e.name) {
      "Default" => {
        let ext = match e.get("Extension") {
          Some(v) => v.to_lower()
          None => return Err("3MF Default 缺少 Extension")
        }
        if ext == "" || defaults.contains(ext) {
          return Err("3MF Default Extension 为空或重复")
        }
        defaults.set(ext, mime)
      }
      "Override" => {
        let raw = match e.get("PartName") {
          Some(v) => v
          None => return Err("3MF Override 缺少 PartName")
        }
        if !raw.has_prefix("/") {
          return Err("3MF Override PartName 必须为绝对部件名")
        }
        let key = match mf_package_path(raw) {
          Ok(p) => p.to_lower()
          Err(e) => return Err(e)
        }
        if overrides.contains(key) {
          return Err("3MF Override PartName 重复")
        }
        overrides.set(key, mime)
      }
      _ => return Err("3MF 内容类型包含未知声明")
    }
  }
  let mut extension = ""
  for token in part.split(".") {
    extension = token.to_lower().to_owned()
  }
  let model_mime = match overrides.get(part.to_lower()) {
    Some(v) => Some(v)
    None => defaults.get(extension)
  }
  if model_mime !=
    Some("application/vnd.ms-package.3dmanufacturing-3dmodel+xml") {
    return Err("3MF 模型部件的 ContentType 缺失或错误")
  }
  let rels_mime = match overrides.get("_rels/.rels") {
    Some(v) => Some(v)
    None => defaults.get("rels")
  }
  if rels_mime !=
    Some("application/vnd.openxmlformats-package.relationships+xml") {
    return Err("3MF 根关系部件的 ContentType 缺失或错误")
  }
  match find_entry(entries, part) {
    Some(raw) => mf_xml_text(raw)
    None => Err("3MF 关系表指向的模型部件不存在：\{part}")
  }
}
