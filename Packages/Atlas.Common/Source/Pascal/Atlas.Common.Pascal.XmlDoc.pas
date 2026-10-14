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
    class function Create(AKind: TXmlDocRunKind; const AText: string; AStyles: TXmlDocStyles = [];
      const ATarget: string = ''; ALevel: Integer = 0): TXmlDocRun; static;
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
    function IndexOf(AKind: TXmlDocSectionKind; const AName: string = ''): Integer;
    /// <summary>Ergänzt fehlende Abschnitte aus ABase (inheritdoc): eigene Abschnitte gehen vor,
    /// Parameter und Exceptions je Name.</summary>
    function Inherit(const ABase: TXmlDoc): TXmlDoc;
    /// <summary>Ganzer Kommentar als Klartext; AWithParams = False lässt die Parameter weg (Parameter-Hint).</summary>
    function ToPlainText(AWithParams: Boolean = True): string;
    /// <summary>Ganzer Kommentar als Markdown (Hover für andere Clients).</summary>
    function ToMarkdown(AWithParams: Boolean = True): string;
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
  System.StrUtils;

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
    procedure WalkList(ANode: Integer; AStyles: TXmlDocStyles; ALevel: Integer);
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
    if IsSpace(AText[Index]) then
      Space := True
    else
    begin
      if Space then
        Result := Result + ' ';
      Space := False;
      Result := Result + AText[Index];
    end;
  if Space then
    Result := Result + ' ';
end;

function CodePointText(ACode: Integer): string;
begin
  if (ACode <= 0) or (ACode > $10FFFF) or ((ACode >= $D800) and (ACode <= $DFFF)) then
    Exit('');
  if ACode <= $FFFF then
    Exit(Char(ACode));
  Dec(ACode, $10000);
  Result := Char($D800 + (ACode shr 10)) + Char($DC00 + (ACode and $3FF));
end;

/// <summary>&amp;lt; &amp;gt; &amp;amp; &amp;quot; &amp;apos; &amp;#NN; &amp;#xNN;; Unbekanntes bleibt stehen.</summary>
function DecodeEntities(const AText: string): string;
var
  Index, Close, Code: Integer;
  Name, Replacement: string;
