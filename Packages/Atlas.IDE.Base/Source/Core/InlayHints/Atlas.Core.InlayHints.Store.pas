unit Atlas.Core.InlayHints.Store;

// Inlay-Hints im Editor (#401, ARG-040), ohne VCL und Open Tools API:
// Parameternamen vor Literal-Argumenten (Zahl, String, Zeichen, True/False,
// nil) aus textDocument/inlayHint. Zwischenspeicher je Datei und Textstand:
// Ändert sich der Text, verfällt alles; geholt wird nur, was in den sichtbaren
// Zeilen (mit Rand) noch fehlt. Der RAD-Studio-Editor kennt keinen
// eingeschobenen Text; die Hinweise erscheinen deshalb in Zeilenreihenfolge
// hinter dem Zeilenende und verschieben weder Text noch Cursor. Weil dort der
// Bezug zum Argument fehlt, steht der Wert dabei („Name = 'LOCALAPPDATA'“), und
// es bleiben nur Hinweise, die etwas sagen: nicht beim einzigen Argument eines
// Aufrufs, nicht bei Namen wie S1, A oder X und nicht, wenn das Argument den
// Namen schon enthält.
// Blockende-Beschriftungen (#620): Die Endmarken des Servers ("// TKunde.Speichern"
// hinter dem end langer Blöcke, inlayHints.endMarkers) liegen getrennt von den
// Parameternamen und haben eine eigene Einstellung (BlockEndLabels). Keine Marke,
// wenn hinter dem end schon ein Kommentar steht; lange Texte enden mit „…“.
// Typmarken (#453): der abgeleitete Typ von var X := …, const X = … und for var X in … (kind 1) liegt
// ebenfalls getrennt, mit eigener Einstellung (InlayTypeHints), und erscheint als „: TStringList“.
// Include-Symbole (#860): hinter {$I datei.inc} die dort gesetzten Symbole, die die Unit prüft
// (data.includeDefines), mit eigener Einstellung (InlayDefineHints); die Beschriftung baut die
// Oberfläche in der Sprache der IDE („definiert COMPLIB_VCL“).
// Steuerzeichen (#862): hinter ^C im Wert einer Konstanten der Code „#3“ (data.controlChar), mit eigener
// Einstellung (InlayCharHints).
// Methoden ohne Self (#686): am Ende des Kopfs die Marke „ohne Self“ (data.methodWithoutSelf); ob sie kommt,
// entscheidet der Server (refactoring.methodKindMarker), die Beschriftung baut die Oberfläche.

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
    /// <summary>Parametername ohne ":"; bei einer Endmarke deren Text ohne "//".</summary>
    Name: string;
    /// <summary>Endmarke hinter einem end (#620) statt Parametername.</summary>
    EndLabel: Boolean;
    /// <summary>Typmarke (#453): Name ist der abgeleitete Typ ohne ":".</summary>
    TypeHint: Boolean;
    /// <summary>Include-Symbole (#860): Name sind die Symbole durch ", " getrennt.</summary>
    DefineHint: Boolean;
    /// <summary>Steuerzeichen (#862): Name ist der Code wie „#3“.</summary>
    CharHint: Boolean;
    /// <summary>Methode ohne Self (#686): Marke am Ende des Kopfs.</summary>
    MethodHint: Boolean;
    /// <summary>Endmarke: Anfang des Blocks (0-basiert), zu dem ein Klick springt; nur mit HasBlock.</summary>
    BlockLine: Integer;
    BlockCharacter: Integer;
    HasBlock: Boolean;
  end;

  TAtlasInlayHintStore = class
  public const
    /// <summary>Zusätzlich geholte Zeilen ober- und unterhalb des sichtbaren Bereichs.</summary>
    Margin = 20;
    /// <summary>Längster gezeigter Wert, danach „…“.</summary>
    MaxValueLength = 24;
    /// <summary>Längster Text einer Blockende-Beschriftung, danach „…“.</summary>
    MaxEndLabelLength = 40;
    /// <summary>Längster gezeigter Typ einer Typmarke (#453), danach „…“.</summary>
    MaxTypeLength = 40;
  private type
    TEntry = class
      Text: string;
      Lines: TArray<string>;
      Covered: TArray<Boolean>;
      Hints: TArray<TAtlasInlayHint>;
      Ends: TArray<TAtlasInlayHint>;
      Types: TArray<TAtlasInlayHint>;
      Defines: TArray<TAtlasInlayHint>;
      Chars: TArray<TAtlasInlayHint>;
      Methods: TArray<TAtlasInlayHint>;
      procedure PutEnd(const AHint: TAtlasInlayHint);
      /// <summary>Typmarke, Include-Symbole, Steuerzeichen oder Methode ohne Self.</summary>
      procedure PutMarker(const AHint: TAtlasInlayHint);
      procedure PutParameter(const AHint: TAtlasInlayHint);
      /// <summary>AHint übernehmen, wenn er in AFrom..ATo liegt und passt.</summary>
      procedure PutHint(const AHint: TAtlasInlayHint; AFrom, ATo: Integer);
      procedure Sort;
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
    /// <summary>Text des Arguments ab ACharacter bis zum nächsten Komma bzw. zur schließenden Klammer
    /// derselben Ebene, ohne Leerraum.</summary>
    class function ArgumentAt(const ALine: string; ACharacter: Integer): string; static;
    /// <summary>Ist das Argument ab ACharacter das einzige des Aufrufs: F(Argument)?</summary>
    class function IsSoleArgument(const ALine: string; ACharacter: Integer): Boolean; static;
    /// <summary>Sagt der Name nichts: ein oder zwei Zeichen oder Buchstabe mit Ziffern (S1, A, X2)?</summary>
    class function IsVagueName(const AName: string): Boolean; static;
    /// <summary>„Name = Wert“, lange Werte gekürzt.</summary>
    class function LabelOf(const AName, AValue: string): string; static;
    /// <summary>„// Text“ einer Blockende-Beschriftung, lange Texte gekürzt.</summary>
    class function EndLabelOf(const AText: string): string; static;
    /// <summary>Steht ab ACharacter (0-basiert) noch ein Kommentar in der Zeile?</summary>
    class function HasCommentAfter(const ALine: string; ACharacter: Integer): Boolean; static;
    /// <summary>Aktueller Text einer Datei; anderer Text verwirft ihre Hinweise.</summary>
    procedure SetText(const AFileName, AText: string);
    /// <summary>Fehlende Zeilen um AFirst..ALast (mit Rand); False, wenn alles da ist.</summary>
    function Missing(const AFileName: string; AFirst, ALast: Integer; out AFrom, ATo: Integer): Boolean;
    /// <summary>Antwort des Servers für AFrom..ATo zu AText; verworfen, wenn sich der Text inzwischen
    /// geändert hat. Nur Parameternamen vor Literalen bleiben.</summary>
    procedure Put(const AFileName, AText: string; AFrom, ATo: Integer; const AHints: TArray<TAtlasInlayHint>);
    /// <summary>Beschriftungen („Name = Wert“) der Zeile in Reihenfolge.</summary>
    function OnLine(const AFileName: string; ALine: Integer): TArray<string>;
    /// <summary>Typmarken („: TStringList“, #453) der Zeile in Reihenfolge.</summary>
    function TypesOnLine(const AFileName: string; ALine: Integer): TArray<string>;
    /// <summary>Include-Symbole hinter {$I} in der Zeile (#860), je Direktive die Symbole durch ", " getrennt.
    /// </summary>
    function DefinesOnLine(const AFileName: string; ALine: Integer): TArray<string>;
    /// <summary>Codes der Steuerzeichen in der Zeile („#3“, #862) in Reihenfolge.</summary>
    function CharsOnLine(const AFileName: string; ALine: Integer): TArray<string>;
    /// <summary>Steht in der Zeile die Marke einer Methode ohne Self (#686)?</summary>
    function MethodOnLine(const AFileName: string; ALine: Integer): Boolean;
    /// <summary>„: Typ“, lange Typen gekürzt.</summary>
    class function TypeLabelOf(const ATypeName: string): string; static;
    /// <summary>Blockende-Beschriftung der Zeile: AText ist der Text der Marke ohne "//" (Anker), ALabel die
    /// gezeigte Beschriftung („// TKunde.Speichern“); False ohne.</summary>
    function EndLabelOn(const AFileName: string; ALine: Integer; out AText, ALabel: string): Boolean; overload;
    /// <summary>Wie oben, dazu die ganze Marke mit Blockanfang (#620).</summary>
    function EndLabelOn(const AFileName: string; ALine: Integer; out AText, ALabel: string;
      out AHint: TAtlasInlayHint): Boolean; overload;
    /// <summary>Zeile im Speicher, zum Vergleich mit dem Editor.</summary>
    function LineText(const AFileName: string; ALine: Integer; out AText: string): Boolean;
    procedure Clear;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Text.Chars;

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
begin
  Result := TTextLines.SplitLines(AText);
