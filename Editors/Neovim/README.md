# Atlas in Neovim

## Installation

`AtlasServer.exe` muss im `PATH` liegen ([Server besorgen](../../docs/Installation.md#server-besorgen)).

`atlas.lua` nach `~/.config/nvim/lua/` (Windows: `%LOCALAPPDATA%\nvim\lua\`) kopieren und in `init.lua` `require('atlas')` eintragen. Benötigt Neovim 0.11 (`vim.lsp.config`). Befehle des Servers wie `atlas.server.rebuildIndex` lassen sich mit `:lua vim.lsp.buf.execute_command({ command = 'atlas.server.rebuildIndex' })` aufrufen.
