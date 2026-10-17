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

class function TAtlasStickyScroll.Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ATopLine,
  AMaxLines, ATabWidth: Integer): TAtlasStickyRows;
var
  Items: TArray<Integer>;
  MaxLines, Grouped, Index: Integer;
  Row: TAtlasStickyRow;
begin
  Result := nil;
  MaxLines := ClampLines(AMaxLines);
  Items := Scopes(ANodes, ATopLine, MaxLines);
  if Length(Items) <= MaxLines then
  begin
    for Index := 0 to High(Items) do
      Result := Result + [HeaderRow(ANodes, ALines, Items[Index], ATabWidth)];
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
    Row.Text := Row.Text + ANodes[Items[Index]].Name;
  end;
  Row.Line := ANodes[Items[Grouped - 1]].NameLine;
  Row.Character := ANodes[Items[Grouped - 1]].NameCharacter;
  Result := [Row];
  for Index := Grouped to High(Items) do
    Result := Result + [HeaderRow(ANodes, ALines, Items[Index], ATabWidth)];
end;

class function TAtlasStickyScroll.Rows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ATopLine,
  AMaxLines: Integer): TAtlasStickyRows;
begin
  Result := Rows(ANodes, ALines, ATopLine, AMaxLines, DefaultTabWidth);
end;

end.
