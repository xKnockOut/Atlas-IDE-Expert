unit Atlas.Core.Outline.StickyScroll;

// Mitlaufender Kopf (#506), Kern ohne VCL und OTA:
// - Blöcke sind Klassen, Records, Interfaces und Objekte sowie Routinen mit
//   Rumpf (Methodenrümpfe, Routinen der Unit, verschachtelte Routinen) aus
//   der Gliederung (TAtlasOutline.FromJson). Deklarationen in Typen und im
//   interface sind keine Blöcke.
// - Scopes wählt die Blöcke, deren Kopf oben aus dem Bild ist und die die
//   erste Zeile unter dem Kopf noch umschließen, die äußeren zuerst. Im
//   Rumpf der äußeren Routine nach inneren Routinen steht nur ihr Kopf, weil
//   die inneren die Zeile nicht umschließen.
// - Rows macht daraus höchstens AMaxLines Zeilen: Bei tieferer Verschachtelung
//   bleiben die inneren Ebenen einzeln sichtbar, die äußeren werden zu einer
//   Zeile „A › B › C“ zusammengefasst. Mehrzeilige Köpfe kürzt Header auf eine
//   Zeile (Parameterliste „(…)“).
// - Zusätzliche Blöcke (#1230): große Anweisungsblöcke (aus der Paaranalyse,
//   ausgewählt vom Aufrufer) zählen wie Routinen; ihr Kopf ist die Zeile des
//   Besitzerworts (if, else, for …) ohne Einrückung. Alle Ebenen sind nach
//   ihrer Kopfzeile geordnet, die äußeren zuerst.
// - Arten (TAtlasStickyKind): Welche Blöcke eine Kopfzeile bekommen, wählt der
//   Aufrufer; Typen und Routinen filtert Rows, die Anweisungsblöcke ordnet
//   OwnerKind ihrem Besitzerwort zu.
// - Blocklinien im Kopf (GuideStart): Eine Linie beginnt mit ihrem Haken in
//   der Kopfzeile ihres Elements. Hat das Element keine Kopfzeile (Art aus,
//   zu kurz oder zusammengefasst), blendet sie in der letzten Kopfzeile von
//   oben ein (FadeWeight), statt ohne Anfang unter der Trennlinie aufzutauchen.
// - Hover über dem Kopf: SourceIndex ordnet ein Zeichen der Kopfzeile dem
//   Quelltext zu, den sie zeigt; der Hover meint dann diesen statt der
//   verdeckten Zeile darunter.

interface

uses
  Atlas.Core.Outline.Model;

