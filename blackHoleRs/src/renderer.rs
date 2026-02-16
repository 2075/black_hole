use std::sync::Arc;
use bytemuck;
use bytemuck::Zeroable;
use wgpu::util::DeviceExt;

use crate::black_hole::*;
use crate::camera::Camera;
use crate::gravity_sim::GravitySim;

/// Main wgpu renderer — owns the compute and render pipelines, camera, and scene state.
/// Replaces the C++ Engine struct from black_hole.cpp.
pub struct Renderer {
    pub device: Arc<wgpu::Device>,
    pub queue: Arc<wgpu::Queue>,
    pub surface: wgpu::Surface<'static>,
    pub surface_config: wgpu::SurfaceConfiguration,

    // Pipelines
    compute_pipeline: wgpu::ComputePipeline,
    quad_pipeline: wgpu::RenderPipeline,
    grid_pipeline: wgpu::RenderPipeline,

    // Bind group layouts
    compute_bind_group_layout: wgpu::BindGroupLayout,
    quad_bind_group_layout: wgpu::BindGroupLayout,
    grid_bind_group_layout: wgpu::BindGroupLayout,

    // Buffers
    quad_vertex_buffer: wgpu::Buffer,
    grid_vertex_buffer: wgpu::Buffer,
    grid_index_buffer: wgpu::Buffer,
    grid_index_count: u32,
    camera_uniform_buffer: wgpu::Buffer,
    disk_uniform_buffer: wgpu::Buffer,
    objects_uniform_buffer: wgpu::Buffer,
    grid_uniform_buffer: wgpu::Buffer,

    // Compute texture (double-buffered)
    compute_textures: [wgpu::Texture; 2],
    compute_texture_views: [wgpu::TextureView; 2],
    display_texture_index: usize,

    // Sampler for quad
    linear_sampler: wgpu::Sampler,

    // Scene
    pub camera: Camera,
    pub gravity_sim: GravitySim,
    pub scene_objects: Vec<SceneObject>,
    pub disk_base_color: [f32; 4],

    // Resolution
    pub resolution_level: u32,
    pub viewport_size: [u32; 2],

    // Dirty flags
    pub needs_compute_update: bool,
    needs_grid_update: bool,

    // Grid
    grid_size: usize,
}

// Fullscreen quad vertices: (x, y, u, v) per vertex, 6 vertices (2 triangles)
#[rustfmt::skip]
const QUAD_VERTICES: &[f32] = &[
    -1.0,  1.0,  0.0, 1.0,
    -1.0, -1.0,  0.0, 0.0,
     1.0, -1.0,  1.0, 0.0,
    -1.0,  1.0,  0.0, 1.0,
     1.0, -1.0,  1.0, 0.0,
     1.0,  1.0,  1.0, 1.0,
];

