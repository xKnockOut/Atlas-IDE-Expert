unit Atlas.Common.Editing.TypeAlias;

// Typ-Alias einführen und auflösen (#681):
//   - Targets: Typausdrücke an einer Stelle, für die ein Alias lohnt
//     (generische Typen mit Argumenten, Arrays, Mengen, Methodenreferenzen
//     und prozedurale Typen), der äußere zuerst; mit Namensvorschlag aus
//     dem Zusammenhang (Feld FGroups mit TList<TKunde> -> TKundeGroups).
//     Offene generische Parameter (TList<T> in TBox<T>) ergeben keinen
//     Alias, Delphi kennt keine generischen Aliase; OpenParams nennt sie.
//   - Introduce: schreibt "TName = Ausdruck;" in den type-Abschnitt vor der
//     ersten Verwendung (bei Bedarf mit Vorwärtsdeklaration der eigenen
//     Klasse), im Projekt immer in den interface-Teil, und ersetzt die
//     Stelle, alle gleichen Ausdrücke der Unit oder des Projekts. Gleich
//     heißt: gleiche aufgelöste Typen (TTypeAliasLookup.Key), nicht gleicher
//     Text. Andere Units nur, wenn sie die Unit einbinden.
//   - InlineAlias: ersetzt die Verwendungen eines Alias X = Y durch Y und
//     entfernt ihn, wenn keine bleibt. Ohne Typnamen (Array, Menge,
//     prozeduraler Typ) nur dort, wo Delphi einen Typausdruck annimmt
//     (Feld, Variable, Konstante, Typdeklaration, Element eines Arrays);
//     Parameter, Ergebnisse, Properties, Typargumente und Ausdrücke behalten
//     den Alias. X = type Y ist ein eigener Typ und wird nicht aufgelöst.
// Atlas schreibt immer die zuweisungsverträgliche Form X = Y.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Was ersetzt wird: nur die Stelle, alle gleichen Ausdrücke der Unit oder des Projekts.</summary>
  TTypeAliasScope = (Here, InUnit, Project);

  /// <summary>Schlüssel des Typnamens an ANode (TypeReference, ohne Typargumente) in ATree der Datei AFileName:
  /// Unit und Name des aufgelösten Typs; '' = unbekannt, dann zählt der Name.</summary>
  TTypeKeyFunc = reference to function(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode): string;
  /// <summary>Ist AName an AOffset in ATree schon sichtbar vergeben?</summary>
  TTypeNameTakenFunc = reference to function(ATree: TSyntaxTree; const AFileName, AName: string;
    AOffset: Integer): Boolean;
  /// <summary>Unit, die den Typnamen an ANode deklariert; '' = eingebaut oder unbekannt. AImplementation: nur im
  /// implementation-Teil dieser Unit deklariert.</summary>
  TTypeUnitFunc = reference to function(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
    out AImplementation: Boolean): string;

  TTypeAliasLookup = record
    Key: TTypeKeyFunc;
    NameTaken: TTypeNameTakenFunc;
    UnitOf: TTypeUnitFunc;
    /// <summary>Nur aus dem Baum: Schlüssel ist der letzte Teil des Namens, vergeben ist ein in der Unit
    /// deklarierter Name, Units unbekannt.</summary>
    class function FromTree: TTypeAliasLookup; static;
  end;

  TTypeAliasTarget = record
    StartOffset: Integer;
    EndOffset: Integer;
    Range: TTextRange;
    /// <summary>Der Ausdruck wie im Quelltext.</summary>
    TypeText: string;
    Kind: TSyntaxKind;
    /// <summary>Vorgeschlagener Name, in der Unit noch frei.</summary>
    Suggestion: string;
    /// <summary>Generische Parameter, die der Ausdruck nutzt, durch Komma getrennt; '' = keine.</summary>
    OpenParams: string;
  end;

  /// <summary>Eine Datei; Offsets nur beim Auflösen: Anfang jeder Verwendung des Alias (0-basiert).</summary>
  TTypeAliasSource = record
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    Offsets: TArray<Integer>;
    class function Create(const AFileName, AText: string; ATree: TSyntaxTree): TTypeAliasSource; overload; static;
    class function Create(const AFileName, AText: string; ATree: TSyntaxTree;
      const AOffsets: TArray<Integer>): TTypeAliasSource; overload; static;
  end;

  TTypeAliasFileEdits = record
    FileName: string;
    Edits: TArray<TTextEdit>;
  end;

  TTypeAliasResult = record
    Files: TArray<TTypeAliasFileEdits>;
    Warnings: TArray<string>;
    /// <summary>Ersetzte Stellen.</summary>
    Places: Integer;
    /// <summary>Was geschieht, dazu je Stelle "Datei, Zeile n".</summary>
    Preview: string;
  end;

  /// <summary>Ein Alias X = Y, der sich auflösen lässt.</summary>
  TInlineAliasTarget = record
    Name: string;
    TypeText: string;
    Kind: TSyntaxKind;
    NamePosition: TTextPosition;
  end;

  TTypeAlias = class
  public const
    IntroduceTitle = 'Typ-Alias einführen (%s)';
    HereTitle = 'Typ-Alias einführen, nur diese Stelle (%s)';
    UnitTitle = 'Typ-Alias einführen, in der Unit (%s)';
    ProjectTitle = 'Typ-Alias einführen, im Projekt (%s)';
    InlineTitle = 'Alias auflösen (%s)';
    /// <summary>Grund bei offenen generischen Parametern (%s: die Parameter).</summary>
    OpenParamsReason = 'Kein Typ-Alias: Der Ausdruck nutzt den generischen Parameter %s, und Delphi kennt keine ' +
      'generischen Aliase. Möglich wäre eine Ableitung TName<T> = class(TBasis<T>), die Atlas nicht selbst anlegt.';
    CompatibilityNote = 'Atlas schreibt X = Y: zuweisungsverträglich mit dem Ausdruck. X = type Y wäre ein ' +
      'eigener, nicht verträglicher Typ.';
  public
    /// <summary>Typausdrücke an APosition, für die ein Alias lohnt: der äußere zuerst, dann der innerste, wenn
    /// er ein anderer ist. Leer ohne Treffer.</summary>
    class function Targets(const AText: string; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition; const ALookup: TTypeAliasLookup): TArray<TTypeAliasTarget>; static;
    /// <summary>Schlüssel für die Gleichheit von Typausdrücken: aufgelöste Namen, Typargumente und der Text der
    /// übrigen Teile ohne Groß-/Kleinschreibung und Kommentare.</summary>
    class function KeyOf(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
      const ALookup: TTypeAliasLookup): string; static;
    /// <summary>Alias AName für den Ausdruck, der an APosition beginnt (aus Targets), in ADeclaring; im Projekt
    /// auch gleiche Ausdrücke in AOthers. False mit Grund, wenn es nicht geht.</summary>
    class function Introduce(const ADeclaring: TTypeAliasSource; const AOthers: TArray<TTypeAliasSource>;
      const APosition: TTextPosition; const AName: string; AScope: TTypeAliasScope;
      const ALookup: TTypeAliasLookup; out AResult: TTypeAliasResult; out AReason: string): Boolean; static;
    /// <summary>Alias X = Y, dessen Name in der Deklaration APosition enthält.</summary>
    class function InlineTarget(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      out ATarget: TInlineAliasTarget; out AReason: string): Boolean; static;
    /// <summary>Löst den Alias an APosition (Name in der Deklaration in ADeclaring) auf; die Verwendungen stehen in
    /// den Offsets von ADeclaring und AOthers.</summary>
    class function InlineAlias(const ADeclaring: TTypeAliasSource; const AOthers: TArray<TTypeAliasSource>;
      const APosition: TTextPosition; const ALookup: TTypeAliasLookup; out AResult: TTypeAliasResult;
      out AReason: string): Boolean; static;
    /// <summary>Name der Reichweite für Befehlsargumente und Einstellungen: here, unit, project.</summary>
    class function ScopeName(AScope: TTypeAliasScope): string; static;
    class function ScopeOf(const AName: string; out AScope: TTypeAliasScope): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.UsesClause;

