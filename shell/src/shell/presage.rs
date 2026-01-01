//! FFI bindings for libpresage - intelligent predictive text entry
//!
//! Presage is a library that provides intelligent predictive text capabilities
//! using statistical, syntactic, and semantic language models.

use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::ptr;

/// Opaque presage handle
#[repr(C)]
pub struct PresageOpaque {
    _private: [u8; 0],
}

pub type PresageT = *mut PresageOpaque;

/// Error codes from presage
pub type PresageErrorCode = c_int;

pub const PRESAGE_OK: PresageErrorCode = 0;
pub const PRESAGE_ERROR: PresageErrorCode = 1;

/// Callback types for providing text context to presage
pub type GetPastStreamCallback = extern "C" fn(*mut c_void) -> *const c_char;
pub type GetFutureStreamCallback = extern "C" fn(*mut c_void) -> *const c_char;

#[link(name = "presage")]
extern "C" {
    pub fn presage_new_with_config(
        past_cb: GetPastStreamCallback,
        past_arg: *mut c_void,
        future_cb: GetFutureStreamCallback,
        future_arg: *mut c_void,
        config: *const c_char,
        result: *mut PresageT,
    ) -> PresageErrorCode;

    pub fn presage_new(
        past_cb: GetPastStreamCallback,
        past_arg: *mut c_void,
        future_cb: GetFutureStreamCallback,
        future_arg: *mut c_void,
        result: *mut PresageT,
    ) -> PresageErrorCode;

    pub fn presage_predict(prsg: PresageT, result: *mut *mut *mut c_char) -> PresageErrorCode;

    pub fn presage_learn(prsg: PresageT, text: *const c_char) -> PresageErrorCode;

    pub fn presage_completion(
        prsg: PresageT,
        token: *const c_char,
        result: *mut *mut c_char,
    ) -> PresageErrorCode;

    pub fn presage_context(prsg: PresageT, result: *mut *mut c_char) -> PresageErrorCode;

    pub fn presage_prefix(prsg: PresageT, result: *mut *mut c_char) -> PresageErrorCode;

    pub fn presage_context_change(prsg: PresageT) -> PresageErrorCode;

    pub fn presage_free(prsg: PresageT);

    pub fn presage_free_string(str_ptr: *mut c_char);

    pub fn presage_free_string_array(str_arr: *mut *mut c_char);

    pub fn presage_config(prsg: PresageT, variable: *const c_char, result: *mut *mut c_char) -> PresageErrorCode;

    pub fn presage_config_set(prsg: PresageT, variable: *const c_char, value: *const c_char) -> PresageErrorCode;
}

/// Context data structure that will be passed to callbacks via pointer
/// This is stored in a Box and lives as long as the Presage instance
struct CallbackContext {
    /// Text before the cursor (the "past stream") - kept as CString for stable pointer
    past_text: CString,
    /// Text after the cursor (the "future stream") - usually empty
    future_text: CString,
}

/// Callback for getting text before cursor
/// arg points to a CallbackContext
extern "C" fn get_past_stream(arg: *mut c_void) -> *const c_char {
    if arg.is_null() {
        return b"\0".as_ptr() as *const c_char;
    }
    unsafe {
        let ctx = &*(arg as *const CallbackContext);
        ctx.past_text.as_ptr()
    }
}

/// Callback for getting text after cursor
/// arg points to a CallbackContext
extern "C" fn get_future_stream(arg: *mut c_void) -> *const c_char {
    if arg.is_null() {
        return b"\0".as_ptr() as *const c_char;
    }
    unsafe {
        let ctx = &*(arg as *const CallbackContext);
        ctx.future_text.as_ptr()
    }
}

/// Safe wrapper around presage
/// Note: This is NOT thread-safe - must be used from single thread only
pub struct Presage {
    handle: PresageT,
    /// Context data - must stay alive while presage is alive
    /// We use a Box to get a stable address
    context: Box<CallbackContext>,
}

impl Presage {
    /// Create a new presage instance with default config
    pub fn new() -> Result<Self, String> {
        // Create context with stable address
        let context = Box::new(CallbackContext {
            past_text: CString::new("").unwrap(),
            future_text: CString::new("").unwrap(),
        });

        let context_ptr = &*context as *const CallbackContext as *mut c_void;
        let mut handle: PresageT = ptr::null_mut();

        let result = unsafe {
            presage_new(
                get_past_stream,
                context_ptr,
                get_future_stream,
                context_ptr,
                &mut handle,
            )
        };

        if result != PRESAGE_OK || handle.is_null() {
            return Err("Failed to initialize presage".to_string());
        }

        let predictor = Self { handle, context };

        // Try to set number of suggestions to 3
        let _ = predictor.set_config("Presage.Selector.SUGGESTIONS", "3");

        Ok(predictor)
    }

