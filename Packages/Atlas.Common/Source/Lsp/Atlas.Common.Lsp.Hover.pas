unit Atlas.Common.Lsp.Hover;

// Hover (textDocument/hover): Deklaration und XML-Dokumentation (///) des
// Symbols unter dem Cursor als Markdown.
//
// Die Deklaration ist die erste Zeile der Fundstelle ab ihrem Anfang. Der
// Dokumentationskommentar sind die ///-Zeilen direkt darüber; XML-Tags wie
// <summary> entfallen, <param name="X"> wird zu "X:". Bei Methoden mit
// getrennter Implementierung gilt die Deklaration (TLspDefinition).
// Bei Klassen folgen die published-Properties und Ereignisse samt geerbter
// (TPublishedMembers). Auf einem Attribut (#119) zusätzlich die Konstruktoren
// der Attributklasse, bei Argumenten die mit passender Parameterzahl.
//
// Clients ohne Markdown (RAD Studio meldet hover.contentFormat ["plaintext"])
// bekommen denselben Inhalt als Klartext (#175).
//
// Für den Atlas-Tooltip (#588) kommen Art, Herkunft, Fundort, Typverweise in der
// Deklaration und die Vererbungskette dazu (Atlas.Common.Lsp.HoverTypes). Ist die
// Datei nicht geöffnet, liest der Hover sie selbst: So fragt das Plugin einen
// angeklickten Typ über seinen Fundort ab.
//
// In FieldByName('…'), FindField('…') und ParamByName('…') meldet der Hover
// einen Namen, den die Datenmenge laut Formulardatei nicht kennt, als Hinweis
// „Feld nicht gefunden in qryOrders“ (#461); keine Diagnose.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.HoverTypes;

