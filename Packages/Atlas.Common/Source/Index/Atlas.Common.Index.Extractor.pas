unit Atlas.Common.Index.Extractor;

// Liest aus dem Syntaxbaum einer Unit die Einträge für den Symbolindex:
// Typen mit Mitgliedern und Vorfahren, Konstanten, Variablen, Routinen und
// die uses-Listen. Lokale Deklarationen in Routinen gehören nicht dazu.
//
// Vor dem Parsen werden die inaktiven Zweige der bedingten Kompilierung
// durch Leerzeichen ersetzt (Zeilenumbrüche bleiben), damit nur aktive
// Deklarationen erscheinen und alle Positionen stimmen.
//
// Mit Include-Auflösung kommen die Deklarationen aktiver $I-Dateien dazu
// (#500): Jede Datei wird für sich geparst (ein Fragment ohne unit-Kopf
// liefert seine Deklarationen), ihre Symbole tragen die .inc als FileName
// und zählen zum Abschnitt, in dem die Direktive steht. Steht die Direktive
// mitten in einem type-, const- oder var-Abschnitt und beginnt die Datei
// nicht selbst mit einem Abschnitt, wird das Schlüsselwort vorangestellt.
// Zyklen und zu tiefe Verschachtelung überspringt der Extractor; die
// Diagnose dazu kommt aus dem Präprozessor.
//
// Vorwärtsdeklarationen (TFoo = class;) erscheinen nur, wenn die Unit den Typ
// nicht vollständig deklariert. Sonst fänden Hover, Vererbungskette und
// Gehe zu Definition die Vorwärtsdeklaration (ohne Vorfahren) statt des Typs.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Index.Contract;

