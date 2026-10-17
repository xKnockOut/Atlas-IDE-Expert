unit Atlas.Core.Editor.LineChanges;

// Änderungsmarken und Zeilenhistorie (#507), ohne VCL, OTA und Prozess:
// - Compute vergleicht den Stand im Repository (HEAD) mit dem Puffer
//   zeilenweise (TTextDiff) und liefert die Blöcke: Added (nur neue Zeilen),
//   Deleted (nur alte Zeilen, Marke zwischen zwei Zeilen) und Modified.
// - MarkAt sagt, wie eine Pufferzeile in der Rinne aussieht; DeletedAt, ob
//   über ihr (bzw. unter der letzten Zeile) etwas gelöscht wurde.
// - Next findet reihum die nächste bzw. vorige Änderung.
// - Revert baut die Textänderung, die einen Block auf den alten Stand bringt
//   (als ein Rückgängig-Schritt über die Arbeitsbereich-Änderungen, #397).
// - BlameLine ordnet eine Pufferzeile der Zeile der Datei auf der Platte zu
//   (blame liest die Platte; ungespeicherte Zeilen sind „noch nicht
//   übernommen“), Age rechnet „vor 3 Tagen“ aus.
// Zeilen sind 0-basiert.

interface

uses
  System.SysUtils,
  Atlas.Text.Diff;

type
{$SCOPEDENUMS ON}
  TAtlasLineChangeKind = (Added, Modified, Deleted);
  TAtlasLineMark = (None, Added, Modified);
  TAtlasAgeUnit = (JustNow, Minutes, Hours, Yesterday, Days, Months, Years);
{$SCOPEDENUMS OFF}

  TAtlasLineChange = record
    Kind: TAtlasLineChangeKind;
    /// <summary>Erste Zeile im Puffer; bei Deleted die Zeile, vor der gelöscht wurde (am Ende = Zeilenzahl).</summary>
    Line: Integer;
    /// <summary>Zeilen im Puffer; bei Deleted 0.</summary>
    Count: Integer;
    /// <summary>Erste Zeile im Stand des Repositorys.</summary>
    OldLine: Integer;
    /// <summary>Alter Stand des Blocks; bei Added leer.</summary>
    OldLines: TArray<string>;
  end;

  TAtlasLineChangeList = TArray<TAtlasLineChange>;

  /// <summary>Textänderung für Revert (0-basiert, Ende ausschließlich).</summary>
  TAtlasLineEdit = record
    StartLine: Integer;
    StartCharacter: Integer;
    EndLine: Integer;
    EndCharacter: Integer;
    NewText: string;
  end;

  TAtlasAge = record
    Unit_: TAtlasAgeUnit;
    Count: Integer;
  end;

  TAtlasLineChanges = class
  public
    /// <summary>Blöcke von AOld (HEAD) nach ANew (Puffer), aufsteigend.</summary>
    class function Compute(const AOld, ANew: TArray<string>): TAtlasLineChangeList; static;
    /// <summary>Marke der Pufferzeile ALine; AIndex ist der Block (-1 ohne).</summary>
    class function MarkAt(const AChanges: TAtlasLineChangeList; ALine: Integer; out AIndex: Integer): TAtlasLineMark;
      static;
    /// <summary>Block, der über ALine gelöscht wurde; bei der letzten Zeile (ALine = ALineCount - 1) auch einer am
    /// Ende. -1 ohne.</summary>
    class function DeletedAt(const AChanges: TAtlasLineChangeList; ALine, ALineCount: Integer): Integer; static;
    /// <summary>Block an ALine: Marke oder Löschung darüber bzw. am Ende (für Klick und Zurücksetzen).</summary>
    class function ChangeAt(const AChanges: TAtlasLineChangeList; ALine, ALineCount: Integer): Integer; static;
    /// <summary>Erste Zeile der nächsten (AForward) bzw. vorigen Änderung nach bzw. vor ALine, reihum; False ohne
    /// Änderungen.</summary>
    class function Next(const AChanges: TAtlasLineChangeList; ALine, ALineCount: Integer; AForward: Boolean;
      out ATarget: Integer): Boolean; static;
    /// <summary>Textänderung, die AChange in ALines (Puffer) auf den alten Stand bringt; ALineBreak trennt die
    /// eingefügten Zeilen.</summary>
    class function Revert(const AChange: TAtlasLineChange; const ALines: TArray<string>;
      const ALineBreak: string): TAtlasLineEdit; static;
    /// <summary>Zeile der Datei auf der Platte zur Pufferzeile ABufferLine; -1, wenn sie seit dem Speichern neu
    /// oder geändert ist. ADisk und ABuffer sind die Zeilen beider Stände.</summary>
    class function BlameLine(const ADisk, ABuffer: TArray<string>; ABufferLine: Integer): Integer; overload; static;
    /// <summary>Wie oben mit vorher berechneten Blöcken von der Platte zum Puffer.</summary>
    class function BlameLine(const AHunks: TArray<TTextLineHunk>; ABufferLine: Integer): Integer; overload; static;
    /// <summary>Abstand von ADate zu ANow (beide UTC) für „vor …“.</summary>
    class function Age(ANow, ADate: TDateTime): TAtlasAge; static;
  end;

