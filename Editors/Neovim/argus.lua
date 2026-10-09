-- Argus im eingebauten LSP-Client von Neovim (ab 0.11).
-- In init.lua: require('argus') oder den Inhalt direkt einfügen.
-- ArgusServer.exe muss im PATH liegen, sonst cmd anpassen.

vim.filetype.add({
  extension = { pas = 'pascal', dpr = 'pascal', dpk = 'pascal', dfm = 'delphiform', fmx = 'delphiform' },
})

vim.lsp.config('argus', {
  cmd = { 'ArgusServer.exe', '--log-level', 'warning' },
  filetypes = { 'pascal', 'delphiform' },
  root_markers = { 'argus.json', '*.dproj', '.git' },
  -- Entspricht den Schlüsseln aus argus.json; die Datei im Projekt hat Vorrang.
  settings = { argus = { language = 'de' } },
})

vim.lsp.enable('argus')
