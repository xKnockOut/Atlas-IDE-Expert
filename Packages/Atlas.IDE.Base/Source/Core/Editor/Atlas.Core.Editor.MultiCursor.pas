unit Atlas.Core.Editor.MultiCursor;

// Mehrere Einfügemarken (#589), ohne Open Tools API: Marken als logische
// Positionen (Zeile, Zeichen, 0-basiert) samt Anker der Markierung.
// - [0] ist die Hauptmarke (die Einfügemarke der IDE), dahinter die
//   Zusatzmarken in der Reihenfolge des Hinzufügens. Merge legt gleiche und
//   überlappende Marken zusammen; die früheste bleibt.
// - Bewegen (Pfeile, Pos1/Ende, Wortsprünge, mit Umschalt erweitern),
//   Hinzufügen (Alt+Klick, Strg+D, Alt+Umschalt+I, Strg+Alt+↑/↓) und
//   Bearbeiten (Tippen, Rücktaste, Entf, Enter, Einfügen) rechnen nur auf dem
//   Text. Edit und Paste liefern den ganzen neuen Text; die IDE schreibt den
//   Unterschied in einem Schritt (ein Undo-Schritt für alle Stellen).
// - Shift folgt fremden Änderungen; Mirror wiederholt eine Änderung der IDE
//   an der Hauptmarke (etwa die Übernahme eines Vorschlags) an allen Marken.
// Für out-Parameter nie dieselbe Variable wie für die Eingabe übergeben: out
// leert verwaltete Variablen vor dem Aufruf.
// Den Unterschied zweier Texte bestimmt ein zeichengenauer Vergleich von
// gemeinsamem Anfang und Ende (TAtlasLineMover.Difference ersetzt ganze
// Zeilen und taugt für Markenpositionen nicht).

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TAtlasCaretMove = (Left, Right, Up, Down, LineStart, LineEnd, WordLeft, WordRight);
  TAtlasCaretEditKind = (Insert, Backspace, Delete, NewLine);
  TAtlasOccurrence = (None, WordSelected, Added);
  {$SCOPEDENUMS OFF}

  /// <summary>Eine Marke, 0-basiert (Zeile, Zeichenindex im String; Tab = 1 Zeichen). Anker = Position ohne
  /// Markierung.</summary>
  TAtlasCaret = record
    Line, Character: Integer;
    AnchorLine, AnchorCharacter: Integer;
    /// <summary>Gewünschte Anzeigespalte für ↑/↓ (Tabs aufgelöst), -1 = aus Character.</summary>
    Column: Integer;
    class function At(ALine, ACharacter: Integer): TAtlasCaret; static;
    class function Range(AAnchorLine, AAnchorCharacter, ALine, ACharacter: Integer): TAtlasCaret; static;
    function HasSelection: Boolean;
    /// <summary>Anfang und Ende der Markierung in Textreihenfolge.</summary>
    procedure Bounds(out AStartLine, AStartCharacter, AEndLine, AEndCharacter: Integer);
  end;
  /// <summary>[0] = Hauptmarke, dann in der Reihenfolge des Hinzufügens.</summary>
  TAtlasCarets = TArray<TAtlasCaret>;

  TAtlasMultiCursor = class
  public
    /// <summary>Entfernt gleiche und überlappende Marken (sich berührende Markierungen bleiben getrennt); die
    /// früheste bleibt und bekommt die vereinigte Markierung; Reihenfolge bleibt, [0] bleibt Hauptmarke.</summary>
    class function Merge(const ACarets: TAtlasCarets): TAtlasCarets; static;
    /// <summary>Alt+Klick: Zusatzmarke an (ALine, ACharacter) entfernen, falls dort eine steht (nie die
    /// Hauptmarke); sonst eine neue Marke anhängen.</summary>
    class function Toggle(const ACarets: TAtlasCarets; ALine, ACharacter: Integer): TAtlasCarets; static;
    /// <summary>Alle Marken bewegen. AExtend: Markierung erweitern, sonst aufheben; ohne AExtend springen Left
    /// und Right mit Markierung an deren Anfang bzw. Ende. Up/Down halten die Anzeigespalte (Tabbreite
    /// ATabWidth) und klemmen ans Zeilenende; in der ersten Zeile führt Up an Zeichen 0, in der letzten Down ans
    /// Zeilenende. WordLeft/WordRight wie die IDE (Bezeichner, Satzzeichenfolgen, Leerraum; am Zeilenrand in
    /// die Nachbarzeile). Danach Merge.</summary>
    class function Move(const ALines: TArray<string>; const ACarets: TAtlasCarets; AMove: TAtlasCaretMove;
      AExtend: Boolean; ATabWidth: Integer): TAtlasCarets; static;
    /// <summary>Strg+Alt+↑/↓: neue Marke eine Zeile über der obersten bzw. unter der untersten Marke in derselben
    /// Anzeigespalte (bei kürzerer Zeile am Zeilenende). False ohne solche Zeile oder ohne Änderung.</summary>
    class function AddVertical(const ALines: TArray<string>; const ACarets: TAtlasCarets; AUp: Boolean;
      ATabWidth: Integer; out AResult: TAtlasCarets): Boolean; static;
    /// <summary>Alt+Umschalt+I: je Zeile der Markierung von ACaret eine Marke am Zeilenende; eine spätere Zeile,
    /// in der die Markierung bei Zeichen 0 endet, zählt nicht. Die erste Zeile ist die Hauptmarke; ohne
    /// Markierung eine Marke am Ende der Zeile.</summary>
    class function LineEnds(const ALines: TArray<string>; const ACaret: TAtlasCaret): TAtlasCarets; static;
    /// <summary>Strg+D: Eine Marke ohne Markierung markiert das Wort am Caret (WordSelected; ohne Wort None).
    /// Sonst wird der Text der zuletzt hinzugefügten Markierung (nur einzeilig) ab deren Ende gesucht, am
    /// Dateiende von vorn; schon markierte Stellen zählen nicht. Gefunden: neue Marke mit Markierung (Added),
    /// sonst None. AMatchCase/AWholeWord wie im Suchen-Dialog der IDE.</summary>
    class function NextOccurrence(const ALines: TArray<string>; const ACarets: TAtlasCarets; AMatchCase,
      AWholeWord: Boolean; out AResult: TAtlasCarets): TAtlasOccurrence; static;
    /// <summary>Strg+K, Strg+D: zuletzt hinzugefügte Marke (nie die Hauptmarke) entfernen und das nächste
    /// Vorkommen ab ihrem Ende hinzufügen. False ohne Zusatzmarke.</summary>
    class function SkipOccurrence(const ALines: TArray<string>; const ACarets: TAtlasCarets; AMatchCase,
      AWholeWord: Boolean; out AResult: TAtlasCarets): Boolean; static;
    /// <summary>Tastendruck an allen Marken auf AText (Zeilenende wie im Dokument, CRLF oder LF). Insert ersetzt
    /// die Markierung durch AInsert; Backspace/Delete löschen die Markierung, sonst ein Zeichen davor bzw.
    /// danach (ein Zeilenumbruch als Ganzes, am Dateianfang bzw. -ende nichts); NewLine = Zeilenumbruch und der
    /// Einzug der Zeile (Leerraum am Zeilenanfang, höchstens bis zur Marke). Die Marken stehen danach hinter dem
    /// Eingefügten, ohne Markierung. False, wenn sich nichts ändert.</summary>
    class function Edit(const AText: string; const ACarets: TAtlasCarets; AKind: TAtlasCaretEditKind;
      const AInsert: string; out ANewText: string; out ANewCarets: TAtlasCarets): Boolean; static;
    /// <summary>Einfügen an allen Marken: Hat die Zwischenablage so viele Zeilen wie Marken (PasteParts), bekommt
    /// jede Marke in Textreihenfolge ihre Zeile, sonst überall den ganzen Text. Zeilenumbrüche im Eingefügten
    /// werden die des Dokuments.</summary>
    class function Paste(const AText: string; const ACarets: TAtlasCarets; const AClipboard: string;
      out ANewText: string; out ANewCarets: TAtlasCarets): Boolean; static;
    /// <summary>Zwischenablage in Zeilen (CRLF oder LF; ein abschließender Umbruch zählt nicht): genau ACount
    /// Zeilen ergeben die Zeilen, sonst ein Element mit dem ganzen Text.</summary>
    class function PasteParts(const AClipboard: string; ACount: Integer): TArray<string>; static;
    /// <summary>Kopieren: markierte Texte in Textreihenfolge, mit ALineBreak verbunden; '' ohne Markierung.
    /// </summary>
    class function SelectedText(const AText: string; const ACarets: TAtlasCarets;
      const ALineBreak: string): string; static;
    /// <summary>Fremde Änderung von AOldText nach ANewText: Marken davor bleiben, ab ihrem Ende (auch genau an
    /// einer Einfügestelle) rücken sie mit, darin stehen sie hinter dem Eingefügten. Danach Merge.</summary>
    class function Shift(const AOldText, ANewText: string; const ACarets: TAtlasCarets): TAtlasCarets; static;
    /// <summary>Änderung der IDE an der Hauptmarke (etwa Übernahme eines Vorschlags) an allen Marken ausführen:
    /// Liegt die Hauptmarke (ohne Markierung) im geänderten Bereich und enthält der gelöschte Teil keinen
    /// Zeilenumbruch, löscht jede andere Marke ohne Markierung gleich viele Zeichen davor und danach (auf ihre
    /// Zeile geklemmt) und fügt dasselbe ein. ACarets beziehen sich auf AOldText; AText ist AOldText mit allen
    /// Änderungen, ANewCarets die Marken darin. False, wenn die Änderung nicht an der Hauptmarke war (dann gilt
    /// Shift).</summary>
    class function Mirror(const AOldText, ANewText: string; const ACarets: TAtlasCarets; out AText: string;
      out ANewCarets: TAtlasCarets): Boolean; static;
    /// <summary>Zeilen von AText ohne Zeilenumbruch (CRLF oder LF); mindestens eine.</summary>
    class function Lines(const AText: string): TArray<string>; static;
    /// <summary>CRLF, wenn AText eines enthält, sonst LF (TTextLines.LineBreakOf).</summary>
    class function LineBreakOf(const AText: string): string; static;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Chars,
  Atlas.Text.Lines;

