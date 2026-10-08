-- BetterDelphiLSP im eingebauten LSP-Client von Neovim (ab 0.11).
-- In init.lua: require('betterdelphilsp') oder den Inhalt direkt einfügen.
-- BetterDelphiLSP.exe muss im PATH liegen, sonst cmd anpassen.

vim.filetype.add({
  extension = { pas = 'pascal', dpr = 'pascal', dpk = 'pascal', dfm = 'delphiform', fmx = 'delphiform' },
})

vim.lsp.config('betterdelphilsp', {
  cmd = { 'BetterDelphiLSP.exe', '--log-level', 'warning' },
  filetypes = { 'pascal', 'delphiform' },
  root_markers = { 'delphi-lsp.json', '*.dproj', '.git' },
  -- Entspricht den Schlüsseln aus delphi-lsp.json; die Datei im Projekt hat Vorrang.
  settings = { betterDelphiLsp = { language = 'de' } },
})

vim.lsp.enable('betterdelphilsp')