const
  TypeKinds = [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.SetType, TSyntaxKind.ProcedureType,
    TSyntaxKind.PointerType, TSyntaxKind.ClassOfType, TSyntaxKind.SubrangeType, TSyntaxKind.FileType];
  /// <summary>Stellen, an denen ein Typausdruck ohne Typnamen stehen darf.</summary>
  AnonymousContexts = [TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.ConstDecl,
    TSyntaxKind.InlineConst, TSyntaxKind.TypeDecl, TSyntaxKind.ArrayType];
  /// <summary>Deklarationen, deren Typ einen Alias bekommen kann.</summary>
  DeclarationContexts = [TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.ConstDecl,
    TSyntaxKind.InlineConst, TSyntaxKind.Parameter, TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl];
  BuiltinNames: array[0..20] of string = ('string', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'Byte', 'Word',
    'Double', 'Single', 'Extended', 'Currency', 'Boolean', 'Char', 'AnsiString', 'UnicodeString', 'Pointer',
    'Variant', 'TObject', 'NativeInt', 'TDateTime', 'Real');

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

function Where(const AFileName: string; ALine: Integer): string;
begin
  Result := Format('%s, Zeile %d', [ExtractFileName(AFileName), ALine + 1]);
end;

function LastPart(const AName: string): string;
begin
  Result := AName;
  if Pos('.', Result) > 0 then
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

function Capitalized(const AName: string): string;
begin
  Result := AName;
  if Result <> '' then
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
end;

function IsUpper(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z']);
end;

/// <summary>TKunde -> Kunde, FGroups -> Groups; eingebaute Namen groß geschrieben.</summary>
function Bare(const AName: string): string;
begin
  Result := LastPart(Trim(AName));
  if (Length(Result) >= 2) and CharInSet(Result[1], ['T', 'F', 'L', 'A', 'G', 'I']) and IsUpper(Result[2]) then
    Result := Copy(Result, 2, MaxInt);
  Result := Capitalized(Result);
end;

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Tiefster Knoten, der AOffset enthält.</summary>
function NodeAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Index: Integer;
  Found: Boolean;
begin
  Result := ANode;
  repeat
    Found := False;
    for Index := 0 to Result.ChildCount - 1 do
      if (AOffset >= Result[Index].StartOffset) and (AOffset < Result[Index].EndOffset) then
      begin
        Result := Result[Index];
        Found := True;
        Break;
      end;
  until not Found;
end;

function IsTypeNode(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in TypeKinds);
end;

/// <summary>Lohnt ein Alias für ANode?</summary>
function Worth(ANode: TSyntaxNode): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.TypeReference:
      Result := ANode.FindChild(TSyntaxKind.GenericArgs) <> nil;
    TSyntaxKind.ArrayType, TSyntaxKind.SetType, TSyntaxKind.ProcedureType:
      Result := True;
  else
    Result := False;
  end;
end;

/// <summary>Gehört ANode zu einem Typausdruck: Typ, Typargumente oder Parameter eines prozeduralen Typs?</summary>
function InTypeChain(ANode: TSyntaxNode): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.GenericArgs:
      Result := True;
    TSyntaxKind.Parameters:
      Result := (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.ProcedureType);
    TSyntaxKind.Parameter:
      Result := (ANode.Parent <> nil) and InTypeChain(ANode.Parent);
  else
    Result := ANode.Kind in TypeKinds;
  end;
end;

function ChildIndex(AParent, AChild: TSyntaxNode): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to AParent.ChildCount - 1 do
    if AParent[Index] = AChild then
      Exit(Index);
end;

/// <summary>Darf ANode ein Alias werden? Nicht als ganze Typdeklaration (das ist schon einer) und nicht als offenes
/// Array eines Parameters (array of X wäre danach ein dynamisches Array).</summary>
function Allowed(ANode: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Parent := ANode.Parent;
  Result := (Parent <> nil) and (Parent.Kind <> TSyntaxKind.TypeDecl) and
    not ((ANode.Kind = TSyntaxKind.ArrayType) and (Parent.Kind = TSyntaxKind.Parameter));
  if Result and not IsTypeNode(Parent) and (Parent.Kind <> TSyntaxKind.GenericArgs) then
    Result := Parent.Kind in DeclarationContexts;
end;

/// <summary>Generische Parameter der umgebenden Typen und Routinen von ANode.</summary>
function GenericParamsAround(ANode: TSyntaxNode): TArray<string>;
var
  Current, Params: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  Current := ANode.Parent;
  while Current <> nil do
  begin
    Params := nil;
    if Current.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.RoutineHeader] then
      Params := Current.FindChild(TSyntaxKind.GenericParams);
    if (Params = nil) and (Current.Kind = TSyntaxKind.RoutineDecl) and
      (Current.FindChild(TSyntaxKind.RoutineHeader) <> nil) then
      Params := Current.FindChild(TSyntaxKind.RoutineHeader).FindChild(TSyntaxKind.GenericParams);
    if Params <> nil then
      for Index := 0 to Params.ChildCount - 1 do
        Result := Result + [Params[Index].Name];
    Current := Current.Parent;
  end;
end;

/// <summary>Die Namen aus AParams, die ANode als Typ nutzt, durch Komma getrennt.</summary>
function UsedParams(ANode: TSyntaxNode; const AParams: TArray<string>): string;
var
  Used: TArray<string>;
  Name: string;
begin
  Result := '';
  if AParams = nil then
    Exit;
  Used := nil;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if (AChild.Kind = TSyntaxKind.TypeReference) and (Pos('.', AChild.Name) = 0) and
        (IndexText(AChild.Name, AParams) >= 0) and (IndexText(AChild.Name, Used) < 0) then
        Used := Used + [AChild.Name];
      Result := True;
    end);
  for Name in Used do
    if Result = '' then
      Result := Name
    else
      Result := Result + ', ' + Name;
