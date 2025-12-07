//! Winit backend for development/testing
//!
//! Runs the compositor in a window, useful for development without
//! needing to log out of your desktop session.

use std::time::Duration;

use anyhow::Result;
use tracing::{debug, info, warn};

use smithay::{
    backend::{
        renderer::{
            damage::OutputDamageTracker,
            element::surface::WaylandSurfaceRenderElement,
            gles::GlesRenderer,
        },
        winit::{self, WinitEvent},
    },
    desktop::space::SpaceRenderElements,
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::{
        calloop::{
            timer::{TimeoutAction, Timer},
            EventLoop,
        },
        wayland_server::Display,
        winit::platform::pump_events::PumpStatus,
    },
    utils::Transform,
};

use crate::state::Flick;

pub fn run() -> Result<()> {
    // Create event loop
    let mut event_loop: EventLoop<Flick> = EventLoop::try_new()?;
    let loop_handle = event_loop.handle();

    // Initialize winit backend
    let (mut backend, mut winit_evt) = winit::init::<GlesRenderer>()
        .map_err(|e| anyhow::anyhow!("Failed to init winit: {:?}", e))?;

    // Get initial window size
    let size = backend.window_size();
    info!("Winit window size: {:?}", size);

    // Create Wayland display
    let display: Display<Flick> = Display::new()?;

    // Create compositor state
    let screen_size = size.to_logical(1);
    let mut state = Flick::new(display, loop_handle.clone(), screen_size);

    // Create output for the winit window
    let output = Output::new(
        "winit".to_string(),
        PhysicalProperties {
            size: (0, 0).into(),
            subpixel: Subpixel::Unknown,
            make: "Flick".to_string(),
            model: "Winit Window".to_string(),
            serial_number: "Unknown".to_string(),
        },
    );

    let mode = Mode {
        size,
        refresh: 60_000,
    };

    output.change_current_state(Some(mode), Some(Transform::Flipped180), None, Some((0, 0).into()));
    output.set_preferred(mode);

    state.space.map_output(&output, (0, 0));
    state.outputs.push(output.clone());

    info!("Wayland socket: {:?}", state.socket_name);

    // Set WAYLAND_DISPLAY for child processes
    std::env::set_var("WAYLAND_DISPLAY", &state.socket_name);

    // Shell is integrated - no external process needed

    // Create damage tracker for rendering
    let mut damage_tracker = OutputDamageTracker::from_output(&output);

    // Add a timer for redraw
    loop_handle
        .insert_source(Timer::immediate(), move |_, _, _state| {
            TimeoutAction::ToDuration(Duration::from_millis(16))
        })
        .expect("Failed to insert timer");

    info!("Entering event loop");
    info!("You can now run Wayland clients with WAYLAND_DISPLAY={:?}", state.socket_name);

    // Main event loop
    loop {
        // Process winit events
        let status = winit_evt.dispatch_new_events(|event| match event {
            WinitEvent::Resized { size, .. } => {
                debug!("Window resized: {:?}", size);
                let mode = Mode {
                    size,
                    refresh: 60_000,
                };
                output.change_current_state(Some(mode), None, None, None);
            }
            WinitEvent::Input(event) => {
                debug!("Input event: {:?}", event);
                // TODO: Handle input and dispatch to clients
            }
            WinitEvent::Redraw => {
                // Get age before binding
                let age = backend.buffer_age().unwrap_or(0);
                let scale = output.current_scale().fractional_scale() as f32;

                let render_result = backend.bind().and_then(|(renderer, mut fb)| {
                    // Get render elements from space
                    let elements: Vec<SpaceRenderElements<GlesRenderer, WaylandSurfaceRenderElement<GlesRenderer>>> = state
                        .space
                        .render_elements_for_output(renderer, &output, scale)
                        .unwrap_or_default();

                    // Render
                    let res = damage_tracker.render_output(
                        renderer,
                        &mut fb,
                        age,
                        &elements,
                        [0.1, 0.1, 0.2, 1.0], // background color
                    );

                    match res {
                        Ok(r) => Ok(r),
                        Err(e) => Err(smithay::backend::SwapBuffersError::ContextLost(
                            Box::new(std::io::Error::new(std::io::ErrorKind::Other, format!("{:?}", e)))
                        )),
                    }
                });

                match render_result {
                    Ok(render_output_result) => {
                        if let Some(damage) = render_output_result.damage {
                            if let Err(e) = backend.submit(Some(damage)) {
                                warn!("Failed to submit: {:?}", e);
                            }
                        } else {
                            let _ = backend.submit(None);
                        }
                    }
                    Err(err) => {
                        warn!("Render error: {:?}", err);
                        let _ = backend.submit(None);
                    }
                }

                // Send frame callbacks to clients
                state.space.elements().for_each(|window| {
                    window.send_frame(
                        &output,
                        state.start_time.elapsed(),
                        Some(Duration::ZERO),
                        |_, _| Some(output.clone()),
                    );
                });
            }
            WinitEvent::CloseRequested => {
                info!("Close requested, exiting...");
                std::process::exit(0);
            }
            WinitEvent::Focus(_) => {}
        });

        if let PumpStatus::Exit(_) = status {
            info!("Winit exit requested");
            break;
        }

        // Dispatch calloop events
        event_loop
            .dispatch(Some(Duration::from_millis(1)), &mut state)
            .expect("Failed to dispatch event loop");
    }

    Ok(())
}