type
  /// <summary>Liefert den Text einer Datei; False, wenn sie nicht lesbar ist.</summary>
  THoverReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Delphi-Version des Dokuments AUri (z. B. "23.0"); '' = unbekannt.</summary>
  THoverVersionProvider = reference to function(const AUri: string): string;

  THoverInfo = record
    Declaration: string;
    Documentation: string;
    /// <summary>Unit der Deklaration, wenn sie nicht die aktuelle ist.</summary>
    UnitName: string;
    /// <summary>Markdown mit published-Properties und Ereignissen bei Klassen; sonst ''.</summary>
    Members: string;
    /// <summary>Link zur DocWiki bei RTL- und VCL-Symbolen (#27); sonst ''.</summary>
    DocWikiUrl: string;
    /// <summary>Microsoft-Link und 64-Bit-Hinweis bei Windows-API-Funktionen (#120); sonst ''.</summary>
    WinApi: string;
    /// <summary>Message-Handler der Klasse als Markdown (#36); sonst ''.</summary>
    Messages: string;
    /// <summary>Wert bei Zahlen, Konstanten und Aufzählungswerten (#38); sonst ''.</summary>
    Value: string;
    /// <summary>Hinweis bei deprecated, platform, experimental (#38); sonst ''.</summary>
    Deprecation: string;
    /// <summary>In der Formulardatei gesetzte Werte eines Komponentenfelds (#126); sonst ''.</summary>
    FormValues: string;
    /// <summary>Konstruktoren der Attributklasse auf einem Attribut (#119); sonst ''.</summary>
    Constructors: string;
    /// <summary>Art für Badge und Kopfzeile (#588), siehe TLspHoverTypes.KindOf; '' wenn unbekannt.</summary>
    Kind: string;
    /// <summary>VCL, FMX oder RTL; '' bei eigenen Units.</summary>
    Origin: string;
    /// <summary>Fundort des Namens der Deklaration (0-basiert); FileName '' ohne.</summary>
    FileName: string;
    Line: Integer;
    Character: Integer;
    /// <summary>Typnamen in Declaration mit Fundort.</summary>
    Links: TArray<THoverLink>;
    /// <summary>Typ, dessen Kette Ancestors zeigt: der Typ selbst bzw. bei "class of T" T.</summary>
    ChainOf: string;
    /// <summary>Vererbungskette ab ChainOf aufwärts; leer bei anderen Arten.</summary>
    Ancestors: TArray<THoverTypeRef>;
    function Found: Boolean;
    function ToMarkdown: string;
    /// <summary>Derselbe Inhalt ohne Markdown-Auszeichnung.</summary>
    function ToPlainText: string;
  end;

  TLspHover = class
  public const
    Method = 'textDocument/hover';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: THoverReadText;
    FNamespaces: TArray<string>;
    FVersionProvider: THoverVersionProvider;
    FMarkdown: Boolean;
    function HandleHover(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: THoverReadText;
      const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Hover-Inhalt an APosition; ATreeText ist der Text von ATree.</summary>
    class function InfoAt(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ATreeText, AFileName: string; const APosition: TTextPosition;
      const AReadText: THoverReadText; const ADelphiVersion: string = ''): THoverInfo; static;
    /// <summary>Dokumentationskommentar über ALine als Markdown; '' ohne Kommentar.</summary>
    class function DocumentationAbove(const ALines: TArray<string>; ALine: Integer): string; static;
    /// <summary>False, wenn der Client in initialize nur Klartext für Hover meldet.</summary>
    class function ClientSupportsMarkdown(const AInitializeParams: TJSONObject): Boolean; static;
    /// <summary>„Feld nicht gefunden in qryOrders“ (#461), wenn APosition im Namen eines FieldByName-, FindField-
    /// oder ParamByName-Aufrufs steht, die Formulardatei Namen für die Datenmenge kennt und dieser nicht dabei ist.
    /// </summary>
    class function DataNameHint(const AText, AFileName: string; const APosition: TTextPosition;
      const AReadText: THoverReadText; out AHint: string): Boolean; static;
    /// <summary>Teile des Hovers für den Atlas-Tooltip (#442), Doku und Hinweis als Klartext.</summary>
    class function AtlasJson(const AInfo: THoverInfo): TJSONObject; static;
    /// <summary>Antwort als Markdown (Vorgabe) oder als Klartext.</summary>
    property Markdown: Boolean read FMarkdown write FMarkdown;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
    /// <summary>Für den Release-Namen der DocWiki-Links; ohne Provider gilt die neueste Version.</summary>
    property VersionProvider: THoverVersionProvider read FVersionProvider write FVersionProvider;
  end;

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.PublishedMembers,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.FormInfo,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Lsp.DocWiki,
  Atlas.Common.Lsp.WinApiDocs,
  Atlas.Common.Lsp.MessageHandlers,
  Atlas.Common.Lsp.HoverValues,
  Atlas.Common.Lsp.CompilerDirectives,
  Atlas.Common.Lsp.KeywordReference,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.Attributes,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Dfm.FormFiles,
  Atlas.Common.Editing.DataFieldNames;

function SplitLines(const AText: string): TArray<string>;
var
  Index, Start: Integer;
  Line: string;
begin
  Result := nil;
  Start := 1;
  for Index := 1 to Length(AText) + 1 do
    if (Index > Length(AText)) or (AText[Index] = #10) then
    begin
      Line := Copy(AText, Start, Index - Start);
      if (Line <> '') and (Line[Length(Line)] = #13) then
        SetLength(Line, Length(Line) - 1);
      Result := Result + [Line];
      Start := Index + 1;
    end;
end;

// Entfernt XML-Tags; <param name="X"> wird zu "X:".
function StripTags(const ALine: string): string;
var
  Index, Close: Integer;
  Tag, Name: string;
  Quote: Integer;
begin
  Result := '';
  Index := 1;
  while Index <= Length(ALine) do
  begin
    if ALine[Index] = '<' then
    begin
      Close := PosEx('>', ALine, Index);
      if Close = 0 then
      begin
        Result := Result + Copy(ALine, Index, MaxInt);
        Break;
      end;
      Tag := Copy(ALine, Index + 1, Close - Index - 1);
      if StartsText('param ', Tag) or StartsText('typeparam ', Tag) then
      begin
        Quote := Pos('"', Tag);
        Name := Copy(Tag, Quote + 1, MaxInt);
        Name := Copy(Name, 1, Pos('"', Name) - 1);
        if Name <> '' then
          Result := Result + '*' + Name + '*: ';
      end;
      Index := Close + 1;
    end
    else
    begin
      Result := Result + ALine[Index];
      Inc(Index);
    end;
  end;
end;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

/// <summary>Deklaration von ARange bis zum Ende der letzten Zeile (dort stehen Direktiven wie deprecated).</summary>
function DeclarationText(const ALines: TArray<string>; const ARange: TTextRange): string;
var
  Line: Integer;
begin
  Result := '';
  for Line := ARange.StartPos.Line to ARange.EndPos.Line do
  begin
    if (Line < 0) or (Line > High(ALines)) then
      Break;
    if Line = ARange.StartPos.Line then
      Result := Copy(ALines[Line], ARange.StartPos.Character + 1, MaxInt)
    else
      Result := Result + ' ' + Trim(ALines[Line]);
  end;
end;

/// <summary>Ordinalzahl eines Aufzählungswerts: Position im Typ, ohne explizite Werte.</summary>
function EnumOrdinal(const AUnit: TUnitIndex; const AMember: TIndexSymbol): Integer;
var
  Symbol: TIndexSymbol;
begin
  Result := 0;
  for Symbol in AUnit.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.EnumMember) and SameText(Symbol.Container, AMember.Container) then
    begin
      if Symbol.SelectionRange.StartPos = AMember.SelectionRange.StartPos then
        Exit;
      Inc(Result);
    end;
end;

// Entfernt nur die Auszeichnung, die der Hover selbst erzeugt: **fett** (Veraltet,
// Überschriften), *Name*: am Absatzanfang (Parameter) und `Code`. Andere Zeichen aus
// dem Kommentar bleiben stehen, z. B. das * in "(Gallery.Page.*)" (in der IDE gesehen).
function StripMarkdown(const AText: string): string;
begin
  Result := TRegEx.Replace(AText, '\*\*([^*\n]+)\*\*', '$1');
  Result := TRegEx.Replace(Result, '(^|\n)\*([^*\n]+)\*:', '$1$2:');
  Result := TRegEx.Replace(Result, '`([^`\n]*)`', '$1');
end;

{ THoverInfo }

function TypeRefJson(const ARef: THoverTypeRef): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ARef.Name);
  if ARef.UnitName <> '' then
    Result.AddPair('unit', ARef.UnitName);
  Result.AddPair('file', ARef.FileName);
  Result.AddPair('line', TJSONNumber.Create(ARef.Line));
  Result.AddPair('character', TJSONNumber.Create(ARef.Character));
end;

class function TLspHover.AtlasJson(const AInfo: THoverInfo): TJSONObject;
var
  Links, Ancestors: TJSONArray;
  Link: THoverLink;
  Ancestor: THoverTypeRef;
  Item: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('declaration', AInfo.Declaration);
  if AInfo.UnitName <> '' then
    Result.AddPair('unit', AInfo.UnitName);
  if AInfo.Documentation <> '' then
    Result.AddPair('documentation', StripMarkdown(AInfo.Documentation));
  if AInfo.Value <> '' then
    Result.AddPair('value', AInfo.Value);
  if AInfo.Deprecation <> '' then
    Result.AddPair('deprecation', StripMarkdown(AInfo.Deprecation));
  if AInfo.Kind <> '' then
    Result.AddPair('kind', AInfo.Kind);
  if AInfo.Origin <> '' then
    Result.AddPair('origin', AInfo.Origin);
  if AInfo.FileName <> '' then
  begin
    Result.AddPair('file', AInfo.FileName);
    Result.AddPair('line', TJSONNumber.Create(AInfo.Line));
    Result.AddPair('character', TJSONNumber.Create(AInfo.Character));
  end;
  if AInfo.DocWikiUrl <> '' then
    Result.AddPair('docWiki', AInfo.DocWikiUrl);
  if Length(AInfo.Links) > 0 then
  begin
    Links := TJSONArray.Create;
    for Link in AInfo.Links do
    begin
      Item := TypeRefJson(Link.Target);
      Item.AddPair('start', TJSONNumber.Create(Link.Start));
      Item.AddPair('length', TJSONNumber.Create(Link.Length));
      Links.AddElement(Item);
    end;
    Result.AddPair('links', Links);
  end;
  if Length(AInfo.Ancestors) > 0 then
  begin
    Result.AddPair('chainOf', AInfo.ChainOf);
    Ancestors := TJSONArray.Create;
    for Ancestor in AInfo.Ancestors do
      Ancestors.AddElement(TypeRefJson(Ancestor));
    Result.AddPair('ancestors', Ancestors);
  end;
end;

function THoverInfo.Found: Boolean;
begin
  Result := Declaration <> '';
end;

function THoverInfo.ToMarkdown: string;
begin
  Result := '```pascal' + #10 + Declaration + #10 + '```';
  if Deprecation <> '' then
    Result := Result + #10#10 + Deprecation;
  if Value <> '' then
    Result := Result + #10#10 + 'Wert: `' + Value + '`';
  if Documentation <> '' then
    Result := Result + #10#10 + Documentation;
  if UnitName <> '' then
    Result := Result + #10#10 + 'Unit `' + UnitName + '`';
  if DocWikiUrl <> '' then
    Result := Result + #10#10 + '[DocWiki](' + DocWikiUrl + ')';
  if WinApi <> '' then
    Result := Result + #10#10 + WinApi;
  if Members <> '' then
    Result := Result + #10#10 + '---' + #10#10 + Members;
  if Messages <> '' then
    Result := Result + #10#10 + '---' + #10#10 + Messages;
  if FormValues <> '' then
    Result := Result + #10#10 + '---' + #10#10 + FormValues;
  if Constructors <> '' then
    Result := Result + #10#10 + '```pascal' + #10 + Constructors + #10 + '```';
end;

function THoverInfo.ToPlainText: string;
begin
  Result := Declaration;
  if Deprecation <> '' then
    Result := Result + #10#10 + StripMarkdown(Deprecation);
  if Value <> '' then
    Result := Result + #10#10 + 'Wert: ' + Value;
  if Documentation <> '' then
    Result := Result + #10#10 + StripMarkdown(Documentation);
  if UnitName <> '' then
    Result := Result + #10#10 + 'Unit ' + UnitName;
  if DocWikiUrl <> '' then
    Result := Result + #10#10 + 'DocWiki: ' + DocWikiUrl;
  if Members <> '' then
    Result := Result + #10#10 + StripMarkdown(Members);
  if Messages <> '' then
    Result := Result + #10#10 + StripMarkdown(Messages);
end;

{ TLspHover }

constructor TLspHover.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FEnsureUnit := AEnsureUnit;
  FMarkdown := True;
end;

procedure TLspHover.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleHover);
end;