end;

/// <summary>Innerster benannter Typ: letztes Typargument bzw. Element, sonst der Name selbst.</summary>
function ElementName(ANode: TSyntaxNode): string;
var
  Args: TSyntaxNode;
  Index: Integer;
begin
  Result := '';
  case ANode.Kind of
    TSyntaxKind.TypeReference:
      begin
        Args := ANode.FindChild(TSyntaxKind.GenericArgs);
        if (Args <> nil) and (Args.ChildCount > 0) then
          Exit(ElementName(Args[Args.ChildCount - 1]));
        Result := Bare(ANode.Name);
      end;
    TSyntaxKind.ArrayType, TSyntaxKind.SetType:
      for Index := ANode.ChildCount - 1 downto 0 do
        if IsTypeNode(ANode[Index]) and (ANode[Index].Kind <> TSyntaxKind.SubrangeType) then
          Exit(ElementName(ANode[Index]));
  end;
end;

function ArrayDepth(ANode: TSyntaxNode): Integer;
var
  Index: Integer;
begin
  Result := 0;
  while (ANode <> nil) and (ANode.Kind = TSyntaxKind.ArrayType) do
  begin
    Inc(Result);
    Index := ANode.ChildCount - 1;
    if Index < 0 then
      Break;
    ANode := ANode[Index];
  end;
end;

/// <summary>Name aus der Deklaration um ANode: Feld, Variable, Parameter, Property, Routine; '' ohne.</summary>
function ContextName(ANode: TSyntaxNode): string;
var
  Owner: TSyntaxNode;
begin
  Result := '';
  Owner := ANode.Parent;
  if (Owner = nil) or not (Owner.Kind in DeclarationContexts) then
    Exit;
  Result := Trim(Owner.Name);
  if Pos(',', Result) > 0 then
    Result := Trim(Copy(Result, 1, Pos(',', Result) - 1));
  Result := Bare(Result);
  // Kurze Namen (A, I, LX) sagen nichts über den Typ.
  if Length(Result) < 3 then
    Result := '';
end;

function Suggest(ANode: TSyntaxNode): string;
var
  Base, Element, Own: string;
  Depth: Integer;
begin
  Base := ContextName(ANode);
  Element := ElementName(ANode);
  case ANode.Kind of
    TSyntaxKind.ProcedureType:
      begin
        if Base = '' then
          Base := 'Callback';
        if ANode.FindChild(TSyntaxKind.TypeReference) <> nil then
          Result := 'T' + Base + 'Func'
        else
          Result := 'T' + Base + 'Proc';
        if EndsText('FuncFunc', Result) or EndsText('ProcProc', Result) then
          Result := Copy(Result, 1, Length(Result) - 4);
      end;
    TSyntaxKind.TypeReference:
      begin
        Own := Bare(ANode.Name);
        if Base = '' then
          Result := 'T' + Element + Own
        else if ContainsText(Base, Element) then
          Result := 'T' + Base
        else
          Result := 'T' + Element + Base;
      end;
    TSyntaxKind.ArrayType:
      if Base <> '' then
        Result := 'T' + Base
      else
      begin
        Depth := ArrayDepth(ANode);
        if Depth = 2 then
          Result := 'T' + Element + 'Matrix'
        else if Depth > 2 then
          Result := Format('T%sArray%dD', [Element, Depth])
        else
          Result := 'T' + Element + 'Array';
      end;
  else
    if Base <> '' then
      Result := 'T' + Base
    else
      Result := 'T' + Element + 'Set';
  end;
end;

function IsIdentifier(const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := (AName <> '') and CharInSet(AName[1], ['A'..'Z', 'a'..'z', '_']) and
    not TPascalLexer.IsReservedWord(AName);
  for Index := 2 to Length(AName) do
    if not CharInSet(AName[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Exit(False);
end;

/// <summary>Abschnitt (interface, implementation) bzw. Wurzel, in dem ANode steht.</summary>
function SectionOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Parent <> nil) and not (Result.Kind in [TSyntaxKind.InterfaceSection,
    TSyntaxKind.ImplementationSection]) do
    Result := Result.Parent;
end;

/// <summary>Deklaration direkt unter dem Abschnitt, die ANode enthält.</summary>
function TopLevelOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Parent <> nil) and (Result.Parent.Parent <> nil) and
    not (Result.Parent.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) do
    Result := Result.Parent;
end;

function InInterface(ANode: TSyntaxNode): Boolean;
begin
  Result := SectionOf(ANode).Kind = TSyntaxKind.InterfaceSection;
end;

{ TTypeAliasLookup }

class function TTypeAliasLookup.FromTree: TTypeAliasLookup;
begin
  Result.Key :=
    function(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode): string
    begin
      Result := '';
    end;
  Result.NameTaken :=
    function(ATree: TSyntaxTree; const AFileName, AName: string; AOffset: Integer): Boolean
    var
      Taken: Boolean;
    begin
      Taken := False;
      ATree.Root.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          if (ANode.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl,
            TSyntaxKind.RoutineDecl, TSyntaxKind.Field, TSyntaxKind.PropertyDecl]) and
            SameText(LastPart(ANode.Name), AName) then
            Taken := True;
          Result := not Taken;
        end);
      Result := Taken;
    end;
  Result.UnitOf :=
    function(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode; out AImplementation: Boolean): string
    begin
      AImplementation := False;
      Result := '';
    end;
end;

{ TTypeAliasSource }

class function TTypeAliasSource.Create(const AFileName, AText: string; ATree: TSyntaxTree): TTypeAliasSource;
begin
  Result := Create(AFileName, AText, ATree, nil);
end;

class function TTypeAliasSource.Create(const AFileName, AText: string; ATree: TSyntaxTree;
  const AOffsets: TArray<Integer>): TTypeAliasSource;
begin
  Result.FileName := AFileName;
  Result.Text := AText;
  Result.Tree := ATree;
  Result.Offsets := AOffsets;
end;

{ TTypeAlias }

class function TTypeAlias.ScopeName(AScope: TTypeAliasScope): string;
begin
  case AScope of
    TTypeAliasScope.Here:
      Result := 'here';
    TTypeAliasScope.Project:
      Result := 'project';
  else
    Result := 'unit';
  end;
