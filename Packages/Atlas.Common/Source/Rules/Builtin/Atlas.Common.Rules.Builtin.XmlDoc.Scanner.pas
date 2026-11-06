unit Atlas.Common.Rules.Builtin.XmlDoc.Scanner;

// Strenger XML-Scanner der Regel xmldoc-mismatch (#979): zerlegt das XML eines
// ///-Blocks nach XML 1.0 in Elemente und meldet Verstöße mit Korrektur
// ("<" und "&" ohne gültiges Tag bzw. Entität, unbekannte Entität, Attributwert
// ohne Anführungszeichen, nicht geschlossene und überzählige Endtags). Nach
// einem Fehler im Aufbau bricht er ab (Broken), Folgefehler wären Rauschen.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  {$SCOPEDENUMS ON}
  /// <summary>Ergebnis beim Lesen eines Starttags: Pending liest weiter, Complete am Tagende, Malformed ist kein
  /// Tag ("&lt;" maskieren), Fatal bricht den Block ab.</summary>
  TTagOutcome = (Pending, Complete, Malformed, Fatal);
  {$SCOPEDENUMS OFF}

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
    /// <summary>Code von dcc für diese Form (#1383); leer, wo dcc sie nicht meldet.</summary>
    Code: string;
    FixTitle: string;
    Replacements: TArray<TDocReplacement>;
    /// <summary>Fehler im Aufbau (Tags); danach prüft die Regel den Block nicht weiter.</summary>
    Structural: Boolean;
    /// <summary>Verstoß von AStart bis AStop (ausschließlich) ohne dcc-Code.</summary>
    class function Create(AStart, AStop: Integer; const AMessage, AFixTitle: string;
      const AReplacements: TArray<TDocReplacement>; AStructural: Boolean): TDocFlaw; static;
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
    function SkipSpaces(AIndex: Integer): Integer;
    function SkipName(AIndex: Integer): Integer;
    function SkipChars(AIndex: Integer; const AChars: TSysCharSet): Integer;
    procedure AddFlaw(const AFlaw: TDocFlaw);
    procedure EscapeLess(AIndex: Integer; const ACode: string);
    /// <summary>"&lt;" an AIndex ist kein Tag: maskieren und dahinter weiterlesen.</summary>
    procedure RejectTag(var AIndex: Integer; const ACode: string);
    procedure EscapeAmpersand(AIndex: Integer; const AMessage: string);
    /// <summary>Hinter dem ";" einer Zeichenreferenz ab AStart (hinter "&amp;#"); 0, wenn keine.</summary>
    function CharRefStop(AStart: Integer): Integer;
    /// <summary>Hinter dem ";" einer Entität mit Namen ab AStart; 0, wenn keine.</summary>
    function EntityRefStop(AStart: Integer): Integer;
    procedure ScanEntity(var AIndex: Integer);
    /// <summary>Endet an AIndex das Starttag ("&gt;" oder "/&gt;")? Setzt dann die Grenzen von AElement.</summary>
    function TagEndAt(AIndex: Integer; var AElement: TDocElement): Boolean;
    function ScanQuotedValue(var AIndex: Integer; var AAttribute: TDocAttribute): TTagOutcome;
    function ScanBareValue(var AIndex: Integer; var AAttribute: TDocAttribute): TTagOutcome;
    function ScanAttribute(var AIndex: Integer; out AAttribute: TDocAttribute): TTagOutcome;
    /// <summary>Attribute und Tagende ab AIndex (hinter dem Tagnamen).</summary>
    function ScanAttributes(AIndex: Integer; var AElement: TDocElement): TTagOutcome;
    procedure AddElement(const AElement: TDocElement);
    procedure ScanStartTag(var AIndex: Integer);
    procedure ScanEndTag(var AIndex: Integer);
    procedure ScanMarkup(var AIndex: Integer);
    procedure Skip(var AIndex: Integer; const AOpen, AClose: string);
    procedure Unclosed(AElement, AInsertAt: Integer);
    /// <summary>Das innerste offene Element am Ende des Blocks.</summary>
    procedure CloseOpen;
  public
    constructor Create(const AXml: string);
    destructor Destroy; override;
    procedure Scan;
    function Elements: TArray<TDocElement>;
    function Flaws: TArray<TDocFlaw>;
    property Broken: Boolean read FBroken;
  end;

