use rand::Rng;
use sdl2::event::Event;
use sdl2::keyboard::Keycode;
use sdl2::mouse::MouseButton;
use sdl2::pixels::Color;
use sdl2::rect::Rect;
use std::time::{Duration, Instant};

const WIDTH: usize = 180;
const HEIGHT: usize = 320;
const CELL_SIZE: u32 = 6;
const SCREEN_W: u32 = WIDTH as u32 * CELL_SIZE;
const SCREEN_H: u32 = HEIGHT as u32 * CELL_SIZE;

#[derive(Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
enum Cell {
    Empty = 0,
    Sand,
    Water,
    Stone,
    Fire,
    Oil,
    Lava,
    Steam,
    Wood,
    Ice,
    Acid,
    Smoke,
    Plant,
    Gunpowder,
    Salt,
}

impl Cell {
    fn color(&self) -> Color {
        match self {
            Cell::Empty => Color::RGB(10, 10, 15),
            Cell::Sand => Color::RGB(212, 165, 116),
            Cell::Water => Color::RGB(74, 144, 226),
            Cell::Stone => Color::RGB(102, 102, 119),
            Cell::Fire => Color::RGB(255, 96 + (rand::random::<u8>() % 60), 32),
            Cell::Oil => Color::RGB(42, 26, 10),
            Cell::Lava => Color::RGB(255, 68 + (rand::random::<u8>() % 40), 0),
            Cell::Steam => Color::RGB(200, 216, 232),
            Cell::Wood => Color::RGB(102, 68, 34),
            Cell::Ice => Color::RGB(170, 221, 255),
            Cell::Acid => Color::RGB(68, 238, 51),
            Cell::Smoke => Color::RGB(80, 85, 96),
            Cell::Plant => Color::RGB(51, 170, 34),
            Cell::Gunpowder => Color::RGB(68, 68, 68),
            Cell::Salt => Color::RGB(240, 240, 232),
        }
    }

    fn is_liquid(&self) -> bool {
        matches!(self, Cell::Water | Cell::Oil | Cell::Lava | Cell::Acid)
    }

    fn is_gas(&self) -> bool {
        matches!(self, Cell::Steam | Cell::Smoke | Cell::Fire)
    }

    fn density(&self) -> u8 {
        match self {
            Cell::Empty => 0,
            Cell::Steam => 1,
            Cell::Smoke => 2,
            Cell::Fire => 3,
            Cell::Oil => 4,
            Cell::Water => 5,
            Cell::Acid => 5,
            Cell::Salt => 6,
            Cell::Sand => 7,
            Cell::Gunpowder => 7,
            Cell::Ice => 5,
            Cell::Wood => 4,
            Cell::Plant => 4,
            Cell::Lava => 8,
            Cell::Stone => 10,
        }
    }
}

struct World {
    cells: Vec<Cell>,
    life: Vec<u8>,
    updated: Vec<bool>,
}

impl World {
    fn new() -> Self {
        let size = WIDTH * HEIGHT;
        Self {
            cells: vec![Cell::Empty; size],
            life: vec![0; size],
            updated: vec![false; size],
        }
    }

    fn idx(&self, x: i32, y: i32) -> Option<usize> {
        if x >= 0 && x < WIDTH as i32 && y >= 0 && y < HEIGHT as i32 {
            Some(y as usize * WIDTH + x as usize)
        } else {
            None
        }
    }

    fn get(&self, x: i32, y: i32) -> Cell {
        self.idx(x, y).map(|i| self.cells[i]).unwrap_or(Cell::Stone)
    }

    fn set(&mut self, x: i32, y: i32, cell: Cell, life: u8) {
        if let Some(i) = self.idx(x, y) {
            self.cells[i] = cell;
            self.life[i] = life;
            self.updated[i] = true;
        }
    }

