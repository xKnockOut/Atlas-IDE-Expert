unit Atlas.Common.Documents.Uris;

// Umwandlung zwischen file-URIs des LSP und Dateipfaden sowie eindeutige
// Schlüssel für Dokumente.
//   file:///c%3A/Projekt/A.pas  ↔  c:\Projekt\A.pas
//   file://server/share/A.pas   ↔  \\server\share\A.pas
//   file:///home/a/A.pas        ↔  /home/a/A.pas
// Wie VS Code wird beim Erzeugen der Laufwerksbuchstabe klein geschrieben
// und ":" kodiert; beim Lesen werden alle %XX-Folgen als UTF-8 entschlüsselt.
//
// Key liefert für jede Schreibweise derselben Datei denselben Schlüssel:
// Kodierung, Laufwerksbuchstabe, Groß-/Kleinschreibung, "\\?\"-Präfix,
// "." und ".." werden vereinheitlicht. Junctions und Symlinks löst ein
// optionaler Canonicalizer auf (unter Windows aus Atlas.Windows).
//
// Die Umwandlung selbst steht in Atlas.Text.Uris und gilt gleich im Plugin
// (ADR 0012); hier bleiben Key und SameFile.

interface

uses
  System.SysUtils;

type
  /// <summary>Löst einen Pfad auf seinen kanonischen Pfad auf (Symlinks, Junctions); sonst unverändert.</summary>
  TPathCanonicalizer = reference to function(const APath: string): string;

  TDocumentUris = class
  public
    /// <summary>Pfad zur URI; '' wenn es keine file-URI ist.</summary>
    class function ToPath(const AUri: string): string; static;
    class function FromPath(const APath: string): string; static;
    /// <summary>Vereinheitlicht Trenner, "\\?\"-Präfix, "." und ".."; Windows-Pfade mit "\".</summary>
    class function NormalizePath(const APath: string): string; static;
    /// <summary>Schlüssel für Wörterbücher: gleiche Datei, gleicher Schlüssel.
    /// Andere Schemata (untitled:) bleiben unverändert.</summary>
    class function Key(const AUri: string; const ACanonicalize: TPathCanonicalizer = nil): string; static;
    /// <summary>Gleiche Datei? Vergleicht die Schlüssel.</summary>
    class function SameFile(const AUriA, AUriB: string): Boolean; static;
  end;

implementation

uses
  Atlas.Text.Uris;

{ TDocumentUris }

class function TDocumentUris.ToPath(const AUri: string): string;
begin
  Result := TTextUris.ToPath(AUri);
end;

class function TDocumentUris.FromPath(const APath: string): string;
begin
  Result := TTextUris.FromPath(APath);
end;

class function TDocumentUris.NormalizePath(const APath: string): string;
begin
  Result := TTextUris.NormalizePath(APath);
end;

class function TDocumentUris.Key(const AUri: string; const ACanonicalize: TPathCanonicalizer): string;
var
  Path: string;
begin
  Path := ToPath(AUri);
  if Path = '' then
    Exit(AUri);
  Path := NormalizePath(Path);
  if Assigned(ACanonicalize) then
    Path := NormalizePath(ACanonicalize(Path));
  // Windows-Dateisysteme unterscheiden Groß-/Kleinschreibung nicht.
  if TTextUris.IsWindowsPath(Path) then
    Path := AnsiLowerCase(Path);
  Result := 'file:' + Path;
end;

class function TDocumentUris.SameFile(const AUriA, AUriB: string): Boolean;
begin
  Result := (ToPath(AUriA) <> '') and (Key(AUriA) = Key(AUriB));
end;

end.
