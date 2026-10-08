unit BDLsp.Common.Lsp.DocumentSymbols;

// Gliederung einer Datei für textDocument/documentSymbol: hierarchische
// DocumentSymbol-Liste aus dem Syntaxbaum. Die Wurzel ist die Unit (bzw. das
// Programm), darunter interface und implementation, darunter Typen mit ihren
// Mitgliedern, Konstanten, Variablen und Routinen.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.SyntaxTree;

type
  /// <summary>Werte für SymbolKind des LSP (Auswahl).</summary>
  TLspSymbolKind = record
  public const
    Module = 2;
    Namespace = 3;
    Class_ = 5;
    Method = 6;
    Property_ = 7;
    Field = 8;
    Constructor_ = 9;
    Enum = 10;
    Interface_ = 11;
    Function_ = 12;
    Variable = 13;
    Constant = 14;
    Object_ = 19;
    EnumMember = 22;
    Struct = 23;
    Event = 24;
    TypeParameter = 26;
  end;

  TLspDocumentSymbols = class
  public const
    Method = 'textDocument/documentSymbol';
  private
    FStore: IDocumentStore;
    function HandleDocumentSymbol(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore);
    /// <summary>Registriert die Anfrage am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Gliederung des Baums. Der Aufrufer übernimmt das Array.</summary>
    class function BuildSymbols(ATree: TSyntaxTree): TJSONArray; static;
  end;

implementation

uses
  BDLsp.Common.Dfm.Contract,
  BDLsp.Common.Dfm.Parser,
  BDLsp.Common.Lsp.FormFiles,
  BDLsp.Common.Lsp.Positions,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.TreeCache,
  BDLsp.Common.Lsp.Internals.Cancellation;