end;

class function TTypeAlias.ScopeOf(const AName: string; out AScope: TTypeAliasScope): Boolean;
begin
  Result := True;
  if SameText(AName, 'here') then
    AScope := TTypeAliasScope.Here
  else if SameText(AName, 'unit') then
    AScope := TTypeAliasScope.InUnit
  else if SameText(AName, 'project') then
    AScope := TTypeAliasScope.Project
  else
  begin
    AScope := TTypeAliasScope.InUnit;
    Result := False;
  end;
end;

class function TTypeAlias.KeyOf(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  const ALookup: TTypeAliasLookup): string;
var
  Args, Child: TSyntaxNode;
  Index: Integer;
  Name: string;
  Inner: TArray<TSyntaxNode>;
  Token: TPascalToken;
  Skip: Integer;
  Parts: TArray<string>;
begin
  if ANode.Kind = TSyntaxKind.TypeReference then
  begin
    Name := '';
    if Assigned(ALookup.Key) then
      Name := ALookup.Key(ATree, AFileName, ANode);
    if Name = '' then
      Name := LastPart(ANode.Name);
    Result := LowerCase(Name);
    Args := ANode.FindChild(TSyntaxKind.GenericArgs);
    if Args <> nil then
    begin
      Parts := nil;
      for Index := 0 to Args.ChildCount - 1 do
        Parts := Parts + [KeyOf(ATree, AFileName, Args[Index], ALookup)];
      Result := Result + '<' + string.Join(',', Parts) + '>';
    end;
    Exit;
  end;
  // Übrige Ausdrücke: Text ohne Kommentare, Typnamen darin über ihren Schlüssel.
  Inner := nil;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      Result := True;
      if (AChild <> ANode) and (AChild.Kind = TSyntaxKind.TypeReference) then
      begin
        Inner := Inner + [AChild];
        Result := False;
      end;
    end);
  Parts := nil;
  Skip := -1;
  for Token in ATree.Tokens do
  begin
    if (Token.Offset < ANode.StartOffset) or (Token.Offset >= ANode.EndOffset) or (Token.Offset < Skip) or
      (Token.Kind = TPascalTokenKind.Comment) then
      Continue;
    Child := nil;
    for Index := 0 to High(Inner) do
      if (Token.Offset >= Inner[Index].StartOffset) and (Token.Offset < Inner[Index].EndOffset) then
        Child := Inner[Index];
    if Child <> nil then
    begin
      Parts := Parts + [KeyOf(ATree, AFileName, Child, ALookup)];
      Skip := Child.EndOffset;
    end
    else
      Parts := Parts + [LowerCase(Token.Text)];
  end;
  Result := string.Join(' ', Parts);
end;

/// <summary>Freier Name ab ABase: ABase, ABase2, ABase3 …</summary>
function FreeName(ATree: TSyntaxTree; const AFileName, ABase: string; AOffset: Integer;
  const ALookup: TTypeAliasLookup): string;
var
  Number: Integer;
begin
  Result := ABase;
  Number := 1;
  while Assigned(ALookup.NameTaken) and ALookup.NameTaken(ATree, AFileName, Result, AOffset) and (Number < 50) do
  begin
    Inc(Number);
    Result := ABase + IntToStr(Number);
  end;
end;

function MakeTarget(const AText: string; ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  const ALines: TLineTable; const ALookup: TTypeAliasLookup): TTypeAliasTarget;
begin
  Result := Default(TTypeAliasTarget);
  Result.StartOffset := ANode.StartOffset;
  Result.EndOffset := ANode.EndOffset;
  Result.Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  Result.TypeText := NodeText(AText, ANode);
  Result.Kind := ANode.Kind;
  Result.OpenParams := UsedParams(ANode, GenericParamsAround(ANode));
  Result.Suggestion := FreeName(ATree, AFileName, Suggest(ANode), ANode.StartOffset, ALookup);
end;

class function TTypeAlias.Targets(const AText: string; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; const ALookup: TTypeAliasLookup): TArray<TTypeAliasTarget>;
var
  Lines: TLineTable;
  Node, Outer, Inner: TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Lines := TLineTable.Build(AText);
  Node := NodeAt(ATree.Root, Lines.OffsetAt(APosition));
  Outer := nil;
  Inner := nil;
  while (Node <> nil) and InTypeChain(Node) do
  begin
    if (Node.Kind in TypeKinds) and Worth(Node) and Allowed(Node) then
    begin
      if Inner = nil then
        Inner := Node;
      Outer := Node;
    end;
    Node := Node.Parent;
  end;
  if Outer = nil then
    Exit;
  Result := [MakeTarget(AText, ATree, AFileName, Outer, Lines, ALookup)];
  if Inner <> Outer then
    Result := Result + [MakeTarget(AText, ATree, AFileName, Inner, Lines, ALookup)];
end;

type
  /// <summary>Eine zu ersetzende Stelle.</summary>
  TAliasSite = record
    Node: TSyntaxNode;
    Start: Integer;
    Stop: Integer;
  end;

/// <summary>Alle Ausdrücke in ATree mit dem Schlüssel AKey, die ein Alias ersetzen darf; ineinander liegende nur
/// einmal (der äußere).</summary>
function SitesIn(ATree: TSyntaxTree; const AFileName, AKey: string; AKind: TSyntaxKind;
  const ALookup: TTypeAliasLookup): TArray<TAliasSite>;
var
  Sites: TArray<TAliasSite>;
begin
  Sites := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Site: TAliasSite;
    begin
      Result := True;
      if (ANode.Kind <> AKind) or not Allowed(ANode) or
        (UsedParams(ANode, GenericParamsAround(ANode)) <> '') or
        (TTypeAlias.KeyOf(ATree, AFileName, ANode, ALookup) <> AKey) then
        Exit;
      Site.Node := ANode;
      Site.Start := ANode.StartOffset;
      Site.Stop := ANode.EndOffset;
      Sites := Sites + [Site];
      Result := False;
    end);
  Result := Sites;
end;

/// <summary>Anfang der Zeile von AOffset, über unmittelbar darüber stehende Kommentarzeilen hinweg.</summary>
function LineAbove(const ALines: TLineTable; const AText: string; AOffset: Integer): Integer;
var
  Line: Integer;
  Content: string;
begin
  Line := ALines.PositionAt(AOffset).Line;
  while Line > 0 do
  begin
    Content := Trim(Copy(AText, ALines.LineStart(Line - 1) + 1, ALines.LineContentEnd(Line - 1) -
      ALines.LineStart(Line - 1)));
    if not (StartsStr('//', Content) or StartsStr('{', Content) and not StartsStr('{$', Content) or
      StartsStr('(*', Content)) then
      Break;
    Dec(Line);
  end;
  Result := ALines.LineStart(Line);
