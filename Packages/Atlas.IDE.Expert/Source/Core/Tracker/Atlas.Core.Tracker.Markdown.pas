unit Atlas.Core.Tracker.Markdown;

// Markdown aus YouTrack und GitHub für das Fenster „Atlas-Issue“ (#1264),
// ohne VCL und Open Tools API.
// - Blocks zerlegt den Text in Blöcke: Absatz, Überschrift (#…), Listenpunkt
//   (-, *, +, 1. mit Ebene und Aufgabenkästchen), Zitat (>), Codeblock
//   (```lang bzw. ~~~ und vier Leerzeichen Einzug), Tabelle (Kopfzeile mit
//   |---|), Trennlinie und alleinstehendes Bild (![alt](url), <img src=…>).
//   Einfache Zeilenumbrüche bleiben Umbrüche, wie in Issues bei GitHub und
//   YouTrack.
// - InlineRuns setzt einen Absatz in Doku-Läufe (TAtlasDoc, wie die XMLDoc in
//   Hover und Detailpanel): **fett**, *kursiv*, `Code`, [Links](url),
//   <https://…>, nackte https-Adressen, Bilder im Fließtext als Link,
//   HTML-Tags entfallen (<br> wird Umbruch), Entitäten werden ersetzt.
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
    MaxListLevel = 4;
    /// <summary>Ziel an der Marke eines anklickbaren Aufgabenpunkts (#1273), gefolgt von seiner Nummer ab 0.
    /// </summary>
    TaskPrefix = 'atlas-task:';
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
  Atlas.Text.Chars,
  Atlas.Text.Entities;

const
  cBullet = '•';
  cTaskOpen = '☐';
  cTaskDone = '☑';
  cQuoteMarker = '│';

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
    if ALine[mIndex] = ' ' then
      Inc(Result)
    else if ALine[mIndex] = #9 then
      Inc(Result, 4)
    else
      Exit;
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
  if Indent(ALine) > 3 then
    Exit;
  mText := TrimLeft(ALine);
  if Length(mText) < 3 then
    Exit;
  mChar := mText[1];
  if (mChar <> '`') and (mChar <> '~') then
    Exit;
  mCount := 0;
  while (mCount < Length(mText)) and (mText[mCount + 1] = mChar) do
    Inc(mCount);
  if mCount < 3 then
    Exit;
  AFence := StringOfChar(mChar, mCount);
  ALanguage := Trim(Copy(mText, mCount + 1, MaxInt));
  // Nur das erste Wort: "pascal title=x" bzw. "{.delphi}".
  if Pos(' ', ALanguage) > 0 then
    ALanguage := Copy(ALanguage, 1, Pos(' ', ALanguage) - 1);
  ALanguage := ALanguage.Trim(['{', '}', '.']);
  // Ein Backtick-Zaun darf keine Backticks in der Info haben (sonst ist es Code im Fließtext).
  Result := (mChar <> '`') or (Pos('`', ALanguage) = 0);
end;

function ClosesFence(const ALine, AFence: string): Boolean;
var
  mText: string;
begin
  mText := Trim(ALine);
  Result := (Indent(ALine) <= 3) and (Length(mText) >= Length(AFence)) and
    (mText = StringOfChar(AFence[1], Length(mText)));
end;

function HeadingOf(const ALine: string; out ALevel: Integer; out AText: string): Boolean;
var
  mText: string;
