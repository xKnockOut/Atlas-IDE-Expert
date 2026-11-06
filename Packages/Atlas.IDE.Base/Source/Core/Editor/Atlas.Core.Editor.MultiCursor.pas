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
  begin
    if AText[Index] = #10 then
    begin
      Len := Index - 1 - Start;
      if (Len > 0) and (AText[Index - 1] = #13) then
      begin
        Dec(Len);
      end;
      Add(Start, Len);
      Start := Index;
    end;
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
    begin
      Low := Middle;
    end
    else
    begin
      High := Middle - 1;
    end;
  end;
  ALine := Low;
  ACharacter := EnsureRange(AOffset - Starts[Low], 0, Lengths[Low]);
end;

{ Hilfen }

function ComparePos(ALine1, ACharacter1, ALine2, ACharacter2: Integer): Integer;
begin
  if ALine1 <> ALine2 then
  begin
    Result := CompareValue(ALine1, ALine2);
  end
  else
  begin
    Result := CompareValue(ACharacter1, ACharacter2);
  end;
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
  begin
    if ALine[Index] = #9 then
    begin
      Result := (Result div TabSize(ATabWidth) + 1) * TabSize(ATabWidth);
    end
    else
    begin
      Inc(Result);
    end;
  end;
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
    begin
      Column := (Column div TabSize(ATabWidth) + 1) * TabSize(ATabWidth);
    end
    else
    begin
      Inc(Column);
    end;
    Inc(Result);
  end;
end;

function Overlaps(const A, B: TAtlasCaret): Boolean;
var
  ASL, ASC, AEL, AEC, BSL, BSC, BEL, BEC: Integer;
begin
  if not A.HasSelection and not B.HasSelection then
  begin
    Exit((A.Line = B.Line) and (A.Character = B.Character));
  end;
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
  begin
    Exit(AKept);
  end;
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
  begin
    Result := TAtlasCaret.Range(KEL, KEC, KSL, KSC);
  end
  else
  begin
    Result := TAtlasCaret.Range(KSL, KSC, KEL, KEC);
  end;
end;

/// <summary>Indizes von ACarets nach dem Anfang ihrer Markierung (Textreihenfolge).</summary>
function TextOrder(const ACarets: TAtlasCarets): TArray<Integer>;
var
  Index, Inner, Value, SL, SC, EL, EC, VL, VC: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ACarets));
  for Index := 0 to High(ACarets) do
  begin
    Result[Index] := Index;
  end;
  for Index := 1 to High(Result) do
  begin
    Value := Result[Index];
    ACarets[Value].Bounds(VL, VC, EL, EC);
    Inner := Index - 1;
    while Inner >= 0 do
    begin
      ACarets[Result[Inner]].Bounds(SL, SC, EL, EC);
      if ComparePos(SL, SC, VL, VC) <= 0 then
      begin
        Break;
      end;
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
  begin
    Inc(Prefix);
  end;
  Suffix := 0;
  while (Suffix < Limit - Prefix) and (AOld[Length(AOld) - Suffix] = ANew[Length(ANew) - Suffix]) do
  begin
    Inc(Suffix);
  end;
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
  begin
    if Edit.Stop <= AOffset then
    begin
      Delta := Delta + Length(Edit.Text) - (Edit.Stop - Edit.Start);
    end
    else if Edit.Start < AOffset then
    begin
      Exit(Edit.Start + Delta + Length(Edit.Text));
    end
    else
    begin
      Break;
    end;
  end;
  Result := AOffset + Delta;
end;

/// <summary>AEdits aufsteigend nach Start (stabil).</summary>
function SortEdits(const AEdits: TArray<TTextEdit>): TArray<TTextEdit>;
var
  mEdit: TTextEdit;
  mIndex, mInner: Integer;
begin
  Result := Copy(AEdits);
  for mIndex := 1 to High(Result) do
  begin
    mEdit := Result[mIndex];
    mInner := mIndex - 1;
    while (mInner >= 0) and (Result[mInner].Start > mEdit.Start) do
    begin
      Result[mInner + 1] := Result[mInner];
      Dec(mInner);
    end;
    Result[mInner + 1] := mEdit;
  end;
end;

