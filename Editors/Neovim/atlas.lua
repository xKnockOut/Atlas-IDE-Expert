-- Atlas im eingebauten LSP-Client von Neovim (ab 0.11).
-- In init.lua: require('atlas') oder den Inhalt direkt einfügen.
-- AtlasServer.exe muss im PATH liegen, sonst cmd anpassen.

vim.filetype.add({
  extension = { pas = 'pascal', dpr = 'pascal', dpk = 'pascal', dfm = 'delphiform', fmx = 'delphiform' },
})

vim.lsp.config('atlas', {
  cmd = { 'AtlasServer.exe', '--log-level', 'warning' },
  filetypes = { 'pascal', 'delphiform' },
  root_markers = { 'atlas.json', '*.dproj', '.git' },
  -- Entspricht den Schlüsseln aus atlas.json; die Datei im Projekt hat Vorrang.
  settings = { atlas = { language = 'de' } },
})

vim.lsp.enable('atlas')
