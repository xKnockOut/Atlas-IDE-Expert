unit Atlas.Core.Lsp.Uris;

// Dateiadressen des LSP und Windows-Pfade im Plugin (wie der Server, ADR 0012):
//   c:\x\a.pas            ↔  file:///c%3A/x/a.pas
//   \\server\share\a.pas  ↔  file://server/share/a.pas
// Andere Schemata ergeben ''. Eigene Unit, damit die Auswertung von
// WorkspaceEdits nicht die ganze Sitzung einbinden muss (Unit-Zyklus, #1450);
// TLspSession.PathToUri und UriToPath geben hierher weiter.

interface

type
  TLspUris = class
  public
    /// <summary>Pfad → file-URI; Laufwerksbuchstabe klein, ":" kodiert.</summary>
    class function FromPath(const APath: string): string; static;
    /// <summary>file-URI → Windows-Pfad mit "\"; '' für andere Schemata.</summary>
    class function ToPath(const AUri: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Uris;

{ TLspUris }

class function TLspUris.FromPath(const APath: string): string;
begin
  Result := TTextUris.FromPath(APath);
end;

class function TLspUris.ToPath(const AUri: string): string;
begin
  Result := StringReplace(TTextUris.ToPath(AUri), '/', '\', [rfReplaceAll]);
end;

end.