    fn swap(&mut self, x1: i32, y1: i32, x2: i32, y2: i32) {
        if let (Some(i1), Some(i2)) = (self.idx(x1, y1), self.idx(x2, y2)) {
            if self.cells[i1] == self.cells[i2] {
                return;
            }
            self.cells.swap(i1, i2);
            self.life.swap(i1, i2);
            self.updated[i1] = true;
            self.updated[i2] = true;
        }
    }

    fn update(&mut self) {
        let mut rng = rand::thread_rng();
        self.updated.fill(false);

        let start_x = if rng.gen::<bool>() { 0 } else { WIDTH as i32 - 1 };
        let step_x = if start_x == 0 { 1 } else { -1 };

        for y in (0..HEIGHT as i32).rev() {
            let mut x = start_x;
            while x >= 0 && x < WIDTH as i32 {
                let i = (y as usize) * WIDTH + (x as usize);
                if self.updated[i] {
                    x += step_x;
                    continue;
                }

                let cell = self.cells[i];
                if cell == Cell::Empty || cell == Cell::Stone {
                    x += step_x;
                    continue;
                }

                let below = self.get(x, y + 1);

                match cell {
                    Cell::Sand | Cell::Gunpowder | Cell::Salt => {
                        if below == Cell::Empty {
                            self.swap(x, y, x, y + 1);
                        } else if below.is_liquid() && cell.density() > below.density() {
                            self.swap(x, y, x, y + 1);
                        } else if cell == Cell::Salt && below == Cell::Water && rng.gen::<f32>() < 0.1 {
                            self.set(x, y, Cell::Empty, 0);
                        } else {
                            let lb = self.get(x - 1, y + 1);
                            let rb = self.get(x + 1, y + 1);
                            let can_l = lb == Cell::Empty || (lb.is_liquid() && cell.density() > lb.density());
                            let can_r = rb == Cell::Empty || (rb.is_liquid() && cell.density() > rb.density());
                            if can_l && can_r {
                                self.swap(x, y, x + if rng.gen() { -1 } else { 1 }, y + 1);
                            } else if can_l {
                                self.swap(x, y, x - 1, y + 1);
                            } else if can_r {
                                self.swap(x, y, x + 1, y + 1);
                            }
                        }
                    }
                    Cell::Water | Cell::Oil | Cell::Acid => {
                        if below == Cell::Empty {
                            self.swap(x, y, x, y + 1);
                        } else if cell == Cell::Water && below == Cell::Fire {
                            self.set(x, y + 1, Cell::Steam, 60);
                            self.set(x, y, Cell::Empty, 0);
                        } else if cell == Cell::Water && below == Cell::Lava {
                            self.set(x, y + 1, Cell::Stone, 0);
                            self.set(x, y, Cell::Steam, 60);
                        } else if cell == Cell::Water && below == Cell::Oil {
                            self.swap(x, y, x, y + 1);
                        } else if cell == Cell::Oil {
                            for dx in -1..=1 {
                                let n = self.get(x + dx, y);
                                if (n == Cell::Fire || n == Cell::Lava) && rng.gen::<f32>() < 0.2 {
                                    self.set(x, y, Cell::Fire, 80);
                                    break;
                                }
                            }
                        } else if cell == Cell::Acid {
                            for dy in -1..=1 {
                                for dx in -1..=1 {
                                    let n = self.get(x + dx, y + dy);
                                    if n != Cell::Empty && n != Cell::Stone && n != Cell::Acid && n != Cell::Lava {
                                        if rng.gen::<f32>() < 0.03 {
                                            self.set(x + dx, y + dy, Cell::Empty, 0);
                                            if rng.gen::<f32>() < 0.2 {
                                                self.set(x, y, Cell::Smoke, 40);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if self.get(x, y) == cell {
                            let lb = self.get(x - 1, y + 1);
                            let rb = self.get(x + 1, y + 1);
                            if lb == Cell::Empty && rb == Cell::Empty {
                                self.swap(x, y, x + if rng.gen() { -1 } else { 1 }, y + 1);
                            } else if lb == Cell::Empty {
                                self.swap(x, y, x - 1, y + 1);
                            } else if rb == Cell::Empty {
                                self.swap(x, y, x + 1, y + 1);
                            } else {
                                let l = self.get(x - 1, y);
                                let r = self.get(x + 1, y);
                                if l == Cell::Empty && r == Cell::Empty {
                                    self.swap(x, y, x + if rng.gen() { -1 } else { 1 }, y);
                                } else if l == Cell::Empty {
                                    self.swap(x, y, x - 1, y);
                                } else if r == Cell::Empty {
                                    self.swap(x, y, x + 1, y);
                                }
                            }
                        }
                    }
                    Cell::Lava => {
                        for dy in -1..=1 {
                            for dx in -1..=1 {
                                let n = self.get(x + dx, y + dy);
                                if (n == Cell::Wood || n == Cell::Plant || n == Cell::Oil) && rng.gen::<f32>() < 0.06 {
                                    self.set(x + dx, y + dy, Cell::Fire, 70);
                                }
                                if n == Cell::Ice {
                                    self.set(x + dx, y + dy, Cell::Water, 0);
                                }
                                if n == Cell::Water {
                                    self.set(x + dx, y + dy, Cell::Steam, 50);
                                    if rng.gen::<f32>() < 0.15 {
                                        self.set(x, y, Cell::Stone, 0);
                                    }
                                }
                                if n == Cell::Gunpowder && rng.gen::<f32>() < 0.3 {
                                    self.explode(x + dx, y + dy, 5);
                                }
                            }
                        }
                        if below == Cell::Empty && rng.gen::<f32>() < 0.5 {
                            self.swap(x, y, x, y + 1);
                        } else if rng.gen::<f32>() < 0.15 {
                            let l = self.get(x - 1, y);
                            let r = self.get(x + 1, y);
                            if l == Cell::Empty {
                                self.swap(x, y, x - 1, y);
                            } else if r == Cell::Empty {
                                self.swap(x, y, x + 1, y);
                            }
                        }
                    }
                    Cell::Fire => {
                        let life = self.life[i].saturating_sub(1);
                        if life == 0 {
                            self.set(x, y, if rng.gen::<f32>() < 0.2 { Cell::Smoke } else { Cell::Empty }, 40);
                        } else {
                            self.life[i] = life;
                            for dx in -1..=1 {
                                let n = self.get(x + dx, y);
                                if n == Cell::Wood && rng.gen::<f32>() < 0.015 {
                                    self.set(x + dx, y, Cell::Fire, 100);
                                }
                                if n == Cell::Plant && rng.gen::<f32>() < 0.04 {
                                    self.set(x + dx, y, Cell::Fire, 40);
                                }
                                if n == Cell::Oil && rng.gen::<f32>() < 0.1 {
                                    self.set(x + dx, y, Cell::Fire, 80);
                                }
                                if n == Cell::Gunpowder && rng.gen::<f32>() < 0.2 {
                                    self.explode(x + dx, y, 5);
                                }
                                if n == Cell::Ice {
                                    self.set(x + dx, y, Cell::Water, 0);
                                }
                            }
                            if self.get(x, y - 1) == Cell::Empty && rng.gen::<f32>() < 0.5 {
                                self.swap(x, y, x, y - 1);
                            }
                        }
                    }
                    Cell::Steam | Cell::Smoke => {
                        let life = self.life[i].saturating_sub(1);
                        if life == 0 {
                            let new_cell = if cell == Cell::Steam && rng.gen::<f32>() < 0.3 {
                                Cell::Water
                            } else {
                                Cell::Empty
                            };
                            self.set(x, y, new_cell, 0);
                        } else {
                            self.life[i] = life;
                            if self.get(x, y - 1) == Cell::Empty && rng.gen::<f32>() < 0.6 {
                                self.swap(x, y, x, y - 1);
                            } else {
                                let dx = if rng.gen() { -1 } else { 1 };
                                if self.get(x + dx, y) == Cell::Empty {
                                    self.swap(x, y, x + dx, y);
                                }
                            }
                        }
                    }
                    Cell::Ice => {
                        for dx in -1..=1 {
                            let n = self.get(x + dx, y);
                            if n == Cell::Water && rng.gen::<f32>() < 0.005 {
                                self.set(x + dx, y, Cell::Ice, 0);
                            }
                            if (n == Cell::Fire || n == Cell::Lava) && rng.gen::<f32>() < 0.05 {
                                self.set(x, y, Cell::Water, 0);
                                break;
                            }
                        }
                    }
                    Cell::Wood | Cell::Plant => {
                        for dx in -1..=1 {
                            let n = self.get(x + dx, y);
                            if (n == Cell::Fire || n == Cell::Lava) && rng.gen::<f32>() < 0.01 {
                                self.set(x, y, Cell::Fire, if cell == Cell::Wood { 100 } else { 40 });
                                break;
                            }
                            if cell == Cell::Plant && n == Cell::Water && rng.gen::<f32>() < 0.01 {
                                self.set(x + dx, y, Cell::Plant, 0);
                            }
                        }
                    }
                    _ => {}
                }
                x += step_x;
            }
        }
    }

    fn explode(&mut self, cx: i32, cy: i32, r: i32) {
        let mut rng = rand::thread_rng();
        for dy in -r..=r {
            for dx in -r..=r {
                if dx * dx + dy * dy <= r * r {
                    let x = cx + dx;
                    let y = cy + dy;
                    if self.get(x, y) != Cell::Stone {
                        if dx * dx + dy * dy < (r * r) / 4 {
                            self.set(x, y, Cell::Fire, 50);
                        } else if rng.gen::<f32>() < 0.4 {
                            self.set(x, y, Cell::Smoke, 40);
                        } else {
                            self.set(x, y, Cell::Empty, 0);
                        }
                    }
                }
            }
        }
    }

    fn draw_brush(&mut self, cx: i32, cy: i32, cell: Cell, radius: i32) {
        let mut rng = rand::thread_rng();
        for dy in -radius..=radius {
            for dx in -radius..=radius {
                if dx * dx + dy * dy <= radius * radius {
                    let x = cx + dx;
                    let y = cy + dy;
                    if let Some(i) = self.idx(x, y) {
                        if cell == Cell::Empty || self.cells[i] == Cell::Empty {
                            let life = match cell {
                                Cell::Fire => 60 + rng.gen::<u8>() % 30,
                                Cell::Steam | Cell::Smoke => 50 + rng.gen::<u8>() % 30,
                                _ => 0,
                            };
                            self.cells[i] = cell;
                            self.life[i] = life;
                        }
                    }
                }
            }
        }
    }

    fn clear(&mut self) {
        self.cells.fill(Cell::Empty);
        self.life.fill(0);
    }
}

fn main() -> Result<(), String> {
    // Set SDL hints for Wayland
    sdl2::hint::set("SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR", "0");

    let sdl = sdl2::init()?;
    let video = sdl.video()?;

    // Use fixed screen size for mobile (1080x2400 typical)
    let screen_w: u32 = 1080;
    let screen_h: u32 = 2400;

    // Calculate cell size to fit screen
    let cell_w = screen_w / WIDTH as u32;
    let cell_h = screen_h / HEIGHT as u32;
    let cell_size = cell_w.min(cell_h).max(1);

    let window = video
        .window("Flick Sandbox", screen_w, screen_h)
        .resizable()
        .build()
        .map_err(|e| e.to_string())?;

    let mut canvas = window
        .into_canvas()
        .present_vsync()
        .build()
        .map_err(|e| e.to_string())?;

    // Present an initial frame immediately to commit the surface
    canvas.set_draw_color(Color::RGB(10, 10, 15));
    canvas.clear();
    canvas.present();

    eprintln!("Sandbox window created: {}x{}, cell_size={}", screen_w, screen_h, cell_size);

    let mut world = World::new();
    let mut event_pump = sdl.event_pump()?;
    let mut selected = Cell::Sand;
    let mut brush_size: i32 = 3;
    let mut mouse_down = false;

    let cells = [
        Cell::Sand,
        Cell::Water,
        Cell::Stone,
        Cell::Fire,
        Cell::Oil,
        Cell::Lava,
        Cell::Steam,
        Cell::Wood,
        Cell::Ice,
        Cell::Acid,
        Cell::Plant,
        Cell::Gunpowder,
        Cell::Salt,
        Cell::Smoke,
        Cell::Empty,
    ];

    let target_fps = 60;
    let frame_duration = Duration::from_secs_f64(1.0 / target_fps as f64);

    'running: loop {
        let frame_start = Instant::now();

        for event in event_pump.poll_iter() {
            match event {
                Event::Quit { .. } => break 'running,
                Event::KeyDown { keycode: Some(k), .. } => match k {
                    Keycode::Escape | Keycode::Q => break 'running,
                    Keycode::C => world.clear(),
                    Keycode::Num1 => selected = cells[0],
                    Keycode::Num2 => selected = cells[1],
                    Keycode::Num3 => selected = cells[2],
                    Keycode::Num4 => selected = cells[3],
                    Keycode::Num5 => selected = cells[4],
                    Keycode::Num6 => selected = cells[5],
                    Keycode::Num7 => selected = cells[6],
                    Keycode::Num8 => selected = cells[7],
                    Keycode::Num9 => selected = cells[8],
                    Keycode::Num0 => selected = cells[9],
                    Keycode::Minus => selected = cells[10],
                    Keycode::Equals => selected = cells[11],
                    Keycode::E => selected = Cell::Empty,
                    Keycode::Up => brush_size = (brush_size + 1).min(10),
                    Keycode::Down => brush_size = (brush_size - 1).max(1),
                    _ => {}
                },
                Event::MouseButtonDown { mouse_btn: MouseButton::Left, x, y, .. } => {
                    mouse_down = true;
                    let gx = x / cell_size as i32;
                    let gy = y / cell_size as i32;
                    world.draw_brush(gx, gy, selected, brush_size);
                }
                Event::MouseButtonUp { mouse_btn: MouseButton::Left, .. } => {
                    mouse_down = false;
                }
                Event::MouseMotion { x, y, .. } if mouse_down => {
                    let gx = x / cell_size as i32;
                    let gy = y / cell_size as i32;
                    world.draw_brush(gx, gy, selected, brush_size);
                }
                Event::FingerDown { x, y, .. } => {
                    mouse_down = true;
                    let gx = (x * screen_w as f32) as i32 / cell_size as i32;
                    let gy = (y * screen_h as f32) as i32 / cell_size as i32;
                    world.draw_brush(gx, gy, selected, brush_size);
                }
                Event::FingerUp { .. } => {
                    mouse_down = false;
                }
                Event::FingerMotion { x, y, .. } if mouse_down => {
                    let gx = (x * screen_w as f32) as i32 / cell_size as i32;
                    let gy = (y * screen_h as f32) as i32 / cell_size as i32;
                    world.draw_brush(gx, gy, selected, brush_size);
                }
                _ => {}
            }
        }

        // Update physics
        world.update();

        // Render
        canvas.set_draw_color(Color::RGB(10, 10, 15));
        canvas.clear();

        for y in 0..HEIGHT {
            for x in 0..WIDTH {
                let cell = world.cells[y * WIDTH + x];
                if cell != Cell::Empty {
                    canvas.set_draw_color(cell.color());
                    canvas.fill_rect(Rect::new(
                        (x as u32 * cell_size) as i32,
                        (y as u32 * cell_size) as i32,
                        cell_size,
                        cell_size,
                    ))?;
                }
            }
        }

        canvas.present();

        // Frame limiting
        let elapsed = frame_start.elapsed();
        if elapsed < frame_duration {
            std::thread::sleep(frame_duration - elapsed);
        }
    }

    Ok(())
}