end;

/// <summary>In der Unit deklarierter Typ (oberste Ebene) namens AName, ohne Vorwärtsdeklarationen; nil ohne.
/// AForwardEnd: Ende der ersten Vorwärtsdeklaration, sonst -1.</summary>
function LocalType(ATree: TSyntaxTree; const AName: string; out AForwardEnd: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
  ForwardEnd: Integer;
begin
  Found := nil;
  ForwardEnd := -1;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := ANode.Kind in [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile,
        TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection];
      if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) then
      begin
        if ANode.FindChild(TSyntaxKind.ForwardType) <> nil then
        begin
          if ForwardEnd < 0 then
            ForwardEnd := ANode.EndOffset;
        end
        else if Found = nil then
          Found := ANode;
      end;
    end);
  AForwardEnd := ForwardEnd;
  Result := Found;
end;

/// <summary>Typnamen in ANode (auch in Typargumenten und Elementen).</summary>
function NamesIn(ANode: TSyntaxNode): TArray<TSyntaxNode>;
var
  Names: TArray<TSyntaxNode>;
begin
  Names := nil;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if AChild.Kind = TSyntaxKind.TypeReference then
        Names := Names + [AChild];
      Result := True;
    end);
  Result := Names;
end;

/// <summary>Bindet die Unit von ATree AUnitName so ein, dass die Stelle an AOffset sie sieht?</summary>
function SeesUnit(ATree: TSyntaxTree; const AUnitName: string; AOffset: Integer): Boolean;
var
  Reference: TUsesReference;
  Implementation_: TSyntaxNode;
  InImplementation, Before: Boolean;
begin
  Result := False;
  Implementation_ := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  InImplementation := (Implementation_ <> nil) and (AOffset >= Implementation_.StartOffset);
  for Reference in TUsesClauses.References(ATree.Tokens) do
  begin
    if (Reference.List <> TUsesListKind.UsesList) or not (SameText(Reference.Name, AUnitName) or
      EndsText('.' + AUnitName, Reference.Name)) then
      Continue;
    Before := (Implementation_ = nil) or (Reference.Range.StartPos.Line < Implementation_.StartPos.Line) or
      (Reference.Range.StartPos.Line = Implementation_.StartPos.Line) and
      (Reference.Range.StartPos.Character < Implementation_.StartPos.Character);
    if InImplementation or Before then
      Exit(True);
  end;
end;

type
  TFileChange = record
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    Edits: TArray<TTextEdit>;
  end;

/// <summary>Prüft, dass jede Datei nach den Änderungen so fehlerfrei parst wie vorher, und baut das Ergebnis.
/// </summary>
function Finish(const AChanges: TArray<TFileChange>; var AResult: TTypeAliasResult; out AReason: string): Boolean;
var
  Change: TFileChange;
  Item: TTypeAliasFileEdits;
  Tree: TSyntaxTree;
begin
  Result := False;
  for Change in AChanges do
  begin
    if Change.Edits = nil then
      Continue;
    Tree := TPascalParser.Parse(TChangeSignature.ApplyEdits(Change.Text, Change.Edits));
    try
      if Length(Tree.Diagnostics) > Length(Change.Tree.Diagnostics) then
        Exit(Fail(Format('Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s)',
          [ExtractFileName(Change.FileName), Tree.Diagnostics[0].StartPos.Line + 1, Tree.Diagnostics[0].Message]),
          AReason));
    finally
      Tree.Free;
    end;
    Item.FileName := Change.FileName;
    Item.Edits := Change.Edits;
    AResult.Files := AResult.Files + [Item];
  end;
  Result := True;
end;

function Edit(const ALines: TLineTable; AStart, AStop: Integer; const AText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ALines.PositionAt(AStart), ALines.PositionAt(AStop)), AText);
end;

class function TTypeAlias.Introduce(const ADeclaring: TTypeAliasSource; const AOthers: TArray<TTypeAliasSource>;
  const APosition: TTextPosition; const AName: string; AScope: TTypeAliasScope; const ALookup: TTypeAliasLookup;
  out AResult: TTypeAliasResult; out AReason: string): Boolean;
var
  Lines, OtherLines: TLineTable;
  Candidates: TArray<TTypeAliasTarget>;
  Target: TTypeAliasTarget;
  Node, First, Top, Section, Previous, Local, NameNode: TSyntaxNode;
  Sites, OtherSites: TArray<TAliasSite>;
  Site: TAliasSite;
  Key, LineBreak, Indent, Declaration, UnitName, Forwards, ForwardKind, Visible: string;
  Insert, ForwardEnd, Index, Skipped: Integer;
  ExportNeeded, AllInInterface: Boolean;
  Change: TFileChange;
  Changes: TArray<TFileChange>;
  Other: TTypeAliasSource;
  PreviewLines: TArray<string>;
  FileCount: Integer;