implementation

uses
  System.Math,
  System.DateUtils;

class function TAtlasLineChanges.Compute(const AOld, ANew: TArray<string>): TAtlasLineChangeList;
var
  Hunk: TTextLineHunk;
  Change: TAtlasLineChange;
begin
  Result := nil;
  for Hunk in TTextDiff.Hunks(AOld, ANew) do
  begin
    Change := Default(TAtlasLineChange);
    Change.Line := Hunk.NewStart;
    Change.Count := Hunk.NewCount;
    Change.OldLine := Hunk.OldStart;
    Change.OldLines := Copy(AOld, Hunk.OldStart, Hunk.OldCount);
    if Hunk.OldCount = 0 then
      Change.Kind := TAtlasLineChangeKind.Added
    else if Hunk.NewCount = 0 then
      Change.Kind := TAtlasLineChangeKind.Deleted
    else
      Change.Kind := TAtlasLineChangeKind.Modified;
    Result := Result + [Change];
  end;
end;

class function TAtlasLineChanges.MarkAt(const AChanges: TAtlasLineChangeList; ALine: Integer;
  out AIndex: Integer): TAtlasLineMark;
var
  Index: Integer;
begin
  AIndex := -1;
  Result := TAtlasLineMark.None;
  for Index := 0 to High(AChanges) do
  begin
    if AChanges[Index].Line > ALine then
      Break;
    if (AChanges[Index].Kind <> TAtlasLineChangeKind.Deleted) and
      (ALine < AChanges[Index].Line + AChanges[Index].Count) then
    begin
      AIndex := Index;
      if AChanges[Index].Kind = TAtlasLineChangeKind.Added then
        Result := TAtlasLineMark.Added
      else
        Result := TAtlasLineMark.Modified;
      Exit;
    end;
  end;
end;

