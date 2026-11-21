unit Atlas.Core.InlayHints.TestSupport;

// Gemeinsame Hilfen der Tests der Inlay-Hinweise (Speicher, Plan im Editor).

interface

uses
  Atlas.Core.InlayHints.Store;

/// <summary>Hinweis AName an Zeile ALine, Zeichen ACharacter.</summary>
function H(ALine, ACharacter: Integer; const AName: string): TAtlasInlayHint;

implementation

function H(ALine, ACharacter: Integer; const AName: string): TAtlasInlayHint;
begin
  Result := Default(TAtlasInlayHint);
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.Name := AName;
end;

end.
