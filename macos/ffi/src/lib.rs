//! C ABI over the OS-free RightType core, for the macOS menu-bar app.
use std::ffi::{c_char, CStr, CString};

/// Fix wrong-layout words in `text` (UTF-8). Returns a newly allocated string
/// to release with `rt_free`, or NULL when nothing needs changing.
#[no_mangle]
pub unsafe extern "C" fn rt_fix(text: *const c_char) -> *mut c_char {
    if text.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(s) = CStr::from_ptr(text).to_str() else {
        return std::ptr::null_mut();
    };
    let r = righttype::repair::repair(s, righttype::dict::english(), righttype::dict::thai());
    if r.changes.is_empty() || r.text == s {
        return std::ptr::null_mut();
    }
    CString::new(r.text).map_or(std::ptr::null_mut(), CString::into_raw)
}

#[no_mangle]
pub unsafe extern "C" fn rt_free(p: *mut c_char) {
    if !p.is_null() {
        drop(CString::from_raw(p));
    }
}

/// Live reading of a word still being typed on the English layout: the Thai it
/// is confidently heading for, or NULL. Release with `rt_free`.
#[no_mangle]
pub unsafe extern "C" fn rt_live(run: *const c_char) -> *mut c_char {
    if run.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(s) = CStr::from_ptr(run).to_str() else {
        return std::ptr::null_mut();
    };
    match righttype::policy::live_reading(s, false, righttype::dict::english(), righttype::dict::thai()) {
        righttype::policy::Reading::Thai(t) if t != s => {
            CString::new(t).map_or(std::ptr::null_mut(), CString::into_raw)
        }
        _ => std::ptr::null_mut(),
    }
}

/// Common Thai misspellings in `run` put right, or NULL. Release with `rt_free`.
#[no_mangle]
pub unsafe extern "C" fn rt_spell(run: *const c_char) -> *mut c_char {
    if run.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(s) = CStr::from_ptr(run).to_str() else {
        return std::ptr::null_mut();
    };
    match righttype::spelling::fix(s, righttype::dict::thai()) {
        Some((fixed, _, _)) if fixed != s => CString::new(fixed).map_or(std::ptr::null_mut(), CString::into_raw),
        _ => std::ptr::null_mut(),
    }
}
