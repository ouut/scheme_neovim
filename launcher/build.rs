use std::env;
use std::fs::{self, File};
use std::io::{self, BufWriter};
use std::path::{Path, PathBuf};
use std::process::Command;
use walkdir::WalkDir;
use flate2::write::GzEncoder;
use flate2::Compression;

fn find_file(names: &[&str], env_var: &str) -> Option<PathBuf> {
    if let Ok(val) = env::var(env_var) {
        let p = PathBuf::from(val);
        if p.exists() {
            return Some(p);
        }
    }
    for name in names {
        let p = PathBuf::from(name);
        if p.exists() {
            return Some(p);
        }
    }
    None
}

fn copy_and_strip(src: &Path, dst: &Path) -> io::Result<()> {
    fs::copy(src, dst)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(dst)?.permissions();
        perms.set_mode(0o755);
        fs::set_permissions(dst, perms)?;

        // Try stripping debug symbols if strip tool is available
        let _ = Command::new("strip").arg(dst).status();
    }
    Ok(())
}

fn copy_dir_filtered(src: &Path, dst: &Path) -> io::Result<()> {
    for entry in WalkDir::new(src).into_iter().filter_map(|e| e.ok()) {
        let path = entry.path();
        let rel_path = path.strip_prefix(src).unwrap();

        // Skip git, github metadata, tests, and heavy doc directories
        let mut skip = false;
        for comp in rel_path.components() {
            let s = comp.as_os_str().to_string_lossy();
            if s == ".git" || s == ".github" || s == "tests" || s == "doc" {
                skip = true;
                break;
            }
        }
        if skip {
            continue;
        }

        let target_path = dst.join(rel_path);
        if entry.file_type().is_dir() {
            fs::create_dir_all(&target_path)?;
        } else if entry.file_type().is_file() {
            if let Some(parent) = target_path.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(path, &target_path)?;
        }
    }
    Ok(())
}

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=../init.lua");
    println!("cargo:rerun-if-changed=../lua/");

    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let staging_dir = out_dir.join("staging_bundle");
    if staging_dir.exists() {
        let _ = fs::remove_dir_all(&staging_dir);
    }
    fs::create_dir_all(staging_dir.join("bin")).unwrap();
    fs::create_dir_all(staging_dir.join("share/nvim")).unwrap();
    fs::create_dir_all(staging_dir.join("config")).unwrap();
    fs::create_dir_all(staging_dir.join("data/nvim/lazy")).unwrap();

    // 1. Locate nvim binary
    let nvim_bin = find_file(
        &["/opt/nvim/bin/nvim", "/usr/local/bin/nvim", "/usr/bin/nvim"],
        "NVIM_BIN_PATH",
    ).expect("Neovim binary not found. Set NVIM_BIN_PATH.");

    // 2. Locate steel binary
    let steel_bin = find_file(
        &["/root/.cargo/bin/steel", "/usr/local/bin/steel", "/usr/bin/steel"],
        "STEEL_BIN_PATH",
    ).expect("Steel Scheme binary not found. Set STEEL_BIN_PATH.");

    // 3. Locate nvim runtime
    let nvim_runtime = find_file(
        &["/opt/nvim/share/nvim/runtime", "/usr/share/nvim/runtime", "/usr/local/share/nvim/runtime"],
        "NVIM_RUNTIME_PATH",
    ).expect("Neovim runtime directory not found. Set NVIM_RUNTIME_PATH.");

    // Copy and strip executables
    copy_and_strip(&nvim_bin, &staging_dir.join("bin/nvim")).unwrap();
    copy_and_strip(&steel_bin, &staging_dir.join("bin/steel")).unwrap();

    // Copy Neovim runtime
    copy_dir_filtered(&nvim_runtime, &staging_dir.join("share/nvim/runtime")).unwrap();

    // Copy Scheme Neovim configs
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let root_dir = manifest_dir.parent().unwrap();

    fs::copy(root_dir.join("init.lua"), staging_dir.join("config/init.lua")).unwrap();
    copy_dir_filtered(&root_dir.join("lua"), &staging_dir.join("config/lua")).unwrap();
    if root_dir.join("docs").exists() {
        copy_dir_filtered(&root_dir.join("docs"), &staging_dir.join("config/docs")).unwrap();
    }
    if root_dir.join("example.scm").exists() {
        fs::copy(root_dir.join("example.scm"), staging_dir.join("config/example.scm")).unwrap();
    }

    // Copy lazy plugins (nvim-treesitter with scheme parser, nvim-paredit, strict-paredit, etc.)
    let home_dir = env::var("HOME").unwrap_or_else(|_| "/root".to_string());
    let lazy_dir = PathBuf::from(&home_dir).join(".local/share/nvim/lazy");
    if lazy_dir.exists() {
        for entry in fs::read_dir(&lazy_dir).unwrap().filter_map(|e| e.ok()) {
            let path = entry.path();
            if path.is_dir() {
                let name = entry.file_name();
                copy_dir_filtered(&path, &staging_dir.join("data/nvim/lazy").join(name)).unwrap();
            }
        }
    }

    // Create tar.gz bundle
    let tar_gz_path = out_dir.join("bundle.tar.gz");
    let tar_gz_file = File::create(&tar_gz_path).unwrap();
    let enc = GzEncoder::new(BufWriter::new(tar_gz_file), Compression::best());
    let mut tar = tar::Builder::new(enc);

    tar.append_dir_all("bundle", &staging_dir).unwrap();
    tar.finish().unwrap();

    // Clean up staging directory
    let _ = fs::remove_dir_all(&staging_dir);
}
