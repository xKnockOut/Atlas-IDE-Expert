unit Atlas.Core.Tracker.Checklist;

// Checklisten in Issue-Beschreibungen (#1273), ohne VCL und Open Tools API.
// - Items: die Aufgabenpunkte ("- [ ]", "* [x]", "+ [ ]", "1. [ ]", auch
//   eingerückt), erkannt mit denselben Regeln wie die Vorschau
//   (TAtlasTrackerMarkdown.Blocks): nicht in Codeblöcken und Zitaten. Die
//   Nummer eines Punkts ist die Nummer seines Kästchens in der Vorschau
//   (TAtlasTrackerMarkdown.TaskTarget).
// - Progress: erledigt/gesamt für Kopfzeile der Vorschau, Statusfeld (#591)
//   und Board (#1272).
// - Toggle: ersetzt in genau einer Zeile "[ ]" durch "[x]" bzw. umgekehrt.
//   Der Punkt muss im aktuellen Text noch an derselben Zeile mit demselben
//   Wortlaut stehen (Vergleich Text + Position); sonst gilt die Beschreibung
//   als geändert, und nichts wird ersetzt. Zeilenenden (CRLF, LF, CR) und der
//   übrige Text bleiben Zeichen für Zeichen erhalten.
// - Append: hängt "- [ ] Text" unter den letzten Punkt (gleicher Einzug und
//   gleiche Marke, nummeriert mit der nächsten Zahl).
// Netz und Schreiben liegen beim Anbieter (IAtlasTrackerDescriptions).

interface

uses
  System.SysUtils;

type
  /// <summary>Aufgabenpunkt einer Beschreibung.</summary>
  TAtlasChecklistItem = record
    /// <summary>Nummer unter den Punkten der Beschreibung, ab 0 (wie das Kästchen in der Vorschau).</summary>
    Index: Integer;
    /// <summary>Zeile im Text, ab 0; Zeilenenden CRLF, LF und CR zählen je als ein Umbruch.</summary>
    Line: Integer;
    /// <summary>Letzte Zeile des Punkts samt Fortsetzungszeilen.</summary>
    LastLine: Integer;
    /// <summary>Die Zeile wie im Text, ohne Zeilenende.</summary>
    LineText: string;
    /// <summary>Markdown hinter dem Kästchen (mit Fortsetzungszeilen, Umbrüche als #10).</summary>
    Text: string;
    Checked: Boolean;
    /// <summary>Listenebene ab 1.</summary>
    Level: Integer;
  end;

  /// <summary>Fortschritt einer Checkliste.</summary>
  TAtlasChecklistProgress = record
    Done: Integer;
    Total: Integer;
    /// <summary>Mindestens ein Punkt.</summary>
    function Any: Boolean;
    /// <summary>"3/5"; '' ohne Punkte.</summary>
    function Text: string;
    class function Create(ADone, ATotal: Integer): TAtlasChecklistProgress; static;
  end;

  TAtlasTrackerChecklist = class
  public const
    /// <summary>Längster Text eines neuen Punkts.</summary>
    MaxItemText = 500;
  public
    class function Items(const AText: string): TArray<TAtlasChecklistItem>; static;
    class function Progress(const AText: string): TAtlasChecklistProgress; static;
    /// <summary>Punkt AIndex; False, wenn es ihn nicht gibt.</summary>
    class function Find(const AText: string; AIndex: Integer; out AItem: TAtlasChecklistItem): Boolean; static;
    /// <summary>Kästchen von AItem in AText umschalten. False (AResult = AText), wenn AText an AItem.Line keinen
    /// Punkt mit genau AItem.LineText mehr hat: Die Beschreibung wurde inzwischen geändert.</summary>
    class function Toggle(const AText: string; const AItem: TAtlasChecklistItem; out AResult: string): Boolean;
      static;
    /// <summary>"- [ ] AItemText" unter dem letzten Punkt anhängen. False (AResult = AText) ohne Punkte oder ohne
    /// Text; Zeilenumbrüche im Text werden Leerzeichen.</summary>
    class function Append(const AText, AItemText: string; out AResult: string): Boolean; static;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Core.Tracker.Markdown;

{ TAtlasChecklistProgress }

class function TAtlasChecklistProgress.Create(ADone, ATotal: Integer): TAtlasChecklistProgress;
begin
  Result.Done := ADone;
  Result.Total := ATotal;
end;

function TAtlasChecklistProgress.Any: Boolean;
begin
  Result := Total > 0;
end;

function TAtlasChecklistProgress.Text: string;
begin
  Result := '';
  if Any then
    Result := IntToStr(Done) + '/' + IntToStr(Total);
end;

{ Zeilen }

