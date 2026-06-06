use super::{cstr_arg, ffi_catch, safe_cstring};
use crate::api;
use std::os::raw::c_char;
use std::panic::AssertUnwindSafe;

// ============================================================================
// M5: SAVE/LOAD PROJECT FFI
// ============================================================================

/// Save project to .audio folder
#[no_mangle]
pub extern "C" fn save_project_ffi(
    project_name: *const c_char,
    project_path: *const c_char,
) -> *mut c_char {
    ffi_catch(
        std::ptr::null_mut(),
        AssertUnwindSafe(|| {
            let Some(project_name_str) = (unsafe { cstr_arg(project_name) }) else {
                return safe_cstring("Error: Invalid project name".to_string()).into_raw();
            };

            let Some(project_path_str) = (unsafe { cstr_arg(project_path) }) else {
                return safe_cstring("Error: Invalid project path".to_string()).into_raw();
            };

            match api::save_project(project_name_str.to_string(), project_path_str.to_string()) {
                Ok(msg) => safe_cstring(msg).into_raw(),
                Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
            }
        }),
    )
}

/// Load project from .audio folder
#[no_mangle]
pub extern "C" fn load_project_ffi(project_path: *const c_char) -> *mut c_char {
    ffi_catch(
        std::ptr::null_mut(),
        AssertUnwindSafe(|| {
            let Some(project_path_str) = (unsafe { cstr_arg(project_path) }) else {
                return safe_cstring("Error: Invalid project path".to_string()).into_raw();
            };

            match api::load_project(project_path_str.to_string()) {
                Ok(msg) => safe_cstring(msg).into_raw(),
                Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
            }
        }),
    )
}