end;

/// <summary>Steht ab AIndex (1-basiert) True, False oder nil?</summary>
function IsLiteralWord(const ALine: string; AIndex: Integer): Boolean;
var
  mStop: Integer;
  mWord: string;
begin
  mStop := AIndex;
  while (mStop <= Length(ALine)) and TTextChars.IsIdentChar(ALine[mStop]) do
  begin
    Inc(mStop);
  end;
  mWord := LowerCase(Copy(ALine, AIndex, mStop - AIndex));
  Result := (mWord = 'true') or (mWord = 'false') or (mWord = 'nil');
end;
class function TAtlasInlayHintStore.IsLiteralAt(const ALine: string; ACharacter: Integer): Boolean;
var
  Index: Integer;
  Next: Char;
begin
  Result := False;
  Index := ACharacter + 1;
  while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
  begin
    Inc(Index);
  end;
  if Index > Length(ALine) then
  begin
    Exit;
  end;
  Next := #0;
  if Index < Length(ALine) then
  begin
    Next := ALine[Index + 1];
  end;
  case ALine[Index] of
    '''', '0'..'9':
      Result := True;
    '#', '$', '%':
      Result := CharInSet(Next, ['0'..'9', 'A'..'F', 'a'..'f', '$']);
    '-', '+':
      Result := CharInSet(Next, ['0'..'9', '$', '%']);
  else
    Result := IsLiteralWord(ALine, Index);
  end;
end;

function TAtlasInlayHintStore.Find(const AFileName: string): TEntry;
begin
  if not FEntries.TryGetValue(Key(AFileName), Result) then
  begin
    Result := nil;
  end;
end;

procedure TAtlasInlayHintStore.SetText(const AFileName, AText: string);
var
  Entry: TEntry;
begin
  Entry := Find(AFileName);
  if (Entry <> nil) and (Entry.Text = AText) then
  begin
    Exit;
  end;
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
  Entry.Ends := nil;
  Entry.Types := nil;
  Entry.Defines := nil;
  Entry.Chars := nil;
  Entry.Methods := nil;
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
  begin
    Exit(False);
  end;
  First := AFirst - Margin;
  if First < 0 then
  begin
    First := 0;
  end;
  Last := ALast + Margin;
  if Last > High(Entry.Lines) then
  begin
    Last := High(Entry.Lines);
  end;
  for Line := First to Last do
  begin
    if not Entry.Covered[Line] then
    begin
      if AFrom < 0 then
      begin
        AFrom := Line;
      end;
      ATo := Line;
    end;
  end;
  Result := AFrom >= 0;
end;

/// <summary>Fügt AHint an, wenn an seiner Stelle noch keiner steht (überlappende Abrufe).</summary>
procedure AddOnce(var AList: TArray<TAtlasInlayHint>; const AHint: TAtlasInlayHint);
var
  Known: TAtlasInlayHint;
begin
  for Known in AList do
  begin
    if (Known.Line = AHint.Line) and (Known.Character = AHint.Character) then
    begin
      Exit;
    end;
  end;
  AList := AList + [AHint];
end;

function HintOrder(const ALeft, ARight: TAtlasInlayHint): Integer;
begin
  Result := ALeft.Line - ARight.Line;
  if Result = 0 then
  begin
    Result := ALeft.Character - ARight.Character;
  end;
end;

{ TAtlasInlayHintStore.TEntry }

procedure TAtlasInlayHintStore.TEntry.PutEnd(const AHint: TAtlasInlayHint);
var
  mKnown: TAtlasInlayHint;
  mDuplicate: Boolean;
begin
  // Endmarke (#620): nur ohne Kommentar hinter dem end, jede Zeile einmal.
  if TAtlasInlayHintStore.HasCommentAfter(Lines[AHint.Line], AHint.Character) then
  begin
    Exit;
  end;
  mDuplicate := False;
  for mKnown in Ends do
  begin
    mDuplicate := mDuplicate or (mKnown.Line = AHint.Line);
  end;
  if not mDuplicate then
  begin
    Ends := Ends + [AHint];
  end;
end;

procedure TAtlasInlayHintStore.TEntry.PutMarker(const AHint: TAtlasInlayHint);
begin
  // Typmarke (#453), Include-Symbole (#860), Steuerzeichen (#862) und Methoden ohne Self (#686): jede Stelle
  // einmal.
  if AHint.TypeHint then
  begin
    AddOnce(Types, AHint);
  end
  else if AHint.DefineHint then
  begin
    AddOnce(Defines, AHint);
  end
  else if AHint.MethodHint then
  begin
    AddOnce(Methods, AHint);
  end
  else
  begin
    AddOnce(Chars, AHint);
  end;
end;

procedure TAtlasInlayHintStore.TEntry.PutParameter(const AHint: TAtlasInlayHint);
var
  mLine: string;
begin
  mLine := Lines[AHint.Line];
  // Nur Parameternamen vor Literalen, die am Zeilenende noch etwas sagen. Überlappende Abrufe liefern
  // dieselben Hinweise noch einmal.
  if TAtlasInlayHintStore.IsLiteralAt(mLine, AHint.Character) and
    not TAtlasInlayHintStore.IsVagueName(AHint.Name) and
    not TAtlasInlayHintStore.IsSoleArgument(mLine, AHint.Character) and
    not ContainsText(TAtlasInlayHintStore.ArgumentAt(mLine, AHint.Character), AHint.Name) then
  begin
    AddOnce(Hints, AHint);
  end;
end;

procedure TAtlasInlayHintStore.TEntry.PutHint(const AHint: TAtlasInlayHint; AFrom, ATo: Integer);
begin
  if (AHint.Line < AFrom) or (AHint.Line > ATo) or (AHint.Line > High(Lines)) or (AHint.Name = '') then
  begin
    Exit;
  end;
  if AHint.EndLabel then
  begin
    PutEnd(AHint);
  end
  else if AHint.TypeHint or AHint.DefineHint or AHint.CharHint or AHint.MethodHint then
  begin
    PutMarker(AHint);
  end
  else
  begin
    PutParameter(AHint);
  end;
end;

procedure TAtlasInlayHintStore.TEntry.Sort;
var
  mOrder: IComparer<TAtlasInlayHint>;
begin
  mOrder := TComparer<TAtlasInlayHint>.Construct(HintOrder);
  TArray.Sort<TAtlasInlayHint>(Hints, mOrder);
  TArray.Sort<TAtlasInlayHint>(Types, mOrder);
  TArray.Sort<TAtlasInlayHint>(Defines, mOrder);
  TArray.Sort<TAtlasInlayHint>(Chars, mOrder);
end;
procedure TAtlasInlayHintStore.Put(const AFileName, AText: string; AFrom, ATo: Integer;
  const AHints: TArray<TAtlasInlayHint>);
var
  Entry: TEntry;
  Line: Integer;
  Hint: TAtlasInlayHint;
begin
  Entry := Find(AFileName);
  if (Entry = nil) or (Entry.Text <> AText) then
  begin
    Exit;
  end;
  for Line := AFrom to ATo do
  begin
    if (Line >= 0) and (Line <= High(Entry.Covered)) then
    begin
      Entry.Covered[Line] := True;
    end;
  end;
  for Hint in AHints do
  begin
    Entry.PutHint(Hint, AFrom, ATo);
  end;
  Entry.Sort;
end;

/// <summary>Namen der Hinweise aus AHints in ALine, in Reihenfolge.</summary>
function NamesOn(const AHints: TArray<TAtlasInlayHint>; ALine: Integer): TArray<string>;
var
  Hint: TAtlasInlayHint;
begin
  Result := nil;
  for Hint in AHints do
  begin
    if Hint.Line = ALine then
    begin
      Result := Result + [Hint.Name];
    end;
  end;
end;

function TAtlasInlayHintStore.DefinesOnLine(const AFileName: string; ALine: Integer): TArray<string>;
var
  Entry: TEntry;
begin
  Result := nil;
  Entry := Find(AFileName);
  if Entry <> nil then
  begin
    Result := NamesOn(Entry.Defines, ALine);
  end;
end;

function TAtlasInlayHintStore.CharsOnLine(const AFileName: string; ALine: Integer): TArray<string>;
var
  Entry: TEntry;
begin
  Result := nil;
  Entry := Find(AFileName);
  if Entry <> nil then
  begin
    Result := NamesOn(Entry.Chars, ALine);
  end;
end;

function TAtlasInlayHintStore.MethodOnLine(const AFileName: string; ALine: Integer): Boolean;
var
  Entry: TEntry;
begin
  Entry := Find(AFileName);
  Result := (Entry <> nil) and (Length(NamesOn(Entry.Methods, ALine)) > 0);
end;

function TAtlasInlayHintStore.OnLine(const AFileName: string; ALine: Integer): TArray<string>;
var
  Entry: TEntry;
  Hint: TAtlasInlayHint;
begin
  Result := nil;
  Entry := Find(AFileName);
  if Entry = nil then
  begin
    Exit;
  end;
  for Hint in Entry.Hints do
  begin
    if Hint.Line = ALine then
    begin
      Result := Result + [LabelOf(Hint.Name, ArgumentAt(Entry.Lines[ALine], Hint.Character))];
    end;
  end;
end;

function TAtlasInlayHintStore.TypesOnLine(const AFileName: string; ALine: Integer): TArray<string>;
var
  Entry: TEntry;
  Hint: TAtlasInlayHint;
begin
  Result := nil;
  Entry := Find(AFileName);
  if Entry = nil then
  begin
    Exit;
  end;
  // In Spaltenreihenfolge, wie die Variablen in der Zeile stehen.
  for Hint in Entry.Types do
  begin
    if Hint.Line = ALine then
    begin
      Result := Result + [TypeLabelOf(Hint.Name)];
    end;
  end;
end;

class function TAtlasInlayHintStore.TypeLabelOf(const ATypeName: string): string;
begin
  Result := ': ' + ATypeName;
  if Length(Result) > MaxTypeLength + 2 then
  begin
    Result := Copy(Result, 1, MaxTypeLength + 1) + '…';
  end;
end;

function TAtlasInlayHintStore.EndLabelOn(const AFileName: string; ALine: Integer; out AText, ALabel: string): Boolean;
var
  Hint: TAtlasInlayHint;
begin
  Result := EndLabelOn(AFileName, ALine, AText, ALabel, Hint);
end;

function TAtlasInlayHintStore.EndLabelOn(const AFileName: string; ALine: Integer; out AText, ALabel: string;
  out AHint: TAtlasInlayHint): Boolean;
var
  Entry: TEntry;
  Hint: TAtlasInlayHint;
begin
  AText := '';
  ALabel := '';
  AHint := Default(TAtlasInlayHint);
  Entry := Find(AFileName);
  if Entry = nil then
  begin
    Exit(False);
  end;
  for Hint in Entry.Ends do
  begin
    if Hint.Line = ALine then
    begin
      AText := Hint.Name;
      ALabel := EndLabelOf(Hint.Name);
      AHint := Hint;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasInlayHintStore.EndLabelOf(const AText: string): string;
begin
  if Length(AText) > MaxEndLabelLength then
  begin
    Result := '// ' + TrimRight(Copy(AText, 1, MaxEndLabelLength - 1)) + '…';
  end
  else
  begin
    Result := '// ' + AText;
  end;
end;

class function TAtlasInlayHintStore.HasCommentAfter(const ALine: string; ACharacter: Integer): Boolean;
var
  Index: Integer;
  InString: Boolean;
begin
  InString := False;
  Index := Max(0, ACharacter) + 1;
  while Index <= Length(ALine) do
  begin
    if InString then
    begin
      if ALine[Index] = '''' then
      begin
        InString := False;
      end;
    end
    else if ALine[Index] = '''' then
    begin
      InString := True;
    end
    else if (ALine[Index] = '{') or (Copy(ALine, Index, 2) = '//') or (Copy(ALine, Index, 2) = '(*') then
    begin
      Exit(True);
    end;
    Inc(Index);
  end;
  Result := False;
end;

class function TAtlasInlayHintStore.ArgumentAt(const ALine: string; ACharacter: Integer): string;
var
  Index, Depth: Integer;
  InString: Boolean;
begin
  Depth := 0;
  InString := False;
  Index := ACharacter + 1;
  while Index <= Length(ALine) do
  begin
    if InString then
    begin
      if ALine[Index] = '''' then
      begin
        InString := False;
      end;
    end
    else if ALine[Index] = '''' then
    begin
      InString := True;
    end
    else if CharInSet(ALine[Index], ['(', '[']) then
    begin
      Inc(Depth);
    end
    else if CharInSet(ALine[Index], [')', ']']) then
    begin
      if Depth = 0 then
      begin
        Break;
      end;
      Dec(Depth);
    end
    else if (ALine[Index] = ',') and (Depth = 0) then
    begin
      Break;
    end;
    Inc(Index);
  end;
  Result := Trim(Copy(ALine, ACharacter + 1, Index - ACharacter - 1));
end;

class function TAtlasInlayHintStore.IsSoleArgument(const ALine: string; ACharacter: Integer): Boolean;
var
  Before, After: Integer;
begin
  Before := ACharacter;
  while (Before >= 1) and CharInSet(ALine[Before], [' ', #9]) do
  begin
    Dec(Before);
  end;
  After := ACharacter + Length(ArgumentAt(ALine, ACharacter)) + 1;
  while (After <= Length(ALine)) and CharInSet(ALine[After], [' ', #9]) do
  begin
    Inc(After);
  end;
  Result := (Before >= 1) and (ALine[Before] = '(') and (After <= Length(ALine)) and (ALine[After] = ')');
end;

class function TAtlasInlayHintStore.IsVagueName(const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := Length(AName) <= 2;
  if Result or not CharInSet(AName[1], ['A'..'Z', 'a'..'z']) then
  begin
    Exit;
  end;
  for Index := 2 to Length(AName) do
  begin
    if not CharInSet(AName[Index], ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TAtlasInlayHintStore.LabelOf(const AName, AValue: string): string;
begin
  if Length(AValue) > MaxValueLength then
  begin
    Result := AName + ' = ' + Copy(AValue, 1, MaxValueLength - 1) + '…';
  end
  else
  begin
    Result := AName + ' = ' + AValue;
  end;
end;

function TAtlasInlayHintStore.LineText(const AFileName: string; ALine: Integer; out AText: string): Boolean;
var
  Entry: TEntry;
begin
  AText := '';
  Entry := Find(AFileName);
  Result := (Entry <> nil) and (ALine >= 0) and (ALine <= High(Entry.Lines));
  if Result then
  begin
    AText := Entry.Lines[ALine];
  end;
end;

procedure TAtlasInlayHintStore.Clear;
begin
  FEntries.Clear;
end;

end.
