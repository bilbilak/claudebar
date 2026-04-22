// claudebar-helper — shared CLI helper for non-GNOME Linux claudebar front-ends.
//
// Subcommands:
//   signin       Run the OAuth flow (PKCE + loopback) and store tokens in the
//                Secret Service (GNOME Keyring, KWallet, KeePassXC, etc.).
//   signout      Remove stored tokens.
//   status       Print a single JSON line with current usage. Front-ends poll this.
//   tray         Run as a StatusNotifierItem, rendering bars into the icon — this
//                is the cross-DE fallback for DEs without a native applet.

mod api;
mod auth;
mod icon;
mod oauth;
mod tray;

use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "claudebar-helper", version, about)]
struct Cli {
    #[command(subcommand)]
    cmd: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Sign in with Claude via OAuth PKCE. Stores tokens in the Secret Service.
    Signin,
    /// Remove stored tokens from the Secret Service.
    Signout,
    /// Print current usage as a single line of JSON on stdout.
    Status,
    /// Run as a cross-DE StatusNotifierItem tray icon that renders the bars.
    Tray {
        /// Poll interval in seconds (clamped to 60-3600).
        #[arg(long, default_value_t = 300)]
        interval: u64,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.cmd {
        Command::Signin => signin(),
        Command::Signout => signout(),
        Command::Status => status(),
        Command::Tray { interval } => tray::run(interval.clamp(60, 3600)),
    }
}

fn signin() -> Result<()> {
    let tokens = oauth::run_login_flow()?;
    auth::store(&tokens)?;
    println!("Signed in; tokens stored in the Secret Service.");
    Ok(())
}

fn signout() -> Result<()> {
    auth::clear()?;
    println!("Signed out; tokens removed from the Secret Service.");
    Ok(())
}

fn status() -> Result<()> {
    let snapshot = api::fetch_snapshot();
    let json = serde_json::to_string(&snapshot)?;
    println!("{}", json);
    Ok(())
}
