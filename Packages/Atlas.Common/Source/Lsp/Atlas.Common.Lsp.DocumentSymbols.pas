unit Atlas.Common.Lsp.DocumentSymbols;

// Gliederung einer Datei für textDocument/documentSymbol: hierarchische
// DocumentSymbol-Liste aus dem Syntaxbaum. Die Wurzel ist die Unit (bzw. das
// Programm), darunter interface und implementation, darunter Typen mit ihren
// Mitgliedern, Konstanten, Variablen und Routinen.
//
// Für das Gliederungsfenster des Plugins (#537) tragen Symbole zusätzlich ein
// Objekt "atlas" (vom LSP nicht vorgesehen, andere Clients übergehen es):
//   - visibility: Sichtbarkeit von Mitgliedern ("private", "strict protected",
//     …). Ohne Angabe gilt bei Klassen mit Vorfahr (außer TObject,
//     TInterfacedObject und Ausnahmen) "published" wie bei {$M+}-Klassen
//     (Formulare, Komponenten), sonst "public".
//   - classMember, override, virtual, abstract: nur wenn wahr.
//   - unimplemented: deklarierte Methode ohne Rumpf (#124, TClassCompletion).
//   - condition: Bedingung des aktiven {$IFDEF}-Zweigs, in dem das Symbol steht
//     (nur das äußerste Symbol im Zweig) oder in dem der Rumpf einer Routine
//     steht (#845), z. B. "CPUX64".
//
// Variante Teile eines Records (#846): ein benanntes Selektorfeld steht wie die
// übrigen Felder im Record, die Zweige bilden eine Gruppe "case Integer of"
// (SymbolKind Namespace) mit allen ihren Feldern; ein verschachtelter Teil ist
// eine eigene Gruppe darin.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Lsp.TypeInfoClasses;

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
    FIndex: ISymbolIndex;
    FReadText: TTypeInfoReadText;
    function HandleDocumentSymbol(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore);
    /// <summary>Registriert die Anfrage am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Gliederung des Baums. Der Aufrufer übernimmt das Array.</summary>
    class function BuildSymbols(ATree: TSyntaxTree): TJSONArray; overload; static;
    /// <summary>Wie oben; markiert zusätzlich deklarierte Methoden ohne Rumpf (#124, #537) aus AText.</summary>
    class function BuildSymbols(ATree: TSyntaxTree; const AText: string): TJSONArray; overload; static;
    /// <summary>Wie oben; die Standardsichtbarkeit (published bei {$M+}-Klassen, #537) folgt den Vorfahren über
    /// AIndex und liest deren Dateien mit AReadText (beide dürfen nil sein).</summary>
    class function BuildSymbols(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
      const AReadText: TTypeInfoReadText): TJSONArray; overload; static;
    /// <summary>Wie oben; AConditionals sind die Zweige der Datei für atlas.condition (#845).</summary>
    class function BuildSymbols(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
      const AReadText: TTypeInfoReadText; const AConditionals: TArray<TConditionalRange>): TJSONArray;
      overload; static;
    /// <summary>Symbolindex für die Vorfahren (#537); ohne gelten nur die bekannten Klassen der RTL/VCL/FMX.</summary>
    property Index: ISymbolIndex read FIndex write FIndex;
    /// <summary>Liest die Datei eines Vorfahren aus dem Index.</summary>
    property ReadText: TTypeInfoReadText read FReadText write FReadText;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Lsp.FormFiles,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation;

