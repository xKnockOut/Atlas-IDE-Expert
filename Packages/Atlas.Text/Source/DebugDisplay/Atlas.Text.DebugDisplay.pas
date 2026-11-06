unit Atlas.Text.DebugDisplay;

// Eigene Wertdarstellung beim Debuggen (#854), Teil für Server und Plugin:
// - Vorlage: Text mit Platzhaltern {Ausdruck} bzw. {Ausdruck:Format}, etwa
//   '{Name}, {Ort} (Nr {Nr})' oder 'Summe {Betrag:0.00}'. {{ und }} stehen für
//   geschweifte Klammern. Ein Ausdruck ist ein Feld, eine Eigenschaft oder ein
//   einfacher Ausdruck relativ zum Wert ({Positionen.Count}, {Liste[0]});
//   Klammern hinter einem Namen gelten als Aufruf (NeedsCall).
// - Regeln im Quelltext, direkt über der Typdeklaration (Kommentar- und
//   Attributzeilen ohne Leerzeile dazwischen):
//     // atlas-debug: '{Name}, {Ort}'          (auch ohne Anführungszeichen)
//     // atlas-debug-children: Name, Ort, Saldo
//     [AtlasDebugDisplay('{Name}, {Ort}')]
//     [AtlasDebugChildren('Name, Ort, Saldo')]
//   Die Attribute stammen aus der mitgelieferten Unit Atlas.Debug.Attributes.
// Spalten und Zeilen sind 0-basiert.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  TDebugDisplaySegmentKind = (Text, Placeholder);
  /// <summary>Woher eine Regel stammt: Kommentar, Attribut oder Projektdatei .atlas.</summary>
  TDebugDisplayOrigin = (Comment, Attribute, Project);
{$SCOPEDENUMS OFF}

  TDebugDisplaySegment = record
    Kind: TDebugDisplaySegmentKind;
    /// <summary>Text bzw. Ausdruck des Platzhalters (getrimmt).</summary>
    Text: string;
    /// <summary>Format hinter dem Doppelpunkt, z. B. 0.00; '' ohne.</summary>
    Format: string;
    /// <summary>Stelle des Ausdrucks in der Vorlage.</summary>
    Offset: Integer;
    /// <summary>Erster Name des Ausdrucks: Positionen bei {Positionen.Count}; '' ohne (etwa {[0]}).</summary>
    function Root: string;
    /// <summary>Enthält der Ausdruck einen Aufruf (Name gefolgt von Klammer)?</summary>
    function NeedsCall: Boolean;
  end;

  TDebugDisplayTemplate = record
    Source: string;
    Segments: TArray<TDebugDisplaySegment>;
    /// <summary>'' oder der Grund, warum die Vorlage nicht gilt (offene Klammer, leerer Platzhalter).</summary>
    Error: string;
    ErrorOffset: Integer;
    function Valid: Boolean;
    function Placeholders: TArray<TDebugDisplaySegment>;
    class function Parse(const AText: string): TDebugDisplayTemplate; static;
  end;

  /// <summary>Regel über einer Typdeklaration.</summary>
  TDebugDisplaySource = record
    Origin: TDebugDisplayOrigin;
    Template: string;
    /// <summary>Zeile und Spalte des ersten Zeichens der Vorlage im Quelltext; -1 ohne Vorlage (nur children).
    /// </summary>
    TemplateLine: Integer;
    TemplateColumn: Integer;
    Children: TArray<string>;
    ChildrenLine: Integer;
    function HasTemplate: Boolean;
  end;

  TDebugDisplayText = class
  public const
    CommentKey = 'atlas-debug:';
    ChildrenKey = 'atlas-debug-children:';
    AttributeName = 'AtlasDebugDisplay';
    ChildrenAttributeName = 'AtlasDebugChildren';
    /// <summary>Name der mitgelieferten Unit mit den Attributen.</summary>
    AttributeUnit = 'Atlas.Debug.Attributes';
  public
    /// <summary>Pascal-Zeichenkette ab AStart (1-basiert, auf dem Anführungszeichen); AEnd hinter dem
    /// schließenden. False ohne gültige Zeichenkette.</summary>
    class function PascalString(const AText: string; AStart: Integer; out AValue: string;
      out AEnd: Integer): Boolean; static;
    /// <summary>Vorlage aus „// atlas-debug: '…'“; AColumn ist die Spalte des ersten Zeichens der Vorlage.</summary>
    class function CommentTemplate(const ALine: string; out ATemplate: string; out AColumn: Integer): Boolean;
      static;
    /// <summary>Namen aus „// atlas-debug-children: A, B“.</summary>
    class function CommentChildren(const ALine: string; out ANames: TArray<string>): Boolean; static;
    /// <summary>Vorlage aus [AtlasDebugDisplay('…')] (auch mit Unit oder Endung Attribute).</summary>
    class function AttributeTemplate(const ALine: string; out ATemplate: string; out AColumn: Integer): Boolean;
      static;
    /// <summary>Namen aus [AtlasDebugChildren('A, B')].</summary>
    class function AttributeChildren(const ALine: string; out ANames: TArray<string>): Boolean; static;
    /// <summary>Kommagetrennte Namen, getrimmt, ohne leere und doppelte.</summary>
    class function SplitNames(const AText: string): TArray<string>; static;
    /// <summary>Regel in den Zeilen direkt über der Deklaration in Zeile ADeclLine: zusammenhängende Kommentar-
    /// und Attributzeilen. Steht in derselben Zeile vor dem Namen ein Attribut, zählt es mit.</summary>
    class function RuleAbove(const ALines: TArray<string>; ADeclLine: Integer;
      out ARule: TDebugDisplaySource): Boolean; static;
    /// <summary>Spalte des Platzhalters ASegment im Quelltext, wenn die Vorlage in ALine ab ATemplateColumn
    /// steht ('' in Anführungszeichen zählen doppelt).</summary>
    class function SourceColumn(const ALine: string; ATemplateColumn: Integer;
      const ASegment: TDebugDisplaySegment): Integer; static;
  end;

