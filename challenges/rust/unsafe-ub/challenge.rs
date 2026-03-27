use std::alloc::{alloc, dealloc, Layout};
use std::ptr;

// Unsafe Rust code with multiple undefined behavior issues.
// This module demonstrates common memory safety violations in unsafe code.

// BUG #1: Buffer overrun — inclusive range reads one past the end
pub fn fast_sum(slice: &[i32]) -> i64 {
    let ptr = slice.as_ptr();
    let len = slice.len();
    let mut sum: i64 = 0;

    unsafe {
        for i in 0..=len {  // BUG: 0..=len reads one past end — UB
            sum += *ptr.add(i) as i64;
        }
    }

    sum
}

// BUG #2: Creating a mutable reference from an immutable reference
pub fn force_mut<T>(reference: &T) -> &mut T {
    unsafe {  // BUG: creating &mut from & is instant UB
        &mut *(reference as *const T as *mut T)
    }
}

// BUG #3: Dynamic buffer without proper Drop implementation
struct FastBuffer {
    ptr: *mut u8,
    len: usize,
    cap: usize,
}

impl FastBuffer {
    pub fn new(capacity: usize) -> Option<Self> {
        let layout = Layout::array::<u8>(capacity).ok()?;
        unsafe {
            let ptr = alloc(layout);
            if ptr.is_null() {
                None
            } else {
                Some(FastBuffer {
                    ptr,
                    len: 0,
                    cap: capacity,
                })
            }
        }
    }

    pub fn push(&mut self, value: u8) -> Result<(), &'static str> {
        if self.len >= self.cap {
            Err("Buffer full")
        } else {
            unsafe {
                ptr::write(self.ptr.add(self.len), value);
            }
            self.len += 1;
            Ok(())
        }
    }

    pub fn as_slice(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.ptr, self.len) }
    }

    pub fn capacity(&self) -> usize {
        self.cap
    }

    pub fn len(&self) -> usize {
        self.len
    }
}
// BUG: no Drop impl — memory leak

fn main() {
    // Example 1: Buffer overrun
    let data = vec![1, 2, 3, 4, 5];
    let result = fast_sum(&data);
    println!("Sum: {}", result);

    // Example 2: Mutable reference from immutable
    let x = 42i32;
    let y = force_mut(&x);
    *y = 100;
    println!("x is now: {}", x);

    // Example 3: Dynamic buffer without cleanup
    if let Some(mut buf) = FastBuffer::new(10) {
        let _ = buf.push(65);
        let _ = buf.push(66);
        println!("Buffer: {:?}", buf.as_slice());
    }
}
