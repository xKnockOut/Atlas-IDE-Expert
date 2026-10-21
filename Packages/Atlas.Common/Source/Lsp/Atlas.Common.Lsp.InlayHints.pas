unit Atlas.Common.Lsp.InlayHints;

// Inlay Hints (textDocument/inlayHint):
//   - Parameternamen vor den Argumenten eines Aufrufs (über die Parameterhilfe, #32);
//     entfällt, wenn das Argument schon so heißt,
//   - abgeleiteter Typ hinter var X := … (Literale, Konstruktoren, Funktionen, Variablen),
//   - Endmarkierungen hinter dem end langer Blöcke: Routine, Typ, if/while/for/with/case/try.
// Was erscheint, steuert "inlayHints" in atlas.json.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Hover;

type
  TInlayHint = record
    Position: TTextPosition;
    Text: string;
    /// <summary>InlayHintKind des LSP: 1 Typ, 2 Parameter, 0 ohne.</summary>
    Kind: Integer;
    PaddingLeft: Boolean;
    PaddingRight: Boolean;
  end;

  /// <summary>Einstellungen für das Dokument AUri.</summary>
  TInlayHintSettingsProvider = reference to function(const AUri: string): TInlayHintSettings;

  TLspInlayHints = class
  public const
    Method = 'textDocument/inlayHint';
    MaxLabelLength = 50;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: THoverReadText;
    FSettings: TInlayHintSettingsProvider;
    FNamespaces: TArray<string>;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: THoverReadText;
      const ASettings: TInlayHintSettingsProvider; const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    class function ParameterNames(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ATreeText, AFileName: string; const ARange: TTextRange; const AReadText: THoverReadText): TArray<TInlayHint>; static;
    class function InferredTypes(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const ARange: TTextRange): TArray<TInlayHint>; static;
    class function EndMarkers(ATree: TSyntaxTree; const ARange: TTextRange; AMinLines: Integer): TArray<TInlayHint>; static;
    /// <summary>Alle eingeschalteten Hinweise in ARange, nach Position sortiert.</summary>
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ATreeText, AFileName: string; const ARange: TTextRange; const ASettings: TInlayHintSettings;
      const AReadText: THoverReadText): TArray<TInlayHint>; static;
    /// <summary>InlayHint[] des LSP. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AHints: TArray<TInlayHint>): TJSONArray; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.SignatureHelp,
  Atlas.Common.Lsp.Internals.Cancellation;

type
  TSyntaxKinds = set of TSyntaxKind;

const
  KindType = 1;
  KindParameter = 2;
  ParameterModifiers: array[0..4] of string = ('const ', 'var ', 'out ', 'constref ', '[ref] ');

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

