unit Atlas.Core.InlayHints.Store;

// Inlay-Hints im Editor (#401, ARG-040), ohne VCL und Open Tools API:
// Parameternamen vor Literal-Argumenten (Zahl, String, Zeichen, True/False,
// nil) aus textDocument/inlayHint. Zwischenspeicher je Datei und Textstand:
// Ändert sich der Text, verfällt alles; geholt wird nur, was in den sichtbaren
// Zeilen (mit Rand) noch fehlt. Der RAD-Studio-Editor kennt keinen
// eingeschobenen Text; die Namen erscheinen deshalb in Zeilenreihenfolge
// hinter dem Zeilenende und verschieben weder Text noch Cursor.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TAtlasInlayHint = record
    /// <summary>0-basiert.</summary>
    Line: Integer;
    /// <summary>0-basiert, UTF-16-Index in der Zeile.</summary>
    Character: Integer;
    /// <summary>Parametername ohne ":".</summary>
    Name: string;
  end;

  TAtlasInlayHintStore = class
  public const
    /// <summary>Zusätzlich geholte Zeilen ober- und unterhalb des sichtbaren Bereichs.</summary>
    Margin = 20;
  private type
    TEntry = class
      Text: string;
      Lines: TArray<string>;
      Covered: TArray<Boolean>;
      Hints: TArray<TAtlasInlayHint>;
    end;
  private
    FEntries: TObjectDictionary<string, TEntry>;
    function Find(const AFileName: string): TEntry;
  public
    constructor Create;
    destructor Destroy; override;
    class function Key(const AFileName: string): string; static;
    /// <summary>Zeilen wie der Server sie zählt: CR, LF und CRLF trennen.</summary>
    class function SplitLines(const AText: string): TArray<string>; static;
    /// <summary>Beginnt an ACharacter (nach Leerraum) ein Literal: Zahl, String, Zeichen, True, False, nil?</summary>
    class function IsLiteralAt(const ALine: string; ACharacter: Integer): Boolean; static;
    /// <summary>Aktueller Text einer Datei; anderer Text verwirft ihre Hinweise.</summary>
    procedure SetText(const AFileName, AText: string);
    /// <summary>Fehlende Zeilen um AFirst..ALast (mit Rand); False, wenn alles da ist.</summary>
    function Missing(const AFileName: string; AFirst, ALast: Integer; out AFrom, ATo: Integer): Boolean;
    /// <summary>Antwort des Servers für AFrom..ATo zu AText; verworfen, wenn sich der Text inzwischen
    /// geändert hat. Nur Parameternamen vor Literalen bleiben.</summary>
    procedure Put(const AFileName, AText: string; AFrom, ATo: Integer; const AHints: TArray<TAtlasInlayHint>);
    /// <summary>Namen der Zeile in Reihenfolge.</summary>
    function OnLine(const AFileName: string; ALine: Integer): TArray<string>;
    /// <summary>Zeile im Speicher, zum Vergleich mit dem Editor.</summary>
    function LineText(const AFileName: string; ALine: Integer; out AText: string): Boolean;
    procedure Clear;
  end;

implementation

uses
  System.Generics.Defaults;

{ TAtlasInlayHintStore }

constructor TAtlasInlayHintStore.Create;
begin
  inherited Create;
  FEntries := TObjectDictionary<string, TEntry>.Create([doOwnsValues]);
end;

destructor TAtlasInlayHintStore.Destroy;
begin
  FEntries.Free;
  inherited;
end;

