# Argus in Neovim

`argus.lua` nach `~/.config/nvim/lua/` (Windows: `%LOCALAPPDATA%\nvim\lua\`) kopieren und in `init.lua` `require('argus')` eintragen. Benötigt Neovim 0.11 (`vim.lsp.config`). Befehle des Servers wie `argus.server.rebuildIndex` lassen sich mit `:lua vim.lsp.buf.execute_command({ command = 'argus.server.rebuildIndex' })` aufrufen.