function InRange(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := (ComparePositions(ARange.StartPos, APosition) <= 0) and (ComparePositions(APosition, ARange.EndPos) <= 0);
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

/// <summary>Index des ersten Tokens mit Offset >= AOffset.</summary>
function FirstTokenAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(ATokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if ATokens[Middle].Offset < AOffset then
      Low := Middle + 1
    else
      High := Middle;
  end;
  Result := Low;
end;

procedure CollectNodes(ANode: TSyntaxNode; const AKinds: TSyntaxKinds; AList: TList<TSyntaxNode>);
var
  Index: Integer;
begin
  if ANode.Kind in AKinds then
    AList.Add(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
    CollectNodes(ANode[Index], AKinds, AList);
end;

/// <summary>Parametername aus "const A: Integer = 1" bzw. "A".</summary>
function ParameterName(const AText: string): string;
var
  Modifier: string;
  Colon: Integer;
begin
  Result := Trim(AText);
  for Modifier in ParameterModifiers do
    if StartsText(Modifier, Result) then
      Delete(Result, 1, Length(Modifier));
  Colon := Pos(':', Result);
  if Colon > 0 then
    Result := Copy(Result, 1, Colon - 1);
  Colon := Pos('=', Result);
  if Colon > 0 then
    Result := Copy(Result, 1, Colon - 1);
  Result := Trim(Result);
end;

/// <summary>Kopfzeile eines Blocks als Text, z. B. "if Assigned(FTheme)".</summary>
function HeaderText(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): string;
var
  Index: Integer;
  Token: TPascalToken;
  Glue, AfterName: Boolean;
begin
  Result := '';
  Glue := True;
  AfterName := False;
  for Index := AFirst to ALast do
  begin
    Token := ATokens[Index];
    if IsTrivia(Token) then
      Continue;
    if Token.IsKeyword('then') or Token.IsKeyword('do') or Token.IsKeyword('of') then
      Break;
    // Kein Leerzeichen nach ( [ . und vor ) ] , . ; sowie zwischen Name und Aufrufklammer.
    if not (Glue or Token.IsSymbol(')') or Token.IsSymbol(']') or Token.IsSymbol(',') or Token.IsSymbol('.') or
      Token.IsSymbol(';') or AfterName and (Token.IsSymbol('(') or Token.IsSymbol('['))) then
      Result := Result + ' ';
    Result := Result + Token.Text;
    Glue := Token.IsSymbol('(') or Token.IsSymbol('[') or Token.IsSymbol('.');
    AfterName := Token.Kind = TPascalTokenKind.Identifier;
    if Length(Result) > TLspInlayHints.MaxLabelLength then
      Exit(Copy(Result, 1, TLspInlayHints.MaxLabelLength) + '…');
  end;
end;

{ TLspInlayHints }

function TLspInlayHints.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspInlayHints.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspInlayHints.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText; const ASettings: TInlayHintSettingsProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FSettings := ASettings;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspInlayHints.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
end;

class function TLspInlayHints.ParameterNames(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const ATreeText, AFileName: string; const ARange: TTextRange;
  const AReadText: THoverReadText): TArray<TInlayHint>;
var
  Tokens: TArray<TPascalToken>;
  Blocks: TList<TSyntaxNode>;
  Block: TSyntaxNode;
  Index, Open, Scan, Depth, Argument, Last: Integer;
  Starts: TList<Integer>;
  InBlock: Boolean;
  Help: TSignatureHelp;
  Signature: TSignature;
  Chosen: Integer;
  Name: string;
  Hint: TInlayHint;
  List: TList<TInlayHint>;
begin
  Tokens := ATree.Tokens;
  Blocks := TList<TSyntaxNode>.Create;
  Starts := TList<Integer>.Create;
  List := TList<TInlayHint>.Create;
  try
    // Nur Anweisungen: Köpfe von Routinen haben auch Bezeichner vor "(".
    CollectNodes(ATree.Root, [TSyntaxKind.Block], Blocks);
    for Index := 0 to High(Tokens) - 1 do
    begin
      if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
        Continue;
      Open := NextToken(Tokens, Index);
      if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('(') or not InRange(ARange, Tokens[Open].EndPos) then
        Continue;
      InBlock := False;
      for Block in Blocks do
        if (Block.StartOffset <= Tokens[Index].Offset) and (Tokens[Index].Offset < Block.EndOffset) then
        begin
          InBlock := True;
          Break;
        end;
      if not InBlock then
        Continue;
      // Argumente bis zur passenden Klammer.
      Starts.Clear;
      Depth := 0;
      Scan := NextToken(Tokens, Open);
      if (Scan <= High(Tokens)) and not Tokens[Scan].IsSymbol(')') then
        Starts.Add(Scan);
      while Scan <= High(Tokens) do
      begin
        if Tokens[Scan].IsSymbol('(') or Tokens[Scan].IsSymbol('[') then
          Inc(Depth)
        else if Tokens[Scan].IsSymbol(')') or Tokens[Scan].IsSymbol(']') then
        begin
          if Depth = 0 then
            Break;
          Dec(Depth);
        end
        else if (Depth = 0) and Tokens[Scan].IsSymbol(',') then
          Starts.Add(NextToken(Tokens, Scan))
        else if (Depth = 0) and Tokens[Scan].IsSymbol(';') then
          Break;
        Scan := NextToken(Tokens, Scan);
      end;
      if Starts.Count = 0 then
        Continue;
      Help := TLspSignatureHelp.HelpAt(AResolver, AIndex, ATree, ATreeText, AFileName, Tokens[Open].EndPos, AReadText);
      // Parameternamen der Compiler-Routinen (Assigned(P), Inc(X) ...) sagen nichts: keine Hinweise (#880).
      if Help.Intrinsic then
        Help.Signatures := nil;
      Chosen := -1;
      for Scan := 0 to High(Help.Signatures) do
        if Length(Help.Signatures[Scan].Parameters) >= Starts.Count then
        begin
          Chosen := Scan;
          Break;
        end;
      if Chosen < 0 then
        Continue;
      Signature := Help.Signatures[Chosen];
      for Argument := 0 to Starts.Count - 1 do
      begin
        Scan := Starts[Argument];
        if Scan > High(Tokens) then
          Continue;
        Name := ParameterName(Copy(Signature.Text, Signature.Parameters[Argument].StartIndex + 1,
          Signature.Parameters[Argument].EndIndex - Signature.Parameters[Argument].StartIndex));
        if Name = '' then
          Continue;
        // Argument heißt schon wie der Parameter (auch Self.Name, FName).
        Last := Scan;
        while (NextToken(Tokens, Last) <= High(Tokens)) and Tokens[NextToken(Tokens, Last)].IsSymbol('.') and
          (NextToken(Tokens, NextToken(Tokens, Last)) <= High(Tokens)) and
          (Tokens[NextToken(Tokens, NextToken(Tokens, Last))].Kind = TPascalTokenKind.Identifier) do
          Last := NextToken(Tokens, NextToken(Tokens, Last));
        if (Tokens[Last].Kind = TPascalTokenKind.Identifier) and
          (SameText(CleanName(Tokens[Last].Text), Name) or SameText(CleanName(Tokens[Last].Text), 'F' + Name) or
          SameText(CleanName(Tokens[Last].Text), 'A' + Name)) then
          Continue;
        Hint := Default(TInlayHint);
        Hint.Position := Tokens[Scan].StartPos;
        Hint.Text := Name + ':';
        Hint.Kind := KindParameter;
        Hint.PaddingRight := True;
        List.Add(Hint);
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Starts.Free;
    Blocks.Free;
  end;
end;

class function TLspInlayHints.InferredTypes(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const ARange: TTextRange): TArray<TInlayHint>;
var
  Tokens: TArray<TPascalToken>;
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Index, NameToken, Assign, First, Last, Scan, Depth: Integer;
  TypeName: string;
  Resolved: TResolvedSymbol;
  Hint: TInlayHint;
  List: TList<TInlayHint>;
  Typed: Boolean;
begin
  Tokens := ATree.Tokens;
  Nodes := TList<TSyntaxNode>.Create;
  List := TList<TInlayHint>.Create;
  try
    CollectNodes(ATree.Root, [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst], Nodes);
    for Node in Nodes do
    begin
      if not InRange(ARange, Node.StartPos) or (Pos(',', Node.Name) > 0) then
        Continue;
      // var X := …: Name, dann ":=" ohne ":" davor.
      NameToken := -1;
      Assign := -1;
      Typed := False;
      Index := FirstTokenAt(Tokens, Node.StartOffset);
      while (Index <= High(Tokens)) and (Tokens[Index].Offset < Node.EndOffset) do
      begin
        if (NameToken < 0) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
          NameToken := Index
        else if Tokens[Index].IsSymbol(':') then
          Typed := True
        else if Tokens[Index].IsSymbol(':=') then
        begin
          Assign := Index;
          Break;
        end;
        Inc(Index);
      end;
      if Typed or (NameToken < 0) or (Assign < 0) then
        Continue;
      First := NextToken(Tokens, Assign);
      Last := First;
      while (NextToken(Tokens, Last) <= High(Tokens)) and (Tokens[NextToken(Tokens, Last)].Offset < Node.EndOffset) and
        not Tokens[NextToken(Tokens, Last)].IsSymbol(';') do
        Last := NextToken(Tokens, Last);
      if First > High(Tokens) then
        Continue;
      TypeName := '';
      if First = Last then
        case Tokens[First].Kind of
          TPascalTokenKind.Number:
            if (Tokens[First].Text[1] <> '$') and (Tokens[First].Text[1] <> '%') and
              ((Pos('.', Tokens[First].Text) > 0) or (Pos('e', LowerCase(Tokens[First].Text)) > 0)) then
              TypeName := 'Extended'
            else
              TypeName := 'Integer';
          TPascalTokenKind.StringLiteral:
            if (Length(Tokens[First].Text) = 3) or (Tokens[First].Text = '''''''''') then
              TypeName := 'Char'
            else
              TypeName := 'string';
          TPascalTokenKind.CharLiteral:
            TypeName := 'Char';
          TPascalTokenKind.Identifier:
            if SameText(Tokens[First].Text, 'True') or SameText(Tokens[First].Text, 'False') then
              TypeName := 'Boolean';
        end;
      if (TypeName = '') and (Tokens[First].Kind = TPascalTokenKind.Identifier) then
      begin
        // Kette A.B.C, optional mit einem Aufruf (…) am Ende, sonst nichts.
        Scan := First;
        while (NextToken(Tokens, Scan) <= Last) and Tokens[NextToken(Tokens, Scan)].IsSymbol('.') and
          (NextToken(Tokens, NextToken(Tokens, Scan)) <= Last) and
          (Tokens[NextToken(Tokens, NextToken(Tokens, Scan))].Kind = TPascalTokenKind.Identifier) do
          Scan := NextToken(Tokens, NextToken(Tokens, Scan));
        Index := Scan;
        if (Index < Last) and Tokens[NextToken(Tokens, Index)].IsSymbol('(') then
        begin
          Depth := 0;
          Index := NextToken(Tokens, Index);
          while Index <= Last do
          begin
            if Tokens[Index].IsSymbol('(') then
              Inc(Depth)
            else if Tokens[Index].IsSymbol(')') then
            begin
              Dec(Depth);
              if Depth = 0 then
                Break;
            end;
            Index := NextToken(Tokens, Index);
          end;
        end;
        if Index = Last then
        begin
          Resolved := AResolver.Resolve(ATree, AFileName, Tokens[Scan].StartPos);
          if Resolved.Found and (Resolved.Kind <> TResolvedKind.UnitName) then
            if Resolved.SymbolKind = TIndexSymbolKind.Constructor_ then
              TypeName := Resolved.Container
            else if Resolved.IsType then
              // Typumwandlung TFoo(X)
              TypeName := Resolved.Name
            else if Resolved.TypeName <> '' then
              TypeName := Resolved.TypeName
            else if Resolved.SymbolKind = TIndexSymbolKind.EnumMember then
              // Enum-Werte stehen im Index unter ihrem Typ.
              TypeName := Resolved.Container;
        end;
      end;
      if TypeName = '' then
        Continue;
      Hint := Default(TInlayHint);
      Hint.Position := Tokens[NameToken].EndPos;
      Hint.Text := ': ' + TypeName;
      Hint.Kind := KindType;
      List.Add(Hint);
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Nodes.Free;
  end;
end;

class function TLspInlayHints.EndMarkers(ATree: TSyntaxTree; const ARange: TTextRange;
  AMinLines: Integer): TArray<TInlayHint>;
var
  Tokens: TArray<TPascalToken>;
  Nodes: TList<TSyntaxNode>;
  Node, Body: TSyntaxNode;
  EndToken, Next, First: Integer;
  Text: string;
  Hint: TInlayHint;
  List: TList<TInlayHint>;
begin
  Tokens := ATree.Tokens;
  Nodes := TList<TSyntaxNode>.Create;
  List := TList<TInlayHint>.Create;
  try
    CollectNodes(ATree.Root, [TSyntaxKind.RoutineDecl, TSyntaxKind.TypeDecl, TSyntaxKind.IfStatement,
      TSyntaxKind.WhileStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WithStatement,
      TSyntaxKind.CaseStatement, TSyntaxKind.TryStatement], Nodes);
    for Node in Nodes do
    begin
      if Node.EndPos.Line - Node.StartPos.Line + 1 < AMinLines then
        Continue;
      // Letztes Token des Knotens muss "end" sein (bei Routinen das des Rumpfs).
      Body := Node;
      if Node.Kind = TSyntaxKind.RoutineDecl then
      begin
        Body := Node.FindChild(TSyntaxKind.Block);
        if Body = nil then
          Continue;
      end;
      EndToken := FirstTokenAt(Tokens, Body.EndOffset) - 1;
      while (EndToken >= 0) and (IsTrivia(Tokens[EndToken]) or Tokens[EndToken].IsSymbol(';')) do
        Dec(EndToken);
      if (EndToken < 0) or not Tokens[EndToken].IsKeyword('end') then
        Continue;
      case Node.Kind of
        TSyntaxKind.RoutineDecl, TSyntaxKind.TypeDecl:
          Text := Node.Name;
        TSyntaxKind.TryStatement:
          Text := 'try';
      else
        First := FirstTokenAt(Tokens, Node.StartOffset);
        Text := HeaderText(Tokens, First, EndToken);
      end;
      if Text = '' then
        Continue;
      Hint := Default(TInlayHint);
      Hint.Position := Tokens[EndToken].EndPos;
      Next := NextToken(Tokens, EndToken);
      if (Next <= High(Tokens)) and (Tokens[Next].IsSymbol(';') or Tokens[Next].IsSymbol('.')) and
        (Tokens[Next].StartPos.Line = Tokens[EndToken].EndPos.Line) then
        Hint.Position := Tokens[Next].EndPos;
      if not InRange(ARange, Hint.Position) then
        Continue;
      Hint.Text := '// ' + Text;
      Hint.PaddingLeft := True;
      List.Add(Hint);
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Nodes.Free;
  end;
end;

function CompareHints(const A, B: TInlayHint): Integer;
begin
  Result := ComparePositions(A.Position, B.Position);
end;

class function TLspInlayHints.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ATreeText, AFileName: string; const ARange: TTextRange; const ASettings: TInlayHintSettings;
  const AReadText: THoverReadText): TArray<TInlayHint>;
var
  List: TList<TInlayHint>;
begin
  List := TList<TInlayHint>.Create(TComparer<TInlayHint>.Construct(CompareHints));
  try
    if ASettings.ParameterNames then
      List.AddRange(ParameterNames(AResolver, AIndex, ATree, ATreeText, AFileName, ARange, AReadText));
    if ASettings.InferredTypes then
      List.AddRange(InferredTypes(AResolver, ATree, AFileName, ARange));
    if ASettings.EndMarkers then
      List.AddRange(EndMarkers(ATree, ARange, ASettings.EndMarkerMinLines));
    List.Sort;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

class function TLspInlayHints.ToJson(const AHints: TArray<TInlayHint>): TJSONArray;
var
  Hint: TInlayHint;
  Entry: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Hint in AHints do
  begin
    Entry := TJSONObject.Create;
    Result.AddElement(Entry);
    Entry.AddPair('position', TLspPositions.PositionToJson(Hint.Position));
    Entry.AddPair('label', Hint.Text);
    if Hint.Kind <> 0 then
      Entry.AddPair('kind', TJSONNumber.Create(Hint.Kind));
    if Hint.PaddingLeft then
      Entry.AddPair('paddingLeft', TJSONBool.Create(True));
    if Hint.PaddingRight then
      Entry.AddPair('paddingRight', TJSONBool.Create(True));
  end;
end;

function TLspInlayHints.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  RangeValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Settings: TInlayHintSettings;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('range', RangeValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Felder "textDocument.uri" und "range" fehlen');
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  if Assigned(FSettings) then
    Settings := FSettings(Uri)
  else
    Settings := TInlayHintSettings.Default;
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := Namespaces;
    Result := ToJson(Collect(Resolver, FIndex, Tree, Document.Text, TDocumentUris.ToPath(Uri),
      TLspPositions.ReadRange(RangeValue), Settings, FReadText));
  finally
    Resolver.Free;
  end;
end;

end.