class function TAtlasInlayHintStore.Key(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

class function TAtlasInlayHintStore.SplitLines(const AText: string): TArray<string>;
var
  Index, Start: Integer;
begin
  Result := nil;
  Start := 1;
  Index := 1;
  while Index <= Length(AText) do
  begin
    if (AText[Index] = #13) or (AText[Index] = #10) then
    begin
      Result := Result + [Copy(AText, Start, Index - Start)];
      if (AText[Index] = #13) and (Index < Length(AText)) and (AText[Index + 1] = #10) then
        Inc(Index);
      Start := Index + 1;
    end;
    Inc(Index);
  end;
  Result := Result + [Copy(AText, Start, MaxInt)];
end;

function IsIdentChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

class function TAtlasInlayHintStore.IsLiteralAt(const ALine: string; ACharacter: Integer): Boolean;
var
  Index, Stop: Integer;
  Word: string;
  Next: Char;
begin
  Result := False;
  Index := ACharacter + 1;
  while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
    Inc(Index);
  if Index > Length(ALine) then
    Exit;
  Next := #0;
  if Index < Length(ALine) then
    Next := ALine[Index + 1];
  case ALine[Index] of
    '''':
      Exit(True);
    '0'..'9':
      Exit(True);
    '#', '$', '%':
      Exit(CharInSet(Next, ['0'..'9', 'A'..'F', 'a'..'f', '$']));
    '-', '+':
      Exit(CharInSet(Next, ['0'..'9', '$', '%']));
  end;
  Stop := Index;
  while (Stop <= Length(ALine)) and IsIdentChar(ALine[Stop]) do
    Inc(Stop);
  Word := LowerCase(Copy(ALine, Index, Stop - Index));
  Result := (Word = 'true') or (Word = 'false') or (Word = 'nil');
end;

function TAtlasInlayHintStore.Find(const AFileName: string): TEntry;
begin
  if not FEntries.TryGetValue(Key(AFileName), Result) then
    Result := nil;
end;

procedure TAtlasInlayHintStore.SetText(const AFileName, AText: string);
var
  Entry: TEntry;
begin
  Entry := Find(AFileName);
  if (Entry <> nil) and (Entry.Text = AText) then
    Exit;
  if Entry = nil then
  begin
    Entry := TEntry.Create;
    FEntries.Add(Key(AFileName), Entry);
  end;
  Entry.Text := AText;
  Entry.Lines := SplitLines(AText);
  Entry.Covered := nil;
  SetLength(Entry.Covered, Length(Entry.Lines));
  Entry.Hints := nil;
end;

function TAtlasInlayHintStore.Missing(const AFileName: string; AFirst, ALast: Integer; out AFrom, ATo: Integer): Boolean;
var
  Entry: TEntry;
  Line, First, Last: Integer;
begin
  AFrom := -1;
  ATo := -1;
  Entry := Find(AFileName);
  if (Entry = nil) or (Length(Entry.Lines) = 0) then
    Exit(False);
  First := AFirst - Margin;
  if First < 0 then
    First := 0;
  Last := ALast + Margin;
  if Last > High(Entry.Lines) then
    Last := High(Entry.Lines);
  for Line := First to Last do
    if not Entry.Covered[Line] then
    begin
      if AFrom < 0 then
        AFrom := Line;
      ATo := Line;
    end;
  Result := AFrom >= 0;
end;

procedure TAtlasInlayHintStore.Put(const AFileName, AText: string; AFrom, ATo: Integer;
  const AHints: TArray<TAtlasInlayHint>);
var
  Entry: TEntry;
  Line: Integer;
  Hint, Known: TAtlasInlayHint;
  Duplicate: Boolean;
begin
  Entry := Find(AFileName);
  if (Entry = nil) or (Entry.Text <> AText) then
    Exit;
  for Line := AFrom to ATo do
    if (Line >= 0) and (Line <= High(Entry.Covered)) then
      Entry.Covered[Line] := True;
  for Hint in AHints do
  begin
    if (Hint.Line < AFrom) or (Hint.Line > ATo) or (Hint.Line > High(Entry.Lines)) or (Hint.Name = '') or
      not IsLiteralAt(Entry.Lines[Hint.Line], Hint.Character) then
      Continue;
    // Überlappende Abrufe liefern dieselben Hinweise noch einmal.
    Duplicate := False;
    for Known in Entry.Hints do
      Duplicate := Duplicate or ((Known.Line = Hint.Line) and (Known.Character = Hint.Character));
    if not Duplicate then
      Entry.Hints := Entry.Hints + [Hint];
  end;
  TArray.Sort<TAtlasInlayHint>(Entry.Hints, TComparer<TAtlasInlayHint>.Construct(
    function(const ALeft, ARight: TAtlasInlayHint): Integer
    begin
      Result := ALeft.Line - ARight.Line;
      if Result = 0 then
        Result := ALeft.Character - ARight.Character;
    end));
end;

function TAtlasInlayHintStore.OnLine(const AFileName: string; ALine: Integer): TArray<string>;
var
  Entry: TEntry;
  Hint: TAtlasInlayHint;
begin
  Result := nil;
  Entry := Find(AFileName);
  if Entry = nil then
    Exit;
  for Hint in Entry.Hints do
    if Hint.Line = ALine then
      Result := Result + [Hint.Name];
end;

function TAtlasInlayHintStore.LineText(const AFileName: string; ALine: Integer; out AText: string): Boolean;
var
  Entry: TEntry;
begin
  AText := '';
  Entry := Find(AFileName);
  Result := (Entry <> nil) and (ALine >= 0) and (ALine <= High(Entry.Lines));
  if Result then
    AText := Entry.Lines[ALine];
end;

procedure TAtlasInlayHintStore.Clear;
begin
  FEntries.Clear;
end;

end.
