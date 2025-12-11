//! XWayland support for running X11 applications

use smithay::{
    delegate_xwayland_shell,
    desktop::Window,
    utils::{Logical, Rectangle},
    wayland::xwayland_shell::{XWaylandShellHandler, XWaylandShellState},
    xwayland::xwm::{Reorder, ResizeEdge as X11ResizeEdge, XwmId, X11Surface, X11Wm, XwmHandler},
};

use crate::state::Flick;

impl XwmHandler for Flick {
    fn xwm_state(&mut self, _xwm: XwmId) -> &mut X11Wm {
        self.xwm.as_mut().unwrap()
    }

    fn new_window(&mut self, _xwm: XwmId, window: X11Surface) {
        tracing::info!("New X11 window: {:?}", window.window_id());
    }

    fn new_override_redirect_window(&mut self, _xwm: XwmId, window: X11Surface) {
        tracing::info!("New X11 override redirect window: {:?}", window.window_id());
    }

    fn map_window_request(&mut self, _xwm: XwmId, window: X11Surface) {
        tracing::info!("X11 map window request: {:?}", window.window_id());

        // Log existing window geometry
        let current_geo = window.geometry();
        tracing::info!("X11 window current geometry: {:?}", current_geo);

        // Configure the window to fullscreen (or viewport size in letterbox mode)
        // Use viewport size in letterbox mode so apps don't expand to full screen
        let target_size = if self.phone_shape_enabled {
            self.effective_viewport().size
        } else if let Some(output) = self.outputs.first() {
            output
                .current_mode()
                .map(|m| m.size)
                .unwrap_or((1920, 1080).into())
                .to_logical(1)
        } else {
            (1920, 1080).into()
        };

        let geo = Rectangle::new(
            (0, 0).into(),
            target_size,
        );

        tracing::info!("Configuring X11 window to size: {:?} (letterbox={})", geo, self.phone_shape_enabled);

        // Configure the X11 window
        if let Err(e) = window.configure(geo) {
            tracing::warn!("Failed to configure X11 window: {:?}", e);
        }

        // Map the window
        if let Err(e) = window.set_mapped(true) {
            tracing::warn!("Failed to map X11 window: {:?}", e);
        }

        // Create a Wayland window wrapper and add to space
        // Do this regardless of whether wl_surface is ready yet
        let win = Window::new_x11_window(window.clone());

        // Use activate=true to bring X11 window to front (on top of shell)
        self.space.map_element(win, (0, 0), true);

        // Switch to App view now that we have a real window
        // This avoids flashing to a random old app when launching from Home
        self.shell.set_view(crate::shell::ShellView::App);

        // Log space state after mapping
        let window_count = self.space.elements().count();
        tracing::info!("X11 window added to space (activate=true), total windows: {}, switched to App view", window_count);

        // Set keyboard focus if surface is available
        if let Some(surface) = window.wl_surface() {
            let serial = smithay::utils::SERIAL_COUNTER.next_serial();
            if let Some(keyboard) = self.seat.get_keyboard() {
                keyboard.set_focus(self, Some(surface.clone()), serial);
                tracing::info!("Keyboard focus set to X11 window");
            }
        } else {
            tracing::info!("X11 window has no wl_surface yet, focus will be set later");
        }
    }

    fn mapped_override_redirect_window(&mut self, _xwm: XwmId, window: X11Surface) {
        tracing::info!("X11 override redirect window mapped: {:?}", window.window_id());

        // Override redirect windows (like menus) - add regardless of surface state
        let win = Window::new_x11_window(window.clone());
        // Override redirect windows go on top
        self.space.map_element(win, (0, 0), true);
        tracing::info!("X11 override redirect window added to space");
    }

    fn unmapped_window(&mut self, _xwm: XwmId, window: X11Surface) {
        tracing::info!("X11 window unmapped: {:?}", window.window_id());

        // Find and remove the window from the space
        let to_remove = self.space.elements()
            .find(|w| {
                w.x11_surface()
                    .map(|s| s.window_id() == window.window_id())
                    .unwrap_or(false)
            })
            .cloned();

        if let Some(win) = to_remove {
            self.space.unmap_elem(&win);

            // If no more X11 windows, switch to Home view
            let has_windows = self.space.elements().any(|w| w.x11_surface().is_some());
            if !has_windows {
                tracing::info!("No more windows after unmap, switching to Home view");
                self.shell.set_view(crate::shell::ShellView::Home);
            }
        }
    }

