use std::env;
use std::path::PathBuf;

fn main() {
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();

    // iOS: Only link audio frameworks, no VST3
    if target_os == "ios" {
        println!("cargo:rustc-link-lib=framework=AVFoundation");
        println!("cargo:rustc-link-lib=framework=AudioToolbox");
        println!("cargo:rustc-link-lib=framework=CoreAudio");
        println!("cargo:rustc-link-lib=framework=CoreFoundation");
        println!("cargo:rustc-link-lib=framework=Foundation");
        println!("cargo:rustc-link-lib=c++");
        return;
    }

    // Desktop (macOS, Linux, Windows): Link VST3 host libraries
    // The libraries are built separately using CMake/Xcode and copied to lib/

    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let lib_dir = PathBuf::from(&manifest_dir).join("lib");

    // Tell cargo to look for libraries in the lib directory
    println!("cargo:rustc-link-search=native={}", lib_dir.display());

    // Link VST3 host libraries in correct order (dependencies last)
    // The linker processes libraries left-to-right, so put the library that uses
    // symbols first, and the library that defines symbols last
    println!("cargo:rustc-link-lib=static=vst3_host");
    println!("cargo:rustc-link-lib=static=sdk_hosting");
    println!("cargo:rustc-link-lib=static=sdk");
    println!("cargo:rustc-link-lib=static=sdk_common");
    println!("cargo:rustc-link-lib=static=pluginterfaces");
    println!("cargo:rustc-link-lib=static=base");

    // Link required system frameworks on macOS
    if target_os == "macos" {
        println!("cargo:rustc-link-lib=framework=CoreFoundation");
        println!("cargo:rustc-link-lib=framework=Foundation");
        println!("cargo:rustc-link-lib=framework=Cocoa");
    }

    // Link C++ standard library
    if target_os == "macos" {
        println!("cargo:rustc-link-lib=c++");
    } else if target_os == "linux" {
        println!("cargo:rustc-link-lib=stdc++");
    }

    // Re-run if the libraries change
    println!("cargo:rerun-if-changed=lib/libvst3_host.a");
    println!("cargo:rerun-if-changed=lib/libsdk_hosting.a");
    println!("cargo:rerun-if-changed=lib/libsdk.a");
    println!("cargo:rerun-if-changed=lib/libsdk_common.a");
    println!("cargo:rerun-if-changed=lib/libbase.a");
    println!("cargo:rerun-if-changed=lib/libpluginterfaces.a");
}
