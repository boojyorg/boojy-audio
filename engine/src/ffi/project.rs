use std::ffi::CStr;
use std::os::raw::c_char;
use crate::api;
use super::safe_cstring;

// ============================================================================
// M5: SAVE/LOAD PROJECT FFI
// ============================================================================

/// Save project to .audio folder
#[no_mangle]
pub extern "C" fn save_project_ffi(
    project_name: *const c_char,
    project_path: *const c_char,
) -> *mut c_char {
    let project_name_str = unsafe {
        match CStr::from_ptr(project_name).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return safe_cstring("Error: Invalid project name".to_string()).into_raw(),
        }
    };

    let project_path_str = unsafe {
        match CStr::from_ptr(project_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return safe_cstring("Error: Invalid project path".to_string()).into_raw(),
        }
    };

    match api::save_project(project_name_str, project_path_str) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Load project from .audio folder
#[no_mangle]
pub extern "C" fn load_project_ffi(project_path: *const c_char) -> *mut c_char {
    let project_path_str = unsafe {
        match CStr::from_ptr(project_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return safe_cstring("Error: Invalid project path".to_string()).into_raw(),
        }
    };

    match api::load_project(project_path_str) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}
