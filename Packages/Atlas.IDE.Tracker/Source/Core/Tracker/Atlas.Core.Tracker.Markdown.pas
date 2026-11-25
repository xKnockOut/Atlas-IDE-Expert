unit Atlas.Core.Tracker.Markdown;

// Markdown aus YouTrack und GitHub für das Fenster „Atlas-Issue“ (#1264),
// ohne VCL und Open Tools API.
// - Blocks zerlegt den Text in Blöcke: Absatz, Überschrift (#…), Listenpunkt
//   (-, *, +, 1. mit Ebene und Aufgabenkästchen), Zitat (>), Codeblock
//   (```lang bzw. ~~~ und vier Leerzeichen Einzug), Tabelle (Kopfzeile mit
//   |---|), Trennlinie und alleinstehendes Bild (![alt](url), <img src=…>).
//   Einfache Zeilenumbrüche bleiben Umbrüche, wie in Issues bei GitHub und
//   YouTrack.
// - InlineRuns setzt einen Absatz in Doku-Läufe; den Fließtext liest
//   Atlas.Core.Tracker.Markdown.Spans.
// - Segments liefert Doku-Abschnitte und dazwischen die alleinstehenden
//   Bilder, damit das Fenster sie als Vorschau zeigen kann. Codeblöcke tragen
//   die Sprache (TAtlasDocRun.Target); Delphi und ohne Angabe werden
//   eingefärbt.
// - Links liefert alle Link-Ziele (für Dateien in GitHub-Issues als Anhänge).
// - Aufgabenlisten (#1273): "- [ ]", "* [x]", "+ [ ]" und nummeriert "1. [ ]",
//   auch eingerückt; nie in Codeblöcken oder Zitaten. Jeder Punkt trägt seine
//   Zeile im Text (Line, LastLine), darauf baut Atlas.Core.Tracker.Checklist
//   auf. TAtlasMarkdownTasks wählt die Darstellung: Kästchen (Kommentare),
//   als Text wie geschrieben (issues.preview.checklists aus) oder anklickbar
//   mit dem Ziel "atlas-task:<n>" an der Marke (Beschreibung).
// Kein vollständiges CommonMark: Es geht um eine lesbare Vorschau. Adressen aus
// dem Text werden hier nicht geprüft; das tut, wer sie öffnet.

interface

uses
  System.SysUtils,
  Atlas.Core.Documentation.Contract;

type
{$SCOPEDENUMS ON}
  TAtlasMarkdownBlockKind = (Paragraph, Heading, Bullet, Quote, Code, Table, Rule, Image);
  /// <summary>Aufgabenkästchen eines Listenpunkts (#1273).</summary>
  TAtlasMarkdownTask = (None, Open, Done);
  /// <summary>Darstellung der Aufgabenlisten (#1273): Kästchen ☐/☑, Text wie geschrieben ("[ ] …") bzw. Kästchen
  /// mit Ziel TAtlasTrackerMarkdown.TaskTarget an der Marke.</summary>
  TAtlasMarkdownTasks = (Boxes, Plain, Clickable);
{$SCOPEDENUMS OFF}

  /// <summary>Link oder Bild im Markdown.</summary>
  TAtlasMarkdownLink = record
    Text: string;
    /// <summary>Wie im Text: absolut oder relativ (YouTrack: Name eines Anhangs).</summary>
    Url: string;
    class function Create(const AText, AUrl: string): TAtlasMarkdownLink; static;
  end;

  TAtlasMarkdownBlock = record
    Kind: TAtlasMarkdownBlockKind;
    /// <summary>Heading: 1–6; Bullet: Listenebene ab 1; sonst 0.</summary>
    Level: Integer;
    /// <summary>Paragraph, Heading, Bullet, Quote: Markdown der Zeile(n), Umbrüche als #10; Code: Quelltext;
    /// Image: Alternativtext.</summary>
    Text: string;
    /// <summary>Bullet: "•", "1.", "☐" bzw. "☑".</summary>
    Marker: string;
    /// <summary>Bullet: Marke der Liste ohne Kästchen ("•" bzw. "1.").</summary>
    ListMarker: string;
    /// <summary>Bullet: Aufgabenkästchen (#1273).</summary>
    Task: TAtlasMarkdownTask;
    /// <summary>Bullet: erste und letzte Zeile im Text (ab 0, samt Fortsetzungszeilen); sonst -1.</summary>
    Line: Integer;
    LastLine: Integer;
    /// <summary>Code: Sprache des Zauns ('' ohne); Image: Adresse.</summary>
    Info: string;
    /// <summary>Table: Zeilen mit Zellen (Markdown), die erste ist die Kopfzeile.</summary>
    Rows: TArray<TArray<string>>;
  end;

