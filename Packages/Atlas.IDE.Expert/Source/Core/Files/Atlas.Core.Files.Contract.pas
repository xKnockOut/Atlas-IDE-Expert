unit Atlas.Core.Files.Contract;

// Contract des Plugin-Features Files: Inhalt einer Textdatei samt Kodierung
// (#121). Andere Features (z. B. Undo) beschreiben damit Dateiinhalte, ohne
// das Root Atlas.Core.Files.TextFile zu importieren (Code-Review A-10).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils;

type
  TAtlasTextEncoding = (Utf8Bom, Utf8, Utf16LE, Utf16BE, Ansi);

  TAtlasTextFileContent = record
    Text: string;
    Encoding: TAtlasTextEncoding;
    /// <summary>Codepage bei Ansi; 0 = ANSI-Codepage des Systems.</summary>
    CodePage: Integer;
  end;

  EAtlasTextFileError = class(Exception);

implementation

end.
