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

  /// <summary>Wo eine Blocklinie im Kopf beginnt: in Kopfzeile Row (0-basiert) mit Haken; bei FadeIn hat ihr
  /// Element keine Kopfzeile, und sie blendet in Row (der letzten) ein. Row = -1 ohne Kopf.</summary>
  TAtlasStickyGuideStart = record
    Row: Integer;
    FadeIn: Boolean;
  end;

  TAtlasStickyScroll = class
  public const
    DefaultMaxLines = 3;
    MaxMaxLines = 10;
    Separator = ' › ';
    /// <summary>So viele Zeilen sucht Header nach der schließenden Klammer.</summary>
    HeaderSearchLines = 30;
    /// <summary>Arten ohne Auswahl: Typen und Routinen der Gliederung.</summary>
    OutlineKinds = [TAtlasStickyKind.Types, TAtlasStickyKind.Routines];
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
    /// <summary>Breite der Einrückung in Spalten (Tabulatoren bis zum nächsten Vielfachen von ATabWidth).</summary>
    class function IndentColumns(const ALine: string; ATabWidth: Integer): Integer; static;
    /// <summary>Zeilen des Kopfs, höchstens AMaxLines (mindestens eine).</summary>
    class function Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ATopLine, AMaxLines,
      ATabWidth: Integer): TAtlasStickyRows; overload; static;
    /// <summary>Wie oben, dazu die Blöcke ABlocks (#1230) als weitere Ebenen.</summary>
    class function Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      const ABlocks: TArray<TAtlasStickyBlock>; ATopLine, AMaxLines, ATabWidth: Integer): TAtlasStickyRows; overload;
      static;
    /// <summary>Wie oben; von der Gliederung nur Blöcke der Arten AKinds (Types, Routines).</summary>
    class function Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      const ABlocks: TArray<TAtlasStickyBlock>; AKinds: TAtlasStickyKinds; ATopLine, AMaxLines,
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
  KindClass = 5;
  KindMethod = 6;
  KindConstructor = 9;
  KindInterface = 11;
  KindFunction = 12;
  KindObject = 19;
  KindStruct = 23;
  DefaultTabWidth = 8;

class function TAtlasStickyScroll.ClampLines(AMaxLines: Integer): Integer;
begin
  Result := EnsureRange(AMaxLines, 1, MaxMaxLines);
end;

class function TAtlasStickyScroll.IsBlock(const ANode: TAtlasOutlineNode): Boolean;
begin
  case ANode.Category of
    TAtlasOutlineCategory.TypeDecl:
      Result := ANode.Kind in [KindClass, KindInterface, KindObject, KindStruct];
    TAtlasOutlineCategory.Routine:
      Result := ANode.Kind in [KindMethod, KindConstructor, KindFunction];
  else
    Result := False;
  end;
end;

class function TAtlasStickyScroll.IsBlock(const ANode: TAtlasOutlineNode; AKinds: TAtlasStickyKinds): Boolean;
begin
  Result := IsBlock(ANode);
  if not Result then
    Exit;
  if ANode.Category = TAtlasOutlineCategory.TypeDecl then
    Result := TAtlasStickyKind.Types in AKinds
  else
    Result := TAtlasStickyKind.Routines in AKinds;
end;

class function TAtlasStickyScroll.OwnerKind(const AOwner: string; out AKind: TAtlasStickyKind): Boolean;
begin
  Result := True;
  AKind := TAtlasStickyKind.Branches;
  if (AOwner = 'if') or (AOwner = 'else') then
    AKind := TAtlasStickyKind.Branches
  else if (AOwner = 'for') or (AOwner = 'while') or (AOwner = 'repeat') then
    AKind := TAtlasStickyKind.Loops
  else if AOwner = 'try' then
    AKind := TAtlasStickyKind.TryBlocks
  else if AOwner = 'case' then
    AKind := TAtlasStickyKind.CaseBlocks
  else if AOwner = 'with' then
    AKind := TAtlasStickyKind.WithBlocks
  else
    Result := False;
end;

