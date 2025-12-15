//! Android WLEGL protocol implementation for libhybris buffer sharing
//!
//! This module implements the android_wlegl Wayland protocol, which allows
//! clients using libhybris (like SDL2/Kivy on Droidian) to share Android
//! gralloc buffers with the compositor for hardware-accelerated rendering.

use std::os::unix::io::{OwnedFd, RawFd};
use std::sync::Mutex;

use smithay::reexports::wayland_server::{
    backend::GlobalId,
    protocol::wl_buffer::WlBuffer,
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use tracing::{debug, info};

// Include the generated protocol code
mod generated {
    #![allow(dead_code, non_camel_case_types, unused_unsafe, unused_variables)]
    #![allow(non_upper_case_globals, non_snake_case, unused_imports)]
    #![allow(missing_docs, clippy::all)]

    use smithay::reexports::wayland_server;
    use smithay::reexports::wayland_server::protocol::*;

    pub mod __interfaces {
        use smithay::reexports::wayland_server::backend as wayland_backend;
        use smithay::reexports::wayland_server::protocol::__interfaces::*;
        wayland_scanner::generate_interfaces!("protocols/android-wlegl.xml");
    }

    use self::__interfaces::*;
    wayland_scanner::generate_server_code!("protocols/android-wlegl.xml");
}

pub use generated::android_wlegl::AndroidWlegl;
pub use generated::android_wlegl_handle::AndroidWleglHandle;

/// Inner data for handle (using RefCell for interior mutability)
#[derive(Debug, Default)]
struct HandleDataInner {
    /// File descriptors for the native handle
    fds: Vec<OwnedFd>,
    /// Integer data for the native handle
    ints: Vec<i32>,
    /// Expected number of fds
    num_fds: i32,
    /// Expected number of ints
    num_ints: i32,
}

/// Data stored for each android_wlegl_handle
#[derive(Debug, Default)]
pub struct HandleData {
    inner: Mutex<HandleDataInner>,
}

/// Data for wl_buffer created from android native handle
#[derive(Debug)]
pub struct AndroidBufferData {
    pub width: i32,
    pub height: i32,
    pub stride: i32,
    pub format: i32,
    pub usage: i32,
    pub fds: Vec<RawFd>,
    pub ints: Vec<i32>,
}

/// State for the android_wlegl global
#[derive(Debug)]
pub struct AndroidWleglState {
    global: GlobalId,
}

impl AndroidWleglState {
    /// Initialize the android_wlegl global
    pub fn new<D>(display: &DisplayHandle) -> Self
    where
        D: GlobalDispatch<AndroidWlegl, ()> + 'static,
        D: Dispatch<AndroidWlegl, ()> + 'static,
        D: Dispatch<AndroidWleglHandle, HandleData> + 'static,
        D: Dispatch<WlBuffer, AndroidBufferData> + 'static,
    {
        let global = display.create_global::<D, AndroidWlegl, _>(2, ());
        info!("android_wlegl global created (version 2)");
        Self { global }
    }

    /// Get the global ID
    pub fn global(&self) -> GlobalId {
        self.global.clone()
    }

    /// Send supported formats to client
    pub fn send_formats(wlegl: &AndroidWlegl) {
        // Common HAL formats used by Android:
        // HAL_PIXEL_FORMAT_RGBA_8888 = 1
        // HAL_PIXEL_FORMAT_RGBX_8888 = 2
        // HAL_PIXEL_FORMAT_RGB_888 = 3
        // HAL_PIXEL_FORMAT_RGB_565 = 4
        // HAL_PIXEL_FORMAT_BGRA_8888 = 5
        let formats = [1, 2, 3, 4, 5];
        for format in formats {
            wlegl.format(format);
        }
    }
}

// Implement GlobalDispatch for android_wlegl
impl<D> GlobalDispatch<AndroidWlegl, (), D> for AndroidWleglState
where
    D: GlobalDispatch<AndroidWlegl, ()> + 'static,
    D: Dispatch<AndroidWlegl, ()> + 'static,
    D: Dispatch<AndroidWleglHandle, HandleData> + 'static,
    D: Dispatch<WlBuffer, AndroidBufferData> + 'static,
{
    fn bind(
        _state: &mut D,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<AndroidWlegl>,
        _global_data: &(),
        data_init: &mut DataInit<'_, D>,
    ) {
        let wlegl = data_init.init(resource, ());
        info!("android_wlegl bound by client");

        // Send supported formats
        AndroidWleglState::send_formats(&wlegl);
    }
}

// Implement Dispatch for android_wlegl
impl<D> Dispatch<AndroidWlegl, (), D> for AndroidWleglState
where
    D: Dispatch<AndroidWlegl, ()> + 'static,
    D: Dispatch<AndroidWleglHandle, HandleData> + 'static,
    D: Dispatch<WlBuffer, AndroidBufferData> + 'static,
    D: AndroidWleglHandler + 'static,
{
    fn request(
        state: &mut D,
        _client: &Client,
        _resource: &AndroidWlegl,
        request: generated::android_wlegl::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, D>,
    ) {
        match request {
            generated::android_wlegl::Request::CreateHandle { id, num_fds, num_ints } => {
                debug!("create_handle: num_fds={}, num_ints={}", num_fds, num_ints);
                let handle_data = HandleData {
                    inner: Mutex::new(HandleDataInner {
                        fds: Vec::with_capacity(num_fds as usize),
                        ints: Vec::with_capacity(num_ints as usize),
                        num_fds,
                        num_ints,
                    }),
                };
                let _handle = data_init.init(id, handle_data);
                debug!("Handle created");
            }
            generated::android_wlegl::Request::CreateBuffer {
                id,
                width,
                height,
                stride,
                format,
                usage,
                native_handle,
            } => {
                debug!(
                    "create_buffer: {}x{}, stride={}, format={}, usage={}",
                    width, height, stride, format, usage
                );

                // Get the handle data
                let handle_data: &HandleData = native_handle.data().expect("Handle has no data");
                let inner = handle_data.inner.lock().unwrap();

                // Extract fds and ints from the handle
                let fds: Vec<RawFd> = inner.fds.iter().map(|fd| {
                    use std::os::unix::io::AsRawFd;
                    fd.as_raw_fd()
                }).collect();
                let ints = inner.ints.clone();

                debug!(
                    "Buffer native handle: {} fds, {} ints",
                    fds.len(),
                    ints.len()
                );

                // Create buffer data
                let buffer_data = AndroidBufferData {
                    width,
                    height,
                    stride,
                    format,
                    usage,
                    fds,
                    ints,
                };

                // Create the wl_buffer
                let buffer = data_init.init(id, buffer_data);
                debug!("Buffer created: {:?}", buffer.id());

                // Notify the handler that a buffer was created
                state.android_buffer_created(&buffer);
            }
        }
    }
}

// Implement Dispatch for android_wlegl_handle
impl<D> Dispatch<AndroidWleglHandle, HandleData, D> for AndroidWleglState
where
    D: Dispatch<AndroidWleglHandle, HandleData> + 'static,
{
    fn request(
        _state: &mut D,
        _client: &Client,
        resource: &AndroidWleglHandle,
        request: generated::android_wlegl_handle::Request,
        data: &HandleData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, D>,
    ) {
        match request {
            generated::android_wlegl_handle::Request::AddFd { fd } => {
                debug!("add_fd: fd received");
                data.inner.lock().unwrap().fds.push(fd);
            }
            generated::android_wlegl_handle::Request::AddInt { value } => {
                debug!("add_int: value={}", value);
                data.inner.lock().unwrap().ints.push(value);
            }
            generated::android_wlegl_handle::Request::Destroy => {
                debug!("handle destroy: {:?}", resource.id());
            }
        }
    }
}

// Implement Dispatch for wl_buffer (android buffers)
impl<D> Dispatch<WlBuffer, AndroidBufferData, D> for AndroidWleglState
where
    D: Dispatch<WlBuffer, AndroidBufferData> + 'static,
{
    fn request(
        _state: &mut D,
        _client: &Client,
        resource: &WlBuffer,
        request: smithay::reexports::wayland_server::protocol::wl_buffer::Request,
        _data: &AndroidBufferData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, D>,
    ) {
        match request {
            smithay::reexports::wayland_server::protocol::wl_buffer::Request::Destroy => {
                debug!("Android buffer destroyed: {:?}", resource.id());
            }
            _ => {}
        }
    }
}

/// Handler trait for android_wlegl events
pub trait AndroidWleglHandler {
    /// Called when an android buffer is created
    fn android_buffer_created(&mut self, buffer: &WlBuffer);
}

/// Macro to delegate android_wlegl handling
#[macro_export]
macro_rules! delegate_android_wlegl {
    ($ty:ty) => {
        smithay::reexports::wayland_server::delegate_global_dispatch!($ty: [
            $crate::android_wlegl::AndroidWlegl: ()
        ] => $crate::android_wlegl::AndroidWleglState);

        smithay::reexports::wayland_server::delegate_dispatch!($ty: [
            $crate::android_wlegl::AndroidWlegl: ()
        ] => $crate::android_wlegl::AndroidWleglState);

        smithay::reexports::wayland_server::delegate_dispatch!($ty: [
            $crate::android_wlegl::AndroidWleglHandle: $crate::android_wlegl::HandleData
        ] => $crate::android_wlegl::AndroidWleglState);

        smithay::reexports::wayland_server::delegate_dispatch!($ty: [
            smithay::reexports::wayland_server::protocol::wl_buffer::WlBuffer: $crate::android_wlegl::AndroidBufferData
        ] => $crate::android_wlegl::AndroidWleglState);
    };
}
