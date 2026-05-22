use super::{ffi_catch, safe_cstring};
use crate::api;
use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic::AssertUnwindSafe;

#[no_mangle]
pub extern "C" fn find_return_by_effect_type_ffi(effect_type: *const c_char) -> i64 {
    ffi_catch(
        -1,
        AssertUnwindSafe(|| {
            let effect_type_str = unsafe {
                match CStr::from_ptr(effect_type).to_str() {
                    Ok(s) => s,
                    Err(_) => return -1,
                }
            };

            match api::find_return_by_effect_type(effect_type_str) {
                Ok(Some(id)) => id as i64,
                Ok(None) => 0,
                Err(e) => {
                    eprintln!("[FFI] find_return_by_effect_type error: {e}");
                    -1
                }
            }
        }),
    )
}

#[no_mangle]
pub extern "C" fn create_return_with_effect_ffi(
    effect_type: *const c_char,
    name: *const c_char,
) -> i64 {
    ffi_catch(
        -1,
        AssertUnwindSafe(|| {
            let effect_type_str = unsafe {
                match CStr::from_ptr(effect_type).to_str() {
                    Ok(s) => s,
                    Err(_) => return -1,
                }
            };
            let name_str = if name.is_null() {
                None
            } else {
                unsafe {
                    match CStr::from_ptr(name).to_str() {
                        Ok(s) if s.is_empty() => None,
                        Ok(s) => Some(s.to_string()),
                        Err(_) => return -1,
                    }
                }
            };

            match api::create_return_with_effect(effect_type_str, name_str) {
                Ok(id) => id as i64,
                Err(e) => {
                    eprintln!("[FFI] create_return_with_effect error: {e}");
                    -1
                }
            }
        }),
    )
}

#[no_mangle]
pub extern "C" fn add_shared_send_ffi(
    source_track_id: u64,
    effect_type: *const c_char,
) -> *mut c_char {
    ffi_catch(
        std::ptr::null_mut(),
        AssertUnwindSafe(|| {
            let effect_type_str = unsafe {
                match CStr::from_ptr(effect_type).to_str() {
                    Ok(s) => s,
                    Err(_) => {
                        return safe_cstring("Error: Invalid effect type".to_string()).into_raw()
                    }
                }
            };

            match api::add_shared_send(source_track_id, effect_type_str) {
                Ok(msg) => safe_cstring(msg).into_raw(),
                Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
            }
        }),
    )
}

#[no_mangle]
pub extern "C" fn add_send_ffi(
    source_track_id: u64,
    return_track_id: u64,
    amount_db: f32,
) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::add_send(source_track_id, return_track_id, amount_db) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

#[no_mangle]
pub extern "C" fn set_send_amount_ffi(
    source_track_id: u64,
    return_track_id: u64,
    amount_db: f32,
) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::set_send_amount(source_track_id, return_track_id, amount_db) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

#[no_mangle]
pub extern "C" fn remove_send_ffi(source_track_id: u64, return_track_id: u64) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::remove_send(source_track_id, return_track_id) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

#[no_mangle]
pub extern "C" fn remove_return_ffi(return_track_id: u64) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::remove_return(return_track_id) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

#[no_mangle]
pub extern "C" fn get_track_sends_ffi(track_id: u64) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::get_track_sends(track_id) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

#[no_mangle]
pub extern "C" fn get_all_returns_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || match api::get_all_returns() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    })
}

#[no_mangle]
pub extern "C" fn count_sends_to_return_ffi(return_track_id: u64) -> i64 {
    ffi_catch(-1, || match api::count_sends_to_return(return_track_id) {
        Ok(count) => count as i64,
        Err(e) => {
            eprintln!("[FFI] count_sends_to_return error: {e}");
            -1
        }
    })
}

#[no_mangle]
pub extern "C" fn get_master_timeline_visible_ffi() -> i32 {
    ffi_catch(0, || match api::get_master_timeline_visible() {
        Ok(visible) => i32::from(visible),
        Err(e) => {
            eprintln!("[FFI] get_master_timeline_visible error: {e}");
            0
        }
    })
}

#[no_mangle]
pub extern "C" fn set_master_timeline_visible_ffi(visible: i32) -> *mut c_char {
    ffi_catch(
        std::ptr::null_mut(),
        || match api::set_master_timeline_visible(visible != 0) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        },
    )
}

#[no_mangle]
pub extern "C" fn sync_master_timeline_visibility_ffi() -> i32 {
    ffi_catch(0, || match api::sync_master_timeline_visibility() {
        Ok(visible) => i32::from(visible),
        Err(e) => {
            eprintln!("[FFI] sync_master_timeline_visibility error: {e}");
            0
        }
    })
}
