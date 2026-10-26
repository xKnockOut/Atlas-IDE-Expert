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
// - Zusätzliche Blöcke (#1230): große if/else-Blöcke (aus der Paaranalyse,
//   ausgewählt vom Aufrufer) zählen wie Routinen; ihr Kopf ist die Zeile des
//   if bzw. else ohne Einrückung. Alle Ebenen sind nach ihrer Kopfzeile
//   geordnet, die äußeren zuerst.

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

  /// <summary>Zusätzlicher Block (#1230): Kopf in Zeile Line (Sprungziel Character), endet in EndLine; 0-basiert.
  /// </summary>
  TAtlasStickyBlock = record
    Line: Integer;
    Character: Integer;
    EndLine: Integer;
    class function Create(ALine, ACharacter, AEndLine: Integer): TAtlasStickyBlock; static;
  end;

  TAtlasStickyScroll = class
  public const
    DefaultMaxLines = 3;
    MaxMaxLines = 10;
    Separator = ' › ';
    /// <summary>So viele Zeilen sucht Header nach der schließenden Klammer.</summary>
    HeaderSearchLines = 30;
  public
    /// <summary>Klasse, Record, Interface oder Objekt; Routine mit Rumpf.</summary>
    class function IsBlock(const ANode: TAtlasOutlineNode): Boolean; static;
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
    /// <summary>Wie oben mit Tabulatorbreite 8.</summary>
    class function Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ATopLine,
      AMaxLines: Integer): TAtlasStickyRows; overload; static;
    /// <summary>Zeilen auf AMaxLines begrenzt (mindestens 1, höchstens MaxMaxLines).</summary>
    class function ClampLines(AMaxLines: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
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

{ TAtlasStickyBlock }

class function TAtlasStickyBlock.Create(ALine, ACharacter, AEndLine: Integer): TAtlasStickyBlock;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.EndLine := AEndLine;
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
function EntriesOf(const ANodes: TAtlasOutlineNodes; const ABlocks: TArray<TAtlasStickyBlock>): TArray<TEntry>;
var
  Index: Integer;
  Entry: TEntry;
begin
  Result := nil;
  for Index := 0 to High(ANodes) do
    if TAtlasStickyScroll.IsBlock(ANodes[Index]) then
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
var
  Entries: TArray<TEntry>;
  Items: TArray<Integer>;
  MaxLines, Grouped, Index, Shown: Integer;
  Row: TAtlasStickyRow;
begin
  Result := nil;
  MaxLines := ClampLines(AMaxLines);
  Entries := EntriesOf(ANodes, ABlocks);
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