begin
  if Pos('&', AText) = 0 then
    Exit(AText);
  Result := '';
  Index := 1;
  while Index <= Length(AText) do
  begin
    if AText[Index] = '&' then
    begin
      Close := PosEx(';', AText, Index + 1);
      if (Close > 0) and (Close - Index <= 10) then
      begin
        Name := Copy(AText, Index + 1, Close - Index - 1);
        Replacement := '';
        if Name = 'lt' then
          Replacement := '<'
        else if Name = 'gt' then
          Replacement := '>'
        else if Name = 'amp' then
          Replacement := '&'
        else if Name = 'quot' then
          Replacement := '"'
        else if Name = 'apos' then
          Replacement := ''''
        else if (Length(Name) > 2) and ((Name[2] = 'x') or (Name[2] = 'X')) and (Name[1] = '#') then
        begin
          if TryStrToInt('$' + Copy(Name, 3, MaxInt), Code) then
            Replacement := CodePointText(Code);
        end
        else if (Length(Name) > 1) and (Name[1] = '#') then
        begin
          if TryStrToInt(Copy(Name, 2, MaxInt), Code) then
            Replacement := CodePointText(Code);
        end;
        if Replacement <> '' then
        begin
          Result := Result + Replacement;
          Index := Close + 1;
          Continue;
        end;
      end;
    end;
    Result := Result + AText[Index];
    Inc(Index);
  end;
end;

function LeadingSpaces(const ALine: string): Integer;
begin
  Result := 0;
  while (Result < Length(ALine)) and ((ALine[Result + 1] = ' ') or (ALine[Result + 1] = #9)) do
    Inc(Result);
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
    Inc(First);
  while (Last >= First) and (Trim(Lines[Last]) = '') do
    Dec(Last);
  if First > Last then
    Exit('');
  // Steht Code direkt hinter <code>, zählt die erste Zeile nicht zur Einrückung.
  Indent := MaxInt;
  for Index := First to Last do
    if (Trim(Lines[Index]) <> '') and not ((Index = 0) and (Last > First)) then
      Indent := Min(Indent, LeadingSpaces(Lines[Index]));
  if Indent = MaxInt then
    Indent := 0;
  Result := '';
  for Index := First to Last do
  begin
    if Index > First then
      Result := Result + #10;
    if (Index = 0) and (Last > First) then
      Result := Result + TrimRight(TrimLeft(Lines[Index]))
    else
      Result := Result + TrimRight(Copy(Lines[Index], Min(Indent, LeadingSpaces(Lines[Index])) + 1, MaxInt));
  end;
end;

function IsBlockSection(const AName: string): Boolean;
begin
  Result := IndexStr(AName, BlockSections) >= 0;
end;

/// <summary>Fasst Text zusammen und kürzt Leerraum an Zeilenanfang und -ende.</summary>
function Normalize(const ARuns: TXmlDocRuns): TXmlDocRuns;
var
  Merged: TXmlDocRuns;
  Run: TXmlDocRun;
  Index, Count: Integer;
  AtLineStart: Boolean;
begin
  // Benachbarte Texte gleichen Stils zusammenfassen.
  Merged := nil;
  for Run in ARuns do
  begin
    Count := Length(Merged);
    if (Run.Kind = TXmlDocRunKind.Text) and (Count > 0) and (Merged[Count - 1].Kind = TXmlDocRunKind.Text) and
      (Merged[Count - 1].Styles = Run.Styles) then
      Merged[Count - 1].Text := Merged[Count - 1].Text + Run.Text
    else
      Merged := Merged + [Run];
  end;
  Result := nil;
  AtLineStart := True;
  for Index := 0 to High(Merged) do
  begin
    Run := Merged[Index];
    if Run.Kind = TXmlDocRunKind.Text then
    begin
      Run.Text := CollapseSpaces(Run.Text);
      if AtLineStart then
        Run.Text := TrimLeft(Run.Text)
      else if (Length(Result) > 0) and (Result[High(Result)].Kind = TXmlDocRunKind.Text) and
        EndsStr(' ', Result[High(Result)].Text) then
        Run.Text := TrimLeft(Run.Text);
      if (Index = High(Merged)) or (Merged[Index + 1].Kind in LineEnds) then
        Run.Text := TrimRight(Run.Text);
      if Run.Text = '' then
        Continue;
    end
    else if Run.Kind in [TXmlDocRunKind.LineBreak, TXmlDocRunKind.Paragraph] then
    begin
      // Keine Umbrüche am Anfang, keine doppelten.
      if Length(Result) = 0 then
        Continue;
      if Result[High(Result)].Kind in [TXmlDocRunKind.LineBreak, TXmlDocRunKind.Paragraph] then
      begin
        if Run.Kind = TXmlDocRunKind.Paragraph then
          Result[High(Result)].Kind := TXmlDocRunKind.Paragraph;
        Continue;
      end;
    end;
    // Leerzeichen am Ende des vorigen Texts vor einem Zeilenwechsel entfernen.
    if (Run.Kind in LineEnds) and (Length(Result) > 0) and (Result[High(Result)].Kind = TXmlDocRunKind.Text) then
    begin
      Result[High(Result)].Text := TrimRight(Result[High(Result)].Text);
      if Result[High(Result)].Text = '' then
        SetLength(Result, Length(Result) - 1);
    end;
    Result := Result + [Run];
    AtLineStart := Run.Kind in LineStarts;
  end;
  // Umbrüche am Ende weg.
  while (Length(Result) > 0) and (Result[High(Result)].Kind in [TXmlDocRunKind.LineBreak,
    TXmlDocRunKind.Paragraph]) do
    SetLength(Result, Length(Result) - 1);
  if (Length(Result) > 0) and (Result[High(Result)].Kind = TXmlDocRunKind.Text) then
  begin
    Result[High(Result)].Text := TrimRight(Result[High(Result)].Text);
    if Result[High(Result)].Text = '' then
      SetLength(Result, Length(Result) - 1);
  end;
end;

{ TXmlDocRun }

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
    SetLength(FNodes, FCount * 2 + 8);
  Result := FCount;
  Inc(FCount);
  FNodes[Result].Name := AName;
  FNodes[Result].Text := AText;
  FNodes[Result].Attributes := AAttributes;
  FNodes[Result].Children := nil;
  if AParent >= 0 then
    FNodes[AParent].Children := FNodes[AParent].Children + [Result];
end;

procedure TXmlDocParser.AddText(AParent: Integer; const AText: string);
var
  Last: Integer;
begin
  if AText = '' then
    Exit;
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

procedure TXmlDocParser.Build(const AXml: string);
var
  Stack: TArray<Integer>;
  Index, Length_, Close, Start, Level, Node: Integer;
  Name, AttrName, Value: string;
  Attributes: TArray<string>;
  SelfClosing, Valid: Boolean;
  Quote: Char;
begin
  FCount := 0;
  FNodes := nil;
  AddNode(-1, '#root', '', nil);
  Stack := [0];
  Index := 1;
  Length_ := Length(AXml);
  while Index <= Length_ do
  begin
    if AXml[Index] <> '<' then
    begin
      Close := PosEx('<', AXml, Index);
      if Close = 0 then
        Close := Length_ + 1;
      AddText(Stack[High(Stack)], DecodeEntities(Copy(AXml, Index, Close - Index)));
      Index := Close;
      Continue;
    end;
    // Kommentar
    if Copy(AXml, Index, 4) = '<!--' then
    begin
      Close := PosEx('-->', AXml, Index + 4);
      if Close = 0 then
        Index := Length_ + 1
      else
        Index := Close + 3;
      Continue;
    end;
    // CDATA: Text ohne Entitäten
    if Copy(AXml, Index, 9) = '<![CDATA[' then
    begin
      Close := PosEx(']]>', AXml, Index + 9);
      if Close = 0 then
        Close := Length_ + 1;
      AddText(Stack[High(Stack)], Copy(AXml, Index + 9, Close - Index - 9));
      Index := Close + 3;
      Continue;
    end;
    // Endtag: schließt das nächste offene Tag gleichen Namens samt allem darin; sonst übergangen.
    if (Index < Length_) and (AXml[Index + 1] = '/') then
    begin
      Close := PosEx('>', AXml, Index);
      Start := Index + 2;
      Name := '';
      while (Start <= Length_) and IsNameChar(AXml[Start]) do
      begin
        Name := Name + AXml[Start];
        Inc(Start);
      end;
      if (Close = 0) or (Name = '') then
      begin
        AddText(Stack[High(Stack)], '<');
        Inc(Index);
        Continue;
      end;
      Name := LowerCase(Name);
      for Level := High(Stack) downto 1 do
        if FNodes[Stack[Level]].Name = Name then
        begin
          SetLength(Stack, Level);
          Break;
        end;
      Index := Close + 1;
      Continue;
    end;
    // Starttag mit Attributen
    Valid := (Index < Length_) and CharInSet(AXml[Index + 1], ['A'..'Z', 'a'..'z', '_']);
    Start := Index + 1;
    Name := '';
    Attributes := nil;
    SelfClosing := False;
    if Valid then
    begin
      while (Start <= Length_) and IsNameChar(AXml[Start]) do
      begin
        Name := Name + AXml[Start];
        Inc(Start);
      end;
      Valid := False;
      while Start <= Length_ do
      begin
        while (Start <= Length_) and IsSpace(AXml[Start]) do
          Inc(Start);
        if Start > Length_ then
          Break;
        if AXml[Start] = '>' then
        begin
          Valid := True;
          Inc(Start);
          Break;
        end;
        if (AXml[Start] = '/') and (Start < Length_) and (AXml[Start + 1] = '>') then
        begin
          Valid := True;
          SelfClosing := True;
          Inc(Start, 2);
          Break;
        end;
        if not IsNameChar(AXml[Start]) then
          Break;
        AttrName := '';
        while (Start <= Length_) and IsNameChar(AXml[Start]) do
        begin
          AttrName := AttrName + AXml[Start];
          Inc(Start);
        end;
        while (Start <= Length_) and IsSpace(AXml[Start]) do
          Inc(Start);
        Value := '';
        if (Start <= Length_) and (AXml[Start] = '=') then
        begin
          Inc(Start);
          while (Start <= Length_) and IsSpace(AXml[Start]) do
            Inc(Start);
          if (Start <= Length_) and ((AXml[Start] = '"') or (AXml[Start] = '''')) then
          begin
            Quote := AXml[Start];
            Close := PosEx(Quote, AXml, Start + 1);
            if Close = 0 then
              Break;
            Value := Copy(AXml, Start + 1, Close - Start - 1);
            Start := Close + 1;
          end
          else
            while (Start <= Length_) and not IsSpace(AXml[Start]) and (AXml[Start] <> '>') and
              not ((AXml[Start] = '/') and (Start < Length_) and (AXml[Start + 1] = '>')) do
            begin
              Value := Value + AXml[Start];
              Inc(Start);
            end;
        end;
        Attributes := Attributes + [LowerCase(AttrName), DecodeEntities(Value)];
      end;
    end;
    if not Valid then
    begin
      // "<" ohne gültiges Tag (z. B. "a < b"): bleibt Text.
      AddText(Stack[High(Stack)], '<');
      Inc(Index);
      Continue;
    end;
    Name := LowerCase(Name);
    // Ein neuer Abschnitt schließt einen offenen (nicht geschlossenes <summary>).
    if IsBlockSection(Name) then
      for Level := 1 to High(Stack) do
        if IsBlockSection(FNodes[Stack[Level]].Name) then
        begin
          SetLength(Stack, Level);
          Break;
        end;
    Node := AddNode(Stack[High(Stack)], Name, '', Attributes);
    if not SelfClosing and (Name <> 'br') then
      Stack := Stack + [Node];
    Index := Start;
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
      Exit(FNodes[ANode].Attributes[Index + 1]);
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
      Exit(True);
    Inc(Index, 2);
  end;
  Result := False;