/// <summary>Überlappungen auf das Ende der vorigen Ersetzung kürzen. True, wenn sich etwas ändert.</summary>
function ClipEdits(var AEdits: TArray<TTextEdit>): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(AEdits) do
  begin
    if (mIndex > 0) and (AEdits[mIndex].Start < AEdits[mIndex - 1].Stop) then
    begin
      AEdits[mIndex].Start := AEdits[mIndex - 1].Stop;
    end;
    if AEdits[mIndex].Stop < AEdits[mIndex].Start then
    begin
      AEdits[mIndex].Stop := AEdits[mIndex].Start;
    end;
    Result := Result or (AEdits[mIndex].Stop > AEdits[mIndex].Start) or (AEdits[mIndex].Text <> '');
  end;
end;

/// <summary>Neuer Text nach den aufsteigenden Ersetzungen AEdits; AEdited: neues Ende je bearbeiteter Marke, -1
/// für die übrigen.</summary>
function EditedText(const AText: string; var AEdits: TArray<TTextEdit>; ACaretCount: Integer;
  out AEdited: TArray<Integer>): string;
var
  mIndex, mPosition, mDelta: Integer;
begin
  Result := '';
  mPosition := 0;
  mDelta := 0;
  AEdited := nil;
  SetLength(AEdited, ACaretCount);
  for mIndex := 0 to High(AEdited) do
  begin
    AEdited[mIndex] := -1;
  end;
  for mIndex := 0 to High(AEdits) do
  begin
    Result := Result + Copy(AText, mPosition + 1, AEdits[mIndex].Start - mPosition) + AEdits[mIndex].Text;
    mPosition := AEdits[mIndex].Stop;
    AEdits[mIndex].NewStop := AEdits[mIndex].Start + mDelta + Length(AEdits[mIndex].Text);
    mDelta := mDelta + Length(AEdits[mIndex].Text) - (AEdits[mIndex].Stop - AEdits[mIndex].Start);
    if (AEdits[mIndex].Caret >= 0) and (AEdits[mIndex].Caret < ACaretCount) then
    begin
      AEdited[AEdits[mIndex].Caret] := AEdits[mIndex].NewStop;
    end;
  end;
  Result := Result + Copy(AText, mPosition + 1, MaxInt);
end;

/// <summary>Marke nach den Ersetzungen: bearbeitete hinter ihr Eingefügtes (AEdited >= 0), die übrigen rücken mit.
/// </summary>
function MovedCaret(const ACaret: TAtlasCaret; AEdited: Integer; const AEdits: TArray<TTextEdit>;
  const AOldIndex, ANewIndex: TLineIndex): TAtlasCaret;
var
  mLine, mCharacter, mAnchorLine, mAnchorCharacter: Integer;
begin
  if AEdited >= 0 then
  begin
    ANewIndex.Position(AEdited, mLine, mCharacter);
    Result := TAtlasCaret.At(mLine, mCharacter);
  end
  else
  begin
    ANewIndex.Position(MapOffset(AEdits, AOldIndex.Offset(ACaret.Line, ACaret.Character)), mLine, mCharacter);
    ANewIndex.Position(MapOffset(AEdits, AOldIndex.Offset(ACaret.AnchorLine, ACaret.AnchorCharacter)),
      mAnchorLine, mAnchorCharacter);
    Result := TAtlasCaret.Range(mAnchorLine, mAnchorCharacter, mLine, mCharacter);
  end;
end;

/// <summary>Wendet AEdits (je höchstens eine Ersetzung pro Marke) auf AText an. Bearbeitete Marken stehen danach
/// hinter ihrem Eingefügten ohne Markierung, die übrigen rücken mit. False, wenn sich nichts ändert.</summary>
function ApplyEdits(const AText: string; const ACarets: TAtlasCarets; const AEdits: TArray<TTextEdit>;
  out ANewText: string; out ANewCarets: TAtlasCarets): Boolean;
var
  mSorted: TArray<TTextEdit>;
  mEdited: TArray<Integer>;
  mIndex: Integer;
  mOldIndex, mNewIndex: TLineIndex;
