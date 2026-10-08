unit BDLsp.Common.Lsp.Hover;

// Hover (textDocument/hover): Deklaration und XML-Dokumentation (///) des
// Symbols unter dem Cursor als Markdown.
//
// Die Deklaration ist die erste Zeile der Fundstelle ab ihrem Anfang. Der
// Dokumentationskommentar sind die ///-Zeilen direkt darüber; XML-Tags wie
// <summary> entfallen, <param name="X"> wird zu "X:". Bei Methoden mit
// getrennter Implementierung gilt die Deklaration (TLspDefinition).

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Semantics.NameResolver;

type
  /// <summary>Liefert den Text einer Datei; False, wenn sie nicht lesbar ist.</summary>
  THoverReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  THoverInfo = record
    Declaration: string;
    Documentation: string;
    /// <summary>Unit der Deklaration, wenn sie nicht die aktuelle ist.</summary>
    UnitName: string;
    function Found: Boolean;
    function ToMarkdown: string;
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
    function HandleHover(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: THoverReadText;
      const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Hover-Inhalt an APosition; ATreeText ist der Text von ATree.</summary>
    class function InfoAt(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ATreeText, AFileName: string; const APosition: TTextPosition;
      const AReadText: THoverReadText): THoverInfo; static;
    /// <summary>Dokumentationskommentar über ALine als Markdown; '' ohne Kommentar.</summary>
    class function DocumentationAbove(const ALines: TArray<string>; ALine: Integer): string; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

implementation

uses
  System.StrUtils,
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Lsp.Positions,
  BDLsp.Common.Lsp.Definition,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Lsp.Internals.Cancellation;

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

{ THoverInfo }

function THoverInfo.Found: Boolean;
begin
  Result := Declaration <> '';
end;

function THoverInfo.ToMarkdown: string;
begin
  Result := '```pascal' + #10 + Declaration + #10 + '```';
  if Documentation <> '' then
    Result := Result + #10#10 + Documentation;
  if UnitName <> '' then
    Result := Result + #10#10 + 'Unit `' + UnitName + '`';
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

class function TLspHover.InfoAt(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ATreeText, AFileName: string; const APosition: TTextPosition;
  const AReadText: THoverReadText): THoverInfo;
var
  Targets: TArray<TDefinitionTarget>;
  Text: string;
  Lines: TArray<string>;
  Start: TTextPosition;
  OwnerUnit: TUnitIndex;
begin
  Result := Default(THoverInfo);
  Targets := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, APosition, True);
  if Length(Targets) = 0 then
    Exit;
  if SameText(Targets[0].FileName, AFileName) then
    Text := ATreeText
  else if not (Assigned(AReadText) and AReadText(Targets[0].FileName, Text)) then
    Exit;
  Lines := SplitLines(Text);
  Start := Targets[0].Range.StartPos;
  // Unit-Namen: Ziel ist der Dateianfang.
  if (Start.Line = 0) and (Start.Character = 0) and (Targets[0].Range.EndPos = Start) and
    not SameText(Targets[0].FileName, AFileName) then
  begin
    if AIndex.FindFile(Targets[0].FileName, OwnerUnit) then
      Result.Declaration := 'unit ' + OwnerUnit.UnitName + ';';
    Result.Documentation := '`' + Targets[0].FileName + '`';
    Exit;
  end;
  if (Start.Line < 0) or (Start.Line > High(Lines)) then
    Exit;
  Result.Declaration := TrimRight(Copy(Lines[Start.Line], Start.Character + 1, MaxInt));
  Result.Documentation := DocumentationAbove(Lines, Start.Line);
  if not SameText(Targets[0].FileName, AFileName) and AIndex.FindFile(Targets[0].FileName, OwnerUnit) then
    Result.UnitName := OwnerUnit.UnitName;
end;

function TLspHover.HandleHover(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Info: THoverInfo;
  Contents: TJSONObject;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen in ' + Method);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Tree := TPascalParser.Parse(Document.Text, Cancellation);
  try
    ACancellation.ThrowIfCancellationRequested;
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := FNamespaces;
      Info := InfoAt(Resolver, FIndex, Tree, Document.Text, TDocumentUris.ToPath(Uri),
        TLspPositions.ReadPosition(PositionValue), FReadText);
    finally
      Resolver.Free;
    end;
  finally
    Tree.Free;
  end;
  if not Info.Found then
    Exit(TJSONNull.Create);
  Contents := TJSONObject.Create;
  Contents.AddPair('kind', 'markdown');
  Contents.AddPair('value', Info.ToMarkdown);
  Result := TJSONObject.Create;
  TJSONObject(Result).AddPair('contents', Contents);
end;

end.
