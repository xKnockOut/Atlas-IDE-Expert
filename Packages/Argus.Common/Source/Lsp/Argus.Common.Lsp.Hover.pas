unit Argus.Common.Lsp.Hover;

// Hover (textDocument/hover): Deklaration und XML-Dokumentation (///) des
// Symbols unter dem Cursor als Markdown.
//
// Die Deklaration ist die erste Zeile der Fundstelle ab ihrem Anfang. Der
// Dokumentationskommentar sind die ///-Zeilen direkt darüber; XML-Tags wie
// <summary> entfallen, <param name="X"> wird zu "X:". Bei Methoden mit
// getrennter Implementierung gilt die Deklaration (TLspDefinition).
// Bei Klassen folgen die published-Properties und Ereignisse samt geerbter
// (TPublishedMembers).
//
// Clients ohne Markdown (RAD Studio meldet hover.contentFormat ["plaintext"])
// bekommen denselben Inhalt als Klartext (#175).

interface

uses
  System.SysUtils,
  System.JSON,
  Argus.Common.JsonRpc.Contract,
  Argus.Common.JsonRpc.Dispatcher,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Index.Contract,
  Argus.Common.Semantics.NameResolver;

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
    /// <summary>Message-Handler der Klasse als Markdown (#36); sonst ''.</summary>
    Messages: string;
    /// <summary>Wert bei Zahlen, Konstanten und Aufzählungswerten (#38); sonst ''.</summary>
    Value: string;
    /// <summary>Hinweis bei deprecated, platform, experimental (#38); sonst ''.</summary>
    Deprecation: string;
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
    /// <summary>Antwort als Markdown (Vorgabe) oder als Klartext.</summary>
    property Markdown: Boolean read FMarkdown write FMarkdown;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
    /// <summary>Für den Release-Namen der DocWiki-Links; ohne Provider gilt die neueste Version.</summary>
    property VersionProvider: THoverVersionProvider read FVersionProvider write FVersionProvider;
  end;

implementation

uses
  System.StrUtils,
  Argus.Common.Documents.Uris,
  Argus.Common.Lsp.Positions,
  Argus.Common.Lsp.Definition,
  Argus.Common.Lsp.PublishedMembers,
  Argus.Common.Lsp.DocWiki,
  Argus.Common.Lsp.MessageHandlers,
  Argus.Common.Lsp.HoverValues,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.TreeCache,
  Argus.Common.Lsp.Internals.Cancellation;

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

// Entfernt die Auszeichnung, die Dokumentation und Mitgliederliste verwenden: `, ** und *.
function StripMarkdown(const AText: string): string;
begin
  Result := StringReplace(AText, '`', '', [rfReplaceAll]);
  Result := StringReplace(Result, '*', '', [rfReplaceAll]);
end;

{ THoverInfo }

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
  if Members <> '' then
    Result := Result + #10#10 + '---' + #10#10 + Members;
  if Messages <> '' then
    Result := Result + #10#10 + '---' + #10#10 + Messages;
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
      end;
      Exit;
    end;
  Targets := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, APosition, True);
  if Length(Targets) = 0 then
    Exit;
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
    Exit;
  Lines := SplitLines(Text);
  if (Start.Line < 0) or (Start.Line > High(Lines)) then
    Exit;
  Result.Declaration := TrimRight(Copy(Lines[Start.Line], Start.Character + 1, MaxInt));
  Result.Documentation := DocumentationAbove(Lines, Start.Line);
  Result.Deprecation := THoverValues.Deprecation(DeclarationText(Lines, Targets[0].Range));
  if not AIndex.FindFile(Targets[0].FileName, OwnerUnit) then
    Exit;
  if not SameText(Targets[0].FileName, AFileName) then
    Result.UnitName := OwnerUnit.UnitName;
  for Symbol in OwnerUnit.Symbols do
    if Symbol.SelectionRange.StartPos = Targets[0].SelectionRange.StartPos then
    begin
      Result.DocWikiUrl := TDocWiki.Url(ADelphiVersion, OwnerUnit.UnitName, Symbol.Container, Symbol.Name);
      if Symbol.Kind = TIndexSymbolKind.Constant then
        Result.Value := THoverValues.ConstantValue(Result.Declaration)
      else if Symbol.Kind = TIndexSymbolKind.EnumMember then
        Result.Value := 'Ord = ' + IntToStr(EnumOrdinal(OwnerUnit, Symbol));
      Break;
    end;
  for Symbol in OwnerUnit.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Container = '') and
      ((Symbol.Range.StartPos = Start) or (Symbol.SelectionRange.StartPos = Start)) then
    begin
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
      Break;
    end;
end;

function TLspHover.HandleHover(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Info: THoverInfo;
  Contents: TJSONObject;
  DelphiVersion: string;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen in ' + Method);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  if Assigned(FVersionProvider) then
    DelphiVersion := FVersionProvider(Uri)
  else
    DelphiVersion := '';
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := FNamespaces;
    Info := InfoAt(Resolver, FIndex, Tree, Document.Text, TDocumentUris.ToPath(Uri),
      TLspPositions.ReadPosition(PositionValue), FReadText, DelphiVersion);
  finally
    Resolver.Free;
  end;
  if not Info.Found then
    Exit(TJSONNull.Create);
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
end;

end.
