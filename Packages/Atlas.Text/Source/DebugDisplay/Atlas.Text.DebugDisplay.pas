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
    Inc(Index);
  Result := Copy(Text, 1, Index - 1);
  if (Result <> '') and Result[1].IsDigit then
    Result := '';
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
      InString := not InString
    else if not InString and (Text[Index] = '(') and (Index > 1) and IsNameChar(Text[Index - 1]) then
      Exit(True);
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
    if Segment.Kind = TDebugDisplaySegmentKind.Placeholder then
      Result := Result + [Segment];
end;

class function TDebugDisplayTemplate.Parse(const AText: string): TDebugDisplayTemplate;
var
  Index, Start, Depth, Colon: Integer;
  Literal, Inner: string;
  Segment: TDebugDisplaySegment;
  InString: Boolean;

  procedure FlushLiteral;
  var
    Item: TDebugDisplaySegment;
  begin
    if Literal = '' then
      Exit;
    Item := Default(TDebugDisplaySegment);
    Item.Kind := TDebugDisplaySegmentKind.Text;
    Item.Text := Literal;
    Item.Offset := -1;
    Result.Segments := Result.Segments + [Item];
    Literal := '';
  end;

begin
  Result := Default(TDebugDisplayTemplate);
  Result.Source := AText;
  Result.ErrorOffset := -1;
  Literal := '';
  Index := 1;
  while Index <= Length(AText) do
  begin
    if (AText[Index] = '{') and (Index < Length(AText)) and (AText[Index + 1] = '{') then
    begin
      Literal := Literal + '{';
      Inc(Index, 2);
      Continue;
    end;
    if (AText[Index] = '}') and (Index < Length(AText)) and (AText[Index + 1] = '}') then
    begin
      Literal := Literal + '}';
      Inc(Index, 2);
      Continue;
    end;
    if AText[Index] = '}' then
    begin
      Result.Error := 'Schließende Klammer ohne öffnende';
      Result.ErrorOffset := Index - 1;
      Exit;
    end;
    if AText[Index] <> '{' then
    begin
      Literal := Literal + AText[Index];
      Inc(Index);
      Continue;
    end;
    // Platzhalter bis zur passenden schließenden Klammer; [], () und Zeichenketten zählen mit.
    Start := Index + 1;
    Depth := 0;
    Colon := 0;
    InString := False;
    Inc(Index);
    while Index <= Length(AText) do
    begin
      if AText[Index] = '''' then
        InString := not InString
      else if not InString then
        case AText[Index] of
          '(', '[':
            Inc(Depth);
          ')', ']':
            Dec(Depth);
          ':':
            if (Depth = 0) and (Colon = 0) then
              Colon := Index;
          '}':
            if Depth <= 0 then
              Break;
        end;
      Inc(Index);
    end;
    if Index > Length(AText) then
    begin
      Result.Error := 'Platzhalter ohne schließende Klammer';
      Result.ErrorOffset := Start - 2;
      Exit;
    end;
    FlushLiteral;
    Segment := Default(TDebugDisplaySegment);
    Segment.Kind := TDebugDisplaySegmentKind.Placeholder;
    if Colon > 0 then
    begin
      Inner := Copy(AText, Start, Colon - Start);
      Segment.Format := Trim(Copy(AText, Colon + 1, Index - Colon - 1));
    end
    else
      Inner := Copy(AText, Start, Index - Start);
    Segment.Text := Trim(Inner);
    Segment.Offset := Start - 1 + (Length(Inner) - Length(TrimLeft(Inner)));
    if Segment.Text = '' then
    begin
      Result.Error := 'Leerer Platzhalter';
      Result.ErrorOffset := Start - 2;
      Exit;
    end;
    Result.Segments := Result.Segments + [Segment];
    Inc(Index);
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
    Exit(False);
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
    Exit;
  Inc(Index, 2);
  while (Index <= Length(ALine)) and (ALine[Index] = ' ') do
    Inc(Index);
  if not SameText(Copy(ALine, Index, Length(AKey)), AKey) then
    Exit;
  Inc(Index, Length(AKey));
  while (Index <= Length(ALine)) and (ALine[Index] = ' ') do
    Inc(Index);
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
    Exit(False);
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
    Exit(False);
  ANames := SplitNames(Copy(ALine, Start, MaxInt));
  Result := Length(ANames) > 0;
end;

/// <summary>Erste Zeichenkette im Attribut AName der Zeile; AColumn 0-basiert auf ihrem ersten Zeichen.</summary>
function AttributeString(const ALine, AName: string; out AValue: string; out AColumn: Integer): Boolean;
var
  Index, Stop, Start: Integer;
  Lower, Name: string;
begin
  Result := False;
  AValue := '';
  AColumn := -1;
  if Pos('[', TrimLeft(ALine)) <> 1 then
    Exit;
  Lower := LowerCase(ALine);
  // Name, Name mit Endung Attribute oder mit Unit (Atlas.Debug.Attributes.AtlasDebugDisplay).
  for Name in TArray<string>.Create(AName + 'Attribute', AName) do
  begin
    Index := Pos(LowerCase(Name), Lower);
    while Index > 0 do
    begin
      Start := Index + Length(Name);
      // Ganzes Wort: davor kein Namenszeichen (Punkt erlaubt), danach Leerraum oder Klammer.
      if ((Index = 1) or not IsNameChar(ALine[Index - 1])) and
        ((Start > Length(ALine)) or not IsNameChar(ALine[Start])) then
      begin
        while (Start <= Length(ALine)) and (ALine[Start] = ' ') do
          Inc(Start);
        if (Start <= Length(ALine)) and (ALine[Start] = '(') then
        begin
          Inc(Start);
          while (Start <= Length(ALine)) and (ALine[Start] = ' ') do
            Inc(Start);
          if TDebugDisplayText.PascalString(ALine, Start, AValue, Stop) then
          begin
            AColumn := Start;
            Exit(True);
          end;
        end;
      end;
      Index := PosEx(LowerCase(Name), Lower, Index + 1);
    end;
  end;
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
      Continue;
    Seen := False;
    for Known in Result do
      if SameText(Known, Name) then
        Seen := True;
    if not Seen then
      Result := Result + [Name];
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
    Exit(False);
  // Attribute in der Zeile der Deklaration: [AtlasDebugDisplay('…')] TKunde = class
  if StartsStr('[', TrimLeft(ALines[ADeclLine])) then
    Inspect(ADeclLine, ALines[ADeclLine], True);
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
      Inc(Index);
    Inc(Index);
    Inc(Offset);
  end;
  Result := Index - 1;
end;

end.
