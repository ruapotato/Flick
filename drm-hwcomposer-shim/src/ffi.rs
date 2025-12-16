//! FFI bindings for libhybris hwcomposer and gralloc
//!
//! These are the raw C bindings to Android HAL via libhybris.

use std::os::raw::{c_char, c_int, c_void};

/// Hardware composer display ID type
pub type Hwc2DisplayT = u64;

/// Hardware composer config ID type
pub type Hwc2ConfigT = u32;

/// Hardware composer error type
pub type Hwc2ErrorT = i32;

/// Android dataspace type
pub type AndroidDataspaceT = i32;

/// HWC2 error codes
pub const HWC2_ERROR_NONE: Hwc2ErrorT = 0;
pub const HWC2_ERROR_BAD_CONFIG: Hwc2ErrorT = 1;
pub const HWC2_ERROR_BAD_DISPLAY: Hwc2ErrorT = 2;
pub const HWC2_ERROR_BAD_LAYER: Hwc2ErrorT = 3;
pub const HWC2_ERROR_BAD_PARAMETER: Hwc2ErrorT = 4;
pub const HWC2_ERROR_NO_RESOURCES: Hwc2ErrorT = 6;
pub const HWC2_ERROR_NOT_VALIDATED: Hwc2ErrorT = 7;
pub const HWC2_ERROR_UNSUPPORTED: Hwc2ErrorT = 8;

/// Power mode constants
pub const HWC2_POWER_MODE_OFF: c_int = 0;
pub const HWC2_POWER_MODE_DOZE: c_int = 1;
pub const HWC2_POWER_MODE_DOZE_SUSPEND: c_int = 3;
pub const HWC2_POWER_MODE_ON: c_int = 2;

/// VSync enable constants
pub const HWC2_VSYNC_ENABLE: c_int = 1;
pub const HWC2_VSYNC_DISABLE: c_int = 0;

/// Composition type constants
pub const HWC2_COMPOSITION_CLIENT: c_int = 1;
pub const HWC2_COMPOSITION_DEVICE: c_int = 2;
pub const HWC2_COMPOSITION_SOLID_COLOR: c_int = 3;
pub const HWC2_COMPOSITION_CURSOR: c_int = 4;
pub const HWC2_COMPOSITION_SIDEBAND: c_int = 5;

/// Blend mode constants
pub const HWC2_BLEND_MODE_NONE: c_int = 0;
pub const HWC2_BLEND_MODE_PREMULTIPLIED: c_int = 1;
pub const HWC2_BLEND_MODE_COVERAGE: c_int = 2;

/// HAL pixel formats
pub const HAL_PIXEL_FORMAT_RGBA_8888: c_int = 1;
pub const HAL_PIXEL_FORMAT_RGBX_8888: c_int = 2;
pub const HAL_PIXEL_FORMAT_RGB_888: c_int = 3;
pub const HAL_PIXEL_FORMAT_RGB_565: c_int = 4;
pub const HAL_PIXEL_FORMAT_BGRA_8888: c_int = 5;

/// Gralloc usage flags
pub const GRALLOC_USAGE_SW_READ_NEVER: u64 = 0x00000000;
pub const GRALLOC_USAGE_SW_READ_RARELY: u64 = 0x00000002;
pub const GRALLOC_USAGE_SW_READ_OFTEN: u64 = 0x00000003;
pub const GRALLOC_USAGE_SW_WRITE_NEVER: u64 = 0x00000000;
pub const GRALLOC_USAGE_SW_WRITE_RARELY: u64 = 0x00000020;
pub const GRALLOC_USAGE_SW_WRITE_OFTEN: u64 = 0x00000030;
pub const GRALLOC_USAGE_HW_TEXTURE: u64 = 0x00000100;
pub const GRALLOC_USAGE_HW_RENDER: u64 = 0x00000200;
pub const GRALLOC_USAGE_HW_2D: u64 = 0x00000400;
pub const GRALLOC_USAGE_HW_COMPOSER: u64 = 0x00000800;
pub const GRALLOC_USAGE_HW_FB: u64 = 0x00001000;

