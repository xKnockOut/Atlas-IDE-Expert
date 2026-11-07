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
  mHunk: TTextLineHunk;
  mChange: TAtlasLineChange;
begin
  Result := nil;
  for mHunk in TTextDiff.Hunks(AOld, ANew) do
  begin
    mChange := Default(TAtlasLineChange);
    mChange.Line := mHunk.NewStart;
    mChange.Count := mHunk.NewCount;
    mChange.OldLine := mHunk.OldStart;
    mChange.OldLines := Copy(AOld, mHunk.OldStart, mHunk.OldCount);
    if mHunk.OldCount = 0 then
    begin
      mChange.Kind := TAtlasLineChangeKind.Added;
    end
    else if mHunk.NewCount = 0 then
    begin
      mChange.Kind := TAtlasLineChangeKind.Deleted;
    end
    else
    begin
      mChange.Kind := TAtlasLineChangeKind.Modified;
    end;
    Result := Result + [mChange];
  end;
end;

class function TAtlasLineChanges.MarkAt(const AChanges: TAtlasLineChangeList; ALine: Integer;
  out AIndex: Integer): TAtlasLineMark;
var
  mIndex: Integer;
begin
  AIndex := -1;
  Result := TAtlasLineMark.None;
  for mIndex := 0 to High(AChanges) do
  begin
    if AChanges[mIndex].Line > ALine then
    begin
      Break;
    end;
    if (AChanges[mIndex].Kind <> TAtlasLineChangeKind.Deleted) and
      (ALine < AChanges[mIndex].Line + AChanges[mIndex].Count) then
    begin
      AIndex := mIndex;
      if AChanges[mIndex].Kind = TAtlasLineChangeKind.Added then
      begin
        Result := TAtlasLineMark.Added;
      end
      else
      begin
        Result := TAtlasLineMark.Modified;
      end;
      Exit;
    end;
  end;
end;

class function TAtlasLineChanges.DeletedAt(const AChanges: TAtlasLineChangeList; ALine, ALineCount: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AChanges) do
  begin
    if (AChanges[mIndex].Kind = TAtlasLineChangeKind.Deleted) and ((AChanges[mIndex].Line = ALine) or
      ((ALine = ALineCount - 1) and (AChanges[mIndex].Line >= ALineCount))) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasLineChanges.ChangeAt(const AChanges: TAtlasLineChangeList; ALine, ALineCount: Integer): Integer;
begin
  MarkAt(AChanges, ALine, Result);
  if Result < 0 then
  begin
    Result := DeletedAt(AChanges, ALine, ALineCount);
  end;
end;

class function TAtlasLineChanges.Next(const AChanges: TAtlasLineChangeList; ALine, ALineCount: Integer;
  AForward: Boolean; out ATarget: Integer): Boolean;
var
  mIndex: Integer;

  function StartOf(AIndex: Integer): Integer;
  begin
    Result := AChanges[AIndex].Line;
    // Löschung am Ende: auf die letzte Zeile.
    if ALineCount > 0 then
    begin
      Result := Min(Result, ALineCount - 1);
    end;
  end;

  function Contains(AIndex: Integer): Boolean;
  begin
    Result := (ALine >= StartOf(AIndex)) and (ALine < StartOf(AIndex) + Max(1, AChanges[AIndex].Count));
  end;

begin
  ATarget := ALine;
  Result := Length(AChanges) > 0;
  if not Result then
  begin
    Exit;
  end;
  if AForward then
  begin
    for mIndex := 0 to High(AChanges) do
    begin
      if (StartOf(mIndex) > ALine) and not Contains(mIndex) then
      begin
        ATarget := StartOf(mIndex);
        Exit;
      end;
    end;
    ATarget := StartOf(0);
  end
  else
  begin
    for mIndex := High(AChanges) downto 0 do
    begin
      if (StartOf(mIndex) < ALine) and not Contains(mIndex) then
      begin
        ATarget := StartOf(mIndex);
        Exit;
      end;
    end;
    ATarget := StartOf(High(AChanges));
  end;
end;

class function TAtlasLineChanges.Revert(const AChange: TAtlasLineChange; const ALines: TArray<string>;
  const ALineBreak: string): TAtlasLineEdit;
