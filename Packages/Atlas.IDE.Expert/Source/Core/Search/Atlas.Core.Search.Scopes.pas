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
  end;

implementation

uses
  Atlas.Text.Chars,
  Atlas.Text.Lines,
  Atlas.Core.Editor.Pairs;

/// <summary>Bezeichner ab ACharacter (0-basiert) in ALine, klein.</summary>
function WordAtPos(const ALine: string; ACharacter: Integer): string;
var
  Stop: Integer;
begin
  Stop := ACharacter + 1;
  while (Stop <= Length(ALine)) and TTextChars.IsIdentChar(ALine[Stop]) do
    Inc(Stop);
  Result := LowerCase(Copy(ALine, ACharacter + 1, Stop - ACharacter - 1));
end;

class function TAtlasSearchScopes.Routines(const AText: string): TArray<TAtlasSearchRoutine>;
var
  Lines: TArray<string>;
  Blocks: TArray<TAtlasPairBlock>;
  Block: TAtlasPairBlock;
  Owner, Opener: string;
  Routine: TAtlasSearchRoutine;
begin
  Result := nil;
  Lines := TTextLines.SplitLines(AText);
  TAtlasPairs.Analyze(AText, Blocks);
  for Block in Blocks do
  begin
    if (Block.OwnerLine < 0) or (Block.OwnerLine > High(Lines)) or (Block.OpenLine > High(Lines)) then
      Continue;
    // Typdeklarationen (TFoo = class … end) haben sich selbst als Besitzer.
    if (Block.OwnerLine = Block.OpenLine) and (Block.OwnerCharacter = Block.OpenCharacter) then
      Continue;
    Owner := WordAtPos(Lines[Block.OwnerLine], Block.OwnerCharacter);
    Opener := WordAtPos(Lines[Block.OpenLine], Block.OpenCharacter);
    if not ((Opener = 'begin') or (Opener = 'asm')) then
      Continue;
    if not ((Owner = 'procedure') or (Owner = 'function') or (Owner = 'constructor') or (Owner = 'destructor') or
      (Owner = 'operator') or (Owner = 'class')) then
      Continue;
    // Bis hinter das end des Rumpfs.
    Routine.Area := TAtlasSearchArea.Create(Block.OwnerLine, Block.OwnerCharacter, Block.CloseLine,
      Block.CloseCharacter + 3);
    Routine.Caption := Trim(Copy(Lines[Block.OwnerLine], Block.OwnerCharacter + 1, MaxInt));
    Result := Result + [Routine];
  end;
end;

class function TAtlasSearchScopes.RoutinesAt(const AText: string;
  const APos: TAtlasSearchPos): TArray<TAtlasSearchRoutine>;
var
  All: TArray<TAtlasSearchRoutine>;
  Routine, Swap: TAtlasSearchRoutine;
  I, J: Integer;
begin
  Result := nil;
  All := Routines(AText);
  for Routine in All do
    if Routine.Area.Contains(APos) then
      Result := Result + [Routine];
  // Innerste zuerst: der späteste Anfang (umgebende Routinen beginnen vorher).
  for I := 1 to High(Result) do
    for J := I downto 1 do
      if TAtlasSearchPos.Compare(Result[J].Area.Start, Result[J - 1].Area.Start) > 0 then
      begin
        Swap := Result[J];
        Result[J] := Result[J - 1];
        Result[J - 1] := Swap;
      end;
end;

class function TAtlasSearchScopes.AreaFor(const AText: string; AScope: TAtlasSearchScope;
  const ACursor: TAtlasSearchPos; const ASelection: TAtlasSearchArea; ALevel: Integer;
  out AArea: TAtlasSearchArea): Boolean;
var
  Around: TArray<TAtlasSearchRoutine>;
  Level: Integer;
begin
  AArea := TAtlasSearchArea.Create(0, 0, 0, 0);
  case AScope of
    TAtlasSearchScope.Method:
      begin
        Around := RoutinesAt(AText, ACursor);
        if Length(Around) = 0 then
          Exit(False);
        Level := ALevel;
        if Level < 0 then
          Level := 0;
        if Level > High(Around) then
          Level := High(Around);
        AArea := Around[Level].Area;
      end;
    TAtlasSearchScope.Selection:
      begin
        if ASelection.IsEmpty then
          Exit(False);
        AArea := ASelection;
      end;
  else
    AArea := TAtlasSearchArea.Whole(TTextLines.SplitLines(AText));
  end;
  Result := True;
end;

end.