end;

function TXmlDocParser.InnerText(ANode: Integer): string;
var
  Child: Integer;
begin
  if FNodes[ANode].Name = '' then
    Exit(FNodes[ANode].Text);
  if FNodes[ANode].Name = 'br' then
    Exit(#10);
  Result := '';
  for Child in FNodes[ANode].Children do
    Result := Result + InnerText(Child);
end;

function TXmlDocParser.HasSection(ANode: Integer): Boolean;
var
  Child: Integer;
begin
  for Child in FNodes[ANode].Children do
    if IsBlockSection(FNodes[Child].Name) or HasSection(Child) then
      Exit(True);
  Result := False;
end;

procedure TXmlDocParser.Add(const ARun: TXmlDocRun);
begin
  FRuns := FRuns + [ARun];
end;

procedure TXmlDocParser.AddInline(const AText: string; AStyles: TXmlDocStyles);
begin
  if AText <> '' then
    Add(TXmlDocRun.Create(TXmlDocRunKind.Text, AText, AStyles));
end;

procedure TXmlDocParser.WalkChildren(ANode: Integer; AStyles: TXmlDocStyles; ALevel: Integer);
var
  Child: Integer;
begin
  for Child in FNodes[ANode].Children do
    WalkNode(Child, AStyles, ALevel);
end;

procedure TXmlDocParser.WalkNode(ANode: Integer; AStyles: TXmlDocStyles; ALevel: Integer);
var
  Name, Text, Target: string;
begin
  Name := FNodes[ANode].Name;
  if Name = '' then
    AddInline(FNodes[ANode].Text, AStyles)
  else if Name = 'c' then
  begin
    Text := Trim(CollapseSpaces(InnerText(ANode)));
    if Text <> '' then
      Add(TXmlDocRun.Create(TXmlDocRunKind.Code, Text, AStyles));
  end
  else if Name = 'code' then
  begin
    Text := Dedent(InnerText(ANode));
    if Text <> '' then
      Add(TXmlDocRun.Create(TXmlDocRunKind.CodeBlock, Text));
  end
  else if Name = 'see' then
  begin
    Text := Trim(CollapseSpaces(InnerText(ANode)));
    if HasAttribute(ANode, 'cref') then
    begin
      Target := TXmlDoc.NormalizeCref(Attribute(ANode, 'cref'));
      if Text = '' then
        Text := Target;
      Add(TXmlDocRun.Create(TXmlDocRunKind.Ref, Text, AStyles, Target));
    end
    else if HasAttribute(ANode, 'href') then
    begin
      Target := Trim(Attribute(ANode, 'href'));
      if Text = '' then
        Text := Target;
      Add(TXmlDocRun.Create(TXmlDocRunKind.Link, Text, AStyles, Target));
    end
    else if HasAttribute(ANode, 'langword') then
      Add(TXmlDocRun.Create(TXmlDocRunKind.Keyword, Trim(Attribute(ANode, 'langword')), AStyles))
    else
      WalkChildren(ANode, AStyles, ALevel);
  end
  else if (Name = 'paramref') or (Name = 'typeparamref') then
  begin
    Text := Trim(Attribute(ANode, 'name'));
    if Text <> '' then
      Add(TXmlDocRun.Create(TXmlDocRunKind.ParamRef, Text, AStyles));
    WalkChildren(ANode, AStyles, ALevel);
  end
  else if Name = 'para' then
  begin
    Add(TXmlDocRun.Create(TXmlDocRunKind.Paragraph, ''));
    WalkChildren(ANode, AStyles, ALevel);
    Add(TXmlDocRun.Create(TXmlDocRunKind.Paragraph, ''));
  end
  else if Name = 'br' then
    Add(TXmlDocRun.Create(TXmlDocRunKind.LineBreak, ''))
  else if (Name = 'b') or (Name = 'strong') then
    WalkChildren(ANode, AStyles + [TXmlDocStyle.Bold], ALevel)
  else if (Name = 'i') or (Name = 'em') then
    WalkChildren(ANode, AStyles + [TXmlDocStyle.Italic], ALevel)
  else if Name = 'list' then
    WalkList(ANode, AStyles, ALevel + 1)
  else if Name = 'seealso' then
    AddSeeAlso(ANode)
  else if Name = 'inheritdoc' then
  begin
    MarkInherit(ANode);
    WalkChildren(ANode, AStyles, ALevel);
  end
  else
    // Unbekannte Tags (und Abschnitte an falscher Stelle) behalten ihren Text.
    WalkChildren(ANode, AStyles, ALevel);
end;

procedure TXmlDocParser.WalkList(ANode: Integer; AStyles: TXmlDocStyles; ALevel: Integer);
var
  Kind, Name: string;
  Child, Part, Number: Integer;
  Table, Header, HasTerm, HasDescription: Boolean;
  Styles: TXmlDocStyles;
  Bullet: string;
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
      Styles := Styles + [TXmlDocStyle.Bold];
    if Header or Table then
      Bullet := ''
    else if Kind = 'number' then
    begin
      Inc(Number);
      Bullet := IntToStr(Number) + '.';
    end
    else
      Bullet := '•';
    Add(TXmlDocRun.Create(TXmlDocRunKind.Bullet, Bullet, Styles, '', ALevel));
    HasTerm := False;
    HasDescription := False;
    for Part in FNodes[Child].Children do
      if FNodes[Part].Name = 'term' then
      begin
        HasTerm := True;
        if Table then
          WalkChildren(Part, Styles, ALevel)
        else
          WalkChildren(Part, Styles + [TXmlDocStyle.Bold], ALevel);
      end
      else if FNodes[Part].Name = 'description' then
      begin
        if Table then
          Add(TXmlDocRun.Create(TXmlDocRunKind.Cell, ''))
        else if HasTerm and not HasDescription then
          AddInline(' – ', Styles);
        HasDescription := True;
        WalkChildren(Part, Styles, ALevel);
      end
      else
        WalkNode(Part, Styles, ALevel);
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
      Text := Target;
    Add(TXmlDocRun.Create(TXmlDocRunKind.Ref, Text, [], Target));
  end
  else if HasAttribute(ANode, 'href') then
  begin
    Target := Trim(Attribute(ANode, 'href'));
    if Text = '' then
      Text := Target;
    Add(TXmlDocRun.Create(TXmlDocRunKind.Link, Text, [], Target));
  end
  else
    AddInline(Text, []);
  if Length(FRuns) > 0 then
  begin
    if Length(FSeeAlso) > 0 then
      FSeeAlso := FSeeAlso + [TXmlDocRun.Create(TXmlDocRunKind.Text, ', ')];
    FSeeAlso := FSeeAlso + FRuns;
  end;
  FRuns := Saved;
end;

procedure TXmlDocParser.MarkInherit(ANode: Integer);
begin
  FDoc.InheritDoc := True;
  if HasAttribute(ANode, 'cref') then
    FDoc.InheritCref := TXmlDoc.NormalizeCref(Attribute(ANode, 'cref'));
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
        FDoc.Sections[Index].Runs := Normalize(FDoc.Sections[Index].Runs +
          [TXmlDocRun.Create(TXmlDocRunKind.Paragraph, '')] + ARuns);
      Exit;
    end;
    if Length(ARuns) = 0 then
      Exit;
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
        SectionName := TXmlDoc.NormalizeCref(Attribute(Child, 'cref'))
      else
        SectionName := Trim(Attribute(Child, 'name'));
      AddSection(Kind, SectionName, Normalize(FRuns));
    end
    else if (Name <> '') and (Name <> 'list') and HasSection(Child) then
      // Hülle um Abschnitte (z. B. <member>): wie oberste Ebene.
      Top(Child, ALoose)
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
      FDoc.Sections[Index].Runs := Normalize(FDoc.Sections[Index].Runs +
        [TXmlDocRun.Create(TXmlDocRunKind.Paragraph, '')] + Loose)
    else
      AddSection(TXmlDocSectionKind.Summary, '', Loose);
  end;
  if Length(FSeeAlso) > 0 then
    AddSection(TXmlDocSectionKind.SeeAlso, '', FSeeAlso);
  // Nach Art sortieren, gleiche Art in Kommentarreihenfolge.
  Sorted := nil;
  for Kind := Low(TXmlDocSectionKind) to High(TXmlDocSectionKind) do
    for Section in FDoc.Sections do
      if Section.Kind = Kind then
        Sorted := Sorted + [Section];
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
            ADoc.Params := ADoc.Params + [Entry]
          else
            ADoc.Exceptions := ADoc.Exceptions + [Entry];
        end;
    end;
end;

function TXmlDoc.IsEmpty: Boolean;
begin
  Result := Length(Sections) = 0;
end;

function TXmlDoc.IndexOf(AKind: TXmlDocSectionKind; const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Sections) do
    if (Sections[Index].Kind = AKind) and ((AName = '') or SameText(Sections[Index].Name, AName)) then
      Exit(Index);
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
      Result.Sections := Result.Sections + [Section];
  end;
  Sorted := nil;
  for Kind := Low(TXmlDocSectionKind) to High(TXmlDocSectionKind) do
    for Section in Result.Sections do
      if Section.Kind = Kind then
        Sorted := Sorted + [Section];
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
    Result := Copy(Result, 3, MaxInt);
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
      Lines := Lines + [TrimRight(Buffer)];
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
          Buffer := Buffer + Run.Text + ' (' + Run.Target + ')'
        else
          Buffer := Buffer + Run.Text;
      TXmlDocRunKind.LineBreak, TXmlDocRunKind.Paragraph:
        Flush;
      TXmlDocRunKind.CodeBlock:
        begin
          Flush;
          for Line in Run.Text.Split([#10]) do
            Lines := Lines + [Line];
        end;
      TXmlDocRunKind.Bullet:
        begin
          Flush;
          Buffer := StringOfChar(' ', 2 * Max(0, Run.Level - 1));
          if Run.Text <> '' then
            Buffer := Buffer + Run.Text + ' ';
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
    Exit;
  if TXmlDocStyle.Italic in AStyles then
    Result := '*' + Result + '*';
  if TXmlDocStyle.Bold in AStyles then
    Result := '**' + Result + '**';
end;

class function TXmlDoc.RunsMarkdown(const ARuns: TXmlDocRuns): string;
var
  Run: TXmlDocRun;
  InList: Boolean;
  Marker: string;
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
        begin
          // Eine Liste beginnt nach einer Leerzeile.
          if InList then
            Result := Result + #10
          else
            Result := Result + #10#10;
          if EndsStr('.', Run.Text) then
            Marker := Run.Text + ' '
          else
            Marker := '- ';
          Result := Result + StringOfChar(' ', 2 * Max(0, Run.Level - 1)) + Marker;
        end;
      TXmlDocRunKind.Cell:
        Result := Result + ' – ';
    end;
    if Run.Kind = TXmlDocRunKind.Bullet then
      InList := True
    else if Run.Kind in [TXmlDocRunKind.Paragraph, TXmlDocRunKind.CodeBlock] then
      InList := False;
  end;
  while Pos(#10#10#10, Result) > 0 do
    Result := StringReplace(Result, #10#10#10, #10#10, [rfReplaceAll]);
  Result := Trim(Result);
end;

function JoinBlocks(const ABlocks: TArray<string>): string;
var
  Block: string;
begin
  Result := '';
  for Block in ABlocks do
    if Block <> '' then
    begin
      if Result <> '' then
        Result := Result + #10#10;
      Result := Result + Block;
    end;
end;

function TXmlDoc.ToPlainText(AWithParams: Boolean): string;
var
  Section: TXmlDocSection;
  Main, ParamLines, TypeLines, Facts, Remark, Example, SeeAlso: string;

  procedure AddLine(var ATarget: string; const ALine: string);
  begin
    if ATarget <> '' then
      ATarget := ATarget + #10;
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
          AddLine(ParamLines, Section.Name + ': ' + Section.Text);
      TXmlDocSectionKind.TypeParam:
        begin
          if TypeLines = '' then
            TypeLines := 'Typparameter:';
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
          Blocks := Blocks + ['*' + Section.Name + '*: ' + RunsMarkdown(Section.Runs)];
      TXmlDocSectionKind.TypeParam:
        begin
          if not TypeHeader then
            Blocks := Blocks + ['**Typparameter**'];
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
        Result := Line
      else
        Result := Line + #10 + Result;
    end
    else if not StartsStr('[', Line) then
      Break;
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
    if SameText(SectionNames[Kind], AName) then
    begin
      AKind := Kind;
      Exit(True);
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
    if SameText(RunKindNames[Kind], AName) then
    begin
      AKind := Kind;
      Exit(True);
    end;
  Result := False;
end;

end.
