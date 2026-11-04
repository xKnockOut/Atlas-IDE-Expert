unit Atlas.Common.Pascal.XmlDoc;

// ///-Dokumentation (XMLDoc) nach Abschnitten zerlegen (#405, #427, #654).
//
// Einziger Parser für XMLDoc: Hover, Parameter-Hint und das Detailpanel der
// Vervollständigung nutzen ihn. Ein Abschnitt (summary, param, typeparam,
// returns, value, exception, remarks, example, seealso) besteht aus
// Teilstücken (TXmlDocRun): Text, Code, Verweis (cref), Link (href),
// Parameterverweis, Schlüsselwort, Zeilenumbruch, Absatz, Codeblock,
// Listenpunkt und Tabellenspalte; Text trägt fett und kursiv als Stil.
//
// Fehlertolerant: Unbekannte Tags behalten ihren inneren Text, nicht
// geschlossene Tags enden am nächsten Abschnitt bzw. am Kommentarende, ein
// "<" ohne Tag bleibt Text. Text geht nie verloren; Text außerhalb von
// Abschnitten zählt zur Zusammenfassung.
//
// Zeilenumbrüche im Kommentar sind Fließtext; Einrückung und Zeilen bleiben
// nur in <code> erhalten. <inheritdoc/> setzt InheritDoc; die Doku des
// Vorfahren löst der Server auf (Atlas.Common.Lsp.Documentation).

interface

uses
  System.SysUtils;

{$SCOPEDENUMS ON}

type
  /// <summary>Art eines Teilstücks. Text, Code, Ref, Link, ParamRef und Keyword tragen Text;
  /// LineBreak, Paragraph und Cell trennen; CodeBlock trägt Zeilen mit #10; Bullet beginnt einen
  /// Listenpunkt (Text "•", "1." bzw. '' bei Tabellenzeilen und Kopfzeilen).</summary>
  TXmlDocRunKind = (Text, Code, Ref, Link, ParamRef, Keyword, LineBreak, Paragraph, CodeBlock, Bullet, Cell);
  TXmlDocStyle = (Bold, Italic);
  TXmlDocStyles = set of TXmlDocStyle;

  TXmlDocRun = record
    Kind: TXmlDocRunKind;
    Text: string;
    /// <summary>Ref: Ziel aus cref ohne Präfix (T:, M: …), Generics als &lt;T&gt;; Link: URL.</summary>
    Target: string;
    Styles: TXmlDocStyles;
    /// <summary>Bullet: Listenebene ab 1.</summary>
    Level: Integer;
    class function Create(AKind: TXmlDocRunKind; const AText: string; AStyles: TXmlDocStyles;
      const ATarget: string; ALevel: Integer): TXmlDocRun; overload; static;
    /// <summary>Wie oben mit ALevel = 0.</summary>
    class function Create(AKind: TXmlDocRunKind; const AText: string; AStyles: TXmlDocStyles;
      const ATarget: string): TXmlDocRun; overload; static;
    /// <summary>Wie oben ohne Ziel (ATarget = '', ALevel = 0).</summary>
    class function Create(AKind: TXmlDocRunKind; const AText: string; AStyles: TXmlDocStyles): TXmlDocRun;
      overload; static;
    /// <summary>Wie oben ohne Auszeichnung (AStyles = [], ATarget = '', ALevel = 0).</summary>
    class function Create(AKind: TXmlDocRunKind; const AText: string): TXmlDocRun; overload; static;
  end;

  TXmlDocRuns = TArray<TXmlDocRun>;

  /// <summary>Abschnitte in der Reihenfolge der Anzeige.</summary>
  TXmlDocSectionKind = (Summary, Param, TypeParam, Returns, Value, Exception, Remarks, Example, SeeAlso);

  TXmlDocSection = record
    Kind: TXmlDocSectionKind;
    /// <summary>Parameter- bzw. Typparametername; bei Exceptions die Klasse (wie Ref.Target).</summary>
    Name: string;
    Runs: TXmlDocRuns;
    /// <summary>Inhalt als Klartext, Absätze und Listenpunkte als eigene Zeilen.</summary>
    function Text: string;
  end;

  TXmlDocEntry = record
    /// <summary>Parametername bzw. Exception-Klasse.</summary>
    Name: string;
    Text: string;
  end;

  TXmlDoc = record
    /// <summary>Abschnitte nach TXmlDocSectionKind sortiert, gleiche Art in Kommentarreihenfolge.</summary>
    Sections: TArray<TXmlDocSection>;
    /// <summary>&lt;inheritdoc/&gt; im Kommentar; InheritCref ist dessen cref (ohne Präfix) oder ''.</summary>
    InheritDoc: Boolean;
    InheritCref: string;
    /// <summary>Klartext der Abschnitte (Kurzform und ältere Aufrufer).</summary>
    Summary: string;
    Returns: string;
    Remarks: string;
    Params: TArray<TXmlDocEntry>;
    Exceptions: TArray<TXmlDocEntry>;
    function IsEmpty: Boolean;
    /// <summary>Index des ersten Abschnitts AKind (bei Name gleich AName); -1 ohne.</summary>
    function IndexOf(AKind: TXmlDocSectionKind; const AName: string): Integer; overload;
    /// <summary>Wie oben ohne Namen (AName = '').</summary>
    function IndexOf(AKind: TXmlDocSectionKind): Integer; overload;
    /// <summary>Ergänzt fehlende Abschnitte aus ABase (inheritdoc): eigene Abschnitte gehen vor,
    /// Parameter und Exceptions je Name.</summary>
    function Inherit(const ABase: TXmlDoc): TXmlDoc;
    /// <summary>Ganzer Kommentar als Klartext; AWithParams = False lässt die Parameter weg (Parameter-Hint).</summary>
    function ToPlainText(AWithParams: Boolean): string; overload;
    /// <summary>Wie oben mit AWithParams = True.</summary>
    function ToPlainText: string; overload;
    /// <summary>Ganzer Kommentar als Markdown (Hover für andere Clients).</summary>
    function ToMarkdown(AWithParams: Boolean): string; overload;
    /// <summary>Wie oben mit AWithParams = True.</summary>
    function ToMarkdown: string; overload;
    /// <summary>Zerlegt den XML-Text eines ///-Kommentars (ohne die ///).</summary>
    class function Parse(const AXml: string): TXmlDoc; static;
    /// <summary>Text der ///-Zeilen direkt über ALine (0-basiert), ohne ///; Attribute ([...])
    /// dazwischen werden übersprungen.</summary>
    class function CommentAbove(const ALines: TArray<string>; ALine: Integer): string; static;
    /// <summary>Innere Tags zu Text, Leerraum zusammengefasst; Absätze bleiben als #10.</summary>
    class function CleanText(const AText: string): string; static;
    /// <summary>cref ohne Präfix "T:", "M:" usw., {T} als &lt;T&gt;.</summary>
    class function NormalizeCref(const ACref: string): string; static;
    class function RunsText(const ARuns: TXmlDocRuns): string; static;
    class function RunsMarkdown(const ARuns: TXmlDocRuns): string; static;
    /// <summary>Name für JSON und Tests (summary, param …).</summary>
    class function SectionName(AKind: TXmlDocSectionKind): string; static;
    class function TryParseSectionName(const AName: string; out AKind: TXmlDocSectionKind): Boolean; static;
    /// <summary>Name für JSON und Tests (text, code, ref …).</summary>
    class function RunKindName(AKind: TXmlDocRunKind): string; static;
    class function TryParseRunKindName(const AName: string; out AKind: TXmlDocRunKind): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Text.Entities;