/// <summary>Stelle (1-basiert) des "[" vor dem Kästchen in einer Zeile mit Listenpunkt; 0 ohne.</summary>
function BoxPosition(const ALine: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  mIndex := 1;
  while (mIndex <= Length(ALine)) and CharInSet(ALine[mIndex], [' ', #9]) do
    Inc(mIndex);
  if mIndex > Length(ALine) then
    Exit;
  if CharInSet(ALine[mIndex], ['-', '*', '+']) then
    Inc(mIndex)
  else
  begin
    if not CharInSet(ALine[mIndex], ['0'..'9']) then
      Exit;
    while (mIndex <= Length(ALine)) and CharInSet(ALine[mIndex], ['0'..'9']) do
      Inc(mIndex);
    if (mIndex > Length(ALine)) or not CharInSet(ALine[mIndex], ['.', ')']) then
      Exit;
    Inc(mIndex);
  end;
  while (mIndex <= Length(ALine)) and CharInSet(ALine[mIndex], [' ', #9]) do
    Inc(mIndex);
  if (mIndex + 2 <= Length(ALine)) and (ALine[mIndex] = '[') and (ALine[mIndex + 2] = ']') and
    CharInSet(ALine[mIndex + 1], [' ', 'x', 'X']) then
    Result := mIndex;
end;

{ TAtlasTrackerChecklist }

class function TAtlasTrackerChecklist.Items(const AText: string): TArray<TAtlasChecklistItem>;
var
  mBlock: TAtlasMarkdownBlock;
  mLines: TArray<string>;
  mItem: TAtlasChecklistItem;
begin
  Result := nil;
  mLines := TTextLines.SplitLines(AText);
  for mBlock in TAtlasTrackerMarkdown.Blocks(AText) do
  begin
    if (mBlock.Kind <> TAtlasMarkdownBlockKind.Bullet) or (mBlock.Task = TAtlasMarkdownTask.None) or
      (mBlock.Line < 0) or (mBlock.Line > High(mLines)) then
      Continue;
    mItem := Default(TAtlasChecklistItem);
    mItem.Index := Length(Result);
    mItem.Line := mBlock.Line;
    mItem.LastLine := mBlock.LastLine;
    mItem.LineText := mLines[mBlock.Line];
    mItem.Text := mBlock.Text;
    mItem.Checked := mBlock.Task = TAtlasMarkdownTask.Done;
    mItem.Level := mBlock.Level;
    Result := Result + [mItem];
  end;
end;

class function TAtlasTrackerChecklist.Progress(const AText: string): TAtlasChecklistProgress;
var
  mItem: TAtlasChecklistItem;
begin
  Result := TAtlasChecklistProgress.Create(0, 0);
  for mItem in Items(AText) do
  begin
    Inc(Result.Total);
    if mItem.Checked then
      Inc(Result.Done);
  end;
end;

class function TAtlasTrackerChecklist.Find(const AText: string; AIndex: Integer;
  out AItem: TAtlasChecklistItem): Boolean;
var
  mItems: TArray<TAtlasChecklistItem>;
begin
  AItem := Default(TAtlasChecklistItem);
  mItems := Items(AText);
  Result := (AIndex >= 0) and (AIndex <= High(mItems));
  if Result then
    AItem := mItems[AIndex];
end;

class function TAtlasTrackerChecklist.Toggle(const AText: string; const AItem: TAtlasChecklistItem;
  out AResult: string): Boolean;
var
  mItem: TAtlasChecklistItem;
  mTable: TLineTable;
  mBox, mAt: Integer;
  mFound: Boolean;
begin
  AResult := AText;
  // Derselbe Punkt an derselben Zeile mit demselben Wortlaut, sonst wurde die Beschreibung geändert.
  mFound := False;
  for mItem in Items(AText) do
    if (mItem.Line = AItem.Line) and (mItem.LineText = AItem.LineText) then
    begin
      mFound := True;
      Break;
    end;
  if not mFound then
    Exit(False);
  mBox := BoxPosition(AItem.LineText);
  mTable := TLineTable.Build(AText);
  if (mBox = 0) or (AItem.Line >= mTable.LineCount) then
    Exit(False);
  // Nur das Zeichen im Kästchen (Offsets der Tabelle 0-basiert); alles andere bleibt, auch die Zeilenenden.
  mAt := mTable.LineStart(AItem.Line) + mBox + 1;
  if AText[mAt] = ' ' then
    AResult[mAt] := 'x'
  else
    AResult[mAt] := ' ';
  Result := True;
end;

class function TAtlasTrackerChecklist.Append(const AText, AItemText: string; out AResult: string): Boolean;
var
  mItems: TArray<TAtlasChecklistItem>;
  mLast: TAtlasChecklistItem;
  mTable: TLineTable;
  mText, mPrefix, mDigits, mLine: string;
  mBox, mIndex, mNumber, mEnd: Integer;
begin
  AResult := AText;
  mText := Trim(StringReplace(StringReplace(AItemText, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(mText) > MaxItemText then
    mText := Copy(mText, 1, MaxItemText);
  mItems := Items(AText);
  if (mText = '') or (Length(mItems) = 0) then
    Exit(False);
  // Unter dem letzten Punkt mit dessen Einzug und Marke.
  mLast := mItems[High(mItems)];
  mBox := BoxPosition(mLast.LineText);
  if mBox = 0 then
    Exit(False);
  mPrefix := Copy(mLast.LineText, 1, mBox - 1);
  // Nummeriert: die nächste Zahl ("3. [ ]" → "4. [ ]").
  mIndex := 1;
  while (mIndex <= Length(mPrefix)) and CharInSet(mPrefix[mIndex], [' ', #9]) do
    Inc(mIndex);
  mDigits := '';
  while (mIndex + Length(mDigits) <= Length(mPrefix)) and
    CharInSet(mPrefix[mIndex + Length(mDigits)], ['0'..'9']) do
    mDigits := mDigits + mPrefix[mIndex + Length(mDigits)];
  if (mDigits <> '') and TryStrToInt(mDigits, mNumber) then
    mPrefix := Copy(mPrefix, 1, mIndex - 1) + IntToStr(mNumber + 1) +
      Copy(mPrefix, mIndex + Length(mDigits), MaxInt);
  mLine := mPrefix + '[ ] ' + mText;
  mTable := TLineTable.Build(AText);
  if (mLast.LastLine < 0) or (mLast.LastLine >= mTable.LineCount) then
    Exit(False);
  // Hinter dem Inhalt der letzten Zeile des Punkts (0-basiert = Anzahl der Zeichen davor).
  mEnd := mTable.LineContentEnd(mLast.LastLine);
  AResult := Copy(AText, 1, mEnd) + TTextLines.LineBreakOf(AText) + mLine + Copy(AText, mEnd + 1, MaxInt);
  Result := True;
end;

end.
