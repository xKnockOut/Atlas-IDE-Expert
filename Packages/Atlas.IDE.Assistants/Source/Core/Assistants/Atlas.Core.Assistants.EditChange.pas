unit Atlas.Core.Assistants.EditChange;

// Eine Änderung eines KI-Assistenten an einer Datei als geänderter Zeilenblock, ohne Windows und VCL: für das
// Fenster „Atlas-KI-Protokoll“ (#2049) und den Hinweis auf zurückgehaltene Änderungen (#2605).
// Between vergleicht den Text vorher und nachher zeilenweise: gleiche Zeilen am Anfang und am Ende fallen weg, der
// Rest ist der Block (alte und neue Zeilen samt Zeilenende). Dazu je bis zu cContextLines unveränderte Zeilen davor
// und danach. Damit lässt sich die Änderung später zurücknehmen, auch wenn an anderer Stelle der Datei
// weitergearbeitet wurde: RevertIn sucht Umgebung und neuen Block im aktuellen Text. Steht er genau einmal da (am
// Dateianfang bzw. -ende verankert, wenn die Umgebung dort endet), wird er durch den alten Block ersetzt; sonst ist
// die Stelle seither geändert und nichts geschieht. Sehr große Änderungen behalten ihre Texte nicht (Kept = False),
// damit das Protokoll klein bleibt; sie lassen sich nur ansehen, nicht zurücknehmen.

interface

type
  TAtlasEditChange = record
  public const
    /// <summary>So viele unveränderte Zeilen davor und danach gehören zur Umgebung.</summary>
    cContextLines = 2;
    /// <summary>Über so viele Zeichen (alter und neuer Block zusammen) werden die Texte nicht behalten.</summary>
    cMaxKeptChars = 200000;
  public
    /// <summary>Erste geänderte Zeile im Text nachher, ab 1.</summary>
    FirstLine: Integer;
    /// <summary>Zeilen des Blocks vorher (−) und nachher (+).</summary>
    Removed: Integer;
    Added: Integer;
    /// <summary>Alter und neuer Block samt Zeilenenden; leer, wenn Kept = False.</summary>
    OldText: string;
    NewText: string;
    /// <summary>Unveränderte Zeilen vor und nach dem Block (im Text vorher und nachher gleich).</summary>
    Before: string;
    After: string;
    /// <summary>Die Umgebung reicht bis zum Anfang bzw. Ende der Datei.</summary>
    AtStart: Boolean;
    AtEnd: Boolean;
    /// <summary>Die Texte des Blocks sind behalten (nicht zu groß).</summary>
    Kept: Boolean;
    /// <summary>Kleinster geänderter Zeilenblock von ABefore nach AAfter.</summary>
    class function Between(const ABefore, AAfter: string): TAtlasEditChange; static;
    /// <summary>Nichts geändert.</summary>
    function IsEmpty: Boolean;
    /// <summary>Letzte geänderte Zeile im Text nachher (bei einer reinen Löschung die Zeile davor, mindestens
    /// FirstLine).</summary>
    function LastLine: Integer;
    /// <summary>Text nach dem Zurücknehmen in ACurrent; False, wenn der Block dort nicht genau einmal unverändert
    /// steht oder die Texte nicht behalten sind.</summary>
    function RevertIn(const ACurrent: string; out ANewText: string): Boolean;
    /// <summary>Zeilen für die Anzeige des Unterschieds: „- “ alte, „+ “ neue Zeilen ohne Zeilenende.</summary>
    function DiffLines: TArray<string>;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Text.Lines;

/// <summary>Zeilen AFrom bis AFrom + ACount - 1 aus ALines zusammengesetzt.</summary>
function JoinLines(const ALines: TArray<string>; AFrom, ACount: Integer): string;
var
  mIndex: Integer;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := AFrom to AFrom + ACount - 1 do
    begin
      mBuilder.Append(ALines[mIndex]);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Zeile ohne Zeilenende.</summary>