const
  SectionNames: array[TXmlDocSectionKind] of string = ('summary', 'param', 'typeparam', 'returns', 'value',
    'exception', 'remarks', 'example', 'seealso');
  RunKindNames: array[TXmlDocRunKind] of string = ('text', 'code', 'ref', 'link', 'paramref', 'keyword', 'br',
    'para', 'codeblock', 'bullet', 'cell');
  // Abschnitte, die einander nicht enthalten können: Ein neuer schließt einen offenen.
  BlockSections: array[0..7] of string = ('summary', 'param', 'typeparam', 'returns', 'value', 'exception',
    'remarks', 'example');
  // Teilstücke, nach denen eine neue Zeile beginnt.
  LineStarts = [TXmlDocRunKind.LineBreak, TXmlDocRunKind.Paragraph, TXmlDocRunKind.CodeBlock,
    TXmlDocRunKind.Bullet, TXmlDocRunKind.Cell];
  // Teilstücke, vor denen eine Zeile endet.
  LineEnds = [TXmlDocRunKind.LineBreak, TXmlDocRunKind.Paragraph, TXmlDocRunKind.CodeBlock,
    TXmlDocRunKind.Bullet, TXmlDocRunKind.Cell];

type
  TXmlNode = record
    /// <summary>Tag in Kleinbuchstaben; '' = Textknoten.</summary>
    Name: string;
    Text: string;
    /// <summary>Paare Name, Wert; Namen in Kleinbuchstaben.</summary>
    Attributes: TArray<string>;
    Children: TArray<Integer>;
  end;

  /// <summary>Fehlertoleranter XML-Baum und Umwandlung in Abschnitte.</summary>
  TXmlDocParser = class
  private
    FNodes: TArray<TXmlNode>;
    FCount: Integer;
    FRuns: TXmlDocRuns;
    FSeeAlso: TXmlDocRuns;
    FDoc: TXmlDoc;
    function AddNode(AParent: Integer; const AName, AText: string; const AAttributes: TArray<string>): Integer;
    procedure AddText(AParent: Integer; const AText: string);
    procedure Build(const AXml: string);
    function Attribute(ANode: Integer; const AName: string): string;
    function HasAttribute(ANode: Integer; const AName: string): Boolean;
    function InnerText(ANode: Integer): string;
    function HasSection(ANode: Integer): Boolean;
    procedure Add(const ARun: TXmlDocRun);
    procedure AddInline(const AText: string; AStyles: TXmlDocStyles);
    procedure WalkChildren(ANode: Integer; AStyles: TXmlDocStyles; ALevel: Integer);
    procedure WalkNode(ANode: Integer; AStyles: TXmlDocStyles; ALevel: Integer);
    /// <summary>c, code, see, paramref und typeparamref; False bei anderem Tag.</summary>
    function WalkCodeTag(ANode: Integer; const AName: string; AStyles: TXmlDocStyles; ALevel: Integer): Boolean;
    /// <summary>para, br, b, strong, i, em, list, seealso und inheritdoc; False bei anderem Tag.</summary>
    function WalkStructureTag(ANode: Integer; const AName: string; AStyles: TXmlDocStyles; ALevel: Integer): Boolean;
    procedure WalkSee(ANode: Integer; AStyles: TXmlDocStyles; ALevel: Integer);
    /// <summary>Verweis mit Ziel ATarget; ohne Text steht das Ziel als Text.</summary>
    procedure AddTargetRun(AKind: TXmlDocRunKind; const AText, ATarget: string; AStyles: TXmlDocStyles);
    procedure WalkList(ANode: Integer; AStyles: TXmlDocStyles; ALevel: Integer);
    /// <summary>Teile eines Listenpunkts (term, description, anderes).</summary>
    procedure WalkItem(AItem: Integer; AStyles: TXmlDocStyles; ALevel: Integer; ATable: Boolean);
    procedure AddSeeAlso(ANode: Integer);
    procedure MarkInherit(ANode: Integer);
    procedure AddSection(AKind: TXmlDocSectionKind; const AName: string; const ARuns: TXmlDocRuns);
    procedure Top(ANode: Integer; var ALoose: TXmlDocRuns);
  public
    function Parse(const AXml: string): TXmlDoc;
  end;