class function TLspHover.DocumentationAbove(const ALines: TArray<string>; ALine: Integer): string;
var
  Index: Integer;
  Line: string;
  Parts: TArray<string>;
begin
  Parts := nil;
  Index := ALine - 1;
  while (Index >= 0) and (Index <= High(ALines)) and StartsStr('///', TrimLeft(ALines[Index])) do
  begin
    Line := Trim(StripTags(Copy(TrimLeft(ALines[Index]), 4, MaxInt)));
    if Line <> '' then
      Parts := [Line] + Parts;
    Dec(Index);
  end;
  Result := '';
  for Line in Parts do
  begin
    if Result <> '' then
      // Zeilen mit *Name*: (Parameter) als eigene Absätze, sonst Fließtext.
      if StartsStr('*', Line) then
        Result := Result + #10#10
      else
        Result := Result + ' ';
    Result := Result + Line;
  end;
end;

class function TLspHover.ClientSupportsMarkdown(const AInitializeParams: TJSONObject): Boolean;
var
  Formats: TJSONArray;
  Item: TJSONValue;
begin
  // Ohne Angabe bleibt es bei Markdown, wie bisher.
  if (AInitializeParams = nil) or
    not AInitializeParams.TryGetValue<TJSONArray>('capabilities.textDocument.hover.contentFormat', Formats) or
    (Formats.Count = 0) then
    Exit(True);
  for Item in Formats do
    if SameText(Item.Value, 'markdown') then
      Exit(True);
  Result := False;