type
  /// <summary>Zeilenanfänge (Offsets, 0-basiert) und Zeilenlängen ohne Umbruch.</summary>
  TLineIndex = record
    Starts, Lengths: TArray<Integer>;
    class function Build(const AText: string): TLineIndex; static;
    function Count: Integer;
    function Offset(ALine, ACharacter: Integer): Integer;
    procedure Position(AOffset: Integer; out ALine, ACharacter: Integer);
  end;

  /// <summary>Ersetzung von [Start, Stop) durch Text; Caret = Index der Marke.</summary>
  TTextEdit = record
    Start, Stop: Integer;
    Text: string;
    Caret: Integer;
    NewStop: Integer;
  end;

{ TLineIndex }

class function TLineIndex.Build(const AText: string): TLineIndex;
var
  Starts, Lengths: TArray<Integer>;
  Index, Start, Count, Len: Integer;

  procedure Add(AStart, ALength: Integer);
  begin
    if Count = Length(Starts) then
    begin
      SetLength(Starts, Count * 2 + 16);
      SetLength(Lengths, Count * 2 + 16);
    end;
    Starts[Count] := AStart;
    Lengths[Count] := ALength;
    Inc(Count);
  end;

begin
  Starts := nil;
  Lengths := nil;
  Count := 0;
  Start := 0;
  for Index := 1 to Length(AText) do
    if AText[Index] = #10 then
    begin
      Len := Index - 1 - Start;
      if (Len > 0) and (AText[Index - 1] = #13) then
        Dec(Len);
      Add(Start, Len);
      Start := Index;
    end;
  Add(Start, Length(AText) - Start);
  SetLength(Starts, Count);
  SetLength(Lengths, Count);
  Result.Starts := Starts;
  Result.Lengths := Lengths;
end;

function TLineIndex.Count: Integer;
begin
  Result := Length(Starts);
end;

function TLineIndex.Offset(ALine, ACharacter: Integer): Integer;
begin
  ALine := EnsureRange(ALine, 0, Count - 1);
  Result := Starts[ALine] + EnsureRange(ACharacter, 0, Lengths[ALine]);
end;

procedure TLineIndex.Position(AOffset: Integer; out ALine, ACharacter: Integer);
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Count - 1;
  while Low < High do
  begin
    Middle := (Low + High + 1) div 2;
    if Starts[Middle] <= AOffset then
      Low := Middle
    else
      High := Middle - 1;
  end;
  ALine := Low;
  ACharacter := EnsureRange(AOffset - Starts[Low], 0, Lengths[Low]);
end;

{ Hilfen }

function ComparePos(ALine1, ACharacter1, ALine2, ACharacter2: Integer): Integer;
begin
  if ALine1 <> ALine2 then
    Result := CompareValue(ALine1, ALine2)
  else
    Result := CompareValue(ACharacter1, ACharacter2);
end;

function IsSpace(C: Char): Boolean;
begin
  Result := (C = ' ') or (C = #9);
end;

/// <summary>Mindestens eine Zeile.</summary>
function SafeLines(const ALines: TArray<string>): TArray<string>;
begin
  Result := ALines;
  if Length(Result) = 0 then
  begin
    SetLength(Result, 1);
    Result[0] := '';
  end;
end;

function TabSize(ATabWidth: Integer): Integer;
begin
  Result := Max(1, ATabWidth);
end;

/// <summary>Anzeigespalte (0-basiert, Tabs aufgelöst) vor dem Zeichen ACharacter.</summary>
function DisplayColumn(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 1 to Min(ACharacter, Length(ALine)) do
    if ALine[Index] = #9 then
      Result := (Result div TabSize(ATabWidth) + 1) * TabSize(ATabWidth)
    else
      Inc(Result);
end;

/// <summary>Zeichenindex zur Anzeigespalte AColumn, höchstens das Zeilenende.</summary>
function CharacterAt(const ALine: string; AColumn, ATabWidth: Integer): Integer;
var
  Column: Integer;
begin
  Result := 0;
  Column := 0;
  while (Result < Length(ALine)) and (Column < AColumn) do
  begin
    if ALine[Result + 1] = #9 then
      Column := (Column div TabSize(ATabWidth) + 1) * TabSize(ATabWidth)
    else
      Inc(Column);
    Inc(Result);
  end;
end;

function Overlaps(const A, B: TAtlasCaret): Boolean;
var
  ASL, ASC, AEL, AEC, BSL, BSC, BEL, BEC: Integer;
begin
  if not A.HasSelection and not B.HasSelection then
    Exit((A.Line = B.Line) and (A.Character = B.Character));
  A.Bounds(ASL, ASC, AEL, AEC);
  B.Bounds(BSL, BSC, BEL, BEC);
  Result := (ComparePos(ASL, ASC, BEL, BEC) < 0) and (ComparePos(BSL, BSC, AEL, AEC) < 0);
end;

/// <summary>AKept um AOther erweitert; die Richtung von AKept bleibt.</summary>
function Union(const AKept, AOther: TAtlasCaret): TAtlasCaret;
var
  KSL, KSC, KEL, KEC, OSL, OSC, OEL, OEC: Integer;
  Backward: Boolean;
begin
  AKept.Bounds(KSL, KSC, KEL, KEC);
  AOther.Bounds(OSL, OSC, OEL, OEC);
  if (ComparePos(OSL, OSC, KSL, KSC) >= 0) and (ComparePos(OEL, OEC, KEL, KEC) <= 0) then
    Exit(AKept);
  if ComparePos(OSL, OSC, KSL, KSC) < 0 then
  begin
    KSL := OSL;
    KSC := OSC;
  end;
  if ComparePos(OEL, OEC, KEL, KEC) > 0 then
  begin
    KEL := OEL;
    KEC := OEC;
  end;
  Backward := ComparePos(AKept.Line, AKept.Character, AKept.AnchorLine, AKept.AnchorCharacter) < 0;
  if Backward then
    Result := TAtlasCaret.Range(KEL, KEC, KSL, KSC)
  else
    Result := TAtlasCaret.Range(KSL, KSC, KEL, KEC);
end;

/// <summary>Indizes von ACarets nach dem Anfang ihrer Markierung (Textreihenfolge).</summary>
function TextOrder(const ACarets: TAtlasCarets): TArray<Integer>;
var
  Index, Inner, Value, SL, SC, EL, EC, VL, VC: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ACarets));
  for Index := 0 to High(ACarets) do
    Result[Index] := Index;
  for Index := 1 to High(Result) do
  begin
    Value := Result[Index];
    ACarets[Value].Bounds(VL, VC, EL, EC);
    Inner := Index - 1;
    while Inner >= 0 do
    begin
      ACarets[Result[Inner]].Bounds(SL, SC, EL, EC);
      if ComparePos(SL, SC, VL, VC) <= 0 then
        Break;
      Result[Inner + 1] := Result[Inner];
      Dec(Inner);
    end;
    Result[Inner + 1] := Value;
  end;
end;

/// <summary>Gemeinsamer Anfang und gemeinsames Ende: In AOld wurde [AStart, AStop) durch AInsert ersetzt.
/// </summary>
procedure Difference(const AOld, ANew: string; out AStart, AStop: Integer; out AInsert: string);
var
  Limit, Prefix, Suffix: Integer;
begin
  Limit := Min(Length(AOld), Length(ANew));
  Prefix := 0;
  while (Prefix < Limit) and (AOld[Prefix + 1] = ANew[Prefix + 1]) do
    Inc(Prefix);
  Suffix := 0;
  while (Suffix < Limit - Prefix) and (AOld[Length(AOld) - Suffix] = ANew[Length(ANew) - Suffix]) do
    Inc(Suffix);
  AStart := Prefix;
  AStop := Length(AOld) - Suffix;
  AInsert := Copy(ANew, Prefix + 1, Length(ANew) - Suffix - Prefix);
end;

/// <summary>Neuer Offset für AOffset nach den aufsteigenden Ersetzungen AEdits; in einer Ersetzung hinter dem
/// Eingefügten.</summary>
function MapOffset(const AEdits: TArray<TTextEdit>; AOffset: Integer): Integer;
var
  Edit: TTextEdit;
  Delta: Integer;
begin
  Delta := 0;
  for Edit in AEdits do
    if Edit.Stop <= AOffset then
      Delta := Delta + Length(Edit.Text) - (Edit.Stop - Edit.Start)
    else if Edit.Start < AOffset then
      Exit(Edit.Start + Delta + Length(Edit.Text))
    else
      Break;
  Result := AOffset + Delta;
end;

/// <summary>Wendet AEdits (je höchstens eine Ersetzung pro Marke) auf AText an. Bearbeitete Marken stehen danach
/// hinter ihrem Eingefügten ohne Markierung, die übrigen rücken mit. False, wenn sich nichts ändert.</summary>
function ApplyEdits(const AText: string; const ACarets: TAtlasCarets; const AEdits: TArray<TTextEdit>;
  out ANewText: string; out ANewCarets: TAtlasCarets): Boolean;
var
  Sorted: TArray<TTextEdit>;
  Edit: TTextEdit;
  Edited: TArray<Integer>;
  Index, Inner, Position, Delta, Line, Character, AnchorLine, AnchorCharacter: Integer;
  OldIndex, NewIndex: TLineIndex;
  Caret: TAtlasCaret;
begin
  // Aufsteigend nach Start; Überlappungen auf das Ende der vorigen gekürzt.
  Sorted := Copy(AEdits);
  for Index := 1 to High(Sorted) do
  begin
    Edit := Sorted[Index];
    Inner := Index - 1;
    while (Inner >= 0) and (Sorted[Inner].Start > Edit.Start) do
    begin
      Sorted[Inner + 1] := Sorted[Inner];
      Dec(Inner);
    end;
    Sorted[Inner + 1] := Edit;
  end;
  Result := False;
  for Index := 0 to High(Sorted) do
  begin
    if (Index > 0) and (Sorted[Index].Start < Sorted[Index - 1].Stop) then
      Sorted[Index].Start := Sorted[Index - 1].Stop;
    if Sorted[Index].Stop < Sorted[Index].Start then
      Sorted[Index].Stop := Sorted[Index].Start;
    if (Sorted[Index].Stop > Sorted[Index].Start) or (Sorted[Index].Text <> '') then
      Result := True;
  end;
  ANewText := AText;
  ANewCarets := ACarets;
  if not Result then
    Exit;
  ANewText := '';
  Position := 0;
  Delta := 0;
  Edited := nil;
  SetLength(Edited, Length(ACarets));
  for Index := 0 to High(Edited) do
    Edited[Index] := -1;
  for Index := 0 to High(Sorted) do
  begin
    ANewText := ANewText + Copy(AText, Position + 1, Sorted[Index].Start - Position) + Sorted[Index].Text;
    Position := Sorted[Index].Stop;
    Sorted[Index].NewStop := Sorted[Index].Start + Delta + Length(Sorted[Index].Text);
    Delta := Delta + Length(Sorted[Index].Text) - (Sorted[Index].Stop - Sorted[Index].Start);
    if (Sorted[Index].Caret >= 0) and (Sorted[Index].Caret < Length(Edited)) then
      Edited[Sorted[Index].Caret] := Sorted[Index].NewStop;
  end;
  ANewText := ANewText + Copy(AText, Position + 1, MaxInt);
  OldIndex := TLineIndex.Build(AText);
  NewIndex := TLineIndex.Build(ANewText);
  ANewCarets := nil;
  SetLength(ANewCarets, Length(ACarets));
  for Index := 0 to High(ACarets) do
  begin
    if Edited[Index] >= 0 then
    begin
      NewIndex.Position(Edited[Index], Line, Character);
      Caret := TAtlasCaret.At(Line, Character);
    end
    else
    begin
      Caret := ACarets[Index];
      NewIndex.Position(MapOffset(Sorted, OldIndex.Offset(Caret.Line, Caret.Character)), Line, Character);
      NewIndex.Position(MapOffset(Sorted, OldIndex.Offset(Caret.AnchorLine, Caret.AnchorCharacter)),
        AnchorLine, AnchorCharacter);
      Caret := TAtlasCaret.Range(AnchorLine, AnchorCharacter, Line, Character);
    end;
    ANewCarets[Index] := Caret;
  end;
  ANewCarets := TAtlasMultiCursor.Merge(ANewCarets);
end;

function MakeEdit(AStart, AStop: Integer; const AText: string; ACaret: Integer): TTextEdit;
begin
  Result.Start := AStart;
  Result.Stop := AStop;
  Result.Text := AText;
  Result.Caret := ACaret;
  Result.NewStop := 0;
end;

/// <summary>Zeilenumbrüche in AText auf ALineBreak.</summary>
function WithLineBreak(const AText, ALineBreak: string): string;
begin
  Result := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  if ALineBreak <> #10 then
    Result := StringReplace(Result, #10, ALineBreak, [rfReplaceAll]);
end;

function IsWholeWord(const ALine: string; AStart, ALength: Integer): Boolean;
begin
  Result := ((AStart = 0) or not TTextChars.IsIdentChar(ALine[AStart])) and
    ((AStart + ALength >= Length(ALine)) or not TTextChars.IsIdentChar(ALine[AStart + ALength + 1]));
end;

/// <summary>Überschneidet [AStart, AStop) in ALine eine Markierung von ACarets?</summary>
function Taken(const ACarets: TAtlasCarets; ALine, AStart, AStop: Integer): Boolean;
var
  Caret: TAtlasCaret;
  SL, SC, EL, EC: Integer;
begin
  Result := False;
  for Caret in ACarets do
    if Caret.HasSelection then
    begin
      Caret.Bounds(SL, SC, EL, EC);
      if (ComparePos(ALine, AStart, EL, EC) < 0) and (ComparePos(SL, SC, ALine, AStop) < 0) then
        Exit(True);
    end;
end;

/// <summary>Nächstes Vorkommen von ANeedle ab (AFromLine, AFromCharacter), am Dateiende von vorn; Stellen, die
/// eine Markierung von AExisting überschneiden, zählen nicht.</summary>
function Find(const ALines: TArray<string>; const AExisting: TAtlasCarets; const ANeedle: string;
  AFromLine, AFromCharacter: Integer; AMatchCase, AWholeWord: Boolean; out ALine, ACharacter: Integer): Boolean;
var
  Pass, Line, From, Found: Integer;
  Needle, Hay: string;
begin
  Result := False;
  ALine := 0;
  ACharacter := 0;
  if (ANeedle = '') or (Length(ALines) = 0) then
    Exit;
  Needle := ANeedle;
  if not AMatchCase then
    Needle := AnsiLowerCase(ANeedle);
  for Pass := 0 to Length(ALines) do
  begin
    Line := (EnsureRange(AFromLine, 0, High(ALines)) + Pass) mod Length(ALines);
    From := 0;
    if Pass = 0 then
      From := Max(0, AFromCharacter);
    Hay := ALines[Line];
    if not AMatchCase then
      Hay := AnsiLowerCase(Hay);
    Found := Pos(Needle, Hay, From + 1);
    while Found > 0 do
    begin
      if (not AWholeWord or IsWholeWord(ALines[Line], Found - 1, Length(Needle))) and
        not Taken(AExisting, Line, Found - 1, Found - 1 + Length(Needle)) then
      begin
        ALine := Line;
        ACharacter := Found - 1;
        Exit(True);
      end;
      Found := Pos(Needle, Hay, Found + 1);
    end;
  end;
end;

/// <summary>Wort an oder direkt vor ACharacter.</summary>
function WordAt(const ALine: string; ACharacter: Integer; out AStart, AStop: Integer): Boolean;
var
  Index: Integer;
begin
  AStart := 0;
  AStop := 0;
  Index := EnsureRange(ACharacter, 0, Length(ALine));
  if (Index >= Length(ALine)) or not TTextChars.IsIdentChar(ALine[Index + 1]) then
  begin
    if (Index > 0) and TTextChars.IsIdentChar(ALine[Index]) then
      Dec(Index)
    else
      Exit(False);
  end;
  AStart := Index;
  while (AStart > 0) and TTextChars.IsIdentChar(ALine[AStart]) do
    Dec(AStart);
  AStop := Index + 1;
  while (AStop < Length(ALine)) and TTextChars.IsIdentChar(ALine[AStop + 1]) do
    Inc(AStop);
  Result := True;
end;

/// <summary>Ein Punkt (ALine, ACharacter) nach AMove; AColumn = gewünschte Anzeigespalte (-1 = keine).</summary>
procedure MovePoint(const ALines: TArray<string>; AMove: TAtlasCaretMove; ATabWidth: Integer;
  var ALine, ACharacter, AColumn: Integer);
var
  Text: string;
  Index, Column: Integer;
begin
  ALine := EnsureRange(ALine, 0, High(ALines));
  Text := ALines[ALine];
  ACharacter := EnsureRange(ACharacter, 0, Length(Text));
  Column := AColumn;
  if Column < 0 then
    Column := DisplayColumn(Text, ACharacter, ATabWidth);
  AColumn := -1;
  case AMove of
    TAtlasCaretMove.Left:
      if ACharacter > 0 then
        Dec(ACharacter)
      else if ALine > 0 then
      begin
        Dec(ALine);
        ACharacter := Length(ALines[ALine]);
      end;
    TAtlasCaretMove.Right:
      if ACharacter < Length(Text) then
        Inc(ACharacter)
      else if ALine < High(ALines) then
      begin
        Inc(ALine);
        ACharacter := 0;
      end;
    TAtlasCaretMove.Up:
      begin
        AColumn := Column;
        if ALine = 0 then
          ACharacter := 0
        else
        begin
          Dec(ALine);
          ACharacter := CharacterAt(ALines[ALine], Column, ATabWidth);
        end;
      end;
    TAtlasCaretMove.Down:
      begin
        AColumn := Column;
        if ALine = High(ALines) then
          ACharacter := Length(Text)
        else
        begin
          Inc(ALine);
          ACharacter := CharacterAt(ALines[ALine], Column, ATabWidth);
        end;
      end;
    TAtlasCaretMove.LineStart:
      ACharacter := 0;
    TAtlasCaretMove.LineEnd:
      ACharacter := Length(Text);
    TAtlasCaretMove.WordRight:
      if ACharacter >= Length(Text) then
      begin
        if ALine < High(ALines) then
        begin
          Inc(ALine);
          ACharacter := 0;
        end;
      end
      else
      begin
        Index := ACharacter + 1;
        if TTextChars.IsIdentChar(Text[Index]) then
          while (Index <= Length(Text)) and TTextChars.IsIdentChar(Text[Index]) do
            Inc(Index)
        else if not IsSpace(Text[Index]) then
          while (Index <= Length(Text)) and not TTextChars.IsIdentChar(Text[Index]) and not IsSpace(Text[Index]) do
            Inc(Index);
        while (Index <= Length(Text)) and IsSpace(Text[Index]) do
          Inc(Index);
        ACharacter := Index - 1;
      end;
    TAtlasCaretMove.WordLeft:
      if ACharacter = 0 then
      begin
        if ALine > 0 then
        begin
          Dec(ALine);
          ACharacter := Length(ALines[ALine]);
        end;
      end
      else
      begin
        Index := ACharacter;
        while (Index >= 1) and IsSpace(Text[Index]) do
          Dec(Index);
        if Index >= 1 then
        begin
          if TTextChars.IsIdentChar(Text[Index]) then
            while (Index >= 1) and TTextChars.IsIdentChar(Text[Index]) do
              Dec(Index)
          else
            while (Index >= 1) and not TTextChars.IsIdentChar(Text[Index]) and not IsSpace(Text[Index]) do
              Dec(Index);
        end;
        ACharacter := Index;
      end;
  end;
end;

{ TAtlasCaret }

class function TAtlasCaret.At(ALine, ACharacter: Integer): TAtlasCaret;
begin
  Result := Range(ALine, ACharacter, ALine, ACharacter);
end;

class function TAtlasCaret.Range(AAnchorLine, AAnchorCharacter, ALine, ACharacter: Integer): TAtlasCaret;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.AnchorLine := AAnchorLine;
  Result.AnchorCharacter := AAnchorCharacter;
  Result.Column := -1;
end;

function TAtlasCaret.HasSelection: Boolean;
begin
  Result := (AnchorLine <> Line) or (AnchorCharacter <> Character);
end;

procedure TAtlasCaret.Bounds(out AStartLine, AStartCharacter, AEndLine, AEndCharacter: Integer);
begin
  if ComparePos(AnchorLine, AnchorCharacter, Line, Character) <= 0 then
  begin
    AStartLine := AnchorLine;
    AStartCharacter := AnchorCharacter;
    AEndLine := Line;
    AEndCharacter := Character;
  end
  else
  begin
    AStartLine := Line;
    AStartCharacter := Character;
    AEndLine := AnchorLine;
    AEndCharacter := AnchorCharacter;
  end;
end;

{ TAtlasMultiCursor }

class function TAtlasMultiCursor.Merge(const ACarets: TAtlasCarets): TAtlasCarets;
var
  Kept: TAtlasCarets;
  Caret: TAtlasCaret;
  Index, Found: Integer;
  Changed: Boolean;
begin
  Result := Copy(ACarets);
  repeat
    Changed := False;
    Kept := nil;
    for Caret in Result do
    begin
      Found := -1;
      for Index := 0 to High(Kept) do
        if Overlaps(Kept[Index], Caret) then
        begin
          Found := Index;
          Break;
        end;
      if Found < 0 then
        Kept := Kept + [Caret]
      else
      begin
        Kept[Found] := Union(Kept[Found], Caret);
        Changed := True;
      end;
    end;
    Result := Kept;
  until not Changed;
end;

class function TAtlasMultiCursor.Toggle(const ACarets: TAtlasCarets; ALine, ACharacter: Integer): TAtlasCarets;
var
  Index: Integer;
  Found: Boolean;
begin
  Result := nil;
  Found := False;
  for Index := 0 to High(ACarets) do
    if (Index > 0) and not Found and not ACarets[Index].HasSelection and (ACarets[Index].Line = ALine) and
      (ACarets[Index].Character = ACharacter) then
      Found := True
    else
      Result := Result + [ACarets[Index]];
  if not Found then
    Result := Merge(Result + [TAtlasCaret.At(ALine, ACharacter)]);
end;

class function TAtlasMultiCursor.Move(const ALines: TArray<string>; const ACarets: TAtlasCarets;
  AMove: TAtlasCaretMove; AExtend: Boolean; ATabWidth: Integer): TAtlasCarets;
var
  Lines: TArray<string>;
  Index, Line, Character, Column, SL, SC, EL, EC: Integer;
  Caret: TAtlasCaret;
begin
  Lines := SafeLines(ALines);
  Result := Copy(ACarets);
  for Index := 0 to High(Result) do
  begin
    Caret := Result[Index];
    if not AExtend and Caret.HasSelection and
      ((AMove = TAtlasCaretMove.Left) or (AMove = TAtlasCaretMove.Right)) then
    begin
      Caret.Bounds(SL, SC, EL, EC);
      if AMove = TAtlasCaretMove.Left then
        Result[Index] := TAtlasCaret.At(SL, SC)
      else
        Result[Index] := TAtlasCaret.At(EL, EC);
      Continue;
    end;
    Line := Caret.Line;
    Character := Caret.Character;
    Column := Caret.Column;
    MovePoint(Lines, AMove, ATabWidth, Line, Character, Column);
    if AExtend then
    begin
      Caret.Line := Line;
      Caret.Character := Character;
    end
    else
      Caret := TAtlasCaret.At(Line, Character);
    Caret.Column := Column;
    Result[Index] := Caret;
  end;
  Result := Merge(Result);
end;

class function TAtlasMultiCursor.AddVertical(const ALines: TArray<string>; const ACarets: TAtlasCarets;
  AUp: Boolean; ATabWidth: Integer; out AResult: TAtlasCarets): Boolean;
var
  Lines: TArray<string>;
  Index, Pick, Target, Column: Integer;
  Caret: TAtlasCaret;
  Merged: TAtlasCarets;
begin
  AResult := Copy(ACarets);
  Result := False;
  if Length(ACarets) = 0 then
    Exit;
  Lines := SafeLines(ALines);
  Pick := 0;
  for Index := 1 to High(ACarets) do
    if (AUp and (ACarets[Index].Line < ACarets[Pick].Line)) or
      (not AUp and (ACarets[Index].Line > ACarets[Pick].Line)) then
      Pick := Index;
  Target := ACarets[Pick].Line + 1;
  if AUp then
    Target := ACarets[Pick].Line - 1;
  if (Target < 0) or (Target > High(Lines)) then
    Exit;
  Column := ACarets[Pick].Column;
  if Column < 0 then
    Column := DisplayColumn(Lines[EnsureRange(ACarets[Pick].Line, 0, High(Lines))], ACarets[Pick].Character,
      ATabWidth);
  Caret := TAtlasCaret.At(Target, CharacterAt(Lines[Target], Column, ATabWidth));
  Caret.Column := Column;
  Merged := Merge(ACarets + [Caret]);
  Result := Length(Merged) > Length(ACarets);
  if Result then
    AResult := Merged;
end;

class function TAtlasMultiCursor.LineEnds(const ALines: TArray<string>; const ACaret: TAtlasCaret): TAtlasCarets;
var
  Lines: TArray<string>;
  SL, SC, EL, EC, Line: Integer;
begin
  Lines := SafeLines(ALines);
  Result := nil;
  ACaret.Bounds(SL, SC, EL, EC);
  SL := EnsureRange(SL, 0, High(Lines));
  EL := EnsureRange(EL, 0, High(Lines));
  if (EC = 0) and (EL > SL) then
    Dec(EL);
  for Line := SL to EL do
    Result := Result + [TAtlasCaret.At(Line, Length(Lines[Line]))];
end;

class function TAtlasMultiCursor.NextOccurrence(const ALines: TArray<string>; const ACarets: TAtlasCarets;
  AMatchCase, AWholeWord: Boolean; out AResult: TAtlasCarets): TAtlasOccurrence;
var
  Lines: TArray<string>;
  Last: TAtlasCaret;
  Line, Start, Stop, SL, SC, EL, EC, FoundLine, FoundCharacter: Integer;
  Needle: string;
begin
  AResult := Copy(ACarets);
  Result := TAtlasOccurrence.None;
  if Length(ACarets) = 0 then
    Exit;
  Lines := SafeLines(ALines);
  if (Length(ACarets) = 1) and not ACarets[0].HasSelection then
  begin
    Line := EnsureRange(ACarets[0].Line, 0, High(Lines));
    if WordAt(Lines[Line], ACarets[0].Character, Start, Stop) then
    begin
      AResult := nil;
      AResult := AResult + [TAtlasCaret.Range(Line, Start, Line, Stop)];
      Result := TAtlasOccurrence.WordSelected;
    end;
    Exit;
  end;
  Last := ACarets[High(ACarets)];
  if not Last.HasSelection or (Last.AnchorLine <> Last.Line) or (Last.Line < 0) or (Last.Line > High(Lines)) then
    Exit;
  Last.Bounds(SL, SC, EL, EC);
  Needle := Copy(Lines[SL], SC + 1, EC - SC);
  if Find(Lines, ACarets, Needle, EL, EC, AMatchCase, AWholeWord, FoundLine, FoundCharacter) then
  begin
    AResult := ACarets + [TAtlasCaret.Range(FoundLine, FoundCharacter, FoundLine, FoundCharacter + Length(Needle))];
    Result := TAtlasOccurrence.Added;
  end;
end;

class function TAtlasMultiCursor.SkipOccurrence(const ALines: TArray<string>; const ACarets: TAtlasCarets;
  AMatchCase, AWholeWord: Boolean; out AResult: TAtlasCarets): Boolean;
var
  Lines: TArray<string>;
  Last: TAtlasCaret;
  Rest: TAtlasCarets;
  SL, SC, EL, EC, FoundLine, FoundCharacter: Integer;
  Needle: string;
begin
  AResult := Copy(ACarets);
  Result := Length(ACarets) >= 2;
  if not Result then
    Exit;
  Lines := SafeLines(ALines);
  Last := ACarets[High(ACarets)];
  Rest := Copy(ACarets, 0, High(ACarets));
  AResult := Rest;
  if not Last.HasSelection or (Last.AnchorLine <> Last.Line) or (Last.Line < 0) or (Last.Line > High(Lines)) then
    Exit;
  Last.Bounds(SL, SC, EL, EC);
  Needle := Copy(Lines[SL], SC + 1, EC - SC);
  if Find(Lines, Rest, Needle, EL, EC, AMatchCase, AWholeWord, FoundLine, FoundCharacter) then
    AResult := Rest + [TAtlasCaret.Range(FoundLine, FoundCharacter, FoundLine, FoundCharacter + Length(Needle))];
end;

class function TAtlasMultiCursor.Edit(const AText: string; const ACarets: TAtlasCarets;
  AKind: TAtlasCaretEditKind; const AInsert: string; out ANewText: string; out ANewCarets: TAtlasCarets): Boolean;
var
  Index: TLineIndex;
  Edits: TArray<TTextEdit>;
  Caret, SL, SC, EL, EC, Start, Stop, Indent: Integer;
  LineText: string;
begin
  Index := TLineIndex.Build(AText);
  Edits := nil;
  for Caret := 0 to High(ACarets) do
  begin
    ACarets[Caret].Bounds(SL, SC, EL, EC);
    Start := Index.Offset(SL, SC);
    Stop := Index.Offset(EL, EC);
    case AKind of
      TAtlasCaretEditKind.Insert:
        Edits := Edits + [MakeEdit(Start, Stop, AInsert, Caret)];
      TAtlasCaretEditKind.Backspace:
        if Start < Stop then
          Edits := Edits + [MakeEdit(Start, Stop, '', Caret)]
        else if Start > 0 then
        begin
          if (Start >= 2) and (AText[Start - 1] = #13) and (AText[Start] = #10) then
            Edits := Edits + [MakeEdit(Start - 2, Start, '', Caret)]
          else
            Edits := Edits + [MakeEdit(Start - 1, Start, '', Caret)];
        end;
      TAtlasCaretEditKind.Delete:
        if Start < Stop then
          Edits := Edits + [MakeEdit(Start, Stop, '', Caret)]
        else if Start < Length(AText) then
        begin
          if (AText[Start + 1] = #13) and (Start + 2 <= Length(AText)) and (AText[Start + 2] = #10) then
            Edits := Edits + [MakeEdit(Start, Start + 2, '', Caret)]
          else
            Edits := Edits + [MakeEdit(Start, Start + 1, '', Caret)];
        end;
      TAtlasCaretEditKind.NewLine:
        begin
          SL := EnsureRange(SL, 0, Index.Count - 1);
          LineText := Copy(AText, Index.Starts[SL] + 1, Index.Lengths[SL]);
          Indent := 0;
          while (Indent < Start - Index.Starts[SL]) and (Indent < Length(LineText)) and
            IsSpace(LineText[Indent + 1]) do
            Inc(Indent);
          Edits := Edits + [MakeEdit(Start, Stop, LineBreakOf(AText) + Copy(LineText, 1, Indent), Caret)];
        end;
    end;
  end;
  Result := ApplyEdits(AText, ACarets, Edits, ANewText, ANewCarets);
end;

class function TAtlasMultiCursor.Paste(const AText: string; const ACarets: TAtlasCarets; const AClipboard: string;
  out ANewText: string; out ANewCarets: TAtlasCarets): Boolean;
var
  Index: TLineIndex;
  Parts: TArray<string>;
  Order: TArray<Integer>;
  Edits: TArray<TTextEdit>;
  Rank, SL, SC, EL, EC: Integer;
  LineBreak, Whole, Part: string;
begin
  Index := TLineIndex.Build(AText);
  LineBreak := LineBreakOf(AText);
  Whole := WithLineBreak(AClipboard, LineBreak);
  Parts := PasteParts(AClipboard, Length(ACarets));
  Order := TextOrder(ACarets);
  Edits := nil;
  for Rank := 0 to High(Order) do
  begin
    Part := Whole;
    if (Length(ACarets) > 1) and (Length(Parts) = Length(ACarets)) then
      Part := Parts[Rank];
    ACarets[Order[Rank]].Bounds(SL, SC, EL, EC);
    Edits := Edits + [MakeEdit(Index.Offset(SL, SC), Index.Offset(EL, EC), Part, Order[Rank])];
  end;
  Result := ApplyEdits(AText, ACarets, Edits, ANewText, ANewCarets);
end;

class function TAtlasMultiCursor.PasteParts(const AClipboard: string; ACount: Integer): TArray<string>;
var
  Parts: TArray<string>;
begin
  Parts := Lines(AClipboard);
  if (Length(Parts) > 1) and (Parts[High(Parts)] = '') then
    SetLength(Parts, Length(Parts) - 1);
  if Length(Parts) = ACount then
    Result := Parts
  else
  begin
    Result := nil;
    SetLength(Result, 1);
    Result[0] := AClipboard;
  end;
end;

class function TAtlasMultiCursor.SelectedText(const AText: string; const ACarets: TAtlasCarets;
  const ALineBreak: string): string;
var
  Index: TLineIndex;
  Order: TArray<Integer>;
  Rank, Start, SL, SC, EL, EC: Integer;
  First: Boolean;
begin
  Result := '';
  Index := TLineIndex.Build(AText);
  Order := TextOrder(ACarets);
  First := True;
  for Rank := 0 to High(Order) do
    if ACarets[Order[Rank]].HasSelection then
    begin
      ACarets[Order[Rank]].Bounds(SL, SC, EL, EC);
      Start := Index.Offset(SL, SC);
      if not First then
        Result := Result + ALineBreak;
      Result := Result + Copy(AText, Start + 1, Index.Offset(EL, EC) - Start);
      First := False;
    end;
end;

class function TAtlasMultiCursor.Shift(const AOldText, ANewText: string;
  const ACarets: TAtlasCarets): TAtlasCarets;
var
  OldIndex, NewIndex: TLineIndex;
  Start, Stop, Index, Line, Character, AnchorLine, AnchorCharacter: Integer;
  Insert: string;
  Caret: TAtlasCaret;

  function Moved(AOffset: Integer): Integer;
  begin
    if AOffset < Start then
      Result := AOffset
    else if AOffset >= Stop then
      Result := AOffset + Length(Insert) - (Stop - Start)
    else
      Result := Start + Length(Insert);
  end;

begin
  Result := Copy(ACarets);
  if AOldText = ANewText then
    Exit;
  Difference(AOldText, ANewText, Start, Stop, Insert);
  OldIndex := TLineIndex.Build(AOldText);
  NewIndex := TLineIndex.Build(ANewText);
  for Index := 0 to High(Result) do
  begin
    Caret := Result[Index];
    NewIndex.Position(Moved(OldIndex.Offset(Caret.Line, Caret.Character)), Line, Character);
    NewIndex.Position(Moved(OldIndex.Offset(Caret.AnchorLine, Caret.AnchorCharacter)), AnchorLine, AnchorCharacter);
    Caret.Line := Line;
    Caret.Character := Character;
    Caret.AnchorLine := AnchorLine;
    Caret.AnchorCharacter := AnchorCharacter;
    Result[Index] := Caret;
  end;
  Result := Merge(Result);
end;

class function TAtlasMultiCursor.Mirror(const AOldText, ANewText: string; const ACarets: TAtlasCarets;
  out AText: string; out ANewCarets: TAtlasCarets): Boolean;
var
  Index: TLineIndex;
  Edits: TArray<TTextEdit>;
  Start, Stop, Main, Before, After, Caret, Offset, LineStart, LineStop: Integer;
  Insert, Deleted: string;
begin
  AText := ANewText;
  ANewCarets := Copy(ACarets);
  Result := False;
  if (Length(ACarets) = 0) or ACarets[0].HasSelection or (AOldText = ANewText) then
    Exit;
  Difference(AOldText, ANewText, Start, Stop, Insert);
  Deleted := Copy(AOldText, Start + 1, Stop - Start);
  if (Pos(#10, Deleted) > 0) or (Pos(#13, Deleted) > 0) then
    Exit;
  Index := TLineIndex.Build(AOldText);
  Main := Index.Offset(ACarets[0].Line, ACarets[0].Character);
  if (Main < Start) or (Main > Stop) then
    Exit;
  Before := Main - Start;
  After := Stop - Main;
  Edits := nil;
  Edits := Edits + [MakeEdit(Start, Stop, Insert, 0)];
  for Caret := 1 to High(ACarets) do
    if not ACarets[Caret].HasSelection then
    begin
      Offset := Index.Offset(ACarets[Caret].Line, ACarets[Caret].Character);
      LineStart := Index.Starts[EnsureRange(ACarets[Caret].Line, 0, Index.Count - 1)];
      LineStop := LineStart + Index.Lengths[EnsureRange(ACarets[Caret].Line, 0, Index.Count - 1)];
      Edits := Edits + [MakeEdit(Max(LineStart, Offset - Before), Min(LineStop, Offset + After), Insert, Caret)];
    end;
  ApplyEdits(AOldText, ACarets, Edits, AText, ANewCarets);
  Result := True;
end;

class function TAtlasMultiCursor.Lines(const AText: string): TArray<string>;
var
  Index: TLineIndex;
  Line: Integer;
begin
  Index := TLineIndex.Build(AText);
  Result := nil;
  SetLength(Result, Index.Count);
  for Line := 0 to Index.Count - 1 do
    Result[Line] := Copy(AText, Index.Starts[Line] + 1, Index.Lengths[Line]);
end;

class function TAtlasMultiCursor.LineBreakOf(const AText: string): string;
begin
  Result := TTextLines.LineBreakOf(AText);
end;

end.