function IsSpace(AChar: Char): Boolean;
begin
  Result := (AChar = ' ') or (AChar = #9) or (AChar = #10) or (AChar = #13);
end;

function IsNameChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_', ':', '.', '-']);
end;

/// <summary>Leerraum (auch Zeilenumbrüche) zu einem Leerzeichen.</summary>
function CollapseSpaces(const AText: string): string;
var
  Index: Integer;
  Space: Boolean;
begin
  Result := '';
  Space := False;
  for Index := 1 to Length(AText) do
  begin
    if IsSpace(AText[Index]) then
    begin
      Space := True;
    end
    else
    begin
      if Space then
      begin
        Result := Result + ' ';
      end;
      Space := False;
      Result := Result + AText[Index];
    end;
  end;
  if Space then
  begin
    Result := Result + ' ';
  end;
end;

function LeadingSpaces(const ALine: string): Integer;
begin
  Result := 0;
  while (Result < Length(ALine)) and ((ALine[Result + 1] = ' ') or (ALine[Result + 1] = #9)) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Gemeinsame Einrückung der nicht leeren Zeilen AFirst bis ALast; steht Code direkt hinter
/// &lt;code&gt;, zählt die erste Zeile nicht mit.</summary>
function CommonIndent(const ALines: TArray<string>; AFirst, ALast: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := MaxInt;
  for mIndex := AFirst to ALast do
  begin
    if (Trim(ALines[mIndex]) <> '') and not ((mIndex = 0) and (ALast > AFirst)) then
    begin
      Result := Min(Result, LeadingSpaces(ALines[mIndex]));
    end;
  end;
  if Result = MaxInt then
  begin
    Result := 0;
  end;
end;

/// <summary>Inhalt von &lt;code&gt;: Leerzeilen am Rand weg, gemeinsame Einrückung weg.</summary>
function Dedent(const AText: string): string;
var
  Lines: TArray<string>;
  First, Last, Index, Indent: Integer;
begin
  Lines := StringReplace(AText, #13, '', [rfReplaceAll]).Split([#10]);
  First := 0;
  Last := High(Lines);
  while (First <= Last) and (Trim(Lines[First]) = '') do
  begin
    Inc(First);
  end;
  while (Last >= First) and (Trim(Lines[Last]) = '') do
  begin
    Dec(Last);
  end;
  Indent := CommonIndent(Lines, First, Last);
  Result := '';
  for Index := First to Last do
  begin
    if Index > First then
    begin
      Result := Result + #10;
    end;
    if (Index = 0) and (Last > First) then
    begin
      Result := Result + TrimRight(TrimLeft(Lines[Index]));
    end
    else
    begin
      Result := Result + TrimRight(Copy(Lines[Index], Min(Indent, LeadingSpaces(Lines[Index])) + 1, MaxInt));
    end;
  end;
end;

function IsBlockSection(const AName: string): Boolean;
begin
  Result := IndexStr(AName, BlockSections) >= 0;
end;

/// <summary>Benachbarte Texte gleichen Stils zusammengefasst.</summary>
function MergeRuns(const ARuns: TXmlDocRuns): TXmlDocRuns;
var
  mRun: TXmlDocRun;
  mCount: Integer;
begin
  Result := nil;
  for mRun in ARuns do
  begin
    mCount := Length(Result);
    if (mRun.Kind = TXmlDocRunKind.Text) and (mCount > 0) and (Result[mCount - 1].Kind = TXmlDocRunKind.Text) and
      (Result[mCount - 1].Styles = mRun.Styles) then
    begin
      Result[mCount - 1].Text := Result[mCount - 1].Text + mRun.Text;
    end
    else
    begin
      Result := Result + [mRun];
    end;
  end;
end;

/// <summary>Endet ARuns mit einem Text, der auf ein Leerzeichen endet?</summary>
function EndsWithSpace(const ARuns: TXmlDocRuns): Boolean;
begin
  Result := (Length(ARuns) > 0) and (ARuns[High(ARuns)].Kind = TXmlDocRunKind.Text) and
    EndsStr(' ', ARuns[High(ARuns)].Text);
end;

/// <summary>Text des Runs AIndex mit zusammengefasstem Leerraum, am Zeilenanfang bzw. hinter einem
/// Leerzeichen links und vor einem Zeilenwechsel rechts gekürzt.</summary>
function TrimmedText(const AMerged: TXmlDocRuns; AIndex: Integer; AAtLineStart: Boolean;
  const AResult: TXmlDocRuns): string;
begin
  Result := CollapseSpaces(AMerged[AIndex].Text);
  if AAtLineStart or EndsWithSpace(AResult) then
  begin
    Result := TrimLeft(Result);
  end;
  if (AIndex = High(AMerged)) or (AMerged[AIndex + 1].Kind in LineEnds) then
  begin
    Result := TrimRight(Result);
  end;
end;

/// <summary>Bleibt der Umbruch ARun? Keine Umbrüche am Anfang, keine doppelten; ein Absatz macht einen
/// vorigen Umbruch zum Absatz.</summary>
function KeepBreak(const ARun: TXmlDocRun; var AResult: TXmlDocRuns): Boolean;
begin
  if Length(AResult) = 0 then
  begin
    Exit(False);
  end;
  Result := not (AResult[High(AResult)].Kind in [TXmlDocRunKind.LineBreak, TXmlDocRunKind.Paragraph]);
  if not Result and (ARun.Kind = TXmlDocRunKind.Paragraph) then
  begin
    AResult[High(AResult)].Kind := TXmlDocRunKind.Paragraph;
  end;
end;

/// <summary>Kürzt den letzten Text rechts und entfernt ihn, wenn er dann leer ist.</summary>
procedure TrimLastText(var ARuns: TXmlDocRuns);
begin
  if (Length(ARuns) = 0) or (ARuns[High(ARuns)].Kind <> TXmlDocRunKind.Text) then
  begin
    Exit;
  end;
  ARuns[High(ARuns)].Text := TrimRight(ARuns[High(ARuns)].Text);
  if ARuns[High(ARuns)].Text = '' then
  begin
    SetLength(ARuns, Length(ARuns) - 1);
  end;
end;

/// <summary>Fasst Text zusammen und kürzt Leerraum an Zeilenanfang und -ende.</summary>
function Normalize(const ARuns: TXmlDocRuns): TXmlDocRuns;
var
  Merged: TXmlDocRuns;
  Run: TXmlDocRun;
  Index: Integer;
  AtLineStart, Keep: Boolean;
begin
  Merged := MergeRuns(ARuns);
  Result := nil;
  AtLineStart := True;
  for Index := 0 to High(Merged) do
  begin
    Run := Merged[Index];
    Keep := True;
    if Run.Kind = TXmlDocRunKind.Text then
    begin
      Run.Text := TrimmedText(Merged, Index, AtLineStart, Result);
      Keep := Run.Text <> '';
    end
    else if Run.Kind in [TXmlDocRunKind.LineBreak, TXmlDocRunKind.Paragraph] then
    begin
      Keep := KeepBreak(Run, Result);
    end;
    if not Keep then
    begin
      Continue;
    end;
    // Leerzeichen am Ende des vorigen Texts vor einem Zeilenwechsel entfernen.
    if Run.Kind in LineEnds then
    begin
      TrimLastText(Result);
    end;
    Result := Result + [Run];
    AtLineStart := Run.Kind in LineStarts;
  end;
  // Umbrüche am Ende weg.
  while (Length(Result) > 0) and (Result[High(Result)].Kind in [TXmlDocRunKind.LineBreak,
    TXmlDocRunKind.Paragraph]) do
  begin
    SetLength(Result, Length(Result) - 1);
  end;
  TrimLastText(Result);
end;

{ TXmlDocRun }

class function TXmlDocRun.Create(AKind: TXmlDocRunKind; const AText: string; AStyles: TXmlDocStyles;
  const ATarget: string): TXmlDocRun;
begin
  Result := Create(AKind, AText, AStyles, ATarget, 0);
end;

class function TXmlDocRun.Create(AKind: TXmlDocRunKind; const AText: string; AStyles: TXmlDocStyles): TXmlDocRun;
begin
  Result := Create(AKind, AText, AStyles, '', 0);
end;

class function TXmlDocRun.Create(AKind: TXmlDocRunKind; const AText: string): TXmlDocRun;
begin
  Result := Create(AKind, AText, [], '', 0);
end;

class function TXmlDocRun.Create(AKind: TXmlDocRunKind; const AText: string; AStyles: TXmlDocStyles;
  const ATarget: string; ALevel: Integer): TXmlDocRun;
begin
  Result.Kind := AKind;
  Result.Text := AText;
  Result.Target := ATarget;
  Result.Styles := AStyles;
  Result.Level := ALevel;
end;

{ TXmlDocSection }

function TXmlDocSection.Text: string;
begin
  Result := TXmlDoc.RunsText(Runs);
end;

{ TXmlDocParser }

function TXmlDocParser.AddNode(AParent: Integer; const AName, AText: string;
  const AAttributes: TArray<string>): Integer;
begin
  if FCount = Length(FNodes) then
  begin
    SetLength(FNodes, FCount * 2 + 8);
  end;
  Result := FCount;
  Inc(FCount);
  FNodes[Result].Name := AName;
  FNodes[Result].Text := AText;
  FNodes[Result].Attributes := AAttributes;
  FNodes[Result].Children := nil;
  if AParent >= 0 then
  begin
    FNodes[AParent].Children := FNodes[AParent].Children + [Result];
  end;
end;

procedure TXmlDocParser.AddText(AParent: Integer; const AText: string);
var
  Last: Integer;
begin
  if AText = '' then
  begin
    Exit;
  end;
  // An einen Textknoten direkt davor anhängen (z. B. "a < b" aus mehreren Stücken).
  if Length(FNodes[AParent].Children) > 0 then
  begin
    Last := FNodes[AParent].Children[High(FNodes[AParent].Children)];
    if FNodes[Last].Name = '' then
    begin
      FNodes[Last].Text := FNodes[Last].Text + AText;
      Exit;
    end;
  end;
  AddNode(AParent, '', AText, nil);
end;

type
  /// <summary>Baut die Knoten von TXmlDocParser aus dem Text: tolerant wie ein Browser, "&lt;" ohne gültiges Tag
  /// bleibt Text, ein Endtag schließt das nächste offene Tag gleichen Namens.</summary>
  TXmlTreeBuilder = class
  private
    FParser: TXmlDocParser;
    FXml: string;
    FLength: Integer;
    FPos: Integer;
    /// <summary>Offene Knoten; unten die Wurzel.</summary>
    FStack: TArray<Integer>;
    function Current: Integer;
    function IsSelfClose(APos: Integer): Boolean;
    procedure SkipSpaces(var APos: Integer);
    function ReadName(var APos: Integer): string;
    /// <summary>Wert hinter "="; False bei einem nicht geschlossenen Anführungszeichen.</summary>
    function ReadValue(var APos: Integer; out AValue: string): Boolean;
    /// <summary>Ein Attribut ab APos; False, wenn dort keins steht oder es ungültig ist.</summary>
    function ReadAttribute(var APos: Integer; var AAttributes: TArray<string>): Boolean;
    /// <summary>Attribute bis "&gt;" bzw. "/&gt;"; False ohne gültiges Ende.</summary>
    function ReadTagEnd(var APos: Integer; out ASelfClosing: Boolean; var AAttributes: TArray<string>): Boolean;
    procedure ReadText;
    procedure SkipComment;
    procedure ReadCData;
    procedure ReadEndTag;
    procedure ReadStartTag;
    /// <summary>"&lt;" ohne gültiges Tag (z. B. "a &lt; b"): bleibt Text.</summary>
    procedure KeepLessThan;
    /// <summary>Schließt das nächste offene Tag AName samt allem darin.</summary>
    procedure CloseTo(const AName: string);
    /// <summary>Ein neuer Abschnitt schließt einen offenen (nicht geschlossenes &lt;summary&gt;).</summary>
    procedure CloseOpenSection;
  public
    constructor Create(AParser: TXmlDocParser; const AXml: string);
    procedure Run;
  end;

constructor TXmlTreeBuilder.Create(AParser: TXmlDocParser; const AXml: string);
begin
  inherited Create;
  FParser := AParser;
  FXml := AXml;
  FLength := Length(AXml);
  FPos := 1;
  FStack := [0];
end;

function TXmlTreeBuilder.Current: Integer;
begin
  Result := FStack[High(FStack)];
end;

function TXmlTreeBuilder.IsSelfClose(APos: Integer): Boolean;
begin
  Result := (FXml[APos] = '/') and (APos < FLength) and (FXml[APos + 1] = '>');
end;

procedure TXmlTreeBuilder.SkipSpaces(var APos: Integer);
begin
  while (APos <= FLength) and IsSpace(FXml[APos]) do
  begin
    Inc(APos);
  end;
end;

function TXmlTreeBuilder.ReadName(var APos: Integer): string;
begin
  Result := '';
  while (APos <= FLength) and IsNameChar(FXml[APos]) do
  begin
    Result := Result + FXml[APos];
    Inc(APos);
  end;
end;

function TXmlTreeBuilder.ReadValue(var APos: Integer; out AValue: string): Boolean;
var
  mClose: Integer;
begin
  AValue := '';
  Result := True;
  if (APos <= FLength) and ((FXml[APos] = '"') or (FXml[APos] = '''')) then
  begin
    mClose := PosEx(FXml[APos], FXml, APos + 1);
    Result := mClose > 0;
    if Result then
    begin
      AValue := Copy(FXml, APos + 1, mClose - APos - 1);
      APos := mClose + 1;
    end;
    Exit;
  end;
  while (APos <= FLength) and not IsSpace(FXml[APos]) and (FXml[APos] <> '>') and not IsSelfClose(APos) do
  begin
    AValue := AValue + FXml[APos];
    Inc(APos);
  end;
end;

function TXmlTreeBuilder.ReadAttribute(var APos: Integer; var AAttributes: TArray<string>): Boolean;
var
  mName, mValue: string;
begin
  Result := IsNameChar(FXml[APos]);
  if not Result then
  begin
    Exit;
  end;
  mName := ReadName(APos);
  SkipSpaces(APos);
  mValue := '';
  if (APos <= FLength) and (FXml[APos] = '=') then
  begin
    Inc(APos);
    SkipSpaces(APos);
    Result := ReadValue(APos, mValue);
  end;
  if Result then
  begin
    AAttributes := AAttributes + [LowerCase(mName), TTextEntities.Decode(mValue)];
  end;
end;

function TXmlTreeBuilder.ReadTagEnd(var APos: Integer; out ASelfClosing: Boolean;
  var AAttributes: TArray<string>): Boolean;
begin
  ASelfClosing := False;
  Result := False;
  while APos <= FLength do
  begin
    SkipSpaces(APos);
    if APos > FLength then
    begin
      Break;
    end;
    if FXml[APos] = '>' then
    begin
      Inc(APos);
      Exit(True);
    end;
    if IsSelfClose(APos) then
    begin
      ASelfClosing := True;
      Inc(APos, 2);
      Exit(True);
    end;
    if not ReadAttribute(APos, AAttributes) then
    begin
      Break;
    end;
  end;
end;

procedure TXmlTreeBuilder.ReadText;
var
  mClose: Integer;
begin
  mClose := PosEx('<', FXml, FPos);
  if mClose = 0 then
  begin
    mClose := FLength + 1;
  end;
  FParser.AddText(Current, TTextEntities.Decode(Copy(FXml, FPos, mClose - FPos)));
  FPos := mClose;
end;

procedure TXmlTreeBuilder.SkipComment;
var
  mClose: Integer;
begin
  mClose := PosEx('-->', FXml, FPos + 4);
  if mClose = 0 then
  begin
    FPos := FLength + 1;
  end
  else
  begin
    FPos := mClose + 3;
  end;
end;

procedure TXmlTreeBuilder.ReadCData;
var
  mClose: Integer;
begin
  // CDATA: Text ohne Entitäten
  mClose := PosEx(']]>', FXml, FPos + 9);
  if mClose = 0 then
  begin
    mClose := FLength + 1;
  end;
  FParser.AddText(Current, Copy(FXml, FPos + 9, mClose - FPos - 9));
  FPos := mClose + 3;
end;

procedure TXmlTreeBuilder.KeepLessThan;
begin
  FParser.AddText(Current, '<');
  Inc(FPos);
end;

procedure TXmlTreeBuilder.CloseTo(const AName: string);
var
  mLevel: Integer;
begin
  for mLevel := High(FStack) downto 1 do
  begin
    if FParser.FNodes[FStack[mLevel]].Name = AName then
    begin
      SetLength(FStack, mLevel);
      Break;
    end;
  end;
end;

procedure TXmlTreeBuilder.CloseOpenSection;
var
  mLevel: Integer;
begin
  for mLevel := 1 to High(FStack) do
  begin
    if IsBlockSection(FParser.FNodes[FStack[mLevel]].Name) then
    begin
      SetLength(FStack, mLevel);
      Break;
    end;
  end;
end;

procedure TXmlTreeBuilder.ReadEndTag;
var
  mClose, mStart: Integer;
  mName: string;
begin
  mClose := PosEx('>', FXml, FPos);
  mStart := FPos + 2;
  mName := ReadName(mStart);
  if (mClose = 0) or (mName = '') then
  begin
    KeepLessThan;
    Exit;
  end;
  CloseTo(LowerCase(mName));
  FPos := mClose + 1;
end;

procedure TXmlTreeBuilder.ReadStartTag;
var
  mStart, mNode: Integer;
  mName: string;
  mAttributes: TArray<string>;
  mSelfClosing, mValid: Boolean;
begin
  mValid := (FPos < FLength) and CharInSet(FXml[FPos + 1], ['A'..'Z', 'a'..'z', '_']);
  mStart := FPos + 1;
  mName := '';
  mAttributes := nil;
  mSelfClosing := False;
  if mValid then
  begin
    mName := LowerCase(ReadName(mStart));
    mValid := ReadTagEnd(mStart, mSelfClosing, mAttributes);
  end;
  if not mValid then
  begin
    KeepLessThan;
    Exit;
  end;
  if IsBlockSection(mName) then
  begin
    CloseOpenSection;
  end;
  mNode := FParser.AddNode(Current, mName, '', mAttributes);
  if not mSelfClosing and (mName <> 'br') then
  begin
    FStack := FStack + [mNode];
  end;
  FPos := mStart;
end;

procedure TXmlTreeBuilder.Run;
begin
  while FPos <= FLength do
  begin
    if FXml[FPos] <> '<' then
    begin
      ReadText;
    end
    else if Copy(FXml, FPos, 4) = '<!--' then
    begin
      SkipComment;
    end
    else if Copy(FXml, FPos, 9) = '<![CDATA[' then
    begin
      ReadCData;
    end
    else if (FPos < FLength) and (FXml[FPos + 1] = '/') then
    begin
      // Endtag: schließt das nächste offene Tag gleichen Namens samt allem darin; sonst übergangen.
      ReadEndTag;
    end
    else
    begin
      ReadStartTag;
    end;
  end;
end;

procedure TXmlDocParser.Build(const AXml: string);
var
  mBuilder: TXmlTreeBuilder;
begin
  FCount := 0;
  FNodes := nil;
  AddNode(-1, '#root', '', nil);
  mBuilder := TXmlTreeBuilder.Create(Self, AXml);
  try
    mBuilder.Run;
  finally
    mBuilder.Free;
  end;
end;

function TXmlDocParser.Attribute(ANode: Integer; const AName: string): string;
var
  Index: Integer;
begin
  Index := 0;
  while Index < High(FNodes[ANode].Attributes) do
  begin
    if FNodes[ANode].Attributes[Index] = AName then
    begin
      Exit(FNodes[ANode].Attributes[Index + 1]);
    end;
    Inc(Index, 2);
  end;
  Result := '';
end;

function TXmlDocParser.HasAttribute(ANode: Integer; const AName: string): Boolean;
var
  Index: Integer;
begin
  Index := 0;
  while Index < High(FNodes[ANode].Attributes) do
  begin
    if FNodes[ANode].Attributes[Index] = AName then
    begin
      Exit(True);
    end;
    Inc(Index, 2);
  end;
  Result := False;
end;

function TXmlDocParser.InnerText(ANode: Integer): string;
var
  Child: Integer;
begin
  if FNodes[ANode].Name = '' then
  begin
    Exit(FNodes[ANode].Text);
  end;
  if FNodes[ANode].Name = 'br' then
  begin
    Exit(#10);
  end;
  Result := '';
  for Child in FNodes[ANode].Children do
  begin
    Result := Result + InnerText(Child);
  end;
end;

function TXmlDocParser.HasSection(ANode: Integer): Boolean;
var
  Child: Integer;
begin
  for Child in FNodes[ANode].Children do
  begin
    if IsBlockSection(FNodes[Child].Name) or HasSection(Child) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TXmlDocParser.Add(const ARun: TXmlDocRun);
begin
  FRuns := FRuns + [ARun];
end;

procedure TXmlDocParser.AddInline(const AText: string; AStyles: TXmlDocStyles);
begin
  if AText <> '' then
  begin
    Add(TXmlDocRun.Create(TXmlDocRunKind.Text, AText, AStyles));
  end;
end;

procedure TXmlDocParser.WalkChildren(ANode: Integer; AStyles: TXmlDocStyles; ALevel: Integer);
var
  Child: Integer;
begin
  for Child in FNodes[ANode].Children do
  begin
    WalkNode(Child, AStyles, ALevel);
  end;
end;

procedure TXmlDocParser.AddTargetRun(AKind: TXmlDocRunKind; const AText, ATarget: string; AStyles: TXmlDocStyles);
var
  mText: string;
begin
  mText := AText;
  if mText = '' then
  begin
    mText := ATarget;
  end;
  Add(TXmlDocRun.Create(AKind, mText, AStyles, ATarget));
end;

procedure TXmlDocParser.WalkSee(ANode: Integer; AStyles: TXmlDocStyles; ALevel: Integer);
var
  mText: string;
begin
  mText := Trim(CollapseSpaces(InnerText(ANode)));
  if HasAttribute(ANode, 'cref') then
  begin
    AddTargetRun(TXmlDocRunKind.Ref, mText, TXmlDoc.NormalizeCref(Attribute(ANode, 'cref')), AStyles);
  end
  else if HasAttribute(ANode, 'href') then
  begin
    AddTargetRun(TXmlDocRunKind.Link, mText, Trim(Attribute(ANode, 'href')), AStyles);
  end
  else if HasAttribute(ANode, 'langword') then
  begin
    Add(TXmlDocRun.Create(TXmlDocRunKind.Keyword, Trim(Attribute(ANode, 'langword')), AStyles));
  end
  else
  begin
    WalkChildren(ANode, AStyles, ALevel);
  end;
end;

function TXmlDocParser.WalkCodeTag(ANode: Integer; const AName: string; AStyles: TXmlDocStyles;
  ALevel: Integer): Boolean;
var
  mText: string;
begin
  Result := True;
  if AName = 'c' then
  begin
    mText := Trim(CollapseSpaces(InnerText(ANode)));
    if mText <> '' then
    begin
      Add(TXmlDocRun.Create(TXmlDocRunKind.Code, mText, AStyles));
    end;
  end
  else if AName = 'code' then
  begin
    mText := Dedent(InnerText(ANode));
    if mText <> '' then
    begin
      Add(TXmlDocRun.Create(TXmlDocRunKind.CodeBlock, mText));
    end;
  end
  else if AName = 'see' then
  begin
    WalkSee(ANode, AStyles, ALevel);
  end
  else if (AName = 'paramref') or (AName = 'typeparamref') then
  begin
    mText := Trim(Attribute(ANode, 'name'));
    if mText <> '' then
    begin
      Add(TXmlDocRun.Create(TXmlDocRunKind.ParamRef, mText, AStyles));
    end;
    WalkChildren(ANode, AStyles, ALevel);
  end
  else
  begin
    Result := False;
  end;
end;

function TXmlDocParser.WalkStructureTag(ANode: Integer; const AName: string; AStyles: TXmlDocStyles;
  ALevel: Integer): Boolean;
begin
  Result := True;
  if AName = 'para' then
  begin
    Add(TXmlDocRun.Create(TXmlDocRunKind.Paragraph, ''));
    WalkChildren(ANode, AStyles, ALevel);
    Add(TXmlDocRun.Create(TXmlDocRunKind.Paragraph, ''));
  end
  else if AName = 'br' then
  begin
    Add(TXmlDocRun.Create(TXmlDocRunKind.LineBreak, ''));
  end
  else if (AName = 'b') or (AName = 'strong') then
  begin
    WalkChildren(ANode, AStyles + [TXmlDocStyle.Bold], ALevel);
  end
  else if (AName = 'i') or (AName = 'em') then
  begin
    WalkChildren(ANode, AStyles + [TXmlDocStyle.Italic], ALevel);
  end
  else if AName = 'list' then
  begin
    WalkList(ANode, AStyles, ALevel + 1);
  end
  else if AName = 'seealso' then
  begin
    AddSeeAlso(ANode);
  end
  else if AName = 'inheritdoc' then
  begin
    MarkInherit(ANode);
    WalkChildren(ANode, AStyles, ALevel);
  end
  else
  begin
    Result := False;
  end;
end;

procedure TXmlDocParser.WalkNode(ANode: Integer; AStyles: TXmlDocStyles; ALevel: Integer);
var
  Name: string;
begin
  Name := FNodes[ANode].Name;
  if Name = '' then
  begin
    AddInline(FNodes[ANode].Text, AStyles);
  end
  else if not WalkCodeTag(ANode, Name, AStyles, ALevel) and not WalkStructureTag(ANode, Name, AStyles, ALevel) then
  begin
    // Unbekannte Tags (und Abschnitte an falscher Stelle) behalten ihren Text.
    WalkChildren(ANode, AStyles, ALevel);
  end;
end;

/// <summary>Aufzählungszeichen eines Listenpunkts: '' bei Kopf- und Tabellenzeilen, "1." … bei
/// type="number", sonst "•".</summary>
function BulletText(AHeader, ATable: Boolean; const AKind: string; var ANumber: Integer): string;
begin
  if AHeader or ATable then
  begin
    Result := '';
  end
  else if AKind = 'number' then
  begin
    Inc(ANumber);
    Result := IntToStr(ANumber) + '.';
  end
  else
  begin
    Result := '•';
  end;
end;

procedure TXmlDocParser.WalkItem(AItem: Integer; AStyles: TXmlDocStyles; ALevel: Integer; ATable: Boolean);
var
  mPart: Integer;
  mHasTerm, mHasDescription: Boolean;
begin
  mHasTerm := False;
  mHasDescription := False;
  for mPart in FNodes[AItem].Children do
  begin
    if FNodes[mPart].Name = 'term' then
    begin
      mHasTerm := True;
      if ATable then
      begin
        WalkChildren(mPart, AStyles, ALevel);
      end
      else
      begin
        WalkChildren(mPart, AStyles + [TXmlDocStyle.Bold], ALevel);
      end;
    end
    else if FNodes[mPart].Name = 'description' then
    begin
      if ATable then
      begin
        Add(TXmlDocRun.Create(TXmlDocRunKind.Cell, ''));
      end
      else if mHasTerm and not mHasDescription then
      begin
        AddInline(' – ', AStyles);
      end;
      mHasDescription := True;
      WalkChildren(mPart, AStyles, ALevel);
    end
    else
    begin
      WalkNode(mPart, AStyles, ALevel);
    end;
  end;
end;

procedure TXmlDocParser.WalkList(ANode: Integer; AStyles: TXmlDocStyles; ALevel: Integer);
var
  Kind, Name: string;
  Child, Number: Integer;
  Table, Header: Boolean;
  Styles: TXmlDocStyles;
begin
  Kind := LowerCase(Trim(Attribute(ANode, 'type')));
  Table := Kind = 'table';
  Number := 0;
  for Child in FNodes[ANode].Children do
  begin
    Name := FNodes[Child].Name;
    if (Name <> 'item') and (Name <> 'listheader') then
    begin
      WalkNode(Child, AStyles, ALevel - 1);
      Continue;
    end;
    Header := Name = 'listheader';
    Styles := AStyles;
    if Header then
    begin
      Styles := Styles + [TXmlDocStyle.Bold];
    end;
    Add(TXmlDocRun.Create(TXmlDocRunKind.Bullet, BulletText(Header, Table, Kind, Number), Styles, '', ALevel));
    WalkItem(Child, Styles, ALevel, Table);
  end;
  // Nach der Liste beginnt der Text in einer neuen Zeile.
  Add(TXmlDocRun.Create(TXmlDocRunKind.Paragraph, ''));
end;

procedure TXmlDocParser.AddSeeAlso(ANode: Integer);
var
  Saved: TXmlDocRuns;
  Text, Target: string;
begin
  Text := Trim(CollapseSpaces(InnerText(ANode)));
  Saved := FRuns;
  FRuns := nil;
  if HasAttribute(ANode, 'cref') then
  begin
    Target := TXmlDoc.NormalizeCref(Attribute(ANode, 'cref'));
    if Text = '' then
    begin
      Text := Target;
    end;
    Add(TXmlDocRun.Create(TXmlDocRunKind.Ref, Text, [], Target));
  end
  else if HasAttribute(ANode, 'href') then
  begin
    Target := Trim(Attribute(ANode, 'href'));
    if Text = '' then
    begin
      Text := Target;
    end;
    Add(TXmlDocRun.Create(TXmlDocRunKind.Link, Text, [], Target));
  end
  else
  begin
    AddInline(Text, []);
  end;
  if Length(FRuns) > 0 then
  begin
    if Length(FSeeAlso) > 0 then
    begin
      FSeeAlso := FSeeAlso + [TXmlDocRun.Create(TXmlDocRunKind.Text, ', ')];
    end;
    FSeeAlso := FSeeAlso + FRuns;
  end;
  FRuns := Saved;
end;

procedure TXmlDocParser.MarkInherit(ANode: Integer);
begin
  FDoc.InheritDoc := True;
  if HasAttribute(ANode, 'cref') then
  begin
    FDoc.InheritCref := TXmlDoc.NormalizeCref(Attribute(ANode, 'cref'));
  end;
end;

procedure TXmlDocParser.AddSection(AKind: TXmlDocSectionKind; const AName: string; const ARuns: TXmlDocRuns);
var
  Index: Integer;
  Section: TXmlDocSection;
begin
  // Mehrfache Abschnitte ohne Namen (zwei <summary>) werden ein Abschnitt mit Absatz dazwischen.
  if not (AKind in [TXmlDocSectionKind.Param, TXmlDocSectionKind.TypeParam, TXmlDocSectionKind.Exception]) then
  begin
    Index := FDoc.IndexOf(AKind);
    if Index >= 0 then
    begin
      if Length(ARuns) > 0 then
      begin
        FDoc.Sections[Index].Runs := Normalize(FDoc.Sections[Index].Runs +
          [TXmlDocRun.Create(TXmlDocRunKind.Paragraph, '')] + ARuns);
      end;
      Exit;
    end;
    if Length(ARuns) = 0 then
    begin
      Exit;
    end;
  end;
  Section.Kind := AKind;
  Section.Name := AName;
  Section.Runs := ARuns;
  FDoc.Sections := FDoc.Sections + [Section];
end;

procedure TXmlDocParser.Top(ANode: Integer; var ALoose: TXmlDocRuns);
var
  Child: Integer;
  Name, SectionName: string;
  Kind: TXmlDocSectionKind;
begin
  for Child in FNodes[ANode].Children do
  begin
    Name := FNodes[Child].Name;
    if IsBlockSection(Name) and TXmlDoc.TryParseSectionName(Name, Kind) then
    begin
      FRuns := nil;
      WalkChildren(Child, [], 0);
      if Kind = TXmlDocSectionKind.Exception then
      begin
        SectionName := TXmlDoc.NormalizeCref(Attribute(Child, 'cref'));
      end
      else
      begin
        SectionName := Trim(Attribute(Child, 'name'));
      end;
      AddSection(Kind, SectionName, Normalize(FRuns));
    end
    else if (Name <> '') and (Name <> 'list') and HasSection(Child) then
    begin
      // Hülle um Abschnitte (z. B. <member>): wie oberste Ebene.
      Top(Child, ALoose);
    end
    else
    begin
      FRuns := ALoose;
      WalkNode(Child, [], 0);
      ALoose := FRuns;
    end;
  end;
end;

function TXmlDocParser.Parse(const AXml: string): TXmlDoc;
var
  Loose: TXmlDocRuns;
  Index: Integer;
  Section: TXmlDocSection;
  Sorted: TArray<TXmlDocSection>;
  Kind: TXmlDocSectionKind;
begin
  FDoc := Default(TXmlDoc);
  FSeeAlso := nil;
  Build(AXml);
  Loose := nil;
  Top(0, Loose);
  // Text außerhalb von Abschnitten gehört zur Zusammenfassung.
  Loose := Normalize(Loose);
  if Length(Loose) > 0 then
  begin
    Index := FDoc.IndexOf(TXmlDocSectionKind.Summary);
    if Index >= 0 then
    begin
      FDoc.Sections[Index].Runs := Normalize(FDoc.Sections[Index].Runs +
        [TXmlDocRun.Create(TXmlDocRunKind.Paragraph, '')] + Loose);
    end
    else
    begin
      AddSection(TXmlDocSectionKind.Summary, '', Loose);
    end;
  end;
  if Length(FSeeAlso) > 0 then
  begin
    AddSection(TXmlDocSectionKind.SeeAlso, '', FSeeAlso);
  end;
  // Nach Art sortieren, gleiche Art in Kommentarreihenfolge.
  Sorted := nil;
  for Kind := Low(TXmlDocSectionKind) to High(TXmlDocSectionKind) do
  begin
    for Section in FDoc.Sections do
    begin
      if Section.Kind = Kind then
      begin
        Sorted := Sorted + [Section];
      end;
    end;
  end;
  FDoc.Sections := Sorted;
  Result := FDoc;
end;

{ TXmlDoc }

procedure FillPlainFields(var ADoc: TXmlDoc);
var
  Section: TXmlDocSection;
  Entry: TXmlDocEntry;
begin
  ADoc.Summary := '';
  ADoc.Returns := '';
  ADoc.Remarks := '';
  ADoc.Params := nil;
  ADoc.Exceptions := nil;
  for Section in ADoc.Sections do
    case Section.Kind of
      TXmlDocSectionKind.Summary:
        ADoc.Summary := Section.Text;
      TXmlDocSectionKind.Returns:
        ADoc.Returns := Section.Text;
      TXmlDocSectionKind.Remarks:
        ADoc.Remarks := Section.Text;
      TXmlDocSectionKind.Param, TXmlDocSectionKind.Exception:
        begin
          Entry.Name := Section.Name;
          Entry.Text := Section.Text;
          if Section.Kind = TXmlDocSectionKind.Param then
          begin
            ADoc.Params := ADoc.Params + [Entry];
          end
          else
          begin
            ADoc.Exceptions := ADoc.Exceptions + [Entry];
          end;
        end;
      TXmlDocSectionKind.TypeParam: ;
      TXmlDocSectionKind.Value: ;
      TXmlDocSectionKind.Example: ;
      TXmlDocSectionKind.SeeAlso: ;
    end;
end;

function TXmlDoc.IsEmpty: Boolean;
begin
  Result := Length(Sections) = 0;
end;

function TXmlDoc.IndexOf(AKind: TXmlDocSectionKind): Integer;
begin
  Result := IndexOf(AKind, '');
end;

function TXmlDoc.IndexOf(AKind: TXmlDocSectionKind; const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Sections) do
  begin
    if (Sections[Index].Kind = AKind) and ((AName = '') or SameText(Sections[Index].Name, AName)) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function TXmlDoc.Inherit(const ABase: TXmlDoc): TXmlDoc;
var
  Section: TXmlDocSection;
  Sorted: TArray<TXmlDocSection>;
  Kind: TXmlDocSectionKind;
  Named: Boolean;
begin
  Result := Self;
  for Section in ABase.Sections do
  begin
    Named := Section.Kind in [TXmlDocSectionKind.Param, TXmlDocSectionKind.TypeParam,
      TXmlDocSectionKind.Exception];
    if (Named and (Result.IndexOf(Section.Kind, Section.Name) < 0)) or
      (not Named and (Result.IndexOf(Section.Kind) < 0)) then
    begin
      Result.Sections := Result.Sections + [Section];
    end;
  end;
  Sorted := nil;
  for Kind := Low(TXmlDocSectionKind) to High(TXmlDocSectionKind) do
  begin
    for Section in Result.Sections do
    begin
      if Section.Kind = Kind then
      begin
        Sorted := Sorted + [Section];
      end;
    end;
  end;
  Result.Sections := Sorted;
  Result.InheritDoc := False;
  Result.InheritCref := '';
  FillPlainFields(Result);
end;

class function TXmlDoc.Parse(const AXml: string): TXmlDoc;
var
  Parser: TXmlDocParser;
begin
  Parser := TXmlDocParser.Create;
  try
    Result := Parser.Parse(StringReplace(AXml, #13, '', [rfReplaceAll]));
  finally
    Parser.Free;
  end;
  FillPlainFields(Result);
end;

class function TXmlDoc.CleanText(const AText: string): string;
begin
  Result := Parse(AText).Summary;
end;

class function TXmlDoc.NormalizeCref(const ACref: string): string;
begin
  Result := Trim(ACref);
  // Präfix der .NET-Konvention: T: Typ, M: Methode, P: Property, F: Feld, E: Ereignis …
  if (Length(Result) > 2) and (Result[2] = ':') and CharInSet(Result[1], ['A'..'Z', 'a'..'z']) then
  begin
    Result := Copy(Result, 3, MaxInt);
  end;
  Result := StringReplace(StringReplace(Result, '{', '<', [rfReplaceAll]), '}', '>', [rfReplaceAll]);
end;

class function TXmlDoc.RunsText(const ARuns: TXmlDocRuns): string;
var
  Lines: TArray<string>;
  Buffer: string;
  Run: TXmlDocRun;
  Line: string;

  procedure Flush;
  begin
    if Trim(Buffer) <> '' then
    begin
      Lines := Lines + [TrimRight(Buffer)];
    end;
    Buffer := '';
  end;

begin
  Lines := nil;
  Buffer := '';
  for Run in ARuns do
    case Run.Kind of
      TXmlDocRunKind.Text, TXmlDocRunKind.Code, TXmlDocRunKind.Ref, TXmlDocRunKind.ParamRef,
      TXmlDocRunKind.Keyword:
        Buffer := Buffer + Run.Text;
      TXmlDocRunKind.Link:
        if (Run.Target <> '') and (Run.Target <> Run.Text) then
        begin
          Buffer := Buffer + Run.Text + ' (' + Run.Target + ')';
        end
        else
        begin
          Buffer := Buffer + Run.Text;
        end;
      TXmlDocRunKind.LineBreak, TXmlDocRunKind.Paragraph:
        Flush;
      TXmlDocRunKind.CodeBlock:
        begin
          Flush;
          for Line in Run.Text.Split([#10]) do
          begin
            Lines := Lines + [Line];
          end;
        end;
      TXmlDocRunKind.Bullet:
        begin
          Flush;
          Buffer := StringOfChar(' ', 2 * Max(0, Run.Level - 1));
          if Run.Text <> '' then
          begin
            Buffer := Buffer + Run.Text + ' ';
          end;
        end;
      TXmlDocRunKind.Cell:
        Buffer := Buffer + ' – ';
    end;
  Flush;
  Result := string.Join(#10, Lines);
end;

function Styled(const AText: string; AStyles: TXmlDocStyles): string;
begin
  Result := AText;
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  if TXmlDocStyle.Italic in AStyles then
  begin
    Result := '*' + Result + '*';
  end;
  if TXmlDocStyle.Bold in AStyles then
  begin
    Result := '**' + Result + '**';
  end;
end;

/// <summary>Markdown für einen Listenpunkt; eine Liste beginnt nach einer Leerzeile.</summary>
function BulletMarkdown(const ARun: TXmlDocRun; AInList: Boolean): string;
begin
  Result := #10#10;
  if AInList then
  begin
    Result := #10;
  end;
  Result := Result + StringOfChar(' ', 2 * Max(0, ARun.Level - 1));
  if EndsStr('.', ARun.Text) then
  begin
    Result := Result + ARun.Text + ' ';
  end
  else
  begin
    Result := Result + '- ';
  end;
end;

class function TXmlDoc.RunsMarkdown(const ARuns: TXmlDocRuns): string;
var
  Run: TXmlDocRun;
  InList: Boolean;
begin
  Result := '';
  InList := False;
  for Run in ARuns do
  begin
    case Run.Kind of
      TXmlDocRunKind.Text:
        Result := Result + Styled(Run.Text, Run.Styles);
      TXmlDocRunKind.Code, TXmlDocRunKind.Ref, TXmlDocRunKind.Keyword:
        Result := Result + Styled('`' + Run.Text + '`', Run.Styles);
      TXmlDocRunKind.ParamRef:
        Result := Result + '*' + Run.Text + '*';
      TXmlDocRunKind.Link:
        Result := Result + '[' + Run.Text + '](' + Run.Target + ')';
      TXmlDocRunKind.LineBreak:
        Result := Result + '  '#10;
      TXmlDocRunKind.Paragraph:
        Result := Result + #10#10;
      TXmlDocRunKind.CodeBlock:
        Result := Result + #10#10'```pascal'#10 + Run.Text + #10'```'#10#10;
      TXmlDocRunKind.Bullet:
        Result := Result + BulletMarkdown(Run, InList);
      TXmlDocRunKind.Cell:
        Result := Result + ' – ';
    end;
    if Run.Kind = TXmlDocRunKind.Bullet then
    begin
      InList := True;
    end
    else if Run.Kind in [TXmlDocRunKind.Paragraph, TXmlDocRunKind.CodeBlock] then
    begin
      InList := False;
    end;
  end;
  while Pos(#10#10#10, Result) > 0 do
  begin
    Result := StringReplace(Result, #10#10#10, #10#10, [rfReplaceAll]);
  end;
  Result := Trim(Result);
end;

function JoinBlocks(const ABlocks: TArray<string>): string;
var
  Block: string;
begin
  Result := '';
  for Block in ABlocks do
  begin
    if Block <> '' then
    begin
      if Result <> '' then
      begin
        Result := Result + #10#10;
      end;
      Result := Result + Block;
    end;
  end;
end;

function TXmlDoc.ToPlainText: string;
begin
  Result := ToPlainText(True);
end;

function TXmlDoc.ToPlainText(AWithParams: Boolean): string;
var
  Section: TXmlDocSection;
  Main, ParamLines, TypeLines, Facts, Remark, Example, SeeAlso: string;

  procedure AddLine(var ATarget: string; const ALine: string);
  begin
    if ATarget <> '' then
    begin
      ATarget := ATarget + #10;
    end;
    ATarget := ATarget + ALine;
  end;

begin
  Main := '';
  ParamLines := '';
  TypeLines := '';
  Facts := '';
  Remark := '';
  Example := '';
  SeeAlso := '';
  for Section in Sections do
    case Section.Kind of
      TXmlDocSectionKind.Summary:
        Main := Section.Text;
      TXmlDocSectionKind.Param:
        if AWithParams then
        begin
          AddLine(ParamLines, Section.Name + ': ' + Section.Text);
        end;
      TXmlDocSectionKind.TypeParam:
        begin
          if TypeLines = '' then
          begin
            TypeLines := 'Typparameter:';
          end;
          AddLine(TypeLines, Section.Name + ': ' + Section.Text);
        end;
      TXmlDocSectionKind.Returns:
        AddLine(Facts, '→ ' + Section.Text);
      TXmlDocSectionKind.Value:
        AddLine(Facts, 'Wert: ' + Section.Text);
      TXmlDocSectionKind.Exception:
        AddLine(Facts, '! ' + Section.Name + ': ' + Section.Text);
      TXmlDocSectionKind.Remarks:
        Remark := Section.Text;
      TXmlDocSectionKind.Example:
        Example := 'Beispiel:'#10 + Section.Text;
      TXmlDocSectionKind.SeeAlso:
        SeeAlso := 'Siehe auch: ' + Section.Text;
    end;
  Result := JoinBlocks([Main, ParamLines, TypeLines, Facts, Remark, Example, SeeAlso]);
end;

function TXmlDoc.ToMarkdown: string;
begin
  Result := ToMarkdown(True);
end;

function TXmlDoc.ToMarkdown(AWithParams: Boolean): string;
var
  Section: TXmlDocSection;
  Blocks: TArray<string>;
  TypeHeader: Boolean;
begin
  Blocks := nil;
  TypeHeader := False;
  for Section in Sections do
    case Section.Kind of
      TXmlDocSectionKind.Summary, TXmlDocSectionKind.Remarks:
        Blocks := Blocks + [RunsMarkdown(Section.Runs)];
      TXmlDocSectionKind.Param:
        if AWithParams then
        begin
          Blocks := Blocks + ['*' + Section.Name + '*: ' + RunsMarkdown(Section.Runs)];
        end;
      TXmlDocSectionKind.TypeParam:
        begin
          if not TypeHeader then
          begin
            Blocks := Blocks + ['**Typparameter**'];
          end;
          TypeHeader := True;
          Blocks := Blocks + ['*' + Section.Name + '*: ' + RunsMarkdown(Section.Runs)];
        end;
      TXmlDocSectionKind.Returns:
        Blocks := Blocks + ['→ ' + RunsMarkdown(Section.Runs)];
      TXmlDocSectionKind.Value:
        Blocks := Blocks + ['Wert: ' + RunsMarkdown(Section.Runs)];
      TXmlDocSectionKind.Exception:
        Blocks := Blocks + ['! `' + Section.Name + '`: ' + RunsMarkdown(Section.Runs)];
      TXmlDocSectionKind.Example:
        Blocks := Blocks + ['**Beispiel**', RunsMarkdown(Section.Runs)];
      TXmlDocSectionKind.SeeAlso:
        Blocks := Blocks + ['Siehe auch: ' + RunsMarkdown(Section.Runs)];
    end;
  Result := JoinBlocks(Blocks);
end;

class function TXmlDoc.CommentAbove(const ALines: TArray<string>; ALine: Integer): string;
var
  Index: Integer;
  Line: string;
begin
  Result := '';
  Index := ALine - 1;
  while (Index >= 0) and (Index <= High(ALines)) do
  begin
    Line := Trim(ALines[Index]);
    if StartsStr('///', Line) then
    begin
      // Nur das Kommentarzeichen weg: Einrückung danach zählt in <code>.
      Line := Copy(TrimLeft(ALines[Index]), 4, MaxInt);
      if Result = '' then
      begin
        Result := Line;
      end
      else
      begin
        Result := Line + #10 + Result;
      end;
    end
    else if not StartsStr('[', Line) then
    begin
      Break;
    end;
    Dec(Index);
  end;
end;

class function TXmlDoc.SectionName(AKind: TXmlDocSectionKind): string;
begin
  Result := SectionNames[AKind];
end;

class function TXmlDoc.TryParseSectionName(const AName: string; out AKind: TXmlDocSectionKind): Boolean;
var
  Kind: TXmlDocSectionKind;
begin
  for Kind := Low(TXmlDocSectionKind) to High(TXmlDocSectionKind) do
  begin
    if SameText(SectionNames[Kind], AName) then
    begin
      AKind := Kind;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TXmlDoc.RunKindName(AKind: TXmlDocRunKind): string;
begin
  Result := RunKindNames[AKind];
end;

class function TXmlDoc.TryParseRunKindName(const AName: string; out AKind: TXmlDocRunKind): Boolean;
var
  Kind: TXmlDocRunKind;
begin
  for Kind := Low(TXmlDocRunKind) to High(TXmlDocRunKind) do
  begin
    if SameText(RunKindNames[Kind], AName) then
    begin
      AKind := Kind;
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
