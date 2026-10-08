unit BDLsp.Common.Lsp.References;

// Referenzsuche (textDocument/references, #29): alle Stellen im Projekt, die
// zur selben Deklaration auflösen wie der Bezeichner unter dem Cursor.
//
// Durchsucht werden die Projektdateien und die geöffneten Dokumente; Dateien,
// in denen der Name nicht einmal als Text vorkommt, werden nicht geparst.
// Steht die Deklaration in einer Unit mit Formular, zählen auch Verweise aus
// der .dfm daneben: Ereignis-Handler (OnClick = Button1Click) und
// Komponentennamen (object Button1: TButton).

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Semantics.NameResolver,
  BDLsp.Common.Lsp.Definition;

type
  TReferenceLocation = record
    FileName: string;
    Range: TTextRange;
  end;

  /// <summary>Text einer Datei, geöffnete Dokumente zuerst; False, wenn sie nicht lesbar ist.</summary>
  TReferenceReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Dateien des Projekts, die nach Verweisen durchsucht werden.</summary>
  TReferenceFilesProvider = reference to function: TArray<string>;

  TLspReferences = class
  public const
    Method = 'textDocument/references';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: TReferenceReadText;
    FFiles: TReferenceFilesProvider;
    FNamespaces: TArray<string>;
    function HandleReferences(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Stellen in ATree, die zu AWanted auflösen; AName ohne &amp;.</summary>
    class function InTree(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName, AName: string; const AWanted: TDefinitionTarget;
      const ACancellation: IJsonRpcCancellationToken = nil): TArray<TTextRange>; static;
    /// <summary>Ereignis-Handler und Komponentennamen AName in einer Formulardatei (Textformat).</summary>
    class function InDfm(const ADfmText, AName: string): TArray<TTextRange>; static;
    /// <summary>Alle Verweise auf das Symbol an APosition; mit ADeclaration auch die Deklaration selbst.</summary>
    class function Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean;
      const AFiles: TArray<string>; const AReadText: TReferenceReadText;
      const ACancellation: IJsonRpcCancellationToken = nil): TArray<TReferenceLocation>; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

implementation

uses
  System.StrUtils,
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Lsp.Positions,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Lsp.Internals.Cancellation;

function CleanName(const AText: string): string;
begin
  // &Begin → Begin
  if (AText <> '') and (AText[1] = '&') then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

function TokenAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  Index: Integer;
  Token: TPascalToken;
begin
  for Index := 0 to High(ATokens) do
  begin
    Token := ATokens[Index];
    if (Token.StartPos.Line > APosition.Line) or
      ((Token.StartPos.Line = APosition.Line) and (Token.StartPos.Character > APosition.Character)) then
      Break;
    // Cursor auf oder direkt hinter dem Bezeichner.
    if (Token.Kind = TPascalTokenKind.Identifier) and (Token.EndPos.Line = APosition.Line) and
      (APosition.Character <= Token.EndPos.Character) then
      Exit(Index);
  end;
  Result := -1;
end;

function SameTarget(const A, B: TDefinitionTarget): Boolean;
begin
  Result := SameText(A.FileName, B.FileName) and (A.SelectionRange.StartPos = B.SelectionRange.StartPos);
end;

function SplitLines(const AText: string): TArray<string>;
var
  I, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for I := 1 to Length(AText) + 1 do
    if (I > Length(AText)) or (AText[I] = #10) then
    begin
      Result := Result + [Copy(AText, Start, I - Start)];
      Start := I + 1;
    end;
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

{ TLspReferences }

constructor TLspReferences.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FFiles := AFiles;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspReferences.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleReferences);
end;

class function TLspReferences.InTree(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, AName: string; const AWanted: TDefinitionTarget;
  const ACancellation: IJsonRpcCancellationToken): TArray<TTextRange>;
var
  Token: TPascalToken;
  Candidate: TArray<TDefinitionTarget>;
begin
  Result := nil;
  for Token in ATree.Tokens do
  begin
    if (Token.Kind <> TPascalTokenKind.Identifier) or not SameText(CleanName(Token.Text), AName) then
      Continue;
    if ACancellation <> nil then
      ACancellation.ThrowIfCancellationRequested;
    Candidate := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, Token.StartPos, True);
    if (Length(Candidate) > 0) and SameTarget(Candidate[0], AWanted) then
      Result := Result + [TTextRange.Create(Token.StartPos, Token.EndPos)];
  end;
end;

class function TLspReferences.InDfm(const ADfmText, AName: string): TArray<TTextRange>;

  // Position und Länge des ersten Bezeichners ab AFrom (1-basiert).
  function NextIdent(const ALine: string; AFrom: Integer; out AStart, ALength: Integer): string;
  begin
    AStart := AFrom;
    while (AStart <= Length(ALine)) and not IsIdentChar(ALine[AStart]) do
      Inc(AStart);
    ALength := 0;
    while (AStart + ALength <= Length(ALine)) and IsIdentChar(ALine[AStart + ALength]) do
      Inc(ALength);
    Result := Copy(ALine, AStart, ALength);
  end;