impl Renderer {
    pub fn new(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        surface: wgpu::Surface<'static>,
        surface_config: wgpu::SurfaceConfiguration,
    ) -> Self {
        let resolution_level: u32 = 2;
        let compute_height = BASE_COMPUTE_HEIGHT * resolution_level;
        let aspect = surface_config.width as f32 / surface_config.height.max(1) as f32;
        let compute_width = ((compute_height as f32 * aspect) as u32).max(1);
        let grid_size: usize = 25;

        // --- Shader modules ---
        let geodesic_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("geodesic compute"),
            source: wgpu::ShaderSource::Wgsl(
                include_str!("../shaders/geodesic.wgsl").into(),
            ),
        });
        let quad_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("quad render"),
            source: wgpu::ShaderSource::Wgsl(
                include_str!("../shaders/quad.wgsl").into(),
            ),
        });
        let grid_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("grid render"),
            source: wgpu::ShaderSource::Wgsl(
                include_str!("../shaders/grid.wgsl").into(),
            ),
        });

        // --- Bind group layouts ---
        let compute_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("compute bind group layout"),
                entries: &[
                    // binding 0: storage texture (write)
                    wgpu::BindGroupLayoutEntry {
                        binding: 0,
                        visibility: wgpu::ShaderStages::COMPUTE,
                        ty: wgpu::BindingType::StorageTexture {
                            access: wgpu::StorageTextureAccess::WriteOnly,
                            format: wgpu::TextureFormat::Rgba8Unorm,
                            view_dimension: wgpu::TextureViewDimension::D2,
                        },
                        count: None,
                    },
                    // binding 1: camera uniforms
                    wgpu::BindGroupLayoutEntry {
                        binding: 1,
                        visibility: wgpu::ShaderStages::COMPUTE,
                        ty: wgpu::BindingType::Buffer {
                            ty: wgpu::BufferBindingType::Uniform,
                            has_dynamic_offset: false,
                            min_binding_size: None,
                        },
                        count: None,
                    },
                    // binding 2: disk uniforms
                    wgpu::BindGroupLayoutEntry {
                        binding: 2,
                        visibility: wgpu::ShaderStages::COMPUTE,
                        ty: wgpu::BindingType::Buffer {
                            ty: wgpu::BufferBindingType::Uniform,
                            has_dynamic_offset: false,
                            min_binding_size: None,
                        },
                        count: None,
                    },
                    // binding 3: objects uniforms
                    wgpu::BindGroupLayoutEntry {
                        binding: 3,
                        visibility: wgpu::ShaderStages::COMPUTE,
                        ty: wgpu::BindingType::Buffer {
                            ty: wgpu::BufferBindingType::Uniform,
                            has_dynamic_offset: false,
                            min_binding_size: None,
                        },
                        count: None,
                    },
                ],
            });

        let quad_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("quad bind group layout"),
                entries: &[
                    wgpu::BindGroupLayoutEntry {
                        binding: 0,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: true },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 1,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                        count: None,
                    },
                ],
            });

        let grid_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("grid bind group layout"),
                entries: &[wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::VERTEX,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                }],
            });

        // --- Compute pipeline ---
        let compute_pipeline_layout =
            device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("compute pipeline layout"),
                bind_group_layouts: &[&compute_bind_group_layout],
                push_constant_ranges: &[],
            });
        let compute_pipeline =
            device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("geodesic compute pipeline"),
                layout: Some(&compute_pipeline_layout),
                module: &geodesic_shader,
                entry_point: Some("main"),
                compilation_options: Default::default(),
                cache: None,
            });

        // --- Quad render pipeline ---
        let quad_pipeline_layout =
            device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("quad pipeline layout"),
                bind_group_layouts: &[&quad_bind_group_layout],
                push_constant_ranges: &[],
            });
        let quad_pipeline =
            device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("quad render pipeline"),
                layout: Some(&quad_pipeline_layout),
                vertex: wgpu::VertexState {
                    module: &quad_shader,
                    entry_point: Some("vs_main"),
                    buffers: &[wgpu::VertexBufferLayout {
                        array_stride: 16, // 4 floats * 4 bytes
                        step_mode: wgpu::VertexStepMode::Vertex,
                        attributes: &[
                            wgpu::VertexAttribute {
                                format: wgpu::VertexFormat::Float32x2,
                                offset: 0,
                                shader_location: 0,
                            },
                            wgpu::VertexAttribute {
                                format: wgpu::VertexFormat::Float32x2,
                                offset: 8,
                                shader_location: 1,
                            },
                        ],
                    }],
                    compilation_options: Default::default(),
                },
                primitive: wgpu::PrimitiveState {
                    topology: wgpu::PrimitiveTopology::TriangleList,
                    ..Default::default()
                },
                depth_stencil: None,
                multisample: wgpu::MultisampleState::default(),
                fragment: Some(wgpu::FragmentState {
                    module: &quad_shader,
                    entry_point: Some("fs_main"),
                    targets: &[Some(wgpu::ColorTargetState {
                        format: surface_config.format,
                        blend: None,
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                    compilation_options: Default::default(),
                }),
                multiview: None,
                cache: None,
            });

        // --- Grid render pipeline ---
        let grid_pipeline_layout =
            device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("grid pipeline layout"),
                bind_group_layouts: &[&grid_bind_group_layout],
                push_constant_ranges: &[],
            });
        let grid_pipeline =
            device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("grid render pipeline"),
                layout: Some(&grid_pipeline_layout),
                vertex: wgpu::VertexState {
                    module: &grid_shader,
                    entry_point: Some("vs_main"),
                    buffers: &[wgpu::VertexBufferLayout {
                        array_stride: 12, // 3 floats * 4 bytes
                        step_mode: wgpu::VertexStepMode::Vertex,
                        attributes: &[wgpu::VertexAttribute {
                            format: wgpu::VertexFormat::Float32x3,
                            offset: 0,
                            shader_location: 0,
                        }],
                    }],
                    compilation_options: Default::default(),
                },
                primitive: wgpu::PrimitiveState {
                    topology: wgpu::PrimitiveTopology::LineList,
                    ..Default::default()
                },
                depth_stencil: None,
                multisample: wgpu::MultisampleState::default(),
                fragment: Some(wgpu::FragmentState {
                    module: &grid_shader,
                    entry_point: Some("fs_main"),
                    targets: &[Some(wgpu::ColorTargetState {
                        format: surface_config.format,
                        blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                    compilation_options: Default::default(),
                }),
                multiview: None,
                cache: None,
            });

        // --- Buffers ---
        let quad_vertex_buffer =
            device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("quad vertices"),
                contents: bytemuck::cast_slice(QUAD_VERTICES),
                usage: wgpu::BufferUsages::VERTEX,
            });

        let vertex_count = (grid_size + 1) * (grid_size + 1);
        let grid_vertex_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("grid vertices"),
            size: (vertex_count * 3 * std::mem::size_of::<f32>()) as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let mut indices: Vec<u32> = Vec::with_capacity(grid_size * grid_size * 4);
        for z in 0..grid_size {
            for x in 0..grid_size {
                let i = (z * (grid_size + 1) + x) as u32;
                indices.push(i);
                indices.push(i + 1);
                indices.push(i);
                indices.push((grid_size + 1) as u32 + i);
            }
        }
        let grid_index_count = indices.len() as u32;
        let grid_index_buffer =
            device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("grid indices"),
                contents: bytemuck::cast_slice(&indices),
                usage: wgpu::BufferUsages::INDEX,
            });

        let camera_uniform_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("camera uniforms"),
            size: std::mem::size_of::<CameraUniforms>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let disk_uniform_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("disk uniforms"),
            size: std::mem::size_of::<DiskUniforms>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let objects_uniform_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("objects uniforms"),
            size: std::mem::size_of::<ObjectsUniforms>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let grid_uniform_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("grid uniforms"),
            size: 64, // mat4x4f = 64 bytes
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        // --- Compute textures (double-buffered) ---
        let make_compute_texture = |label: &str| {
            device.create_texture(&wgpu::TextureDescriptor {
                label: Some(label),
                size: wgpu::Extent3d {
                    width: compute_width,
                    height: compute_height,
                    depth_or_array_layers: 1,
                },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: wgpu::TextureFormat::Rgba8Unorm,
                usage: wgpu::TextureUsages::STORAGE_BINDING
                    | wgpu::TextureUsages::TEXTURE_BINDING,
                view_formats: &[],
            })
        };
        let tex0 = make_compute_texture("compute texture 0");
        let tex1 = make_compute_texture("compute texture 1");
        let view0 = tex0.create_view(&Default::default());
        let view1 = tex1.create_view(&Default::default());

        // --- Sampler ---
        let linear_sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("linear sampler"),
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            ..Default::default()
        });

        Self {
            device,
            queue,
            surface,
            viewport_size: [surface_config.width, surface_config.height],
            surface_config,
            compute_pipeline,
            quad_pipeline,
            grid_pipeline,
            compute_bind_group_layout,
            quad_bind_group_layout,
            grid_bind_group_layout,
            quad_vertex_buffer,
            grid_vertex_buffer,
            grid_index_buffer,
            grid_index_count,
            camera_uniform_buffer,
            disk_uniform_buffer,
            objects_uniform_buffer,
            grid_uniform_buffer,
            compute_textures: [tex0, tex1],
            compute_texture_views: [view0, view1],
            display_texture_index: 0,
            linear_sampler,
            camera: Camera::default(),
            gravity_sim: GravitySim::default(),
            scene_objects: make_default_scene_objects(),
            disk_base_color: [1.0, 0.7, 0.2, 1.0],
            resolution_level,
            needs_compute_update: true,
            needs_grid_update: true,
            grid_size,
        }
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        if width == 0 || height == 0 {
            return;
        }
        self.surface_config.width = width;
        self.surface_config.height = height;
        self.surface.configure(&self.device, &self.surface_config);
        self.viewport_size = [width, height];
        self.reallocate_compute_textures();
        self.needs_compute_update = true;
    }

    pub fn set_resolution_level(&mut self, level: u32) {
        let clamped = level.clamp(1, 9);
        if clamped == self.resolution_level {
            return;
        }
        self.resolution_level = clamped;
        self.reallocate_compute_textures();
        self.needs_compute_update = true;
        log::info!(
            "Resolution level {}: {}x{}",
            self.resolution_level,
            self.compute_width(),
            self.compute_height()
        );
    }

    fn compute_width(&self) -> u32 {
        let aspect = self.viewport_size[0] as f32 / self.viewport_size[1].max(1) as f32;
        ((self.compute_height() as f32 * aspect) as u32).max(1)
    }

    fn compute_height(&self) -> u32 {
        BASE_COMPUTE_HEIGHT * self.resolution_level
    }

    fn reallocate_compute_textures(&mut self) {
        let w = self.compute_width();
        let h = self.compute_height();
        let make = |label: &str| {
            self.device.create_texture(&wgpu::TextureDescriptor {
                label: Some(label),
                size: wgpu::Extent3d {
                    width: w,
                    height: h,
                    depth_or_array_layers: 1,
                },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: wgpu::TextureFormat::Rgba8Unorm,
                usage: wgpu::TextureUsages::STORAGE_BINDING
                    | wgpu::TextureUsages::TEXTURE_BINDING,
                view_formats: &[],
            })
        };
        self.compute_textures[0] = make("compute texture 0");
        self.compute_textures[1] = make("compute texture 1");
        self.compute_texture_views[0] =
            self.compute_textures[0].create_view(&Default::default());
        self.compute_texture_views[1] =
            self.compute_textures[1].create_view(&Default::default());
        self.display_texture_index = 0;
    }

    // ─── Uniform Helpers ─────────────────────────────────────────────────

    fn make_camera_uniforms(&self) -> CameraUniforms {
        let aspect = self.viewport_size[0] as f32 / self.viewport_size[1].max(1) as f32;
        let steps = if self.camera.is_moving || self.camera.is_dragging {
            INTERACTION_STEP_COUNT
        } else {
            DEFAULT_STEP_COUNT
        };
        let pos = self.camera.position();
        let right = self.camera.right();
        let up = self.camera.up();
        let fwd = self.camera.forward();
        CameraUniforms {
            cam_pos: pos.to_array(),
            _pad0: 0.0,
            cam_right: right.to_array(),
            _pad1: 0.0,
            cam_up: up.to_array(),
            _pad2: 0.0,
            cam_forward: fwd.to_array(),
            _pad3: 0.0,
            tan_half_fov: self.camera.tan_half_fov(),
            aspect,
            moving: if self.camera.is_dragging { 1 } else { 0 },
            step_count: steps,
        }
    }

    fn make_disk_uniforms(&self) -> DiskUniforms {
        let rs = SAG_A_RS as f32;
        DiskUniforms {
            disk_r1: rs * DISK_INNER_FACTOR,
            disk_r2: rs * DISK_OUTER_FACTOR,
            disk_num: 2.0,
            thickness: DISK_THICKNESS,
            disk_color: self.disk_base_color,
        }
    }

    fn make_objects_uniforms(&self) -> ObjectsUniforms {
        let mut uniforms = ObjectsUniforms::zeroed();
        let count = self.scene_objects.len().min(16);
        uniforms.num_objects = count as i32;
        for i in 0..count {
            let obj = &self.scene_objects[i];
            uniforms.obj_pos_radius[i] =
                [obj.position.x, obj.position.y, obj.position.z, obj.radius];
            uniforms.obj_color[i] = obj.color;
            uniforms.mass[i] = obj.mass;
        }
        uniforms
    }

    // ─── Grid Generation ─────────────────────────────────────────────────

    fn update_grid_vertices(&self) {
        let spacing: f32 = 1e10;
        let n = self.grid_size;
        let vertex_count = (n + 1) * (n + 1);
        let mut vertices: Vec<f32> = Vec::with_capacity(vertex_count * 3);

        for z in 0..=n {
            for x in 0..=n {
                let world_x = (x as f32 - n as f32 / 2.0) * spacing;
                let world_z = (z as f32 - n as f32 / 2.0) * spacing;
                let mut y: f32 = 0.0;

                for obj in &self.scene_objects {
                    let r_s = 2.0 * GRAVITATIONAL_CONSTANT * obj.mass as f64
                        / (SPEED_OF_LIGHT * SPEED_OF_LIGHT);
                    let dx = (world_x - obj.position.x) as f64;
                    let dz = (world_z - obj.position.z) as f64;
                    let dist = (dx * dx + dz * dz).sqrt();

                    if dist > r_s {
                        let delta_y = 2.0 * (r_s * (dist - r_s)).sqrt();
                        y += delta_y as f32 - 3e10;
                    } else {
                        y += 2.0 * (r_s * r_s).sqrt() as f32 - 3e10;
                    }
                }

                vertices.push(world_x);
                vertices.push(y);
                vertices.push(world_z);
            }
        }

        self.queue.write_buffer(
            &self.grid_vertex_buffer,
            0,
            bytemuck::cast_slice(&vertices),
        );
    }

    // ─── Frame Render ────────────────────────────────────────────────────

    pub fn render(&mut self) -> Result<(), wgpu::SurfaceError> {
        // 0) Update camera (for auto-rotation)
        self.camera.update();

        // 1) N-body gravity
        let gravity_active = self.gravity_sim.is_enabled;
        self.gravity_sim.step(&mut self.scene_objects, 1.0 / 60.0);

        // 2) Determine if compute needs to run
        if self.camera.has_changed {
            self.needs_compute_update = true;
            self.camera.clear_changed();
        }
        if gravity_active {
            self.needs_compute_update = true;
        }

        // 3) Regenerate grid if needed
        if self.needs_grid_update || gravity_active {
            self.update_grid_vertices();
            self.needs_grid_update = false;
        }

        // 4) Upload uniforms
        let cam_u = self.make_camera_uniforms();
        self.queue
            .write_buffer(&self.camera_uniform_buffer, 0, bytemuck::bytes_of(&cam_u));
        let disk_u = self.make_disk_uniforms();
        self.queue
            .write_buffer(&self.disk_uniform_buffer, 0, bytemuck::bytes_of(&disk_u));
        let obj_u = self.make_objects_uniforms();
        self.queue.write_buffer(
            &self.objects_uniform_buffer,
            0,
            bytemuck::bytes_of(&obj_u),
        );

        // Upload grid view-proj
        let aspect = self.viewport_size[0] as f32 / self.viewport_size[1].max(1) as f32;
        let view_proj = self.camera.view_proj(aspect);
        self.queue.write_buffer(
            &self.grid_uniform_buffer,
            0,
            bytemuck::bytes_of(&view_proj),
        );

        // 5) Dispatch compute into the back texture
        let write_index = 1 - self.display_texture_index;

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("frame encoder"),
            });

        if self.needs_compute_update {
            let compute_bind_group =
                self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                    label: Some("compute bind group"),
                    layout: &self.compute_bind_group_layout,
                    entries: &[
                        wgpu::BindGroupEntry {
                            binding: 0,
                            resource: wgpu::BindingResource::TextureView(
                                &self.compute_texture_views[write_index],
                            ),
                        },
                        wgpu::BindGroupEntry {
                            binding: 1,
                            resource: self.camera_uniform_buffer.as_entire_binding(),
                        },
                        wgpu::BindGroupEntry {
                            binding: 2,
                            resource: self.disk_uniform_buffer.as_entire_binding(),
                        },
                        wgpu::BindGroupEntry {
                            binding: 3,
                            resource: self.objects_uniform_buffer.as_entire_binding(),
                        },
                    ],
                });

            let mut cpass =
                encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("geodesic compute pass"),
                    timestamp_writes: None,
                });
            cpass.set_pipeline(&self.compute_pipeline);
            cpass.set_bind_group(0, &compute_bind_group, &[]);
            let groups_x =
                (self.compute_width() + WORKGROUP_SIZE - 1) / WORKGROUP_SIZE;
            let groups_y =
                (self.compute_height() + WORKGROUP_SIZE - 1) / WORKGROUP_SIZE;
            cpass.dispatch_workgroups(groups_x, groups_y, 1);
            drop(cpass);

            self.display_texture_index = write_index;
            self.needs_compute_update = false;
        }

        // 6) Render pass: fullscreen quad + grid overlay
        let surface_texture = self.surface.get_current_texture()?;
        let surface_view = surface_texture
            .texture
            .create_view(&Default::default());

        let quad_bind_group =
            self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("quad bind group"),
                layout: &self.quad_bind_group_layout,
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: wgpu::BindingResource::TextureView(
                            &self.compute_texture_views[self.display_texture_index],
                        ),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: wgpu::BindingResource::Sampler(&self.linear_sampler),
                    },
                ],
            });

        let grid_bind_group =
            self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("grid bind group"),
                layout: &self.grid_bind_group_layout,
                entries: &[wgpu::BindGroupEntry {
                    binding: 0,
                    resource: self.grid_uniform_buffer.as_entire_binding(),
                }],
            });

        {
            let mut rpass =
                encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: Some("render pass"),
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                        view: &surface_view,
                        resolve_target: None,
                        ops: wgpu::Operations {
                            load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                            store: wgpu::StoreOp::Store,
                        },
                    })],
                    depth_stencil_attachment: None,
                    timestamp_writes: None,
                    occlusion_query_set: None,
                });

            // Draw fullscreen quad
            rpass.set_pipeline(&self.quad_pipeline);
            rpass.set_bind_group(0, &quad_bind_group, &[]);
            rpass.set_vertex_buffer(0, self.quad_vertex_buffer.slice(..));
            rpass.draw(0..6, 0..1);

            // Draw grid overlay
            rpass.set_pipeline(&self.grid_pipeline);
            rpass.set_bind_group(0, &grid_bind_group, &[]);
            rpass.set_vertex_buffer(0, self.grid_vertex_buffer.slice(..));
            rpass.set_index_buffer(
                self.grid_index_buffer.slice(..),
                wgpu::IndexFormat::Uint32,
            );
            rpass.draw_indexed(0..self.grid_index_count, 0, 0..1);
        }

        self.queue.submit(std::iter::once(encoder.finish()));
        surface_texture.present();

        // Clear transient movement flag
        if self.camera.is_moving {
            self.needs_compute_update = true;
            self.camera.clear_moving();
        }

        Ok(())
    }
}