begin
  Result := False;
  AResult := Default(TTypeAliasResult);
  AReason := '';
  if not IsIdentifier(AName) then
    Exit(Fail(Format('"%s" ist kein gültiger Bezeichner', [AName]), AReason));
  Lines := TLineTable.Build(ADeclaring.Text);
  Candidates := Targets(ADeclaring.Text, ADeclaring.Tree, ADeclaring.FileName, APosition, ALookup);
  if Candidates = nil then
    Exit(Fail('Hier steht kein Typausdruck, für den ein Alias lohnt', AReason));
  Target := Candidates[0];
  for Index := 1 to High(Candidates) do
    if Candidates[Index].StartOffset = Lines.OffsetAt(APosition) then
      Target := Candidates[Index];
  if Target.OpenParams <> '' then
    Exit(Fail(Format(OpenParamsReason, [Target.OpenParams]), AReason));
  Node := NodeAt(ADeclaring.Tree.Root, Target.StartOffset);
  while (Node <> nil) and not ((Node.Kind = Target.Kind) and (Node.StartOffset = Target.StartOffset) and
    (Node.EndOffset = Target.EndOffset)) do
    Node := Node.Parent;
  if Node = nil then
    Exit(Fail('Hier steht kein Typausdruck, für den ein Alias lohnt', AReason));
  Key := KeyOf(ADeclaring.Tree, ADeclaring.FileName, Node, ALookup);
  // Stellen der Unit.
  if AScope = TTypeAliasScope.Here then
  begin
    Site.Node := Node;
    Site.Start := Node.StartOffset;
    Site.Stop := Node.EndOffset;
    Sites := [Site];
  end
  else
    Sites := SitesIn(ADeclaring.Tree, ADeclaring.FileName, Key, Node.Kind, ALookup);
  First := Node;
  for Site in Sites do
    if Site.Start < First.StartOffset then
      First := Site.Node;
  // Im Projekt steht der Alias im interface-Teil, sonst sehen ihn andere Units nicht.
  ExportNeeded := (AScope = TTypeAliasScope.Project) and (AOthers <> nil) and not InInterface(First);
  AllInInterface := True;
  for NameNode in NamesIn(Node) do
    if (LocalType(ADeclaring.Tree, LastPart(NameNode.Name), ForwardEnd) <> nil) and
      not InInterface(LocalType(ADeclaring.Tree, LastPart(NameNode.Name), ForwardEnd)) then
      AllInInterface := False;
  if ExportNeeded and not AllInInterface then
  begin
    ExportNeeded := False;
    AScope := TTypeAliasScope.InUnit;
    AResult.Warnings := AResult.Warnings + [Format('%s nutzt Typen aus dem implementation-Teil; ersetzt wird nur ' +
      'in dieser Unit', [Target.TypeText])];
  end;
  if Assigned(ALookup.NameTaken) and ALookup.NameTaken(ADeclaring.Tree, ADeclaring.FileName, AName,
    First.StartOffset) then
    Exit(Fail(Format('Der Name %s ist schon vergeben', [AName]), AReason));
  // Einfügestelle: vor der Typdeklaration mit der ersten Verwendung, sonst ein neuer type-Abschnitt.
  LineBreak := TTextLines.LineBreakOf(ADeclaring.Text);
  Section := SectionOf(First);
  if ExportNeeded then
  begin
    Section := ADeclaring.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
    if Section = nil then
      Exit(Fail('Die Unit hat keinen interface-Teil', AReason));
    Top := nil;
    if Section.ChildCount > 0 then
      Top := Section[Section.ChildCount - 1];
  end
  else
    Top := TopLevelOf(First);
  Forwards := '';
  Indent := '  ';
  if ExportNeeded then
  begin
    // Ans Ende des interface-Teils: in den letzten type-Abschnitt oder als neuer Abschnitt.
    if (Top <> nil) and (Top.Kind = TSyntaxKind.TypeSection) and (Top.ChildCount > 0) then
    begin
      Insert := Lines.LineStart(Lines.PositionAt(Top[Top.ChildCount - 1].EndOffset).Line + 1);
      Indent := TTextLines.IndentOf(ADeclaring.Text,
        Lines.PositionAt(Top[Top.ChildCount - 1].StartOffset).Line);
      Declaration := Indent + AName + ' = ' + Target.TypeText + ';' + LineBreak;
    end
    else
    begin
      Insert := Lines.LineStart(Lines.PositionAt(Section.EndOffset).Line);
      if (Top <> nil) then
        Insert := Lines.LineStart(Lines.PositionAt(Top.EndOffset).Line + 1);
      Declaration := LineBreak + 'type' + LineBreak + Indent + AName + ' = ' + Target.TypeText + ';' + LineBreak;
    end;
  end
  else if Top.Kind = TSyntaxKind.TypeSection then
  begin
    // Die Typdeklaration des Abschnitts, in der die erste Verwendung steht.
    for Index := 0 to Top.ChildCount - 1 do
      if (First.StartOffset >= Top[Index].StartOffset) and (First.StartOffset < Top[Index].EndOffset) then
      begin
        Top := Top[Index];
        Break;
      end;
    Insert := LineAbove(Lines, ADeclaring.Text, Top.StartOffset);
    Indent := TTextLines.IndentOf(ADeclaring.Text, Lines.PositionAt(Top.StartOffset).Line);
    Declaration := Indent + AName + ' = ' + Target.TypeText + ';' + LineBreak;
  end
  else
  begin
    Previous := nil;
    Index := ChildIndex(Section, Top);
    if Index > 0 then
      Previous := Section[Index - 1];
    if (Previous <> nil) and (Previous.Kind = TSyntaxKind.TypeSection) and (Previous.ChildCount > 0) then
    begin
      Insert := Lines.LineStart(Lines.PositionAt(Previous[Previous.ChildCount - 1].EndOffset).Line + 1);
      Indent := TTextLines.IndentOf(ADeclaring.Text,
        Lines.PositionAt(Previous[Previous.ChildCount - 1].StartOffset).Line);
      Declaration := Indent + AName + ' = ' + Target.TypeText + ';' + LineBreak;
    end
    else
    begin
      Insert := LineAbove(Lines, ADeclaring.Text, Top.StartOffset);
      Declaration := 'type' + LineBreak + Indent + AName + ' = ' + Target.TypeText + ';' + LineBreak + LineBreak;
    end;
  end;
  // Typen der Unit, die der Ausdruck nennt, müssen vor dem Alias stehen; die eigene Klasse geht per
  // Vorwärtsdeklaration.
  for NameNode in NamesIn(Node) do
  begin
    Local := LocalType(ADeclaring.Tree, LastPart(NameNode.Name), ForwardEnd);
    if (Local = nil) or (Local.EndOffset <= Insert) or (ForwardEnd >= 0) and (ForwardEnd <= Insert) then
      Continue;
    if (Local.StartOffset <= First.StartOffset) and (First.StartOffset < Local.EndOffset) and
      (Top <> nil) and (Local = Top) and (Local.FindChild(TSyntaxKind.ClassType) <> nil) then
      ForwardKind := 'class'
    else if (Local.StartOffset <= First.StartOffset) and (First.StartOffset < Local.EndOffset) and
      (Top <> nil) and (Local = Top) and (Local.FindChild(TSyntaxKind.InterfaceType) <> nil) then
      ForwardKind := 'interface'
    else
      Exit(Fail(Format('%s ist vor der ersten Verwendung von %s noch nicht deklariert', [Local.Name,
        Target.TypeText]), AReason));
    if not ContainsText(Forwards, ' ' + Local.Name + ' = ') then
      Forwards := Forwards + Indent + Local.Name + ' = ' + ForwardKind + ';' + LineBreak;
    AResult.Warnings := AResult.Warnings + [Format('%s bekommt eine Vorwärtsdeklaration vor dem Alias',
      [Local.Name])];
  end;
  Change := Default(TFileChange);
  Change.FileName := ADeclaring.FileName;
  Change.Text := ADeclaring.Text;
  Change.Tree := ADeclaring.Tree;
  if Forwards <> '' then
    Declaration := Forwards + Declaration;
  Change.Edits := [Edit(Lines, Insert, Insert, Declaration)];
  PreviewLines := nil;
  for Site in Sites do
  begin
    Change.Edits := Change.Edits + [Edit(Lines, Site.Start, Site.Stop, AName)];
    PreviewLines := PreviewLines + [Where(ADeclaring.FileName, Lines.PositionAt(Site.Start).Line)];
  end;
  AResult.Places := Length(Sites);
  Changes := [Change];
  // Andere Units des Projekts: nur, wenn sie die Unit einbinden und den Namen nicht selbst vergeben.
  if (AScope = TTypeAliasScope.Project) and (InInterface(First) or ExportNeeded) then
  begin
    UnitName := TUsesClauses.OwnName(ADeclaring.Tree.Tokens);
    for Other in AOthers do
    begin
      if SameText(Other.FileName, ADeclaring.FileName) or (Other.Tree = nil) then
        Continue;
      OtherSites := SitesIn(Other.Tree, Other.FileName, Key, Node.Kind, ALookup);
      if OtherSites = nil then
        Continue;
      Change := Default(TFileChange);
      Change.FileName := Other.FileName;
      Change.Text := Other.Text;
      Change.Tree := Other.Tree;
      OtherLines := TLineTable.Build(Other.Text);
      Skipped := 0;
      for Site in OtherSites do
      begin
        if not SeesUnit(Other.Tree, UnitName, Site.Start) or Assigned(ALookup.NameTaken) and
          ALookup.NameTaken(Other.Tree, Other.FileName, AName, Site.Start) then
        begin
          Inc(Skipped);
          Continue;
        end;
        Change.Edits := Change.Edits + [Edit(OtherLines, Site.Start, Site.Stop, AName)];
        PreviewLines := PreviewLines + [Where(Other.FileName, OtherLines.PositionAt(Site.Start).Line)];
        Inc(AResult.Places);
      end;
      if Skipped > 0 then
        AResult.Warnings := AResult.Warnings + [Format('%s: %d gleiche Ausdrücke bleiben (%s nicht eingebunden ' +
          'oder %s dort vergeben)', [ExtractFileName(Other.FileName), Skipped, UnitName, AName])];
      if Change.Edits <> nil then
        Changes := Changes + [Change];
    end;
  end
  else if (AScope = TTypeAliasScope.Project) and (AOthers <> nil) then
    AResult.Warnings := AResult.Warnings + [Format('%s steht im implementation-Teil; andere Units sehen ihn nicht',
      [AName])];
  if not Finish(Changes, AResult, AReason) then
    Exit;
  FileCount := Length(AResult.Files);
  Visible := 'implementation-Teil';
  if InInterface(First) or ExportNeeded then
    Visible := 'interface-Teil';
  AResult.Preview := Format('%s = %s; im %s, %d Stellen in %d Dateien.', [AName, Target.TypeText, Visible,
    AResult.Places, FileCount]) + sLineBreak + CompatibilityNote;
  if PreviewLines <> nil then
    AResult.Preview := AResult.Preview + sLineBreak + string.Join(sLineBreak, PreviewLines);
  Result := True;