class function TAtlasStickyScroll.Chain(const ANodes: TAtlasOutlineNodes; ALine: Integer): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  // Kinder stehen hinter ihren Eltern: die Reihenfolge ist schon von außen nach innen.
  for Index := 0 to High(ANodes) do
    if IsBlock(ANodes[Index]) and (ANodes[Index].NameLine < ALine) and (ALine <= ANodes[Index].EndLine) then
      Result := Result + [Index];
end;

class function TAtlasStickyScroll.Scopes(const ANodes: TAtlasOutlineNodes; ATopLine,
  AMaxLines: Integer): TArray<Integer>;
var
  Shown, MaxLines: Integer;
begin
  MaxLines := ClampLines(AMaxLines);
  ATopLine := Max(0, ATopLine);
  // Mit Shown Kopfzeilen ist ATopLine + Shown die erste lesbare Zeile; die kleinste Zahl, die reicht, gilt.
  for Shown := 0 to MaxLines do
  begin
    Result := Chain(ANodes, ATopLine + Shown);
    if Min(Length(Result), MaxLines) <= Shown then
      Exit;
  end;
end;

/// <summary>Klammertiefe nach der Zeile, ab AFrom; Zeichenketten und //-Kommentare zählen nicht. AOpen ist die
/// Stelle der äußersten offenen Klammer (0 = keine), AClose die Stelle, an der die Tiefe auf 0 fällt.</summary>
procedure Scan(const ALine: string; var ADepth: Integer; out AOpen, AClose: Integer);
var
  Position: Integer;
  InString: Boolean;
begin
  AOpen := 0;
  AClose := 0;
  InString := False;
  Position := 1;
  while Position <= Length(ALine) do
  begin
    if InString then
    begin
      if ALine[Position] = '''' then
        InString := False;
    end
    else
      case ALine[Position] of
        '''':
          InString := True;
        '/':
          if (Position < Length(ALine)) and (ALine[Position + 1] = '/') then
            Break;
        '(':
          begin
            if ADepth = 0 then
              AOpen := Position;
            Inc(ADepth);
          end;
        ')':
          if ADepth > 0 then
          begin
            Dec(ADepth);
            if ADepth = 0 then
            begin
              AOpen := 0;
              if AClose = 0 then
                AClose := Position;
            end;
          end;
      end;
    Inc(Position);
  end;
end;

class function TAtlasStickyScroll.Header(const ALines: TArray<string>; const ANode: TAtlasOutlineNode): string;
var
  Depth, Open, Close, Index, Last: Integer;
  Line: string;
begin
  if (ANode.NameLine < 0) or (ANode.NameLine > High(ALines)) then
    Exit(ANode.Name);
  Line := Trim(ALines[ANode.NameLine]);
  Depth := 0;
  Scan(Line, Depth, Open, Close);
  if Depth <= 0 then
    Exit(Line);
  // Parameterliste über mehrere Zeilen: bis zur offenen Klammer, dann „…“ und der Rest nach der schließenden.
  Result := Copy(Line, 1, Open) + '…';
  Last := Min(High(ALines), Min(ANode.EndLine, ANode.NameLine + HeaderSearchLines));
  for Index := ANode.NameLine + 1 to Last do
  begin
    Line := Trim(ALines[Index]);
    Scan(Line, Depth, Open, Close);
    if Depth <= 0 then
      Exit(Result + Copy(Line, Close, MaxInt));
  end;
  Result := Result + ')';
end;

class function TAtlasStickyScroll.IndentColumns(const ALine: string; ATabWidth: Integer): Integer;
var
  Indent: Char;
begin
  Result := 0;
  ATabWidth := Max(1, ATabWidth);
  for Indent in TTextLines.IndentOf(ALine) do
    if Indent = #9 then
      Result := (Result div ATabWidth + 1) * ATabWidth
    else
      Inc(Result);
end;

function HeaderRow(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ANode,
  ATabWidth: Integer): TAtlasStickyRow;
begin
  Result.Text := TAtlasStickyScroll.Header(ALines, ANodes[ANode]);
  Result.Line := ANodes[ANode].NameLine;
  Result.Character := ANodes[ANode].NameCharacter;
  Result.Indent := 0;
  if (Result.Line >= 0) and (Result.Line <= High(ALines)) then
    Result.Indent := TAtlasStickyScroll.IndentColumns(ALines[Result.Line], ATabWidth);
  Result.Summary := False;