    /// Create a new presage instance with custom config file
    pub fn with_config(config_path: &str) -> Result<Self, String> {
        let config = CString::new(config_path).map_err(|e| e.to_string())?;

        // Create context with stable address
        let context = Box::new(CallbackContext {
            past_text: CString::new("").unwrap(),
            future_text: CString::new("").unwrap(),
        });

        let context_ptr = &*context as *const CallbackContext as *mut c_void;
        let mut handle: PresageT = ptr::null_mut();

        let result = unsafe {
            presage_new_with_config(
                get_past_stream,
                context_ptr,
                get_future_stream,
                context_ptr,
                config.as_ptr(),
                &mut handle,
            )
        };

        if result != PRESAGE_OK || handle.is_null() {
            return Err(format!("Failed to initialize presage with config: {}", config_path));
        }

        Ok(Self { handle, context })
    }

    /// Update the text context (call before predict)
    /// SAFETY: This mutates the context that callbacks read from.
    /// Presage must not be called from multiple threads simultaneously.
    pub fn set_context(&mut self, past: &str, future: &str) {
        // Update the context - the Box ensures stable address
        self.context.past_text = CString::new(past).unwrap_or_else(|_| CString::new("").unwrap());
        self.context.future_text = CString::new(future).unwrap_or_else(|_| CString::new("").unwrap());

        // Notify presage that context changed (this may call our callbacks synchronously)
        unsafe {
            presage_context_change(self.handle);
        }
    }

    /// Get predictions for the current context
    pub fn predict(&self) -> Vec<String> {
        let mut predictions: Vec<String> = Vec::new();
        let mut result: *mut *mut c_char = ptr::null_mut();

        let err = unsafe { presage_predict(self.handle, &mut result) };

        if err == PRESAGE_OK && !result.is_null() {
            // Iterate through null-terminated array of strings
            let mut i = 0;
            unsafe {
                loop {
                    let str_ptr = *result.offset(i);
                    if str_ptr.is_null() {
                        break;
                    }
                    if let Ok(s) = CStr::from_ptr(str_ptr).to_str() {
                        predictions.push(s.to_string());
                    }
                    i += 1;
                }
                presage_free_string_array(result);
            }
        }

        predictions
    }

    /// Get the completion for a given token (what presage would add to complete it)
    pub fn completion(&self, token: &str) -> Option<String> {
        let token_c = CString::new(token).ok()?;
        let mut result: *mut c_char = ptr::null_mut();

        let err = unsafe { presage_completion(self.handle, token_c.as_ptr(), &mut result) };

        if err == PRESAGE_OK && !result.is_null() {
            let completion = unsafe {
                let s = CStr::from_ptr(result).to_str().ok().map(|s| s.to_string());
                presage_free_string(result);
                s
            };
            completion
        } else {
            None
        }
    }

    /// Get the current prefix (partial word being typed)
    pub fn prefix(&self) -> Option<String> {
        let mut result: *mut c_char = ptr::null_mut();

        let err = unsafe { presage_prefix(self.handle, &mut result) };

        if err == PRESAGE_OK && !result.is_null() {
            let prefix = unsafe {
                let s = CStr::from_ptr(result).to_str().ok().map(|s| s.to_string());
                presage_free_string(result);
                s
            };
            prefix
        } else {
            None
        }
    }

    /// Learn from text (improves future predictions)
    pub fn learn(&self, text: &str) -> bool {
        if let Ok(text_c) = CString::new(text) {
            let err = unsafe { presage_learn(self.handle, text_c.as_ptr()) };
            err == PRESAGE_OK
        } else {
            false
        }
    }

    /// Set a configuration variable
    pub fn set_config(&self, variable: &str, value: &str) -> bool {
        let var_c = match CString::new(variable) {
            Ok(c) => c,
            Err(_) => return false,
        };
        let val_c = match CString::new(value) {
            Ok(c) => c,
            Err(_) => return false,
        };

        let err = unsafe { presage_config_set(self.handle, var_c.as_ptr(), val_c.as_ptr()) };
        err == PRESAGE_OK
    }

    /// Get a configuration variable
    pub fn get_config(&self, variable: &str) -> Option<String> {
        let var_c = CString::new(variable).ok()?;
        let mut result: *mut c_char = ptr::null_mut();

        let err = unsafe { presage_config(self.handle, var_c.as_ptr(), &mut result) };

        if err == PRESAGE_OK && !result.is_null() {
            let config = unsafe {
                let s = CStr::from_ptr(result).to_str().ok().map(|s| s.to_string());
                presage_free_string(result);
                s
            };
            config
        } else {
            None
        }
    }
}

impl Drop for Presage {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe {
                presage_free(self.handle);
            }
        }
    }
}