class function TAtlasLineChanges.DeletedAt(const AChanges: TAtlasLineChangeList; ALine, ALineCount: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(AChanges) do
    if (AChanges[Index].Kind = TAtlasLineChangeKind.Deleted) and ((AChanges[Index].Line = ALine) or
      ((ALine = ALineCount - 1) and (AChanges[Index].Line >= ALineCount))) then
      Exit(Index);
  Result := -1;
end;

class function TAtlasLineChanges.ChangeAt(const AChanges: TAtlasLineChangeList; ALine, ALineCount: Integer): Integer;
begin
  MarkAt(AChanges, ALine, Result);
  if Result < 0 then
    Result := DeletedAt(AChanges, ALine, ALineCount);
end;

class function TAtlasLineChanges.Next(const AChanges: TAtlasLineChangeList; ALine, ALineCount: Integer;
  AForward: Boolean; out ATarget: Integer): Boolean;
var
  Index: Integer;

  function StartOf(AIndex: Integer): Integer;
  begin
    Result := AChanges[AIndex].Line;
    // Löschung am Ende: auf die letzte Zeile.
    if ALineCount > 0 then
      Result := Min(Result, ALineCount - 1);
  end;

  function Contains(AIndex: Integer): Boolean;
  begin
    Result := (ALine >= StartOf(AIndex)) and (ALine < StartOf(AIndex) + Max(1, AChanges[AIndex].Count));
  end;

begin
  ATarget := ALine;
  Result := Length(AChanges) > 0;
  if not Result then
    Exit;
  if AForward then
  begin
    for Index := 0 to High(AChanges) do
      if (StartOf(Index) > ALine) and not Contains(Index) then
      begin
        ATarget := StartOf(Index);
        Exit;
      end;
    ATarget := StartOf(0);
  end
  else
  begin
    for Index := High(AChanges) downto 0 do
      if (StartOf(Index) < ALine) and not Contains(Index) then
      begin
        ATarget := StartOf(Index);
        Exit;
      end;
    ATarget := StartOf(High(AChanges));
  end;
end;

class function TAtlasLineChanges.Revert(const AChange: TAtlasLineChange; const ALines: TArray<string>;
  const ALineBreak: string): TAtlasLineEdit;
var
  Old: string;
  Last: Integer;
begin
  Result := Default(TAtlasLineEdit);
  Old := string.Join(ALineBreak, AChange.OldLines);
  Last := AChange.Line + AChange.Count;
  if AChange.Kind = TAtlasLineChangeKind.Deleted then
  begin
    if AChange.Line < Length(ALines) then
    begin
      // Vor der Zeile einfügen.
      Result.StartLine := AChange.Line;
      Result.EndLine := AChange.Line;
      Result.NewText := Old + ALineBreak;
    end
    else
    begin
      // Am Ende: hinter der letzten Zeile.
      Result.StartLine := Max(0, High(ALines));
      if Length(ALines) > 0 then
        Result.StartCharacter := Length(ALines[High(ALines)]);
      Result.EndLine := Result.StartLine;
      Result.EndCharacter := Result.StartCharacter;
      Result.NewText := ALineBreak + Old;
    end;
    Exit;
  end;
  if Last < Length(ALines) then
  begin
    // Ganze Zeilen samt Umbruch ersetzen.
    Result.StartLine := AChange.Line;
    Result.EndLine := Last;
    Result.NewText := Old;
    if AChange.Kind = TAtlasLineChangeKind.Modified then
      Result.NewText := Old + ALineBreak;
    Exit;
  end;
  // Block bis zum Ende des Puffers.
  Result.EndLine := Max(0, High(ALines));
  if Length(ALines) > 0 then
    Result.EndCharacter := Length(ALines[High(ALines)]);
  if (AChange.Kind = TAtlasLineChangeKind.Added) and (AChange.Line > 0) then
  begin
    // Neue Zeilen am Ende samt dem Umbruch davor entfernen.
    Result.StartLine := AChange.Line - 1;
    Result.StartCharacter := Length(ALines[AChange.Line - 1]);
    Result.NewText := '';
  end
  else
  begin
    Result.StartLine := AChange.Line;
    Result.NewText := Old;
  end;
end;

class function TAtlasLineChanges.BlameLine(const AHunks: TArray<TTextLineHunk>; ABufferLine: Integer): Integer;
var
  Hunk: TTextLineHunk;
  Shift: Integer;
begin
  Shift := 0;
  for Hunk in AHunks do
  begin
    if ABufferLine < Hunk.NewStart then
      Break;
    if ABufferLine < Hunk.NewStart + Hunk.NewCount then
      Exit(-1);
    Shift := Hunk.OldCount - Hunk.NewCount + Shift;
  end;
  Result := ABufferLine + Shift;
end;

class function TAtlasLineChanges.BlameLine(const ADisk, ABuffer: TArray<string>; ABufferLine: Integer): Integer;
begin
  Result := BlameLine(TTextDiff.Hunks(ADisk, ABuffer), ABufferLine);
end;

class function TAtlasLineChanges.Age(ANow, ADate: TDateTime): TAtlasAge;
var
  Minutes: Int64;
begin
  Result.Count := 0;
  Minutes := Max(0, MinutesBetween(ANow, ADate));
  if ANow < ADate then
    Minutes := 0;
  if Minutes < 1 then
    Result.Unit_ := TAtlasAgeUnit.JustNow
  else if Minutes < 60 then
  begin
    Result.Unit_ := TAtlasAgeUnit.Minutes;
    Result.Count := Integer(Minutes);
  end
  else if Minutes < 24 * 60 then
  begin
    Result.Unit_ := TAtlasAgeUnit.Hours;
    Result.Count := Integer(Minutes div 60);
  end
  else if Minutes < 2 * 24 * 60 then
    Result.Unit_ := TAtlasAgeUnit.Yesterday
  else if Minutes < 30 * 24 * 60 then
  begin
    Result.Unit_ := TAtlasAgeUnit.Days;
    Result.Count := Integer(Minutes div (24 * 60));
  end
  else if Minutes < 365 * 24 * 60 then
  begin
    Result.Unit_ := TAtlasAgeUnit.Months;
    Result.Count := Integer(Minutes div (30 * 24 * 60));
  end
  else
  begin
    Result.Unit_ := TAtlasAgeUnit.Years;
    Result.Count := Integer(Minutes div (365 * 24 * 60));
  end;
end;

end.
