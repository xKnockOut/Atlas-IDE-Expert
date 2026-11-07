unit Atlas.Core.Search.Scopes;

// Suchbereiche der Atlas-Suche (#877, #878), ohne VCL und Open Tools API:
// - Methode: Routine mit Rumpf am Cursor, vom Kopf (samt „class“) über die
//   lokalen Deklarationen bis zum end des Rumpfs. Die Routinen kommen aus den
//   Blockpaaren (Atlas.Core.Editor.Pairs, #653): ein begin- bzw. asm-Block,
//   dessen Besitzer procedure, function, constructor, destructor, operator
//   oder class ist. Bei verschachtelten Routinen liefert RoutinesAt alle
//   umgebenden, die innerste zuerst; Stufe 0 = innerste, höhere Stufen nach
//   außen (zu hohe Stufen bleiben bei der äußersten).
// - Unit: der ganze Text.
// - Auswahl: der übergebene Bereich.
// - Offene Dateien, Projekt, Projektgruppe (#893): je Datei der ganze Text;
//   welche Dateien dazugehören, bestimmt die IDE-Schicht (SpansFiles).
// Zeilen und Zeichen 0-basiert wie in Atlas.Core.Search.Matching.

interface

uses
  System.SysUtils,
  Atlas.Core.Search.Matching;

type
  TAtlasSearchRoutine = record
    Area: TAtlasSearchArea;
    /// <summary>Kopfzeile ab dem Schlüsselwort, ohne Leerraum am Rand (für die Anzeige).</summary>
    Caption: string;
  end;

  TAtlasSearchScopes = class
  public
    /// <summary>Alle Routinen mit Rumpf in AText, in der Reihenfolge ihres Endes.</summary>
    class function Routines(const AText: string): TArray<TAtlasSearchRoutine>; static;
    /// <summary>Routinen, die APos enthalten, die innerste zuerst.</summary>
    class function RoutinesAt(const AText: string; const APos: TAtlasSearchPos): TArray<TAtlasSearchRoutine>; static;
    /// <summary>Bereich zu AScope: Routine der Stufe ALevel am Cursor, ganzer Text oder ASelection. False, wenn es
    /// den Bereich nicht gibt (Cursor in keiner Routine, leere Auswahl).</summary>
    class function AreaFor(const AText: string; AScope: TAtlasSearchScope; const ACursor: TAtlasSearchPos;
      const ASelection: TAtlasSearchArea; ALevel: Integer; out AArea: TAtlasSearchArea): Boolean; static;
    /// <summary>Bereich über mehrere Dateien (offene Dateien, Projekt, Projektgruppe)?</summary>
    class function SpansFiles(AScope: TAtlasSearchScope): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Chars,
  Atlas.Text.Lines,
  Atlas.Core.Editor.Pairs;

/// <summary>Bezeichner ab ACharacter (0-basiert) in ALine, klein.</summary>
function WordAtPos(const ALine: string; ACharacter: Integer): string;
var
  mStop: Integer;
begin
  mStop := ACharacter + 1;
  while (mStop <= Length(ALine)) and TTextChars.IsIdentChar(ALine[mStop]) do
  begin
    Inc(mStop);
  end;
  Result := LowerCase(Copy(ALine, ACharacter + 1, mStop - ACharacter - 1));
end;

class function TAtlasSearchScopes.Routines(const AText: string): TArray<TAtlasSearchRoutine>;
var
  mLines: TArray<string>;
  mBlocks: TArray<TAtlasPairBlock>;
  mBlock: TAtlasPairBlock;
  mOwner, mOpener: string;
  mRoutine: TAtlasSearchRoutine;
begin
  Result := nil;
  mLines := TTextLines.SplitLines(AText);
  TAtlasPairs.Analyze(AText, mBlocks);
  for mBlock in mBlocks do
  begin
    if (mBlock.OwnerLine < 0) or (mBlock.OwnerLine > High(mLines)) or (mBlock.OpenLine > High(mLines)) then
    begin
      Continue;
    end;
    // Typdeklarationen (TFoo = class … end) haben sich selbst als Besitzer.
    if (mBlock.OwnerLine = mBlock.OpenLine) and (mBlock.OwnerCharacter = mBlock.OpenCharacter) then
    begin
      Continue;
    end;
    mOwner := WordAtPos(mLines[mBlock.OwnerLine], mBlock.OwnerCharacter);
    mOpener := WordAtPos(mLines[mBlock.OpenLine], mBlock.OpenCharacter);
    if not ((mOpener = 'begin') or (mOpener = 'asm')) then
    begin
      Continue;
    end;
    if not MatchStr(mOwner, ['procedure', 'function', 'constructor', 'destructor', 'operator', 'class']) then
    begin
      Continue;
    end;
    // Bis hinter das end des Rumpfs.
    mRoutine.Area := TAtlasSearchArea.Create(mBlock.OwnerLine, mBlock.OwnerCharacter, mBlock.CloseLine,
      mBlock.CloseCharacter + 3);
    mRoutine.Caption := Trim(Copy(mLines[mBlock.OwnerLine], mBlock.OwnerCharacter + 1, MaxInt));
    Result := Result + [mRoutine];
  end;
end;

class function TAtlasSearchScopes.RoutinesAt(const AText: string;
  const APos: TAtlasSearchPos): TArray<TAtlasSearchRoutine>;
var
  mAll: TArray<TAtlasSearchRoutine>;
  mRoutine, mSwap: TAtlasSearchRoutine;
  I, J: Integer;
begin
  Result := nil;
  mAll := Routines(AText);
  for mRoutine in mAll do
  begin
    if mRoutine.Area.Contains(APos) then
    begin
      Result := Result + [mRoutine];
    end;
  end;
  // Innerste zuerst: der späteste Anfang (umgebende Routinen beginnen vorher).
  for I := 1 to High(Result) do
  begin
    for J := I downto 1 do
    begin
      if TAtlasSearchPos.Compare(Result[J].Area.Start, Result[J - 1].Area.Start) > 0 then
      begin
        mSwap := Result[J];
        Result[J] := Result[J - 1];
        Result[J - 1] := mSwap;
      end;
    end;
  end;
end;

class function TAtlasSearchScopes.AreaFor(const AText: string; AScope: TAtlasSearchScope;
  const ACursor: TAtlasSearchPos; const ASelection: TAtlasSearchArea; ALevel: Integer;
  out AArea: TAtlasSearchArea): Boolean;
var
  mAround: TArray<TAtlasSearchRoutine>;
  mLevel: Integer;
begin
  AArea := TAtlasSearchArea.Create(0, 0, 0, 0);
  case AScope of
    TAtlasSearchScope.Method:
      begin
        mAround := RoutinesAt(AText, ACursor);
        if Length(mAround) = 0 then
        begin
          Exit(False);
        end;
        mLevel := ALevel;
        if mLevel < 0 then
        begin
          mLevel := 0;
        end;
        if mLevel > High(mAround) then
        begin
          mLevel := High(mAround);
        end;
        AArea := mAround[mLevel].Area;
      end;
    TAtlasSearchScope.Selection:
      begin
        if ASelection.IsEmpty then
        begin
          Exit(False);
        end;
        AArea := ASelection;
      end;
  else
    AArea := TAtlasSearchArea.Whole(TTextLines.SplitLines(AText));
  end;
  Result := True;
end;

class function TAtlasSearchScopes.SpansFiles(AScope: TAtlasSearchScope): Boolean;
begin
  Result := AScope in [TAtlasSearchScope.OpenFiles, TAtlasSearchScope.Project, TAtlasSearchScope.ProjectGroup];
end;

end.