type
  /// <summary>Baut die Symbole; kennt die Token für Namensbereiche und Routinenarten.</summary>
  TSymbolBuilder = class
  private
    FTokens: TArray<TPascalToken>;
    /// <summary>Aktuelle Sichtbarkeit in einem Typ; '' außerhalb.</summary>
    FVisibility: string;
    /// <summary>Namensanfang deklarierter Methoden ohne Rumpf (#124).</summary>
    FUnimplemented: TArray<TTextPosition>;
    /// <summary>Aktive Token (ohne inaktive Zweige) für den Schalter {$M+}.</summary>
    FActive: TArray<TPascalToken>;
    FTypeInfo: TTypeInfoClasses;
    /// <summary>Klassen dieser Datei: mit RTTI für published übersetzt?</summary>
    FLocalTypeInfo: TDictionary<string, Boolean>;
    /// <summary>Nur die aktiven Zweige (#845).</summary>
    FConditionals: TArray<TConditionalRange>;
    function IsClassMember(ANode: TSyntaxNode): Boolean;
    function InnermostBranch(const APosition: TTextPosition): Integer;
    function ConditionOf(ANode: TSyntaxNode): string;
    procedure AddExtras(ASymbol: TJSONObject; ANode: TSyntaxNode; ARoutine: Boolean);
    function DefaultVisibility(ADecl, ABody: TSyntaxNode): string;
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
    procedure AddVariantPart(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
  public
    constructor Create(const ATokens: TArray<TPascalToken>; const AUnimplemented: TArray<TTextPosition>);
      overload;
    /// <summary>AActive: aktive Token für {$M+}; ATypeInfo gehört weiter dem Aufrufer.</summary>
    constructor Create(const ATokens: TArray<TPascalToken>; const AUnimplemented: TArray<TTextPosition>;
      const AActive: TArray<TPascalToken>; ATypeInfo: TTypeInfoClasses); overload;
    destructor Destroy; override;
    /// <summary>Zweige der Datei; inaktive werden übergangen.</summary>
    procedure SetConditionals(const AConditionals: TArray<TConditionalRange>);
    function Build(ARoot: TSyntaxNode): TJSONArray;
  end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

{ TSymbolBuilder }

constructor TSymbolBuilder.Create(const ATokens: TArray<TPascalToken>;
  const AUnimplemented: TArray<TTextPosition>);
begin
  Create(ATokens, AUnimplemented, ATokens, nil);
end;

constructor TSymbolBuilder.Create(const ATokens: TArray<TPascalToken>; const AUnimplemented: TArray<TTextPosition>;
  const AActive: TArray<TPascalToken>; ATypeInfo: TTypeInfoClasses);
begin
  inherited Create;
  FTokens := ATokens;
  FUnimplemented := AUnimplemented;
  FActive := AActive;
  FTypeInfo := ATypeInfo;
  FLocalTypeInfo := TDictionary<string, Boolean>.Create;
end;

destructor TSymbolBuilder.Destroy;
begin
  FLocalTypeInfo.Free;
  inherited Destroy;
end;

procedure TSymbolBuilder.SetConditionals(const AConditionals: TArray<TConditionalRange>);
var
  Conditional: TConditionalRange;
begin
  FConditionals := nil;
  for Conditional in AConditionals do
    if Conditional.Active and (Conditional.Condition <> '') then
      FConditionals := FConditionals + [Conditional];
end;

/// <summary>A vor B?</summary>
function PositionBefore(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

/// <summary>Liegt APosition in ARange (Ende ausgeschlossen)?</summary>
function PositionIn(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result := not PositionBefore(APosition, ARange.StartPos) and PositionBefore(APosition, ARange.EndPos);
end;

function TSymbolBuilder.InnermostBranch(const APosition: TTextPosition): Integer;
var
  Index: Integer;
begin
  // Verschachtelte Zweige beginnen später als die äußeren.
  Result := -1;
  for Index := 0 to High(FConditionals) do
    if PositionIn(APosition, FConditionals[Index].Range) and ((Result < 0) or
      PositionBefore(FConditionals[Result].Range.StartPos, FConditionals[Index].Range.StartPos)) then
      Result := Index;
end;

function TSymbolBuilder.ConditionOf(ANode: TSyntaxNode): string;
var
  Branch: Integer;
  Body: TSyntaxNode;
begin
  Result := '';
  if FConditionals = nil then
    Exit;
  // Das Symbol steht im Zweig; liegt der Elternknoten im selben Zweig, trägt ihn schon jener.
  Branch := InnermostBranch(ANode.StartPos);
  if (Branch >= 0) and ((ANode.Parent = nil) or not PositionIn(ANode.Parent.StartPos,
    FConditionals[Branch].Range)) then
    Exit(FConditionals[Branch].Condition);
  // Nur der Rumpf steht im Zweig: begin … end bzw. asm … end je Plattform (Fälle 01 und 10).
  if ANode.Kind <> TSyntaxKind.RoutineDecl then
    Exit;
  Body := ANode.FindChild(TSyntaxKind.Block);
  if Body = nil then
    Body := ANode.FindChild(TSyntaxKind.AsmBlock);
  if Body = nil then
    Exit;
  Branch := InnermostBranch(Body.StartPos);
  if (Branch >= 0) and not PositionIn(ANode.StartPos, FConditionals[Branch].Range) then
    Result := FConditionals[Branch].Condition;
end;

function TSymbolBuilder.IsClassMember(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  // "class procedure", "class function": class steht vorn; bei "class property" und "class var" hat der
  // Parser das Wort schon übersprungen, es steht also davor.
  Index := TokenIndexAt(ANode.StartOffset);
  while (Index < Length(FTokens)) and (FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Inc(Index);
  if (Index < Length(FTokens)) and FTokens[Index].IsKeyword('class') then
    Exit(True);
  Dec(Index);
  while (Index >= 0) and (FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Dec(Index);
  Result := (Index >= 0) and FTokens[Index].IsKeyword('class');
end;

function TSymbolBuilder.DefaultVisibility(ADecl, ABody: TSyntaxNode): string;
var
  Index: Integer;
  Ancestor, Key: string;
  TypeInfo: Boolean;
begin
  Result := 'public';
  if not (ABody.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType]) then
    Exit;
  // Ohne Angabe sind Mitglieder published, wenn die Klasse mit RTTI für published übersetzt wird: {$M+} bzw.
  // {$TYPEINFO ON} bei der Deklaration oder ein so übersetzter Vorfahr (TPersistent und Nachfahren).
  TypeInfo := TTypeInfoClasses.SwitchAt(FActive, ADecl.StartPos);
  if not TypeInfo then
    for Index := 0 to ABody.ChildCount - 1 do
      if (ABody[Index].Kind = TSyntaxKind.TypeReference) and (ABody[Index].Name <> '') then
      begin
        // Nur der erste Eintrag ist der Vorfahr, die übrigen sind Interfaces.
        Ancestor := ABody[Index].Name;
        Key := LowerCase(Copy(Ancestor, LastDelimiter('.', Ancestor) + 1, MaxInt));
        if not FLocalTypeInfo.TryGetValue(Key, TypeInfo) then
        begin
          if FTypeInfo <> nil then
            TypeInfo := FTypeInfo.HasTypeInfo(Ancestor)
          else
            TypeInfo := TTypeInfoClasses.KnownTypeInfoClass(Ancestor);
        end;
        Break;
      end;
  FLocalTypeInfo.AddOrSetValue(LowerCase(ADecl.Name), TypeInfo);
  if TypeInfo then
    Result := 'published';
end;

procedure TSymbolBuilder.AddExtras(ASymbol: TJSONObject; ANode: TSyntaxNode; ARoutine: Boolean);
var
  Existing: TJSONValue;
  Extras: TJSONObject;
  Index: Integer;
  Start: TTextPosition;
  Position: TTextPosition;
  Directive: string;
begin
  // NewSymbol legt "atlas" schon an, wenn das Symbol eine Bedingung hat.
  Existing := ASymbol.GetValue('atlas');
  if Existing is TJSONObject then
    Extras := TJSONObject(Existing)
  else
    Extras := TJSONObject.Create;
  if FVisibility <> '' then
    Extras.AddPair('visibility', FVisibility);
  if IsClassMember(ANode) then
    Extras.AddPair('classMember', TJSONBool.Create(True));
  if ARoutine then
  begin
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind = TSyntaxKind.Directive then
      begin
        Directive := ANode[Index].Name;
        if ((Directive = 'override') or (Directive = 'virtual') or (Directive = 'abstract')) and
          (Extras.GetValue(Directive) = nil) then
          Extras.AddPair(Directive, TJSONBool.Create(True));
        // dynamic ist virtuell wie virtual.
        if (Directive = 'dynamic') and (Extras.GetValue('virtual') = nil) then
          Extras.AddPair('virtual', TJSONBool.Create(True));
      end;
    Start := NameRange(ANode, ANode.Name).StartPos;
    for Position in FUnimplemented do
      if (Position.Line = Start.Line) and (Position.Character = Start.Character) then
      begin
        Extras.AddPair('unimplemented', TJSONBool.Create(True));
        Break;
      end;
  end;
  if Extras = Existing then
    Exit;
  if Extras.Count > 0 then
    ASymbol.AddPair('atlas', Extras)
  else
    Extras.Free;
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
var
  Condition, Name: string;
begin
  Result := TJSONObject.Create;
  // Namen ohne Escape-& wie im Index: &begin heißt begin, &&op_Equality heißt &op_Equality (#1137).
  Name := TPascalLexer.PlainName(AName);
  // VS Code lehnt Symbole mit leerem Namen ab.
  if Name = '' then
    Result.AddPair('name', '?')
  else
    Result.AddPair('name', Name);
  if ADetail <> '' then
    Result.AddPair('detail', ADetail);
  Result.AddPair('kind', TJSONNumber.Create(AKind));
  Result.AddPair('range', TLspPositions.RangeToJson(NodeRange(ANode)));
  Result.AddPair('selectionRange', TLspPositions.RangeToJson(NameRange(ANode, Name)));
  Condition := ConditionOf(ANode);
  if Condition <> '' then
    Result.AddPair('atlas', TJSONObject.Create(TJSONPair.Create('condition', Condition)));
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
  Outer: string;
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
    else
      // Übrige Werte bewusst ohne Wirkung.
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
    // Verschachtelte Typen haben eigene Abschnitte; danach gilt wieder der äußere.
    Outer := FVisibility;
    FVisibility := DefaultVisibility(ADecl, Body);
    Members := TJSONArray.Create;
    try
      AddDeclarations(Body, Members, True);
      MoveChildren(Members, Result);
    finally
      Members.Free;
      FVisibility := Outer;
    end;
  end;
end;

procedure TSymbolBuilder.AddNames(ANode: TSyntaxNode; ATarget: TJSONArray; AKind: Integer);
var
  Name: string;
  Symbol: TJSONObject;
begin
  // Felder und Variablen mit mehreren Namen: A, B: Integer.
  for Name in ANode.Name.Split([',']) do
  begin
    Symbol := NewSymbol(ANode, Name.Trim, AKind);
    if AKind = TLspSymbolKind.Field then
      AddExtras(Symbol, ANode, False);
    ATarget.AddElement(Symbol);
  end;
end;

/// <summary>Typ des Selektors eines varianten Teils: "Integer" bei case Integer of und case Tag: Integer of.</summary>
function SelectorType(AVariant: TSyntaxNode): string;
var
  Index, Inner: Integer;
begin
  Result := '';
  for Index := 0 to AVariant.ChildCount - 1 do
    if AVariant[Index].Kind = TSyntaxKind.TypeReference then
      Exit(AVariant[Index].Name)
    else if AVariant[Index].Kind = TSyntaxKind.Field then
    begin
      for Inner := 0 to AVariant[Index].ChildCount - 1 do
        if AVariant[Index][Inner].Kind = TSyntaxKind.TypeReference then
          Exit(AVariant[Index][Inner].Name);
    end;
end;

procedure TSymbolBuilder.AddVariantPart(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
var
  Group: TJSONObject;
  Fields: TJSONArray;
  Title: string;
  Index: Integer;
begin
  // case Tag: Typ of (#846): das Selektorfeld neben die Felder des Records, die Zweige in eine Gruppe.
  Title := 'case ';
  if ANode.Name <> '' then
    Title := Title + ANode.Name + ': ';
  Title := Title + SelectorType(ANode) + ' of';
  Fields := TJSONArray.Create;
  try
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind = TSyntaxKind.Field then
        AddNames(ANode[Index], ATarget, TLspSymbolKind.Field)
      else if ANode[Index].Kind = TSyntaxKind.CaseItem then
        AddDeclarations(ANode[Index], Fields, AInType);
    if Fields.Count = 0 then
      Exit;
    Group := NewSymbol(ANode, Title, TLspSymbolKind.Namespace);
    ATarget.AddElement(Group);
    MoveChildren(Fields, Group);
  finally
    Fields.Free;
  end;
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
  Outer: string;
begin
  case ANode.Kind of
    TSyntaxKind.Visibility:
      if AInType then
        FVisibility := ANode.Name;
    TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection:
      AddDeclarations(ANode, ATarget, AInType);
    TSyntaxKind.VariantPart:
      AddVariantPart(ANode, ATarget, AInType);
    TSyntaxKind.TypeDecl:
      ATarget.AddElement(TypeSymbol(ANode));
    TSyntaxKind.ConstDecl:
      begin
        Symbol := NewSymbol(ANode, ANode.Name, TLspSymbolKind.Constant);
        if AInType then
          AddExtras(Symbol, ANode, False);
        ATarget.AddElement(Symbol);
      end;
    TSyntaxKind.VarDecl:
      if AInType then
        AddNames(ANode, ATarget, TLspSymbolKind.Field)
      else
        AddNames(ANode, ATarget, TLspSymbolKind.Variable);
    TSyntaxKind.Field:
      AddNames(ANode, ATarget, TLspSymbolKind.Field);
    TSyntaxKind.PropertyDecl:
      begin
        Symbol := NewSymbol(ANode, ANode.Name, TLspSymbolKind.Property_);
        if AInType then
          AddExtras(Symbol, ANode, False);
        ATarget.AddElement(Symbol);
      end;
    TSyntaxKind.RoutineHeader:
      // Methodenzuordnung procedure IFoo.Bar = MyBar erscheint nicht in der Gliederung (#849).
      if not ANode.IsMethodResolution then
      begin
        Symbol := NewSymbol(ANode, ANode.Name, RoutineKind(ANode, AInType));
        if AInType then
          AddExtras(Symbol, ANode, True);
        ATarget.AddElement(Symbol);
      end;
    TSyntaxKind.RoutineDecl:
      begin
        Symbol := NewSymbol(ANode, ANode.Name, RoutineKind(ANode, AInType));
        ATarget.AddElement(Symbol);
        // Lokale Routinen, Typen und Konstanten unter der Routine. Der eigene
        // Kopf ist ebenfalls ein Kind und darf nicht noch einmal erscheinen.
        // Sie liegen außerhalb jedes Typs: keine Sichtbarkeit.
        Outer := FVisibility;
        FVisibility := '';
        Nested := TJSONArray.Create;
        try
          for Index := 0 to ANode.ChildCount - 1 do
            if ANode[Index].Kind <> TSyntaxKind.RoutineHeader then
              AddDeclaration(ANode[Index], Nested, False);
          MoveChildren(Nested, Symbol);
        finally
          Nested.Free;
          FVisibility := Outer;
        end;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
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
  Builder := TSymbolBuilder.Create(ATree.Tokens, nil);
  try
    Result := Builder.Build(ATree.Root);
  finally
    Builder.Free;
  end;
end;

class function TLspDocumentSymbols.BuildSymbols(ATree: TSyntaxTree; const AText: string): TJSONArray;
begin
  Result := BuildSymbols(ATree, AText, nil, nil);
end;

class function TLspDocumentSymbols.BuildSymbols(ATree: TSyntaxTree; const AText: string;
  const AIndex: ISymbolIndex; const AReadText: TTypeInfoReadText): TJSONArray;
begin
  Result := BuildSymbols(ATree, AText, AIndex, AReadText, nil);
end;

class function TLspDocumentSymbols.BuildSymbols(ATree: TSyntaxTree; const AText: string;
  const AIndex: ISymbolIndex; const AReadText: TTypeInfoReadText;
  const AConditionals: TArray<TConditionalRange>): TJSONArray;
var
  Builder: TSymbolBuilder;
  Missing: TArray<TTextPosition>;
  Method: TUnmatchedMethod;
  TypeInfo: TTypeInfoClasses;
begin
  Missing := nil;
  for Method in TClassCompletion.Unmatched(ATree, AText) do
    if Method.Declared then
      Missing := Missing + [Method.Symbol.SelectionRange.StartPos];
  TypeInfo := TTypeInfoClasses.Create(AIndex, AReadText);
  try
    Builder := TSymbolBuilder.Create(ATree.Tokens, Missing, TTypeInfoClasses.ActiveTokens(AText), TypeInfo);
    try
      Builder.SetConditionals(AConditionals);
      Result := Builder.Build(ATree.Root);
    finally
      Builder.Free;
    end;
  finally
    TypeInfo.Free;
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
  Result := BuildSymbols(Tree, Document.Text, FIndex, FReadText, Shared.Conditionals);
end;

end.
