mod black_hole;
mod camera;
mod gravity_sim;
mod renderer;

use std::sync::Arc;
use winit::{
    application::ApplicationHandler,
    event::{ElementState, KeyEvent, MouseButton, MouseScrollDelta, WindowEvent},
    event_loop::{ActiveEventLoop, ControlFlow, EventLoop},
    keyboard::{Key, NamedKey},
    window::{Window, WindowAttributes, WindowId},
};

use renderer::Renderer;

const ARROW_STEP: f32 = 0.05;

struct App {
    renderer: Option<Renderer>,
    window: Option<Arc<Window>>,
    /// Saved gravity state before right-click, so we can restore it on release.
    /// This ensures right-click acts as a temporary "boost" without interfering with 'g' key toggle.
    gravity_state_before_right_click: bool,
}

impl App {
    fn new() -> Self {
        Self {
            renderer: None,
            window: None,
            gravity_state_before_right_click: false,
        }
    }
}

impl ApplicationHandler for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }

        let attrs = WindowAttributes::default()
            .with_title("Black Hole — Rust + wgpu")
            .with_inner_size(winit::dpi::LogicalSize::new(800u32, 600u32));

        let window = Arc::new(event_loop.create_window(attrs).unwrap());
        self.window = Some(window.clone());

        // Initialize wgpu
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::all(),
            ..Default::default()
        });

        let surface = instance.create_surface(window.clone()).unwrap();

        let (adapter, device, queue) = pollster::block_on(async {
            let adapter = instance
                .request_adapter(&wgpu::RequestAdapterOptions {
                    power_preference: wgpu::PowerPreference::HighPerformance,
                    compatible_surface: Some(&surface),
                    force_fallback_adapter: false,
                })
                .await
                .expect("Failed to find a suitable GPU adapter");

            log::info!("GPU: {}", adapter.get_info().name);

            let (device, queue) = adapter
                .request_device(
                    &wgpu::DeviceDescriptor {
                        label: Some("black hole device"),
                        required_features: wgpu::Features::empty(),
                        required_limits: wgpu::Limits::default(),
                        memory_hints: Default::default(),
                    },
                    None,
                )
                .await
                .expect("Failed to create device");

            (adapter, device, queue)
        });

        let size = window.inner_size();
        let surface_config = surface
            .get_default_config(&adapter, size.width.max(1), size.height.max(1))
            .expect("Surface not supported by adapter");
        surface.configure(&device, &surface_config);

        let device = Arc::new(device);
        let queue = Arc::new(queue);

        self.renderer = Some(Renderer::new(device, queue, surface, surface_config));
    }

    fn window_event(
        &mut self,
        event_loop: &ActiveEventLoop,
        _window_id: WindowId,
        event: WindowEvent,
    ) {
        let Some(renderer) = self.renderer.as_mut() else {
            return;
        };

        match event {
            WindowEvent::CloseRequested => {
                event_loop.exit();
            }

            WindowEvent::Resized(size) => {
                renderer.resize(size.width, size.height);
                if let Some(win) = &self.window {
                    win.request_redraw();
                }
            }

            WindowEvent::RedrawRequested => {
                match renderer.render() {
                    Ok(_) => {}
                    Err(wgpu::SurfaceError::Lost) => {
                        let [w, h] = renderer.viewport_size;
                        renderer.resize(w, h);
                    }
                    Err(wgpu::SurfaceError::OutOfMemory) => {
                        event_loop.exit();
                    }
                    Err(e) => {
                        log::warn!("Surface error: {:?}", e);
                    }
                }
                if let Some(win) = &self.window {
                    win.request_redraw();
                }
            }

            WindowEvent::MouseInput { state, button, .. } => match button {
                MouseButton::Left => {
                    if state == ElementState::Pressed {
                        renderer.camera.on_mouse_press(0.0, 0.0);
                    } else {
                        renderer.camera.on_mouse_release();
                    }
                }
                MouseButton::Right => {
                    if state == ElementState::Pressed {
                        // Save current state and enable gravity as a temporary boost
                        self.gravity_state_before_right_click = renderer.gravity_sim.is_enabled;
                        renderer.gravity_sim.is_enabled = true;
                    } else {
                        // Restore the saved state (respects 'g' key toggle)
                        renderer.gravity_sim.is_enabled = self.gravity_state_before_right_click;
                    }
                    renderer.needs_compute_update = true;
                }
                _ => {}
            },

            WindowEvent::CursorMoved { position, .. } => {
                if renderer.camera.is_dragging {
                    renderer.camera.on_mouse_drag(position.x, position.y);
                } else {
                    // Store position for next drag start
                    renderer.camera.last_mouse = [position.x, position.y];
                }
            }

            WindowEvent::MouseWheel { delta, .. } => {
                let scroll = match delta {
                    MouseScrollDelta::LineDelta(_, y) => y,
                    MouseScrollDelta::PixelDelta(pos) => pos.y as f32 / 30.0,
                };
                renderer.camera.on_scroll(scroll);
            }

            WindowEvent::KeyboardInput {
                event:
                    KeyEvent {
                        logical_key,
                        state: ElementState::Pressed,
                        ..
                    },
                ..
            } => match logical_key {
                Key::Character(ref c) => match c.as_str() {
                    "g" => {
                        renderer.gravity_sim.is_enabled =
                            !renderer.gravity_sim.is_enabled;
                        renderer.needs_compute_update = true;
                        log::info!(
                            "Gravity {}",
                            if renderer.gravity_sim.is_enabled {
                                "ON"
                            } else {
                                "OFF"
                            }
                        );
                    }
                    "r" => {
                        renderer.camera.auto_rotate = !renderer.camera.auto_rotate;
                        log::info!(
                            "Auto-rotate {}",
                            if renderer.camera.auto_rotate { "ON" } else { "OFF" }
                        );
                    }
                    "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" => {
                        let level: u32 = c.parse().unwrap_or(2);
                        renderer.set_resolution_level(level);
                    }
                    _ => {}
                },
                Key::Named(NamedKey::ArrowUp) => {
                    renderer.camera.nudge_elevation(-ARROW_STEP);
                }
                Key::Named(NamedKey::ArrowDown) => {
                    renderer.camera.nudge_elevation(ARROW_STEP);
                }
                Key::Named(NamedKey::ArrowLeft) => {
                    renderer.camera.nudge_azimuth(-ARROW_STEP);
                }
                Key::Named(NamedKey::ArrowRight) => {
                    renderer.camera.nudge_azimuth(ARROW_STEP);
                }
                Key::Named(NamedKey::Escape) => {
                    event_loop.exit();
                }
                _ => {}
            },

            _ => {}
        }
    }
}

fn main() {
    env_logger::init();

    let event_loop = EventLoop::new().unwrap();
    event_loop.set_control_flow(ControlFlow::Poll);

    let mut app = App::new();
    event_loop.run_app(&mut app).unwrap();
}