type
  TAtlasStickyRow = record
    /// <summary>Kopfzeile ohne Einrückung oder die Zusammenfassung.</summary>
    Text: string;
    /// <summary>Sprungziel (0-basiert): der Name im Kopf; bei der Zusammenfassung der innerste Block in
    /// ihr.</summary>
    Line: Integer;
    Character: Integer;
    /// <summary>Einrückung des Kopfs in Spalten (Tabulatoren ausgerechnet); 0 bei der Zusammenfassung.</summary>
    Indent: Integer;
    Summary: Boolean;
  end;

  TAtlasStickyRows = TArray<TAtlasStickyRow>;

  {$SCOPEDENUMS ON}
  /// <summary>Art eines Stücks der Kopfzeile für die Hervorhebung wie im Editor (Elemente des Farbschemas).
  /// </summary>
  TAtlasStickySyntax = (Plain, Reserved, Identifier, Number, StringLiteral, Character, Comment, Symbol,
    Preprocessor);
  /// <summary>Art eines Blocks mit eigener Kopfzeile: Klasse, Record, Interface, Objekt; Routine; if/else;
  /// for/while/repeat; try; case; with.</summary>
  TAtlasStickyKind = (Types, Routines, Branches, Loops, TryBlocks, CaseBlocks, WithBlocks);
  {$SCOPEDENUMS OFF}

  TAtlasStickyKinds = set of TAtlasStickyKind;

  /// <summary>Stück der Kopfzeile; Start 1-basiert.</summary>
  TAtlasStickyToken = record
    Start: Integer;
    Length: Integer;
    Kind: TAtlasStickySyntax;
  end;

  /// <summary>Zusätzlicher Block (#1230): Kopf in Zeile Line (Sprungziel Character), endet in EndLine; 0-basiert.
  /// </summary>
  TAtlasStickyBlock = record
    Line: Integer;
    Character: Integer;
    EndLine: Integer;
    class function Create(ALine, ACharacter, AEndLine: Integer): TAtlasStickyBlock; static;
  end;

  /// <summary>Quelle des Kopfs: Gliederung Nodes, Zeilen Lines, weitere Blöcke Blocks (#1230) und die Arten Kinds,
  /// deren Blöcke der Gliederung zählen.</summary>
  TAtlasStickySource = record
    Nodes: TAtlasOutlineNodes;
    Lines: TArray<string>;
    Blocks: TArray<TAtlasStickyBlock>;
    Kinds: TAtlasStickyKinds;
    class function Create(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      const ABlocks: TArray<TAtlasStickyBlock>; AKinds: TAtlasStickyKinds): TAtlasStickySource; static;
  end;

  /// <summary>Wo eine Blocklinie im Kopf beginnt: in Kopfzeile Row (0-basiert) mit Haken; bei FadeIn hat ihr
  /// Element keine Kopfzeile, und sie blendet in Row (der letzten) ein. Row = -1 ohne Kopf.</summary>
  TAtlasStickyGuideStart = record
    Row: Integer;
    FadeIn: Boolean;
  end;

  TAtlasStickyScroll = class
  public const
    cMaxMaxLines = 10;
    cSeparator = ' › ';
    /// <summary>So viele Zeilen sucht Header nach der schließenden Klammer.</summary>
    cHeaderSearchLines = 30;
    /// <summary>Arten ohne Auswahl: Typen und Routinen der Gliederung.</summary>
    cOutlineKinds = [TAtlasStickyKind.Types, TAtlasStickyKind.Routines];
  public
    /// <summary>Klasse, Record, Interface oder Objekt; Routine mit Rumpf.</summary>
    class function IsBlock(const ANode: TAtlasOutlineNode): Boolean; overload; static;
    /// <summary>Wie oben, nur Arten aus AKinds (Types, Routines).</summary>
    class function IsBlock(const ANode: TAtlasOutlineNode; AKinds: TAtlasStickyKinds): Boolean; overload; static;
    /// <summary>Art eines Anweisungsblocks nach seinem ersten Besitzerwort (klein): if/else, for/while/repeat, try,
    /// case, with; False für andere (begin, asm, on …).</summary>
    class function OwnerKind(const AOwner: string; out AKind: TAtlasStickyKind): Boolean; static;
    /// <summary>Blöcke, die ALine (0-basiert) umschließen und deren Kopf darüber steht; die äußeren zuerst.</summary>
    class function Chain(const ANodes: TAtlasOutlineNodes; ALine: Integer): TArray<Integer>; static;
    /// <summary>Blöcke für den Kopf, wenn ATopLine (0-basiert) die oberste sichtbare Zeile ist: die Blöcke der
    /// ersten Zeile unter dem Kopf (die Zahl der Kopfzeilen höchstens AMaxLines).</summary>
    class function Scopes(const ANodes: TAtlasOutlineNodes; ATopLine, AMaxLines: Integer): TArray<Integer>; static;
    /// <summary>Kopfzeile des Blocks ohne Einrückung; mehrzeilige Parameterlisten als „(…)“.</summary>
    class function Header(const ALines: TArray<string>; const ANode: TAtlasOutlineNode): string; static;
    /// <summary>Zeichenindex (0-basiert) in der Quellzeile ALine, den die Kopfzeile ARow an ihrem Zeichen AOffset
    /// (0-basiert, ohne Einrückung) zeigt. False, wo der Kopf nicht Zeichen für Zeichen die Zeile zeigt:
    /// Zusammenfassung, vor oder hinter dem Text, gekürzte Parameterliste „(…)“, Tabulator, geänderte Zeile.
    /// </summary>
    class function SourceIndex(const ARow: TAtlasStickyRow; const ALine: string; AOffset: Integer;
      out AIndex: Integer): Boolean; static;
    /// <summary>Breite der Einrückung in Spalten (Tabulatoren bis zum nächsten Vielfachen von ATabWidth).</summary>
    class function IndentColumns(const ALine: string; ATabWidth: Integer): Integer; static;
    /// <summary>Zeilen des Kopfs, höchstens AMaxLines (mindestens eine).</summary>
    class function Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ATopLine, AMaxLines,
      ATabWidth: Integer): TAtlasStickyRows; overload; static;
    /// <summary>Wie oben, dazu die Blöcke ABlocks (#1230) als weitere Ebenen.</summary>
    class function Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      const ABlocks: TArray<TAtlasStickyBlock>; ATopLine, AMaxLines, ATabWidth: Integer): TAtlasStickyRows; overload;
      static;
    /// <summary>Wie oben aus ASource; von der Gliederung nur Blöcke der Arten ASource.Kinds.</summary>
    class function Rows(const ASource: TAtlasStickySource; ATopLine, AMaxLines,
      ATabWidth: Integer): TAtlasStickyRows; overload; static;
    /// <summary>Wie oben mit Tabulatorbreite 8.</summary>
    class function Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ATopLine,
      AMaxLines: Integer): TAtlasStickyRows; overload; static;
    /// <summary>Zeilen auf AMaxLines begrenzt (mindestens 1, höchstens MaxMaxLines).</summary>
    class function ClampLines(AMaxLines: Integer): Integer; static;
    /// <summary>Kopfzeile in Stücke wie die Hervorhebung des Editors: reservierte Wörter und Direktiven einer
    /// Deklaration, Bezeichner, Zahlen, Strings, Zeichen (#13), Kommentare, Compilerdirektiven, Symbole. Lücken
    /// (Leerzeichen) bleiben Plain. Lückenlos, in Textreihenfolge.</summary>
    class function Syntax(const AText: string): TArray<TAtlasStickyToken>; static;
    /// <summary>Reserviertes Wort oder Direktive, die der Editor fett zeigt (procedure, const, string, override …).
    /// </summary>
    class function IsReserved(const AWord: string): Boolean; static;
    /// <summary>Beginn der Blocklinie, deren Element in AFirstLine (0-basiert) steht: die Kopfzeile des Elements
    /// (keine Zusammenfassung), sonst eingeblendet in der letzten Kopfzeile.</summary>
    class function GuideStart(const ARows: TAtlasStickyRows; AFirstLine: Integer): TAtlasStickyGuideStart; static;
    /// <summary>Deckkraft (0 bis 1) einer eingeblendeten Linie in Pixelzeile AOffset (0 = oben) einer Kopfzeile der
    /// Höhe AHeight: von fast 0 oben bis 1 in der untersten Pixelzeile, dazwischen weich (quadratisch).</summary>
    class function FadeWeight(AOffset, AHeight: Integer): Double; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Chars,
  Atlas.Text.Lines;