type
  TIndexExtractor = class
  private
    FTokens: TArray<TPascalToken>;
    FSymbols: TList<TIndexSymbol>;
    FInInterface: Boolean;
    FVisibility: TIndexVisibility;
    // Typargumente des Vorfahren für den nächsten Add aus AddType.
    FAncestorArgs: string;
    // Der nächste Add aus AddType ist eine Vorwärtsdeklaration; FForwards hält deren Nummern in FSymbols.
    FForward: Boolean;
    FForwards: TList<Integer>;
    function IsDefaultProperty(ANode: TSyntaxNode): Boolean;
    /// <summary>Methodenkopf mit virtual, dynamic, abstract oder override?</summary>
    class function IsVirtualHeader(ANode: TSyntaxNode): Boolean; static;
    function TokenIndexAt(AOffset: Integer): Integer;
    function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
    function IsConstructor(ANode: TSyntaxNode): Boolean;
    procedure Add(ANode: TSyntaxNode; const AName, AContainer: string; AKind: TIndexSymbolKind;
      const AAncestors: TArray<string> = nil);
    procedure AddNames(ANode: TSyntaxNode; const AContainer: string; AKind: TIndexSymbolKind);
    procedure AddType(ADecl: TSyntaxNode; const AContainer: string);
    procedure AddMembers(ABody: TSyntaxNode; const AContainer: string);
    procedure AddDeclarations(ANode: TSyntaxNode);
    procedure AddRoutine(ANode: TSyntaxNode);
    /// <summary>Vorwärtsdeklarationen entfernen, deren Typ in der Unit vollständig deklariert ist.</summary>
    procedure DropForwards;
    procedure Walk(ARoot: TSyntaxNode; var AUnit: TUnitIndex);
    class function UsesOf(ASection: TSyntaxNode): TArray<string>; static;
    class function ExtractLevel(const AText, AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver; const AStack: TArray<string>): TUnitIndex; static;
    class procedure AddIncluded(ATree: TSyntaxTree; const AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver; const AStack: TArray<string>; var AUnit: TUnitIndex); static;
  public
    /// <summary>Erster direkter Typverweis eines Knotens (A: TFoo, function F: TFoo); sonst ''.</summary>
    class function DeclaredType(ANode: TSyntaxNode): string; static;
    /// <summary>Knoten des ersten direkten Typverweises; sonst nil.</summary>
    class function DeclaredTypeNode(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Typ als Text samt Typargumenten: TDictionary&lt;string, TList&lt;TKunde&gt;&gt; (#263).</summary>
    class function TypeText(ANode: TSyntaxNode): string; static;
    /// <summary>Typargumente eines Typverweises kommagetrennt ('' ohne).</summary>
    class function GenericArgsText(ATypeRef: TSyntaxNode): string; static;
    /// <summary>Typparameter aus GenericParams eines Knotens kommagetrennt ('' ohne).</summary>
    class function TypeParamsOf(ANode: TSyntaxNode): string; static;
    /// <summary>Parameterzahlen und -typen eines Routinenkopfs oder einer indizierten Property.</summary>
    class procedure ParamInfo(ANode: TSyntaxNode; out AMin, AMax: Integer; out ATypes: TArray<string>); static;
    constructor Create(const ATokens: TArray<TPascalToken>);
    destructor Destroy; override;
    /// <summary>Index-Eintrag aus einem fertigen Syntaxbaum (ohne Stamp und Hash).</summary>
    class function Extract(ATree: TSyntaxTree; const AFileName: string): TUnitIndex; static;
    /// <summary>Parst AText mit den aktiven Symbolen ADefines und liefert den Eintrag.</summary>
    /// <summary>Mit AResolver werden $I-Dateien gelesen (#264): ihre $DEFINEs gelten, Includes listet sie auf.</summary>
    class function ExtractText(const AText, AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver = nil): TUnitIndex; static;
    /// <summary>Ersetzt inaktive Zweige durch Leerzeichen; Zeilen und Spalten bleiben erhalten.</summary>
    class function BlankInactive(const AText: string; const ADefines: TArray<string>): string; overload; static;
    /// <summary>Wie oben, mit Include-Auflösung; AIncludes erhält die eingebundenen Dateien.</summary>
    class function BlankInactive(const AText, AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver; out AIncludes: TArray<string>): string; overload; static;
    /// <summary>Wie oben, zusätzlich die bedingten Zweige der Hauptdatei (#476).</summary>
    class function BlankInactive(const AText, AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver; out AIncludes: TArray<string>;
      out AConditionals: TArray<TConditionalRange>): string; overload; static;
    /// <summary>Bedingungen an die Symbole schreiben und Deklarationen aus nicht geltenden Zweigen
    /// als Unavailable erfassen (#476).</summary>
    class procedure AnnotateConditions(var AUnit: TUnitIndex; const AText: string;
      const AConditionals: TArray<TConditionalRange>); static;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  System.RegularExpressions,
  Atlas.Common.Pascal.TreeCache;

function VisibilityOf(const AText: string): TIndexVisibility;
var
  Text: string;
begin
  Text := LowerCase(Trim(AText));
  if Text = 'strict private' then
    Result := TIndexVisibility.StrictPrivate
  else if Text = 'private' then
    Result := TIndexVisibility.Private
  else if Text = 'strict protected' then
    Result := TIndexVisibility.StrictProtected
  else if Text = 'protected' then
    Result := TIndexVisibility.Protected
  else if Text = 'published' then
    Result := TIndexVisibility.Published
  else
    Result := TIndexVisibility.Public;
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function FileNameToUnitName(const AFileName: string): string;
var
  Start, Stop: Integer;
begin
  Start := LastDelimiter('\/', AFileName) + 1;
  Stop := LastDelimiter('.', AFileName);
  if Stop < Start then
    Stop := Length(AFileName) + 1;
  Result := Copy(AFileName, Start, Stop - Start);
end;

{ TIndexExtractor }

constructor TIndexExtractor.Create(const ATokens: TArray<TPascalToken>);
begin
  inherited Create;
  FTokens := ATokens;
  FSymbols := TList<TIndexSymbol>.Create;
  FForwards := TList<Integer>.Create;
end;

destructor TIndexExtractor.Destroy;
begin
  FForwards.Free;
  FSymbols.Free;
  inherited;
end;

function TIndexExtractor.TokenIndexAt(AOffset: Integer): Integer;
var
  Left, Right, Middle: Integer;
begin
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

function TIndexExtractor.NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
var
  Index: Integer;
begin
  Index := TokenIndexAt(ANode.StartOffset);
  while (Index < Length(FTokens)) and (FTokens[Index].Offset < ANode.EndOffset) do
  begin
    if (FTokens[Index].Kind = TPascalTokenKind.Identifier) and
      (SameText(FTokens[Index].Text, AName) or SameText(FTokens[Index].Text, '&' + AName)) then
      Exit(TTextRange.Create(FTokens[Index].StartPos, FTokens[Index].EndPos));
    Inc(Index);
  end;
  Result := NodeRange(ANode);
end;

function TIndexExtractor.IsConstructor(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := TokenIndexAt(ANode.StartOffset);
  while (Index < Length(FTokens)) and (FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Inc(Index);
  if (Index < Length(FTokens)) and FTokens[Index].IsKeyword('class') then
    Inc(Index);
  Result := (Index < Length(FTokens)) and
    (FTokens[Index].IsKeyword('constructor') or FTokens[Index].IsKeyword('destructor'));
end;

procedure TIndexExtractor.Add(ANode: TSyntaxNode; const AName, AContainer: string; AKind: TIndexSymbolKind;
  const AAncestors: TArray<string>);
var
  Symbol: TIndexSymbol;
begin
  if AName = '' then
    Exit;
  Symbol.Name := AName;
  Symbol.Container := AContainer;
  Symbol.Kind := AKind;
  Symbol.Range := NodeRange(ANode);
  Symbol.SelectionRange := NameRange(ANode, AName);
  Symbol.InInterface := FInInterface;
  Symbol.Ancestors := AAncestors;
  Symbol.TypeArgs := '';
  if AKind in [TIndexSymbolKind.TypeAlias, TIndexSymbolKind.Constant, TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
    TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Routine] then
  begin
    Symbol.TypeName := DeclaredType(ANode);
    if Symbol.TypeName <> '' then
      Symbol.TypeArgs := GenericArgsText(DeclaredTypeNode(ANode));
  end
  else
    Symbol.TypeName := '';
  // Erweiterungen für die Namensauflösung, Stufe 2 (#263).
  Symbol.AncestorArgs := FAncestorArgs;
  Symbol.TypeParams := TypeParamsOf(ANode);
  if (AContainer <> '') and (AKind <> TIndexSymbolKind.EnumMember) then
    Symbol.Visibility := FVisibility
  else
    Symbol.Visibility := TIndexVisibility.Public;
  Symbol.MinArgs := 0;
  Symbol.MaxArgs := 0;
  Symbol.ParamTypes := nil;
  Symbol.IsDefault := False;
  if AKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine,
    TIndexSymbolKind.Property_] then
    ParamInfo(ANode, Symbol.MinArgs, Symbol.MaxArgs, Symbol.ParamTypes);
  if AKind = TIndexSymbolKind.Property_ then
    Symbol.IsDefault := IsDefaultProperty(ANode);
  Symbol.IsVirtual := (AKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and IsVirtualHeader(ANode);
  Symbol.FileName := '';
  if FForward then
    FForwards.Add(FSymbols.Count);
  FSymbols.Add(Symbol);
end;

class function TIndexExtractor.DeclaredTypeNode(ANode: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  // Erster direkter Typverweis: A: TFoo, property P: TFoo, function F: TFoo.
  // Bei RoutineDecl steht der Typ im Kopf.
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.RoutineHeader) <> nil) then
    ANode := ANode.FindChild(TSyntaxKind.RoutineHeader);
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].Kind = TSyntaxKind.TypeReference then
      Exit(ANode[Index]);
  Result := nil;
end;

class function TIndexExtractor.DeclaredType(ANode: TSyntaxNode): string;
var
  Node: TSyntaxNode;
begin
  Node := DeclaredTypeNode(ANode);
  if Node <> nil then
    Result := Node.Name
  else
    Result := '';
end;

class function TIndexExtractor.GenericArgsText(ATypeRef: TSyntaxNode): string;
var
  Args: TSyntaxNode;
  Index: Integer;
begin
  Result := '';
  if ATypeRef = nil then
    Exit;
  Args := ATypeRef.FindChild(TSyntaxKind.GenericArgs);
  if Args = nil then
    Exit;
  for Index := 0 to Args.ChildCount - 1 do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + TypeText(Args[Index]);
  end;
end;

class function TIndexExtractor.TypeText(ANode: TSyntaxNode): string;
var
  Args: string;
begin
  Result := '';
  if ANode = nil then
    Exit;
  case ANode.Kind of
    TSyntaxKind.TypeReference:
      begin
        Result := ANode.Name;
        Args := GenericArgsText(ANode);
        if Args <> '' then
          Result := Result + '<' + Args + '>';
      end;
    TSyntaxKind.ArrayType:
      if ANode.FindChild(TSyntaxKind.TypeReference) <> nil then
        Result := 'array of ' + TypeText(ANode[ANode.ChildCount - 1]);
  end;
end;

class function TIndexExtractor.TypeParamsOf(ANode: TSyntaxNode): string;
var
  Params: TSyntaxNode;
  Index: Integer;
begin
  Result := '';
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.RoutineHeader) <> nil) then
    ANode := ANode.FindChild(TSyntaxKind.RoutineHeader);
  Params := ANode.FindChild(TSyntaxKind.GenericParams);
  if Params = nil then
    Exit;
  for Index := 0 to Params.ChildCount - 1 do
    if Params[Index].Name <> '' then
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + Params[Index].Name;
    end;
