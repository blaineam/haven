//! Render a relay link as a scannable QR code in the terminal, plus the prominent
//! "paste this into the Haven app" block. First-run UX: a user scans this with their
//! phone (or copies the text) and the circle is attached — no typing node ids.

use qrcode::{EcLevel, QrCode};

/// Print the relay link as a terminal QR (half-block rendering) and the copy/paste block.
/// Falls back to text-only if the payload is too large to encode.
pub fn print_link_qr(uri: &str) {
    println!("\n┌───────────────────────────────────────────────────────────────┐");
    println!("│  Add this relay to your circle:                               │");
    println!("│  Haven → Settings → Storage → \"Connect a relay\" → paste id    │");
    println!("└───────────────────────────────────────────────────────────────┘\n");

    match QrCode::with_error_correction_level(uri.as_bytes(), EcLevel::L) {
        Ok(code) => print_qr(&code),
        Err(_) => {
            // Payload too big for a QR (very large circles) — text fallback only.
            println!("  (link too long for a QR; copy the text below)\n");
        }
    }

    println!("  Or paste this relay link into the app:\n");
    println!("    {uri}\n");
}

/// Render a QR matrix to the terminal using Unicode half-block characters, so two QR
/// rows map to one text line (keeps the code roughly square in a normal terminal).
fn print_qr(code: &QrCode) {
    let w = code.width();
    let dark = |x: usize, y: usize| -> bool {
        // Out-of-range cells are treated as light (the quiet zone).
        if x >= w || y >= w {
            false
        } else {
            code[(x, y)] == qrcode::Color::Dark
        }
    };

    // A 2-module quiet zone on every side so scanners lock on reliably.
    let quiet = 2usize;
    let total = w + quiet * 2;

    // Each printed row covers two QR rows: top = upper half, bottom = lower half.
    let mut y = 0usize;
    while y < total {
        let mut line = String::from("    "); // left margin
        for x in 0..total {
            let top = dark(x.wrapping_sub(quiet), y.wrapping_sub(quiet));
            let bottom = dark(x.wrapping_sub(quiet), (y + 1).wrapping_sub(quiet));
            // Invert so a "dark" QR module prints as a filled block on a light terminal.
            line.push(match (top, bottom) {
                (true, true) => '█',
                (true, false) => '▀',
                (false, true) => '▄',
                (false, false) => ' ',
            });
        }
        println!("{line}");
        y += 2;
    }
    println!();
}
