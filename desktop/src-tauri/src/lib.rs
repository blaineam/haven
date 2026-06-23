//! Haven desktop — Tauri 2 GUI client plus a headless circle-relay mode, both built on the
//! shared Rust core (`haven_ffi`). The GUI is the WebView2 frontend in `../ui`; `--headless`
//! runs only the in-process relay/mailbox (the "invisible relay", like the Mac app).

mod callwire;
mod commands;
mod engine;
mod localmedia;
mod store;
mod wire;

use std::sync::Arc;

use anyhow::{anyhow, Result};
use haven_ffi::Account;
use sha2::{Digest, Sha256};
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::Manager;

use crate::engine::Engine;
use crate::store::Paths;

/// Load the master seed from the secure store, or mint + persist a new identity.
fn ensure_seed() -> Result<[u8; 32]> {
    if let Some(s) = store::load_seed()? {
        return Ok(s);
    }
    let acct: Arc<Account> = Account::generate();
    let seed: [u8; 32] = acct
        .secret_seed()
        .try_into()
        .map_err(|_| anyhow!("generated seed is not 32 bytes"))?;
    store::save_seed(&seed)?;
    Ok(seed)
}

/// Run the full GUI app.
pub fn run() {
    let paths = Paths::resolve().expect("resolve app data dir");
    let seed = ensure_seed().expect("load or create identity");
    let engine = Engine::new(paths, seed).expect("build engine");

    let setup_engine = engine.clone();
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_notification::init())
        .manage(engine)
        .setup(move |app| {
            let handle = app.handle().clone();
            setup_engine.set_app(handle.clone());
            let e = setup_engine.clone();
            tauri::async_runtime::spawn(async move {
                e.start().await;
            });

            // System tray: show the window, toggle the relay, or quit. The relay keeps running
            // when the window is closed, so the tray is the "invisible background relay" surface.
            let show = MenuItem::with_id(app, "show", "Open Haven", true, None::<&str>)?;
            let relay = MenuItem::with_id(app, "relay", "Host relay", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit Haven", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &relay, &quit])?;
            let tray_engine = setup_engine.clone();
            TrayIconBuilder::with_id("haven-tray")
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("Haven")
                .menu(&menu)
                .show_menu_on_left_click(true)
                .on_menu_event(move |app, event| match event.id().as_ref() {
                    "show" => {
                        if let Some(w) = app.get_webview_window("main") {
                            let _ = w.show();
                            let _ = w.set_focus();
                        }
                    }
                    "relay" => {
                        let e = tray_engine.clone();
                        tauri::async_runtime::spawn(async move {
                            let _ = e.start_hosting().await;
                        });
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .build(app)?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::bootstrap,
            commands::self_test,
            commands::get_profile,
            commands::set_profile,
            commands::circles,
            commands::create_circle,
            commands::rename_circle,
            commands::leave_circle,
            commands::add_to_circle,
            commands::feed,
            commands::post,
            commands::post_story,
            commands::comment,
            commands::react,
            commands::unreact,
            commands::edit_post,
            commands::unsend_post,
            commands::dm_threads,
            commands::start_dm,
            commands::messages,
            commands::send_dm,
            commands::connect_by_link,
            commands::pending,
            commands::approve,
            commands::dismiss,
            commands::contacts,
            commands::blocked,
            commands::block,
            commands::unblock,
            commands::relay_status,
            commands::start_hosting,
            commands::stop_hosting,
            commands::adopt_relay,
            commands::add_media,
            commands::media_data_url,
            commands::call_group_invite,
            commands::call_accept,
            commands::call_hangup,
            commands::call_signal,
            commands::my_node_hex,
            commands::s3_status,
            commands::s3_configure,
            commands::s3_clear,
            commands::set_foreground,
            commands::reset,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Haven");
}

/// Run only the circle relay/mailbox — no window. Mirrors the Mac app's invisible relay and the
/// standalone `haven-relay`: serves E2E-sealed blobs it can never read, identified by a stable
/// relay-specific node id derived from this device's seed.
pub fn run_headless() {
    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("tokio runtime");
    rt.block_on(async {
        let paths = Paths::resolve().expect("resolve app data dir");
        let seed = ensure_seed().expect("load or create identity");

        // Stable relay-specific seed, distinct from the messaging identity (per the core's contract).
        let mut hasher = Sha256::new();
        hasher.update(seed);
        hasher.update(b"haven-relay");
        let relay_seed: [u8; 32] = hasher.finalize().into();

        let dir = paths.relay_dir();
        std::fs::create_dir_all(&dir).ok();
        let handle = haven_ffi::RelayServerHandle::start(relay_seed.to_vec(), dir.to_string_lossy().to_string())
            .await
            .expect("start relay");
        let node_hex = handle.node_id_hex();

        let prefs = store::Prefs::load(&paths);
        let members: Vec<String> = prefs.contacts.iter().map(|c| c.id_hex.clone()).collect();
        let link = haven_ffi::make_relay_link(node_hex.clone(), members);

        println!("Haven relay running.");
        println!("  relay node id : {node_hex}");
        println!("  relay link    : {link}");
        println!("  storage       : {}", dir.display());
        println!("Share the relay link with your circle, then leave this running. Ctrl-C to stop.");

        let _ = tokio::signal::ctrl_c().await;
        println!("\nStopping relay.");
        drop(handle);
    });
}