end;

class procedure TIndexExtractor.ParamInfo(ANode: TSyntaxNode; out AMin, AMax: Integer; out ATypes: TArray<string>);
var
  Params, Param, TypeNode: TSyntaxNode;
  Index, Child, Count: Integer;
  ParamType: string;
  HasDefault: Boolean;
begin
  AMin := 0;
  AMax := 0;
  ATypes := nil;
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.RoutineHeader) <> nil) then
    ANode := ANode.FindChild(TSyntaxKind.RoutineHeader);
  Params := ANode.FindChild(TSyntaxKind.Parameters);
  if Params = nil then
    Exit;
  for Index := 0 to Params.ChildCount - 1 do
  begin
    Param := Params[Index];
    if Param.Kind <> TSyntaxKind.Parameter then
      Continue;
    // Kinder: Typ (fehlt bei untypisierten Parametern), danach ggf. der Standardwert.
    TypeNode := nil;
    HasDefault := False;
    for Child := 0 to Param.ChildCount - 1 do
      if (TypeNode = nil) and (Param[Child].Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType]) then
        TypeNode := Param[Child]
      else
        HasDefault := True;
    ParamType := TypeText(TypeNode);
    // A, B: Integer zählt zweimal.
    for Count := 1 to Length(Param.Name.Split([','])) do
    begin
      Inc(AMax);
      if not HasDefault then
        Inc(AMin);
      ATypes := ATypes + [ParamType];
    end;
  end;
end;

class function TIndexExtractor.IsVirtualHeader(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if ANode.Kind <> TSyntaxKind.RoutineHeader then
    Exit;
  for Index := 0 to ANode.ChildCount - 1 do
    if (ANode[Index].Kind = TSyntaxKind.Directive) and (SameText(ANode[Index].Name, 'virtual') or
      SameText(ANode[Index].Name, 'dynamic') or SameText(ANode[Index].Name, 'abstract') or
      SameText(ANode[Index].Name, 'override')) then
      Exit(True);
end;

function TIndexExtractor.IsDefaultProperty(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  // property Items[I: Integer]: T read Get; default;  Anders als "default 0" (gespeicherter
  // Standardwert) folgt "default" hier auf ein Semikolon.
  Result := False;
  Index := TokenIndexAt(ANode.StartOffset);
  while (Index + 1 < Length(FTokens)) and (FTokens[Index].Offset <= ANode.EndOffset) do
  begin
    if FTokens[Index].IsSymbol(';') and SameText(FTokens[Index + 1].Text, 'default') then
      Exit(True);
    Inc(Index);
  end;
end;

procedure TIndexExtractor.AddNames(ANode: TSyntaxNode; const AContainer: string; AKind: TIndexSymbolKind);
var
  Name: string;
begin
  // A, B: Integer
  for Name in ANode.Name.Split([',']) do
    Add(ANode, Name.Trim, AContainer, AKind);
end;

procedure TIndexExtractor.AddMembers(ABody: TSyntaxNode; const AContainer: string);
var
  Index: Integer;
  Child: TSyntaxNode;
  Kind: TIndexSymbolKind;
begin
  for Index := 0 to ABody.ChildCount - 1 do
  begin
    Child := ABody[Index];
    case Child.Kind of
      TSyntaxKind.Visibility:
        begin
          FVisibility := VisibilityOf(Child.Name);
          AddMembers(Child, AContainer);
        end;
      TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection,
      TSyntaxKind.VariantPart:
        AddMembers(Child, AContainer);
      TSyntaxKind.TypeDecl:
        AddType(Child, AContainer);
      TSyntaxKind.ConstDecl:
        Add(Child, Child.Name, AContainer, TIndexSymbolKind.Constant);
      TSyntaxKind.VarDecl, TSyntaxKind.Field:
        AddNames(Child, AContainer, TIndexSymbolKind.Field);
      TSyntaxKind.PropertyDecl:
        Add(Child, Child.Name, AContainer, TIndexSymbolKind.Property_);
      TSyntaxKind.RoutineHeader:
        begin
          if IsConstructor(Child) then
            Kind := TIndexSymbolKind.Constructor_
          else
            Kind := TIndexSymbolKind.Method;
          Add(Child, Child.Name, AContainer, Kind);
        end;
    end;
  end;
end;

procedure TIndexExtractor.AddType(ADecl: TSyntaxNode; const AContainer: string);
var
  Body: TSyntaxNode;
  Index: Integer;
  Kind: TIndexSymbolKind;
  Ancestors: TList<string>;
  Qualified, AncestorArgs: string;
  Visibility: TIndexVisibility;
begin
  Body := nil;
  AncestorArgs := '';
  for Index := 0 to ADecl.ChildCount - 1 do
    if not (ADecl[Index].Kind in [TSyntaxKind.GenericParams, TSyntaxKind.Attribute]) then
    begin
      Body := ADecl[Index];
      Break;
    end;
  Kind := TIndexSymbolKind.TypeAlias;
  Ancestors := TList<string>.Create;
  try
    if Body <> nil then
    begin
      case Body.Kind of
        TSyntaxKind.ClassType, TSyntaxKind.ClassOfType, TSyntaxKind.ForwardType:
          Kind := TIndexSymbolKind.ClassType;
        TSyntaxKind.ObjectType:
          Kind := TIndexSymbolKind.ObjectType;
        TSyntaxKind.HelperType:
          Kind := TIndexSymbolKind.HelperType;
        TSyntaxKind.RecordType:
          Kind := TIndexSymbolKind.RecordType;
        TSyntaxKind.InterfaceType:
          Kind := TIndexSymbolKind.InterfaceType;
        TSyntaxKind.EnumType:
          Kind := TIndexSymbolKind.EnumType;
      end;
      // Vorfahren: direkte Typverweise des Rumpfs (class(TBase, IFoo), helper for T).
      if Body.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.InterfaceType,
        TSyntaxKind.HelperType] then
        for Index := 0 to Body.ChildCount - 1 do
          if (Body[Index].Kind = TSyntaxKind.TypeReference) and (Body[Index].Name <> '') then
          begin
            if Ancestors.Count = 0 then
              AncestorArgs := GenericArgsText(Body[Index]);
            Ancestors.Add(Body[Index].Name);
          end;
    end;
    FAncestorArgs := AncestorArgs;
    FForward := (Body <> nil) and (Body.Kind = TSyntaxKind.ForwardType);
    try
      Add(ADecl, ADecl.Name, AContainer, Kind, Ancestors.ToArray);
    finally
      FAncestorArgs := '';
      FForward := False;
    end;
  finally
    Ancestors.Free;
  end;
  if Body = nil then
    Exit;
  if AContainer = '' then
    Qualified := ADecl.Name
  else
    Qualified := AContainer + '.' + ADecl.Name;
  if Body.Kind = TSyntaxKind.EnumType then
  begin
    // Enum-Werte sind ohne SCOPEDENUMS auch auf Unit-Ebene sichtbar; der
    // Container hält den Typ fest, die Namensauflösung entscheidet.
    for Index := 0 to Body.ChildCount - 1 do
      if Body[Index].Kind = TSyntaxKind.Identifier then
        Add(Body[Index], Body[Index].Name, Qualified, TIndexSymbolKind.EnumMember);
  end
  else if Body.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.HelperType,
    TSyntaxKind.RecordType, TSyntaxKind.InterfaceType] then
  begin
    // Verschachtelte Typen haben ihre eigene Sichtbarkeit; danach gilt wieder die äußere.
    Visibility := FVisibility;
    FVisibility := TIndexVisibility.Public;
    try
      AddMembers(Body, Qualified);
    finally
      FVisibility := Visibility;
    end;
  end;