end;

class function TTypeAlias.InlineTarget(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  out ATarget: TInlineAliasTarget; out AReason: string): Boolean;
var
  Lines: TLineTable;
  Node, Expression: TSyntaxNode;
  Index, Offset: Integer;
  Token: TPascalToken;
begin
  ATarget := Default(TInlineAliasTarget);
  AReason := '';
  if (ATree = nil) or (ATree.Root = nil) then
    Exit(Fail('kein Baum', AReason));
  Lines := TLineTable.Build(AText);
  Offset := Lines.OffsetAt(APosition);
  Node := NodeAt(ATree.Root, Offset);
  while (Node <> nil) and (Node.Kind <> TSyntaxKind.TypeDecl) do
    Node := Node.Parent;
  if (Node = nil) or (Offset >= Node.StartOffset + Length(Node.Name)) then
    Exit(Fail('Hier steht kein Typ-Alias', AReason));
  if Node.FindChild(TSyntaxKind.GenericParams) <> nil then
    Exit(Fail(Format('%s ist generisch', [Node.Name]), AReason));
  Expression := nil;
  for Index := 0 to Node.ChildCount - 1 do
    if Node[Index].Kind in TypeKinds then
      Expression := Node[Index];
  if (Expression = nil) or (Node.ChildCount <> 1) then
    Exit(Fail(Format('%s ist kein Alias', [Node.Name]), AReason));
  // X = type Y: eigener Typ.
  for Token in ATree.Tokens do
    if (Token.Offset > Node.StartOffset) and (Token.Offset < Expression.StartOffset) and Token.IsKeyword('type') then
      Exit(Fail(Format('%s = type … ist ein eigener Typ; Auflösen würde die Bedeutung ändern', [Node.Name]),
        AReason));
  ATarget.Name := Node.Name;
  ATarget.TypeText := NodeText(AText, Expression);
  ATarget.Kind := Expression.Kind;
  ATarget.NamePosition := Node.StartPos;
  Result := True;
end;

/// <summary>Der Knoten, den eine Verwendung an AOffset ersetzt: TypeReference, Bezeichner oder qualifizierter
/// Zugriff Unit.X; ATypePosition: an der Stelle steht ein Typ (kein Ausdruck).</summary>
function UseNode(ATree: TSyntaxTree; AOffset: Integer; out ATypePosition: Boolean): TSyntaxNode;
begin
  Result := NodeAt(ATree.Root, AOffset);
  ATypePosition := False;
  while (Result <> nil) and not (Result.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.Identifier,
    TSyntaxKind.MemberAccess]) do
    Result := Result.Parent;
  if Result = nil then
    Exit;
  ATypePosition := Result.Kind = TSyntaxKind.TypeReference;
  // Unit.X als Ausdruck liefert NodeAt als MemberAccess selbst, X.Create dagegen den Bezeichner X darin.
end;

class function TTypeAlias.InlineAlias(const ADeclaring: TTypeAliasSource; const AOthers: TArray<TTypeAliasSource>;
  const APosition: TTextPosition; const ALookup: TTypeAliasLookup; out AResult: TTypeAliasResult;
  out AReason: string): Boolean;
var
  Target: TInlineAliasTarget;
  Lines, FileLines: TLineTable;
  Decl, Expression, Use, Section: TSyntaxNode;
  Sources: TArray<TTypeAliasSource>;
  Source: TTypeAliasSource;
  Offset, Kept, FirstSite, Start, Stop, Index: Integer;
  TypePosition, Named, Hidden, Own, Implementation_: Boolean;
  Change: TFileChange;
  Changes: TArray<TFileChange>;
  PreviewLines, Units: TArray<string>;
  UnitName, OwnName, LineBreak: string;
  NameNode: TSyntaxNode;
  UsesEdit: TTextEdit;
