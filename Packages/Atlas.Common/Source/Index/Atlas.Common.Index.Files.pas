unit Atlas.Common.Index.Files;

// Zuordnung von Dateien zu Units des Index (#500): die Unit einer Datei oder
// eine Unit, die sie per $I einbindet. Steht im Root des Features Index, weil
// ein Contract nur Typen und Interfaces enthält.

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
  mCandidate: TUnitIndex;
begin
  Result := (AIndex <> nil) and AIndex.FindFile(AFileName, AUnit);
  if Result or (AIndex = nil) then
  begin
    Exit;
  end;
  for mCandidate in AIndex.Units do
  begin
    if IndexText(AFileName, mCandidate.Includes) >= 0 then
    begin
      AUnit := mCandidate;
      Exit(True);
    end;
  end;
end;

end.