implementation

uses
  System.StrUtils,
  System.Character;

function IsNameChar(AChar: Char): Boolean;
begin
  Result := (AChar = '_') or AChar.IsLetterOrDigit;
end;

{ TDebugDisplaySegment }

function TDebugDisplaySegment.Root: string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(Text)) and IsNameChar(Text[Index]) do
  begin
    Inc(Index);
  end;
  Result := Copy(Text, 1, Index - 1);
  if (Result <> '') and Result[1].IsDigit then
  begin
    Result := '';
  end;
end;

function TDebugDisplaySegment.NeedsCall: Boolean;
var
  Index: Integer;
  InString: Boolean;
begin
  InString := False;
  for Index := 1 to Length(Text) do
  begin
    if Text[Index] = '''' then
    begin
      InString := not InString;
    end
    else if not InString and (Text[Index] = '(') and (Index > 1) and IsNameChar(Text[Index - 1]) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TDebugDisplayTemplate }

function TDebugDisplayTemplate.Valid: Boolean;
begin
  Result := Error = '';
end;

function TDebugDisplayTemplate.Placeholders: TArray<TDebugDisplaySegment>;
var
  Segment: TDebugDisplaySegment;
begin
  Result := nil;
  for Segment in Segments do
  begin
    if Segment.Kind = TDebugDisplaySegmentKind.Placeholder then
    begin
      Result := Result + [Segment];
    end;
  end;
end;

// Verdoppelte Klammer ("{{" bzw. "}}") bei AIndex?
function IsDoubled(const AText: string; AIndex: Integer; AChar: Char): Boolean;
begin
  Result := (AText[AIndex] = AChar) and (AIndex < Length(AText)) and (AText[AIndex + 1] = AChar);
end;

// Zählt das Zeichen AText[APos] außerhalb von Zeichenketten: Klammertiefe und ersten Doppelpunkt; True bei der
// schließenden "}" des Platzhalters.
function IsPlaceholderClose(const AText: string; APos: Integer; var ADepth, AColon: Integer): Boolean;
begin
  Result := False;
  case AText[APos] of
    '(', '[':
      Inc(ADepth);
    ')', ']':
      Dec(ADepth);
    ':':
      if (ADepth = 0) and (AColon = 0) then
      begin
        AColon := APos;
      end;
    '}':
      Result := ADepth <= 0;
  end;
end;

// Ende des Platzhalters ab AStart (hinter "{"): Stelle der passenden "}", sonst Length(AText) + 1. [], () und
// Zeichenketten zählen mit; AColon ist der erste Doppelpunkt außerhalb von Klammern, 0 ohne.
function PlaceholderEnd(const AText: string; AStart: Integer; out AColon: Integer): Integer;
var
  mDepth: Integer;
  mInString: Boolean;
begin
  mDepth := 0;
  AColon := 0;
  mInString := False;
  Result := AStart;
  while Result <= Length(AText) do
  begin
    if AText[Result] = '''' then
    begin
      mInString := not mInString;
    end
    else if not mInString and IsPlaceholderClose(AText, Result, mDepth, AColon) then
    begin
      Exit;
    end;
    Inc(Result);
  end;