/// Native handle type (opaque)
#[repr(C)]
pub struct NativeHandle {
    _data: [u8; 0],
}

/// HWC color structure
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct HwcColor {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

/// HWC2 display config structure from the compatibility layer
#[repr(C)]
#[derive(Debug, Clone)]
pub struct HWC2DisplayConfig {
    pub id: Hwc2ConfigT,
    pub display: Hwc2DisplayT,
    pub width: i32,
    pub height: i32,
    pub vsync_period: i64,
    pub dpi_x: f32,
    pub dpi_y: f32,
}

/// HWC2 event listener structure
#[repr(C)]
pub struct HWC2EventListener {
    pub on_vsync_received: Option<
        extern "C" fn(
            listener: *mut HWC2EventListener,
            sequence_id: i32,
            display: Hwc2DisplayT,
            timestamp: i64,
        ),
    >,
    pub on_hotplug_received: Option<
        extern "C" fn(
            listener: *mut HWC2EventListener,
            sequence_id: i32,
            display: Hwc2DisplayT,
            connected: bool,
            primary_display: bool,
        ),
    >,
    pub on_refresh_received: Option<
        extern "C" fn(listener: *mut HWC2EventListener, sequence_id: i32, display: Hwc2DisplayT),
    >,
}

/// Opaque hwc2_compat_device_t
#[repr(C)]
pub struct Hwc2CompatDevice {
    _data: [u8; 0],
}

/// Opaque hwc2_compat_display_t
#[repr(C)]
pub struct Hwc2CompatDisplay {
    _data: [u8; 0],
}

/// Opaque hwc2_compat_layer_t
#[repr(C)]
pub struct Hwc2CompatLayer {
    _data: [u8; 0],
}

/// Opaque hwc2_compat_out_fences_t
#[repr(C)]
pub struct Hwc2CompatOutFences {
    _data: [u8; 0],
}

/// Opaque ANativeWindow
#[repr(C)]
pub struct ANativeWindow {
    _data: [u8; 0],
}

/// Opaque ANativeWindowBuffer
#[repr(C)]
pub struct ANativeWindowBuffer {
    _data: [u8; 0],
}

/// Present callback type for HWCNativeWindow
pub type HWCPresentCallback = extern "C" fn(
    user_data: *mut c_void,
    window: *mut ANativeWindow,
    buffer: *mut ANativeWindowBuffer,
);

/// Opaque buffer handle type from Android
#[repr(C)]
pub struct BufferHandle {
    _data: [u8; 0],
}

/// buffer_handle_t is a pointer to buffer handle
pub type BufferHandleT = *mut BufferHandle;

// Gralloc functions - MUST call hybris_gralloc_initialize before using
#[link(name = "gralloc")]
extern "C" {
    /// Initialize hybris gralloc - needed for buffer allocation
    pub fn hybris_gralloc_initialize(framebuffer: c_int);

    /// Allocate a gralloc buffer
    /// Returns 0 on success, non-zero on failure
    pub fn hybris_gralloc_allocate(
        width: c_int,
        height: c_int,
        format: c_int,
        usage: c_int,
        handle_ptr: *mut BufferHandleT,
        stride_ptr: *mut u32,
    ) -> c_int;

    /// Release a gralloc buffer
    /// was_allocated: 1 if buffer was allocated by us, 0 if imported
    pub fn hybris_gralloc_release(handle: BufferHandleT, was_allocated: c_int) -> c_int;

    /// Retain (add reference to) a gralloc buffer
    pub fn hybris_gralloc_retain(handle: BufferHandleT) -> c_int;

    /// Lock buffer for CPU access
    /// Returns pointer to buffer data in vaddr
    pub fn hybris_gralloc_lock(
        handle: BufferHandleT,
        usage: c_int,
        l: c_int,
        t: c_int,
        w: c_int,
        h: c_int,
        vaddr: *mut *mut c_void,
    ) -> c_int;

    /// Unlock buffer after CPU access
    pub fn hybris_gralloc_unlock(handle: BufferHandleT) -> c_int;
}

/// Initialize gralloc subsystem - call this first!
pub fn gralloc_initialize() {
    unsafe { hybris_gralloc_initialize(0) };
}

/// Initialize HWC2 subsystem - call this after gralloc_initialize() and before creating devices
pub fn hwc2_initialize() {
    unsafe { hybris_hwc2_initialize() };
}

// Link against libhybris libraries
#[link(name = "hybris-hwcomposerwindow")]
#[link(name = "hwc2")]
extern "C" {
    /// Initialize HWC2 subsystem - MUST be called before hwc2_compat_device_new
    pub fn hybris_hwc2_initialize();

    // === HWC2 Compatibility Layer Functions ===

    /// Create a new HWC2 device
    pub fn hwc2_compat_device_new(use_vr_composer: bool) -> *mut Hwc2CompatDevice;

    /// Register event callbacks
    pub fn hwc2_compat_device_register_callback(
        device: *mut Hwc2CompatDevice,
        listener: *mut HWC2EventListener,
        composer_sequence_id: c_int,
    );

    /// Handle hotplug event
    pub fn hwc2_compat_device_on_hotplug(
        device: *mut Hwc2CompatDevice,
        display_id: Hwc2DisplayT,
        connected: bool,
    );

    /// Get display by ID
    pub fn hwc2_compat_device_get_display_by_id(
        device: *mut Hwc2CompatDevice,
        id: Hwc2DisplayT,
    ) -> *mut Hwc2CompatDisplay;

    /// Destroy a display
    pub fn hwc2_compat_device_destroy_display(
        device: *mut Hwc2CompatDevice,
        display: *mut Hwc2CompatDisplay,
    );

    /// Get active display configuration
    pub fn hwc2_compat_display_get_active_config(
        display: *mut Hwc2CompatDisplay,
    ) -> *mut HWC2DisplayConfig;

    /// Accept display changes
    pub fn hwc2_compat_display_accept_changes(display: *mut Hwc2CompatDisplay) -> Hwc2ErrorT;

    /// Create a layer on the display
    pub fn hwc2_compat_display_create_layer(
        display: *mut Hwc2CompatDisplay,
    ) -> *mut Hwc2CompatLayer;

    /// Destroy a layer
    pub fn hwc2_compat_display_destroy_layer(
        display: *mut Hwc2CompatDisplay,
        layer: *mut Hwc2CompatLayer,
    );

    /// Get release fences
    pub fn hwc2_compat_display_get_release_fences(
        display: *mut Hwc2CompatDisplay,
        out_fences: *mut *mut Hwc2CompatOutFences,
    ) -> Hwc2ErrorT;

    /// Present the display
    pub fn hwc2_compat_display_present(
        display: *mut Hwc2CompatDisplay,
        out_present_fence: *mut i32,
    ) -> Hwc2ErrorT;

    /// Set the client target buffer
    pub fn hwc2_compat_display_set_client_target(
        display: *mut Hwc2CompatDisplay,
        slot: u32,
        buffer: *mut ANativeWindowBuffer,
        acquire_fence_fd: i32,
        dataspace: AndroidDataspaceT,
    ) -> Hwc2ErrorT;

    /// Set power mode
    pub fn hwc2_compat_display_set_power_mode(
        display: *mut Hwc2CompatDisplay,
        mode: c_int,
    ) -> Hwc2ErrorT;

    /// Enable/disable vsync
    pub fn hwc2_compat_display_set_vsync_enabled(
        display: *mut Hwc2CompatDisplay,
        enabled: c_int,
    ) -> Hwc2ErrorT;

    /// Validate the display composition
    pub fn hwc2_compat_display_validate(
        display: *mut Hwc2CompatDisplay,
        out_num_types: *mut u32,
        out_num_requests: *mut u32,
    ) -> Hwc2ErrorT;

    /// Present or validate
    pub fn hwc2_compat_display_present_or_validate(
        display: *mut Hwc2CompatDisplay,
        out_num_types: *mut u32,
        out_num_requests: *mut u32,
        out_present_fence: *mut i32,
        state: *mut u32,
    ) -> Hwc2ErrorT;

    // === Layer Functions ===

    /// Set layer buffer
    pub fn hwc2_compat_layer_set_buffer(
        layer: *mut Hwc2CompatLayer,
        slot: u32,
        buffer: *mut ANativeWindowBuffer,
        acquire_fence_fd: i32,
    ) -> Hwc2ErrorT;

    /// Set layer blend mode
    pub fn hwc2_compat_layer_set_blend_mode(
        layer: *mut Hwc2CompatLayer,
        mode: c_int,
    ) -> Hwc2ErrorT;

    /// Set layer color
    pub fn hwc2_compat_layer_set_color(layer: *mut Hwc2CompatLayer, color: HwcColor)
        -> Hwc2ErrorT;

    /// Set composition type
    pub fn hwc2_compat_layer_set_composition_type(
        layer: *mut Hwc2CompatLayer,
        comp_type: c_int,
    ) -> Hwc2ErrorT;

    /// Set layer dataspace
    pub fn hwc2_compat_layer_set_dataspace(
        layer: *mut Hwc2CompatLayer,
        dataspace: AndroidDataspaceT,
    ) -> Hwc2ErrorT;

    /// Set display frame
    pub fn hwc2_compat_layer_set_display_frame(
        layer: *mut Hwc2CompatLayer,
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    ) -> Hwc2ErrorT;

    /// Set plane alpha
    pub fn hwc2_compat_layer_set_plane_alpha(
        layer: *mut Hwc2CompatLayer,
        alpha: f32,
    ) -> Hwc2ErrorT;

    /// Set sideband stream
    pub fn hwc2_compat_layer_set_sideband_stream(
        layer: *mut Hwc2CompatLayer,
        stream: *mut NativeHandle,
    ) -> Hwc2ErrorT;

    /// Set source crop
    pub fn hwc2_compat_layer_set_source_crop(
        layer: *mut Hwc2CompatLayer,
        left: f32,
        top: f32,
        right: f32,
        bottom: f32,
    ) -> Hwc2ErrorT;

    /// Set transform
    pub fn hwc2_compat_layer_set_transform(
        layer: *mut Hwc2CompatLayer,
        transform: c_int,
    ) -> Hwc2ErrorT;

    /// Set visible region
    pub fn hwc2_compat_layer_set_visible_region(
        layer: *mut Hwc2CompatLayer,
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    ) -> Hwc2ErrorT;

    // === Fence Functions ===

    /// Get fence for a layer
    pub fn hwc2_compat_out_fences_get_fence(
        fences: *mut Hwc2CompatOutFences,
        layer: *mut Hwc2CompatLayer,
    ) -> i32;

    /// Destroy out fences
    pub fn hwc2_compat_out_fences_destroy(fences: *mut Hwc2CompatOutFences);

    // === HWC Native Window Functions ===

    /// Create a native window for HWC rendering
    pub fn HWCNativeWindowCreate(
        width: u32,
        height: u32,
        format: u32,
        present: HWCPresentCallback,
        cb_data: *mut c_void,
    ) -> *mut ANativeWindow;

    /// Destroy a native window
    pub fn HWCNativeWindowDestroy(window: *mut ANativeWindow);

    /// Set buffer count
    pub fn HWCNativeWindowSetBufferCount(window: *mut ANativeWindow, cnt: c_int) -> c_int;

    /// Get fence FD from buffer
    pub fn HWCNativeBufferGetFence(buf: *mut ANativeWindowBuffer) -> c_int;

    /// Set fence FD on buffer
    pub fn HWCNativeBufferSetFence(buf: *mut ANativeWindowBuffer, fd: c_int);
}

// EGL types and functions
pub type EGLDisplay = *mut c_void;
pub type EGLSurface = *mut c_void;
pub type EGLContext = *mut c_void;
pub type EGLConfig = *mut c_void;
pub type EGLNativeWindowType = *mut ANativeWindow;
pub type EGLNativeDisplayType = *mut c_void;
pub type EGLint = i32;
pub type EGLBoolean = u32;

pub const EGL_FALSE: EGLBoolean = 0;
pub const EGL_TRUE: EGLBoolean = 1;
pub const EGL_NO_DISPLAY: EGLDisplay = std::ptr::null_mut();
pub const EGL_NO_SURFACE: EGLSurface = std::ptr::null_mut();
pub const EGL_NO_CONTEXT: EGLContext = std::ptr::null_mut();

// EGL attributes
pub const EGL_SURFACE_TYPE: EGLint = 0x3033;
pub const EGL_WINDOW_BIT: EGLint = 0x0004;
pub const EGL_RENDERABLE_TYPE: EGLint = 0x3040;
pub const EGL_OPENGL_ES2_BIT: EGLint = 0x0004;
pub const EGL_RED_SIZE: EGLint = 0x3024;
pub const EGL_GREEN_SIZE: EGLint = 0x3023;
pub const EGL_BLUE_SIZE: EGLint = 0x3022;
pub const EGL_ALPHA_SIZE: EGLint = 0x3021;
pub const EGL_DEPTH_SIZE: EGLint = 0x3025;
pub const EGL_NONE: EGLint = 0x3038;
pub const EGL_CONTEXT_CLIENT_VERSION: EGLint = 0x3098;
pub const EGL_DEFAULT_DISPLAY: EGLNativeDisplayType = std::ptr::null_mut();

#[link(name = "EGL")]
extern "C" {
    pub fn eglGetDisplay(display_id: EGLNativeDisplayType) -> EGLDisplay;
    pub fn eglInitialize(dpy: EGLDisplay, major: *mut EGLint, minor: *mut EGLint) -> EGLBoolean;
    pub fn eglTerminate(dpy: EGLDisplay) -> EGLBoolean;
    pub fn eglChooseConfig(
        dpy: EGLDisplay,
        attrib_list: *const EGLint,
        configs: *mut EGLConfig,
        config_size: EGLint,
        num_config: *mut EGLint,
    ) -> EGLBoolean;
    pub fn eglCreateWindowSurface(
        dpy: EGLDisplay,
        config: EGLConfig,
        win: EGLNativeWindowType,
        attrib_list: *const EGLint,
    ) -> EGLSurface;
    pub fn eglCreateContext(
        dpy: EGLDisplay,
        config: EGLConfig,
        share_context: EGLContext,
        attrib_list: *const EGLint,
    ) -> EGLContext;
    pub fn eglMakeCurrent(
        dpy: EGLDisplay,
        draw: EGLSurface,
        read: EGLSurface,
        ctx: EGLContext,
    ) -> EGLBoolean;
    pub fn eglSwapBuffers(dpy: EGLDisplay, surface: EGLSurface) -> EGLBoolean;
    pub fn eglDestroyContext(dpy: EGLDisplay, ctx: EGLContext) -> EGLBoolean;
    pub fn eglDestroySurface(dpy: EGLDisplay, surface: EGLSurface) -> EGLBoolean;
    pub fn eglGetError() -> EGLint;
}

// Safety note: All these FFI functions are unsafe by nature.
// The safe wrappers in hwcomposer.rs handle proper initialization and cleanup.