end;

procedure TIndexExtractor.AddRoutine(ANode: TSyntaxNode);
var
  Name, Container: string;
  Dot: Integer;
  Kind: TIndexSymbolKind;
begin
  // TFoo.Bar in implementation: Methode von TFoo; sonst freie Routine.
  Name := ANode.Name;
  Dot := Name.LastIndexOf('.');
  if Dot >= 0 then
  begin
    Container := Name.Substring(0, Dot);
    Name := Name.Substring(Dot + 1);
    if IsConstructor(ANode) then
      Kind := TIndexSymbolKind.Constructor_
    else
      Kind := TIndexSymbolKind.Method;
  end
  else
  begin
    Container := '';
    Kind := TIndexSymbolKind.Routine;
  end;
  Add(ANode, Name, Container, Kind);
end;

procedure TIndexExtractor.AddDeclarations(ANode: TSyntaxNode);
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    case Child.Kind of
      TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection:
        AddDeclarations(Child);
      TSyntaxKind.TypeDecl:
        AddType(Child, '');
      TSyntaxKind.ConstDecl:
        Add(Child, Child.Name, '', TIndexSymbolKind.Constant);
      TSyntaxKind.VarDecl:
        AddNames(Child, '', TIndexSymbolKind.Variable);
      TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl:
        AddRoutine(Child);
    end;
  end;
end;

class function TIndexExtractor.UsesOf(ASection: TSyntaxNode): TArray<string>;
var
  Clause: TSyntaxNode;
  Names: TList<string>;
  Index: Integer;
begin
  Result := nil;
  if ASection = nil then
    Exit;
  Clause := ASection.FindChild(TSyntaxKind.UsesClause);
  if Clause = nil then
    Exit;
  Names := TList<string>.Create;
  try
    for Index := 0 to Clause.ChildCount - 1 do
      if (Clause[Index].Kind = TSyntaxKind.UsedUnit) and (Clause[Index].Name <> '') then
        Names.Add(Clause[Index].Name);
    Result := Names.ToArray;
  finally
    Names.Free;
  end;
end;

procedure TIndexExtractor.DropForwards;
var
  Index: Integer;
  Forwards: TArray<Boolean>;
  Full: TDictionary<string, Boolean>;
begin
  if FForwards.Count = 0 then
    Exit;
  SetLength(Forwards, FSymbols.Count);
  for Index in FForwards do
    Forwards[Index] := True;
  Full := TDictionary<string, Boolean>.Create;
  try
    for Index := 0 to FSymbols.Count - 1 do
      if not Forwards[Index] then
        Full.AddOrSetValue(UpperCase(FSymbols[Index].QualifiedName), True);
    for Index := FForwards.Count - 1 downto 0 do
      if Full.ContainsKey(UpperCase(FSymbols[FForwards[Index]].QualifiedName)) then
        FSymbols.Delete(FForwards[Index]);
  finally
    Full.Free;
  end;
  FForwards.Clear;
end;

procedure TIndexExtractor.Walk(ARoot: TSyntaxNode; var AUnit: TUnitIndex);
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  AUnit.InterfaceUses := nil;
  AUnit.ImplementationUses := nil;
  AUnit.HasInitialization := (ARoot.FindChild(TSyntaxKind.InitializationSection) <> nil) or
    (ARoot.FindChild(TSyntaxKind.FinalizationSection) <> nil);
  if ARoot.Kind = TSyntaxKind.UnitFile then
  begin
    AUnit.InterfaceUses := UsesOf(ARoot.FindChild(TSyntaxKind.InterfaceSection));
    AUnit.ImplementationUses := UsesOf(ARoot.FindChild(TSyntaxKind.ImplementationSection));
  end
  else
    // program, library, package: alles gilt als implementation.
    AUnit.ImplementationUses := UsesOf(ARoot);
  for Index := 0 to ARoot.ChildCount - 1 do
  begin
    Child := ARoot[Index];
    if Child.Kind = TSyntaxKind.InterfaceSection then
    begin
      FInInterface := True;
      AddDeclarations(Child);
    end
    else if Child.Kind = TSyntaxKind.ImplementationSection then
    begin
      FInInterface := False;
      AddDeclarations(Child);
    end;
  end;
  if ARoot.Kind <> TSyntaxKind.UnitFile then
  begin
    FInInterface := False;
    AddDeclarations(ARoot);
  end;
  DropForwards;
  AUnit.Symbols := FSymbols.ToArray;
