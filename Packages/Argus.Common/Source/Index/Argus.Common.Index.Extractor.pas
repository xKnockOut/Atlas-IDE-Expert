unit Argus.Common.Index.Extractor;

// Liest aus dem Syntaxbaum einer Unit die Einträge für den Symbolindex:
// Typen mit Mitgliedern und Vorfahren, Konstanten, Variablen, Routinen und
// die uses-Listen. Lokale Deklarationen in Routinen gehören nicht dazu.
//
// Vor dem Parsen werden die inaktiven Zweige der bedingten Kompilierung
// durch Leerzeichen ersetzt (Zeilenumbrüche bleiben), damit nur aktive
// Deklarationen erscheinen und alle Positionen stimmen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Index.Contract;

type
  TIndexExtractor = class
  private
    FTokens: TArray<TPascalToken>;
    FSymbols: TList<TIndexSymbol>;
    FInInterface: Boolean;
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
    procedure Walk(ARoot: TSyntaxNode; var AUnit: TUnitIndex);
    class function UsesOf(ASection: TSyntaxNode): TArray<string>; static;
  public
    /// <summary>Erster direkter Typverweis eines Knotens (A: TFoo, function F: TFoo); sonst ''.</summary>
    class function DeclaredType(ANode: TSyntaxNode): string; static;
    constructor Create(const ATokens: TArray<TPascalToken>);
    destructor Destroy; override;
    /// <summary>Index-Eintrag aus einem fertigen Syntaxbaum (ohne Stamp und Hash).</summary>
    class function Extract(ATree: TSyntaxTree; const AFileName: string): TUnitIndex; static;
    /// <summary>Parst AText mit den aktiven Symbolen ADefines und liefert den Eintrag.</summary>
    class function ExtractText(const AText, AFileName: string; const ADefines: TArray<string>): TUnitIndex; static;
    /// <summary>Ersetzt inaktive Zweige durch Leerzeichen; Zeilen und Spalten bleiben erhalten.</summary>
    class function BlankInactive(const AText: string; const ADefines: TArray<string>): string; static;
  end;

implementation

uses
  Argus.Common.Pascal.Parser,
  Argus.Common.Pascal.Preprocessor;

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
end;

destructor TIndexExtractor.Destroy;
begin
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
  if AKind in [TIndexSymbolKind.TypeAlias, TIndexSymbolKind.Constant, TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
    TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Routine] then
    Symbol.TypeName := DeclaredType(ANode)
  else
    Symbol.TypeName := '';
  FSymbols.Add(Symbol);
end;

class function TIndexExtractor.DeclaredType(ANode: TSyntaxNode): string;
var
  Index: Integer;
begin
  // Erster direkter Typverweis: A: TFoo, property P: TFoo, function F: TFoo.
  // Bei RoutineDecl steht der Typ im Kopf.
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.RoutineHeader) <> nil) then
    ANode := ANode.FindChild(TSyntaxKind.RoutineHeader);
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].Kind = TSyntaxKind.TypeReference then
      Exit(ANode[Index].Name);
  Result := '';
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
      TSyntaxKind.Visibility, TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection,
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
  Qualified: string;
begin
  Body := nil;
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
            Ancestors.Add(Body[Index].Name);
    end;
    Add(ADecl, ADecl.Name, AContainer, Kind, Ancestors.ToArray);
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
    AddMembers(Body, Qualified);
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

procedure TIndexExtractor.Walk(ARoot: TSyntaxNode; var AUnit: TUnitIndex);
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  AUnit.InterfaceUses := nil;
  AUnit.ImplementationUses := nil;
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
  if Pos('{$', AText) + Pos('(*$', AText) = 0 then
    Exit;
  Options := TPreprocessorOptions.Default;
  Options.Defines := ADefines;
  Processed := TPascalPreprocessor.Process(AText, Options);
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
  const ADefines: TArray<string>): TUnitIndex;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(BlankInactive(AText, ADefines));
  try
    Result := Extract(Tree, AFileName);
  finally
    Tree.Free;
  end;
end;

end.