begin
  Result := False;
  AResult := Default(TTypeAliasResult);
  if not InlineTarget(ADeclaring.Text, ADeclaring.Tree, APosition, Target, AReason) then
    Exit;
  Lines := TLineTable.Build(ADeclaring.Text);
  Decl := NodeAt(ADeclaring.Tree.Root, Lines.OffsetAt(Target.NamePosition));
  while (Decl <> nil) and (Decl.Kind <> TSyntaxKind.TypeDecl) do
    Decl := Decl.Parent;
  Expression := Decl[0];
  Named := Expression.Kind = TSyntaxKind.TypeReference;
  OwnName := TUsesClauses.OwnName(ADeclaring.Tree.Tokens);
  // Units der Typen im Ausdruck, für andere Units; Typen aus dem implementation-Teil sehen sie nicht.
  Units := nil;
  Hidden := not InInterface(Decl);
  for NameNode in NamesIn(Expression) do
  begin
    UnitName := '';
    Implementation_ := False;
    if Assigned(ALookup.UnitOf) then
      UnitName := ALookup.UnitOf(ADeclaring.Tree, ADeclaring.FileName, NameNode, Implementation_);
    if Implementation_ then
      Hidden := True;
    if (UnitName <> '') and (IndexText(UnitName, Units) < 0) then
      Units := Units + [UnitName];
  end;
  Sources := TArray<TTypeAliasSource>.Create(ADeclaring) + AOthers;
  Changes := nil;
  PreviewLines := nil;
  Kept := 0;
  for Source in Sources do
  begin
    Own := SameText(Source.FileName, ADeclaring.FileName);
    if (Source.Tree = nil) or (Source.Offsets = nil) then
      Continue;
    if not Own and Hidden then
    begin
      Inc(Kept, Length(Source.Offsets));
      Continue;
    end;
    Change := Default(TFileChange);
    Change.FileName := Source.FileName;
    Change.Text := Source.Text;
    Change.Tree := Source.Tree;
    FileLines := TLineTable.Build(Source.Text);
    FirstSite := -1;
    for Offset in Source.Offsets do
    begin
      if Own and (Offset >= Decl.StartOffset) and (Offset < Decl.StartOffset + Length(Decl.Name)) then
        Continue;
      Use := UseNode(Source.Tree, Offset, TypePosition);
      if Use = nil then
      begin
        Inc(Kept);
        Continue;
      end;
      // Ohne Typnamen nimmt Delphi den Ausdruck nur in Deklarationen von Feldern, Variablen, Konstanten und
      // Typen an, nicht in Parametern, Ergebnissen, Properties, Typargumenten und Ausdrücken.
      if not Named and not (TypePosition and (Use.Parent <> nil) and (Use.Parent.Kind in AnonymousContexts)) then
      begin
        Inc(Kept);
        Continue;
      end;
      Start := Use.StartOffset;
      Stop := Use.EndOffset;
      if Use.Kind = TSyntaxKind.TypeReference then
        Stop := Use.StartOffset + Length(Use.Name);
      Change.Edits := Change.Edits + [Edit(FileLines, Start, Stop, Target.TypeText)];
      PreviewLines := PreviewLines + [Where(Source.FileName, FileLines.PositionAt(Start).Line)];
      Inc(AResult.Places);
      if (FirstSite < 0) or InInterface(Use) and not InInterface(NodeAt(Source.Tree.Root, FirstSite)) then
        FirstSite := Start;
    end;
    // Fehlende uses für die Typen des Ausdrucks.
    if not Own and (FirstSite >= 0) then
    begin
      LineBreak := TTextLines.LineBreakOf(Source.Text);
      for UnitName in Units do
        if not SameText(UnitName, TUsesClauses.OwnName(Source.Tree.Tokens)) and
          not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(Source.Tree.Tokens), UnitName, nil) then
        begin
          if not TUsesClauses.AddUnit(Source.Tree.Tokens, FirstSite, UnitName, LineBreak, UsesEdit) then
            Exit(Fail(Format('%s: uses für %s lässt sich nicht ergänzen', [ExtractFileName(Source.FileName),
              UnitName]), AReason));
          Change.Edits := Change.Edits + [UsesEdit];
        end;
    end;
    if Change.Edits <> nil then
      Changes := Changes + [Change];
  end;
  // Ohne verbliebene Verwendung fällt der Alias weg, mit seinem type-Abschnitt, wenn er der einzige war.
  if Kept = 0 then
  begin
    Section := Decl.Parent;
    if (Section <> nil) and (Section.Kind = TSyntaxKind.TypeSection) and (Section.ChildCount = 1) then
    begin
      Start := Lines.LineStart(Section.StartPos.Line);
      Stop := Lines.LineStart(Section.EndPos.Line + 1);
    end
    else
    begin
      Start := Lines.LineStart(Decl.StartPos.Line);
      Stop := Lines.LineStart(Decl.EndPos.Line + 1);
    end;
    if Decl.EndPos.Line + 1 >= Lines.LineCount then
      Stop := Length(ADeclaring.Text);
    Index := -1;
    for Offset := 0 to High(Changes) do
      if SameText(Changes[Offset].FileName, ADeclaring.FileName) then
        Index := Offset;
    if Index < 0 then
    begin
      Change := Default(TFileChange);
      Change.FileName := ADeclaring.FileName;
      Change.Text := ADeclaring.Text;
      Change.Tree := ADeclaring.Tree;
      Changes := Changes + [Change];
      Index := High(Changes);
    end;
    Changes[Index].Edits := Changes[Index].Edits + [Edit(Lines, Start, Stop, '')];
  end
  else
    AResult.Warnings := AResult.Warnings + [Format('%d Verwendungen behalten %s (Parameter, Ergebnis, Property, ' +
      'Typargument, Ausdruck oder eine Unit, die den Typ nicht sieht); der Alias bleibt', [Kept, Target.Name])];
  if AResult.Places = 0 then
    if Kept = 0 then
      AResult.Warnings := AResult.Warnings + [Format('%s wird nirgends verwendet', [Target.Name])]
    else
      Exit(Fail(Format('Keine Verwendung von %s lässt sich ersetzen', [Target.Name]), AReason));
  if not Finish(Changes, AResult, AReason) then
    Exit;
  AResult.Preview := Format('%s wird durch %s ersetzt, %d Stellen in %d Dateien', [Target.Name, Target.TypeText,
    AResult.Places, Length(AResult.Files)]);
  if Kept = 0 then
    AResult.Preview := AResult.Preview + '; der Alias entfällt.'
  else
    AResult.Preview := AResult.Preview + '.';
  if PreviewLines <> nil then
    AResult.Preview := AResult.Preview + sLineBreak + string.Join(sLineBreak, PreviewLines);
  Result := True;
end;

end.