const
  cKindClass = 5;
  cKindMethod = 6;
  cKindConstructor = 9;
  cKindInterface = 11;
  cKindFunction = 12;
  cKindObject = 19;
  cKindStruct = 23;
  cDefaultTabWidth = 8;

class function TAtlasStickyScroll.ClampLines(AMaxLines: Integer): Integer;
begin
  Result := EnsureRange(AMaxLines, 1, cMaxMaxLines);
end;

class function TAtlasStickyScroll.IsBlock(const ANode: TAtlasOutlineNode): Boolean;
begin
  case ANode.Category of
    TAtlasOutlineCategory.TypeDecl:
      Result := ANode.Kind in [cKindClass, cKindInterface, cKindObject, cKindStruct];
    TAtlasOutlineCategory.Routine:
      Result := ANode.Kind in [cKindMethod, cKindConstructor, cKindFunction];
  else
    Result := False;
  end;
end;

class function TAtlasStickyScroll.IsBlock(const ANode: TAtlasOutlineNode; AKinds: TAtlasStickyKinds): Boolean;
begin
  Result := IsBlock(ANode);
  if not Result then
  begin
    Exit;
  end;
  if ANode.Category = TAtlasOutlineCategory.TypeDecl then
  begin
    Result := TAtlasStickyKind.Types in AKinds;
  end
  else
  begin
    Result := TAtlasStickyKind.Routines in AKinds;
  end;
end;

class function TAtlasStickyScroll.OwnerKind(const AOwner: string; out AKind: TAtlasStickyKind): Boolean;
begin
  Result := True;
  AKind := TAtlasStickyKind.Branches;
  if (AOwner = 'if') or (AOwner = 'else') then
  begin
    AKind := TAtlasStickyKind.Branches;
  end
  else if (AOwner = 'for') or (AOwner = 'while') or (AOwner = 'repeat') then
  begin
    AKind := TAtlasStickyKind.Loops;
  end
  else if AOwner = 'try' then
  begin
    AKind := TAtlasStickyKind.TryBlocks;
  end
  else if AOwner = 'case' then
  begin
    AKind := TAtlasStickyKind.CaseBlocks;
  end
  else if AOwner = 'with' then
  begin
    AKind := TAtlasStickyKind.WithBlocks;
  end
  else
  begin
    Result := False;
  end;
end;