var
  Lines: TArray<string>;
  LineIndex, Start, Len, Eq: Integer;
  Line, Word: string;
begin
  Result := nil;
  Lines := SplitLines(StringReplace(ADfmText, #13, '', [rfReplaceAll]));
  for LineIndex := 0 to High(Lines) do
  begin
    Line := Lines[LineIndex];
    Word := NextIdent(Line, 1, Start, Len);
    if SameText(Word, 'object') or SameText(Word, 'inherited') or SameText(Word, 'inline') then
    begin
      // object Button1: TButton
      Word := NextIdent(Line, Start + Len, Start, Len);
      if SameText(Word, AName) and (Pos(':', Copy(Line, Start + Len, MaxInt)) > 0) then
        Result := Result + [TTextRange.Create(TTextPosition.Create(LineIndex, Start - 1),
          TTextPosition.Create(LineIndex, Start - 1 + Len))];
    end
    else if StartsText('On', Word) then
    begin
      // OnClick = Button1Click
      Eq := Pos('=', Line);
      if (Eq > Start + Len - 1) and (Trim(Copy(Line, Start + Len, Eq - Start - Len)) = '') then
      begin
        Word := NextIdent(Line, Eq + 1, Start, Len);
        if SameText(Word, AName) and (Trim(Copy(Line, Start + Len, MaxInt)) = '') then
          Result := Result + [TTextRange.Create(TTextPosition.Create(LineIndex, Start - 1),
            TTextPosition.Create(LineIndex, Start - 1 + Len))];
      end;
    end;
  end;
end;

class function TLspReferences.Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean;
  const AFiles: TArray<string>; const AReadText: TReferenceReadText;
  const ACancellation: IJsonRpcCancellationToken): TArray<TReferenceLocation>;

  procedure Add(const AFile: string; const ARanges: TArray<TTextRange>);
  var
    Range: TTextRange;
    Location: TReferenceLocation;
  begin
    for Range in ARanges do
    begin
      Location.FileName := AFile;
      Location.Range := Range;
      Result := Result + [Location];
    end;
  end;

var
  Index: Integer;
  Name, FileName, Text, DfmName: string;
  Wanted: TArray<TDefinitionTarget>;
  Searched: TArray<string>;
  Tree: TSyntaxTree;
  Filtered: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
begin
  Result := nil;
  Index := TokenAt(ATree.Tokens, APosition);
  if Index < 0 then
    Exit;
  Wanted := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, APosition, True);
  if Length(Wanted) = 0 then
    Exit;
  Name := CleanName(ATree.Tokens[Index].Text);
  Add(AFileName, InTree(AResolver, AIndex, ATree, AFileName, Name, Wanted[0], ACancellation));
  Searched := [AFileName];
  for FileName in AFiles do
  begin
    if IndexText(FileName, Searched) >= 0 then
      Continue;
    Searched := Searched + [FileName];
    if not (Assigned(AReadText) and AReadText(FileName, Text)) or not ContainsText(Text, Name) then
      Continue;
    Tree := TPascalParser.Parse(Text);
    try
      Add(FileName, InTree(AResolver, AIndex, Tree, FileName, Name, Wanted[0], ACancellation));
    finally
      Tree.Free;
    end;
  end;
  // Formular zur Unit der Deklaration.
  DfmName := ChangeFileExt(Wanted[0].FileName, '.dfm');
  if Assigned(AReadText) and AReadText(DfmName, Text) then
    Add(DfmName, InDfm(Text, Name));
  if ADeclaration then
    Exit;
  Filtered := nil;
  for Location in Result do
    if not (SameText(Location.FileName, Wanted[0].FileName) and
      (Location.Range.StartPos = Wanted[0].SelectionRange.StartPos)) then
      Filtered := Filtered + [Location];
  Result := Filtered;
end;

function TLspReferences.HandleReferences(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  IncludeDeclaration: Boolean;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Files: TArray<string>;
  Found: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
  Item: TJSONObject;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen in ' + Method);
  if not TJSONObject(AParams).TryGetValue<Boolean>('context.includeDeclaration', IncludeDeclaration) then
    IncludeDeclaration := True;
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  Files := nil;
  if Assigned(FFiles) then
    Files := FFiles();
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Tree := TPascalParser.Parse(Document.Text, Cancellation);
  try
    ACancellation.ThrowIfCancellationRequested;
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := FNamespaces;
      Found := Find(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue),
        IncludeDeclaration, Files, FReadText, ACancellation);
    finally
      Resolver.Free;
    end;
  finally
    Tree.Free;
  end;
  Result := TJSONArray.Create;
  for Location in Found do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('uri', TDocumentUris.FromPath(Location.FileName));
    Item.AddPair('range', TLspPositions.RangeToJson(Location.Range));
    TJSONArray(Result).AddElement(Item);
  end;
end;

end.