end;

class function TIndexExtractor.Extract(ATree: TSyntaxTree; const AFileName: string): TUnitIndex;
var
  Extractor: TIndexExtractor;
begin
  Result := Default(TUnitIndex);
  Result.FileName := AFileName;
  Result.UnitName := ATree.Root.Name;
  if Result.UnitName = '' then
    Result.UnitName := FileNameToUnitName(AFileName);
  Extractor := TIndexExtractor.Create(ATree.Tokens);
  try
    Extractor.Walk(ATree.Root, Result);
  finally
    Extractor.Free;
  end;
end;

class function TIndexExtractor.BlankInactive(const AText: string; const ADefines: TArray<string>): string;
var
  Includes: TArray<string>;
begin
  Result := BlankInactive(AText, '', ADefines, nil, Includes);
end;

class function TIndexExtractor.BlankInactive(const AText, AFileName: string; const ADefines: TArray<string>;
  const AResolver: TIncludeResolver; out AIncludes: TArray<string>): string;
var
  Conditionals: TArray<TConditionalRange>;
begin
  Result := BlankInactive(AText, AFileName, ADefines, AResolver, AIncludes, Conditionals);
end;

class function TIndexExtractor.BlankInactive(const AText, AFileName: string; const ADefines: TArray<string>;
  const AResolver: TIncludeResolver; out AIncludes: TArray<string>;
  out AConditionals: TArray<TConditionalRange>): string;
var
  Conditional: TConditionalRange;
  Options: TPreprocessorOptions;
  Processed: TPreprocessorResult;
  LineStarts: TList<Integer>;
  Range: TInactiveRange;
  Index, StartOffset, EndOffset: Integer;

  function OffsetOf(const APosition: TTextPosition): Integer;
  begin
    // 1-basiert; über das Textende hinaus wird abgeschnitten.
    if APosition.Line >= LineStarts.Count then
      Exit(Length(AText) + 1);
    Result := LineStarts[APosition.Line] + APosition.Character;
    if Result > Length(AText) + 1 then
      Result := Length(AText) + 1;
  end;

