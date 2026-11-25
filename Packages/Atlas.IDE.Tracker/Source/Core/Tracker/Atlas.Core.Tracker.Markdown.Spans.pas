unit Atlas.Core.Tracker.Markdown.Spans;

// Fließtext eines Markdown-Absatzes für das Fenster „Atlas-Issue“ (#1264), ohne VCL und Open Tools API: setzt
// ihn in Doku-Läufe (TAtlasDoc, wie die XMLDoc in Hover und Detailpanel): **fett**, *kursiv*, ~~durchgestrichen~~,
// `Code`, [Links](url), <https://…>, nackte https-Adressen, Bilder im Fließtext als Link, HTML-Tags entfallen
// (<br> wird Umbruch, <a> und <img> werden Links), Entitäten werden ersetzt. Die Blöcke (Absätze, Listen,
// Tabellen …) zerlegt Atlas.Core.Tracker.Markdown und gibt jeden Absatz hierher.

interface

uses
  Atlas.Plugin.Documentation.Contract;

type
  TAtlasMarkdownInline = record
  public
    /// <summary>Läufe eines Absatzes; ABold: alles fett (Überschrift, Kopfzeile), AItalic: alles kursiv (Zitat).
    /// </summary>
    class function Runs(const AText: string; ABold, AItalic: Boolean): TAtlasDocRuns; static;
    /// <summary>HTML-Entitäten ersetzen: wie TTextEntities.Decode, dazu &amp;nbsp; als Leerzeichen.</summary>
    class function DecodeHtml(const AText: string): string; static;
    /// <summary>Wert des Attributs AName in einem HTML-Tag (src="…" bzw. alt='…'); '' ohne.</summary>
    class function HtmlAttribute(const ATag, AName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Chars,
  Atlas.Text.Entities;

/// <summary>Wert des Attributs AName in einem HTML-Tag (src="…" bzw. alt='…'); '' ohne.</summary>
function AttributeOf(const ATag, AName: string): string;
var
  mPos, mStop: Integer;
  mQuote: Char;
begin
  Result := '';
  mPos := Pos(LowerCase(AName) + '=', LowerCase(ATag));
  if mPos = 0 then
  begin
    Exit;
  end;
  mPos := mPos + Length(AName) + 1;
  if mPos > Length(ATag) then
  begin
    Exit;
  end;
  mQuote := ATag[mPos];
  if (mQuote = '"') or (mQuote = '''') then
  begin
    mStop := PosEx(mQuote, ATag, mPos + 1);
    if mStop > 0 then
    begin
      Result := Copy(ATag, mPos + 1, mStop - mPos - 1);
    end;
  end
  else
  begin
    mStop := mPos;
    while (mStop <= Length(ATag)) and not CharInSet(ATag[mStop], [' ', '>', '/']) do
    begin
      Inc(mStop);
    end;
    Result := Copy(ATag, mPos, mStop - mPos);
  end;
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

{ TInlineBuilder }

procedure TInlineBuilder.Flush;
var
  mRun: TAtlasDocRun;
begin
  if Text = '' then
  begin
    Exit;
  end;
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
  begin
    mText := AUrl;
  end;
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
    begin
      Inc(mDepth);
    end
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
    begin
      Exit;
    end;
  end;
  if (mClose = 0) or (mClose >= Length(AText)) or (AText[mClose + 1] <> '(') then
  begin
    Exit;
  end;
  mProbe := PosEx(')', AText, mClose + 2);
  if mProbe = 0 then
  begin
    Exit;
  end;
  ALabel := Copy(AText, AIndex + 1, mClose - AIndex - 1);
  AUrl := Trim(Copy(AText, mClose + 2, mProbe - mClose - 2));
  if Pos(' ', AUrl) > 0 then
  begin
    AUrl := Copy(AUrl, 1, Pos(' ', AUrl) - 1);
  end;
  AUrl := AUrl.Trim(['<', '>']);
  Result := mProbe;
  // YouTrack: Attribute nach dem Bild ({width=70%}).
  if (Result < Length(AText)) and (AText[Result + 1] = '{') and (PosEx('}', AText, Result + 1) > 0) then
  begin
    Result := PosEx('}', AText, Result + 1);
  end;
end;

/// <summary>Nackte Adresse ab AIndex ("https://…"); Satzzeichen am Ende gehören nicht dazu.</summary>
function BareUrlEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and not CharInSet(AText[Result], [' ', #9, #10, '<', '>', '"']) do
  begin
    Inc(Result);
  end;
  Dec(Result);
  while (Result > AIndex) and CharInSet(AText[Result], ['.', ',', ';', ':', '!', '?', ')', '''']) do
  begin
    Dec(Result);
  end;
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
    begin
      Exit(True);
    end;
    mProbe := PosEx(ADelimiter, AText, mProbe + Length(ADelimiter));
  end;
  Result := False;
end;

type
  /// <summary>Liest einen Absatz Zeichen für Zeichen; jedes Try… verarbeitet ein Stück an Index und liefert True,
  /// wenn es das Stück erkannt hat.</summary>
  TInlineParser = record
    Builder: TInlineBuilder;
    Source: string;
    Index: Integer;
    function CharAt(AIndex: Integer): Char;
    function Current: Char;
    function Next: Char;
    function Prev: Char;
    function TryEscape: Boolean;
    function TryBreak: Boolean;
    function TryCode: Boolean;
    function TryImage: Boolean;
    function TryLink: Boolean;
    procedure AddAnchor(AStop: Integer; const ATag: string);
    function TryHtmlTag(AStop: Integer; const ATag: string): Boolean;
    function TryTag: Boolean;
    function TryBareUrl: Boolean;
    function TryStrike: Boolean;
    function IsIntraword(const ADelimiter: string): Boolean;
    function ToggleBold(const ADelimiter: string): Boolean;
    function ToggleItalic(const ADelimiter: string): Boolean;
    function TryEmphasis: Boolean;
    function TryEntity: Boolean;
    function TryMarkup: Boolean;
    function TryOther: Boolean;
    procedure Step;
  end;

{ TInlineParser }

function TInlineParser.CharAt(AIndex: Integer): Char;
begin
  Result := #0;
  if (AIndex >= 1) and (AIndex <= Length(Source)) then
  begin
    Result := Source[AIndex];
  end;
end;

function TInlineParser.Current: Char;
begin
  Result := Source[Index];
end;

function TInlineParser.Next: Char;
begin
  Result := CharAt(Index + 1);
end;

function TInlineParser.Prev: Char;
begin
  Result := ' ';
  if Index > 1 then
  begin
    Result := Source[Index - 1];
  end;
end;

/// <summary>Maskiert: \* \_ \` \[ …</summary>
function TInlineParser.TryEscape: Boolean;
begin
  Result := (Current = '\') and (Next <> #0) and CharInSet(Next, ['\', '`', '*', '_', '{', '}', '[', ']', '(', ')',
    '#', '+', '-', '.', '!', '|', '<', '>', '~']);
  if Result then
  begin
    Builder.Text := Builder.Text + Next;
    Inc(Index, 2);
  end;
end;

/// <summary>Umbruch; Zeile mit "\" bzw. zwei Leerzeichen am Ende ist derselbe Umbruch.</summary>
function TInlineParser.TryBreak: Boolean;
begin
  Result := Current = #10;
  if not Result then
  begin
    Exit;
  end;
  Builder.Text := TrimRight(Builder.Text);
  if EndsStr('\', Builder.Text) then
  begin
    Delete(Builder.Text, Length(Builder.Text), 1);
  end;
  Builder.AddBreak;
  Inc(Index);
end;

/// <summary>Code im Fließtext: gleich viele Backticks schließen.</summary>
function TInlineParser.TryCode: Boolean;
var
  mTicks, mClose: Integer;
begin
  Result := Current = '`';
  if not Result then
  begin
    Exit;
  end;
  mTicks := 0;
  while (Index + mTicks <= Length(Source)) and (Source[Index + mTicks] = '`') do
  begin
    Inc(mTicks);
  end;
  mClose := PosEx(StringOfChar('`', mTicks), Source, Index + mTicks);
  if mClose > 0 then
  begin
    Builder.AddCode(Trim(StringReplace(Copy(Source, Index + mTicks, mClose - Index - mTicks), #10, ' ',
      [rfReplaceAll])));
    Index := mClose + mTicks;
  end
  else
  begin
    Builder.Text := Builder.Text + StringOfChar('`', mTicks);
    Inc(Index, mTicks);
  end;
end;

/// <summary>Bild im Fließtext: als Link mit dem Alternativtext.</summary>
function TInlineParser.TryImage: Boolean;
var
  mStop: Integer;
  mLabel, mUrl: string;
begin
  Result := False;
  if (Current <> '!') or (Next <> '[') then
  begin
    Exit;
  end;
  mStop := LinkEnd(Source, Index + 1, mLabel, mUrl);
  if mStop = 0 then
  begin
    Exit;
  end;
  if mLabel = '' then
  begin
    mLabel := Copy(mUrl, LastDelimiter('/\', mUrl) + 1, MaxInt);
  end;
  Builder.AddLink(mLabel, mUrl);
  Index := mStop + 1;
  Result := True;
end;

function TInlineParser.TryLink: Boolean;
var
  mStop: Integer;
  mLabel, mUrl: string;
begin
  Result := False;
  if Current <> '[' then
  begin
    Exit;
  end;
  mStop := LinkEnd(Source, Index, mLabel, mUrl);
  if mStop = 0 then
  begin
    Exit;
  end;
  // Hervorhebungen im Linktext entfallen.
  mLabel := StringReplace(StringReplace(mLabel, '**', '', [rfReplaceAll]), '`', '', [rfReplaceAll]);
  Builder.AddLink(TAtlasMarkdownInline.DecodeHtml(mLabel), mUrl);
  Index := mStop + 1;
  Result := True;
end;

/// <summary>&lt;a href="…"&gt;Text&lt;/a&gt;: Text als Link; ohne &lt;/a&gt; entfällt nur das Tag.</summary>
procedure TInlineParser.AddAnchor(AStop: Integer; const ATag: string);
const
  cAnchorClose = '</a>';
var
  mClose: Integer;
begin
  mClose := PosEx(cAnchorClose, LowerCase(Source), AStop + 1);
  if mClose > 0 then
  begin
    Builder.AddLink(TAtlasMarkdownInline.DecodeHtml(Copy(Source, AStop + 1, mClose - AStop - 1)),
      TAtlasMarkdownInline.DecodeHtml(AttributeOf(ATag, 'href')));
    Index := mClose + Length(cAnchorClose);
  end;
end;

/// <summary>HTML-Tag ATag, das bei AStop endet: entfällt; &lt;br&gt; wird Umbruch, &lt;img&gt; und &lt;a&gt; Link.
/// </summary>
function TInlineParser.TryHtmlTag(AStop: Integer; const ATag: string): Boolean;
begin
  Result := (ATag <> '') and CharInSet(ATag[1], ['a'..'z', 'A'..'Z', '/', '!']) and (Pos(#10, ATag) = 0);
  if not Result then
  begin
    Exit;
  end;
  Index := AStop + 1;
  if SameText(ATag.TrimRight(['/', ' ']), 'br') then
  begin
    Builder.AddBreak;
  end
  else if StartsText('img', ATag) and (AttributeOf(ATag, 'src') <> '') then
  begin
    Builder.AddLink(TAtlasMarkdownInline.DecodeHtml(AttributeOf(ATag, 'alt')),
      TAtlasMarkdownInline.DecodeHtml(AttributeOf(ATag, 'src')));
  end
  else if StartsText('a ', ATag) and (AttributeOf(ATag, 'href') <> '') then
  begin
    AddAnchor(AStop, ATag);
  end;
end;

/// <summary>&lt;https://…&gt; bzw. HTML-Tag.</summary>
function TInlineParser.TryTag: Boolean;
var
  mStop: Integer;
  mTag: string;
begin
  Result := False;
  if Current <> '<' then
  begin
    Exit;
  end;
  mStop := PosEx('>', Source, Index + 1);
  if mStop = 0 then
  begin
    Exit;
  end;
  mTag := Copy(Source, Index + 1, mStop - Index - 1);
  if StartsText('http://', mTag) or StartsText('https://', mTag) then
  begin
    Builder.AddLink(mTag, mTag);
    Index := mStop + 1;
    Exit(True);
  end;
  Result := TryHtmlTag(mStop, mTag);
end;

/// <summary>Nackte Adresse (GitHub verlinkt sie).</summary>
function TInlineParser.TryBareUrl: Boolean;
const
  cHttps = 'https://';
  cHttp = 'http://';
var
  mStop: Integer;
  mUrl: string;
begin
  Result := CharInSet(Current, ['h', 'H']) and not TTextChars.IsIdentChar(Prev) and
    (StartsText(cHttps, Copy(Source, Index, Length(cHttps))) or StartsText(cHttp, Copy(Source, Index, Length(cHttp))));
  if not Result then
  begin
    Exit;
  end;
  mStop := BareUrlEnd(Source, Index);
  mUrl := Copy(Source, Index, mStop - Index + 1);
  Builder.AddLink(mUrl, mUrl);
  Index := mStop + 1;
end;

/// <summary>Durchgestrichen: Zeichen entfallen.</summary>
function TInlineParser.TryStrike: Boolean;
begin
  Result := (Current = '~') and (Next = '~');
  if Result then
  begin
    Inc(Index, 2);
  end;
end;

/// <summary>"_" mitten in einem Wort (snake_case) hebt nichts hervor.</summary>
function TInlineParser.IsIntraword(const ADelimiter: string): Boolean;
begin
  Result := (Current = '_') and TTextChars.IsIdentChar(Prev) and (Index + Length(ADelimiter) <= Length(Source)) and
    TTextChars.IsIdentChar(Source[Index + Length(ADelimiter)]);
end;

function TInlineParser.ToggleBold(const ADelimiter: string): Boolean;
begin
  if Builder.Bold and not CharInSet(Prev, [' ', #9]) then
  begin
    Builder.Flush;
    Builder.Bold := False;
    Inc(Index, Length(ADelimiter));
    Exit(True);
  end;
  Result := not Builder.Bold and (Index + Length(ADelimiter) <= Length(Source))
    and not CharInSet(Source[Index + Length(ADelimiter)], [' ', #9, #10])
    and HasCloser(Source, ADelimiter, Index + Length(ADelimiter) + 1);
  if Result then
  begin
    Builder.Flush;
    Builder.Bold := True;
    Inc(Index, Length(ADelimiter));
  end;
end;

function TInlineParser.ToggleItalic(const ADelimiter: string): Boolean;
begin
  if Builder.Italic and not CharInSet(Prev, [' ', #9]) then
  begin
    Builder.Flush;
    Builder.Italic := False;
    Inc(Index);
    Exit(True);
  end;
  Result := not Builder.Italic and (Next <> #0) and not CharInSet(Next, [' ', #9, #10]) and
    HasCloser(Source, ADelimiter, Index + 2);
  if Result then
  begin
    Builder.Flush;
    Builder.Italic := True;
    Inc(Index);
  end;
end;

/// <summary>Fett und kursiv: ** bzw. __, * bzw. _; "_" nur an Wortgrenzen (snake_case bleibt).</summary>
function TInlineParser.TryEmphasis: Boolean;
var
  mDelimiter: string;
  mToggled: Boolean;
begin
  Result := CharInSet(Current, ['*', '_']);
  if not Result then
  begin
    Exit;
  end;
  mDelimiter := Current;
  if Next = Current then
  begin
    mDelimiter := mDelimiter + Current;
  end;
  mToggled := False;
  if not IsIntraword(mDelimiter) then
  begin
    if Length(mDelimiter) = 2 then
    begin
      mToggled := ToggleBold(mDelimiter);
    end
    else
    begin
      mToggled := ToggleItalic(mDelimiter);
    end;
  end;
  if not mToggled then
  begin
    Builder.Text := Builder.Text + mDelimiter;
    Inc(Index, Length(mDelimiter));
  end;
end;

function TInlineParser.TryEntity: Boolean;
const
  /// <summary>Längste Entität, die ersetzt wird (&amp;#x1F600; hat neun Zeichen samt Semikolon).</summary>
  cMaxEntityLength = 8;
var
  mStop: Integer;
begin
  Result := False;
  if Current <> '&' then
  begin
    Exit;
  end;
  mStop := PosEx(';', Source, Index + 1);
  Result := (mStop > 0) and (mStop - Index <= cMaxEntityLength);
  if Result then
  begin
    Builder.Text := Builder.Text + TAtlasMarkdownInline.DecodeHtml(Copy(Source, Index, mStop - Index + 1));
    Index := mStop + 1;
  end;
end;

function TInlineParser.TryMarkup: Boolean;
begin
  Result := TryEscape or TryBreak or TryCode or TryImage or TryLink;
end;

function TInlineParser.TryOther: Boolean;
begin
  Result := TryTag or TryBareUrl or TryStrike or TryEmphasis or TryEntity;
end;

procedure TInlineParser.Step;
begin
  if not (TryMarkup or TryOther) then
  begin
    Builder.Text := Builder.Text + Current;
    Inc(Index);
  end;
end;

class function TAtlasMarkdownInline.Runs(const AText: string; ABold, AItalic: Boolean): TAtlasDocRuns;
var
  mParser: TInlineParser;
begin
  mParser := Default(TInlineParser);
  mParser.Builder.Runs := nil;
  mParser.Builder.BaseBold := ABold;
  mParser.Builder.BaseItalic := AItalic;
  mParser.Source := AText;
  mParser.Index := 1;
  while mParser.Index <= Length(mParser.Source) do
  begin
    mParser.Step;
  end;
  mParser.Builder.Flush;
  Result := mParser.Builder.Runs;
end;

class function TAtlasMarkdownInline.DecodeHtml(const AText: string): string;
begin
  // &nbsp; kennt nur HTML; alles Übrige wie in XML über Atlas.Text.
  Result := TTextEntities.Decode(StringReplace(AText, '&nbsp;', ' ', [rfReplaceAll]));
end;

class function TAtlasMarkdownInline.HtmlAttribute(const ATag, AName: string): string;
begin
  Result := AttributeOf(ATag, AName);
end;

end.