implementation

uses
  System.StrUtils,
  System.Character,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TXmlDocScannerText = (NotWellFormed, EscapeLt, WriteLt, WriteAmp, EscapeAmp, UndefinedEntity, NotClosedWith,
    AddName, QuoteMissing, Unquoted, AddQuotes, BrNotClosed, WriteBr, TagNotClosed, WriteAsText, AddClosing,
    NoOpening, RemoveClosing);

const
  cTexts: array[TXmlDocScannerText] of TAtlasText = (
    (De: 'Doku-Kommentar ist kein wohlgeformtes XML: '; En: 'Doc comment is not well-formed XML: '),
    (De: '''<'' muss &lt; heißen.'; En: '''<'' must be written &lt;.'),
    (De: '''<'' als &lt; schreiben'; En: 'Write ''<'' as &lt;'),
    (De: '''&'' als &amp; schreiben'; En: 'Write ''&'' as &amp;'),
    (De: '''&'' muss &amp; heißen.'; En: '''&'' must be written &amp;.'),
    (De: '&%s; ist in XML nicht definiert.'; En: '&%s; is not defined in XML.'),
    (De: '%s wird nicht mit %s geschlossen.'; En: '%s is not closed with %s.'),
    (De: '%s ergänzen'; En: 'Add %s'),
    (De: 'Anführungszeichen hinter %s fehlt.'; En: 'Quotation mark after %s is missing.'),
    (De: 'Wert von %s ohne Anführungszeichen.'; En: 'Value of %s without quotation marks.'),
    (De: 'Anführungszeichen setzen'; En: 'Add quotation marks'),
    (De: '<br> wird nicht geschlossen.'; En: '<br> is not closed.'),
    (De: '<br/> schreiben'; En: 'Write <br/>'),
    (De: '<%s> wird nicht geschlossen.'; En: '<%s> is not closed.'),
    (De: '<%s> als Text schreiben'; En: 'Write <%s> as text'),
    (De: '</%s> ergänzen'; En: 'Add </%s>'),
    (De: '</%s> hat kein öffnendes Tag.'; En: '</%s> has no opening tag.'),
    (De: '</%s> entfernen'; En: 'Remove </%s>'));

{$SCOPEDENUMS OFF}

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
  begin
    if SameText(Item.Name, AName) then
    begin
      AAttribute := Item;
      Exit(True);
    end;
  end;
  AAttribute := Default(TDocAttribute);
  Result := False;
end;

class function TDocFlaw.Create(AStart, AStop: Integer; const AMessage, AFixTitle: string;
  const AReplacements: TArray<TDocReplacement>; AStructural: Boolean): TDocFlaw;
begin
  Result.Start := AStart;
  Result.Stop := AStop;
  Result.Message := cTexts[TXmlDocScannerText.NotWellFormed].Text + AMessage;
  Result.Code := '';
  Result.FixTitle := AFixTitle;
  Result.Replacements := AReplacements;
  Result.Structural := AStructural;
end;

/// <summary>Steht an AIndex "/&gt;"?</summary>
function IsEmptyTagEnd(const AXml: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex < Length(AXml)) and (AXml[AIndex] = '/') and (AXml[AIndex + 1] = '>');
end;

/// <summary>Wert [AStart, AStop) des Attributs.</summary>
procedure SetAttributeValue(var AAttribute: TDocAttribute; const AXml: string; AStart, AStop: Integer);
begin
  AAttribute.Value := Copy(AXml, AStart, AStop - AStart);
  AAttribute.ValueStart := AStart;
  AAttribute.ValueStop := AStop;
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

function TDocScanner.SkipSpaces(AIndex: Integer): Integer;
begin
  Result := AIndex;
  while IsSpaceAt(Result) do
  begin
    Inc(Result);
  end;
end;

function TDocScanner.SkipName(AIndex: Integer): Integer;
begin
  Result := AIndex;
  while IsNameCharAt(Result) do
  begin
    Inc(Result);
  end;
end;

function TDocScanner.SkipChars(AIndex: Integer; const AChars: TSysCharSet): Integer;
begin
  Result := AIndex;
  while (Result <= FLength) and CharInSet(FXml[Result], AChars) do
  begin
    Inc(Result);
  end;
end;

procedure TDocScanner.AddFlaw(const AFlaw: TDocFlaw);
begin
  FFlaws.Add(AFlaw);
  if AFlaw.Structural then
  begin
    FBroken := True;
  end;
end;

procedure TDocScanner.EscapeLess(AIndex: Integer; const ACode: string);
var
  mFlaw: TDocFlaw;
begin
  mFlaw := TDocFlaw.Create(AIndex, AIndex + 1, cTexts[TXmlDocScannerText.EscapeLt].Text,
    cTexts[TXmlDocScannerText.WriteLt].Text,
    [TDocReplacement.Create(AIndex, AIndex + 1, '&lt;')], False);
  mFlaw.Code := ACode;
  AddFlaw(mFlaw);
end;

procedure TDocScanner.RejectTag(var AIndex: Integer; const ACode: string);
begin
  EscapeLess(AIndex, ACode);
  Inc(AIndex);
end;

procedure TDocScanner.EscapeAmpersand(AIndex: Integer; const AMessage: string);
begin
  AddFlaw(TDocFlaw.Create(AIndex, AIndex + 1, AMessage, cTexts[TXmlDocScannerText.WriteAmp].Text,
    [TDocReplacement.Create(AIndex, AIndex + 1, '&amp;')], False));
end;

function TDocScanner.CharRefStop(AStart: Integer): Integer;
var
  mIndex: Integer;
begin
  if (AStart <= FLength) and CharInSet(FXml[AStart], ['x', 'X']) then
  begin
    mIndex := SkipChars(AStart + 1, ['0'..'9', 'a'..'f', 'A'..'F']);
  end
  else
  begin
    mIndex := SkipChars(AStart, ['0'..'9']);
  end;
  Result := 0;
  if (mIndex <= FLength) and (FXml[mIndex] = ';') and not CharInSet(FXml[mIndex - 1], ['#', 'x', 'X']) then
  begin
    Result := mIndex + 1;
  end;
end;

function TDocScanner.EntityRefStop(AStart: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  if not IsNameStartAt(AStart) then
  begin
    Exit;
  end;
  mIndex := SkipName(AStart);
  if (mIndex <= FLength) and (FXml[mIndex] = ';') then
  begin
    Result := mIndex + 1;
  end;
end;

procedure TDocScanner.ScanEntity(var AIndex: Integer);
var
  mStop: Integer;
  mNumeric: Boolean;
  mName: string;
begin
  mNumeric := (AIndex < FLength) and (FXml[AIndex + 1] = '#');
  if mNumeric then
  begin
    mStop := CharRefStop(AIndex + 2);
  end
  else
  begin
    mStop := EntityRefStop(AIndex + 1);
  end;
  if mStop = 0 then
  begin
    EscapeAmpersand(AIndex, cTexts[TXmlDocScannerText.EscapeAmp].Text);
    Inc(AIndex);
    Exit;
  end;
  mName := Copy(FXml, AIndex + 1, mStop - AIndex - 2);
  if not mNumeric and (IndexText(mName, XmlEntities) < 0) then
  begin
    EscapeAmpersand(AIndex, cTexts[TXmlDocScannerText.UndefinedEntity].Fmt([mName]));
  end;
  AIndex := mStop;
end;

procedure TDocScanner.Skip(var AIndex: Integer; const AOpen, AClose: string);
var
  Close: Integer;
begin
  Close := PosEx(AClose, FXml, AIndex + Length(AOpen));
  if Close = 0 then
  begin
    AddFlaw(TDocFlaw.Create(AIndex, AIndex + Length(AOpen), cTexts[TXmlDocScannerText.NotClosedWith].Fmt(
      [AOpen, AClose]), cTexts[TXmlDocScannerText.AddName].Fmt([AClose]), [TDocReplacement.Create(FLength + 1, FLength +
        1, AClose)],
      True));
    AIndex := FLength + 1;
  end
  else
  begin
    AIndex := Close + Length(AClose);
  end;
end;

function TDocScanner.TagEndAt(AIndex: Integer; var AElement: TDocElement): Boolean;
begin
  Result := False;
  if AIndex > FLength then
  begin
    Exit;
  end;
  if FXml[AIndex] = '>' then
  begin
    AElement.OpenStop := AIndex + 1;
    Exit(True);
  end;
  if IsEmptyTagEnd(FXml, AIndex) then
  begin
    AElement.OpenStop := AIndex + 2;
    AElement.CloseStart := AElement.OpenStop;
    AElement.Stop := AElement.OpenStop;
    Result := True;
  end;
end;

function TDocScanner.ScanQuotedValue(var AIndex: Integer; var AAttribute: TDocAttribute): TTagOutcome;
var
  mStart, mStop: Integer;
begin
  mStart := AIndex + 1;
  mStop := PosEx(FXml[AIndex], FXml, mStart);
  if mStop = 0 then
  begin
    AddFlaw(TDocFlaw.Create(mStart - 1, mStart, cTexts[TXmlDocScannerText.QuoteMissing].Fmt([AAttribute.Name]), '',
      nil, True));
    Exit(TTagOutcome.Fatal);
  end;
  SetAttributeValue(AAttribute, FXml, mStart, mStop);
  AIndex := mStop + 1;
  Result := TTagOutcome.Pending;
end;

function TDocScanner.ScanBareValue(var AIndex: Integer; var AAttribute: TDocAttribute): TTagOutcome;
var
  mStart: Integer;
begin
  // Wert ohne Anführungszeichen: bis Leerraum oder Tagende.
  mStart := AIndex;
  while (AIndex <= FLength) and not IsSpaceAt(AIndex) and (FXml[AIndex] <> '>') and
    not IsEmptyTagEnd(FXml, AIndex) do
  begin
    Inc(AIndex);
  end;
  if AIndex = mStart then
  begin
    Exit(TTagOutcome.Malformed);
  end;
  AddFlaw(TDocFlaw.Create(mStart, AIndex, cTexts[TXmlDocScannerText.Unquoted].Fmt([AAttribute.Name]),
    cTexts[TXmlDocScannerText.AddQuotes].Text, [TDocReplacement.Create(mStart, mStart, '"'),
      TDocReplacement.Create(AIndex, AIndex,
    '"')], False));
  SetAttributeValue(AAttribute, FXml, mStart, AIndex);
  Result := TTagOutcome.Pending;
end;

function TDocScanner.ScanAttribute(var AIndex: Integer; out AAttribute: TDocAttribute): TTagOutcome;
var
  mStart: Integer;
begin
  AAttribute := Default(TDocAttribute);
  mStart := AIndex;
  AIndex := SkipName(AIndex);
  AAttribute.Name := Copy(FXml, mStart, AIndex - mStart);
  AIndex := SkipSpaces(AIndex);
  if (AIndex > FLength) or (FXml[AIndex] <> '=') then
  begin
    Exit(TTagOutcome.Malformed);
  end;
  AIndex := SkipSpaces(AIndex + 1);
  if (AIndex <= FLength) and CharInSet(FXml[AIndex], ['"', '''']) then
  begin
    Result := ScanQuotedValue(AIndex, AAttribute);
  end
  else
  begin
    Result := ScanBareValue(AIndex, AAttribute);
  end;
end;

function TDocScanner.ScanAttributes(AIndex: Integer; var AElement: TDocElement): TTagOutcome;
var
  mIndex: Integer;
  mHadSpace: Boolean;
  mAttribute: TDocAttribute;
begin
  mIndex := AIndex;
  repeat
    mHadSpace := IsSpaceAt(mIndex);
    mIndex := SkipSpaces(mIndex);
    if TagEndAt(mIndex, AElement) then
    begin
      Result := TTagOutcome.Complete;
    end
    else if not mHadSpace or not IsNameStartAt(mIndex) then
    begin
      Result := TTagOutcome.Malformed;
    end
    else
    begin
      Result := ScanAttribute(mIndex, mAttribute);
      if Result = TTagOutcome.Pending then
      begin
        AElement.Attributes := AElement.Attributes + [mAttribute];
      end;
    end;
  until Result <> TTagOutcome.Pending;
end;

procedure TDocScanner.AddElement(const AElement: TDocElement);
var
  mParent: TDocElement;
begin
  if FStack.Count > 0 then
  begin
    mParent := FElements[FStack.Last];
    mParent.HasChildren := True;
    FElements[FStack.Last] := mParent;
  end;
  FElements.Add(AElement);
  if AElement.Stop = 0 then
  begin
    FStack.Add(FElements.Count - 1);
  end;
end;

procedure TDocScanner.ScanStartTag(var AIndex: Integer);
var
  mNameStop: Integer;
  mElement: TDocElement;
  mOutcome: TTagOutcome;
begin
  if not IsNameStartAt(AIndex + 1) then
  begin
    RejectTag(AIndex, '');
    Exit;
  end;
  mNameStop := SkipName(AIndex + 1);
  if (mNameStop <= FLength) and not IsSpaceAt(mNameStop) and not CharInSet(FXml[mNameStop], ['>', '/']) then
  begin
    // dcc meldet hier W1205 ("'>' erwartet"), nicht W1204 (Cm.W1204).
    RejectTag(AIndex, 'W1205');
    Exit;
  end;
  mElement := Default(TDocElement);
  mElement.Name := Copy(FXml, AIndex + 1, mNameStop - AIndex - 1);
  mElement.Start := AIndex;
  mElement.Depth := FStack.Count;
  mOutcome := ScanAttributes(mNameStop, mElement);
  if mOutcome = TTagOutcome.Malformed then
  begin
    RejectTag(AIndex, '');
  end
  else if mOutcome = TTagOutcome.Fatal then
  begin
    AIndex := FLength + 1;
  end
  else
  begin
    AddElement(mElement);
    AIndex := mElement.OpenStop;
  end;
end;

procedure TDocScanner.Unclosed(AElement, AInsertAt: Integer);
var
  Element: TDocElement;
  Index: Integer;
begin
  Element := FElements[AElement];
  // Ein offener Abschnitt endet vor dem nächsten Abschnitt darin, hinter dem letzten Zeichen davor.
  if IndexText(Element.Name, BlockSections) >= 0 then
  begin
    for Index := FElements.Count - 1 downto AElement + 1 do
    begin
      if IndexText(FElements[Index].Name, BlockSections) >= 0 then
      begin
        AInsertAt := FElements[Index].Start;
      end;
    end;
  end;
  while (AInsertAt > Element.OpenStop) and IsSpaceAt(AInsertAt - 1) do
  begin
    Dec(AInsertAt);
  end;
  if SameText(Element.Name, 'br') then
  begin
    AddFlaw(TDocFlaw.Create(Element.Start, Element.OpenStop, cTexts[TXmlDocScannerText.BrNotClosed].Text,
      cTexts[TXmlDocScannerText.WriteBr].Text,
      [TDocReplacement.Create(Element.OpenStop - 1, Element.OpenStop - 1, '/')], True));
  end
  else if (Length(Element.Attributes) = 0) and not Element.HasChildren and
    ((IndexText(Element.Name, DocTags) < 0) or (IndexText(Element.Name, AttributeTags) >= 0)) then
  begin
    // Fremder Name oder Tag ohne sein Attribut, ohne Inhalt: gemeint ist Text wie TList<T>.
    AddFlaw(TDocFlaw.Create(Element.Start, Element.OpenStop,
      cTexts[TXmlDocScannerText.TagNotClosed].Fmt([Element.Name]),
      cTexts[TXmlDocScannerText.WriteAsText].Fmt([Element.Name]), [TDocReplacement.Create(Element.Start, Element.Start +
        1,
      '&lt;'), TDocReplacement.Create(Element.OpenStop - 1, Element.OpenStop, '&gt;')], True));
  end
  else
  begin
    AddFlaw(TDocFlaw.Create(Element.Start, Element.OpenStop,
      cTexts[TXmlDocScannerText.TagNotClosed].Fmt([Element.Name]),
      cTexts[TXmlDocScannerText.AddClosing].Fmt([Element.Name]), [TDocReplacement.Create(AInsertAt, AInsertAt,
      Format('</%s>', [Element.Name]))], True));
  end;
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
    EscapeLess(AIndex, '');
    Inc(AIndex);
    Exit;
  end;
  while IsNameCharAt(Index) do
  begin
    Inc(Index);
  end;
  Name := Copy(FXml, AIndex + 2, Index - AIndex - 2);
  while IsSpaceAt(Index) do
  begin
    Inc(Index);
  end;
  if (Index > FLength) or (FXml[Index] <> '>') then
  begin
    EscapeLess(AIndex, '');
    Inc(AIndex);
    Exit;
  end;
  Level := FStack.Count - 1;
  while (Level >= 0) and (FElements[FStack[Level]].Name <> Name) do
  begin
    Dec(Level);
  end;
  if Level < 0 then
  begin
    AddFlaw(TDocFlaw.Create(AIndex, Index + 1, cTexts[TXmlDocScannerText.NoOpening].Fmt([Name]),
      cTexts[TXmlDocScannerText.RemoveClosing].Fmt([Name]), [TDocReplacement.Create(AIndex, Index + 1, '')], True));
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

procedure TDocScanner.ScanMarkup(var AIndex: Integer);
begin
  if Copy(FXml, AIndex, 4) = '<!--' then
  begin
    Skip(AIndex, '<!--', '-->');
  end
  else if Copy(FXml, AIndex, 9) = '<![CDATA[' then
  begin
    Skip(AIndex, '<![CDATA[', ']]>');
  end
  else if Copy(FXml, AIndex, 2) = '<?' then
  begin
    Skip(AIndex, '<?', '?>');
  end
  else if Copy(FXml, AIndex, 2) = '</' then
  begin
    ScanEndTag(AIndex);
  end
  else
  begin
    ScanStartTag(AIndex);
  end;
end;

procedure TDocScanner.CloseOpen;
var
  mStop: Integer;
begin
  // Endtag hinter dem letzten Zeichen, das kein Leerraum ist.
  mStop := FLength + 1;
  while (mStop > 1) and IsSpaceAt(mStop - 1) do
  begin
    Dec(mStop);
  end;
  Unclosed(FStack.Last, mStop);
end;

procedure TDocScanner.Scan;
var
  mIndex: Integer;
begin
  mIndex := 1;
  while (mIndex <= FLength) and not FBroken do
  begin
    case FXml[mIndex] of
      '&':
        ScanEntity(mIndex);
      '<':
        ScanMarkup(mIndex);
    else
      Inc(mIndex);
    end;
  end;
  if not FBroken and (FStack.Count > 0) then
  begin
    CloseOpen;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.XmlDoc.Scanner', cTexts);

end.
