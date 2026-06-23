// Haven desktop entry point. `--headless` (or `--relay`) runs the invisible circle relay;
// otherwise the full GUI launches.
//
// Note: we intentionally do NOT set `windows_subsystem = "windows"` yet, so `--headless`
// can print to the console on Windows. The MSIX/GUI packaging step will attach-console
// conditionally instead (tracked in docs/WINDOWS-PORT.md).

fn main() {
    let headless = std::env::args().any(|a| a == "--headless" || a == "--relay");
    if headless {
        haven_desktop_lib::run_headless();
    } else {
        haven_desktop_lib::run();
    }
}