end;

/// <summary>Werte des Komponentenfelds AFieldName aus der Formulardatei neben AUnitFile (#126); nur die eigene
/// Formulardatei, ohne Vorfahr-Formulare (#115 nicht geplant).</summary>
function FormFieldValues(const AUnitFile, AFormClass, AFieldName, AOpenFile, AOpenText: string;
  const AReadText: THoverReadText): string;
var
  FormFile, FormText, Extension: string;
  Document: TDfmDocument;
  Obj: TDfmObject;
begin
  Result := '';
  FormText := '';
  for Extension in TArray<string>.Create('.dfm', '.fmx') do
  begin
    FormFile := ChangeFileExt(AUnitFile, Extension);
    if SameText(FormFile, AOpenFile) then
      FormText := AOpenText
    else if not (Assigned(AReadText) and AReadText(FormFile, FormText)) then
      FormText := '';
    if FormText <> '' then
      Break;
  end;
  if FormText = '' then
    Exit;
  Document := TDfmParser.Parse(FormText);
  try
    Obj := TFormInfo.FindComponent(Document, AFormClass, AFieldName);
    if Obj <> nil then
      Result := TFormInfo.ComponentMarkdown(Obj, FormFile);
  finally
    Document.Free;
  end;end;

/// <summary>Konstruktoren von AClass in AUnit, die AArgCount Argumente annehmen; passt keiner, alle.</summary>
function AttributeConstructors(const AUnit: TUnitIndex; const AClass: TIndexSymbol; const ALines: TArray<string>;
  AArgCount: Integer): string;