class function TAtlasStickyScroll.Chain(const ANodes: TAtlasOutlineNodes; ALine: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  // Kinder stehen hinter ihren Eltern: die Reihenfolge ist schon von außen nach innen.
  for mIndex := 0 to High(ANodes) do
  begin
    if IsBlock(ANodes[mIndex]) and (ANodes[mIndex].NameLine < ALine) and (ALine <= ANodes[mIndex].EndLine) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

class function TAtlasStickyScroll.Scopes(const ANodes: TAtlasOutlineNodes; ATopLine,
  AMaxLines: Integer): TArray<Integer>;
var
  mShown, mMaxLines: Integer;
begin
  mMaxLines := ClampLines(AMaxLines);
  ATopLine := Max(0, ATopLine);
  // Mit Shown Kopfzeilen ist ATopLine + Shown die erste lesbare Zeile; die kleinste Zahl, die reicht, gilt.
  for mShown := 0 to mMaxLines do
  begin
    Result := Chain(ANodes, ATopLine + mShown);
    if Min(Length(Result), mMaxLines) <= mShown then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Öffnende Klammer an APosition: merkt die äußerste.</summary>
procedure OpenParen(APosition: Integer; var ADepth, AOpen: Integer);
begin
  if ADepth = 0 then
  begin
    AOpen := APosition;
  end;
  Inc(ADepth);
end;

/// <summary>Schließende Klammer an APosition: AClose ist die erste Stelle, an der die Tiefe auf 0 fällt.</summary>
procedure CloseParen(APosition: Integer; var ADepth, AOpen, AClose: Integer);
begin
  if ADepth = 0 then
  begin
    Exit;
  end;
  Dec(ADepth);
  if ADepth > 0 then
  begin
    Exit;
  end;
  AOpen := 0;
  if AClose = 0 then
  begin
    AClose := APosition;
  end;
end;

/// <summary>Klammertiefe nach der Zeile, ab AFrom; Zeichenketten und //-Kommentare zählen nicht. AOpen ist die
/// Stelle der äußersten offenen Klammer (0 = keine), AClose die Stelle, an der die Tiefe auf 0 fällt.</summary>
procedure Scan(const ALine: string; var ADepth: Integer; out AOpen, AClose: Integer);
var
  mPosition: Integer;
  mInString: Boolean;
begin
  AOpen := 0;
  AClose := 0;
  mInString := False;
  mPosition := 1;
  while mPosition <= Length(ALine) do
  begin
    if mInString then
    begin
      mInString := ALine[mPosition] <> '''';
    end
    else if (ALine[mPosition] = '/') and (Copy(ALine, mPosition + 1, 1) = '/') then
    begin
      Break;
    end
    else
      case ALine[mPosition] of
        '''':
          mInString := True;
        '(':
          OpenParen(mPosition, ADepth, AOpen);
        ')':
          CloseParen(mPosition, ADepth, AOpen, AClose);
      end;
    Inc(mPosition);
  end;
end;

class function TAtlasStickyScroll.Header(const ALines: TArray<string>; const ANode: TAtlasOutlineNode): string;
var
  mDepth, mOpen, mClose, mIndex, mLast: Integer;
  mLine: string;
begin
  if (ANode.NameLine < 0) or (ANode.NameLine > High(ALines)) then
  begin
    Exit(ANode.Name);
  end;
  mLine := Trim(ALines[ANode.NameLine]);
  mDepth := 0;
  Scan(mLine, mDepth, mOpen, mClose);
  if mDepth <= 0 then
  begin
    Exit(mLine);
  end;
  // Parameterliste über mehrere Zeilen: bis zur offenen Klammer, dann „…“ und der Rest nach der schließenden.
  Result := Copy(mLine, 1, mOpen) + '…';
  mLast := Min(High(ALines), Min(ANode.EndLine, ANode.NameLine + cHeaderSearchLines));
  for mIndex := ANode.NameLine + 1 to mLast do
  begin
    mLine := Trim(ALines[mIndex]);
    Scan(mLine, mDepth, mOpen, mClose);
    if mDepth <= 0 then
    begin
      Exit(Result + Copy(mLine, mClose, MaxInt));
    end;
  end;
  Result := Result + ')';
end;

class function TAtlasStickyScroll.SourceIndex(const ARow: TAtlasStickyRow; const ALine: string; AOffset: Integer;
  out AIndex: Integer): Boolean;
var
  mIndent, mPos: Integer;
begin
  AIndex := -1;
  Result := False;
  if ARow.Summary or (AOffset < 0) or (AOffset >= Length(ARow.Text)) then
  begin
    Exit;
  end;
  // Der Kopf ist die Zeile ohne Einrückung (Header, BlockText): bis einschließlich AOffset muss er ihr gleichen.
  // Ein Tabulator im Text stünde im Kopf schmaler als im Editor, danach passten die Spalten nicht mehr.
  mIndent := Length(ALine) - Length(TrimLeft(ALine));
  for mPos := 1 to AOffset + 1 do
  begin
    if (mIndent + mPos > Length(ALine)) or (ARow.Text[mPos] <> ALine[mIndent + mPos]) or (ARow.Text[mPos] = #9) then
    begin
      Exit;
    end;
  end;
  AIndex := mIndent + AOffset;
  Result := True;
end;

class function TAtlasStickyScroll.IndentColumns(const ALine: string; ATabWidth: Integer): Integer;
var
  mIndent: Char;
begin
  Result := 0;
  ATabWidth := Max(1, ATabWidth);
  for mIndent in TTextLines.IndentOf(ALine) do
  begin
    if mIndent = #9 then
    begin
      Result := (Result div ATabWidth + 1) * ATabWidth;
    end
    else
    begin
      Inc(Result);
    end;
  end;
end;

function HeaderRow(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ANode,
  ATabWidth: Integer): TAtlasStickyRow;
begin
  Result.Text := TAtlasStickyScroll.Header(ALines, ANodes[ANode]);
  Result.Line := ANodes[ANode].NameLine;
  Result.Character := ANodes[ANode].NameCharacter;
  Result.Indent := 0;
  if (Result.Line >= 0) and (Result.Line <= High(ALines)) then
  begin
    Result.Indent := TAtlasStickyScroll.IndentColumns(ALines[Result.Line], ATabWidth);
  end;
  Result.Summary := False;
end;

class function TAtlasStickyScroll.IsReserved(const AWord: string): Boolean;
const
  // Reservierte Wörter von Delphi und die Direktiven in Köpfen. Mehrdeutige Direktiven (index, name, read, write,
  // default, message …) fehlen: Als Bezeichner zeigt sie der Editor nicht fett.
  cWords: array[0..98] of string = ('and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except', 'exports', 'file',
    'finalization', 'finally', 'for', 'function', 'goto', 'if', 'implementation', 'in', 'inherited',
    'initialization', 'inline', 'interface', 'is', 'label', 'library', 'mod', 'nil', 'not', 'object', 'of', 'or',
    'packed', 'procedure', 'program', 'property', 'raise', 'record', 'repeat', 'resourcestring', 'set', 'shl', 'shr',
    'string', 'then', 'threadvar', 'to', 'try', 'type', 'unit', 'until', 'uses', 'var', 'while', 'with', 'xor',
    'operator', 'out', 'absolute', 'abstract', 'assembler', 'automated', 'cdecl', 'deprecated', 'dynamic',
    'experimental', 'external', 'final', 'forward', 'overload', 'override', 'pascal', 'platform', 'private',
    'protected', 'public', 'published', 'register', 'reintroduce', 'safecall', 'sealed', 'static', 'stdcall',
    'strict', 'unsafe', 'varargs', 'virtual', 'winapi', 'delayed', 'reference', 'helper');
var
  mLower, mWord: string;
begin
  mLower := LowerCase(AWord);
  for mWord in cWords do
  begin
    if mWord = mLower then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function CharAt(const AText: string; APos: Integer): Char;
begin
  if APos <= Length(AText) then
  begin
    Result := AText[APos];
  end
  else
  begin
    Result := #0;
  end;
end;

/// <summary>Bis hinter ACloser (oder Zeilenende).</summary>
function SkipTo(const AText: string; AFrom: Integer; const ACloser: string): Integer;
begin
  Result := Pos(ACloser, AText, AFrom);
  if Result = 0 then
  begin
    Result := Length(AText) + 1;
  end
  else
  begin
    Inc(Result, Length(ACloser));
  end;
end;

/// <summary>Kommentar oder Compilerdirektive ab AIndex: Ende in AEnd; False, wenn dort keiner beginnt.</summary>
function CommentToken(const AText: string; AIndex: Integer; out AEnd: Integer;
  out AKind: TAtlasStickySyntax): Boolean;
begin
  Result := True;
  AKind := TAtlasStickySyntax.Comment;
  if AText[AIndex] = '{' then
  begin
    AEnd := SkipTo(AText, AIndex + 1, '}');
    if CharAt(AText, AIndex + 1) = '$' then
    begin
      AKind := TAtlasStickySyntax.Preprocessor;
    end;
  end
  else if (AText[AIndex] = '(') and (CharAt(AText, AIndex + 1) = '*') then
  begin
    AEnd := SkipTo(AText, AIndex + 2, '*)');
    if CharAt(AText, AIndex + 2) = '$' then
    begin
      AKind := TAtlasStickySyntax.Preprocessor;
    end;
  end
  else if (AText[AIndex] = '/') and (CharAt(AText, AIndex + 1) = '/') then
  begin
    AEnd := Length(AText) + 1;
  end
  else
  begin
    AEnd := AIndex;
    Result := False;
  end;
end;

/// <summary>Ende des Strings ab dem Hochkomma an AIndex; '' im String ist ein Hochkomma.</summary>
function StringEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while Result <= Length(AText) do
  begin
    if AText[Result] = '''' then
    begin
      if CharAt(AText, Result + 1) <> '''' then
      begin
        Break;
      end;
      Inc(Result);
    end;
    Inc(Result);
  end;
  if Result <= Length(AText) then
  begin
    Inc(Result);
  end;
end;

/// <summary>Ende der Folge ab AIndex aus Zeichen in AChars.</summary>
function RunEnd(const AText: string; AIndex: Integer; const AChars: TSysCharSet): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and CharInSet(AText[Result], AChars) do
  begin
    Inc(Result);
  end;
end;

function IsNumberStart(const AText: string; AIndex: Integer): Boolean;
begin
  Result := CharInSet(AText[AIndex], ['0'..'9']) or
    ((AText[AIndex] = '$') and CharInSet(CharAt(AText, AIndex + 1), ['0'..'9', 'a'..'f', 'A'..'F'])) or
    ((AText[AIndex] = '%') and CharInSet(CharAt(AText, AIndex + 1), ['0', '1']));
end;

/// <summary>Ende der Zahl ab AIndex (hex, binär, mit Exponent).</summary>
function NumberEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= Length(AText)) and (CharInSet(AText[Result], ['0'..'9', 'a'..'f', 'A'..'F', '_', '.']) or
    (CharInSet(AText[Result], ['+', '-']) and CharInSet(AText[Result - 1], ['e', 'E']))) do
  begin
    Inc(Result);
  end;
end;

function IdentEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and TTextChars.IsIdentChar(AText[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Bezeichner oder reserviertes Wort ab AIndex; hinter "." ein Mitglied (TFoo.Free, Self.Create), nie
/// ein Schlüsselwort.</summary>
function WordKind(const AText: string; AStart, AEnd: Integer): TAtlasStickySyntax;
begin
  if ((AStart = 1) or (AText[AStart - 1] <> '.')) and
    TAtlasStickyScroll.IsReserved(Copy(AText, AStart, AEnd - AStart)) then
  begin
    Result := TAtlasStickySyntax.Reserved;
  end
  else
  begin
    Result := TAtlasStickySyntax.Identifier;
  end;
end;

/// <summary>Ende und Art des Stücks ab AIndex.</summary>
function TokenEnd(const AText: string; AIndex: Integer; out AKind: TAtlasStickySyntax): Integer;
begin
  if CommentToken(AText, AIndex, Result, AKind) then
  begin
    Exit;
  end;
  AKind := TAtlasStickySyntax.Symbol;
  Result := AIndex + 1;
  if AText[AIndex] = '''' then
  begin
    Result := StringEnd(AText, AIndex);
    AKind := TAtlasStickySyntax.StringLiteral;
  end
  else if AText[AIndex] = '#' then
  begin
    Result := RunEnd(AText, AIndex + 1, ['0'..'9', 'a'..'f', 'A'..'F', '$']);
    AKind := TAtlasStickySyntax.Character;
  end
  else if IsNumberStart(AText, AIndex) then
  begin
    Result := NumberEnd(AText, AIndex);
    AKind := TAtlasStickySyntax.Number;
  end
  else if (AText[AIndex] = '&') and TTextChars.IsIdentChar(CharAt(AText, AIndex + 1)) then
  begin
    // &begin: escapter Bezeichner, nicht reserviert.
    Result := IdentEnd(AText, AIndex + 1);
    AKind := TAtlasStickySyntax.Identifier;
  end
  else if TTextChars.IsIdentChar(AText[AIndex]) then
  begin
    Result := IdentEnd(AText, AIndex);
    AKind := WordKind(AText, AIndex, Result);
  end
  else if CharInSet(AText[AIndex], [' ', #9]) then
  begin
    Result := RunEnd(AText, AIndex, [' ', #9]);
    AKind := TAtlasStickySyntax.Plain;
  end;
end;

class function TAtlasStickyScroll.Syntax(const AText: string): TArray<TAtlasStickyToken>;
var
  mIndex, mStart: Integer;
  mToken: TAtlasStickyToken;
begin
  Result := nil;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    mStart := mIndex;
    mIndex := Max(TokenEnd(AText, mIndex, mToken.Kind), mStart + 1);
    mToken.Start := mStart;
    mToken.Length := mIndex - mStart;
    Result := Result + [mToken];
  end;
end;

{ TAtlasStickyBlock }

class function TAtlasStickySource.Create(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  const ABlocks: TArray<TAtlasStickyBlock>; AKinds: TAtlasStickyKinds): TAtlasStickySource;
begin
  Result.Nodes := ANodes;
  Result.Lines := ALines;
  Result.Blocks := ABlocks;
  Result.Kinds := AKinds;
end;

class function TAtlasStickyBlock.Create(ALine, ACharacter, AEndLine: Integer): TAtlasStickyBlock;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.EndLine := AEndLine;
end;

class function TAtlasStickyScroll.GuideStart(const ARows: TAtlasStickyRows;
  AFirstLine: Integer): TAtlasStickyGuideStart;
var
  mIndex: Integer;
begin
  Result.Row := High(ARows);
  Result.FadeIn := Length(ARows) > 0;
  for mIndex := 0 to High(ARows) do
  begin
    if not ARows[mIndex].Summary and (ARows[mIndex].Line = AFirstLine) then
    begin
      Result.Row := mIndex;
      Result.FadeIn := False;
    end;
  end;
end;

class function TAtlasStickyScroll.FadeWeight(AOffset, AHeight: Integer): Double;
begin
  if AHeight <= 1 then
  begin
    Exit(1);
  end;
  Result := Sqr(EnsureRange(AOffset + 1, 1, AHeight) / AHeight);
end;

type
  /// <summary>Ebene des Kopfs: Block der Gliederung (Node >= 0) oder zusätzlicher Block (Node = -1).</summary>
  TEntry = record
    Line: Integer;
    Character: Integer;
    EndLine: Integer;
    Node: Integer;
  end;

/// <summary>Alle Ebenen nach Kopfzeile, bei gleicher Zeile die längere (äußere) zuerst.</summary>
function EntriesOf(const ANodes: TAtlasOutlineNodes; const ABlocks: TArray<TAtlasStickyBlock>;
  AKinds: TAtlasStickyKinds): TArray<TEntry>;
var
  mIndex: Integer;
  mEntry: TEntry;
begin
  Result := nil;
  for mIndex := 0 to High(ANodes) do
  begin
    if TAtlasStickyScroll.IsBlock(ANodes[mIndex], AKinds) then
    begin
      mEntry.Line := ANodes[mIndex].NameLine;
      mEntry.Character := ANodes[mIndex].NameCharacter;
      mEntry.EndLine := ANodes[mIndex].EndLine;
      mEntry.Node := mIndex;
      Result := Result + [mEntry];
    end;
  end;
  for mIndex := 0 to High(ABlocks) do
  begin
    mEntry.Line := ABlocks[mIndex].Line;
    mEntry.Character := ABlocks[mIndex].Character;
    mEntry.EndLine := ABlocks[mIndex].EndLine;
    mEntry.Node := -1;
    Result := Result + [mEntry];
  end;
  TArray.Sort<TEntry>(Result, TComparer<TEntry>.Construct(
    function(const A, B: TEntry): Integer
    begin
      Result := CompareValue(A.Line, B.Line);
      if Result = 0 then
      begin
        Result := CompareValue(B.EndLine, A.EndLine);
      end;
      // Eindeutig (TArray.Sort ist nicht stabil): Gliederung vor zusätzlichen Blöcken.
      if Result = 0 then
      begin
        Result := CompareValue(B.Node, A.Node);
      end;
      if Result = 0 then
      begin
        Result := CompareValue(A.Character, B.Character);
      end;
    end));
end;

/// <summary>Ebenen, die ALine umschließen und deren Kopf darüber steht; die äußeren zuerst.</summary>
function EntryChain(const AEntries: TArray<TEntry>; ALine: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AEntries) do
  begin
    if (AEntries[mIndex].Line < ALine) and (ALine <= AEntries[mIndex].EndLine) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

/// <summary>Kopfzeile eines zusätzlichen Blocks: seine Zeile ohne Einrückung.</summary>
function BlockText(const ALines: TArray<string>; ALine: Integer): string;
begin
  Result := '';
  if (ALine >= 0) and (ALine <= High(ALines)) then
  begin
    Result := Trim(ALines[ALine]);
  end;
end;

/// <summary>Name in der Zusammenfassung „A › B“: Name der Gliederung bzw. gekürzte Kopfzeile.</summary>
function EntryName(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; const AEntry: TEntry): string;
const
  cMaxName = 30;
begin
  if AEntry.Node >= 0 then
  begin
    Exit(ANodes[AEntry.Node].Name);
  end;
  Result := BlockText(ALines, AEntry.Line);
  if Length(Result) > cMaxName then
  begin
    Result := Copy(Result, 1, cMaxName) + '…';
  end;
end;

function EntryRow(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; const AEntry: TEntry;
  ATabWidth: Integer): TAtlasStickyRow;
begin
  if AEntry.Node >= 0 then
  begin
    Exit(HeaderRow(ANodes, ALines, AEntry.Node, ATabWidth));
  end;
  Result.Text := BlockText(ALines, AEntry.Line);
  Result.Line := AEntry.Line;
  Result.Character := AEntry.Character;
  Result.Indent := 0;
  if (AEntry.Line >= 0) and (AEntry.Line <= High(ALines)) then
  begin
    Result.Indent := TAtlasStickyScroll.IndentColumns(ALines[AEntry.Line], ATabWidth);
  end;
  Result.Summary := False;
end;

class function TAtlasStickyScroll.Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  const ABlocks: TArray<TAtlasStickyBlock>; ATopLine, AMaxLines, ATabWidth: Integer): TAtlasStickyRows;
begin
  Result := Rows(TAtlasStickySource.Create(ANodes, ALines, ABlocks, cOutlineKinds), ATopLine, AMaxLines, ATabWidth);
end;

/// <summary>Wie Scopes: Mit Shown Kopfzeilen ist ATopLine + Shown die erste lesbare Zeile; die Kette zur kleinsten
/// Zahl, die reicht.</summary>
function VisibleChain(const AEntries: TArray<TEntry>; ATopLine, AMaxLines: Integer): TArray<Integer>;
var
  mShown: Integer;
begin
  Result := nil;
  for mShown := 0 to AMaxLines do
  begin
    Result := EntryChain(AEntries, ATopLine + mShown);
    if Min(Length(Result), AMaxLines) <= mShown then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Die äußeren AGrouped Ebenen der Kette AItems in einer Zeile.</summary>
function SummaryRow(const ASource: TAtlasStickySource; const AEntries: TArray<TEntry>; const AItems: TArray<Integer>;
  AGrouped: Integer): TAtlasStickyRow;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasStickyRow);
  Result.Summary := True;
  for mIndex := 0 to AGrouped - 1 do
  begin
    if mIndex > 0 then
    begin
      Result.Text := Result.Text + TAtlasStickyScroll.cSeparator;
    end;
    Result.Text := Result.Text + EntryName(ASource.Nodes, ASource.Lines, AEntries[AItems[mIndex]]);
  end;
  Result.Line := AEntries[AItems[AGrouped - 1]].Line;
  Result.Character := AEntries[AItems[AGrouped - 1]].Character;
end;

class function TAtlasStickyScroll.Rows(const ASource: TAtlasStickySource; ATopLine, AMaxLines,
  ATabWidth: Integer): TAtlasStickyRows;
var
  mEntries: TArray<TEntry>;
  mItems: TArray<Integer>;
  mMaxLines, mGrouped, mIndex: Integer;
begin
  Result := nil;
  mMaxLines := ClampLines(AMaxLines);
  mEntries := EntriesOf(ASource.Nodes, ASource.Blocks, ASource.Kinds);
  mItems := VisibleChain(mEntries, Max(0, ATopLine), mMaxLines);
  // Die inneren MaxLines - 1 Ebenen einzeln, die äußeren in einer Zeile (bei einer Zeile alle).
  mGrouped := 0;
  if Length(mItems) > mMaxLines then
  begin
    mGrouped := Length(mItems) - mMaxLines + 1;
    Result := [SummaryRow(ASource, mEntries, mItems, mGrouped)];
  end;
  for mIndex := mGrouped to High(mItems) do
  begin
    Result := Result + [EntryRow(ASource.Nodes, ASource.Lines, mEntries[mItems[mIndex]], ATabWidth)];
  end;
end;

class function TAtlasStickyScroll.Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ATopLine,
  AMaxLines, ATabWidth: Integer): TAtlasStickyRows;
begin
  Result := Rows(ANodes, ALines, nil, ATopLine, AMaxLines, ATabWidth);
end;

class function TAtlasStickyScroll.Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ATopLine,
  AMaxLines: Integer): TAtlasStickyRows;
begin
  Result := Rows(ANodes, ALines, ATopLine, AMaxLines, cDefaultTabWidth);
end;

end.
