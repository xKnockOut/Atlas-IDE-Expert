# BetterDelphiLSP in Neovim

`betterdelphilsp.lua` nach `~/.config/nvim/lua/` (Windows: `%LOCALAPPDATA%\nvim\lua\`) kopieren und in `init.lua` `require('betterdelphilsp')` eintragen. Benötigt Neovim 0.11 (`vim.lsp.config`). Befehle des Servers wie `betterdelphilsp.rebuildIndex` lassen sich mit `:lua vim.lsp.buf.execute_command({ command = 'betterdelphilsp.rebuildIndex' })` aufrufen.