var
  Symbol: TIndexSymbol;
  All, Matching: string;
  Line: string;
begin
  All := '';
  Matching := '';
  for Symbol in AUnit.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.Constructor_) and SameText(Symbol.Container, AClass.Name) and
      (Symbol.Range.StartPos.Line > AClass.Range.StartPos.Line) and
      (Symbol.Range.StartPos.Line < AClass.Range.EndPos.Line) and (Symbol.Range.StartPos.Line <= High(ALines)) then
    begin
      Line := Trim(ALines[Symbol.Range.StartPos.Line]);
      All := All + IfThen(All <> '', #10) + Line;
      if (AArgCount >= Symbol.MinArgs) and (AArgCount <= Symbol.MaxArgs) then
        Matching := Matching + IfThen(Matching <> '', #10) + Line;
    end;
  Result := IfThen(Matching <> '', Matching, All);
end;

class function TLspHover.InfoAt(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ATreeText, AFileName: string; const APosition: TTextPosition;
  const AReadText: THoverReadText; const ADelphiVersion: string): THoverInfo;
var
  Targets: TArray<TDefinitionTarget>;
  Text: string;
  Lines: TArray<string>;
  Start: TTextPosition;
  OwnerUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  ReadText: TMemberReadText;
  ClassTree: TSyntaxTree;
  Token: TPascalToken;
  Number: Int64;
  Use: TAttributeUse;
  SelfName, ChainName: string;
  TypeSymbol: Boolean;
  Resolved: TResolvedSymbol;
begin
  Result := Default(THoverInfo);
  // Zahlenliteral unter dem Cursor: Schreibweisen statt Deklaration.
  for Token in ATree.Tokens do
    if (Token.Kind = TPascalTokenKind.Number) and (ComparePositions(Token.StartPos, APosition) <= 0) and
      (ComparePositions(APosition, Token.EndPos) < 0) then
    begin
      if THoverValues.TryParseNumber(Token.Text, Number) then
      begin
        Result.Declaration := Token.Text;
        Result.Value := THoverValues.FormatNumber(Number);
      end
      else
        TRequestDiagnostics.Reason('numberUnparsed');
      Exit;
    end;
  Targets := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, APosition, True);
  if Length(Targets) = 0 then
  begin
    // Grundcodes für das Diagnoselog (#647).
    TRequestDiagnostics.Reason('noTarget');
    Exit;
  end;
  Start := Targets[0].Range.StartPos;
  // Unit-Namen: Ziel ist der Dateianfang. Vor dem Lesen der Datei prüfen,
  // denn dafür wird ihr Text nicht gebraucht.
  if (Start.Line = 0) and (Start.Character = 0) and (Targets[0].Range.EndPos = Start) and
    not SameText(Targets[0].FileName, AFileName) then
  begin
    if AIndex.FindFile(Targets[0].FileName, OwnerUnit) then
    begin
      Result.Declaration := 'unit ' + OwnerUnit.UnitName + ';';
      Result.DocWikiUrl := TDocWiki.Url(ADelphiVersion, OwnerUnit.UnitName, '', '');
    end;
    Result.Documentation := '`' + Targets[0].FileName + '`';
    Exit;
  end;
  if SameText(Targets[0].FileName, AFileName) then
    Text := ATreeText
  else if not (Assigned(AReadText) and AReadText(Targets[0].FileName, Text)) then
  begin
    TRequestDiagnostics.Reason('declarationUnreadable');
    Exit;
  end;
  Lines := SplitLines(Text);
  if (Start.Line < 0) or (Start.Line > High(Lines)) then
  begin
    TRequestDiagnostics.Reason('declarationOutOfRange');
    Exit;
  end;
  Result.Declaration := TrimRight(Copy(Lines[Start.Line], Start.Character + 1, MaxInt));
  Result.Documentation := DocumentationAbove(Lines, Start.Line);
  Result.Deprecation := THoverValues.Deprecation(DeclarationText(Lines, Targets[0].Range));
  Result.FileName := Targets[0].FileName;
  Result.Line := Targets[0].SelectionRange.StartPos.Line;
  Result.Character := Targets[0].SelectionRange.StartPos.Character;
  // Aus einer Include-Datei (#500): die einbindende Unit, die Datei dahinter. Die eigene Datei
  // auch ohne Index (noch nicht gespeichert bzw. nicht im Projekt) aus dem Baum.
  if not TIndexFiles.UnitOf(AIndex, Targets[0].FileName, OwnerUnit) then
    if SameText(Targets[0].FileName, AFileName) then
      OwnerUnit := TIndexExtractor.Extract(ATree, AFileName)
    else
    begin
      TRequestDiagnostics.Reason('unitNotIndexed');
      Exit;
    end;
  if not SameText(Targets[0].FileName, OwnerUnit.FileName) then
    Result.UnitName := OwnerUnit.UnitName + ' (' + ExtractFileName(Targets[0].FileName) + ')'
  else if not SameText(Targets[0].FileName, AFileName) then
    Result.UnitName := OwnerUnit.UnitName;
  SelfName := '';
  TypeSymbol := False;
  for Symbol in OwnerUnit.Symbols do
    if (Symbol.SelectionRange.StartPos = Targets[0].SelectionRange.StartPos) and
      SameText(OwnerUnit.SymbolFile(Symbol), Targets[0].FileName) then
    begin
      SelfName := Symbol.Name;
      Result.Kind := TLspHoverTypes.KindOf(Symbol.Kind, Result.Declaration);
      TypeSymbol := (Symbol.Container = '') and (Symbol.Kind in [TIndexSymbolKind.ClassType,
        TIndexSymbolKind.ObjectType, TIndexSymbolKind.InterfaceType]);
      Result.DocWikiUrl := TDocWiki.Url(ADelphiVersion, OwnerUnit.UnitName, Symbol.Container, Symbol.Name);
      if (Symbol.Container = '') and TWinApiDocs.IsWinApiUnit(OwnerUnit.UnitName) then
        Result.WinApi := TWinApiDocs.HoverText(Symbol.Name);
      if Symbol.Kind = TIndexSymbolKind.Constant then
        Result.Value := THoverValues.ConstantValue(Result.Declaration)
      else if Symbol.Kind = TIndexSymbolKind.EnumMember then
        Result.Value := 'Ord = ' + IntToStr(EnumOrdinal(OwnerUnit, Symbol))
      else if (Symbol.Kind = TIndexSymbolKind.Field) and (Symbol.Container <> '') then
        Result.FormValues := FormFieldValues(Targets[0].FileName, Symbol.Container, Symbol.Name,
          AFileName, ATreeText, AReadText);
      Break;
    end;
  // Typen in der Deklaration und Vererbungskette für den Atlas-Tooltip (#588).
  Result.Origin := TLspHoverTypes.Origin(OwnerUnit.UnitName);
  Result.Links := TLspHoverTypes.Links(AResolver, OwnerUnit, Result.Declaration, SelfName);
  if TypeSymbol then
  begin
    ChainName := TLspHoverTypes.ClassRefTarget(Result.Declaration);
    if ChainName = '' then
      ChainName := SelfName;
    if AResolver.ResolveTypeFrom(OwnerUnit, ChainName, Resolved) then
    begin
      Result.ChainOf := Resolved.Name;
      Result.Ancestors := TLspHoverTypes.Chain(AResolver, Resolved);
    end;
  end;
  for Symbol in OwnerUnit.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Container = '') and
      ((Symbol.Range.StartPos = Start) or (Symbol.SelectionRange.StartPos = Start)) and
      SameText(OwnerUnit.SymbolFile(Symbol), Targets[0].FileName) then
    begin
      if TAttributes.At(ATree, APosition, Use) then
        Result.Constructors := AttributeConstructors(OwnerUnit, Symbol, Lines, Use.ArgCount);
      // Die eigene Datei kommt aus dem Editor, nicht von der Platte.
      ReadText :=
        function(const AName: string; out AText: string): Boolean
        begin
          if SameText(AName, AFileName) then
          begin
            AText := ATreeText;
            Exit(True);
          end;
          Result := Assigned(AReadText) and AReadText(AName, AText);
        end;
      Result.Members := TPublishedMembers.ToMarkdown(TPublishedMembers.Collect(AIndex, Symbol.Name, ReadText));
      if SameText(Targets[0].FileName, AFileName) then
        Result.Messages := TMessageHandlers.Overview(AResolver, AIndex, ATree, AFileName, Symbol.Name,
          function(const AName: string; out AText: string): Boolean
          begin
            Result := ReadText(AName, AText);
          end).ToMarkdown
      else
      begin
        ClassTree := TSyntaxTreeCache.Parse(Text);
        try
          Result.Messages := TMessageHandlers.Overview(AResolver, AIndex, ClassTree, Targets[0].FileName, Symbol.Name,
            function(const AName: string; out AText: string): Boolean
            begin
              Result := ReadText(AName, AText);
            end).ToMarkdown;
        finally
          ClassTree.Free;
        end;
      end;
      // ReadText liegt im selben Closure-Rahmen, den es selbst und die Aufrufe oben einfangen:
      // ohne Freigabe hielte der Rahmen sich selbst (Leck je Hover auf eine Klasse).
      ReadText := nil;
      Break;
    end;