    fn destroyed_window(&mut self, _xwm: XwmId, window: X11Surface) {
        tracing::info!("X11 window destroyed: {:?}", window.window_id());
    }

    fn configure_request(
        &mut self,
        _xwm: XwmId,
        window: X11Surface,
        x: Option<i32>,
        y: Option<i32>,
        w: Option<u32>,
        h: Option<u32>,
        _reorder: Option<Reorder>,
    ) {
        tracing::debug!("X11 configure request: {:?}", window.window_id());

        // In letterbox mode, enforce viewport size to prevent apps from resizing to full screen
        // This is critical for the lock screen and other apps to stay within the letterbox
        let new_geo = if self.phone_shape_enabled {
            let viewport = self.effective_viewport();
            tracing::info!("X11 configure request enforcing viewport size: {:?} (letterbox mode)", viewport.size);
            Rectangle::new((0, 0).into(), viewport.size)
        } else {
            // Without letterbox, honor the window's requested geometry
            let geo = window.geometry();
            Rectangle::new(
                (x.unwrap_or(geo.loc.x), y.unwrap_or(geo.loc.y)).into(),
                (
                    w.map(|w| w as i32).unwrap_or(geo.size.w).max(1),
                    h.map(|h| h as i32).unwrap_or(geo.size.h).max(1),
                ).into(),
            )
        };

        if let Err(e) = window.configure(new_geo) {
            tracing::warn!("Failed to configure X11 window: {:?}", e);
        }
    }

    fn configure_notify(
        &mut self,
        _xwm: XwmId,
        window: X11Surface,
        geometry: Rectangle<i32, Logical>,
        _above: Option<u32>,
    ) {
        tracing::debug!("X11 configure notify: {:?} -> {:?}", window.window_id(), geometry);
    }

    fn resize_request(
        &mut self,
        _xwm: XwmId,
        window: X11Surface,
        _button: u32,
        _resize_edge: X11ResizeEdge,
    ) {
        tracing::debug!("X11 resize request: {:?}", window.window_id());
        // We don't support interactive resize for now
    }

    fn move_request(&mut self, _xwm: XwmId, window: X11Surface, _button: u32) {
        tracing::debug!("X11 move request: {:?}", window.window_id());
        // We don't support interactive move for now
    }

    fn maximize_request(&mut self, _xwm: XwmId, window: X11Surface) {
        tracing::debug!("X11 maximize request: {:?}", window.window_id());
        // Already fullscreen
    }

    fn unmaximize_request(&mut self, _xwm: XwmId, window: X11Surface) {
        tracing::debug!("X11 unmaximize request: {:?}", window.window_id());
    }

    fn fullscreen_request(&mut self, _xwm: XwmId, window: X11Surface) {
        tracing::debug!("X11 fullscreen request: {:?}", window.window_id());
        // Already fullscreen
    }

    fn unfullscreen_request(&mut self, _xwm: XwmId, window: X11Surface) {
        tracing::debug!("X11 unfullscreen request: {:?}", window.window_id());
    }

    fn minimize_request(&mut self, _xwm: XwmId, window: X11Surface) {
        tracing::debug!("X11 minimize request: {:?}", window.window_id());
    }
}

impl XWaylandShellHandler for Flick {
    fn xwayland_shell_state(&mut self) -> &mut XWaylandShellState {
        self.xwayland_shell_state.as_mut().unwrap()
    }

    fn surface_associated(
        &mut self,
        _xwm: XwmId,
        wl_surface: smithay::reexports::wayland_server::protocol::wl_surface::WlSurface,
        window: X11Surface,
    ) {
        tracing::info!(
            "X11 window {:?} associated with wl_surface",
            window.window_id()
        );

        // Now that we have a wl_surface, set keyboard focus to this X11 window
        let serial = smithay::utils::SERIAL_COUNTER.next_serial();
        if let Some(keyboard) = self.seat.get_keyboard() {
            keyboard.set_focus(self, Some(wl_surface), serial);
            tracing::info!("Keyboard focus set to X11 window via surface_associated");
        }
    }
}

delegate_xwayland_shell!(Flick);
