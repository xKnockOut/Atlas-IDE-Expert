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
    cCommentKey = 'atlas-debug:';
    cChildrenKey = 'atlas-debug-children:';
    cAttributeName = 'AtlasDebugDisplay';
    cChildrenAttributeName = 'AtlasDebugChildren';
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
  mIndex: Integer;
begin
  mIndex := 1;
  while (mIndex <= Length(Text)) and IsNameChar(Text[mIndex]) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(Text, 1, mIndex - 1);
  if (Result <> '') and Result[1].IsDigit then
  begin
    Result := '';
  end;
end;

function TDebugDisplaySegment.NeedsCall: Boolean;
var
  mIndex: Integer;
  mInString: Boolean;
begin
  mInString := False;
  for mIndex := 1 to Length(Text) do
  begin
    if Text[mIndex] = '''' then
    begin
      mInString := not mInString;
    end
    else if not mInString and (Text[mIndex] = '(') and (mIndex > 1) and IsNameChar(Text[mIndex - 1]) then
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
  mSegment: TDebugDisplaySegment;
begin
  Result := nil;
  for mSegment in Segments do
  begin
    if mSegment.Kind = TDebugDisplaySegmentKind.Placeholder then
    begin
      Result := Result + [mSegment];
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
  mIndex: Integer;
begin
  AValue := '';
  AEnd := AStart;
  if (AStart < 1) or (AStart > Length(AText)) or (AText[AStart] <> '''') then
  begin
    Exit(False);
  end;
  mIndex := AStart + 1;
  while mIndex <= Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      if (mIndex < Length(AText)) and (AText[mIndex + 1] = '''') then
      begin
        AValue := AValue + '''';
        Inc(mIndex, 2);
        Continue;
      end;
      AEnd := mIndex + 1;
      Exit(True);
    end;
    AValue := AValue + AText[mIndex];
    Inc(mIndex);
  end;
  Result := False;
end;

/// <summary>Text hinter „//“ und dem Schlüssel AKey (ohne Groß-/Kleinschreibung); AStart 1-basiert dahinter.
/// </summary>
function AfterCommentKey(const ALine, AKey: string; out AStart: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  AStart := 0;
  mIndex := Pos('//', ALine);
  if (mIndex = 0) or (Trim(Copy(ALine, 1, mIndex - 1)) <> '') then
  begin
    Exit;
  end;
  Inc(mIndex, 2);
  while (mIndex <= Length(ALine)) and (ALine[mIndex] = ' ') do
  begin
    Inc(mIndex);
  end;
  if not SameText(Copy(ALine, mIndex, Length(AKey)), AKey) then
  begin
    Exit;
  end;
  Inc(mIndex, Length(AKey));
  while (mIndex <= Length(ALine)) and (ALine[mIndex] = ' ') do
  begin
    Inc(mIndex);
  end;
  AStart := mIndex;
  Result := True;
end;

class function TDebugDisplayText.CommentTemplate(const ALine: string; out ATemplate: string;
  out AColumn: Integer): Boolean;
var
  mStart, mStop: Integer;
begin
  ATemplate := '';
  AColumn := -1;
  if not AfterCommentKey(ALine, cCommentKey, mStart) then
  begin
    Exit(False);
  end;
  if (mStart <= Length(ALine)) and (ALine[mStart] = '''') then
  begin
    Result := PascalString(ALine, mStart, ATemplate, mStop);
    AColumn := mStart;
  end
  else
  begin
    ATemplate := TrimRight(Copy(ALine, mStart, MaxInt));
    AColumn := mStart - 1;
    Result := ATemplate <> '';
  end;
end;

class function TDebugDisplayText.CommentChildren(const ALine: string; out ANames: TArray<string>): Boolean;
var
  mStart: Integer;
begin
  ANames := nil;
  if not AfterCommentKey(ALine, cChildrenKey, mStart) then
  begin
    Exit(False);
  end;
  ANames := SplitNames(Copy(ALine, mStart, MaxInt));
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
  Result := AttributeString(ALine, cAttributeName, ATemplate, AColumn);
end;

class function TDebugDisplayText.AttributeChildren(const ALine: string; out ANames: TArray<string>): Boolean;
var
  mText: string;
  mColumn: Integer;
begin
  ANames := nil;
  Result := AttributeString(ALine, cChildrenAttributeName, mText, mColumn);
  if Result then
  begin
    ANames := SplitNames(mText);
    Result := Length(ANames) > 0;
  end;
end;

class function TDebugDisplayText.SplitNames(const AText: string): TArray<string>;
var
  mPart, mName, mKnown: string;
  mSeen: Boolean;
begin
  Result := nil;
  for mPart in AText.Split([',']) do
  begin
    mName := Trim(mPart);
    if mName = '' then
    begin
      Continue;
    end;
    mSeen := False;
    for mKnown in Result do
    begin
      if SameText(mKnown, mName) then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      Result := Result + [mName];
    end;
  end;
end;

function IsCommentLine(const ALine: string): Boolean;
begin
  Result := StartsStr('//', TrimLeft(ALine));
end;

function IsAttributeLine(const ALine: string): Boolean;
var
  mTrimmed: string;
begin
  mTrimmed := Trim(ALine);
  Result := StartsStr('[', mTrimmed) and EndsStr(']', mTrimmed);
end;

class function TDebugDisplayText.RuleAbove(const ALines: TArray<string>; ADeclLine: Integer;
  out ARule: TDebugDisplaySource): Boolean;
var
  mLine: Integer;

  procedure Inspect(ALineIndex: Integer; const AText: string; AAttributesOnly: Boolean);
  var
    mTemplate: string;
    mColumn: Integer;
    mNames: TArray<string>;
  begin
    // Die nächste Zeile über der Deklaration gewinnt; Attribut vor Kommentar in derselben Zeile.
    if not ARule.HasTemplate then
    begin
      if TDebugDisplayText.AttributeTemplate(AText, mTemplate, mColumn) then
      begin
        ARule.Origin := TDebugDisplayOrigin.Attribute;
        ARule.Template := mTemplate;
        ARule.TemplateLine := ALineIndex;
        ARule.TemplateColumn := mColumn;
      end
      else if not AAttributesOnly and TDebugDisplayText.CommentTemplate(AText, mTemplate, mColumn) then
      begin
        ARule.Origin := TDebugDisplayOrigin.Comment;
        ARule.Template := mTemplate;
        ARule.TemplateLine := ALineIndex;
        ARule.TemplateColumn := mColumn;
      end;
    end;
    if ARule.Children = nil then
    begin
      if TDebugDisplayText.AttributeChildren(AText, mNames) or
        (not AAttributesOnly and TDebugDisplayText.CommentChildren(AText, mNames)) then
      begin
        ARule.Children := mNames;
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
  mLine := ADeclLine - 1;
  while (mLine >= 0) and (IsCommentLine(ALines[mLine]) or IsAttributeLine(ALines[mLine])) do
  begin
    Inspect(mLine, ALines[mLine], False);
    Dec(mLine);
  end;
  Result := ARule.HasTemplate or (ARule.Children <> nil);
end;

class function TDebugDisplayText.SourceColumn(const ALine: string; ATemplateColumn: Integer;
  const ASegment: TDebugDisplaySegment): Integer;
var
  mIndex, mOffset: Integer;
  mQuoted: Boolean;
begin
  // Vorlage zeichenweise gegen die Zeile abgleichen; in einer Pascal-Zeichenkette steht ' doppelt.
  mQuoted := (ATemplateColumn > 0) and (ATemplateColumn <= Length(ALine)) and (ALine[ATemplateColumn] = '''');
  mIndex := ATemplateColumn + 1;
  mOffset := 0;
  while (mOffset < ASegment.Offset) and (mIndex <= Length(ALine)) do
  begin
    if mQuoted and (ALine[mIndex] = '''') then
    begin
      Inc(mIndex);
    end;
    Inc(mIndex);
    Inc(mOffset);
  end;
  Result := mIndex - 1;
end;

end.
