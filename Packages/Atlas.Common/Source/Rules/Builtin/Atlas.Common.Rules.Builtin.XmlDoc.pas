unit Atlas.Common.Rules.Builtin.XmlDoc;

// xmldoc-mismatch (#979, Gruppe Stil und Metriken): ///-Kommentare, die nicht
// zur Signatur passen oder kein wohlgeformtes XML sind, wie die Compiler-
// warnungen W1201 bis W1208 mit eingeschalteter XML-Dokumentation.
//
// Wohlgeformt (W1201 bis W1205): "<" oder "&" ohne gültiges Tag bzw. Entität,
// unbekannte Entität, Attributwert ohne Anführungszeichen, nicht geschlossene
// und überzählige Endtags. Korrektur: Zeichen maskieren, Anführungszeichen
// setzen, Endtag ergänzen oder entfernen; ein Tag ohne Attribute und Inhalt
// mit fremdem Namen (TList<T>) wird zu Text. Nach einem Fehler im Aufbau
// prüft die Regel den Block nicht weiter, Folgefehler wären Rauschen.
//
// Signatur (W1207, W1208): <param> zu einem Parameter, den es nicht gibt;
// fehlende <param>, wenn der Block überhaupt Parameter beschreibt (wie
// W1208 „but other parameters do“); <returns> an einer Routine ohne Ergebnis
// und fehlendes <returns> an einer Funktion, deren Block Parameter beschreibt
// (beides nur mit checkReturns). Mit <inheritdoc/> fehlt nichts. Korrektur:
// unbekannte <param> der Reihe nach auf die fehlenden umbenennen, weitere
// fehlende als leere Zeilen in Signaturreihenfolge ergänzen, überzählige und
// <returns> an Prozeduren entfernen, <returns> ergänzen.
//
// cref (W1206): Ziele über den Index wie der Hover (TNameResolver.LocateCref).
// Still ohne Index, wenn eine Unit aus uses fehlt, bei generischen Zielen,
// Unit-Namen und Typen mit unbekannten Vorfahren. Korrektur: das ähnlichste
// Symbol (TTextFuzzy.Closest), sofern es sich auflösen lässt.
//
// requirePublic: public- und published-Methoden und -Properties von Typen im
// interface ohne ///-Kommentar; override und Properties ohne Typ (geerbte
// Doku) zählen nicht. Korrektur: Gerüst wie nach "///" (#88).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  XmlDocMismatchRuleId = 'xmldoc-mismatch';

type
  TXmlDocMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterXmlDocRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Character,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.UnresolvedNames,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.DocComments,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Text.Lines,
  Atlas.Text.Fuzzy;

const
  // Tags der XML-Dokumentation: Nicht geschlossen bekommen sie ein Endtag, fremde Namen werden zu Text.
  DocTags: array[0..27] of string = ('summary', 'param', 'typeparam', 'returns', 'value', 'exception', 'remarks',
    'example', 'seealso', 'see', 'para', 'c', 'code', 'b', 'i', 'u', 'list', 'item', 'term', 'description',
    'listheader', 'paramref', 'typeparamref', 'inheritdoc', 'br', 'permission', 'include', 'note');
  // Abschnitte, die einander nicht enthalten: Ein offener endet vor dem nächsten (wie TXmlDoc).
  BlockSections: array[0..7] of string = ('summary', 'param', 'typeparam', 'returns', 'value', 'exception',
    'remarks', 'example');
  // Tags, die ohne Attribut (name bzw. cref) nichts bedeuten: so geschrieben ist Text gemeint ("ohne <param>").
  AttributeTags: array[0..8] of string = ('param', 'typeparam', 'paramref', 'typeparamref', 'exception',
    'permission', 'see', 'seealso', 'include');
  // Entitäten, die XML ohne DTD kennt.
  XmlEntities: array[0..4] of string = ('lt', 'gt', 'amp', 'quot', 'apos');
  RoutineWords: array[0..5] of string = ('class', 'function', 'procedure', 'constructor', 'destructor', 'operator');

type
  /// <summary>Ersetzung im XML eines Blocks: [Start, Stop) 1-basiert durch Text.</summary>
  TDocReplacement = record
    Start: Integer;
    Stop: Integer;
    Text: string;
    class function Create(AStart, AStop: Integer; const AText: string): TDocReplacement; static;
  end;

  TDocAttribute = record
    Name: string;
    Value: string;
    /// <summary>Wert ohne Anführungszeichen, [ValueStart, ValueStop) im XML des Blocks.</summary>
    ValueStart: Integer;
    ValueStop: Integer;
  end;

  TDocElement = record
    Name: string;
    Attributes: TArray<TDocAttribute>;
    /// <summary>"&lt;" des Starttags, Zeichen hinter dessen "&gt;", "&lt;" des Endtags und Zeichen hinter dem
    /// Element (1-basiert im XML des Blocks).</summary>
    Start: Integer;
    OpenStop: Integer;
    CloseStart: Integer;
    Stop: Integer;
    /// <summary>0 = oberste Ebene.</summary>
    Depth: Integer;
    HasChildren: Boolean;
    function Attribute(const AName: string; out AAttribute: TDocAttribute): Boolean;
  end;

  /// <summary>Verstoß gegen wohlgeformtes XML.</summary>
  TDocFlaw = record
    Start: Integer;
    Stop: Integer;
    Message: string;
    FixTitle: string;
    Replacements: TArray<TDocReplacement>;
    /// <summary>Fehler im Aufbau (Tags); danach prüft die Regel den Block nicht weiter.</summary>
    Structural: Boolean;
  end;

  /// <summary>Zerlegt das XML eines Blocks streng nach XML 1.0 (anders als der fehlertolerante TXmlDoc-Parser).
  /// </summary>
  TDocScanner = class
  private
    FXml: string;
    FLength: Integer;
    FElements: TList<TDocElement>;
    FStack: TList<Integer>;
    FFlaws: TList<TDocFlaw>;
    FBroken: Boolean;
    function IsSpaceAt(AIndex: Integer): Boolean;
    function IsNameStartAt(AIndex: Integer): Boolean;
    function IsNameCharAt(AIndex: Integer): Boolean;
    procedure AddFlaw(AStart, AStop: Integer; const AMessage, AFixTitle: string;
      const AReplacements: TArray<TDocReplacement>; AStructural: Boolean);
    procedure EscapeLess(AIndex: Integer; const ACode: string);
    procedure ScanEntity(var AIndex: Integer);
    procedure ScanStartTag(var AIndex: Integer);
    procedure ScanEndTag(var AIndex: Integer);
    procedure Skip(var AIndex: Integer; const AOpen, AClose: string);
    procedure Unclosed(AElement, AInsertAt: Integer);
  public
    constructor Create(const AXml: string);
    destructor Destroy; override;
    procedure Scan;
    function Elements: TArray<TDocElement>;
    function Flaws: TArray<TDocFlaw>;
    property Broken: Boolean read FBroken;
  end;

  /// <summary>Folge von ///-Zeilen: Inhalt ohne "///", Zeilen mit #10 verbunden.</summary>
  TDocBlock = record
    Xml: string;
    /// <summary>Je Zeile: Anfang im XML (1-basiert), Offset im Dokument (0-basiert) und Dokumentzeile.</summary>
    Starts: TArray<Integer>;
    Offsets: TArray<Integer>;
    Lines: TArray<Integer>;
    Indent: string;
    FirstToken: Integer;
    LastToken: Integer;
    /// <summary>Offset im Dokument zum Zeichen AIndex des XML.</summary>
    function OffsetOf(AIndex: Integer): Integer;
    /// <summary>Zeile des Blocks (ab 0) zum Zeichen AIndex des XML.</summary>
    function RowOf(AIndex: Integer): Integer;
    /// <summary>Steht in der Zeile von AStart vor AStart und in der von AStop ab AStop nur Leerraum?</summary>
    function OwnsLines(AStart, AStop: Integer): Boolean;
  end;

  TDocSignature = record
    Params: TArray<string>;
    HasResult: Boolean;
  end;

