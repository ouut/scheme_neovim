use std::env;
use std::fs;
use std::io::{self, Cursor};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use flate2::read::GzDecoder;
use sha2::{Digest, Sha256};
use tar::Archive;

static BUNDLE_BYTES: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/bundle.tar.gz"));

fn exe_suffix() -> &'static str {
    if cfg!(windows) {
        ".exe"
    } else {
        ""
    }
}

fn compute_bundle_hash() -> String {
    let mut hasher = Sha256::new();
    hasher.update(BUNDLE_BYTES);
    let result = hasher.finalize();
    format!("{:x}", result)[..12].to_string()
}

fn get_base_dir() -> PathBuf {
    if let Ok(custom) = env::var("STEEL_IDE_HOME") {
        return PathBuf::from(custom);
    }
    if let Some(data_dir) = dirs::data_local_dir() {
        return data_dir.join("steel-ide");
    }
    let home = env::var("HOME")
        .or_else(|_| env::var("USERPROFILE"))
        .unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".steel-ide")
}

fn ensure_extracted(install_dir: &Path) -> io::Result<()> {
    let marker = install_dir.join(".complete");
    let suffix = exe_suffix();
    let nvim_bin = install_dir.join(format!("bin/nvim{}", suffix));
    let steel_bin = install_dir.join(format!("bin/steel{}", suffix));
    let init_lua = install_dir.join("config/init.lua");

    let mut is_valid = marker.exists() && nvim_bin.exists() && steel_bin.exists() && init_lua.exists();
    if cfg!(windows) && is_valid {
        if !install_dir.join("bin/lua51.dll").exists() {
            is_valid = false;
        }
    }

    if is_valid {
        return Ok(());
    }

    eprintln!("[steel-ide] First run detected: extracting portable runtime (one-time setup)...");
    fs::create_dir_all(install_dir)?;

    let decoder = GzDecoder::new(Cursor::new(BUNDLE_BYTES));
    let mut archive = Archive::new(decoder);

    for entry in archive.entries()? {
        let mut entry = entry?;
        let path = entry.path()?;

        // Strip the top-level "bundle" prefix if present
        let rel_path = if let Ok(stripped) = path.strip_prefix("bundle") {
            stripped.to_path_buf()
        } else {
            path.to_path_buf()
        };

        if rel_path.as_os_str().is_empty() {
            continue;
        }

        let target_path = install_dir.join(rel_path);
        if let Some(parent) = target_path.parent() {
            fs::create_dir_all(parent)?;
        }
        entry.unpack(&target_path)?;
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        for bin in &[&nvim_bin, &steel_bin] {
            if bin.exists() {
                let mut perms = fs::metadata(bin)?.permissions();
                perms.set_mode(0o755);
                fs::set_permissions(bin, perms)?;
            }
        }
    }

    // Write installation completion marker
    fs::write(&marker, b"complete\n")?;

    eprintln!("[steel-ide] Runtime initialized successfully!");
    Ok(())
}

fn print_help() {
    println!(r#"steel-ide 0.1.0
All-in-One portable Steel Scheme IDE powered by Neovim and Strict Paredit

USAGE:
    steel-ide [OPTIONS] [FILES...]

OPTIONS:
    -h, --help            Print help information
    -V, --version         Print version information
    --extract <DIR>       Extract the bundled runtime to DIR and exit
    --repl                Directly launch the interactive Steel REPL
    --example             Open the built-in Scheme tutorial & playground

EXAMPLES:
    steel-ide                     Start the IDE with an empty buffer
    steel-ide main.scm            Open or create 'main.scm'
    steel-ide --example           Open the interactive testbed with all 17 shortcuts
    steel-ide --repl              Directly enter the Steel REPL terminal
"#);
}

fn print_version() {
    println!("steel-ide 0.1.0");
    println!("  Runtime : Neovim 0.10.4");
    println!("  Scheme  : Rust Steel 0.8.2");
    println!("  Paredit : strict-paredit.nvim + nvim-paredit");
    println!("  Design  : 17 One-Shot Alt-Matrix Shortcuts");
}

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().skip(1).collect();

    if let Some(first) = args.first() {
        match first.as_str() {
            "-h" | "--help" => {
                print_help();
                return Ok(());
            }
            "-V" | "--version" => {
                print_version();
                return Ok(());
            }
            "--extract" => {
                if let Some(target) = args.get(1) {
                    let target_path = PathBuf::from(target);
                    ensure_extracted(&target_path)?;
                    println!("Bundle extracted to: {}", target_path.display());
                    return Ok(());
                } else {
                    eprintln!("Error: --extract requires a target directory argument.");
                    std::process::exit(1);
                }
            }
            _ => {}
        }
    }

    let bundle_hash = compute_bundle_hash();
    let base_dir = get_base_dir();
    let install_dir = base_dir.join(format!("v{}", bundle_hash));

    ensure_extracted(&install_dir)?;

    let suffix = exe_suffix();
    let nvim_bin = install_dir.join(format!("bin/nvim{}", suffix));
    let steel_bin = install_dir.join(format!("bin/steel{}", suffix));
    let config_dir = install_dir.join("config");
    let init_lua = config_dir.join("init.lua");
    let vimruntime = install_dir.join("share/nvim/runtime");
    let data_dir = install_dir.join("data");
    let isolated_config_parent = install_dir.join("isolated_config");
    fs::create_dir_all(&isolated_config_parent)?;

    // Handle direct --repl flag
    if args.iter().any(|a| a == "--repl") {
        let mut cmd = Command::new(&steel_bin);
        let repl_args: Vec<_> = args.into_iter().filter(|a| a != "--repl").collect();
        cmd.args(&repl_args)
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit());
        let status = cmd.status()?;
        std::process::exit(status.code().unwrap_or(0));
    }

    // Prepare Neovim execution
    let mut cmd = Command::new(&nvim_bin);

    // Isolate environment completely from host ~/.config/nvim and ~/.local/share/nvim
    cmd.env("VIMRUNTIME", &vimruntime);
    cmd.env("XDG_DATA_HOME", &data_dir);
    cmd.env("XDG_CONFIG_HOME", &isolated_config_parent);
    cmd.env("NVIM_APPNAME", "nvim");

    // Prepend bundled bin/ to PATH so :term steel and child processes find it immediately
    let mut paths = vec![install_dir.join("bin")];
    if let Some(current) = env::var_os("PATH") {
        paths.extend(env::split_paths(&current));
    }
    if let Ok(new_path) = env::join_paths(paths) {
        cmd.env("PATH", new_path);
    }

    // Ensure config directory is in runtimepath and specify isolated init.lua
    let config_dir_str = config_dir.to_string_lossy().replace('\\', "/");
    cmd.arg("--cmd").arg(format!("set rtp^={}", config_dir_str));
    cmd.arg("-u").arg(&init_lua);

    // Process remaining user arguments
    let example_path = config_dir.join("example.scm");
    for arg in &args {
        if arg == "--example" {
            cmd.arg(&example_path);
        } else {
            cmd.arg(arg);
        }
    }

    // Connect standard I/O for interactive terminal
    cmd.stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());

    let status = cmd.status()?;
    std::process::exit(status.code().unwrap_or(0));
}