begin
  mSorted := SortEdits(AEdits);
  Result := ClipEdits(mSorted);
  ANewText := AText;
  ANewCarets := ACarets;
  if Result then
  begin
    ANewText := EditedText(AText, mSorted, Length(ACarets), mEdited);
    mOldIndex := TLineIndex.Build(AText);
    mNewIndex := TLineIndex.Build(ANewText);
    ANewCarets := nil;
    SetLength(ANewCarets, Length(ACarets));
    for mIndex := 0 to High(ACarets) do
    begin
      ANewCarets[mIndex] := MovedCaret(ACarets[mIndex], mEdited[mIndex], mSorted, mOldIndex, mNewIndex);
    end;
    ANewCarets := TAtlasMultiCursor.Merge(ANewCarets);
  end;
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
  begin
    Result := StringReplace(Result, #10, ALineBreak, [rfReplaceAll]);
  end;
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
  begin
    if Caret.HasSelection then
    begin
      Caret.Bounds(SL, SC, EL, EC);
      if (ComparePos(ALine, AStart, EL, EC) < 0) and (ComparePos(SL, SC, ALine, AStop) < 0) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

type
  /// <summary>Was Find sucht: Needle ab (FromLine, FromCharacter).</summary>
  TFindQuery = record
    Needle: string;
    FromLine: Integer;
    FromCharacter: Integer;
    MatchCase: Boolean;
    WholeWord: Boolean;
    class function Create(const ANeedle: string; AFromLine, AFromCharacter: Integer; AMatchCase,
      AWholeWord: Boolean): TFindQuery; static;
  end;

class function TFindQuery.Create(const ANeedle: string; AFromLine, AFromCharacter: Integer; AMatchCase,
  AWholeWord: Boolean): TFindQuery;
begin
  Result.Needle := ANeedle;
  Result.FromLine := AFromLine;
  Result.FromCharacter := AFromCharacter;
  Result.MatchCase := AMatchCase;
  Result.WholeWord := AWholeWord;
end;

/// <summary>Erste passende Stelle von AQuery in Zeile ALine ab AFrom (0-basiert); -1 ohne.</summary>
function FindInLine(const ALines: TArray<string>; const AExisting: TAtlasCarets; const AQuery: TFindQuery;
  const ANeedle: string; ALine, AFrom: Integer): Integer;
var
  mHay: string;
  mFound: Integer;
begin
  Result := -1;
  mHay := ALines[ALine];
  if not AQuery.MatchCase then
  begin
    mHay := AnsiLowerCase(mHay);
  end;
  mFound := Pos(ANeedle, mHay, AFrom + 1);
  while (Result < 0) and (mFound > 0) do
  begin
    if (not AQuery.WholeWord or IsWholeWord(ALines[ALine], mFound - 1, Length(ANeedle))) and
      not Taken(AExisting, ALine, mFound - 1, mFound - 1 + Length(ANeedle)) then
    begin
      Result := mFound - 1;
    end;
    mFound := Pos(ANeedle, mHay, mFound + 1);
  end;
end;

/// <summary>Nächstes Vorkommen von AQuery.Needle ab (FromLine, FromCharacter), am Dateiende von vorn; Stellen, die
/// eine Markierung von AExisting überschneiden, zählen nicht.</summary>
function Find(const ALines: TArray<string>; const AExisting: TAtlasCarets; const AQuery: TFindQuery;
  out ALine, ACharacter: Integer): Boolean;
var
  mPass, mFrom: Integer;
  mNeedle: string;
begin
  Result := False;
  ALine := 0;
  ACharacter := 0;
  if (AQuery.Needle <> '') and (Length(ALines) > 0) then
  begin
    mNeedle := AQuery.Needle;
    if not AQuery.MatchCase then
    begin
      mNeedle := AnsiLowerCase(AQuery.Needle);
    end;
    mPass := 0;
    while not Result and (mPass <= Length(ALines)) do
    begin
      ALine := (EnsureRange(AQuery.FromLine, 0, High(ALines)) + mPass) mod Length(ALines);
      mFrom := 0;
      if mPass = 0 then
      begin
        mFrom := Max(0, AQuery.FromCharacter);
      end;
      ACharacter := FindInLine(ALines, AExisting, AQuery, mNeedle, ALine, mFrom);
      Result := ACharacter >= 0;
      Inc(mPass);
    end;
    if not Result then
    begin
      ALine := 0;
      ACharacter := 0;
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
    begin
      Dec(Index);
    end
    else
    begin
      Exit(False);
    end;
  end;
  AStart := Index;
  while (AStart > 0) and TTextChars.IsIdentChar(ALine[AStart]) do
  begin
    Dec(AStart);
  end;
  AStop := Index + 1;
  while (AStop < Length(ALine)) and TTextChars.IsIdentChar(ALine[AStop + 1]) do
  begin
    Inc(AStop);
  end;
  Result := True;
end;

/// <summary>Rücktaste: Markierung löschen, sonst das Zeichen (bzw. #13#10) davor.</summary>
procedure AddBackspace(const AText: string; AStart, AStop, ACaret: Integer; var AEdits: TArray<TTextEdit>);
begin
  if AStart < AStop then
  begin
    AEdits := AEdits + [MakeEdit(AStart, AStop, '', ACaret)];
  end
  else if (AStart >= 2) and (AText[AStart - 1] = #13) and (AText[AStart] = #10) then
  begin
    AEdits := AEdits + [MakeEdit(AStart - 2, AStart, '', ACaret)];
  end
  else if AStart > 0 then
  begin
    AEdits := AEdits + [MakeEdit(AStart - 1, AStart, '', ACaret)];
  end;
end;

/// <summary>Entf: Markierung löschen, sonst das Zeichen (bzw. #13#10) dahinter.</summary>
procedure AddDelete(const AText: string; AStart, AStop, ACaret: Integer; var AEdits: TArray<TTextEdit>);
begin
  if AStart < AStop then
  begin
    AEdits := AEdits + [MakeEdit(AStart, AStop, '', ACaret)];
  end
  else if (AStart + 2 <= Length(AText)) and (AText[AStart + 1] = #13) and (AText[AStart + 2] = #10) then
  begin
    AEdits := AEdits + [MakeEdit(AStart, AStart + 2, '', ACaret)];
  end
  else if AStart < Length(AText) then
  begin
    AEdits := AEdits + [MakeEdit(AStart, AStart + 1, '', ACaret)];
  end;
end;

/// <summary>Zeilenumbruch mit dem Einzug der Zeile ALine bis zum Cursor.</summary>
function NewLineEdit(const AText: string; const AIndex: TLineIndex; ALine, AStart, AStop, ACaret: Integer):
  TTextEdit;
var
  mLine, mIndent: Integer;
  mLineText: string;
begin
  mLine := EnsureRange(ALine, 0, AIndex.Count - 1);
  mLineText := Copy(AText, AIndex.Starts[mLine] + 1, AIndex.Lengths[mLine]);
  mIndent := 0;
  while (mIndent < AStart - AIndex.Starts[mLine]) and (mIndent < Length(mLineText)) and
    IsSpace(mLineText[mIndent + 1]) do
  begin
    Inc(mIndent);
  end;
  Result := MakeEdit(AStart, AStop, TTextLines.LineBreakOf(AText) + Copy(mLineText, 1, mIndent), ACaret);
end;

/// <summary>Spiegel der Ersetzung um die Marke ACaret: ABefore Zeichen davor, AAfter dahinter, in ihrer Zeile.
/// </summary>
function MirrorEdit(const AIndex: TLineIndex; const ACaret: TAtlasCaret; ABefore, AAfter: Integer;
  const AInsert: string; ACaretIndex: Integer): TTextEdit;
var
  mOffset, mLine, mLineStart: Integer;
begin
  mOffset := AIndex.Offset(ACaret.Line, ACaret.Character);
  mLine := EnsureRange(ACaret.Line, 0, AIndex.Count - 1);
  mLineStart := AIndex.Starts[mLine];
  Result := MakeEdit(Max(mLineStart, mOffset - ABefore), Min(mLineStart + AIndex.Lengths[mLine], mOffset + AAfter),
    AInsert, ACaretIndex);
end;

type
  {$SCOPEDENUMS ON}
  TCharClass = (Space, Ident, Symbol);
  {$SCOPEDENUMS OFF}

function ClassOf(AChar: Char): TCharClass;
begin
  if IsSpace(AChar) then
  begin
    Result := TCharClass.Space;
  end
  else if TTextChars.IsIdentChar(AChar) then
  begin
    Result := TCharClass.Ident;
  end
  else
  begin
    Result := TCharClass.Symbol;
  end;
end;

/// <summary>Ab AIndex (1-basiert) in Schritten AStep über Zeichen der Klasse AClass; Ergebnis: erstes Zeichen
/// danach (0 bzw. Length + 1 am Rand).</summary>
function SkipClass(const AText: string; AIndex, AStep: Integer; AClass: TCharClass): Integer;
begin
  Result := AIndex;
  while (Result >= 1) and (Result <= Length(AText)) and (ClassOf(AText[Result]) = AClass) do
  begin
    Inc(Result, AStep);
  end;
end;

procedure MoveLeft(const ALines: TArray<string>; var ALine, ACharacter: Integer);
begin
  if ACharacter > 0 then
  begin
    Dec(ACharacter);
  end
  else if ALine > 0 then
  begin
    Dec(ALine);
    ACharacter := Length(ALines[ALine]);
  end;
end;

procedure MoveRight(const ALines: TArray<string>; var ALine, ACharacter: Integer);
begin
  if ACharacter < Length(ALines[ALine]) then
  begin
    Inc(ACharacter);
  end
  else if ALine < High(ALines) then
  begin
    Inc(ALine);
    ACharacter := 0;
  end;
end;

procedure MoveUp(const ALines: TArray<string>; AColumn, ATabWidth: Integer; var ALine, ACharacter: Integer);
begin
  if ALine = 0 then
  begin
    ACharacter := 0;
  end
  else
  begin
    Dec(ALine);
    ACharacter := CharacterAt(ALines[ALine], AColumn, ATabWidth);
  end;
end;

procedure MoveDown(const ALines: TArray<string>; AColumn, ATabWidth: Integer; var ALine, ACharacter: Integer);
begin
  if ALine = High(ALines) then
  begin
    ACharacter := Length(ALines[ALine]);
  end
  else
  begin
    Inc(ALine);
    ACharacter := CharacterAt(ALines[ALine], AColumn, ATabWidth);
  end;
end;

/// <summary>Hinter das Wort (bzw. die Zeichenfolge) am Cursor und den Leerraum danach; am Zeilenende in die
/// nächste Zeile.</summary>
procedure MoveWordRight(const ALines: TArray<string>; var ALine, ACharacter: Integer);
var
  mText: string;
  mIndex: Integer;
  mClass: TCharClass;
begin
  mText := ALines[ALine];
  if ACharacter >= Length(mText) then
  begin
    if ALine < High(ALines) then
    begin
      Inc(ALine);
      ACharacter := 0;
    end;
  end
  else
  begin
    mIndex := ACharacter + 1;
    mClass := ClassOf(mText[mIndex]);
    if mClass <> TCharClass.Space then
    begin
      mIndex := SkipClass(mText, mIndex, 1, mClass);
    end;
    ACharacter := SkipClass(mText, mIndex, 1, TCharClass.Space) - 1;
  end;
end;

/// <summary>Über Leerraum zurück an den Anfang des Worts (bzw. der Zeichenfolge); am Zeilenanfang in die vorige
/// Zeile.</summary>
procedure MoveWordLeft(const ALines: TArray<string>; var ALine, ACharacter: Integer);
var
  mText: string;
  mIndex: Integer;
begin
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
    mText := ALines[ALine];
    mIndex := SkipClass(mText, ACharacter, -1, TCharClass.Space);
    if mIndex >= 1 then
    begin
      mIndex := SkipClass(mText, mIndex, -1, ClassOf(mText[mIndex]));
    end;
    ACharacter := mIndex;
  end;
end;

/// <summary>Ein Punkt (ALine, ACharacter) nach AMove; AColumn = gewünschte Anzeigespalte (-1 = keine).</summary>
procedure MovePoint(const ALines: TArray<string>; AMove: TAtlasCaretMove; ATabWidth: Integer;
  var ALine, ACharacter, AColumn: Integer);
var
  mColumn: Integer;
begin
  ALine := EnsureRange(ALine, 0, High(ALines));
  ACharacter := EnsureRange(ACharacter, 0, Length(ALines[ALine]));
  mColumn := AColumn;
  if mColumn < 0 then
  begin
    mColumn := DisplayColumn(ALines[ALine], ACharacter, ATabWidth);
  end;
  AColumn := -1;
  case AMove of
    TAtlasCaretMove.Left:
      MoveLeft(ALines, ALine, ACharacter);
    TAtlasCaretMove.Right:
      MoveRight(ALines, ALine, ACharacter);
    TAtlasCaretMove.Up:
      begin
        AColumn := mColumn;
        MoveUp(ALines, mColumn, ATabWidth, ALine, ACharacter);
      end;
    TAtlasCaretMove.Down:
      begin
        AColumn := mColumn;
        MoveDown(ALines, mColumn, ATabWidth, ALine, ACharacter);
      end;
    TAtlasCaretMove.LineStart:
      ACharacter := 0;
    TAtlasCaretMove.LineEnd:
      ACharacter := Length(ALines[ALine]);
    TAtlasCaretMove.WordRight:
      MoveWordRight(ALines, ALine, ACharacter);
    TAtlasCaretMove.WordLeft:
      MoveWordLeft(ALines, ALine, ACharacter);
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
      begin
        if Overlaps(Kept[Index], Caret) then
        begin
          Found := Index;
          Break;
        end;
      end;
      if Found < 0 then
      begin
        Kept := Kept + [Caret];
      end
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
  begin
    if (Index > 0) and not Found and not ACarets[Index].HasSelection and (ACarets[Index].Line = ALine) and
      (ACarets[Index].Character = ACharacter) then
    begin
      Found := True;
    end
    else
    begin
      Result := Result + [ACarets[Index]];
    end;
  end;
  if not Found then
  begin
    Result := Merge(Result + [TAtlasCaret.At(ALine, ACharacter)]);
  end;
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
      begin
        Result[Index] := TAtlasCaret.At(SL, SC);
      end
      else
      begin
        Result[Index] := TAtlasCaret.At(EL, EC);
      end;
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
    begin
      Caret := TAtlasCaret.At(Line, Character);
    end;
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
  begin
    Exit;
  end;
  Lines := SafeLines(ALines);
  Pick := 0;
  for Index := 1 to High(ACarets) do
  begin
    if (AUp and (ACarets[Index].Line < ACarets[Pick].Line)) or
      (not AUp and (ACarets[Index].Line > ACarets[Pick].Line)) then
    begin
      Pick := Index;
    end;
  end;
  Target := ACarets[Pick].Line + 1;
  if AUp then
  begin
    Target := ACarets[Pick].Line - 1;
  end;
  if (Target < 0) or (Target > High(Lines)) then
  begin
    Exit;
  end;
  Column := ACarets[Pick].Column;
  if Column < 0 then
  begin
    Column := DisplayColumn(Lines[EnsureRange(ACarets[Pick].Line, 0, High(Lines))], ACarets[Pick].Character,
      ATabWidth);
  end;
  Caret := TAtlasCaret.At(Target, CharacterAt(Lines[Target], Column, ATabWidth));
  Caret.Column := Column;
  Merged := Merge(ACarets + [Caret]);
  Result := Length(Merged) > Length(ACarets);
  if Result then
  begin
    AResult := Merged;
  end;
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
  begin
    Dec(EL);
  end;
  for Line := SL to EL do
  begin
    Result := Result + [TAtlasCaret.At(Line, Length(Lines[Line]))];
  end;
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
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  Last.Bounds(SL, SC, EL, EC);
  Needle := Copy(Lines[SL], SC + 1, EC - SC);
  if Find(Lines, ACarets, TFindQuery.Create(Needle, EL, EC, AMatchCase, AWholeWord), FoundLine,
    FoundCharacter) then
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
  begin
    Exit;
  end;
  Lines := SafeLines(ALines);
  Last := ACarets[High(ACarets)];
  Rest := Copy(ACarets, 0, High(ACarets));
  AResult := Rest;
  if not Last.HasSelection or (Last.AnchorLine <> Last.Line) or (Last.Line < 0) or (Last.Line > High(Lines)) then
  begin
    Exit;
  end;
  Last.Bounds(SL, SC, EL, EC);
  Needle := Copy(Lines[SL], SC + 1, EC - SC);
  if Find(Lines, Rest, TFindQuery.Create(Needle, EL, EC, AMatchCase, AWholeWord), FoundLine,
    FoundCharacter) then
  begin
    AResult := Rest + [TAtlasCaret.Range(FoundLine, FoundCharacter, FoundLine, FoundCharacter + Length(Needle))];
  end;
end;

class function TAtlasMultiCursor.Edit(const AText: string; const ACarets: TAtlasCarets;
  AKind: TAtlasCaretEditKind; const AInsert: string; out ANewText: string; out ANewCarets: TAtlasCarets): Boolean;
var
  mIndex: TLineIndex;
  mEdits: TArray<TTextEdit>;
  mCaret, mSL, mSC, mEL, mEC, mStart, mStop: Integer;
begin
  mIndex := TLineIndex.Build(AText);
  mEdits := nil;
  for mCaret := 0 to High(ACarets) do
  begin
    ACarets[mCaret].Bounds(mSL, mSC, mEL, mEC);
    mStart := mIndex.Offset(mSL, mSC);
    mStop := mIndex.Offset(mEL, mEC);
    case AKind of
      TAtlasCaretEditKind.Insert:
        mEdits := mEdits + [MakeEdit(mStart, mStop, AInsert, mCaret)];
      TAtlasCaretEditKind.Backspace:
        AddBackspace(AText, mStart, mStop, mCaret, mEdits);
      TAtlasCaretEditKind.Delete:
        AddDelete(AText, mStart, mStop, mCaret, mEdits);
      TAtlasCaretEditKind.NewLine:
        mEdits := mEdits + [NewLineEdit(AText, mIndex, mSL, mStart, mStop, mCaret)];
    end;
  end;
  Result := ApplyEdits(AText, ACarets, mEdits, ANewText, ANewCarets);
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
    begin
      Part := Parts[Rank];
    end;
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
  begin
    SetLength(Parts, Length(Parts) - 1);
  end;
  if Length(Parts) = ACount then
  begin
    Result := Parts;
  end
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
  begin
    if ACarets[Order[Rank]].HasSelection then
    begin
      ACarets[Order[Rank]].Bounds(SL, SC, EL, EC);
      Start := Index.Offset(SL, SC);
      if not First then
      begin
        Result := Result + ALineBreak;
      end;
      Result := Result + Copy(AText, Start + 1, Index.Offset(EL, EC) - Start);
      First := False;
    end;
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
    begin
      Result := AOffset;
    end
    else if AOffset >= Stop then
    begin
      Result := AOffset + Length(Insert) - (Stop - Start);
    end
    else
    begin
      Result := Start + Length(Insert);
    end;
  end;

begin
  Result := Copy(ACarets);
  if AOldText = ANewText then
  begin
    Exit;
  end;
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
  Start, Stop, Main, Before, After, Caret: Integer;
  Insert, Deleted: string;
begin
  AText := ANewText;
  ANewCarets := Copy(ACarets);
  Result := False;
  if (Length(ACarets) = 0) or ACarets[0].HasSelection or (AOldText = ANewText) then
  begin
    Exit;
  end;
  Difference(AOldText, ANewText, Start, Stop, Insert);
  Deleted := Copy(AOldText, Start + 1, Stop - Start);
  if (Pos(#10, Deleted) > 0) or (Pos(#13, Deleted) > 0) then
  begin
    Exit;
  end;
  Index := TLineIndex.Build(AOldText);
  Main := Index.Offset(ACarets[0].Line, ACarets[0].Character);
  if (Main < Start) or (Main > Stop) then
  begin
    Exit;
  end;
  Before := Main - Start;
  After := Stop - Main;
  Edits := nil;
  Edits := Edits + [MakeEdit(Start, Stop, Insert, 0)];
  for Caret := 1 to High(ACarets) do
  begin
    if not ACarets[Caret].HasSelection then
    begin
      Edits := Edits + [MirrorEdit(Index, ACarets[Caret], Before, After, Insert, Caret)];
    end;
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
  begin
    Result[Line] := Copy(AText, Index.Starts[Line] + 1, Index.Lengths[Line]);
  end;
end;

class function TAtlasMultiCursor.LineBreakOf(const AText: string): string;
begin
  Result := TTextLines.LineBreakOf(AText);
end;

end.