var
  mOld: string;
  mLast: Integer;
begin
  Result := Default(TAtlasLineEdit);
  mOld := string.Join(ALineBreak, AChange.OldLines);
  mLast := AChange.Line + AChange.Count;
  if AChange.Kind = TAtlasLineChangeKind.Deleted then
  begin
    if AChange.Line < Length(ALines) then
    begin
      // Vor der Zeile einfügen.
      Result.StartLine := AChange.Line;
      Result.EndLine := AChange.Line;
      Result.NewText := mOld + ALineBreak;
    end
    else
    begin
      // Am Ende: hinter der letzten Zeile.
      Result.StartLine := Max(0, High(ALines));
      if Length(ALines) > 0 then
      begin
        Result.StartCharacter := Length(ALines[High(ALines)]);
      end;
      Result.EndLine := Result.StartLine;
      Result.EndCharacter := Result.StartCharacter;
      Result.NewText := ALineBreak + mOld;
    end;
    Exit;
  end;
  if mLast < Length(ALines) then
  begin
    // Ganze Zeilen samt Umbruch ersetzen.
    Result.StartLine := AChange.Line;
    Result.EndLine := mLast;
    Result.NewText := mOld;
    if AChange.Kind = TAtlasLineChangeKind.Modified then
    begin
      Result.NewText := mOld + ALineBreak;
    end;
    Exit;
  end;
  // Block bis zum Ende des Puffers.
  Result.EndLine := Max(0, High(ALines));
  if Length(ALines) > 0 then
  begin
    Result.EndCharacter := Length(ALines[High(ALines)]);
  end;
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
    Result.NewText := mOld;
  end;
end;

class function TAtlasLineChanges.BlameLine(const AHunks: TArray<TTextLineHunk>; ABufferLine: Integer): Integer;
var
  mHunk: TTextLineHunk;
  mShift: Integer;
begin
  mShift := 0;
  for mHunk in AHunks do
  begin
    if ABufferLine < mHunk.NewStart then
    begin
      Break;
    end;
    if ABufferLine < mHunk.NewStart + mHunk.NewCount then
    begin
      Exit(-1);
    end;
    mShift := mHunk.OldCount - mHunk.NewCount + mShift;
  end;
  Result := ABufferLine + mShift;
end;

class function TAtlasLineChanges.BlameLine(const ADisk, ABuffer: TArray<string>; ABufferLine: Integer): Integer;
begin
  Result := BlameLine(TTextDiff.Hunks(ADisk, ABuffer), ABufferLine);
end;

class function TAtlasLineChanges.Age(ANow, ADate: TDateTime): TAtlasAge;
var
  mMinutes: Int64;
begin
  Result.Count := 0;
  mMinutes := Max(0, MinutesBetween(ANow, ADate));
  if ANow < ADate then
  begin
    mMinutes := 0;
  end;
  if mMinutes < 1 then
  begin
    Result.Unit_ := TAtlasAgeUnit.JustNow;
  end
  else if mMinutes < 60 then
  begin
    Result.Unit_ := TAtlasAgeUnit.Minutes;
    Result.Count := Integer(mMinutes);
  end
  else if mMinutes < 24 * 60 then
  begin
    Result.Unit_ := TAtlasAgeUnit.Hours;
    Result.Count := Integer(mMinutes div 60);
  end
  else if mMinutes < 2 * 24 * 60 then
  begin
    Result.Unit_ := TAtlasAgeUnit.Yesterday;
  end
  else if mMinutes < 30 * 24 * 60 then
  begin
    Result.Unit_ := TAtlasAgeUnit.Days;
    Result.Count := Integer(mMinutes div (24 * 60));
  end
  else if mMinutes < 365 * 24 * 60 then
  begin
    Result.Unit_ := TAtlasAgeUnit.Months;
    Result.Count := Integer(mMinutes div (30 * 24 * 60));
  end
  else
  begin
    Result.Unit_ := TAtlasAgeUnit.Years;
    Result.Count := Integer(mMinutes div (365 * 24 * 60));
  end;
end;

end.