end;

// Platzhalter AText[AStart..AStop - 1] mit Format hinter AColon (0 ohne).
function PlaceholderSegment(const AText: string; AStart, AColon, AStop: Integer): TDebugDisplaySegment;
var
  mInner: string;
begin
  Result := Default(TDebugDisplaySegment);
  Result.Kind := TDebugDisplaySegmentKind.Placeholder;
  if AColon > 0 then
  begin
    mInner := Copy(AText, AStart, AColon - AStart);
    Result.Format := Trim(Copy(AText, AColon + 1, AStop - AColon - 1));
  end
  else
  begin
    mInner := Copy(AText, AStart, AStop - AStart);
  end;
  Result.Text := Trim(mInner);
  Result.Offset := AStart - 1 + (Length(mInner) - Length(TrimLeft(mInner)));
end;

class function TDebugDisplayTemplate.Parse(const AText: string): TDebugDisplayTemplate;
var
  mIndex: Integer;
  mLiteral: string;
  mOk: Boolean;

  procedure FlushLiteral;
  var
    mItem: TDebugDisplaySegment;
  begin
    if mLiteral = '' then
    begin
      Exit;
    end;
    mItem := Default(TDebugDisplaySegment);
    mItem.Kind := TDebugDisplaySegmentKind.Text;
    mItem.Text := mLiteral;
    mItem.Offset := -1;
    Result.Segments := Result.Segments + [mItem];
    mLiteral := '';
  end;

  procedure Fail(const AMessage: string; AOffset: Integer);
  begin
    Result.Error := AMessage;
    Result.ErrorOffset := AOffset;
  end;

  // Platzhalter ab "{" bei mIndex; AOk = False mit Fehler.
  procedure ReadPlaceholder(out AOk: Boolean);
  var
    mStart, mStop, mColon: Integer;
    mSegment: TDebugDisplaySegment;
  begin
    AOk := False;
    mStart := mIndex + 1;
    mStop := PlaceholderEnd(AText, mStart, mColon);
    if mStop > Length(AText) then
    begin
      Fail('Platzhalter ohne schließende Klammer', mStart - 2);
      Exit;
    end;
    FlushLiteral;
    mSegment := PlaceholderSegment(AText, mStart, mColon, mStop);
    if mSegment.Text = '' then
    begin
      Fail('Leerer Platzhalter', mStart - 2);
      Exit;
    end;
    Result.Segments := Result.Segments + [mSegment];
    mIndex := mStop + 1;
    AOk := True;
  end;

begin
  Result := Default(TDebugDisplayTemplate);
  Result.Source := AText;
  Result.ErrorOffset := -1;
  mLiteral := '';
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if IsDoubled(AText, mIndex, '{') or IsDoubled(AText, mIndex, '}') then
    begin
      mLiteral := mLiteral + AText[mIndex];
      Inc(mIndex, 2);
    end
    else if AText[mIndex] = '}' then
    begin
      Fail('Schließende Klammer ohne öffnende', mIndex - 1);
      Exit;
    end
    else if AText[mIndex] <> '{' then
    begin
      mLiteral := mLiteral + AText[mIndex];
      Inc(mIndex);
    end
    else
    begin
      ReadPlaceholder(mOk);
      if not mOk then
      begin
        Exit;
      end;
    end;
  end;
  FlushLiteral;
end;

{ TDebugDisplaySource }

function TDebugDisplaySource.HasTemplate: Boolean;
begin
  Result := TemplateLine >= 0;
end;

{ TDebugDisplayText }

class function TDebugDisplayText.PascalString(const AText: string; AStart: Integer; out AValue: string;
  out AEnd: Integer): Boolean;
var
  Index: Integer;
