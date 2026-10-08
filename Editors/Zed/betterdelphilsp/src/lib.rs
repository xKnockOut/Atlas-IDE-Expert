// Startet BetterDelphiLSP aus dem PATH. Ein abweichender Pfad lässt sich in den
// Zed-Einstellungen unter lsp.betterdelphilsp.binary.path setzen.
use zed_extension_api::{self as zed, settings::LspSettings, LanguageServerId, Result};

struct BetterDelphiLsp;

impl zed::Extension for BetterDelphiLsp {
    fn new() -> Self {
        BetterDelphiLsp
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let binary = LspSettings::for_worktree(language_server_id.as_ref(), worktree)
            .ok()
            .and_then(|settings| settings.binary);
        let command = binary
            .as_ref()
            .and_then(|b| b.path.clone())
            .or_else(|| worktree.which("BetterDelphiLSP.exe"))
            .or_else(|| worktree.which("BetterDelphiLSP"))
            .ok_or("BetterDelphiLSP.exe nicht im PATH; lsp.betterdelphilsp.binary.path setzen")?;
        let args = binary.and_then(|b| b.arguments).unwrap_or_default();
        Ok(zed::Command { command, args, env: Default::default() })
    }
}

zed::register_extension!(BetterDelphiLsp);