end;

class function TAtlasStickyScroll.IsReserved(const AWord: string): Boolean;
const
  // Reservierte Wörter von Delphi und die Direktiven in Köpfen. Mehrdeutige Direktiven (index, name, read, write,
  // default, message …) fehlen: Als Bezeichner zeigt sie der Editor nicht fett.
  Words: array[0..98] of string = ('and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
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
  Lower, Word: string;
begin
  Lower := LowerCase(AWord);
  for Word in Words do
    if Word = Lower then
      Exit(True);
  Result := False;
end;

class function TAtlasStickyScroll.Syntax(const AText: string): TArray<TAtlasStickyToken>;
var
  Index, Start, Count: Integer;
  Kind: TAtlasStickySyntax;

  procedure Add(AStart, AStop: Integer; AKind: TAtlasStickySyntax);
  var
    Token: TAtlasStickyToken;
  begin
    if AStop <= AStart then
      Exit;
    Token.Start := AStart;
    Token.Length := AStop - AStart;
    Token.Kind := AKind;
    Result := Result + [Token];
  end;

  function At(APos: Integer): Char;
  begin
    if APos <= Count then
      Result := AText[APos]
    else
      Result := #0;
  end;

  /// <summary>Bis hinter ACloser (oder Zeilenende).</summary>
  function SkipTo(AFrom: Integer; const ACloser: string): Integer;
  begin
    Result := Pos(ACloser, AText, AFrom);
    if Result = 0 then
      Result := Count + 1
    else
      Inc(Result, Length(ACloser));
  end;

begin
  Result := nil;
  Count := Length(AText);
  Index := 1;
  while Index <= Count do
  begin
    Start := Index;
    if (AText[Index] = '{') and (At(Index + 1) = '$') then
    begin
      Index := SkipTo(Index + 1, '}');
      Kind := TAtlasStickySyntax.Preprocessor;
    end
    else if AText[Index] = '{' then
    begin
      Index := SkipTo(Index + 1, '}');
      Kind := TAtlasStickySyntax.Comment;
    end
    else if (AText[Index] = '(') and (At(Index + 1) = '*') then
    begin
      Index := SkipTo(Index + 2, '*)');
      if At(Start + 2) = '$' then
        Kind := TAtlasStickySyntax.Preprocessor
      else
        Kind := TAtlasStickySyntax.Comment;
    end
    else if (AText[Index] = '/') and (At(Index + 1) = '/') then
    begin
      Index := Count + 1;
      Kind := TAtlasStickySyntax.Comment;
    end
    else if AText[Index] = '''' then
    begin
      Inc(Index);
      while Index <= Count do
      begin
        if AText[Index] = '''' then
        begin
          // '' im String ist ein Hochkomma.
          if At(Index + 1) <> '''' then
            Break;
          Inc(Index);
        end;
        Inc(Index);
      end;
      if Index <= Count then
        Inc(Index);
      Kind := TAtlasStickySyntax.StringLiteral;
    end
    else if AText[Index] = '#' then
    begin
      Inc(Index);
      while (Index <= Count) and CharInSet(AText[Index], ['0'..'9', 'a'..'f', 'A'..'F', '$']) do
        Inc(Index);
      Kind := TAtlasStickySyntax.Character;
    end
    else if CharInSet(AText[Index], ['0'..'9']) or
      ((AText[Index] = '$') and CharInSet(At(Index + 1), ['0'..'9', 'a'..'f', 'A'..'F'])) or
      ((AText[Index] = '%') and CharInSet(At(Index + 1), ['0', '1'])) then
    begin
      Inc(Index);
      while (Index <= Count) and (CharInSet(AText[Index], ['0'..'9', 'a'..'f', 'A'..'F', '_', '.']) or
        (CharInSet(AText[Index], ['+', '-']) and CharInSet(AText[Index - 1], ['e', 'E']))) do
        Inc(Index);
      Kind := TAtlasStickySyntax.Number;
    end
    else if (AText[Index] = '&') and TTextChars.IsIdentChar(At(Index + 1)) then
    begin
      // &begin: escapter Bezeichner, nicht reserviert.
      Inc(Index);
      while (Index <= Count) and TTextChars.IsIdentChar(AText[Index]) do
        Inc(Index);
      Kind := TAtlasStickySyntax.Identifier;
    end
    else if TTextChars.IsIdentChar(AText[Index]) then
    begin
      while (Index <= Count) and TTextChars.IsIdentChar(AText[Index]) do
        Inc(Index);
      // Hinter "." ein Mitglied (TFoo.Free, Self.Create), nie ein Schlüsselwort.
      if ((Start = 1) or (AText[Start - 1] <> '.')) and IsReserved(Copy(AText, Start, Index - Start)) then
        Kind := TAtlasStickySyntax.Reserved
      else
        Kind := TAtlasStickySyntax.Identifier;
    end
    else if CharInSet(AText[Index], [' ', #9]) then
    begin
      while (Index <= Count) and CharInSet(AText[Index], [' ', #9]) do
        Inc(Index);
      Kind := TAtlasStickySyntax.Plain;
    end
    else
    begin
      Inc(Index);
      Kind := TAtlasStickySyntax.Symbol;
    end;
    Add(Start, Index, Kind);
  end;
end;

{ TAtlasStickyBlock }

class function TAtlasStickyBlock.Create(ALine, ACharacter, AEndLine: Integer): TAtlasStickyBlock;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.EndLine := AEndLine;
end;

class function TAtlasStickyScroll.GuideStart(const ARows: TAtlasStickyRows;
  AFirstLine: Integer): TAtlasStickyGuideStart;
var
  Index: Integer;
begin
  Result.Row := High(ARows);
  Result.FadeIn := Length(ARows) > 0;
  for Index := 0 to High(ARows) do
    if not ARows[Index].Summary and (ARows[Index].Line = AFirstLine) then
    begin
      Result.Row := Index;
      Result.FadeIn := False;
    end;
end;

class function TAtlasStickyScroll.FadeWeight(AOffset, AHeight: Integer): Double;
begin
  if AHeight <= 1 then
    Exit(1);
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
  Index: Integer;
  Entry: TEntry;
begin
  Result := nil;
  for Index := 0 to High(ANodes) do
    if TAtlasStickyScroll.IsBlock(ANodes[Index], AKinds) then
    begin
      Entry.Line := ANodes[Index].NameLine;
      Entry.Character := ANodes[Index].NameCharacter;
      Entry.EndLine := ANodes[Index].EndLine;
      Entry.Node := Index;
      Result := Result + [Entry];
    end;
  for Index := 0 to High(ABlocks) do
  begin
    Entry.Line := ABlocks[Index].Line;
    Entry.Character := ABlocks[Index].Character;
    Entry.EndLine := ABlocks[Index].EndLine;
    Entry.Node := -1;
    Result := Result + [Entry];
  end;
  TArray.Sort<TEntry>(Result, TComparer<TEntry>.Construct(
    function(const A, B: TEntry): Integer
    begin
      Result := CompareValue(A.Line, B.Line);
      if Result = 0 then
        Result := CompareValue(B.EndLine, A.EndLine);
      // Eindeutig (TArray.Sort ist nicht stabil): Gliederung vor zusätzlichen Blöcken.
      if Result = 0 then
        Result := CompareValue(B.Node, A.Node);
      if Result = 0 then
        Result := CompareValue(A.Character, B.Character);
    end));
end;

/// <summary>Ebenen, die ALine umschließen und deren Kopf darüber steht; die äußeren zuerst.</summary>
function EntryChain(const AEntries: TArray<TEntry>; ALine: Integer): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(AEntries) do
    if (AEntries[Index].Line < ALine) and (ALine <= AEntries[Index].EndLine) then
      Result := Result + [Index];
end;

/// <summary>Kopfzeile eines zusätzlichen Blocks: seine Zeile ohne Einrückung.</summary>
function BlockText(const ALines: TArray<string>; ALine: Integer): string;
begin
  Result := '';
  if (ALine >= 0) and (ALine <= High(ALines)) then
    Result := Trim(ALines[ALine]);
end;

/// <summary>Name in der Zusammenfassung „A › B“: Name der Gliederung bzw. gekürzte Kopfzeile.</summary>
function EntryName(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; const AEntry: TEntry): string;
const
  MaxName = 30;
begin
  if AEntry.Node >= 0 then
    Exit(ANodes[AEntry.Node].Name);
  Result := BlockText(ALines, AEntry.Line);
  if Length(Result) > MaxName then
    Result := Copy(Result, 1, MaxName) + '…';
end;

function EntryRow(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; const AEntry: TEntry;
  ATabWidth: Integer): TAtlasStickyRow;
begin
  if AEntry.Node >= 0 then
    Exit(HeaderRow(ANodes, ALines, AEntry.Node, ATabWidth));
  Result.Text := BlockText(ALines, AEntry.Line);
  Result.Line := AEntry.Line;
  Result.Character := AEntry.Character;
  Result.Indent := 0;
  if (AEntry.Line >= 0) and (AEntry.Line <= High(ALines)) then
    Result.Indent := TAtlasStickyScroll.IndentColumns(ALines[AEntry.Line], ATabWidth);
  Result.Summary := False;
end;

class function TAtlasStickyScroll.Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  const ABlocks: TArray<TAtlasStickyBlock>; ATopLine, AMaxLines, ATabWidth: Integer): TAtlasStickyRows;
begin
  Result := Rows(ANodes, ALines, ABlocks, OutlineKinds, ATopLine, AMaxLines, ATabWidth);
end;

class function TAtlasStickyScroll.Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  const ABlocks: TArray<TAtlasStickyBlock>; AKinds: TAtlasStickyKinds; ATopLine, AMaxLines,
  ATabWidth: Integer): TAtlasStickyRows;
var
  Entries: TArray<TEntry>;
  Items: TArray<Integer>;
  MaxLines, Grouped, Index, Shown: Integer;
  Row: TAtlasStickyRow;
begin
  Result := nil;
  MaxLines := ClampLines(AMaxLines);
  Entries := EntriesOf(ANodes, ABlocks, AKinds);
  ATopLine := Max(0, ATopLine);
  // Wie Scopes: Mit Shown Kopfzeilen ist ATopLine + Shown die erste lesbare Zeile; die kleinste Zahl, die reicht.
  Items := nil;
  for Shown := 0 to MaxLines do
  begin
    Items := EntryChain(Entries, ATopLine + Shown);
    if Min(Length(Items), MaxLines) <= Shown then
      Break;
  end;
  if Length(Items) <= MaxLines then
  begin
    for Index := 0 to High(Items) do
      Result := Result + [EntryRow(ANodes, ALines, Entries[Items[Index]], ATabWidth)];
    Exit;
  end;
  // Die inneren MaxLines - 1 Ebenen einzeln, die äußeren in einer Zeile (bei einer Zeile alle).
  Grouped := Length(Items) - MaxLines + 1;
  Row := Default(TAtlasStickyRow);
  Row.Summary := True;
  for Index := 0 to Grouped - 1 do
  begin
    if Index > 0 then
      Row.Text := Row.Text + Separator;
    Row.Text := Row.Text + EntryName(ANodes, ALines, Entries[Items[Index]]);
  end;
  Row.Line := Entries[Items[Grouped - 1]].Line;
  Row.Character := Entries[Items[Grouped - 1]].Character;
  Result := [Row];
  for Index := Grouped to High(Items) do
    Result := Result + [EntryRow(ANodes, ALines, Entries[Items[Index]], ATabWidth)];
end;

class function TAtlasStickyScroll.Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ATopLine,
  AMaxLines, ATabWidth: Integer): TAtlasStickyRows;
begin
  Result := Rows(ANodes, ALines, nil, ATopLine, AMaxLines, ATabWidth);
end;

class function TAtlasStickyScroll.Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ATopLine,
  AMaxLines: Integer): TAtlasStickyRows;
begin
  Result := Rows(ANodes, ALines, ATopLine, AMaxLines, DefaultTabWidth);
end;

end.