end;

class function TLspHover.DataNameHint(const AText, AFileName: string; const APosition: TTextPosition;
  const AReadText: THoverReadText; out AHint: string): Boolean;
var
  Lines: TArray<string>;
  Call: TDataNameCall;
  FormFile, FormText, Sql: string;
  Names: TArray<TDataName>;
  Found: Boolean;
begin
  AHint := '';
  Result := False;
  Lines := AText.Split([#10]);
  if (APosition.Line < 0) or (APosition.Line > High(Lines)) or not Assigned(AReadText) or
    not TDataFieldNames.CallAt(Lines[APosition.Line].TrimRight([#13]), APosition.Character, Call) or
    (Call.Content = '') then
    Exit;
  for FormFile in TFormFiles.FormFiles(AFileName, AText) do
    if AReadText(FormFile, FormText) then
    begin
      Names := TDataFieldNames.FromForm(FormText, Call.DataSet, Call.Kind, Sql, Found);
      if Found then
      begin
        // Ohne bekannte Namen (select * ohne Schema) lässt sich nichts sagen.
        if (Length(Names) = 0) or TDataFieldNames.Contains(Names, Call.Content) then
          Exit;
        if Call.Kind = TDataNameKind.Param then
          AHint := Format('Parameter nicht gefunden in %s', [Call.DataSet])
        else
          AHint := Format('Feld nicht gefunden in %s', [Call.DataSet]);
        Exit(True);
      end;
    end;
end;

function TLspHover.HandleHover(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri, Text: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree, OwnTree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Info: THoverInfo;
  Contents: TJSONObject;
  DelphiVersion, Markdown: string;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen in ' + Method);
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  OwnTree := nil;
  if FStore.TryGet(Uri, Document) then
  begin
    Text := Document.Text;
    Shared := TSyntaxTreeCache.Get(Document, Cancellation);
    Tree := Shared.Tree;
  end
  // Nicht geöffnete Datei (Typ aus dem Atlas-Tooltip angeklickt, #588): selbst lesen.
  else if Assigned(FReadText) and FReadText(TDocumentUris.ToPath(Uri), Text) then
  begin
    OwnTree := TSyntaxTreeCache.Parse(Text, Cancellation);
    Tree := OwnTree;
  end
  else
  begin
    TRequestDiagnostics.Reason('documentNotOpen');
    Exit(TJSONNull.Create);
  end;
  try
    TRequestDiagnostics.Note('syntaxErr', Length(Tree.Diagnostics));
    if Assigned(FVersionProvider) then
      DelphiVersion := FVersionProvider(Uri)
    else
      DelphiVersion := '';
    ACancellation.ThrowIfCancellationRequested;
    // Compiler-Direktiven wie {$R+} oder {$WARN …} (#102).
    if TCompilerDirectives.HoverAt(Tree, TLspPositions.ReadPosition(PositionValue), DelphiVersion, Markdown) then
    begin
      Contents := TJSONObject.Create;
      Contents.AddPair('kind', 'markdown');
      Contents.AddPair('value', Markdown);
      Result := TJSONObject.Create;
      TJSONObject(Result).AddPair('contents', Contents);
      Exit;
    end;
    // Unbekannter Feld- oder Parametername (#461).
    if DataNameHint(Text, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue), FReadText,
      Markdown) then
    begin
      Contents := TJSONObject.Create;
      Contents.AddPair('kind', 'markdown');
      Contents.AddPair('value', Markdown);
      Result := TJSONObject.Create;
      TJSONObject(Result).AddPair('contents', Contents);
      Exit;
    end;
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := FNamespaces;
      Info := InfoAt(Resolver, FIndex, Tree, Text, TDocumentUris.ToPath(Uri),
        TLspPositions.ReadPosition(PositionValue), FReadText, DelphiVersion);
    finally
      Resolver.Free;
    end;
    if not Info.Found then
    begin
      // Seltene Schlüsselwörter und Direktiven (#187), wenn kein Symbol so heißt.
      if not TKeywordReference.HoverAt(Text, TLspPositions.ReadPosition(PositionValue), DelphiVersion,
        Markdown) then
      begin
        TRequestDiagnostics.DefaultReason('noSymbol');
        Exit(TJSONNull.Create);
      end;
      Contents := TJSONObject.Create;
      Contents.AddPair('kind', 'markdown');
      Contents.AddPair('value', Markdown);
      Result := TJSONObject.Create;
      TJSONObject(Result).AddPair('contents', Contents);
      Exit;
    end;
    Result := TJSONObject.Create;
    if FMarkdown then
    begin
      Contents := TJSONObject.Create;
      Contents.AddPair('kind', 'markdown');
      Contents.AddPair('value', Info.ToMarkdown);
      TJSONObject(Result).AddPair('contents', Contents);
    end
    else
      // Klartext als einfacher String und ohne "range", genau wie DelphiLSP
      // antwortet. RAD Studio zeigt den Hover benutzerdefinierter Server trotzdem
      // nicht als Tooltip an; dafür braucht es ein IDE-Plugin (#175).
      TJSONObject(Result).AddPair('contents', Info.ToPlainText);
    // Für den Atlas-Tooltip (#442, #588) die Teile einzeln; andere Clients ignorieren das Feld.
    TJSONObject(Result).AddPair('atlas', AtlasJson(Info));
  finally
    OwnTree.Free;
  end;
end;

end.