class function TDocReplacement.Create(AStart, AStop: Integer; const AText: string): TDocReplacement;
begin
  Result.Start := AStart;
  Result.Stop := AStop;
  Result.Text := AText;
end;

function TDocElement.Attribute(const AName: string; out AAttribute: TDocAttribute): Boolean;
var
  Item: TDocAttribute;
begin
  for Item in Attributes do
    if SameText(Item.Name, AName) then
    begin
      AAttribute := Item;
      Exit(True);
    end;
  AAttribute := Default(TDocAttribute);
  Result := False;
end;

function TDocBlock.RowOf(AIndex: Integer): Integer;
begin
  Result := High(Starts);
  while (Result > 0) and (Starts[Result] > AIndex) do
    Dec(Result);
end;

function TDocBlock.OffsetOf(AIndex: Integer): Integer;
var
  Row: Integer;
begin
  Row := RowOf(AIndex);
  Result := Offsets[Row] + AIndex - Starts[Row];
end;

function TDocBlock.OwnsLines(AStart, AStop: Integer): Boolean;
var
  Index: Integer;
begin
  Index := Starts[RowOf(AStart)];
  while Index < AStart do
  begin
    if not CharInSet(Xml[Index], [' ', #9]) then
      Exit(False);
    Inc(Index);
  end;
  Index := AStop;
  while (Index <= Length(Xml)) and (Xml[Index] <> #10) do
  begin
    if not CharInSet(Xml[Index], [' ', #9]) then
      Exit(False);
    Inc(Index);
  end;
  Result := True;
end;

{ TDocScanner }

constructor TDocScanner.Create(const AXml: string);
begin
  inherited Create;
  FXml := AXml;
  FLength := Length(AXml);
  FElements := TList<TDocElement>.Create;
  FStack := TList<Integer>.Create;
  FFlaws := TList<TDocFlaw>.Create;
end;

destructor TDocScanner.Destroy;
begin
  FFlaws.Free;
  FStack.Free;
  FElements.Free;
  inherited;
end;

function TDocScanner.Elements: TArray<TDocElement>;
begin
  Result := FElements.ToArray;
end;

function TDocScanner.Flaws: TArray<TDocFlaw>;
begin
  Result := FFlaws.ToArray;
end;

function TDocScanner.IsSpaceAt(AIndex: Integer): Boolean;
begin
  Result := (AIndex <= FLength) and CharInSet(FXml[AIndex], [' ', #9, #10, #13]);
end;

function TDocScanner.IsNameStartAt(AIndex: Integer): Boolean;
begin
  Result := (AIndex <= FLength) and (CharInSet(FXml[AIndex], ['A'..'Z', 'a'..'z', '_', ':']) or
    ((Ord(FXml[AIndex]) > 127) and FXml[AIndex].IsLetter));
end;

function TDocScanner.IsNameCharAt(AIndex: Integer): Boolean;
begin
  Result := IsNameStartAt(AIndex) or ((AIndex <= FLength) and CharInSet(FXml[AIndex], ['0'..'9', '-', '.']));
end;

procedure TDocScanner.AddFlaw(AStart, AStop: Integer; const AMessage, AFixTitle: string;
  const AReplacements: TArray<TDocReplacement>; AStructural: Boolean);
var
  Flaw: TDocFlaw;
begin
  Flaw.Start := AStart;
  Flaw.Stop := AStop;
  Flaw.Message := 'Doku-Kommentar ist kein wohlgeformtes XML: ' + AMessage;
  Flaw.FixTitle := AFixTitle;
  Flaw.Replacements := AReplacements;
  Flaw.Structural := AStructural;
  FFlaws.Add(Flaw);
  if AStructural then
    FBroken := True;
end;

procedure TDocScanner.EscapeLess(AIndex: Integer; const ACode: string);
begin
  AddFlaw(AIndex, AIndex + 1, Format('''<'' muss &lt; heißen (wie %s).', [ACode]), '''<'' als &lt; schreiben',
    [TDocReplacement.Create(AIndex, AIndex + 1, '&lt;')], False);
end;

procedure TDocScanner.ScanEntity(var AIndex: Integer);
var
  Index: Integer;
  Name: string;

  procedure Escape(const AMessage: string);
  begin
    AddFlaw(AIndex, AIndex + 1, AMessage, '''&'' als &amp; schreiben',
      [TDocReplacement.Create(AIndex, AIndex + 1, '&amp;')], False);
  end;

begin
  Index := AIndex + 1;
  if (Index > FLength) or IsSpaceAt(Index) then
  begin
    Escape('''&'' muss &amp; heißen (wie W1201).');
    Inc(AIndex);
    Exit;
  end;
  if FXml[Index] = '#' then
  begin
    Inc(Index);
    if (Index <= FLength) and CharInSet(FXml[Index], ['x', 'X']) then
    begin
      Inc(Index);
      while (Index <= FLength) and CharInSet(FXml[Index], ['0'..'9', 'a'..'f', 'A'..'F']) do
        Inc(Index);
    end
    else
      while (Index <= FLength) and CharInSet(FXml[Index], ['0'..'9']) do
        Inc(Index);
    if (Index <= FLength) and (FXml[Index] = ';') and not CharInSet(FXml[Index - 1], ['#', 'x', 'X']) then
      AIndex := Index + 1
    else
    begin
      Escape('''&'' muss &amp; heißen (wie W1205).');
      Inc(AIndex);
    end;
    Exit;
  end;
  if not IsNameStartAt(Index) then
  begin
    Escape('''&'' muss &amp; heißen (wie W1203).');
    Inc(AIndex);
    Exit;
  end;
  while IsNameCharAt(Index) do
    Inc(Index);
  Name := Copy(FXml, AIndex + 1, Index - AIndex - 1);
  if (Index > FLength) or (FXml[Index] <> ';') then
  begin
    Escape('''&'' muss &amp; heißen (wie W1205).');
    Inc(AIndex);
    Exit;
  end;
  if IndexText(Name, XmlEntities) < 0 then
    Escape(Format('&%s; ist in XML nicht definiert (wie W1202).', [Name]));
  AIndex := Index + 1;
end;

procedure TDocScanner.Skip(var AIndex: Integer; const AOpen, AClose: string);
var
  Close: Integer;
begin
  Close := PosEx(AClose, FXml, AIndex + Length(AOpen));
  if Close = 0 then
  begin
    AddFlaw(AIndex, AIndex + Length(AOpen), Format('%s wird nicht mit %s geschlossen.', [AOpen, AClose]),
      Format('%s ergänzen', [AClose]), [TDocReplacement.Create(FLength + 1, FLength + 1, AClose)], True);
    AIndex := FLength + 1;
  end
  else
    AIndex := Close + Length(AClose);
end;

procedure TDocScanner.ScanStartTag(var AIndex: Integer);
var
  Index, NameStop, ValueStart: Integer;
  Element, Parent: TDocElement;
  Attribute: TDocAttribute;
  Quote: Char;
  HadSpace: Boolean;
begin
  if (AIndex + 1 > FLength) or IsSpaceAt(AIndex + 1) then
  begin
    EscapeLess(AIndex, 'W1201');
    Inc(AIndex);
    Exit;
  end;
  if not IsNameStartAt(AIndex + 1) then
  begin
    EscapeLess(AIndex, 'W1203');
    Inc(AIndex);
    Exit;
  end;
  Index := AIndex + 1;
  while IsNameCharAt(Index) do
    Inc(Index);
  NameStop := Index;
  if (Index <= FLength) and not IsSpaceAt(Index) and (FXml[Index] <> '>') and (FXml[Index] <> '/') then
  begin
    EscapeLess(AIndex, 'W1204');
    Inc(AIndex);
    Exit;
  end;
  Element := Default(TDocElement);
  Element.Name := Copy(FXml, AIndex + 1, NameStop - AIndex - 1);
  Element.Start := AIndex;
  Element.Depth := FStack.Count;
  while True do
  begin
    HadSpace := IsSpaceAt(Index);
    while IsSpaceAt(Index) do
      Inc(Index);
    if Index > FLength then
    begin
      EscapeLess(AIndex, 'W1205');
      Inc(AIndex);
      Exit;
    end;
    if FXml[Index] = '>' then
    begin
      Element.OpenStop := Index + 1;
      Break;
    end;
    if (FXml[Index] = '/') and (Index < FLength) and (FXml[Index + 1] = '>') then
    begin
      Element.OpenStop := Index + 2;
      Element.CloseStart := Element.OpenStop;
      Element.Stop := Element.OpenStop;
      Break;
    end;
    if not HadSpace or not IsNameStartAt(Index) then
    begin
      EscapeLess(AIndex, 'W1205');
      Inc(AIndex);
      Exit;
    end;
    Attribute := Default(TDocAttribute);
    ValueStart := Index;
    while IsNameCharAt(Index) do
      Inc(Index);
    Attribute.Name := Copy(FXml, ValueStart, Index - ValueStart);
    while IsSpaceAt(Index) do
      Inc(Index);
    if (Index > FLength) or (FXml[Index] <> '=') then
    begin
      EscapeLess(AIndex, 'W1205');
      Inc(AIndex);
      Exit;
    end;
    Inc(Index);
    while IsSpaceAt(Index) do
      Inc(Index);
    if (Index <= FLength) and ((FXml[Index] = '"') or (FXml[Index] = '''')) then
    begin
      Quote := FXml[Index];
      ValueStart := Index + 1;
      Index := PosEx(Quote, FXml, ValueStart);
      if Index = 0 then
      begin
        AddFlaw(ValueStart - 1, ValueStart, Format('Anführungszeichen hinter %s fehlt (wie W1205).',
          [Attribute.Name]), '', nil, True);
        AIndex := FLength + 1;
        Exit;
      end;
      Attribute.Value := Copy(FXml, ValueStart, Index - ValueStart);
      Attribute.ValueStart := ValueStart;
      Attribute.ValueStop := Index;
      Inc(Index);
    end
    else
    begin
      // Wert ohne Anführungszeichen: bis Leerraum oder Tagende.
      ValueStart := Index;
      while (Index <= FLength) and not IsSpaceAt(Index) and (FXml[Index] <> '>') and
        not ((FXml[Index] = '/') and (Index < FLength) and (FXml[Index + 1] = '>')) do
        Inc(Index);
      if Index = ValueStart then
      begin
        EscapeLess(AIndex, 'W1205');
        Inc(AIndex);
        Exit;
      end;
      AddFlaw(ValueStart, Index, Format('Wert von %s ohne Anführungszeichen (wie W1205).', [Attribute.Name]),
        'Anführungszeichen setzen', [TDocReplacement.Create(ValueStart, ValueStart, '"'),
        TDocReplacement.Create(Index, Index, '"')], False);
      Attribute.Value := Copy(FXml, ValueStart, Index - ValueStart);
      Attribute.ValueStart := ValueStart;
      Attribute.ValueStop := Index;
    end;
    Element.Attributes := Element.Attributes + [Attribute];
  end;
  if FStack.Count > 0 then
  begin
    Parent := FElements[FStack.Last];
    Parent.HasChildren := True;
    FElements[FStack.Last] := Parent;
  end;
  FElements.Add(Element);
  if Element.Stop = 0 then
    FStack.Add(FElements.Count - 1);
  AIndex := Element.OpenStop;
end;

procedure TDocScanner.Unclosed(AElement, AInsertAt: Integer);
var
  Element: TDocElement;
  Index: Integer;
begin
  Element := FElements[AElement];
  // Ein offener Abschnitt endet vor dem nächsten Abschnitt darin, hinter dem letzten Zeichen davor.
  if IndexText(Element.Name, BlockSections) >= 0 then
    for Index := FElements.Count - 1 downto AElement + 1 do
      if IndexText(FElements[Index].Name, BlockSections) >= 0 then
        AInsertAt := FElements[Index].Start;
  while (AInsertAt > Element.OpenStop) and IsSpaceAt(AInsertAt - 1) do
    Dec(AInsertAt);
  if SameText(Element.Name, 'br') then
    AddFlaw(Element.Start, Element.OpenStop, '<br> wird nicht geschlossen.', '<br/> schreiben',
      [TDocReplacement.Create(Element.OpenStop - 1, Element.OpenStop - 1, '/')], True)
  else if (Length(Element.Attributes) = 0) and not Element.HasChildren and
    ((IndexText(Element.Name, DocTags) < 0) or (IndexText(Element.Name, AttributeTags) >= 0)) then
    // Fremder Name oder Tag ohne sein Attribut, ohne Inhalt: gemeint ist Text wie TList<T>.
    AddFlaw(Element.Start, Element.OpenStop, Format('<%s> wird nicht geschlossen.', [Element.Name]),
      Format('<%s> als Text schreiben', [Element.Name]), [TDocReplacement.Create(Element.Start, Element.Start + 1,
      '&lt;'), TDocReplacement.Create(Element.OpenStop - 1, Element.OpenStop, '&gt;')], True)
  else
    AddFlaw(Element.Start, Element.OpenStop, Format('<%s> wird nicht geschlossen.', [Element.Name]),
      Format('</%s> ergänzen', [Element.Name]), [TDocReplacement.Create(AInsertAt, AInsertAt,
      Format('</%s>', [Element.Name]))], True);
end;

procedure TDocScanner.ScanEndTag(var AIndex: Integer);
var
  Index, Level: Integer;
  Name: string;
  Element: TDocElement;
begin
  Index := AIndex + 2;
  if not IsNameStartAt(Index) then
  begin
    EscapeLess(AIndex, 'W1203');
    Inc(AIndex);
    Exit;
  end;
  while IsNameCharAt(Index) do
    Inc(Index);
  Name := Copy(FXml, AIndex + 2, Index - AIndex - 2);
  while IsSpaceAt(Index) do
    Inc(Index);
  if (Index > FLength) or (FXml[Index] <> '>') then
  begin
    EscapeLess(AIndex, 'W1205');
    Inc(AIndex);
    Exit;
  end;
  Level := FStack.Count - 1;
  while (Level >= 0) and (FElements[FStack[Level]].Name <> Name) do
    Dec(Level);
  if Level < 0 then
  begin
    AddFlaw(AIndex, Index + 1, Format('</%s> hat kein öffnendes Tag.', [Name]), Format('</%s> entfernen', [Name]),
      [TDocReplacement.Create(AIndex, Index + 1, '')], True);
    AIndex := FLength + 1;
    Exit;
  end;
  if Level < FStack.Count - 1 then
  begin
    Unclosed(FStack.Last, AIndex);
    AIndex := FLength + 1;
    Exit;
  end;
  Element := FElements[FStack.Last];
  Element.CloseStart := AIndex;
  Element.Stop := Index + 1;
  FElements[FStack.Last] := Element;
  FStack.Delete(FStack.Count - 1);
  AIndex := Index + 1;
end;

procedure TDocScanner.Scan;
var
  Index, Stop: Integer;
begin
  Index := 1;
  while (Index <= FLength) and not FBroken do
    case FXml[Index] of
      '&':
        ScanEntity(Index);
      '<':
        if Copy(FXml, Index, 4) = '<!--' then
          Skip(Index, '<!--', '-->')
        else if Copy(FXml, Index, 9) = '<![CDATA[' then
          Skip(Index, '<![CDATA[', ']]>')
        else if Copy(FXml, Index, 2) = '<?' then
          Skip(Index, '<?', '?>')
        else if Copy(FXml, Index, 2) = '</' then
          ScanEndTag(Index)
        else
          ScanStartTag(Index);
    else
      Inc(Index);
    end;
  if not FBroken and (FStack.Count > 0) then
  begin
    // Endtag hinter dem letzten Zeichen, das kein Leerraum ist.
    Stop := FLength + 1;
    while (Stop > 1) and IsSpaceAt(Stop - 1) do
      Dec(Stop);
    Unclosed(FStack.Last, Stop);
  end;
end;

{ Blöcke und Deklarationen }

function IsDocToken(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Comment) and StartsStr('///', AToken.Text) and
    not StartsStr('////', AToken.Text);
end;

/// <summary>Alle ///-Blöcke: aufeinanderfolgende Zeilen, in denen der Kommentar das erste Token ist.</summary>
function DocBlocks(const ATokens: TArray<TPascalToken>; const ALines: TArray<string>): TArray<TDocBlock>;
var
  Index: Integer;
  Block: TDocBlock;
  Line: string;

  function StartsLine(AIndex: Integer): Boolean;
  begin
    Result := (AIndex = 0) or (ATokens[AIndex - 1].EndPos.Line < ATokens[AIndex].StartPos.Line);
  end;

begin
  Result := nil;
  Index := 0;
  while Index <= High(ATokens) do
  begin
    if not IsDocToken(ATokens[Index]) or not StartsLine(Index) then
    begin
      Inc(Index);
      Continue;
    end;
    Block := Default(TDocBlock);
    Block.FirstToken := Index;
    Line := '';
    if ATokens[Index].StartPos.Line <= High(ALines) then
      Line := ALines[ATokens[Index].StartPos.Line];
    Block.Indent := Copy(Line, 1, ATokens[Index].StartPos.Character);
    repeat
      if Block.Xml <> '' then
        Block.Xml := Block.Xml + #10;
      Block.Starts := Block.Starts + [Length(Block.Xml) + 1];
      Block.Offsets := Block.Offsets + [ATokens[Index].Offset + 3];
      Block.Lines := Block.Lines + [ATokens[Index].StartPos.Line];
      Block.Xml := Block.Xml + Copy(ATokens[Index].Text, 4, MaxInt);
      Block.LastToken := Index;
      Inc(Index);
    until (Index > High(ATokens)) or not IsDocToken(ATokens[Index]) or
      (ATokens[Index].StartPos.Line <> ATokens[Index - 1].StartPos.Line + 1);
    Result := Result + [Block];
  end;
end;

/// <summary>Erstes Token der Deklaration hinter dem Block (Attribute übersprungen); -1 ohne.</summary>
function DeclarationToken(const ATokens: TArray<TPascalToken>; ALast: Integer): Integer;
var
  Depth: Integer;
begin
  Result := ALast + 1;
  while (Result <= High(ATokens)) and ATokens[Result].IsSymbol('[') do
  begin
    Depth := 0;
    repeat
      if ATokens[Result].IsSymbol('[') then
        Inc(Depth)
      else if ATokens[Result].IsSymbol(']') then
        Dec(Depth);
      Inc(Result);
    until (Result > High(ATokens)) or (Depth = 0);
  end;
  if Result > High(ATokens) then
    Result := -1;
end;

// Iterativ (Bericht M1).
procedure CollectDeclarations(ARoot: TSyntaxNode; AMap: TDictionary<Integer, TSyntaxNode>);
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl, TSyntaxKind.TypeDecl,
        TSyntaxKind.Field, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl]) and not AMap.ContainsKey(Node.StartOffset) then
        AMap.Add(Node.StartOffset, Node);
      if Node.Kind = TSyntaxKind.Block then
        Continue;
      for Index := Node.ChildCount - 1 downto 0 do
        Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

function SignatureOf(AHeader: TSyntaxNode): TDocSignature;
var
  Parameters: TSyntaxNode;
  Index: Integer;
  Name: string;
begin
  Result := Default(TDocSignature);
  for Index := 0 to AHeader.ChildCount - 1 do
    if AHeader[Index].Kind = TSyntaxKind.TypeReference then
      Result.HasResult := True;
  Parameters := AHeader.FindChild(TSyntaxKind.Parameters);
  if Parameters = nil then
    Exit;
  for Index := 0 to Parameters.ChildCount - 1 do
    if Parameters[Index].Kind = TSyntaxKind.Parameter then
      for Name in Parameters[Index].Name.Split([',']) do
        Result.Params := Result.Params + [Trim(Name)];
end;

/// <summary>Typ, in dem ANode deklariert ist ("TAussen.TInnen"), bei TFoo.Bar im implementation-Teil "TFoo";
/// bei Typen der Typ selbst.</summary>
function ContainerOf(ANode: TSyntaxNode): string;
var
  Node: TSyntaxNode;
begin
  Result := '';
  if (ANode.Kind = TSyntaxKind.RoutineHeader) and (LastDelimiter('.', ANode.Name) > 0) then
    Exit(Copy(ANode.Name, 1, LastDelimiter('.', ANode.Name) - 1));
  Node := ANode;
  while Node <> nil do
  begin
    if Node.Kind = TSyntaxKind.TypeDecl then
      if Result = '' then
        Result := Node.Name
      else
        Result := Node.Name + '.' + Result;
    Node := Node.Parent;
  end;
end;

/// <summary>Name der Deklaration ab Token AStart (hinter class, function …), bei TFoo.Bar die ganze Kette.</summary>
function NameRange(const ATokens: TArray<TPascalToken>; AStart: Integer; out AFrom, ATo: Integer): Boolean;
var
  Index: Integer;
begin
  Index := AStart;
  while (Index <= High(ATokens)) and ((ATokens[Index].Kind = TPascalTokenKind.Comment) or
    MatchText(ATokens[Index].Text, RoutineWords) or SameText(ATokens[Index].Text, 'property')) do
    Inc(Index);
  Result := (Index <= High(ATokens)) and (ATokens[Index].Kind in [TPascalTokenKind.Identifier,
    TPascalTokenKind.Keyword]);
  if not Result then
    Exit;
  AFrom := Index;
  ATo := Index;
  while (ATo + 2 <= High(ATokens)) and ATokens[ATo + 1].IsSymbol('.') and
    (ATokens[ATo + 2].Kind = TPascalTokenKind.Identifier) do
    Inc(ATo, 2);
end;

/// <summary>Edits nach Anfang sortiert (stabil), wie Clients und Tests sie von hinten anwenden.</summary>
function Sorted(const AEdits: TArray<TTextEdit>): TArray<TTextEdit>;
var
  Index, Position: Integer;
  Edit: TTextEdit;

  function Before(const A, B: TTextPosition): Boolean;
  begin
    Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
  end;

begin
  Result := Copy(AEdits);
  for Index := 1 to High(Result) do
  begin
    Edit := Result[Index];
    Position := Index;
    while (Position > 0) and Before(Edit.Range.StartPos, Result[Position - 1].Range.StartPos) do
    begin
      Result[Position] := Result[Position - 1];
      Dec(Position);
    end;
    Result[Position] := Edit;
  end;
end;

function Joined(const ANames: TArray<string>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(ANames) do
    if Index = 0 then
      Result := ANames[Index]
    else if Index = High(ANames) then
      Result := Result + ' und ' + ANames[Index]
    else
      Result := Result + ', ' + ANames[Index];
end;

function Contains(const ANames: TArray<string>; const AName: string): Boolean;
var
  Name: string;
begin
  for Name in ANames do
    if SameText(Name, AName) then
      Exit(True);
  Result := False;
end;

{ TXmlDocMismatchRule }

function TXmlDocMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(XmlDocMismatchRuleId, TRuleSeverity.Hint,
    'XMLDoc passt nicht zur Signatur oder ist kein wohlgeformtes XML');
end;

procedure TXmlDocMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Tokens: TArray<TPascalToken>;
  Lines: TArray<string>;
  LineBreak: string;
  CheckReturns, RequirePublic: Boolean;
  Declarations: TDictionary<Integer, TSyntaxNode>;
  Documented: TDictionary<TSyntaxNode, Boolean>;
  Resolver: TNameResolver;
  FromUnit: TUnitIndex;
  CrefsKnown: Boolean;
  CrefLevel: TRuleConfidence;

  function TokenAt(AOffset: Integer): Integer;
  var
    Low, High_, Middle: Integer;
  begin
    Low := 0;
    High_ := High(Tokens);
    while Low <= High_ do
    begin
      Middle := (Low + High_) div 2;
      if Tokens[Middle].Offset < AOffset then
        Low := Middle + 1
      else if Tokens[Middle].Offset > AOffset then
        High_ := Middle - 1
      else
        Exit(Middle);
    end;
    Result := -1;
  end;

  function DeclarationRange(ANode: TSyntaxNode): TTextRange;
  var
    First, Last: Integer;
  begin
    First := TokenAt(ANode.StartOffset);
    if (First >= 0) and NameRange(Tokens, First, First, Last) then
      Result := TTextRange.Create(Tokens[First].StartPos, Tokens[Last].EndPos)
    else
      Result := TTextRange.Create(ANode.StartPos, ANode.StartPos);
  end;

  function XmlRange(const ABlock: TDocBlock; AStart, AStop: Integer): TTextRange;
  begin
    Result := TRuleDerived.OffsetRange(Cache, AContext, ABlock.OffsetOf(AStart), ABlock.OffsetOf(AStop));
  end;

  function ReplacementEdit(const ABlock: TDocBlock; const AReplacement: TDocReplacement): TRuleEdit;
  begin
    Result := TRuleEdit.Create(XmlRange(ABlock, AReplacement.Start, AReplacement.Stop), AReplacement.Text);
  end;

  // Element entfernen; füllt es seine Zeilen allein, die ganzen Zeilen.
  function RemoveEdit(const ABlock: TDocBlock; const AElement: TDocElement): TRuleEdit;
  begin
    if ABlock.OwnsLines(AElement.Start, AElement.Stop) then
      Result := TRuleEdit.Create(TTextRange.Create(ABlock.Lines[ABlock.RowOf(AElement.Start)], 0,
        ABlock.Lines[ABlock.RowOf(AElement.Stop)] + 1, 0), '')
    else
      Result := TRuleEdit.Create(XmlRange(ABlock, AElement.Start, AElement.Stop), '');
  end;

  function DocLine(const ABlock: TDocBlock; const AText: string): string;
  begin
    Result := ABlock.Indent + '/// ' + AText + LineBreak;
  end;

  procedure ReportFlaws(const ABlock: TDocBlock; const AFlaws: TArray<TDocFlaw>);
  var
    Flaw: TDocFlaw;
    Replacement: TDocReplacement;
    Edits: TArray<TRuleEdit>;
  begin
    for Flaw in AFlaws do
    begin
      Edits := nil;
      for Replacement in Flaw.Replacements do
        Edits := Edits + [ReplacementEdit(ABlock, Replacement)];
      if Length(Edits) > 0 then
        AReport.Add(XmlRange(ABlock, Flaw.Start, Flaw.Stop), Flaw.Message,
          [TRuleFix.Create(Flaw.FixTitle, Sorted(Edits))])
      else
        AReport.Add(XmlRange(ABlock, Flaw.Start, Flaw.Stop), Flaw.Message);
    end;
  end;

  procedure CheckSignature(const ABlock: TDocBlock; const AElements: TArray<TDocElement>; AHeader: TSyntaxNode);
  var
    Signature: TDocSignature;
    Element, Returns: TDocElement;
    Attribute: TDocAttribute;
    // <param> der obersten Ebene und je Eintrag sein Name; Unknown = Positionen darin ohne Parameter.
    Params: TArray<TDocElement>;
    ParamNames, Seen, Missing, Parts, Names: TArray<string>;
    Unknown: TArray<Integer>;
    HasReturns, Inherits, StrayReturns, MissingReturns: Boolean;
    Edits: TArray<TRuleEdit>;
    Message, Name: string;
    Index, Position, Row, Previous: Integer;
    Range: TTextRange;
    // Erste und letzte Blockzeile je Signaturparameter nach der Korrektur, -1 ohne.
    FirstRows, LastRows: TArray<Integer>;
    Inserts: TDictionary<Integer, string>;
    Keys: TArray<Integer>;

    procedure Insert(ARow: Integer; const AText: string);
    begin
      if Inserts.ContainsKey(ARow) then
        Inserts[ARow] := Inserts[ARow] + DocLine(ABlock, AText)
      else
        Inserts.Add(ARow, DocLine(ABlock, AText));
    end;

  begin
    Signature := SignatureOf(AHeader);
    HasReturns := False;
    Inherits := False;
    Returns := Default(TDocElement);
    Params := nil;
    ParamNames := nil;
    Seen := nil;
    Unknown := nil;
    for Element in AElements do
    begin
      if SameText(Element.Name, 'inheritdoc') then
        Inherits := True;
      if Element.Depth > 0 then
        Continue;
      if SameText(Element.Name, 'returns') then
      begin
        HasReturns := True;
        Returns := Element;
      end
      else if SameText(Element.Name, 'param') and Element.Attribute('name', Attribute) then
      begin
        Params := Params + [Element];
        ParamNames := ParamNames + [Trim(Attribute.Value)];
        if Contains(Signature.Params, Trim(Attribute.Value)) then
          Seen := Seen + [Trim(Attribute.Value)]
        else
          Unknown := Unknown + [High(Params)];
      end;
    end;
    Missing := nil;
    if (Length(Params) > 0) and not Inherits then
      for Name in Signature.Params do
        if not Contains(Seen, Name) then
          Missing := Missing + [Name];
    StrayReturns := CheckReturns and HasReturns and not Signature.HasResult;
    // Fehlendes <returns> nur, wenn vollständige Doku verlangt ist: Die korrigierte Form aus #979 beschreibt
    // die Parameter einer Funktion ohne <returns> und gilt als passend.
    MissingReturns := CheckReturns and RequirePublic and Signature.HasResult and not HasReturns and not Inherits;
    if (Length(Unknown) = 0) and (Length(Missing) = 0) and not StrayReturns and not MissingReturns then
      Exit;
    Parts := nil;
    if Length(Unknown) > 0 then
    begin
      Names := nil;
      for Position in Unknown do
        Names := Names + [Format('<param name="%s">', [ParamNames[Position]])];
      Parts := Parts + [Joined(Names) + ' gibt es nicht'];
    end;
    if Length(Missing) = 1 then
      Parts := Parts + [Missing[0] + ' ist nicht beschrieben']
    else if Length(Missing) > 1 then
      Parts := Parts + [Joined(Missing) + ' sind nicht beschrieben'];
    if StrayReturns then
      Parts := Parts + ['<returns> steht an einer Routine ohne Ergebnis'];
    if MissingReturns then
      Parts := Parts + ['<returns> fehlt'];
    Message := String.Join('; ', Parts) + '.';
    // Korrektur: unbekannte der Reihe nach auf die fehlenden umbenennen, übrige unbekannte entfernen.
    Edits := nil;
    SetLength(FirstRows, Length(Signature.Params));
    SetLength(LastRows, Length(Signature.Params));
    for Index := 0 to High(Signature.Params) do
    begin
      FirstRows[Index] := -1;
      LastRows[Index] := -1;
    end;
    Previous := -1;
    for Index := 0 to High(Params) do
    begin
      Name := ParamNames[Index];
      Position := -1;
      for Row := 0 to High(Unknown) do
        if Unknown[Row] = Index then
          Position := Row;
      if Position >= Length(Missing) then
      begin
        Edits := Edits + [RemoveEdit(ABlock, Params[Index])];
        Continue;
      end;
      if Position >= 0 then
      begin
        Name := Missing[Position];
        Params[Index].Attribute('name', Attribute);
        Edits := Edits + [TRuleEdit.Create(XmlRange(ABlock, Attribute.ValueStart, Attribute.ValueStop), Name)];
      end;
      Previous := ABlock.RowOf(Params[Index].Stop - 1);
      for Row := 0 to High(Signature.Params) do
        if SameText(Signature.Params[Row], Name) and (FirstRows[Row] < 0) then
        begin
          FirstRows[Row] := ABlock.RowOf(Params[Index].Start);
          LastRows[Row] := Previous;
        end;
    end;
    Inserts := TDictionary<Integer, string>.Create;
    try
      // Fehlende ohne umbenanntes Gegenstück: hinter dem vorigen beschriebenen Parameter, sonst vor dem nächsten,
      // sonst hinter dem letzten verbliebenen <param>.
      for Index := 0 to High(Signature.Params) do
      begin
        if FirstRows[Index] >= 0 then
          Continue;
        Row := -1;
        for Position := Index - 1 downto 0 do
          if (Row < 0) and (LastRows[Position] >= 0) then
            Row := ABlock.Lines[LastRows[Position]] + 1;
        for Position := Index + 1 to High(Signature.Params) do
          if (Row < 0) and (FirstRows[Position] >= 0) then
            Row := ABlock.Lines[FirstRows[Position]];
        if (Row < 0) and (Previous >= 0) then
          Row := ABlock.Lines[Previous] + 1;
        if Row < 0 then
          Row := ABlock.Lines[High(ABlock.Lines)] + 1;
        Insert(Row, Format('<param name="%s"></param>', [Signature.Params[Index]]));
      end;
      if MissingReturns then
        if Previous >= 0 then
          Insert(ABlock.Lines[Previous] + 1, '<returns></returns>')
        else
          Insert(ABlock.Lines[High(ABlock.Lines)] + 1, '<returns></returns>');
      Keys := Inserts.Keys.ToArray;
      TArray.Sort<Integer>(Keys);
      for Row in Keys do
        Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Row, 0, Row, 0), Inserts[Row])];
    finally
      Inserts.Free;
    end;
    if StrayReturns then
      Edits := Edits + [RemoveEdit(ABlock, Returns)];
    if Length(Unknown) > 0 then
      Range := XmlRange(ABlock, Params[Unknown[0]].Start, Params[Unknown[0]].OpenStop)
    else if StrayReturns then
      Range := XmlRange(ABlock, Returns.Start, Returns.OpenStop)
    else
      Range := DeclarationRange(AHeader);
    AReport.Add(Range, Message, [TRuleFix.Create('Doku an die Signatur anpassen', Sorted(Edits))]);
  end;

  // Vorfahrenkette bis TObject bzw. IInterface bekannt? Sonst kann ein Mitglied geerbt sein.
  function ChainKnown(const AType: TResolvedSymbol): Boolean;
  var
    Current, Ancestor: TResolvedSymbol;
    Steps: Integer;
  begin
    Current := AType;
    for Steps := 1 to 64 do
    begin
      if Current.SymbolKind = TIndexSymbolKind.HelperType then
        Exit(False);
      if not Resolver.AncestorOf(Current, Ancestor) then
        Exit((Length(Current.Ancestors) = 0) and (SameText(Current.Name, 'TObject') or
          SameText(Current.Name, 'IInterface') or not (Current.SymbolKind in [TIndexSymbolKind.ClassType,
          TIndexSymbolKind.InterfaceType])));
      Current := Ancestor;
    end;
    Result := False;
  end;

  // Lässt sich ACref sicher als fehlend erkennen? Unit-Namen, generische Ziele, eingebaute Namen und Typen mit
  // unbekannten Vorfahren bleiben offen.
  function CrefMissing(const AContainer, AName: string): Boolean;
  var
    Found, Owner: TResolvedSymbol;
    Parts: TArray<string>;
    Prefix: string;
    Index: Integer;
    Ignored: TUnitIndex;
  begin
    Result := False;
    if (AName = '') or (LastDelimiter('<>{}`', AName) > 0) or TNameResolver.IsBuiltinTypeName(AName) or
      TUnresolvedNames.IsIntrinsic(AName) then
      Exit;
    if Resolver.LocateCref(FromUnit, AContainer, AName, Found) then
      Exit;
    Parts := AName.Split(['.']);
    Prefix := '';
    for Index := 0 to High(Parts) do
    begin
      if Prefix <> '' then
        Prefix := Prefix + '.';
      Prefix := Prefix + Parts[Index];
      if AContext.Index.FindUnit(Prefix, Ignored) then
        Exit;
    end;
    if Length(Parts) > 1 then
    begin
      Prefix := Copy(AName, 1, LastDelimiter('.', AName) - 1);
      if Resolver.ResolveTypeFrom(FromUnit, Prefix, Owner) and not ChainKnown(Owner) then
        Exit;
    end
    else if (AContainer <> '') and Resolver.ResolveTypeFrom(FromUnit, AContainer, Owner) and not ChainKnown(Owner) then
      Exit;
    Result := True;
  end;

  function CandidateNames(const ASymbols: TArray<TResolvedSymbol>): TArray<string>;
  var
    Symbol: TResolvedSymbol;
  begin
    Result := nil;
    for Symbol in ASymbols do
      Result := Result + [Symbol.Name];
  end;

  procedure CheckCref(const ABlock: TDocBlock; const AElement: TDocElement; const AAttribute: TDocAttribute;
    const AContainer: string; AOffset: Integer);
  var
    Value, Prefix, Name, Rest, Head, Tail, Wanted, Closest, Replaced: string;
    Found: TResolvedSymbol;
    Candidates: TArray<string>;
    Dot: Integer;
    Fixes: TArray<TRuleFix>;
    Message: string;
  begin
    Value := Trim(AAttribute.Value);
    Prefix := '';
    if (Length(Value) > 2) and (Value[2] = ':') then
    begin
      Prefix := Copy(Value, 1, 2);
      Value := Copy(Value, 3, MaxInt);
    end;
    Rest := '';
    if Pos('(', Value) > 0 then
    begin
      Rest := Copy(Value, Pos('(', Value), MaxInt);
      Value := Copy(Value, 1, Pos('(', Value) - 1);
    end;
    Name := Trim(Value);
    if not CrefMissing(AContainer, Name) then
      Exit;
    // Ähnlichster Name: Mitglied hinter dem Typ bzw. ein Name im Bereich der Deklaration.
    Dot := LastDelimiter('.', Name);
    Head := Copy(Name, 1, Dot);
    Tail := Copy(Name, Dot + 1, MaxInt);
    Wanted := Tail;
    Resolver.NameFilter :=
      function(const ACandidate: string): Boolean
      begin
        Result := Abs(Length(ACandidate) - Length(Wanted)) <= 2;
      end;
    try
      if Dot > 0 then
        Candidates := CandidateNames(Resolver.MemberCandidates(AContext.Tree, AContext.RelativePath,
          Copy(Name, 1, Dot - 1).Split(['.']), AOffset))
      else
      begin
        Candidates := CandidateNames(Resolver.ScopeCandidates(AContext.Tree, AContext.RelativePath, AOffset));
        if AContainer <> '' then
          Candidates := Candidates + CandidateNames(Resolver.MemberCandidates(AContext.Tree, AContext.RelativePath,
            AContainer.Split(['.']), AOffset));
      end;
    finally
      Resolver.NameFilter := nil;
    end;
    Closest := TTextFuzzy.Closest(Tail, Candidates);
    Fixes := nil;
    Message := Format('cref "%s" zeigt auf kein Symbol (wie W1206).', [AAttribute.Value]);
    if Closest <> '' then
    begin
      Replaced := Head + Closest;
      if Resolver.LocateCref(FromUnit, AContainer, Replaced, Found) then
      begin
        Message := Message + Format(' Gemeint ist wohl %s.', [Replaced]);
        Fixes := [TRuleFix.Create(Format('cref auf %s setzen', [Replaced]),
          [TRuleEdit.Create(XmlRange(ABlock, AAttribute.ValueStart, AAttribute.ValueStop),
          Prefix + Replaced + Rest)])];
      end;
    end;
    AReport.Add(XmlRange(ABlock, AElement.Start, AElement.OpenStop), Message, CrefLevel, Fixes);
  end;

  procedure CheckBlock(const ABlock: TDocBlock);
  var
    Scanner: TDocScanner;
    Elements: TArray<TDocElement>;
    Element: TDocElement;
    Attribute: TDocAttribute;
    Declaration: TSyntaxNode;
    Token: Integer;
  begin
    Declaration := nil;
    Token := DeclarationToken(Tokens, ABlock.LastToken);
    if Token >= 0 then
      Declarations.TryGetValue(Tokens[Token].Offset, Declaration);
    if Declaration <> nil then
      Documented.AddOrSetValue(Declaration, True);
    Scanner := TDocScanner.Create(ABlock.Xml);
    try
      Scanner.Scan;
      ReportFlaws(ABlock, Scanner.Flaws);
      if Scanner.Broken then
        Exit;
      Elements := Scanner.Elements;
    finally
      Scanner.Free;
    end;
    if (Declaration <> nil) and (Declaration.Kind = TSyntaxKind.RoutineHeader) then
      CheckSignature(ABlock, Elements, Declaration);
    if CrefsKnown then
      for Element in Elements do
        if Element.Attribute('cref', Attribute) then
          if Declaration <> nil then
            CheckCref(ABlock, Element, Attribute, ContainerOf(Declaration), Declaration.StartOffset)
          else
            CheckCref(ABlock, Element, Attribute, '', Tokens[ABlock.FirstToken].Offset);
  end;

  function Overrides(AMember: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    for Index := 0 to AMember.ChildCount - 1 do
      if (AMember[Index].Kind = TSyntaxKind.Directive) and SameText(AMember[Index].Name, 'override') then
        Exit(True);
    Result := False;
  end;

  // requirePublic: öffentliche Mitglieder von Typen im interface ohne Doku. Die Rekursion steigt nur in
  // verschachtelte Typdeklarationen ab (Tiefe wie die Schachtelung der Typen im Quelltext, unabhängig von
  // Anweisungen und Ausdrücken) und bleibt deshalb (Bericht M1).
  procedure CheckPublic(ANode: TSyntaxNode; APublic: Boolean);
  var
    Index, First, Row: Integer;
    Member: TSyntaxNode;
    Visible: Boolean;
    Skeleton: TArray<string>;
  begin
    Visible := APublic;
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Member := ANode[Index];
      case Member.Kind of
        TSyntaxKind.Visibility:
          Visible := APublic and (SameText(Member.Name, 'public') or SameText(Member.Name, 'published'));
        TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl, TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
        TSyntaxKind.RecordType, TSyntaxKind.InterfaceType:
          if Visible then
            CheckPublic(Member, True);
        TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl:
          begin
            if not Visible or Documented.ContainsKey(Member) or Overrides(Member) or
              not (ANode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
              TSyntaxKind.InterfaceType]) then
              Continue;
            // Property ohne Typ veröffentlicht eine geerbte neu, deren Doku gilt.
            if (Member.Kind = TSyntaxKind.PropertyDecl) and (Member.FindChild(TSyntaxKind.TypeReference) = nil) then
              Continue;
            // Gerüst über den Attributen.
            First := TokenAt(Member.StartOffset);
            Row := Member.StartPos.Line;
            while (First > 0) and Tokens[First - 1].IsSymbol(']') do
            begin
              repeat
                Dec(First);
              until (First <= 0) or Tokens[First].IsSymbol('[');
              Row := Tokens[First].StartPos.Line;
            end;
            Skeleton := TDocComments.Skeleton(TDocComments.Signature(Lines, Member.StartPos.Line),
              TTextLines.IndentOf(Lines[Row]));
            AReport.Add(DeclarationRange(Member), Format('Öffentliches Mitglied %s hat keinen Doku-Kommentar.',
              [Member.Name]), [TRuleFix.Create('Doku-Kommentar erzeugen', [TRuleEdit.Create(TTextRange.Create(Row,
              0, Row, 0), TTextLines.JoinLines(Skeleton, LineBreak) + LineBreak)])]);
          end;
      end;
    end;
  end;

var
  Block: TDocBlock;
  Section: TSyntaxNode;
  Index: Integer;
  Token: TPascalToken;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Tokens := AContext.Tree.Tokens;
  Lines := TTextLines.SplitLines(AContext.Text);
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  CheckReturns := TRuleOptions.Bool(AContext.Options, 'checkReturns', True);
  RequirePublic := TRuleOptions.Bool(AContext.Options, 'requirePublic', False);
  CrefsKnown := TUnresolvedNames.Available(AContext.Index) and TUnresolvedNames.UsesKnown(AContext.Index,
    TUsesClauses.UsedUnits(Tokens), AContext.Namespaces, AContext.EnsureUnit);
  // Mit Include-Dateien kann ein Ziel dort deklariert sein.
  CrefLevel := TRuleConfidence.High;
  for Token in Tokens do
    if (Token.Kind = TPascalTokenKind.Directive) and (StartsText('{$I ', Token.Text) or
      StartsText('{$INCLUDE ', Token.Text)) then
      CrefLevel := TRuleConfidence.Medium;
  Declarations := TDictionary<Integer, TSyntaxNode>.Create;
  Documented := TDictionary<TSyntaxNode, Boolean>.Create;
  Resolver := nil;
  try
    CollectDeclarations(AContext.Tree.Root, Declarations);
    if CrefsKnown then
    begin
      Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
      Resolver.Namespaces := AContext.Namespaces;
      FromUnit := TRuleDerived.UnitIndex(Cache, AContext);
    end;
    for Block in DocBlocks(Tokens, Lines) do
      CheckBlock(Block);
    if RequirePublic then
      for Index := 0 to AContext.Tree.Root.ChildCount - 1 do
      begin
        Section := AContext.Tree.Root[Index];
        if Section.Kind = TSyntaxKind.InterfaceSection then
          CheckPublic(Section, True);
      end;
  finally
    Resolver.Free;
    Documented.Free;
    Declarations.Free;
  end;
end;

procedure RegisterXmlDocRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TXmlDocMismatchRule.Create);
end;

end.