begin
  Result := False;
  ALevel := 0;
  AText := '';
  if Indent(ALine) > 3 then
    Exit;
  mText := TrimLeft(ALine);
  while (ALevel < Length(mText)) and (mText[ALevel + 1] = '#') do
    Inc(ALevel);
  if (ALevel < 1) or (ALevel > 6) then
    Exit;
  if (Length(mText) > ALevel) and (mText[ALevel + 1] <> ' ') and (mText[ALevel + 1] <> #9) then
    Exit;
  AText := Trim(Copy(mText, ALevel + 1, MaxInt));
  // Schließende # ("## Titel ##").
  while (AText <> '') and (AText[Length(AText)] = '#') do
    Delete(AText, Length(AText), 1);
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
  if Indent(ALine) > 3 then
    Exit;
  mText := Trim(ALine);
  if mText = '' then
    Exit;
  mChar := mText[1];
  if (mChar <> '-') and (mChar <> '*') and (mChar <> '_') then
    Exit;
  mCount := 0;
  for mIndex := 1 to Length(mText) do
    if mText[mIndex] = mChar then
      Inc(mCount)
    else if mText[mIndex] <> ' ' then
      Exit;
  Result := mCount >= 3;
end;

function QuoteOf(const ALine: string; out AText: string): Boolean;
var
  mText: string;
begin
  AText := '';
  mText := TrimLeft(ALine);
  Result := (Indent(ALine) <= 3) and (mText <> '') and (mText[1] = '>');
  if not Result then
    Exit;
  AText := Copy(mText, 2, MaxInt);
  if (AText <> '') and (AText[1] = ' ') then
    Delete(AText, 1, 1);
end;

/// <summary>Listenpunkt: AMarker "•" bzw. "1.", ATask das Aufgabenkästchen davor (Text ohne Kästchen).</summary>
function ListItemOf(const ALine: string; out AIndent: Integer; out AMarker, AText: string;
  out ATask: TAtlasMarkdownTask): Boolean; overload;
var
  mText: string;
  mDigits: Integer;
begin
  Result := False;
  AMarker := '';
  AText := '';
  ATask := TAtlasMarkdownTask.None;
  AIndent := Indent(ALine);
  mText := TrimLeft(ALine);
  if mText = '' then
    Exit;
  if CharInSet(mText[1], ['-', '*', '+']) then
  begin
    if (Length(mText) > 1) and (mText[2] <> ' ') and (mText[2] <> #9) then
      Exit;
    AMarker := cBullet;
    AText := Trim(Copy(mText, 2, MaxInt));
  end
  else
  begin
    mDigits := 0;
    while (mDigits < Length(mText)) and (mDigits < 9) and CharInSet(mText[mDigits + 1], ['0'..'9']) do
      Inc(mDigits);
    if (mDigits = 0) or (mDigits >= Length(mText)) or not CharInSet(mText[mDigits + 1], ['.', ')']) then
      Exit;
    if (Length(mText) > mDigits + 1) and (mText[mDigits + 2] <> ' ') and (mText[mDigits + 2] <> #9) then
      Exit;
    AMarker := Copy(mText, 1, mDigits) + '.';
    AText := Trim(Copy(mText, mDigits + 2, MaxInt));
  end;
  // Aufgabenliste: "- [ ] offen", "- [x] erledigt", auch nummeriert (#1273).
  if StartsText('[ ] ', AText + ' ') then
  begin
    ATask := TAtlasMarkdownTask.Open;
    AText := Trim(Copy(AText, 4, MaxInt));
  end
  else if StartsText('[x] ', AText + ' ') then
  begin
    ATask := TAtlasMarkdownTask.Done;
    AText := Trim(Copy(AText, 4, MaxInt));
  end;
  Result := True;
end;

function ListItemOf(const ALine: string; out AIndent: Integer; out AMarker, AText: string): Boolean; overload;
var
  mTask: TAtlasMarkdownTask;
begin
  Result := ListItemOf(ALine, AIndent, AMarker, AText, mTask);
end;

function SplitRow(const ALine: string): TArray<string>;
var
  mText, mCell: string;
  mIndex: Integer;
  mEscaped, mInCode: Boolean;
begin
  Result := nil;
  mText := Trim(ALine);
  if (mText <> '') and (mText[1] = '|') then
    Delete(mText, 1, 1);
  if (mText <> '') and (mText[Length(mText)] = '|') and ((Length(mText) < 2) or (mText[Length(mText) - 1] <> '\'))
    then
    Delete(mText, Length(mText), 1);
  mCell := '';
  mEscaped := False;
  mInCode := False;
  for mIndex := 1 to Length(mText) do
  begin
    if mEscaped then
    begin
      if mText[mIndex] <> '|' then
        mCell := mCell + '\';
      mCell := mCell + mText[mIndex];
      mEscaped := False;
      Continue;
    end;
    if mText[mIndex] = '\' then
    begin
      mEscaped := True;
      Continue;
    end;
    if mText[mIndex] = '`' then
      mInCode := not mInCode;
    if (mText[mIndex] = '|') and not mInCode then
    begin
      Result := Result + [Trim(mCell)];
      mCell := '';
    end
    else
      mCell := mCell + mText[mIndex];
  end;
  Result := Result + [Trim(mCell)];
end;

function IsTableSeparator(const ALine: string): Boolean;
var
  mCell, mText: string;
  mIndex: Integer;
  mCells: TArray<string>;
begin
  Result := False;
  if Pos('-', ALine) = 0 then
    Exit;
  mCells := SplitRow(ALine);
  if Length(mCells) = 0 then
    Exit;
  for mCell in mCells do
  begin
    mText := mCell.Trim([':']);
    if mText = '' then
      Exit;
    for mIndex := 1 to Length(mText) do
      if mText[mIndex] <> '-' then
        Exit;
  end;
  Result := True;
end;

function IsTableStart(const ALines: TArray<string>; AIndex: Integer): Boolean;
begin
  Result := (AIndex < High(ALines)) and (Pos('|', ALines[AIndex]) > 0) and IsTableSeparator(ALines[AIndex + 1]);
end;

/// <summary>Wert des Attributs AName in einem HTML-Tag (src="…" bzw. alt='…'); '' ohne.</summary>
function AttributeOf(const ATag, AName: string): string;
var
  mPos, mStop: Integer;
  mQuote: Char;
begin
  Result := '';
  mPos := Pos(LowerCase(AName) + '=', LowerCase(ATag));
  if mPos = 0 then
    Exit;
  mPos := mPos + Length(AName) + 1;
  if mPos > Length(ATag) then
    Exit;
  mQuote := ATag[mPos];
  if (mQuote = '"') or (mQuote = '''') then
  begin
    mStop := PosEx(mQuote, ATag, mPos + 1);
    if mStop > 0 then
      Result := Copy(ATag, mPos + 1, mStop - mPos - 1);
  end
  else
  begin
    mStop := mPos;
    while (mStop <= Length(ATag)) and not CharInSet(ATag[mStop], [' ', '>', '/']) do
      Inc(mStop);
    Result := Copy(ATag, mPos, mStop - mPos);
  end;
end;

/// <summary>Zeile ist genau ein Bild: ![alt](url) (YouTrack auch mit {width=…}) bzw. &lt;img … src=…&gt;.</summary>
function ImageLineOf(const ALine: string; out AAlt, AUrl: string): Boolean;
var
  mText: string;
  mClose, mOpen, mStop: Integer;
begin
  Result := False;
  AAlt := '';
  AUrl := '';
  mText := Trim(ALine);
  if StartsText('<img', mText) and (mText[Length(mText)] = '>') and (Pos('>', mText) = Length(mText)) then
  begin
    AUrl := TAtlasTrackerMarkdown.DecodeHtml(AttributeOf(mText, 'src'));
    AAlt := TAtlasTrackerMarkdown.DecodeHtml(AttributeOf(mText, 'alt'));
    Exit(AUrl <> '');
  end;
  if not StartsStr('![', mText) then
    Exit;
  mClose := Pos('](', mText);
  if mClose = 0 then
    Exit;
  mOpen := mClose + 1;
  mStop := PosEx(')', mText, mOpen + 1);
  if mStop = 0 then
    Exit;
  // Danach nur noch Attribute in geschweiften Klammern.
  if (mStop < Length(mText)) and ((mText[mStop + 1] <> '{') or (mText[Length(mText)] <> '}')) then
    Exit;
  AAlt := Copy(mText, 3, mClose - 3);
  AUrl := Trim(Copy(mText, mOpen + 1, mStop - mOpen - 1));
  // Titel nach der Adresse: ![a](bild.png "Titel").
  if Pos(' ', AUrl) > 0 then
    AUrl := Copy(AUrl, 1, Pos(' ', AUrl) - 1);
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

{ TAtlasTrackerMarkdown }

class function TAtlasTrackerMarkdown.Blocks(const AText: string): TArray<TAtlasMarkdownBlock>;
var
  mLines, mCells: TArray<string>;
  mIndex, mLevel, mIndent, mBase: Integer;
  mLine, mFence, mLanguage, mText, mMarker, mCode, mUrl: string;
  mBlock: TAtlasMarkdownBlock;
  mIndents: TArray<Integer>;
  mTask: TAtlasMarkdownTask;

  procedure Add(const ABlock: TAtlasMarkdownBlock);
  begin
    Result := Result + [ABlock];
  end;

  function LevelOf(AIndent: Integer): Integer;
  var
    mProbe: Integer;
  begin
    // Ebene aus den Einzügen der offenen Liste: tiefer eingerückt = eine Ebene tiefer.
    while (Length(mIndents) > 0) and (mIndents[High(mIndents)] > AIndent) do
      SetLength(mIndents, Length(mIndents) - 1);
    if (Length(mIndents) = 0) or (mIndents[High(mIndents)] < AIndent) then
      mIndents := mIndents + [AIndent];
    mProbe := Length(mIndents);
    if mProbe > MaxListLevel then
      mProbe := MaxListLevel;
    Result := mProbe;
  end;

begin
  Result := nil;
  mIndents := nil;
  mLines := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]).Split([#10]);
  mIndex := 0;
  while mIndex <= High(mLines) do
  begin
    mLine := mLines[mIndex];
    if IsBlank(mLine) or IsHtmlComment(mLine) then
    begin
      Inc(mIndex);
      Continue;
    end;
    if not ListItemOf(mLine, mIndent, mMarker, mText) then
      mIndents := nil;
    // Codeblock mit Zaun; ohne schließenden Zaun bis zum Ende.
    if FenceOf(mLine, mFence, mLanguage) then
    begin
      mBase := Indent(mLine);
      mCode := '';
      Inc(mIndex);
      while (mIndex <= High(mLines)) and not ClosesFence(mLines[mIndex], mFence) do
      begin
        mText := mLines[mIndex];
        // Einzug des Zauns entfernen.
        mLevel := 0;
        while (mLevel < mBase) and (mText <> '') and (mText[1] = ' ') do
        begin
          Delete(mText, 1, 1);
          Inc(mLevel);
        end;
        if mCode <> '' then
          mCode := mCode + #10;
        mCode := mCode + mText;
        Inc(mIndex);
      end;
      Inc(mIndex);
      mBlock := NewBlock(TAtlasMarkdownBlockKind.Code, mCode);
      mBlock.Info := mLanguage;
      Add(mBlock);
      Continue;
    end;
    if HeadingOf(mLine, mLevel, mText) then
    begin
      mBlock := NewBlock(TAtlasMarkdownBlockKind.Heading, mText);
      mBlock.Level := mLevel;
      Add(mBlock);
      Inc(mIndex);
      Continue;
    end;
    // Vor den Listen: "- - -" und "***" sind Trennlinien.
    if IsRule(mLine) then
    begin
      Add(NewBlock(TAtlasMarkdownBlockKind.Rule, ''));
      Inc(mIndex);
      Continue;
    end;
    if QuoteOf(mLine, mText) then
    begin
      mCode := mText;
      Inc(mIndex);
      while (mIndex <= High(mLines)) and QuoteOf(mLines[mIndex], mText) do
      begin
        mCode := mCode + #10 + mText;
        Inc(mIndex);
      end;
      Add(NewBlock(TAtlasMarkdownBlockKind.Quote, Trim(mCode)));
      Continue;
    end;
    if ListItemOf(mLine, mIndent, mMarker, mText, mTask) then
    begin
      mBlock := NewBlock(TAtlasMarkdownBlockKind.Bullet, mText);
      mBlock.ListMarker := mMarker;
      mBlock.Task := mTask;
      case mTask of
        TAtlasMarkdownTask.Open:
          mBlock.Marker := cTaskOpen;
        TAtlasMarkdownTask.Done:
          mBlock.Marker := cTaskDone;
      else
        mBlock.Marker := mMarker;
      end;
      mBlock.Level := LevelOf(mIndent);
      mBlock.Line := mIndex;
      Inc(mIndex);
      // Fortsetzungszeilen: eingerückt, kein neuer Punkt, kein anderer Block.
      while (mIndex <= High(mLines)) and not IsBlank(mLines[mIndex]) and (Indent(mLines[mIndex]) > mIndent) and
        not StartsBlock(mLines, mIndex) do
      begin
        mBlock.Text := mBlock.Text + #10 + Trim(mLines[mIndex]);
        Inc(mIndex);
      end;
      mBlock.LastLine := mIndex - 1;
      Add(mBlock);
      Continue;
    end;
    if IsTableStart(mLines, mIndex) then
    begin
      mBlock := NewBlock(TAtlasMarkdownBlockKind.Table, '');
      mBlock.Rows := TArray<TArray<string>>.Create(SplitRow(mLine));
      Inc(mIndex, 2);
      while (mIndex <= High(mLines)) and not IsBlank(mLines[mIndex]) and (Pos('|', mLines[mIndex]) > 0) do
      begin
        mCells := SplitRow(mLines[mIndex]);
        mBlock.Rows := mBlock.Rows + [mCells];
        Inc(mIndex);
      end;
      Add(mBlock);
      Continue;
    end;
    if ImageLineOf(mLine, mText, mUrl) then
    begin
      mBlock := NewBlock(TAtlasMarkdownBlockKind.Image, mText);
      mBlock.Info := mUrl;
      Add(mBlock);
      Inc(mIndex);
      Continue;
    end;
    // Eingerückter Code (vier Leerzeichen) außerhalb von Absätzen.
    if Indent(mLine) >= 4 then
    begin
      mCode := '';
      while (mIndex <= High(mLines)) and (IsBlank(mLines[mIndex]) or (Indent(mLines[mIndex]) >= 4)) do
      begin
        if mCode <> '' then
          mCode := mCode + #10;
        mCode := mCode + Copy(mLines[mIndex], 5, MaxInt);
        Inc(mIndex);
      end;
      Add(NewBlock(TAtlasMarkdownBlockKind.Code, TrimRight(mCode)));
      Continue;
    end;
    // Absatz bis zur Leerzeile oder bis zu einem anderen Block.
    mCode := Trim(mLine);
    Inc(mIndex);
    while (mIndex <= High(mLines)) and not IsBlank(mLines[mIndex]) and not StartsBlock(mLines, mIndex) do
    begin
      mCode := mCode + #10 + Trim(mLines[mIndex]);
      Inc(mIndex);
    end;
    Add(NewBlock(TAtlasMarkdownBlockKind.Paragraph, mCode));
  end;
end;

class function TAtlasTrackerMarkdown.DecodeHtml(const AText: string): string;
begin
  // &nbsp; kennt nur HTML; alles Übrige wie in XML über Atlas.Text (ADR 0012).
  Result := TTextEntities.Decode(StringReplace(AText, '&nbsp;', ' ', [rfReplaceAll]));
end;

{ Fließtext }

type
  TInlineBuilder = record
    Runs: TAtlasDocRuns;
    Text: string;
    Bold: Boolean;
    Italic: Boolean;
    BaseBold: Boolean;
    BaseItalic: Boolean;
    procedure Flush;
    procedure Add(const ARun: TAtlasDocRun);
    procedure AddLink(const AText, AUrl: string);
    procedure AddCode(const AText: string);
    procedure AddBreak;
  end;

procedure TInlineBuilder.Flush;
var
  mRun: TAtlasDocRun;
begin
  if Text = '' then
    Exit;
  mRun := TAtlasDocRun.Create(TAtlasDocRunKind.Text, Text);
  mRun.Bold := Bold or BaseBold;
  mRun.Italic := Italic or BaseItalic;
  Runs := Runs + [mRun];
  Text := '';
end;

procedure TInlineBuilder.Add(const ARun: TAtlasDocRun);
begin
  Flush;
  Runs := Runs + [ARun];
end;

procedure TInlineBuilder.AddLink(const AText, AUrl: string);
var
  mRun: TAtlasDocRun;
  mText: string;
begin
  mText := AText;
  if mText = '' then
    mText := AUrl;
  mRun := TAtlasDocRun.Create(TAtlasDocRunKind.Link, mText, AUrl);
  mRun.Bold := Bold or BaseBold;
  mRun.Italic := Italic or BaseItalic;
  Add(mRun);
end;

procedure TInlineBuilder.AddCode(const AText: string);
begin
  Add(TAtlasDocRun.Create(TAtlasDocRunKind.Code, AText));
end;

procedure TInlineBuilder.AddBreak;
begin
  Add(TAtlasDocRun.Create(TAtlasDocRunKind.LineBreak, ''));
end;

/// <summary>Ende eines [Text](Adresse) ab der öffnenden Klammer AIndex; 0 ohne.</summary>
function LinkEnd(const AText: string; AIndex: Integer; out ALabel, AUrl: string): Integer;
var
  mDepth, mProbe, mClose: Integer;
begin
  Result := 0;
  ALabel := '';
  AUrl := '';
  mDepth := 0;
  mClose := 0;
  for mProbe := AIndex to Length(AText) do
  begin
    if AText[mProbe] = '[' then
      Inc(mDepth)
    else if AText[mProbe] = ']' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        mClose := mProbe;
        Break;
      end;
    end
    else if AText[mProbe] = #10 then
      Exit;
  end;
  if (mClose = 0) or (mClose >= Length(AText)) or (AText[mClose + 1] <> '(') then
    Exit;
  mProbe := PosEx(')', AText, mClose + 2);
  if mProbe = 0 then
    Exit;
  ALabel := Copy(AText, AIndex + 1, mClose - AIndex - 1);
  AUrl := Trim(Copy(AText, mClose + 2, mProbe - mClose - 2));
  if Pos(' ', AUrl) > 0 then
    AUrl := Copy(AUrl, 1, Pos(' ', AUrl) - 1);
  AUrl := AUrl.Trim(['<', '>']);
  Result := mProbe;
  // YouTrack: Attribute nach dem Bild ({width=70%}).
  if (Result < Length(AText)) and (AText[Result + 1] = '{') and (PosEx('}', AText, Result + 1) > 0) then
    Result := PosEx('}', AText, Result + 1);
end;

/// <summary>Nackte Adresse ab AIndex ("https://…"); Satzzeichen am Ende gehören nicht dazu.</summary>
function BareUrlEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and not CharInSet(AText[Result], [' ', #9, #10, '<', '>', '"']) do
    Inc(Result);
  Dec(Result);
  while (Result > AIndex) and CharInSet(AText[Result], ['.', ',', ';', ':', '!', '?', ')', '''']) do
    Dec(Result);
end;

/// <summary>Ein schließendes ADelimiter folgt noch (sonst ist es kein Hervorheben).</summary>
function HasCloser(const AText, ADelimiter: string; AFrom: Integer): Boolean;
var
  mProbe: Integer;
begin
  mProbe := PosEx(ADelimiter, AText, AFrom);
  while mProbe > 0 do
  begin
    // Schließend: davor kein Leerzeichen.
    if (mProbe > AFrom) and not CharInSet(AText[mProbe - 1], [' ', #9, #10]) then
      Exit(True);
    mProbe := PosEx(ADelimiter, AText, mProbe + Length(ADelimiter));
  end;
  Result := False;
end;

class function TAtlasTrackerMarkdown.InlineRuns(const AText: string; ABold, AItalic: Boolean): TAtlasDocRuns;
var
  mBuilder: TInlineBuilder;
  mText, mLabel, mUrl, mTag, mDelimiter: string;
  mIndex, mStop, mTicks, mClose: Integer;
  mChar, mNext, mPrev: Char;
begin
  mBuilder := Default(TInlineBuilder);
  mBuilder.Runs := nil;
  mBuilder.BaseBold := ABold;
  mBuilder.BaseItalic := AItalic;
  mText := AText;
  mIndex := 1;
  while mIndex <= Length(mText) do
  begin
    mChar := mText[mIndex];
    if mIndex < Length(mText) then
      mNext := mText[mIndex + 1]
    else
      mNext := #0;
    if mIndex > 1 then
      mPrev := mText[mIndex - 1]
    else
      mPrev := ' ';
    // Maskiert: \* \_ \` \[ …
    if (mChar = '\') and (mNext <> #0) and CharInSet(mNext, ['\', '`', '*', '_', '{', '}', '[', ']', '(', ')', '#',
      '+', '-', '.', '!', '|', '<', '>', '~']) then
    begin
      mBuilder.Text := mBuilder.Text + mNext;
      Inc(mIndex, 2);
      Continue;
    end;
    // Umbruch; Zeile mit "\" bzw. zwei Leerzeichen am Ende ist derselbe Umbruch.
    if mChar = #10 then
    begin
      mBuilder.Text := TrimRight(mBuilder.Text);
      if EndsStr('\', mBuilder.Text) then
        Delete(mBuilder.Text, Length(mBuilder.Text), 1);
      mBuilder.AddBreak;
      Inc(mIndex);
      Continue;
    end;
    // Code im Fließtext: gleich viele Backticks schließen.
    if mChar = '`' then
    begin
      mTicks := 0;
      while (mIndex + mTicks <= Length(mText)) and (mText[mIndex + mTicks] = '`') do
        Inc(mTicks);
      mClose := PosEx(StringOfChar('`', mTicks), mText, mIndex + mTicks);
      if mClose > 0 then
      begin
        mBuilder.AddCode(Trim(StringReplace(Copy(mText, mIndex + mTicks, mClose - mIndex - mTicks), #10, ' ',
          [rfReplaceAll])));
        mIndex := mClose + mTicks;
        Continue;
      end;
      mBuilder.Text := mBuilder.Text + StringOfChar('`', mTicks);
      Inc(mIndex, mTicks);
      Continue;
    end;
    // Bild im Fließtext: als Link mit dem Alternativtext.
    if (mChar = '!') and (mNext = '[') then
    begin
      mStop := LinkEnd(mText, mIndex + 1, mLabel, mUrl);
      if mStop > 0 then
      begin
        if mLabel = '' then
          mLabel := Copy(mUrl, LastDelimiter('/\', mUrl) + 1, MaxInt);
        mBuilder.AddLink(mLabel, mUrl);
        mIndex := mStop + 1;
        Continue;
      end;
    end;
    if mChar = '[' then
    begin
      mStop := LinkEnd(mText, mIndex, mLabel, mUrl);
      if mStop > 0 then
      begin
        // Hervorhebungen im Linktext entfallen.
        mLabel := StringReplace(StringReplace(mLabel, '**', '', [rfReplaceAll]), '`', '', [rfReplaceAll]);
        mBuilder.AddLink(DecodeHtml(mLabel), mUrl);
        mIndex := mStop + 1;
        Continue;
      end;
    end;
    // <https://…> bzw. HTML-Tag.
    if mChar = '<' then
    begin
      mStop := PosEx('>', mText, mIndex + 1);
      if mStop > 0 then
      begin
        mTag := Copy(mText, mIndex + 1, mStop - mIndex - 1);
        if StartsText('http://', mTag) or StartsText('https://', mTag) then
        begin
          mBuilder.AddLink(mTag, mTag);
          mIndex := mStop + 1;
          Continue;
        end;
        if (mTag <> '') and (CharInSet(mTag[1], ['a'..'z', 'A'..'Z', '/', '!'])) and (Pos(#10, mTag) = 0) then
        begin
          if SameText(mTag.TrimRight(['/', ' ']), 'br') then
            mBuilder.AddBreak
          else if StartsText('img', mTag) and (AttributeOf(mTag, 'src') <> '') then
            mBuilder.AddLink(DecodeHtml(AttributeOf(mTag, 'alt')), DecodeHtml(AttributeOf(mTag, 'src')))
          else if StartsText('a ', mTag) and (AttributeOf(mTag, 'href') <> '') then
          begin
            // <a href="…">Text</a>: Text als Link.
            mClose := PosEx('</a>', LowerCase(mText), mStop + 1);
            if mClose > 0 then
            begin
              mBuilder.AddLink(DecodeHtml(Copy(mText, mStop + 1, mClose - mStop - 1)),
                DecodeHtml(AttributeOf(mTag, 'href')));
              mIndex := mClose + 4;
              Continue;
            end;
          end;
          mIndex := mStop + 1;
          Continue;
        end;
      end;
    end;
    // Nackte Adresse (GitHub verlinkt sie).
    if ((mChar = 'h') or (mChar = 'H')) and not TTextChars.IsIdentChar(mPrev) and (StartsText('https://', Copy(mText, mIndex, 8))
      or StartsText('http://', Copy(mText, mIndex, 7))) then
    begin
      mStop := BareUrlEnd(mText, mIndex);
      mUrl := Copy(mText, mIndex, mStop - mIndex + 1);
      mBuilder.AddLink(mUrl, mUrl);
      mIndex := mStop + 1;
      Continue;
    end;
    // Durchgestrichen: Zeichen entfallen.
    if (mChar = '~') and (mNext = '~') then
    begin
      Inc(mIndex, 2);
      Continue;
    end;
    // Fett und kursiv: ** bzw. __, * bzw. _; "_" nur an Wortgrenzen (snake_case bleibt).
    if (mChar = '*') or (mChar = '_') then
    begin
      if mNext = mChar then
        mDelimiter := mChar + mChar
      else
        mDelimiter := mChar;
      if (mChar = '_') and TTextChars.IsIdentChar(mPrev) and (mIndex + Length(mDelimiter) <= Length(mText)) and
        TTextChars.IsIdentChar(mText[mIndex + Length(mDelimiter)]) then
      begin
        mBuilder.Text := mBuilder.Text + mDelimiter;
        Inc(mIndex, Length(mDelimiter));
        Continue;
      end;
      if Length(mDelimiter) = 2 then
      begin
        if mBuilder.Bold and not CharInSet(mPrev, [' ', #9]) then
        begin
          mBuilder.Flush;
          mBuilder.Bold := False;
          Inc(mIndex, 2);
          Continue;
        end;
        if not mBuilder.Bold and (mIndex + 2 <= Length(mText)) and not CharInSet(mText[mIndex + 2], [' ', #9, #10])
          and HasCloser(mText, mDelimiter, mIndex + 3) then
        begin
          mBuilder.Flush;
          mBuilder.Bold := True;
          Inc(mIndex, 2);
          Continue;
        end;
      end
      else
      begin
        if mBuilder.Italic and not CharInSet(mPrev, [' ', #9]) then
        begin
          mBuilder.Flush;
          mBuilder.Italic := False;
          Inc(mIndex);
          Continue;
        end;
        if not mBuilder.Italic and (mNext <> #0) and not CharInSet(mNext, [' ', #9, #10]) and
          HasCloser(mText, mDelimiter, mIndex + 2) then
        begin
          mBuilder.Flush;
          mBuilder.Italic := True;
          Inc(mIndex);
          Continue;
        end;
      end;
      mBuilder.Text := mBuilder.Text + mDelimiter;
      Inc(mIndex, Length(mDelimiter));
      Continue;
    end;
    if mChar = '&' then
    begin
      mStop := PosEx(';', mText, mIndex + 1);
      if (mStop > 0) and (mStop - mIndex <= 8) then
      begin
        mBuilder.Text := mBuilder.Text + DecodeHtml(Copy(mText, mIndex, mStop - mIndex + 1));
        mIndex := mStop + 1;
        Continue;
      end;
    end;
    mBuilder.Text := mBuilder.Text + mChar;
    Inc(mIndex);
  end;
  mBuilder.Flush;
  Result := mBuilder.Runs;
end;

class function TAtlasTrackerMarkdown.InlineRuns(const AText: string): TAtlasDocRuns;
begin
  Result := InlineRuns(AText, False, False);
end;

/// <summary>Läufe eines Blocks (ohne Bild) samt Absatz am Ende. ATaskIndex: Nummer des nächsten Aufgabenpunkts;
/// ein Aufgabenpunkt zählt sie weiter.</summary>
function BlockRuns(const ABlock: TAtlasMarkdownBlock; ANextIsBullet: Boolean; ATasks: TAtlasMarkdownTasks;
  var ATaskIndex: Integer): TAtlasDocRuns;
var
  mRun: TAtlasDocRun;
  mRow: TArray<string>;
  mRowIndex, mCell: Integer;
  mText: string;
begin
  Result := nil;
  case ABlock.Kind of
    TAtlasMarkdownBlockKind.Paragraph:
      Result := TAtlasTrackerMarkdown.InlineRuns(ABlock.Text) +
        [TAtlasDocRun.Create(TAtlasDocRunKind.Paragraph, '')];
    TAtlasMarkdownBlockKind.Heading:
      Result := TAtlasTrackerMarkdown.InlineRuns(ABlock.Text, True, False) +
        [TAtlasDocRun.Create(TAtlasDocRunKind.Paragraph, '')];
    TAtlasMarkdownBlockKind.Bullet:
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
                  mText := '[x] ' + mText
                else
                  mText := '[ ] ' + mText;
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
          Result := Result + [TAtlasDocRun.Create(TAtlasDocRunKind.Paragraph, '')];
      end;
    TAtlasMarkdownBlockKind.Quote:
      begin
        mRun := TAtlasDocRun.Create(TAtlasDocRunKind.Bullet, cQuoteMarker);
        mRun.Level := 1;
        Result := TAtlasDocRuns.Create(mRun) + TAtlasTrackerMarkdown.InlineRuns(ABlock.Text, False, True) +
          [TAtlasDocRun.Create(TAtlasDocRunKind.Paragraph, '')];
      end;
    TAtlasMarkdownBlockKind.Code:
      Result := [TAtlasDocRun.Create(TAtlasDocRunKind.CodeBlock, ABlock.Text, ABlock.Info)];
    TAtlasMarkdownBlockKind.Table:
      begin
        // Zweispaltig wie die Tabellen der XMLDoc: erste Zelle, dann die übrigen mit Trennern.
        for mRowIndex := 0 to High(ABlock.Rows) do
        begin
          mRow := ABlock.Rows[mRowIndex];
          if Length(mRow) = 0 then
            Continue;
          mRun := TAtlasDocRun.Create(TAtlasDocRunKind.Bullet, '');
          mRun.Level := 1;
          Result := Result + [mRun] + TAtlasTrackerMarkdown.InlineRuns(mRow[0], mRowIndex = 0, False) +
            [TAtlasDocRun.Create(TAtlasDocRunKind.Cell, '')];
          for mCell := 1 to High(mRow) do
          begin
            if mCell > 1 then
              Result := Result + [TAtlasDocRun.Create(TAtlasDocRunKind.Cell, '')];
            Result := Result + TAtlasTrackerMarkdown.InlineRuns(mRow[mCell], mRowIndex = 0, False);
          end;
        end;
        Result := Result + [TAtlasDocRun.Create(TAtlasDocRunKind.Paragraph, '')];
      end;
    TAtlasMarkdownBlockKind.Rule:
      Result := [TAtlasDocRun.Create(TAtlasDocRunKind.Paragraph, '')];
    TAtlasMarkdownBlockKind.Image:
      Result := [TAtlasDocRun.Create(TAtlasDocRunKind.Link, ABlock.Text, ABlock.Info),
        TAtlasDocRun.Create(TAtlasDocRunKind.Paragraph, '')];
  end;
  if (ABlock.Kind = TAtlasMarkdownBlockKind.Image) and (Result[0].Text = '') then
    Result[0].Text := Copy(ABlock.Info, LastDelimiter('/\', ABlock.Info) + 1, MaxInt);
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
    SetLength(mRuns, Length(mRuns) - 1);
  if Length(mRuns) = 0 then
    Exit;
  mSection := Default(TAtlasDocSection);
  mSection.Kind := TAtlasDocSectionKind.Summary;
  mSection.Runs := mRuns;
  Result.Sections := [mSection];
end;

function NextIsBullet(const ABlocks: TArray<TAtlasMarkdownBlock>; AIndex: Integer): Boolean;
begin
  Result := (AIndex < High(ABlocks)) and (ABlocks[AIndex + 1].Kind = TAtlasMarkdownBlockKind.Bullet);
end;

class function TAtlasTrackerMarkdown.ToDoc(const AText: string): TAtlasDoc;
begin
  Result := ToDoc(AText, TAtlasMarkdownTasks.Boxes);
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
    mRuns := mRuns + BlockRuns(mBlocks[mIndex], NextIsBullet(mBlocks, mIndex), ATasks, mTask);
  Result := DocOf(mRuns);
end;

class function TAtlasTrackerMarkdown.TaskTarget(AIndex: Integer): string;
begin
  Result := TaskPrefix + IntToStr(AIndex);
end;

class function TAtlasTrackerMarkdown.TaskIndexOf(const ATarget: string; out AIndex: Integer): Boolean;
begin
  AIndex := -1;
  Result := StartsStr(TaskPrefix, ATarget) and TryStrToInt(Copy(ATarget, Length(TaskPrefix) + 1, MaxInt), AIndex)
    and (AIndex >= 0);
  if not Result then
    AIndex := -1;
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
      Exit;
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
          for mCell in mRow do
            mRuns := mRuns + InlineRuns(mCell);
      TAtlasMarkdownBlockKind.Image:
        Result := Result + [TAtlasMarkdownLink.Create(mBlock.Text, mBlock.Info)];
      TAtlasMarkdownBlockKind.Code, TAtlasMarkdownBlockKind.Rule: ;
    end;
    for mRun in mRuns do
      if mRun.Kind = TAtlasDocRunKind.Link then
        Result := Result + [TAtlasMarkdownLink.Create(mRun.Text, mRun.Target)];
  end;
end;

end.