function WithoutBreak(const ALine: string): string;
begin
  Result := ALine;
  while (Result <> '') and CharInSet(Result[Length(Result)], [#13, #10]) do
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

/// <summary>Stellen, an denen ABlock in AText beginnt (0-basiert), höchstens zwei.</summary>
function Occurrences(const AText, ABlock: string): TArray<Integer>;
var
  mFrom, mAt, mCount: Integer;
begin
  Result := nil;
  SetLength(Result, 2);
  mCount := 0;
  mFrom := 1;
  while mCount < Length(Result) do
  begin
    mAt := Pos(ABlock, AText, mFrom);
    if mAt = 0 then
    begin
      Break;
    end;
    Result[mCount] := mAt - 1;
    Inc(mCount);
    mFrom := mAt + 1;
  end;
  SetLength(Result, mCount);
end;

{ TAtlasEditChange }

class function TAtlasEditChange.Between(const ABefore, AAfter: string): TAtlasEditChange;
var
  mOld, mNew: TArray<string>;
  mPrefix, mSuffix, mLimit, mContextStart, mContextCount: Integer;
begin
  Result := Default(TAtlasEditChange);
  mOld := TTextLines.SplitKeepingBreaks(ABefore);
  mNew := TTextLines.SplitKeepingBreaks(AAfter);
  mLimit := Min(Length(mOld), Length(mNew));
  mPrefix := 0;
  while (mPrefix < mLimit) and (mOld[mPrefix] = mNew[mPrefix]) do
  begin
    Inc(mPrefix);
  end;
  mSuffix := 0;
  while (mSuffix < mLimit - mPrefix) and (mOld[High(mOld) - mSuffix] = mNew[High(mNew) - mSuffix]) do
  begin
    Inc(mSuffix);
  end;
  Result.FirstLine := mPrefix + 1;
  Result.Removed := Length(mOld) - mPrefix - mSuffix;
  Result.Added := Length(mNew) - mPrefix - mSuffix;
  Result.OldText := JoinLines(mOld, mPrefix, Result.Removed);
  Result.NewText := JoinLines(mNew, mPrefix, Result.Added);
  Result.Kept := Length(Result.OldText) + Length(Result.NewText) <= cMaxKeptChars;
  if not Result.Kept then
  begin
    Result.OldText := '';
    Result.NewText := '';
  end;
  mContextStart := Max(0, mPrefix - cContextLines);
  Result.Before := JoinLines(mNew, mContextStart, mPrefix - mContextStart);
  Result.AtStart := mContextStart = 0;
  mContextCount := Min(cContextLines, mSuffix);
  Result.After := JoinLines(mNew, mPrefix + Result.Added, mContextCount);
  Result.AtEnd := mContextCount = mSuffix;
end;

function TAtlasEditChange.IsEmpty: Boolean;
begin
  Result := (Removed = 0) and (Added = 0);
end;

function TAtlasEditChange.LastLine: Integer;
begin
  Result := Max(FirstLine, FirstLine + Added - 1);
end;

function TAtlasEditChange.RevertIn(const ACurrent: string; out ANewText: string): Boolean;
var
  mBlock: string;
  mFound: TArray<Integer>;
  mAt: Integer;
begin
  ANewText := '';
  if not Kept or IsEmpty then
  begin
    Exit(False);
  end;
  mBlock := Before + NewText + After;
  if mBlock = '' then
  begin
    // Die ganze Datei war der Block und ist jetzt leer: nur dann zurück, wenn sie noch leer ist.
    Result := ACurrent = '';
    if Result then
    begin
      ANewText := OldText;
    end;
    Exit;
  end;
  if AtStart then
  begin
    mFound := nil;
    if ACurrent.StartsWith(mBlock) then
    begin
      mFound := [0];
    end;
  end
  else
  begin
    mFound := Occurrences(ACurrent, mBlock);
  end;
  if Length(mFound) <> 1 then
  begin
    Exit(False);
  end;
  mAt := mFound[0];
  if AtEnd and (mAt + Length(mBlock) <> Length(ACurrent)) then
  begin
    Exit(False);
  end;
  ANewText := Copy(ACurrent, 1, mAt) + Before + OldText + After + Copy(ACurrent, mAt + Length(mBlock) + 1, MaxInt);
  Result := True;
end;

function TAtlasEditChange.DiffLines: TArray<string>;
var
  mLine: string;
begin
  Result := nil;
  for mLine in TTextLines.SplitKeepingBreaks(OldText) do
  begin
    Result := Result + ['- ' + WithoutBreak(mLine)];
  end;
  for mLine in TTextLines.SplitKeepingBreaks(NewText) do
  begin
    Result := Result + ['+ ' + WithoutBreak(mLine)];
  end;
end;

end.
