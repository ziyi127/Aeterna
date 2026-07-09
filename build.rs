use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    // Parse resources/resources.qrc and generate a qrc! macro invocation that
    // embeds every icon and QML file listed in the descriptor. This keeps the
    // binary self-contained and avoids drift between resources.qrc and the
    // actual files registered at runtime.
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap_or_else(|_| ".".into());
    let qrc_path = PathBuf::from(&manifest_dir).join("resources").join("resources.qrc");
    let out_dir = env::var("OUT_DIR").expect("OUT_DIR not set");
    let out_path = PathBuf::from(&out_dir).join("resources_qrc.rs");

    let qrc_content = fs::read_to_string(&qrc_path)
        .unwrap_or_else(|e| panic!("Failed to read {}: {}", qrc_path.display(), e));

    let resources = parse_qrc(&qrc_content);
    if resources.is_empty() {
        panic!("No resources found in {}", qrc_path.display());
    }

    let mut generated = String::new();
    generated.push_str("qrc! {\n");
    generated.push_str("    pub resources,\n");

    for (idx, (prefix, files)) in resources.iter().enumerate() {
        if idx > 0 {
            generated.push_str(",\n");
        }
        // The qrc! macro expects a local base directory and a virtual prefix.
        // resources.qrc lives in the "resources" directory, so all file paths
        // are relative to that directory. The virtual prefix comes from the
        // <qresource prefix="..."> attribute.
        generated.push_str(&format!("    \"resources\" as \"{}\" {{\n", prefix));
        for file in files {
            generated.push_str(&format!("        \"{}\",\n", file));
        }
        generated.push_str("    }");
    }

    generated.push_str("\n}\n");

    fs::write(&out_path, generated)
        .unwrap_or_else(|e| panic!("Failed to write {}: {}", out_path.display(), e));

    println!("cargo:rerun-if-changed=resources/resources.qrc");
    println!("cargo:rerun-if-changed=resources/qml");
    println!("cargo:rerun-if-changed=resources/icons");
}

/// Parse a simple .qrc file and return a list of (prefix, file_paths).
fn parse_qrc(content: &str) -> Vec<(String, Vec<String>)> {
    let mut result = Vec::new();
    let mut current_prefix = String::from("/");
    let mut current_files = Vec::new();
    let mut in_qresource = false;

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("<qresource") {
            in_qresource = true;
            current_prefix = extract_prefix(trimmed).unwrap_or_else(|| "/".into());
            current_files.clear();
        } else if trimmed.starts_with("</qresource>") {
            in_qresource = false;
            if !current_files.is_empty() {
                result.push((normalize_prefix(&current_prefix), current_files.clone()));
            }
            current_files.clear();
        } else if in_qresource && trimmed.starts_with("<file") {
            if let Some(path) = extract_file_path(trimmed) {
                current_files.push(path);
            }
        }
    }

    result
}

fn extract_prefix(tag: &str) -> Option<String> {
    // e.g. <qresource prefix="/">
    let start = tag.find("prefix=\"")? + 8;
    let rest = &tag[start..];
    let end = rest.find('"')?;
    Some(rest[..end].to_string())
}

fn extract_file_path(tag: &str) -> Option<String> {
    // e.g. <file>icons/clock_20.png</file>
    // or   <file alias="foo.png">icons/foo.png</file>
    let start = tag.find('>')? + 1;
    let end = tag.find("</file>")?;
    if start < end {
        Some(tag[start..end].trim().to_string())
    } else {
        None
    }
}

fn normalize_prefix(prefix: &str) -> String {
    // qrc! prefixes should not have a leading or trailing slash.
    let mut s = prefix.trim().to_string();
    if s.starts_with('/') {
        s.remove(0);
    }
    if s.ends_with('/') {
        s.pop();
    }
    s
}
