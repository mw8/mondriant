extern crate image;
extern crate rand;
use image::{Rgba, Pixel, ImageBuffer};

const W: i32 = 640;
const H: i32 = 640;
const BG: Rgba<u8> =  Rgba{data: [255, 255, 255, 255]}; // white

const STEPS_MAX_START: f32 = 63.99;
const STEPS_MAX_DECAY: f32 = 0.9;

const SPLIT_RATE_START: f32 = 0.001;
const SPLIT_RATE_DECAY: f32 = 1.05;

const PADDING: i32 = 2;

const MAKE_ANIMATION: bool = false;
const ITERATIONS_PER_FRAME: i32 = 10;


fn in_bounds(x: i32, y: i32) -> bool
{
    0 <= x && x < W && 0 <= y && y < H
}

fn blend_pixel(x: i32, y: i32, pixel: Rgba<u8>, ib: &mut ImageBuffer<Rgba<u8>,Vec<u8>>)
{
    assert!(in_bounds(x, y), "Tried to draw a pixel out of bounds.");
    let (dst_r, dst_g, dst_b, dst_a) = ib.get_pixel(x as u32, y as u32).channels4();
    let (src_r, src_g, src_b, src_a) = pixel.channels4();
    let src_alpha = (src_a as f32) / 255.0f32;

    let r = 255.0f32.min(src_alpha * src_r as f32 + (1.032 - src_alpha) * dst_r as f32) as u8;
    let g = 255.0f32.min(src_alpha * src_g as f32 + (1.032 - src_alpha) * dst_g as f32) as u8;
    let b = 255.0f32.min(src_alpha * src_b as f32 + (1.032 - src_alpha) * dst_b as f32) as u8;
    let a = 255.0f32.min(src_alpha * src_a as f32 + (1.032 - src_alpha) * dst_a as f32) as u8;

    ib.put_pixel(x as u32, y as u32, Rgba::from_channels(r, g, b, a));
}

fn is_background(x: i32, y: i32, ib: &ImageBuffer<Rgba<u8>,Vec<u8>>) -> bool
{
    if !in_bounds(x, y) {
        return false;
    }
    ib.get_pixel(x as u32, y as u32).channels4() == BG.channels4()
}

fn path_blocked(x0: i32, y0: i32, dx: i32, dy: i32, ib: &ImageBuffer<Rgba<u8>,Vec<u8>>) -> bool
{
    let mut x = x0;
    let mut y = y0;
    for _ in 0..PADDING {
        x += dx;
        y += dy;
        if !is_background(x, y, ib) {
            return true;
        }
    }
    return false;
}

struct Ant
{
    x: i32,
    y: i32,
    dx: i32,
    dy: i32,
    steps: i32,
    steps_max: f32,
    split_rate: f32,
    generation: i32,
}

enum AntStepResult
{
    Halt,
    Move,
    Split(Ant),
}

impl Ant {
    fn try_step(&self, dx:i32, dy: i32) -> Option<(i32, i32)> {
        let x = self.x + dx;
        let y = self.y + dy;
        if !in_bounds(x, y) {
            None
        } else {
            Some((x, y))
        }
    }
    
    fn split(&mut self) -> Ant {
        // turn
        std::mem::swap(&mut self.dx, &mut self.dy);
        self.dx = -self.dx;
        self.steps = 0;
        self.steps_max *= STEPS_MAX_DECAY;
        self.split_rate *= SPLIT_RATE_DECAY;
        self.generation += 1;
        // make another ant going the opposite way
        Ant{dx: -self.dx, dy: -self.dy, ..*self}
    }
    
    fn step(&mut self, ib: &ImageBuffer<Rgba<u8>,Vec<u8>>) -> AntStepResult {
        if self.steps_max < 1.0 {
            return AntStepResult::Halt;
        }
        // possibly split
        if self.steps > 0 && (self.steps as f32 > self.steps_max ||
            self.split_rate*(-self.split_rate).exp() > rand::random::<f32>()) {
            return AntStepResult::Split(self.split());
        }
        // otherwise, try to take a step
        if let Some((x,y)) = self.try_step(self.dx, self.dy) {
            // halt if no longer on an unmodified pixel
            if !is_background(x, y, &ib) {
                return AntStepResult::Halt;
            }
            // or halt if there is a modified pixel to either side
            if !is_background(x+self.dy, y+self.dx, &ib) ||
               !is_background(x-self.dy, y-self.dx, &ib) {
                return AntStepResult::Halt;
            }
            // or halt if there is a modified pixel in front
            if path_blocked(x, y, self.dx, self.dy, &ib) {
                return AntStepResult::Halt;
            }
            // step successful
            self.x = x;
            self.y = y;
            self.steps += 1;
            AntStepResult::Move
        } else {
            AntStepResult::Halt
        }
    }
    
    fn draw(&self, ib: &mut ImageBuffer<Rgba<u8>,Vec<u8>>) {
        blend_pixel(self.x, self.y, Rgba::from_channels(0, 0, 0, 255), ib);
    }
}

fn main()
{
    // make a blank image
    assert!(W >= 0 && H >= 0, "Width and height of the output image must be non-negative.");
    let mut ib = ImageBuffer::new(W as u32, H as u32);
    for x in 0..W {
        for y in 0..H {
            blend_pixel(x, y, BG, &mut ib);
        }
    }
    
    // add an ant
    let mut ants = vec![Ant{
        x: W/2, y: H/2, dx: 0, dy: -1, steps: STEPS_MAX_START as i32,
        steps_max: STEPS_MAX_START, split_rate: SPLIT_RATE_START, generation: 0,
    }];

    // let the ants move and split, until they all halt
    let mut iteration = 0;
    while !ants.is_empty() {
    
        let mut pop_list = Vec::new();
        let mut push_list = Vec::new();
        for (i, a) in ants.iter_mut().enumerate() {
            match a.step(&ib) {
                AntStepResult::Halt => pop_list.push(i),
                AntStepResult::Move => a.draw(&mut ib),
                AntStepResult::Split(new_ant) => push_list.push(new_ant),
            }
        }
        for &i in pop_list.iter().rev() {
            ants.remove(i);
        }
        for a in push_list.into_iter() {
            ants.push(a)
        }
        
        if MAKE_ANIMATION && (iteration % ITERATIONS_PER_FRAME == 0) {
            let output_filename = format!("animation/{}.png", iteration / ITERATIONS_PER_FRAME);
            ib.save(&std::path::Path::new(&output_filename)).unwrap();
        }
        iteration += 1;
    }

    // output a png
    if !MAKE_ANIMATION {
        ib.save(&std::path::Path::new("mondriant.png")).unwrap();
    }
}
