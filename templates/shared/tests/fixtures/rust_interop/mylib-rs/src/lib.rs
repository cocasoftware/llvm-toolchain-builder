/// Add two i32 values — exported as a C-compatible function.
#[no_mangle]
pub extern "C" fn rust_add(a: i32, b: i32) -> i32 {
    a + b
}

/// Return a greeting string length (demonstrates Rust std usage).
#[no_mangle]
pub extern "C" fn rust_greeting_len() -> usize {
    let msg = String::from("Hello from Rust!");
    msg.len()
}