{$SCOPEDENUMS ON}
  TAtlasMarkdownSegmentKind = (Doc, Image);
{$SCOPEDENUMS OFF}

  /// <summary>Stück der Vorschau: gesetzter Text oder ein alleinstehendes Bild.</summary>
  TAtlasMarkdownSegment = record
    Kind: TAtlasMarkdownSegmentKind;
    Doc: TAtlasDoc;
    Image: TAtlasMarkdownLink;
  end;

  TAtlasTrackerMarkdown = class
  public const
    /// <summary>Tiefer eingerückte Listen bleiben auf dieser Ebene.</summary>
    cMaxListLevel = 4;
    /// <summary>Ziel an der Marke eines anklickbaren Aufgabenpunkts (#1273), gefolgt von seiner Nummer ab 0.
    /// </summary>
    cTaskPrefix = 'atlas-task:';
  public
    class function Blocks(const AText: string): TArray<TAtlasMarkdownBlock>; static;
    /// <summary>Läufe eines Absatzes (Markdown im Fließtext); ABold: alles fett (Überschrift, Kopfzeile),
    /// AItalic: alles kursiv (Zitat).</summary>
    class function InlineRuns(const AText: string; ABold, AItalic: Boolean): TAtlasDocRuns; overload; static;
    class function InlineRuns(const AText: string): TAtlasDocRuns; overload; static;
    /// <summary>Alles als eine Doku (Abschnitt Summary); alleinstehende Bilder als Link.</summary>
    class function ToDoc(const AText: string): TAtlasDoc; overload; static;
    class function ToDoc(const AText: string; ATasks: TAtlasMarkdownTasks): TAtlasDoc; overload; static;
    /// <summary>Doku-Stücke, getrennt durch alleinstehende Bilder; Aufgaben als Kästchen.</summary>
    class function Segments(const AText: string): TArray<TAtlasMarkdownSegment>; overload; static;
    /// <summary>Wie oben, Aufgaben nach ATasks; Clickable zählt die Punkte über alle Stücke hinweg.</summary>
    class function Segments(const AText: string; ATasks: TAtlasMarkdownTasks): TArray<TAtlasMarkdownSegment>;
      overload; static;
    /// <summary>Ziel der Marke des Aufgabenpunkts AIndex (ab 0): "atlas-task:3".</summary>
    class function TaskTarget(AIndex: Integer): string; static;
    /// <summary>Nummer aus einem Ziel von TaskTarget; False bei anderen Zielen.</summary>
    class function TaskIndexOf(const ATarget: string; out AIndex: Integer): Boolean; static;
    /// <summary>Alle Links und Bilder in Reihenfolge (ohne Codeblöcke und Code im Fließtext).</summary>
    class function Links(const AText: string): TArray<TAtlasMarkdownLink>; static;
    /// <summary>HTML-Entitäten ersetzen: wie TTextEntities.Decode, dazu &amp;nbsp; als Leerzeichen.</summary>
    class function DecodeHtml(const AText: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  Atlas.Core.Tracker.Markdown.Spans;

const
  cBullet = '•';
  cTaskOpen = '☐';
  cTaskDone = '☑';
  cQuoteMarker = '│';
  /// <summary>Spalten eines Tabulators beim Zählen der Einrückung.</summary>
  cTabWidth = 4;
  /// <summary>Ab dieser Einrückung ist eine Zeile eingerückter Code; Blöcke dürfen weniger haben.</summary>
  cCodeIndent = 4;
  cMaxBlockIndent = cCodeIndent - 1;
  /// <summary>Mindestzahl der Zeichen eines Codezauns und einer Trennlinie.</summary>
  cMinFenceLength = 3;
  cMinRuleMarks = 3;
  cMaxHeadingLevel = 6;
  /// <summary>Höchstens so viele Ziffern hat die Nummer eines Listenpunkts.</summary>
  cMaxListDigits = 9;
  /// <summary>Aufgabenkästchen „[ ]“ bzw. „[x]“.</summary>
  cTaskBoxLength = 3;
  cImageStart = '![';

{ TAtlasMarkdownLink }

class function TAtlasMarkdownLink.Create(const AText, AUrl: string): TAtlasMarkdownLink;
begin
  Result.Text := AText;
  Result.Url := AUrl;
end;

{ Zeilen }

function Indent(const ALine: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 1 to Length(ALine) do
  begin
    if ALine[mIndex] = ' ' then
    begin
      Inc(Result);
    end
    else if ALine[mIndex] = #9 then
    begin
      Inc(Result, cTabWidth);
    end
    else
    begin
      Exit;
    end;
  end;
end;

function IsBlank(const ALine: string): Boolean;
begin
  Result := Trim(ALine) = '';
end;

function FenceOf(const ALine: string; out AFence: string; out ALanguage: string): Boolean;
var
  mText: string;
  mChar: Char;
  mCount: Integer;
begin
  Result := False;
  AFence := '';
  ALanguage := '';
  if Indent(ALine) > cMaxBlockIndent then
  begin
    Exit;
  end;
  mText := TrimLeft(ALine);
  if Length(mText) < cMinFenceLength then
  begin
    Exit;
  end;
  mChar := mText[1];
  if (mChar <> '`') and (mChar <> '~') then
  begin
    Exit;
  end;
  mCount := 0;
  while (mCount < Length(mText)) and (mText[mCount + 1] = mChar) do
  begin
    Inc(mCount);
  end;
  if mCount < cMinFenceLength then
  begin
    Exit;
  end;
  AFence := StringOfChar(mChar, mCount);
  ALanguage := Trim(Copy(mText, mCount + 1, MaxInt));
  // Nur das erste Wort: "pascal title=x" bzw. "{.delphi}".
  if Pos(' ', ALanguage) > 0 then
  begin
    ALanguage := Copy(ALanguage, 1, Pos(' ', ALanguage) - 1);
  end;
  ALanguage := ALanguage.Trim(['{', '}', '.']);
  // Ein Backtick-Zaun darf keine Backticks in der Info haben (sonst ist es Code im Fließtext).
  Result := (mChar <> '`') or (Pos('`', ALanguage) = 0);
end;

function ClosesFence(const ALine, AFence: string): Boolean;
var
  mText: string;
begin
  mText := Trim(ALine);
  Result := (Indent(ALine) <= cMaxBlockIndent) and (Length(mText) >= Length(AFence)) and
    (mText = StringOfChar(AFence[1], Length(mText)));
end;

function HeadingOf(const ALine: string; out ALevel: Integer; out AText: string): Boolean;
var
  mText: string;
begin
  Result := False;
  ALevel := 0;
  AText := '';
  if Indent(ALine) > cMaxBlockIndent then
  begin
    Exit;
  end;
  mText := TrimLeft(ALine);
  while (ALevel < Length(mText)) and (mText[ALevel + 1] = '#') do
  begin
    Inc(ALevel);
  end;
  if (ALevel < 1) or (ALevel > cMaxHeadingLevel) then
  begin
    Exit;
  end;
  if (Length(mText) > ALevel) and (mText[ALevel + 1] <> ' ') and (mText[ALevel + 1] <> #9) then
  begin
    Exit;
  end;
  AText := Trim(Copy(mText, ALevel + 1, MaxInt));
  // Schließende # ("## Titel ##").
  while (AText <> '') and (AText[Length(AText)] = '#') do
  begin
    Delete(AText, Length(AText), 1);
  end;
  AText := Trim(AText);
  Result := True;
end;

function IsRule(const ALine: string): Boolean;
var
  mText: string;
  mChar: Char;
  mIndex, mCount: Integer;
begin
  Result := False;
  if Indent(ALine) > cMaxBlockIndent then
  begin
    Exit;
  end;
  mText := Trim(ALine);
  if mText = '' then
  begin
    Exit;
  end;
  mChar := mText[1];
  if (mChar <> '-') and (mChar <> '*') and (mChar <> '_') then
  begin
    Exit;
  end;
  mCount := 0;
  for mIndex := 1 to Length(mText) do
  begin
    if mText[mIndex] = mChar then
    begin
      Inc(mCount);
    end
    else if mText[mIndex] <> ' ' then
    begin
      Exit;
    end;
  end;
  Result := mCount >= cMinRuleMarks;
end;

function QuoteOf(const ALine: string; out AText: string): Boolean;
var
  mText: string;
begin
  AText := '';
  mText := TrimLeft(ALine);
  Result := (Indent(ALine) <= cMaxBlockIndent) and (mText <> '') and (mText[1] = '>');
  if not Result then
  begin
    Exit;
  end;
  AText := Copy(mText, 2, MaxInt);
  if (AText <> '') and (AText[1] = ' ') then
  begin
    Delete(AText, 1, 1);
  end;
end;

/// <summary>Zeichen AIndex fehlt oder ist ein Leerzeichen bzw. Tabulator (Ende einer Listenmarke).</summary>
function EndsMarker(const AText: string; AIndex: Integer): Boolean;
begin
  Result := (Length(AText) < AIndex) or CharInSet(AText[AIndex], [' ', #9]);
end;

/// <summary>Marke am Anfang von AText ("•" für -, *, + bzw. "1." für 1. und 1)) und der Text danach.</summary>
function ListMarkerOf(const AText: string; out AMarker, ARest: string): Boolean;
var
  mDigits: Integer;
begin
  Result := False;
  if CharInSet(AText[1], ['-', '*', '+']) then
  begin
    Result := EndsMarker(AText, 2);
    AMarker := cBullet;
    ARest := Trim(Copy(AText, 2, MaxInt));
    Exit;
  end;
  mDigits := 0;
  while (mDigits < Length(AText)) and (mDigits < cMaxListDigits) and CharInSet(AText[mDigits + 1], ['0'..'9']) do
  begin
    Inc(mDigits);
  end;
  if (mDigits = 0) or (mDigits >= Length(AText)) or not CharInSet(AText[mDigits + 1], ['.', ')']) then
  begin
    Exit;
  end;
  Result := EndsMarker(AText, mDigits + 2);
  AMarker := Copy(AText, 1, mDigits) + '.';
  ARest := Trim(Copy(AText, mDigits + 2, MaxInt));
end;

/// <summary>Aufgabenliste: "- [ ] offen", "- [x] erledigt", auch nummeriert (#1273); AText ohne Kästchen.
/// </summary>
function TaskOf(var AText: string): TAtlasMarkdownTask;
begin
  Result := TAtlasMarkdownTask.None;
  if StartsText('[ ] ', AText + ' ') then
  begin
    Result := TAtlasMarkdownTask.Open;
  end
  else if StartsText('[x] ', AText + ' ') then
  begin
    Result := TAtlasMarkdownTask.Done;
  end;
  if Result <> TAtlasMarkdownTask.None then
  begin
    AText := Trim(Copy(AText, cTaskBoxLength + 1, MaxInt));
  end;
end;

/// <summary>Listenpunkt: AMarker "•" bzw. "1.", ATask das Aufgabenkästchen davor (Text ohne Kästchen).</summary>
function ListItemOf(const ALine: string; out AIndent: Integer; out AMarker, AText: string;
  out ATask: TAtlasMarkdownTask): Boolean; overload;
var
  mText: string;
begin
  AMarker := '';
  AText := '';
  ATask := TAtlasMarkdownTask.None;
  AIndent := Indent(ALine);
  mText := TrimLeft(ALine);
  Result := (mText <> '') and ListMarkerOf(mText, AMarker, AText);
  if Result then
  begin
    ATask := TaskOf(AText);
  end
  else
  begin
    AMarker := '';
    AText := '';
  end;
end;

function ListItemOf(const ALine: string; out AIndent: Integer; out AMarker, AText: string): Boolean; overload;
var
  mTask: TAtlasMarkdownTask;
begin
  Result := ListItemOf(ALine, AIndent, AMarker, AText, mTask);
end;

/// <summary>AText ohne "|" am Anfang und ohne unmaskiertes "|" am Ende.</summary>
function RowBody(const ALine: string): string;
begin
  Result := Trim(ALine);
  if (Result <> '') and (Result[1] = '|') then
  begin
    Delete(Result, 1, 1);
  end;
  if (Result <> '') and (Result[Length(Result)] = '|') and
    ((Length(Result) < 2) or (Result[Length(Result) - 1] <> '\')) then
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

type
  /// <summary>Zellen einer Tabellenzeile: "\|" ist ein Zeichen, in `Code` trennt "|" nicht.</summary>
  TRowSplitter = record
    Cells: TArray<string>;
    Cell: string;
    Escaped: Boolean;
    InCode: Boolean;
    procedure Take(AChar: Char);
  end;

{ TRowSplitter }

procedure TRowSplitter.Take(AChar: Char);
begin
  if Escaped then
  begin
    if AChar <> '|' then
    begin
      Cell := Cell + '\';
    end;
    Cell := Cell + AChar;
    Escaped := False;
  end
  else if AChar = '\' then
  begin
    Escaped := True;
  end
  else if (AChar = '|') and not InCode then
  begin
    Cells := Cells + [Trim(Cell)];
    Cell := '';
  end
  else
  begin
    if AChar = '`' then
    begin
      InCode := not InCode;
    end;
    Cell := Cell + AChar;
  end;
end;

function SplitRow(const ALine: string): TArray<string>;
var
  mSplitter: TRowSplitter;
  mChar: Char;
begin
  mSplitter := Default(TRowSplitter);
  mSplitter.Cells := nil;
  for mChar in RowBody(ALine) do
  begin
    mSplitter.Take(mChar);
  end;
  Result := mSplitter.Cells + [Trim(mSplitter.Cell)];
end;

function IsTableSeparator(const ALine: string): Boolean;
var
  mCell, mText: string;
  mIndex: Integer;
  mCells: TArray<string>;
begin
  Result := False;
  if Pos('-', ALine) = 0 then
  begin
    Exit;
  end;
  mCells := SplitRow(ALine);
  if Length(mCells) = 0 then
  begin
    Exit;
  end;
  for mCell in mCells do
  begin
    mText := mCell.Trim([':']);
    if mText = '' then
    begin
      Exit;
    end;
    for mIndex := 1 to Length(mText) do
    begin
      if mText[mIndex] <> '-' then
      begin
        Exit;
      end;
    end;
  end;
  Result := True;
end;

function IsTableStart(const ALines: TArray<string>; AIndex: Integer): Boolean;
begin
  Result := (AIndex < High(ALines)) and (Pos('|', ALines[AIndex]) > 0) and IsTableSeparator(ALines[AIndex + 1]);
end;

/// <summary>Zeile ist genau ein &lt;img … src=…&gt;.</summary>
function HtmlImageOf(const AText: string; out AAlt, AUrl: string): Boolean;
begin
  AAlt := '';
  AUrl := '';
  Result := StartsText('<img', AText) and (AText[Length(AText)] = '>') and (Pos('>', AText) = Length(AText));
  if Result then
  begin
    AUrl := TAtlasTrackerMarkdown.DecodeHtml(TAtlasMarkdownInline.HtmlAttribute(AText, 'src'));
    AAlt := TAtlasTrackerMarkdown.DecodeHtml(TAtlasMarkdownInline.HtmlAttribute(AText, 'alt'));
    Result := AUrl <> '';
  end;
end;

/// <summary>Zeile ist genau ein Bild: ![alt](url) (YouTrack auch mit {width=…}) bzw. &lt;img … src=…&gt;.</summary>
function ImageLineOf(const ALine: string; out AAlt, AUrl: string): Boolean;
var
  mText: string;
  mClose, mStop: Integer;
begin
  mText := Trim(ALine);
  if HtmlImageOf(mText, AAlt, AUrl) or not StartsStr(cImageStart, mText) then
  begin
    Exit(AUrl <> '');
  end;
  mClose := Pos('](', mText);
  mStop := 0;
  if mClose > 0 then
  begin
    mStop := PosEx(')', mText, mClose + 2);
  end;
  // Danach nur noch Attribute in geschweiften Klammern.
  if (mStop = 0) or ((mStop < Length(mText)) and ((mText[mStop + 1] <> '{') or (mText[Length(mText)] <> '}'))) then
  begin
    Exit(False);
  end;
  AAlt := Copy(mText, Length(cImageStart) + 1, mClose - Length(cImageStart) - 1);
  AUrl := Trim(Copy(mText, mClose + 2, mStop - mClose - 2));
  // Titel nach der Adresse: ![a](bild.png "Titel").
  if Pos(' ', AUrl) > 0 then
  begin
    AUrl := Copy(AUrl, 1, Pos(' ', AUrl) - 1);
  end;
  AUrl := AUrl.Trim(['<', '>']);
  Result := AUrl <> '';
end;

function IsHtmlComment(const ALine: string): Boolean;
var
  mText: string;
begin
  mText := Trim(ALine);
  Result := StartsStr('<!--', mText) and EndsStr('-->', mText);
end;

function NewBlock(AKind: TAtlasMarkdownBlockKind; const AText: string): TAtlasMarkdownBlock;
begin
  Result := Default(TAtlasMarkdownBlock);
  Result.Kind := AKind;
  Result.Text := AText;
  Result.Rows := nil;
  Result.Line := -1;
  Result.LastLine := -1;
end;

function StartsBlock(const ALines: TArray<string>; AIndex: Integer): Boolean;
var
  mFence, mLanguage, mText, mMarker: string;
  mLevel, mIndent: Integer;
begin
  Result := FenceOf(ALines[AIndex], mFence, mLanguage) or HeadingOf(ALines[AIndex], mLevel, mText) or
    IsRule(ALines[AIndex]) or QuoteOf(ALines[AIndex], mText) or ListItemOf(ALines[AIndex], mIndent, mMarker, mText)
    or IsTableStart(ALines, AIndex) or ImageLineOf(ALines[AIndex], mText, mMarker);
end;

/// <summary>"☐" bzw. "☑" bei Aufgaben, sonst die Listenmarke.</summary>
function TaskMarker(ATask: TAtlasMarkdownTask; const AListMarker: string): string;
begin
  case ATask of
    TAtlasMarkdownTask.Open:
      Result := cTaskOpen;
    TAtlasMarkdownTask.Done:
      Result := cTaskDone;
  else
    Result := AListMarker;
  end;
end;

/// <summary>Bis zu ACount Leerzeichen am Anfang entfernen.</summary>
function Dedented(const ALine: string; ACount: Integer): string;
var
  mRemoved: Integer;
begin
  Result := ALine;
  mRemoved := 0;
  while (mRemoved < ACount) and (Result <> '') and (Result[1] = ' ') do
  begin
    Delete(Result, 1, 1);
    Inc(mRemoved);
  end;
end;

procedure AppendLine(var ACode: string; const ALine: string);
begin
  if ACode <> '' then
  begin
    ACode := ACode + #10;
  end;
  ACode := ACode + ALine;
end;

type
  /// <summary>Zerlegt die Zeilen in Blöcke; jedes Try… liest einen Block ab Index und liefert True, wenn er dort
  /// beginnt.</summary>
  TBlockReader = record
    Lines: TArray<string>;
    Index: Integer;
    /// <summary>Einzüge der offenen Liste.</summary>
    Indents: TArray<Integer>;
    Blocks: TArray<TAtlasMarkdownBlock>;
    function CurrentLine: string;
    function HasLine: Boolean;
    procedure Add(const ABlock: TAtlasMarkdownBlock);
    function LevelOf(AIndent: Integer): Integer;
    function TryFence: Boolean;
    function TryHeading: Boolean;
    function TryRule: Boolean;
    function TryQuote: Boolean;
    function TryBullet: Boolean;
    function TryTable: Boolean;
    function TryImage: Boolean;
    function TryIndentedCode: Boolean;
    procedure ReadParagraph;
    function TryStructured: Boolean;
    function TryListLike: Boolean;
    procedure Step;
  end;

{ TBlockReader }

function TBlockReader.CurrentLine: string;
begin
  Result := Lines[Index];
end;

function TBlockReader.HasLine: Boolean;
begin
  Result := Index <= High(Lines);
end;

procedure TBlockReader.Add(const ABlock: TAtlasMarkdownBlock);
begin
  Blocks := Blocks + [ABlock];
end;

function TBlockReader.LevelOf(AIndent: Integer): Integer;
begin
  // Ebene aus den Einzügen der offenen Liste: tiefer eingerückt = eine Ebene tiefer.
  while (Length(Indents) > 0) and (Indents[High(Indents)] > AIndent) do
  begin
    SetLength(Indents, Length(Indents) - 1);
  end;
  if (Length(Indents) = 0) or (Indents[High(Indents)] < AIndent) then
  begin
    Indents := Indents + [AIndent];
  end;
  Result := Min(Length(Indents), TAtlasTrackerMarkdown.cMaxListLevel);
end;

/// <summary>Codeblock mit Zaun; ohne schließenden Zaun bis zum Ende.</summary>
function TBlockReader.TryFence: Boolean;
var
  mFence, mLanguage, mCode: string;
  mBase: Integer;
  mBlock: TAtlasMarkdownBlock;
begin
  Result := FenceOf(CurrentLine, mFence, mLanguage);
  if not Result then
  begin
    Exit;
  end;
  mBase := Indent(CurrentLine);
  mCode := '';
  Inc(Index);
  while HasLine and not ClosesFence(CurrentLine, mFence) do
  begin
    // Einzug des Zauns entfernen.
    AppendLine(mCode, Dedented(CurrentLine, mBase));
    Inc(Index);
  end;
  Inc(Index);
  mBlock := NewBlock(TAtlasMarkdownBlockKind.Code, mCode);
  mBlock.Info := mLanguage;
  Add(mBlock);
end;

function TBlockReader.TryHeading: Boolean;
var
  mLevel: Integer;
  mText: string;
  mBlock: TAtlasMarkdownBlock;
begin
  Result := HeadingOf(CurrentLine, mLevel, mText);
  if Result then
  begin
    mBlock := NewBlock(TAtlasMarkdownBlockKind.Heading, mText);
    mBlock.Level := mLevel;
    Add(mBlock);
    Inc(Index);
  end;
end;

/// <summary>Vor den Listen: "- - -" und "***" sind Trennlinien.</summary>
function TBlockReader.TryRule: Boolean;
begin
  Result := IsRule(CurrentLine);
  if Result then
  begin
    Add(NewBlock(TAtlasMarkdownBlockKind.Rule, ''));
    Inc(Index);
  end;
end;

function TBlockReader.TryQuote: Boolean;
var
  mText: string;
  mCode: TStringBuilder;
begin
  Result := QuoteOf(CurrentLine, mText);
  if not Result then
  begin
    Exit;
  end;
  mCode := TStringBuilder.Create(mText);
  try
    Inc(Index);
    while HasLine and QuoteOf(CurrentLine, mText) do
    begin
      mCode.Append(#10).Append(mText);
      Inc(Index);
    end;
    Add(NewBlock(TAtlasMarkdownBlockKind.Quote, Trim(mCode.ToString)));
  finally
    mCode.Free;
  end;
end;

function TBlockReader.TryBullet: Boolean;
var
  mIndent: Integer;
  mMarker, mText: string;
  mTask: TAtlasMarkdownTask;
  mBlock: TAtlasMarkdownBlock;
begin
  Result := ListItemOf(CurrentLine, mIndent, mMarker, mText, mTask);
  if not Result then
  begin
    Exit;
  end;
  mBlock := NewBlock(TAtlasMarkdownBlockKind.Bullet, mText);
  mBlock.ListMarker := mMarker;
  mBlock.Task := mTask;
  mBlock.Marker := TaskMarker(mTask, mMarker);
  mBlock.Level := LevelOf(mIndent);
  mBlock.Line := Index;
  Inc(Index);
  // Fortsetzungszeilen: eingerückt, kein neuer Punkt, kein anderer Block.
  while HasLine and not IsBlank(CurrentLine) and (Indent(CurrentLine) > mIndent) and
    not StartsBlock(Lines, Index) do
  begin
    mBlock.Text := mBlock.Text + #10 + Trim(CurrentLine);
    Inc(Index);
  end;
  mBlock.LastLine := Index - 1;
  Add(mBlock);
end;

function TBlockReader.TryTable: Boolean;
var
  mBlock: TAtlasMarkdownBlock;
begin
  Result := IsTableStart(Lines, Index);
  if not Result then
  begin
    Exit;
  end;
  mBlock := NewBlock(TAtlasMarkdownBlockKind.Table, '');
  mBlock.Rows := TArray<TArray<string>>.Create(SplitRow(CurrentLine));
  Inc(Index, 2);
  while HasLine and not IsBlank(CurrentLine) and (Pos('|', CurrentLine) > 0) do
  begin
    mBlock.Rows := mBlock.Rows + [SplitRow(CurrentLine)];
    Inc(Index);
  end;
  Add(mBlock);
end;

function TBlockReader.TryImage: Boolean;
var
  mText, mUrl: string;
  mBlock: TAtlasMarkdownBlock;
begin
  Result := ImageLineOf(CurrentLine, mText, mUrl);
  if Result then
  begin
    mBlock := NewBlock(TAtlasMarkdownBlockKind.Image, mText);
    mBlock.Info := mUrl;
    Add(mBlock);
    Inc(Index);
  end;
end;

/// <summary>Eingerückter Code (vier Leerzeichen) außerhalb von Absätzen.</summary>
function TBlockReader.TryIndentedCode: Boolean;
var
  mCode: string;
begin
  Result := Indent(CurrentLine) >= cCodeIndent;
  if not Result then
  begin
    Exit;
  end;
  mCode := '';
  while HasLine and (IsBlank(CurrentLine) or (Indent(CurrentLine) >= cCodeIndent)) do
  begin
    AppendLine(mCode, Copy(CurrentLine, cCodeIndent + 1, MaxInt));
    Inc(Index);
  end;
  Add(NewBlock(TAtlasMarkdownBlockKind.Code, TrimRight(mCode)));
end;

/// <summary>Absatz bis zur Leerzeile oder bis zu einem anderen Block.</summary>
procedure TBlockReader.ReadParagraph;
var
  mCode: TStringBuilder;
begin
  mCode := TStringBuilder.Create(Trim(CurrentLine));
  try
    Inc(Index);
    while HasLine and not IsBlank(CurrentLine) and not StartsBlock(Lines, Index) do
    begin
      mCode.Append(#10).Append(Trim(CurrentLine));
      Inc(Index);
    end;
    Add(NewBlock(TAtlasMarkdownBlockKind.Paragraph, mCode.ToString));
  finally
    mCode.Free;
  end;
end;

function TBlockReader.TryStructured: Boolean;
begin
  Result := TryFence or TryHeading or TryRule or TryQuote;
end;

function TBlockReader.TryListLike: Boolean;
begin
  Result := TryBullet or TryTable or TryImage or TryIndentedCode;
end;

procedure TBlockReader.Step;
var
  mIndent: Integer;
  mMarker, mText: string;
begin
  if IsBlank(CurrentLine) or IsHtmlComment(CurrentLine) then
  begin
    Inc(Index);
    Exit;
  end;
  if not ListItemOf(CurrentLine, mIndent, mMarker, mText) then
  begin
    Indents := nil;
  end;
  if not (TryStructured or TryListLike) then
  begin
    ReadParagraph;
  end;
end;

{ TAtlasTrackerMarkdown }

class function TAtlasTrackerMarkdown.Blocks(const AText: string): TArray<TAtlasMarkdownBlock>;
var
  mReader: TBlockReader;
begin
  mReader := Default(TBlockReader);
  mReader.Indents := nil;
  mReader.Blocks := nil;
  mReader.Lines := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10,
    [rfReplaceAll]).Split([#10]);
  mReader.Index := 0;
  while mReader.HasLine do
  begin
    mReader.Step;
  end;
  Result := mReader.Blocks;
end;

class function TAtlasTrackerMarkdown.InlineRuns(const AText: string): TAtlasDocRuns;
begin
  Result := InlineRuns(AText, False, False);
end;

class function TAtlasTrackerMarkdown.InlineRuns(const AText: string; ABold, AItalic: Boolean): TAtlasDocRuns;
begin
  Result := TAtlasMarkdownInline.Runs(AText, ABold, AItalic);
end;

class function TAtlasTrackerMarkdown.ToDoc(const AText: string): TAtlasDoc;
begin
  Result := ToDoc(AText, TAtlasMarkdownTasks.Boxes);
end;

function ParagraphRun: TAtlasDocRun;
begin
  Result := TAtlasDocRun.Create(TAtlasDocRunKind.Paragraph, '');
end;

/// <summary>Läufe eines Listenpunkts; ATaskIndex wie bei BlockRuns.</summary>
function BulletRuns(const ABlock: TAtlasMarkdownBlock; ANextIsBullet: Boolean; ATasks: TAtlasMarkdownTasks;
  var ATaskIndex: Integer): TAtlasDocRuns;
var
  mRun: TAtlasDocRun;
  mText: string;
begin
  mRun := TAtlasDocRun.Create(TAtlasDocRunKind.Bullet, ABlock.Marker);
  mRun.Level := ABlock.Level;
  mText := ABlock.Text;
  if ABlock.Task <> TAtlasMarkdownTask.None then
  begin
    case ATasks of
      // Wie geschrieben: Listenmarke und "[ ]" bzw. "[x]" als Text.
      TAtlasMarkdownTasks.Plain:
        begin
          mRun.Text := ABlock.ListMarker;
          if ABlock.Task = TAtlasMarkdownTask.Done then
          begin
            mText := '[x] ' + mText;
          end
          else
          begin
            mText := '[ ] ' + mText;
          end;
        end;
      TAtlasMarkdownTasks.Clickable:
        mRun.Target := TAtlasTrackerMarkdown.TaskTarget(ATaskIndex);
      TAtlasMarkdownTasks.Boxes: ;
    end;
    Inc(ATaskIndex);
  end;
  Result := TAtlasDocRuns.Create(mRun) + TAtlasTrackerMarkdown.InlineRuns(mText);
  // Nach dem letzten Punkt einer Liste ein Absatz (Abstand und Ende des hängenden Einzugs).
  if not ANextIsBullet then
  begin
    Result := Result + [ParagraphRun];
  end;
end;

/// <summary>Zweispaltig wie die Tabellen der XMLDoc: erste Zelle, dann die übrigen mit Trennern.</summary>
function TableRuns(const ABlock: TAtlasMarkdownBlock): TAtlasDocRuns;
var
  mRun: TAtlasDocRun;
  mRow: TArray<string>;
  mRowIndex, mCell: Integer;
begin
  Result := nil;
  for mRowIndex := 0 to High(ABlock.Rows) do
  begin
    mRow := ABlock.Rows[mRowIndex];
    if Length(mRow) = 0 then
    begin
      Continue;
    end;
    mRun := TAtlasDocRun.Create(TAtlasDocRunKind.Bullet, '');
    mRun.Level := 1;
    Result := Result + [mRun] + TAtlasTrackerMarkdown.InlineRuns(mRow[0], mRowIndex = 0, False) +
      [TAtlasDocRun.Create(TAtlasDocRunKind.Cell, '')];
    for mCell := 1 to High(mRow) do
    begin
      if mCell > 1 then
      begin
        Result := Result + [TAtlasDocRun.Create(TAtlasDocRunKind.Cell, '')];
      end;
      Result := Result + TAtlasTrackerMarkdown.InlineRuns(mRow[mCell], mRowIndex = 0, False);
    end;
  end;
  Result := Result + [ParagraphRun];
end;

/// <summary>Läufe eines Blocks (ohne Bild) samt Absatz am Ende. ATaskIndex: Nummer des nächsten Aufgabenpunkts;
/// ein Aufgabenpunkt zählt sie weiter.</summary>
function BlockRuns(const ABlock: TAtlasMarkdownBlock; ANextIsBullet: Boolean; ATasks: TAtlasMarkdownTasks;
  var ATaskIndex: Integer): TAtlasDocRuns;
var
  mRun: TAtlasDocRun;
begin
  Result := nil;
  case ABlock.Kind of
    TAtlasMarkdownBlockKind.Paragraph:
      Result := TAtlasTrackerMarkdown.InlineRuns(ABlock.Text) + [ParagraphRun];
    TAtlasMarkdownBlockKind.Heading:
      Result := TAtlasTrackerMarkdown.InlineRuns(ABlock.Text, True, False) + [ParagraphRun];
    TAtlasMarkdownBlockKind.Bullet:
      Result := BulletRuns(ABlock, ANextIsBullet, ATasks, ATaskIndex);
    TAtlasMarkdownBlockKind.Quote:
      begin
        mRun := TAtlasDocRun.Create(TAtlasDocRunKind.Bullet, cQuoteMarker);
        mRun.Level := 1;
        Result := TAtlasDocRuns.Create(mRun) + TAtlasTrackerMarkdown.InlineRuns(ABlock.Text, False, True) +
          [ParagraphRun];
      end;
    TAtlasMarkdownBlockKind.Code:
      Result := [TAtlasDocRun.Create(TAtlasDocRunKind.CodeBlock, ABlock.Text, ABlock.Info)];
    TAtlasMarkdownBlockKind.Table:
      Result := TableRuns(ABlock);
    TAtlasMarkdownBlockKind.Rule:
      Result := [ParagraphRun];
    TAtlasMarkdownBlockKind.Image:
      Result := [TAtlasDocRun.Create(TAtlasDocRunKind.Link, ABlock.Text, ABlock.Info), ParagraphRun];
  end;
  if (ABlock.Kind = TAtlasMarkdownBlockKind.Image) and (Result[0].Text = '') then
  begin
    Result[0].Text := Copy(ABlock.Info, LastDelimiter('/\', ABlock.Info) + 1, MaxInt);
  end;
end;

function DocOf(const ARuns: TAtlasDocRuns): TAtlasDoc;
var
  mSection: TAtlasDocSection;
  mRuns: TAtlasDocRuns;
begin
  Result := Default(TAtlasDoc);
  Result.Sections := nil;
  mRuns := ARuns;
  // Kein Abstand nach dem letzten Block.
  while (Length(mRuns) > 0) and (mRuns[High(mRuns)].Kind = TAtlasDocRunKind.Paragraph) do
  begin
    SetLength(mRuns, Length(mRuns) - 1);
  end;
  if Length(mRuns) = 0 then
  begin
    Exit;
  end;
  mSection := Default(TAtlasDocSection);
  mSection.Kind := TAtlasDocSectionKind.Summary;
  mSection.Runs := mRuns;
  Result.Sections := [mSection];
end;

function NextIsBullet(const ABlocks: TArray<TAtlasMarkdownBlock>; AIndex: Integer): Boolean;
begin
  Result := (AIndex < High(ABlocks)) and (ABlocks[AIndex + 1].Kind = TAtlasMarkdownBlockKind.Bullet);
end;

class function TAtlasTrackerMarkdown.ToDoc(const AText: string; ATasks: TAtlasMarkdownTasks): TAtlasDoc;
var
  mBlocks: TArray<TAtlasMarkdownBlock>;
  mRuns: TAtlasDocRuns;
  mIndex, mTask: Integer;
begin
  mBlocks := Blocks(AText);
  mRuns := nil;
  mTask := 0;
  for mIndex := 0 to High(mBlocks) do
  begin
    mRuns := mRuns + BlockRuns(mBlocks[mIndex], NextIsBullet(mBlocks, mIndex), ATasks, mTask);
  end;
  Result := DocOf(mRuns);
end;

class function TAtlasTrackerMarkdown.Segments(const AText: string): TArray<TAtlasMarkdownSegment>;
begin
  Result := Segments(AText, TAtlasMarkdownTasks.Boxes);
end;

class function TAtlasTrackerMarkdown.Segments(const AText: string;
  ATasks: TAtlasMarkdownTasks): TArray<TAtlasMarkdownSegment>;
var
  mBlocks: TArray<TAtlasMarkdownBlock>;
  mRuns: TAtlasDocRuns;
  mIndex, mTask: Integer;
  mSegment: TAtlasMarkdownSegment;

  procedure FlushDoc;
  var
    mDoc: TAtlasDoc;
  begin
    mDoc := DocOf(mRuns);
    mRuns := nil;
    if mDoc.IsEmpty then
    begin
      Exit;
    end;
    mSegment := Default(TAtlasMarkdownSegment);
    mSegment.Kind := TAtlasMarkdownSegmentKind.Doc;
    mSegment.Doc := mDoc;
    Result := Result + [mSegment];
  end;

begin
  Result := nil;
  mRuns := nil;
  mTask := 0;
  mBlocks := Blocks(AText);
  for mIndex := 0 to High(mBlocks) do
  begin
    if mBlocks[mIndex].Kind <> TAtlasMarkdownBlockKind.Image then
    begin
      mRuns := mRuns + BlockRuns(mBlocks[mIndex], NextIsBullet(mBlocks, mIndex), ATasks, mTask);
      Continue;
    end;
    FlushDoc;
    mSegment := Default(TAtlasMarkdownSegment);
    mSegment.Kind := TAtlasMarkdownSegmentKind.Image;
    mSegment.Image := TAtlasMarkdownLink.Create(mBlocks[mIndex].Text, mBlocks[mIndex].Info);
    Result := Result + [mSegment];
  end;
  FlushDoc;
end;

class function TAtlasTrackerMarkdown.TaskTarget(AIndex: Integer): string;
begin
  Result := cTaskPrefix + IntToStr(AIndex);
end;

class function TAtlasTrackerMarkdown.TaskIndexOf(const ATarget: string; out AIndex: Integer): Boolean;
begin
  AIndex := -1;
  Result := StartsStr(cTaskPrefix, ATarget) and TryStrToInt(Copy(ATarget, Length(cTaskPrefix) + 1, MaxInt), AIndex)
    and (AIndex >= 0);
  if not Result then
  begin
    AIndex := -1;
  end;
end;

class function TAtlasTrackerMarkdown.Links(const AText: string): TArray<TAtlasMarkdownLink>;
var
  mBlock: TAtlasMarkdownBlock;
  mRun: TAtlasDocRun;
  mRow: TArray<string>;
  mCell: string;
  mRuns: TAtlasDocRuns;
begin
  Result := nil;
  for mBlock in Blocks(AText) do
  begin
    mRuns := nil;
    case mBlock.Kind of
      TAtlasMarkdownBlockKind.Paragraph, TAtlasMarkdownBlockKind.Heading, TAtlasMarkdownBlockKind.Bullet,
      TAtlasMarkdownBlockKind.Quote:
        mRuns := InlineRuns(mBlock.Text);
      TAtlasMarkdownBlockKind.Table:
        for mRow in mBlock.Rows do
        begin
          for mCell in mRow do
          begin
            mRuns := mRuns + InlineRuns(mCell);
          end;
        end;
      TAtlasMarkdownBlockKind.Image:
        Result := Result + [TAtlasMarkdownLink.Create(mBlock.Text, mBlock.Info)];
      TAtlasMarkdownBlockKind.Code, TAtlasMarkdownBlockKind.Rule: ;
    end;
    for mRun in mRuns do
    begin
      if mRun.Kind = TAtlasDocRunKind.Link then
      begin
        Result := Result + [TAtlasMarkdownLink.Create(mRun.Text, mRun.Target)];
      end;
    end;
  end;
end;

class function TAtlasTrackerMarkdown.DecodeHtml(const AText: string): string;
begin
  Result := TAtlasMarkdownInline.DecodeHtml(AText);
end;

end.