type
  /// <summary>Baut die Symbole; kennt die Token für Namensbereiche und Routinenarten.</summary>
  TSymbolBuilder = class
  private
    FTokens: TArray<TPascalToken>;
    function TokenIndexAt(AOffset: Integer): Integer;
    function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
    function NewSymbol(ANode: TSyntaxNode; const AName: string; AKind: Integer;
      const ADetail: string = ''): TJSONObject;
    procedure AddChild(ASymbol, AChild: TJSONObject);
    function RoutineKind(ANode: TSyntaxNode; AInType: Boolean): Integer;
    function TypeSymbol(ADecl: TSyntaxNode): TJSONObject;
    procedure AddDeclarations(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
    procedure AddDeclaration(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
    procedure MoveChildren(ASource: TJSONArray; ATarget: TJSONObject);
    procedure AddNames(ANode: TSyntaxNode; ATarget: TJSONArray; AKind: Integer);
  public
    constructor Create(const ATokens: TArray<TPascalToken>);
    function Build(ARoot: TSyntaxNode): TJSONArray;
  end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

{ TSymbolBuilder }

constructor TSymbolBuilder.Create(const ATokens: TArray<TPascalToken>);
begin
  inherited Create;
  FTokens := ATokens;
end;

function TSymbolBuilder.TokenIndexAt(AOffset: Integer): Integer;
var
  Left: Integer;
  Right: Integer;
  Middle: Integer;
begin
  // Erstes Token mit Offset >= AOffset (binäre Suche), sonst Length(FTokens).
  Left := 0;
  Right := Length(FTokens);
  while Left < Right do
  begin
    Middle := (Left + Right) div 2;
    if FTokens[Middle].Offset < AOffset then
      Left := Middle + 1
    else
      Right := Middle;
  end;
  Result := Left;
end;

function TSymbolBuilder.NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
var
  Index: Integer;
  Simple: string;
begin
  // Bei TFoo.Bar zeigt die Auswahl auf Bar.
  Simple := AName;
  if Simple.LastIndexOf('.') >= 0 then
    Simple := Simple.Substring(Simple.LastIndexOf('.') + 1);
  Index := TokenIndexAt(ANode.StartOffset);
  while (Index < Length(FTokens)) and (FTokens[Index].Offset < ANode.EndOffset) do
  begin
    if (FTokens[Index].Kind = TPascalTokenKind.Identifier) and
      (SameText(FTokens[Index].Text, Simple) or SameText(FTokens[Index].Text, '&' + Simple)) then
      Exit(TTextRange.Create(FTokens[Index].StartPos, FTokens[Index].EndPos));
    Inc(Index);
  end;
  Result := NodeRange(ANode);
end;

function TSymbolBuilder.NewSymbol(ANode: TSyntaxNode; const AName: string; AKind: Integer;
  const ADetail: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  // VS Code lehnt Symbole mit leerem Namen ab.
  if AName = '' then
    Result.AddPair('name', '?')
  else
    Result.AddPair('name', AName);
  if ADetail <> '' then
    Result.AddPair('detail', ADetail);
  Result.AddPair('kind', TJSONNumber.Create(AKind));
  Result.AddPair('range', TLspPositions.RangeToJson(NodeRange(ANode)));
  Result.AddPair('selectionRange', TLspPositions.RangeToJson(NameRange(ANode, AName)));
end;

procedure TSymbolBuilder.AddChild(ASymbol, AChild: TJSONObject);
var
  Children: TJSONArray;
begin
  Children := ASymbol.GetValue('children') as TJSONArray;
  if Children = nil then
  begin
    Children := TJSONArray.Create;
    ASymbol.AddPair('children', Children);
  end;
  Children.AddElement(AChild);
end;

function TSymbolBuilder.RoutineKind(ANode: TSyntaxNode; AInType: Boolean): Integer;
var
  Index: Integer;
begin
  Index := TokenIndexAt(ANode.StartOffset);
  // class procedure, class function ...: das Wort nach class zählt.
  while (Index < Length(FTokens)) and (FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Inc(Index);
  if (Index < Length(FTokens)) and FTokens[Index].IsKeyword('class') then
    Inc(Index);
  if (Index < Length(FTokens)) and (FTokens[Index].IsKeyword('constructor') or FTokens[Index].IsKeyword('destructor')) then
    Result := TLspSymbolKind.Constructor_
  else if AInType or (ANode.Name.IndexOf('.') >= 0) then
    Result := TLspSymbolKind.Method
  else
    Result := TLspSymbolKind.Function_;
end;

function TSymbolBuilder.TypeSymbol(ADecl: TSyntaxNode): TJSONObject;
var
  Body: TSyntaxNode;
  Members: TJSONArray;
  Index: Integer;
  Kind: Integer;
  Detail: string;
begin
  Body := nil;
  for Index := 0 to ADecl.ChildCount - 1 do
    if not (ADecl[Index].Kind in [TSyntaxKind.GenericParams, TSyntaxKind.Attribute]) then
    begin
      Body := ADecl[Index];
      Break;
    end;
  Kind := TLspSymbolKind.TypeParameter;
  Detail := '';
  if Body <> nil then
    case Body.Kind of
      TSyntaxKind.ClassType, TSyntaxKind.ClassOfType, TSyntaxKind.ForwardType:
        begin
          Kind := TLspSymbolKind.Class_;
          Detail := 'class';
        end;
      TSyntaxKind.ObjectType:
        begin
          Kind := TLspSymbolKind.Class_;
          Detail := 'object';
        end;
      TSyntaxKind.HelperType:
        begin
          Kind := TLspSymbolKind.Class_;
          Detail := 'helper';
        end;
      TSyntaxKind.RecordType:
        begin
          Kind := TLspSymbolKind.Struct;
          Detail := 'record';
        end;
      TSyntaxKind.InterfaceType:
        begin
          Kind := TLspSymbolKind.Interface_;
          Detail := 'interface';
        end;
      TSyntaxKind.EnumType:
        Kind := TLspSymbolKind.Enum;
    end;
  Result := NewSymbol(ADecl, ADecl.Name, Kind, Detail);
  if Body = nil then
    Exit;
  if Body.Kind = TSyntaxKind.EnumType then
  begin
    for Index := 0 to Body.ChildCount - 1 do
      if Body[Index].Kind = TSyntaxKind.Identifier then
        AddChild(Result, NewSymbol(Body[Index], Body[Index].Name, TLspSymbolKind.EnumMember));
  end
  else if Body.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.HelperType,
    TSyntaxKind.RecordType, TSyntaxKind.InterfaceType] then
  begin
    Members := TJSONArray.Create;
    try
      AddDeclarations(Body, Members, True);
      MoveChildren(Members, Result);
    finally
      Members.Free;
    end;
  end;
end;

procedure TSymbolBuilder.AddNames(ANode: TSyntaxNode; ATarget: TJSONArray; AKind: Integer);
var
  Name: string;
begin
  // Felder und Variablen mit mehreren Namen: A, B: Integer.
  for Name in ANode.Name.Split([',']) do
    ATarget.AddElement(NewSymbol(ANode, Name.Trim, AKind));
end;

procedure TSymbolBuilder.AddDeclarations(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
    AddDeclaration(ANode[Index], ATarget, AInType);
end;

procedure TSymbolBuilder.AddDeclaration(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
var
  Symbol: TJSONObject;
  Nested: TJSONArray;
  Index: Integer;
begin
  case ANode.Kind of
    TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection, TSyntaxKind.VariantPart:
      AddDeclarations(ANode, ATarget, AInType);
    TSyntaxKind.TypeDecl:
      ATarget.AddElement(TypeSymbol(ANode));
    TSyntaxKind.ConstDecl:
      ATarget.AddElement(NewSymbol(ANode, ANode.Name, TLspSymbolKind.Constant));
    TSyntaxKind.VarDecl:
      if AInType then
        AddNames(ANode, ATarget, TLspSymbolKind.Field)
      else
        AddNames(ANode, ATarget, TLspSymbolKind.Variable);
    TSyntaxKind.Field:
      AddNames(ANode, ATarget, TLspSymbolKind.Field);
    TSyntaxKind.PropertyDecl:
      ATarget.AddElement(NewSymbol(ANode, ANode.Name, TLspSymbolKind.Property_));
    TSyntaxKind.RoutineHeader:
      ATarget.AddElement(NewSymbol(ANode, ANode.Name, RoutineKind(ANode, AInType)));
    TSyntaxKind.RoutineDecl:
      begin
        Symbol := NewSymbol(ANode, ANode.Name, RoutineKind(ANode, AInType));
        ATarget.AddElement(Symbol);
        // Lokale Routinen, Typen und Konstanten unter der Routine. Der eigene
        // Kopf ist ebenfalls ein Kind und darf nicht noch einmal erscheinen.
        Nested := TJSONArray.Create;
        try
          for Index := 0 to ANode.ChildCount - 1 do
            if ANode[Index].Kind <> TSyntaxKind.RoutineHeader then
              AddDeclaration(ANode[Index], Nested, False);
          MoveChildren(Nested, Symbol);
        finally
          Nested.Free;
        end;
      end;
  end;
end;

procedure TSymbolBuilder.MoveChildren(ASource: TJSONArray; ATarget: TJSONObject);
begin
  while ASource.Count > 0 do
    AddChild(ATarget, TJSONObject(ASource.Remove(0)));
end;

function TSymbolBuilder.Build(ARoot: TSyntaxNode): TJSONArray;
var
  Root: TJSONObject;
  Section: TJSONObject;
  Items: TJSONArray;
  Index: Integer;
  Child: TSyntaxNode;
begin
  Result := TJSONArray.Create;
  Root := NewSymbol(ARoot, ARoot.Name, TLspSymbolKind.Module);
  Result.AddElement(Root);
  Items := TJSONArray.Create;
  try
    for Index := 0 to ARoot.ChildCount - 1 do
    begin
      Child := ARoot[Index];
      if Child.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
      begin
        if Child.Kind = TSyntaxKind.InterfaceSection then
          Section := NewSymbol(Child, 'interface', TLspSymbolKind.Namespace)
        else
          Section := NewSymbol(Child, 'implementation', TLspSymbolKind.Namespace);
        AddChild(Root, Section);
        AddDeclarations(Child, Items, False);
        MoveChildren(Items, Section);
      end
      else
      begin
        // program, library, package: Deklarationen direkt unter der Wurzel.
        AddDeclaration(Child, Items, False);
        MoveChildren(Items, Root);
      end;
    end;
  finally
    Items.Free;
  end;
end;

{ TLspDocumentSymbols }

constructor TLspDocumentSymbols.Create(const AStore: IDocumentStore);
begin
  inherited Create;
  FStore := AStore;
end;

procedure TLspDocumentSymbols.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  // Nebenläufig: Parsen großer Dateien blockiert die Nachrichtenschleife nicht.
  ADispatcher.RegisterConcurrentRequest(Method, HandleDocumentSymbol);
end;

class function TLspDocumentSymbols.BuildSymbols(ATree: TSyntaxTree): TJSONArray;
var
  Builder: TSymbolBuilder;
begin
  Builder := TSymbolBuilder.Create(ATree.Tokens);
  try
    Result := Builder.Build(ATree.Root);
  finally
    Builder.Free;
  end;
end;

function TLspDocumentSymbols.HandleDocumentSymbol(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Form: TDfmDocument;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "textDocument.uri" fehlt in ' + Method);
  // Nicht geöffnete Dokumente haben keine Gliederung.
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  // Formulardateien (#44) haben einen eigenen Baum.
  if TDfmParser.IsFormFile(Uri) then
  begin
    Form := TDfmParser.Parse(Document.Text);
    try
      Exit(TLspFormFiles.BuildSymbols(Form));
    finally
      Form.Free;
    end;
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Result := BuildSymbols(Tree);
end;

end.
