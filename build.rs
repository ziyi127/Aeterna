use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    // ── Qt static linking detection ──
    //
    // If a static Qt build is available (libQt6Core.a), force the linker
    // to prefer static libraries. This produces a self-contained binary
    // that does not depend on Qt shared objects at runtime.
    //
    // qmetaobject calls pkg-config internally; we set the environment
    // so pkg-config returns --static flags.
    // Static Qt is an explicit Linux-only opt-in. Host filesystem probing made
    // ordinary builds vary unexpectedly between machines and targets.
    if std::env::var_os("AETERNA_STATIC_QT").is_some() && is_static_qt_available() {
        println!("cargo:rustc-cfg=qt_static");
        println!("cargo:rustc-link-search=native=/usr/lib");
        // Tell pkg-config to emit static linking flags
        println!("cargo:rustc-env=PKG_CONFIG_ALL_STATIC=true");
        // The linker needs to see the static libs; instruct cargo
        // to prefer static over dynamic.
        println!("cargo:rustc-link-arg=-Wl,-Bstatic");
        // Link order: Qt modules come from pkg-config, system deps after
        println!("cargo:rustc-link-lib=static=Qt6Core");
        println!("cargo:rustc-link-lib=static=Qt6Gui");
        println!("cargo:rustc-link-lib=static=Qt6Widgets");
        println!("cargo:rustc-link-lib=static=Qt6Quick");
        println!("cargo:rustc-link-lib=static=Qt6Qml");
        println!("cargo:rustc-link-lib=static=Qt6DBus");
        println!("cargo:rustc-link-lib=static=Qt6QmlMeta");
        println!("cargo:rustc-link-lib=static=Qt6QmlModels");
        println!("cargo:rustc-link-lib=static=Qt6Network");
        println!("cargo:rustc-link-lib=static=Qt6OpenGL");
        println!("cargo:rustc-link-lib=static=Qt6QuickControls2");
        println!("cargo:rustc-link-lib=static=Qt6QuickTemplates2");
        // Switch back to dynamic for system libs
        println!("cargo:rustc-link-arg=-Wl,-Bdynamic");
        // System deps that Qt6 depends on (static Qt needs these pulled in)
        for lib in &[
            "GL",
            "glib-2.0",
            "gobject-2.0",
            "xkbcommon",
            "fontconfig",
            "freetype",
            "X11",
            "xcb",
            "xcb-render",
            "xcb-shm",
            "xcb-xfixes",
            "xcb-shape",
            "xcb-sync",
            "xcb-randr",
            "xcb-image",
            "xcb-keysyms",
            "xcb-util",
            "xcb-render-util",
            "X11-xcb",
            "ICE",
            "SM",
            "dbus-1",
            "z",
            "dl",
            "pthread",
        ] {
            println!("cargo:rustc-link-lib={}", lib);
        }
    } else {
        // 动态链接：按平台设置 rpath，使二进制能找到自带的 Qt 运行时。
        // 注意：ELF 的 $ORIGIN 语法在 macOS 上无效，需使用 @executable_path。
        #[cfg(target_os = "linux")]
        {
            println!("cargo:rustc-link-arg=-Wl,-rpath,$ORIGIN/../lib");
        }
        #[cfg(target_os = "macos")]
        {
            println!("cargo:rustc-link-arg=-Wl,-rpath,@executable_path/../Frameworks");
        }
        // Windows 通过并行程序集 / PATH 查找 DLL，无需 rpath。
    }

    // ── QRC resource embedding ──
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap_or_else(|_| ".".into());
    let qrc_path = PathBuf::from(&manifest_dir)
        .join("resources")
        .join("resources.qrc");
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
        generated.push_str(&format!("    \"resources\" as \"{}\" {{\n", prefix));
        for file in files {
            generated.push_str(&format!("        \"{}\",\n", file));
        }
        generated.push_str("    }");
    }

    generated.push_str("\n}\n");

    fs::write(&out_path, generated)
        .unwrap_or_else(|e| panic!("Failed to write {}: {}", out_path.display(), e));

    println!("cargo:rerun-if-env-changed=AETERNA_STATIC_QT");
    println!("cargo:rerun-if-changed=resources/resources.qrc");
    println!("cargo:rerun-if-changed=resources/qml");
    println!("cargo:rerun-if-changed=resources/icons");
    println!("cargo:rerun-if-changed=resources/shaders");
}

fn is_static_qt_available() -> bool {
    let search_dirs = &["/usr/lib", "/usr/lib64", "/usr/local/lib"];
    let required = &["Qt6Core", "Qt6Gui", "Qt6Quick", "Qt6Qml"];
    for dir in search_dirs {
        if required.iter().all(|lib| {
            let path = format!("{}/lib{}.a", dir, lib);
            std::path::Path::new(&path).exists()
        }) {
            return true;
        }
    }
    false
}

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
    let start = tag.find("prefix=\"")? + 8;
    let rest = &tag[start..];
    let end = rest.find('"')?;
    Some(rest[..end].to_string())
}

fn extract_file_path(tag: &str) -> Option<String> {
    let start = tag.find('>')? + 1;
    let end = tag.find("</file>")?;
    if start < end {
        Some(tag[start..end].trim().to_string())
    } else {
        None
    }
}

fn normalize_prefix(prefix: &str) -> String {
    let mut s = prefix.trim().to_string();
    if s.starts_with('/') {
        s.remove(0);
    }
    if s.ends_with('/') {
        s.pop();
    }
    s
}
