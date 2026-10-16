unit Atlas.Common.Index.Files;

// Zuordnung von Dateien zu Units des Index (#500): die Unit einer Datei oder
// eine Unit, die sie per $I einbindet. Steht im Root des Features Index, weil
// ein Contract nur Typen und Interfaces enthält (Code-Review A-10).

interface

uses
  Atlas.Common.Index.Contract;

type
  TIndexFiles = class
  public
    /// <summary>Unit zu AFileName: die Unit dieser Datei, sonst eine Unit, die sie per $I einbindet (#500).</summary>
    class function UnitOf(const AIndex: ISymbolIndex; const AFileName: string; out AUnit: TUnitIndex): Boolean;
      static;
  end;

implementation

uses
  System.StrUtils;

{ TIndexFiles }

class function TIndexFiles.UnitOf(const AIndex: ISymbolIndex; const AFileName: string; out AUnit: TUnitIndex): Boolean;
var
  Candidate: TUnitIndex;
begin
  Result := (AIndex <> nil) and AIndex.FindFile(AFileName, AUnit);
  if Result or (AIndex = nil) then
    Exit;
  for Candidate in AIndex.Units do
    if IndexText(AFileName, Candidate.Includes) >= 0 then
    begin
      AUnit := Candidate;
      Exit(True);
    end;
end;

end.