begin
  Result := AText;
  AIncludes := nil;
  AConditionals := nil;
  if Pos('{$', AText) + Pos('(*$', AText) = 0 then
    Exit;
  Options := TPreprocessorOptions.Default;
  Options.Defines := ADefines;
  Options.FileName := AFileName;
  Options.ResolveInclude := AResolver;
  Processed := TPascalPreprocessor.Process(AText, Options);
  for Index := 1 to High(Processed.Files) do
    if IndexText(Processed.Files[Index], AIncludes) < 0 then
      AIncludes := AIncludes + [Processed.Files[Index]];
  for Conditional in Processed.Conditionals do
    if Conditional.FileIndex = 0 then
      AConditionals := AConditionals + [Conditional];
  if Length(Processed.InactiveRanges) = 0 then
    Exit;
  LineStarts := TList<Integer>.Create;
  try
    LineStarts.Add(1);
    Index := 1;
    while Index <= Length(AText) do
    begin
      if AText[Index] = #13 then
      begin
        if (Index < Length(AText)) and (AText[Index + 1] = #10) then
          Inc(Index);
        LineStarts.Add(Index + 1);
      end
      else if AText[Index] = #10 then
        LineStarts.Add(Index + 1);
      Inc(Index);
    end;
    for Range in Processed.InactiveRanges do
    begin
      if Range.FileIndex <> 0 then
        Continue;
      StartOffset := OffsetOf(Range.Range.StartPos);
      EndOffset := OffsetOf(Range.Range.EndPos);
      for Index := StartOffset to EndOffset - 1 do
        if (Index >= 1) and (Index <= Length(Result)) and not CharInSet(Result[Index], [#10, #13]) then
          Result[Index] := ' ';
    end;
  finally
    LineStarts.Free;
  end;
end;

class function TIndexExtractor.ExtractText(const AText, AFileName: string;
  const ADefines: TArray<string>; const AResolver: TIncludeResolver): TUnitIndex;
begin
  Result := ExtractLevel(AText, AFileName, ADefines, AResolver, [AFileName]);
end;

/// <summary>Liegt APosition in ARange (Ende ausgeschlossen)?</summary>
function InRange(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result := ((APosition.Line > ARange.StartPos.Line) or
    ((APosition.Line = ARange.StartPos.Line) and (APosition.Character >= ARange.StartPos.Character))) and
    ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character < ARange.EndPos.Character)));
end;

class procedure TIndexExtractor.AnnotateConditions(var AUnit: TUnitIndex; const AText: string;
  const AConditionals: TArray<TConditionalRange>);
var
  Lines: TArray<string>;
  Index, LineIndex, Best, ImplementationLine, Indent: Integer;
  Conditional: TConditionalRange;
  Symbol: TIndexSymbol;
  Section, Line, Code, Keyword, Owner: string;
  Match: TMatch;
  Known: TDictionary<string, Boolean>;
  // Abschnitt (type/const/var …) am Anfang jeder Zeile; einmal für die ganze Datei bestimmt.
  Sections: TArray<string>;

  function IndentOf(const AValue: string): Integer;
  begin
    Result := 0;
    while (Result < Length(AValue)) and CharInSet(AValue[Result + 1], [' ', #9]) do
      Inc(Result);
  end;

  procedure AddUnavailable(const AName: string; AKind: TIndexSymbolKind; ALine, AColumn: Integer;
    const ACondition: string; const AContainer: string = '');
  var
    Item: TIndexSymbol;
    Key: string;
  begin
    // Mitglieder je Typ: gleichnamige Mitglieder anderer Typen sind etwas anderes.
    Key := UpperCase(AName);
    if AContainer <> '' then
      Key := UpperCase(AContainer) + '.' + Key;
    if Known.ContainsKey(Key) then
      Exit;
    Known.Add(Key, True);
    Item := Default(TIndexSymbol);
    Item.Name := AName;
    Item.Kind := AKind;
    Item.Container := AContainer;
    Item.Range := TTextRange.Create(TTextPosition.Create(ALine, 0), TTextPosition.Create(ALine, Length(Lines[ALine])));
    Item.SelectionRange := TTextRange.Create(TTextPosition.Create(ALine, AColumn),
      TTextPosition.Create(ALine, AColumn + Length(AName)));
    Item.InInterface := (ImplementationLine < 0) or (ALine < ImplementationLine);
    Item.Visibility := TIndexVisibility.Public;
    Item.Condition := ACondition;
    Item.Unavailable := True;
    AUnit.Unavailable := AUnit.Unavailable + [Item];
  end;

  // Innerster Klassen-, Record- oder Interface-Typ, in dessen Rumpf ALine liegt; '' = keiner.
  function OwnerOf(ALine: Integer): string;
  var
    Candidate: TIndexSymbol;
    Best: TTextRange;
  begin
    Result := '';
    for Candidate in AUnit.Symbols do
      if (Candidate.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
        TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType]) and (Candidate.FileName = '') and
        (Candidate.Range.StartPos.Line < ALine) and (Candidate.Range.EndPos.Line >= ALine) then
        if (Result = '') or (Candidate.Range.StartPos.Line >= Best.StartPos.Line) then
        begin
          Result := Candidate.QualifiedName;
          Best := Candidate.Range;
        end;
  end;

  // Mitglied in einem nicht geltenden Zweig innerhalb eines Typrumpfs (#476): Methoden, Properties, Felder.
  procedure AddMember(const ACode: string; ALine: Integer; const AOwner, ACondition: string);
  var
    Found: TMatch;
    Words: string;
    Kind: TIndexSymbolKind;
    Name: string;
    Column: Integer;
  begin
    Found := TRegEx.Match(ACode,
      '^\s*(class\s+)?(procedure|function|constructor|destructor|operator)\s+([A-Za-z_]\w*)', [roIgnoreCase]);
    if Found.Success then
    begin
      Words := LowerCase(Found.Groups[2].Value);
      if Words = 'constructor' then
        Kind := TIndexSymbolKind.Constructor_
      else
        Kind := TIndexSymbolKind.Method;
      AddUnavailable(Found.Groups[3].Value, Kind, ALine, Found.Groups[3].Index - 1, ACondition, AOwner);
      Exit;
    end;
    Found := TRegEx.Match(ACode, '^\s*(class\s+)?property\s+([A-Za-z_]\w*)', [roIgnoreCase]);
    if Found.Success then
    begin
      AddUnavailable(Found.Groups[2].Value, TIndexSymbolKind.Property_, ALine, Found.Groups[2].Index - 1,
        ACondition, AOwner);
      Exit;
    end;
    // Felder "A, B: Integer;" (auch nach "class var" / "var"); Schlüsselwörter sind keine Felder.
    Found := TRegEx.Match(ACode, '^\s*((class\s+)?var\s+)?([A-Za-z_]\w*(\s*,\s*[A-Za-z_]\w*)*)\s*:[^=]',
      [roIgnoreCase]);
    if not Found.Success then
      Exit;
    Column := Found.Groups[3].Index - 1;
    for Name in Found.Groups[3].Value.Split([',']) do
    begin
      Words := Trim(Name);
      if MatchText(Words, ['private', 'protected', 'public', 'published', 'strict', 'case', 'end']) then
        Continue;
      AddUnavailable(Words, TIndexSymbolKind.Field, ALine, Column + Pos(Words, Found.Groups[3].Value) - 1,
        ACondition, AOwner);
    end;
  end;

  procedure AddType(const AMatch: TMatch; ALine: Integer; const ACondition: string);
  var
    Kind: TIndexSymbolKind;
  begin
    Keyword := LowerCase(AMatch.Groups[4].Value);
    if Keyword = 'class' then
      Kind := TIndexSymbolKind.ClassType
    else if Keyword = 'record' then
      Kind := TIndexSymbolKind.RecordType
    else if (Keyword = 'interface') or (Keyword = 'dispinterface') then
      Kind := TIndexSymbolKind.InterfaceType
    else if Keyword = '(' then
      Kind := TIndexSymbolKind.EnumType
    else
      Kind := TIndexSymbolKind.TypeAlias;
    AddUnavailable(AMatch.Groups[1].Value, Kind, ALine, AMatch.Groups[1].Index - 1, ACondition);
  end;

begin
  AUnit.Unavailable := nil;
  Lines := AText.Replace(#13#10, #10).Split([#10]);
  // Geltende Zweige: der innerste umgebende Zweig bestimmt die Bedingung.
  for Index := 0 to High(AUnit.Symbols) do
  begin
    if AUnit.Symbols[Index].FileName <> '' then
      Continue;
    Best := -1;
    for LineIndex := 0 to High(AConditionals) do
      if AConditionals[LineIndex].Active and InRange(AUnit.Symbols[Index].SelectionRange.StartPos,
        AConditionals[LineIndex].Range) then
        if (Best < 0) or InRange(AConditionals[LineIndex].Range.StartPos, AConditionals[Best].Range) then
          Best := LineIndex;
    if Best >= 0 then
      AUnit.Symbols[Index].Condition := AConditionals[Best].Condition
    else
    begin
      // Direktive platform an der Deklaration (erste Zeile).
      LineIndex := AUnit.Symbols[Index].SelectionRange.StartPos.Line;
      if (LineIndex >= 0) and (LineIndex <= High(Lines)) and
        TRegEx.IsMatch(Lines[LineIndex], '\bplatform\s*;', [roIgnoreCase]) then
        AUnit.Symbols[Index].Condition := 'platform';
    end;
  end;
  // Nur wenn ein Zweig nicht gilt, lohnt die Suche nach Deklarationen darin.
  Best := 0;
  for Conditional in AConditionals do
    if not Conditional.Active then
      Inc(Best);
  if Best = 0 then
    Exit;
  // Ein Durchlauf über die Datei: Abschnitt je Zeile und Beginn des implementation-Teils.
  // Große Units (System.pas) haben tausende Zweige; je Zweig neu zu suchen wäre quadratisch.
  ImplementationLine := -1;
  SetLength(Sections, Length(Lines));
  Section := '';
  for LineIndex := 0 to High(Lines) do
  begin
    Sections[LineIndex] := Section;
    Line := TrimLeft(Lines[LineIndex]);
    if (Line = '') or not CharInSet(Line[1], ['a'..'z', 'A'..'Z']) then
      Continue;
    Match := TRegEx.Match(Line, '^(type|const|var|threadvar|resourcestring|implementation|interface)\b',
      [roIgnoreCase]);
    if not Match.Success then
      Continue;
    Keyword := LowerCase(Match.Groups[1].Value);
    if (Keyword = 'implementation') or (Keyword = 'interface') then
    begin
      Section := '';
      if (Keyword = 'implementation') and (ImplementationLine < 0) then
        ImplementationLine := LineIndex;
    end
    else
      Section := Keyword;
  end;
  Known := TDictionary<string, Boolean>.Create;
  try
    // Was in geltenden Zweigen schon deklariert ist, nicht noch einmal (IFDEF WIN32 ... ELSE ... gleicher Name).
    for Symbol in AUnit.Symbols do
      if Symbol.Container = '' then
        Known.AddOrSetValue(UpperCase(Symbol.Name), True)
      else
        Known.AddOrSetValue(UpperCase(Symbol.Container) + '.' + UpperCase(Symbol.Name), True);
    for Conditional in AConditionals do
    begin
      if Conditional.Active then
        Continue;
      // Abschnitt am Anfang des Zweigs aus dem einen Durchlauf oben.
      if (Conditional.Range.StartPos.Line >= 0) and (Conditional.Range.StartPos.Line < Length(Sections) - 1) then
        Section := Sections[Conditional.Range.StartPos.Line + 1]
      else
        Section := '';
      // Im implementation-Teil nur Routinen der Unit (eigene Unit, z. B. "procedure ApplyAppIcon;" unter
      // {$IFDEF FPC}): ein billiger Vergleich am Zeilenanfang je Zeile, denn lange Zweige mit ganzen
      // Implementierungen (System.pas) sollen nichts kosten. Methodenrümpfe "TFoo.Bar" zählen nicht.
      if (ImplementationLine >= 0) and (Conditional.Range.StartPos.Line > ImplementationLine) then
      begin
        for LineIndex := Conditional.Range.StartPos.Line + 1 to Min(Conditional.Range.EndPos.Line, High(Lines)) do
        begin
          Line := Lines[LineIndex];
          if not (StartsText('procedure ', Line) or StartsText('function ', Line)) then
            Continue;
          Match := TRegEx.Match(Line, '^(procedure|function)\s+([A-Za-z_]\w*)\s*[(:;]', [roIgnoreCase]);
          if Match.Success then
            AddUnavailable(Match.Groups[2].Value, TIndexSymbolKind.Routine, LineIndex, Match.Groups[2].Index - 1,
              Conditional.Condition);
        end;
        Continue;
      end;
      // Zweig im Rumpf einer Klasse, eines Records oder Interfaces: Mitglieder dieses Typs.
      Owner := OwnerOf(Conditional.Range.StartPos.Line);
      if Owner <> '' then
      begin
        for LineIndex := Conditional.Range.StartPos.Line + 1 to Min(Conditional.Range.EndPos.Line, High(Lines)) do
        begin
          Code := Lines[LineIndex];
          if Pos('//', Code) > 0 then
            Code := Copy(Code, 1, Pos('//', Code) - 1);
          AddMember(Code, LineIndex, Owner, Conditional.Condition);
        end;
        Continue;
      end;
      for LineIndex := Conditional.Range.StartPos.Line + 1 to Min(Conditional.Range.EndPos.Line, High(Lines)) do
      begin
        Line := Lines[LineIndex];
        Code := Line;
        if Pos('//', Code) > 0 then
          Code := Copy(Code, 1, Pos('//', Code) - 1);
        Match := TRegEx.Match(Code, '^\s*(type|const|var|threadvar|resourcestring)\b', [roIgnoreCase]);
        if Match.Success then
        begin
          Section := LowerCase(Match.Groups[1].Value);
          Code := Copy(Code, Match.Length + 1, MaxInt);
          if Trim(Code) = '' then
            Continue;
        end;
        Indent := IndentOf(Line);
        // Routinen auf Unit-Ebene stehen am Zeilenanfang.
        Match := TRegEx.Match(Code, '^(procedure|function)\s+([A-Za-z_]\w*)\s*[(:;]', [roIgnoreCase]);
        if Match.Success then
        begin
          AddUnavailable(Match.Groups[2].Value, TIndexSymbolKind.Routine, LineIndex, Match.Groups[2].Index - 1,
            Conditional.Condition);
          Section := '';
          Continue;
        end;
        if Indent > 2 then
          Continue;
        if Section = 'type' then
        begin
          // Vorwärtsdeklaration "TFoo = class;" zählt nicht.
          if TRegEx.IsMatch(Code, '=\s*(packed\s+)?(class|interface)\s*;', [roIgnoreCase]) then
            Continue;
          Match := TRegEx.Match(Code, '^\s*([A-Za-z_]\w*)\s*(<[^>]*>)?\s*=\s*(packed\s+)?(\w+|\()', [roIgnoreCase]);
          if Match.Success then
            AddType(Match, LineIndex, Conditional.Condition);
        end
        else if (Section = 'const') or (Section = 'resourcestring') then
        begin
          Match := TRegEx.Match(Code, '^\s*([A-Za-z_]\w*)\s*(:[^=]+)?=', [roIgnoreCase]);
          if Match.Success then
            AddUnavailable(Match.Groups[1].Value, TIndexSymbolKind.Constant, LineIndex, Match.Groups[1].Index - 1,
              Conditional.Condition);
        end
        else if (Section = 'var') or (Section = 'threadvar') then
        begin
          Match := TRegEx.Match(Code, '^\s*([A-Za-z_]\w*)\s*:', [roIgnoreCase]);
          if Match.Success then
            AddUnavailable(Match.Groups[1].Value, TIndexSymbolKind.Variable, LineIndex, Match.Groups[1].Index - 1,
              Conditional.Condition);
        end;
      end;
    end;
  finally
    Known.Free;
  end;
end;

class function TIndexExtractor.ExtractLevel(const AText, AFileName: string; const ADefines: TArray<string>;
  const AResolver: TIncludeResolver; const AStack: TArray<string>): TUnitIndex;
var
  Tree: TSyntaxTree;
  Includes: TArray<string>;
  Conditionals: TArray<TConditionalRange>;
begin
  Tree := TSyntaxTreeCache.Parse(BlankInactive(AText, AFileName, ADefines, AResolver, Includes, Conditionals));
  try
    Result := Extract(Tree, AFileName);
    Result.Includes := Includes;
    AnnotateConditions(Result, AText, Conditionals);
    AddIncluded(Tree, AFileName, ADefines, AResolver, AStack, Result);
  finally
    Tree.Free;
  end;
end;

/// <summary>Name aus "{$I Name}", "{$INCLUDE 'Name'}" bzw. "(*$I Name*)"; False bei Schaltern wie {$I+}.</summary>
function IncludeNameOf(const ADirective: string; out AName: string): Boolean;
var
  Text, Word: string;
  Index: Integer;
begin
  Result := False;
  Text := ADirective;
  if Text.StartsWith('{$') and Text.EndsWith('}') then
    Text := Copy(Text, 3, Length(Text) - 3)
  else if Text.StartsWith('(*$') and Text.EndsWith('*)') then
    Text := Copy(Text, 4, Length(Text) - 5)
  else
    Exit;
  Index := 1;
  while (Index <= Length(Text)) and CharInSet(Text[Index], ['A'..'Z', 'a'..'z']) do
    Inc(Index);
  Word := UpperCase(Copy(Text, 1, Index - 1));
  if (Word <> 'I') and (Word <> 'INCLUDE') then
    Exit;
  AName := Trim(Copy(Text, Index, MaxInt));
  Result := (AName <> '') and not CharInSet(AName[1], ['+', '-']);
end;

/// <summary>Erstes Wort von AText hinter Leerraum und Kommentaren, klein.</summary>
function FirstWord(const AText: string): string;
var
  Index, Start: Integer;
begin
  Result := '';
  Index := 1;
  while Index <= Length(AText) do
  begin
    if CharInSet(AText[Index], [#1..' ']) then
      Inc(Index)
    else if AText[Index] = '{' then
    begin
      Index := PosEx('}', AText, Index);
      if Index = 0 then
        Exit;
      Inc(Index);
    end
    else if Copy(AText, Index, 2) = '(*' then
    begin
      Index := PosEx('*)', AText, Index);
      if Index = 0 then
        Exit;
      Inc(Index, 2);
    end
    else if Copy(AText, Index, 2) = '//' then
    begin
      while (Index <= Length(AText)) and not CharInSet(AText[Index], [#10, #13]) do
        Inc(Index);
    end
    else
    begin
      Start := Index;
      while (Index <= Length(AText)) and CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(Index);
      Exit(LowerCase(Copy(AText, Start, Index - Start)));
    end;
  end;
end;

function Shifted(const APosition: TTextPosition; ALines: Integer): TTextPosition;
begin
  Result := TTextPosition.Create(APosition.Line - ALines, APosition.Character);
end;

class procedure TIndexExtractor.AddIncluded(ATree: TSyntaxTree; const AFileName: string;
  const ADefines: TArray<string>; const AResolver: TIncludeResolver; const AStack: TArray<string>;
  var AUnit: TUnitIndex);
const
  MaxDepth = 16;
  SectionWords: array[0..4] of string = ('type', 'const', 'var', 'resourcestring', 'threadvar');
  StartWords: array[0..13] of string = ('type', 'const', 'var', 'resourcestring', 'threadvar', 'procedure',
    'function', 'constructor', 'destructor', 'class', 'operator', 'uses', 'begin', 'exports');
var
  Token: TPascalToken;
  ImplementationOffset, Shift: Integer;
  IsUnit, InInterface: Boolean;
  Section, Name, IncFile, IncText: string;
  Included: TUnitIndex;
  Symbol, Copied: TIndexSymbol;
  Symbols: TList<TIndexSymbol>;
begin
  if not Assigned(AResolver) or (Length(AStack) > MaxDepth) then
    Exit;
  IsUnit := ATree.Root.Kind = TSyntaxKind.UnitFile;
  ImplementationOffset := MaxInt;
  for Token in ATree.Tokens do
    if Token.IsKeyword('implementation') then
    begin
      ImplementationOffset := Token.Offset;
      Break;
    end;
  Section := '';
  Symbols := TList<TIndexSymbol>.Create;
  try
    Symbols.AddRange(AUnit.Symbols);
    for Token in ATree.Tokens do
    begin
      // Zuletzt geöffneter Deklarationsabschnitt, für Dateien ohne eigenes Schlüsselwort.
      if (Token.Kind = TPascalTokenKind.Keyword) and (IndexText(Token.Text, SectionWords) >= 0) then
        Section := LowerCase(Token.Text)
      else if Token.IsKeyword('begin') or Token.IsKeyword('implementation') or Token.IsKeyword('interface') then
        Section := '';
      if (Token.Kind <> TPascalTokenKind.Directive) or not IncludeNameOf(Token.Text, Name) then
        Continue;
      // Nicht gefunden oder Zyklus: überspringen, die Diagnose kommt aus dem Präprozessor.
      if not AResolver(Name, AFileName, IncFile, IncText) or (IndexText(IncFile, AStack) >= 0) then
        Continue;
      InInterface := IsUnit and (Token.Offset < ImplementationOffset);
      Shift := 0;
      if (Section <> '') and (IndexText(FirstWord(IncText), StartWords) < 0) then
      begin
        IncText := Section + #10 + IncText;
        Shift := 1;
      end;
      Included := ExtractLevel(IncText, IncFile, ADefines, AResolver, AStack + [IncFile]);
      for Symbol in Included.Symbols do
      begin
        Copied := Symbol;
        if Copied.FileName = '' then
        begin
          Copied.FileName := IncFile;
          Copied.Range := TTextRange.Create(Shifted(Copied.Range.StartPos, Shift), Shifted(Copied.Range.EndPos, Shift));
          Copied.SelectionRange := TTextRange.Create(Shifted(Copied.SelectionRange.StartPos, Shift),
            Shifted(Copied.SelectionRange.EndPos, Shift));
        end;
        Copied.InInterface := InInterface;
        Symbols.Add(Copied);
      end;
      if IndexText(IncFile, AUnit.Includes) < 0 then
        AUnit.Includes := AUnit.Includes + [IncFile];
      for Name in Included.Includes do
        if IndexText(Name, AUnit.Includes) < 0 then
          AUnit.Includes := AUnit.Includes + [Name];
    end;
    AUnit.Symbols := Symbols.ToArray;
  finally
    Symbols.Free;
  end;
end;
end.
