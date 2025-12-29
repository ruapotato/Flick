// Flick Sandbox - Enhanced Falling Sand Simulation
//
// CONTROLS:
// ========
// Numbers 1-0, -, =:  Select basic elements (Sand, Water, Stone, Fire, Oil, Lava, Steam, Wood, Ice, Acid, Plant, Gunpowder)
// Q, W:               Salt, Smoke
// A, S, D, F:         Snow, Ash, Metal, Glass
// G, H, J, K, L:      Gas, Poison Gas, Mud, Clay, Seed
// Z:                  Lightning
// E:                  Eraser
// R, T, X, V:         Quick select common elements (Sand, Fire, Water, Wood)
// C:                  Clear screen
// Up/Down arrows:     Increase/decrease brush size
// ESC:                Quit
//
// FEATURES:
// =========
// - 360x640 simulation grid (230,400 pixels) for detailed simulations
// - 25 different element types with realistic physics
// - Complex element interactions:
//   * Sand + Heat (Fire/Lava) = Glass
//   * Clay + Water = Mud
//   * Seed + Water/Mud = Plant (grows)
//   * Water + Fire = Steam
//   * Water + Lava = Stone + Steam
//   * Ice/Snow melts near heat
//   * Acid dissolves most materials (produces Poison Gas)
//   * Fire burns Wood/Oil/Plant (produces Ash/Smoke)
//   * Lightning ignites flammables, spreads through Metal
//   * Plants grow near Water and produce Seeds
//   * Poison Gas kills Plants
//   * Metal melts in Lava
//   * And many more!

use rand::Rng;
use sdl2::event::Event;
use sdl2::keyboard::Keycode;
use sdl2::mouse::MouseButton;
use sdl2::pixels::Color;
use sdl2::rect::Rect;
use std::time::{Duration, Instant};