begin
  AValue := '';
  AEnd := AStart;
  if (AStart < 1) or (AStart > Length(AText)) or (AText[AStart] <> '''') then
  begin
    Exit(False);
  end;
  Index := AStart + 1;
  while Index <= Length(AText) do
  begin
    if AText[Index] = '''' then
    begin
      if (Index < Length(AText)) and (AText[Index + 1] = '''') then
      begin
        AValue := AValue + '''';
        Inc(Index, 2);
        Continue;
      end;
      AEnd := Index + 1;
      Exit(True);
    end;
    AValue := AValue + AText[Index];
    Inc(Index);
  end;
  Result := False;
end;

/// <summary>Text hinter „//“ und dem Schlüssel AKey (ohne Groß-/Kleinschreibung); AStart 1-basiert dahinter.
/// </summary>
function AfterCommentKey(const ALine, AKey: string; out AStart: Integer): Boolean;
var
  Index: Integer;
begin
  Result := False;
  AStart := 0;
  Index := Pos('//', ALine);
  if (Index = 0) or (Trim(Copy(ALine, 1, Index - 1)) <> '') then
  begin
    Exit;
  end;
  Inc(Index, 2);
  while (Index <= Length(ALine)) and (ALine[Index] = ' ') do
  begin
    Inc(Index);
  end;
  if not SameText(Copy(ALine, Index, Length(AKey)), AKey) then
  begin
    Exit;
  end;
  Inc(Index, Length(AKey));
  while (Index <= Length(ALine)) and (ALine[Index] = ' ') do
  begin
    Inc(Index);
  end;
  AStart := Index;
  Result := True;
end;

class function TDebugDisplayText.CommentTemplate(const ALine: string; out ATemplate: string;
  out AColumn: Integer): Boolean;
var
  Start, Stop: Integer;
begin
  ATemplate := '';
  AColumn := -1;
  if not AfterCommentKey(ALine, CommentKey, Start) then
  begin
    Exit(False);
  end;
  if (Start <= Length(ALine)) and (ALine[Start] = '''') then
  begin
    Result := PascalString(ALine, Start, ATemplate, Stop);
    AColumn := Start;
  end
  else
  begin
    ATemplate := TrimRight(Copy(ALine, Start, MaxInt));
    AColumn := Start - 1;
    Result := ATemplate <> '';
  end;
end;

class function TDebugDisplayText.CommentChildren(const ALine: string; out ANames: TArray<string>): Boolean;
var
  Start: Integer;
begin
  ANames := nil;
  if not AfterCommentKey(ALine, ChildrenKey, Start) then
  begin
    Exit(False);
  end;
  ANames := SplitNames(Copy(ALine, Start, MaxInt));
  Result := Length(ANames) > 0;
end;

/// <summary>Erste Zeichenkette im Attribut AName der Zeile; AColumn 0-basiert auf ihrem ersten Zeichen.</summary>
// Erste Stelle ab AStart, die kein Leerzeichen ist.
function SkipBlanks(const ALine: string; AStart: Integer): Integer;
begin
  Result := AStart;
  while (Result <= Length(ALine)) and (ALine[Result] = ' ') do
  begin
    Inc(Result);
  end;
end;

// Ganzes Wort ALine[AIndex..AStop - 1]: davor kein Namenszeichen (Punkt erlaubt), danach keins.
function IsWholeName(const ALine: string; AIndex, AStop: Integer): Boolean;
begin
  Result := ((AIndex = 1) or not IsNameChar(ALine[AIndex - 1])) and
    ((AStop > Length(ALine)) or not IsNameChar(ALine[AStop]));
end;

// Zeichenkette als erstes Argument hinter dem Namen, der bei AStart endet: Name ('…').
function ArgumentString(const ALine: string; AStart: Integer; out AValue: string; out AColumn: Integer): Boolean;
var
  mStart, mStop: Integer;
begin
  Result := False;
  mStart := SkipBlanks(ALine, AStart);
  if (mStart > Length(ALine)) or (ALine[mStart] <> '(') then
  begin
    Exit;
  end;
  mStart := SkipBlanks(ALine, mStart + 1);
  if TDebugDisplayText.PascalString(ALine, mStart, AValue, mStop) then
  begin
    AColumn := mStart;
    Result := True;
  end;
end;

function AttributeString(const ALine, AName: string; out AValue: string; out AColumn: Integer): Boolean;
var
  mIndex: Integer;
  mLower, mName: string;
begin
  AValue := '';
  AColumn := -1;
  if Pos('[', TrimLeft(ALine)) <> 1 then
  begin
    Exit(False);
  end;
  mLower := LowerCase(ALine);
  // Name, Name mit Endung Attribute oder mit Unit (Atlas.Debug.Attributes.AtlasDebugDisplay).
  for mName in TArray<string>.Create(AName + 'Attribute', AName) do
  begin
    mIndex := Pos(LowerCase(mName), mLower);
    while mIndex > 0 do
    begin
      if IsWholeName(ALine, mIndex, mIndex + Length(mName)) and
        ArgumentString(ALine, mIndex + Length(mName), AValue, AColumn) then
      begin
        Exit(True);
      end;
      mIndex := PosEx(LowerCase(mName), mLower, mIndex + 1);
    end;
  end;
  Result := False;
end;

class function TDebugDisplayText.AttributeTemplate(const ALine: string; out ATemplate: string;
  out AColumn: Integer): Boolean;
begin
  Result := AttributeString(ALine, AttributeName, ATemplate, AColumn);
end;

class function TDebugDisplayText.AttributeChildren(const ALine: string; out ANames: TArray<string>): Boolean;
var
  Text: string;
  Column: Integer;
begin
  ANames := nil;
  Result := AttributeString(ALine, ChildrenAttributeName, Text, Column);
  if Result then
  begin
    ANames := SplitNames(Text);
    Result := Length(ANames) > 0;
  end;
end;

class function TDebugDisplayText.SplitNames(const AText: string): TArray<string>;
var
  Part, Name, Known: string;
  Seen: Boolean;
begin
  Result := nil;
  for Part in AText.Split([',']) do
  begin
    Name := Trim(Part);
    if Name = '' then
    begin
      Continue;
    end;
    Seen := False;
    for Known in Result do
    begin
      if SameText(Known, Name) then
      begin
        Seen := True;
      end;
    end;
    if not Seen then
    begin
      Result := Result + [Name];
    end;
  end;
end;

function IsCommentLine(const ALine: string): Boolean;
begin
  Result := StartsStr('//', TrimLeft(ALine));
end;

function IsAttributeLine(const ALine: string): Boolean;
var
  Trimmed: string;
begin
  Trimmed := Trim(ALine);
  Result := StartsStr('[', Trimmed) and EndsStr(']', Trimmed);
end;

class function TDebugDisplayText.RuleAbove(const ALines: TArray<string>; ADeclLine: Integer;
  out ARule: TDebugDisplaySource): Boolean;
var
  Line: Integer;

  procedure Inspect(ALineIndex: Integer; const AText: string; AAttributesOnly: Boolean);
  var
    Template: string;
    Column: Integer;
    Names: TArray<string>;
  begin
    // Die nächste Zeile über der Deklaration gewinnt; Attribut vor Kommentar in derselben Zeile.
    if not ARule.HasTemplate then
    begin
      if TDebugDisplayText.AttributeTemplate(AText, Template, Column) then
      begin
        ARule.Origin := TDebugDisplayOrigin.Attribute;
        ARule.Template := Template;
        ARule.TemplateLine := ALineIndex;
        ARule.TemplateColumn := Column;
      end
      else if not AAttributesOnly and TDebugDisplayText.CommentTemplate(AText, Template, Column) then
      begin
        ARule.Origin := TDebugDisplayOrigin.Comment;
        ARule.Template := Template;
        ARule.TemplateLine := ALineIndex;
        ARule.TemplateColumn := Column;
      end;
    end;
    if ARule.Children = nil then
    begin
      if TDebugDisplayText.AttributeChildren(AText, Names) or
        (not AAttributesOnly and TDebugDisplayText.CommentChildren(AText, Names)) then
      begin
        ARule.Children := Names;
        ARule.ChildrenLine := ALineIndex;
      end;
    end;
  end;

begin
  ARule := Default(TDebugDisplaySource);
  ARule.TemplateLine := -1;
  ARule.TemplateColumn := -1;
  ARule.ChildrenLine := -1;
  if (ADeclLine < 0) or (ADeclLine > High(ALines)) then
  begin
    Exit(False);
  end;
  // Attribute in der Zeile der Deklaration: [AtlasDebugDisplay('…')] TKunde = class
  if StartsStr('[', TrimLeft(ALines[ADeclLine])) then
  begin
    Inspect(ADeclLine, ALines[ADeclLine], True);
  end;
  Line := ADeclLine - 1;
  while (Line >= 0) and (IsCommentLine(ALines[Line]) or IsAttributeLine(ALines[Line])) do
  begin
    Inspect(Line, ALines[Line], False);
    Dec(Line);
  end;
  Result := ARule.HasTemplate or (ARule.Children <> nil);
end;

class function TDebugDisplayText.SourceColumn(const ALine: string; ATemplateColumn: Integer;
  const ASegment: TDebugDisplaySegment): Integer;
var
  Index, Offset: Integer;
  Quoted: Boolean;
begin
  // Vorlage zeichenweise gegen die Zeile abgleichen; in einer Pascal-Zeichenkette steht ' doppelt.
  Quoted := (ATemplateColumn > 0) and (ATemplateColumn <= Length(ALine)) and (ALine[ATemplateColumn] = '''');
  Index := ATemplateColumn + 1;
  Offset := 0;
  while (Offset < ASegment.Offset) and (Index <= Length(ALine)) do
  begin
    if Quoted and (ALine[Index] = '''') then
    begin
      Inc(Index);
    end;
    Inc(Index);
    Inc(Offset);
  end;
  Result := Index - 1;
end;

end.