const WIDTH: usize = 360;
const HEIGHT: usize = 640;
const CELL_SIZE: u32 = 3;
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
    Snow,
    Ash,
    Metal,
    Glass,
    Gas,
    PoisonGas,
    Mud,
    Clay,
    Seed,
    Lightning,
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
            Cell::Snow => Color::RGB(245, 250, 255),
            Cell::Ash => Color::RGB(60, 60, 64),
            Cell::Metal => Color::RGB(140, 145, 160),
            Cell::Glass => Color::RGB(180, 220, 240),
            Cell::Gas => Color::RGB(230, 240, 220),
            Cell::PoisonGas => Color::RGB(120, 190, 100),
            Cell::Mud => Color::RGB(90, 70, 50),
            Cell::Clay => Color::RGB(180, 140, 100),
            Cell::Seed => Color::RGB(100, 80, 40),
            Cell::Lightning => Color::RGB(200 + (rand::random::<u8>() % 55), 220 + (rand::random::<u8>() % 35), 255),
        }
    }

    fn is_liquid(&self) -> bool {
        matches!(self, Cell::Water | Cell::Oil | Cell::Lava | Cell::Acid | Cell::Mud)
    }

    fn is_gas(&self) -> bool {
        matches!(self, Cell::Steam | Cell::Smoke | Cell::Fire | Cell::Gas | Cell::PoisonGas)
    }

    fn density(&self) -> u8 {
        match self {
            Cell::Empty => 0,
            Cell::Steam => 1,
            Cell::Smoke => 2,
            Cell::Gas => 2,
            Cell::PoisonGas => 2,
            Cell::Fire => 3,
            Cell::Lightning => 1,
            Cell::Oil => 4,
            Cell::Water => 5,
            Cell::Acid => 5,
            Cell::Mud => 6,
            Cell::Salt => 6,
            Cell::Snow => 3,
            Cell::Ash => 4,
            Cell::Sand => 7,
            Cell::Gunpowder => 7,
            Cell::Clay => 7,
            Cell::Ice => 5,
            Cell::Wood => 4,
            Cell::Plant => 4,
            Cell::Seed => 6,
            Cell::Lava => 8,
            Cell::Glass => 8,
            Cell::Stone => 10,
            Cell::Metal => 11,
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
                    Cell::Sand | Cell::Gunpowder | Cell::Salt | Cell::Clay | Cell::Ash | Cell::Seed => {
                        // Special interactions
                        if cell == Cell::Sand {
                            for dy in -1..=1 {
                                for dx in -1..=1 {
                                    let n = self.get(x + dx, y + dy);
                                    if (n == Cell::Lava || n == Cell::Fire) && rng.gen::<f32>() < 0.02 {
                                        self.set(x, y, Cell::Glass, 0);
                                        break;
                                    }
                                }
                            }
                        }
                        if cell == Cell::Clay {
                            for dy in -1..=1 {
                                for dx in -1..=1 {
                                    let n = self.get(x + dx, y + dy);
                                    if n == Cell::Water && rng.gen::<f32>() < 0.01 {
                                        self.set(x, y, Cell::Mud, 0);
                                    }
                                }
                            }
                        }
                        if cell == Cell::Seed {
                            let below_cell = self.get(x, y + 1);
                            if (below_cell == Cell::Water || below_cell == Cell::Mud) && rng.gen::<f32>() < 0.005 {
                                self.set(x, y, Cell::Plant, 0);
                            }
                        }

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
                    Cell::Water | Cell::Oil | Cell::Acid | Cell::Mud => {
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
                                    // Acid dissolves most things except Stone, Glass, and itself
                                    if n != Cell::Empty && n != Cell::Stone && n != Cell::Acid && n != Cell::Lava && n != Cell::Glass {
                                        let dissolve_rate = if n == Cell::Metal { 0.01 } else { 0.03 };
                                        if rng.gen::<f32>() < dissolve_rate {
                                            self.set(x + dx, y + dy, Cell::Empty, 0);
                                            if rng.gen::<f32>() < 0.3 {
                                                self.set(x, y, Cell::PoisonGas, 50);
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
                                if n == Cell::Ice || n == Cell::Snow {
                                    self.set(x + dx, y + dy, Cell::Water, 0);
                                }
                                if n == Cell::Water {
                                    self.set(x + dx, y + dy, Cell::Steam, 50);
                                    if rng.gen::<f32>() < 0.15 {
                                        self.set(x, y, Cell::Stone, 0);
                                    }
                                }
                                if n == Cell::Sand && rng.gen::<f32>() < 0.05 {
                                    self.set(x + dx, y + dy, Cell::Glass, 0);
                                }
                                if n == Cell::Metal && rng.gen::<f32>() < 0.002 {
                                    self.set(x + dx, y + dy, Cell::Lava, 0);
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
                            let rand_val = rng.gen::<f32>();
                            if rand_val < 0.15 {
                                self.set(x, y, Cell::Smoke, 40);
                            } else if rand_val < 0.25 {
                                self.set(x, y, Cell::Ash, 0);
                            } else {
                                self.set(x, y, Cell::Empty, 0);
                            }
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
                                if n == Cell::Ice || n == Cell::Snow {
                                    self.set(x + dx, y, Cell::Water, 0);
                                }
                                if n == Cell::Gas && rng.gen::<f32>() < 0.3 {
                                    self.explode(x + dx, y, 3);
                                }
                            }
                            if self.get(x, y - 1) == Cell::Empty && rng.gen::<f32>() < 0.5 {
                                self.swap(x, y, x, y - 1);
                            }
                        }
                    }
                    Cell::Steam | Cell::Smoke | Cell::Gas | Cell::PoisonGas => {
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
                            if cell == Cell::PoisonGas {
                                // Poison gas kills plants
                                for dx in -1..=1 {
                                    if self.get(x + dx, y) == Cell::Plant && rng.gen::<f32>() < 0.05 {
                                        self.set(x + dx, y, Cell::Empty, 0);
                                    }
                                }
                            }
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
                            if cell == Cell::Plant {
                                if n == Cell::Water && rng.gen::<f32>() < 0.008 {
                                    self.set(x + dx, y, Cell::Plant, 0);
                                }
                                // Plants produce seeds occasionally
                                if n == Cell::Empty && rng.gen::<f32>() < 0.001 {
                                    self.set(x + dx, y, Cell::Seed, 0);
                                }
                            }
                        }
                    }
                    Cell::Snow => {
                        // Snow melts near heat
                        for dx in -1..=1 {
                            let n = self.get(x + dx, y);
                            if (n == Cell::Fire || n == Cell::Lava) && rng.gen::<f32>() < 0.1 {
                                self.set(x, y, Cell::Water, 0);
                                break;
                            }
                        }
                        // Snow falls like powder
                        if below == Cell::Empty {
                            self.swap(x, y, x, y + 1);
                        } else if below.is_liquid() && Cell::Snow.density() < below.density() {
                            if rng.gen::<f32>() < 0.3 {
                                self.swap(x, y, x, y + 1);
                            }
                        } else {
                            let lb = self.get(x - 1, y + 1);
                            let rb = self.get(x + 1, y + 1);
                            if lb == Cell::Empty && rb == Cell::Empty {
                                self.swap(x, y, x + if rng.gen() { -1 } else { 1 }, y + 1);
                            } else if lb == Cell::Empty {
                                self.swap(x, y, x - 1, y + 1);
                            } else if rb == Cell::Empty {
                                self.swap(x, y, x + 1, y + 1);
                            }
                        }
                    }
                    Cell::Lightning => {
                        let life = self.life[i].saturating_sub(1);
                        if life == 0 {
                            self.set(x, y, Cell::Empty, 0);
                        } else {
                            self.life[i] = life;
                            // Lightning spreads rapidly downward and ignites things
                            if self.get(x, y + 1) == Cell::Empty && rng.gen::<f32>() < 0.8 {
                                self.set(x, y + 1, Cell::Lightning, life.saturating_sub(2));
                            }
                            for dx in -1..=1 {
                                let n = self.get(x + dx, y);
                                if (n == Cell::Wood || n == Cell::Plant || n == Cell::Oil || n == Cell::Gunpowder) && rng.gen::<f32>() < 0.4 {
                                    self.set(x + dx, y, Cell::Fire, 80);
                                }
                                if n == Cell::Metal && rng.gen::<f32>() < 0.3 {
                                    self.set(x + dx, y, Cell::Lightning, life.saturating_sub(1));
                                }
                                if n == Cell::Water && rng.gen::<f32>() < 0.2 {
                                    self.set(x + dx, y, Cell::Steam, 40);
                                }
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
                                Cell::Steam | Cell::Smoke | Cell::Gas | Cell::PoisonGas => 50 + rng.gen::<u8>() % 30,
                                Cell::Lightning => 20 + rng.gen::<u8>() % 10,
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
        Cell::Sand,       // 1
        Cell::Water,      // 2
        Cell::Stone,      // 3
        Cell::Fire,       // 4
        Cell::Oil,        // 5
        Cell::Lava,       // 6
        Cell::Steam,      // 7
        Cell::Wood,       // 8
        Cell::Ice,        // 9
        Cell::Acid,       // 0
        Cell::Plant,      // -
        Cell::Gunpowder,  // =
        Cell::Salt,       // Q
        Cell::Smoke,      // W
        Cell::Snow,       // A
        Cell::Ash,        // S
        Cell::Metal,      // D
        Cell::Glass,      // F
        Cell::Gas,        // G
        Cell::PoisonGas,  // H
        Cell::Mud,        // J
        Cell::Clay,       // K
        Cell::Seed,       // L
        Cell::Lightning,  // Z
        Cell::Empty,      // E
    ];

    let target_fps = 60;
    let frame_duration = Duration::from_secs_f64(1.0 / target_fps as f64);

    'running: loop {
        let frame_start = Instant::now();

        for event in event_pump.poll_iter() {
            match event {
                Event::Quit { .. } => break 'running,
                Event::KeyDown { keycode: Some(k), .. } => match k {
                    Keycode::Escape => break 'running,
                    Keycode::C => world.clear(),
                    // Number keys
                    Keycode::Num1 => selected = cells[0],   // Sand
                    Keycode::Num2 => selected = cells[1],   // Water
                    Keycode::Num3 => selected = cells[2],   // Stone
                    Keycode::Num4 => selected = cells[3],   // Fire
                    Keycode::Num5 => selected = cells[4],   // Oil
                    Keycode::Num6 => selected = cells[5],   // Lava
                    Keycode::Num7 => selected = cells[6],   // Steam
                    Keycode::Num8 => selected = cells[7],   // Wood
                    Keycode::Num9 => selected = cells[8],   // Ice
                    Keycode::Num0 => selected = cells[9],   // Acid
                    Keycode::Minus => selected = cells[10], // Plant
                    Keycode::Equals => selected = cells[11], // Gunpowder
                    // Top row letters
                    Keycode::Q => selected = cells[12],     // Salt
                    Keycode::W => selected = cells[13],     // Smoke
                    Keycode::E => selected = Cell::Empty,   // Eraser
                    Keycode::R => selected = cells[0],      // Repeat Sand (common)
                    Keycode::T => selected = cells[3],      // Repeat Fire (common)
                    // Middle row letters
                    Keycode::A => selected = cells[14],     // Snow
                    Keycode::S => selected = cells[15],     // Ash
                    Keycode::D => selected = cells[16],     // Metal
                    Keycode::F => selected = cells[17],     // Glass
                    Keycode::G => selected = cells[18],     // Gas
                    Keycode::H => selected = cells[19],     // PoisonGas
                    Keycode::J => selected = cells[20],     // Mud
                    Keycode::K => selected = cells[21],     // Clay
                    Keycode::L => selected = cells[22],     // Seed
                    // Bottom row letters
                    Keycode::Z => selected = cells[23],     // Lightning
                    Keycode::X => selected = cells[1],      // Repeat Water (common)
                    Keycode::V => selected = cells[7],      // Repeat Wood (common)
                    // Brush size
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
