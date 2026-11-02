unit Atlas.Common.Rules.Builtin.FormFields;

// Abgleich von Formularklasse und Formulardatei (#123):
//   form-field-without-object   published-Feld ohne Objekt in der .dfm/.fmx
//   form-object-without-field   Objekt der Formulardatei ohne Feld in der Klasse
//   form-field-type-mismatch    Feld und Objekt mit verschiedener Klasse
//   form-access-before-create   Konstruktor, AfterConstruction oder OnCreate eines automatisch erzeugten
//                               Formulars benutzt die globale Variable eines Formulars, das laut
//                               Application.CreateForm in der .dpr erst danach entsteht (#956). Die
//                               Reihenfolge kommt über TRuleContext.AutoCreateForms vom Server. Still bei
//                               Assigned/nil-Vergleich, eigener Zuweisung, CreateForm und lokalen Namen.
//
// Die Formulardatei neben der Unit kommt über TRuleContext.FormText; ohne sie
// prüfen die Regeln nichts. Geerbte Objekte (inherited) gehören zu Feldern des
// Vorfahren, Objekte in inline-Frames zur Frame-Klasse, Komponenten ohne Namen
// und Collection-Einträge haben kein Feld; sie werden nicht gemeldet. Felder
// außerhalb von published zählen nicht als fehlende Objekte. Kennt der
// Symbolindex die Klasse aus der Formulardatei nicht, entfällt der Typvergleich.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TFormFieldWithoutObjectRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TFormObjectWithoutFieldRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TFormFieldTypeMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TFormAccessBeforeCreateRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Variablen aus Application.CreateForm(TKlasse, Variable) der .dpr in Aufrufreihenfolge.</summary>
    class function AutoCreatedForms(const AMainSource: string): TArray<string>; static;
    /// <summary>AutoCreatedForms des ersten Programms aus APrograms (Quelltexte der .dpr), dessen uses die Unit
    /// AUnitName nennt; nil ohne (Linter, Golden-Korpus).</summary>
    class function FormsOfProgram(const APrograms: TArray<string>; const AUnitName: string): TArray<string>; static;
    /// <summary>Name des OnCreate-Handlers des Formulars selbst aus der Formulardatei; '' ohne.</summary>
    class function CreateHandler(const AFormText: string): string; static;
  end;

procedure RegisterFormFieldRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Derived,
  Atlas.Text.Lines;

type
  TFormField = record
    Name: string;
    TypeName: string;
    Node: TSyntaxNode;
    TypeNode: TSyntaxNode;
    IsPublished: Boolean;
  end;

  /// <summary>Formularklasse der Unit und Objekte der Formulardatei.</summary>
  TFormMatch = class
  private
    FDocument: TDfmDocument;
    FClass: TSyntaxNode;
    FFields: TList<TFormField>;
    FObjects: TList<TDfmObject>;
    procedure CollectObjects(AObject: TDfmObject; AInFrame: Boolean);
    function FindClass(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    function Valid: Boolean;
    function FindField(const AName: string; out AField: TFormField): Boolean;
    /// <summary>Hat die Formulardatei irgendein Objekt dieses Namens (auch inherited)?</summary>
    function HasObject(const AName: string): Boolean;
    /// <summary>Einfügestelle für ein neues Feld: vor dem ersten Sichtbarkeitsabschnitt.</summary>
    function FieldInsert(const AText: string; out ALine: Integer; out AIndent: string): Boolean;
    property Fields: TList<TFormField> read FFields;
    /// <summary>Eigene Objekte des Formulars: benannt, nicht geerbt, nicht in Frames.</summary>
    property Objects: TList<TDfmObject> read FObjects;
    property Document: TDfmDocument read FDocument;
  end;

function ShortName(const AName: string): string;
begin
  Result := AName;
  if LastDelimiter('.', Result) > 0 then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

{ TFormMatch }

constructor TFormMatch.Create(const AContext: TRuleContext);
var
  Index: Integer;
  Child: TSyntaxNode;
  Field: TFormField;
  IsPublished: Boolean;
begin
  inherited Create;
  FFields := TList<TFormField>.Create;
  FObjects := TList<TDfmObject>.Create;
  if (AContext.FormText = '') or (AContext.Tree = nil) then
  begin
    Exit;
  end;
  FDocument := TDfmParser.Parse(AContext.FormText);
  if FDocument.Root = nil then
  begin
    Exit;
  end;
  FClass := FindClass(AContext.Tree.Root, FDocument.Root.TypeName);
  if FClass = nil then
  begin
    Exit;
  end;
  // Ohne Sichtbarkeit gilt published (Formulare werden mit {$M+} übersetzt).
  IsPublished := True;
  for Index := 0 to FClass.ChildCount - 1 do
  begin
    Child := FClass.Children[Index];
    if Child.Kind = TSyntaxKind.Visibility then
    begin
      IsPublished := SameText(Child.Name, 'published');
    end
    else if (Child.Kind = TSyntaxKind.Field) and (Child.Name <> '') then
    begin
      Field := Default(TFormField);
      Field.Name := Child.Name;
      Field.Node := Child;
      Field.TypeNode := Child.FindChild(TSyntaxKind.TypeReference);
      if Field.TypeNode <> nil then
      begin
        Field.TypeName := Field.TypeNode.Name;
      end;
      Field.IsPublished := IsPublished;
      FFields.Add(Field);
    end;
  end;
  CollectObjects(FDocument.Root, False);
end;

destructor TFormMatch.Destroy;
begin
  FObjects.Free;
  FFields.Free;
  FDocument.Free;
  inherited;
end;

// Iterativ (Bericht M1).
function TFormMatch.FindClass(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.TypeDecl) and SameText(Node.Name, AName) then
      begin
        Result := Node.FindChild(TSyntaxKind.ClassType);
        if Result <> nil then
        begin
          Exit;
        end;
        Continue;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        if Node.Children[Index].Kind in [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile,
          TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection,
          TSyntaxKind.TypeDecl] then
        begin
          Pending.Push(Node.Children[Index]);
        end;
      end;
    end;
  finally
    Pending.Free;
  end;
end;

procedure TFormMatch.CollectObjects(AObject: TDfmObject; AInFrame: Boolean);
var
  Child: TDfmObject;
begin
  if (AObject <> FDocument.Root) and not AInFrame and (AObject.Name <> '') and
    (AObject.Kind in [TDfmObjectKind.Object_, TDfmObjectKind.Inline_]) then
  begin
    FObjects.Add(AObject);
  end;
  for Child in AObject.Children do
  begin
    CollectObjects(Child, AInFrame or ((AObject <> FDocument.Root) and (AObject.Kind = TDfmObjectKind.Inline_)));
  end;
end;

function TFormMatch.Valid: Boolean;
begin
  Result := FClass <> nil;
end;

function TFormMatch.FindField(const AName: string; out AField: TFormField): Boolean;
var
  Field: TFormField;
begin
  for Field in FFields do
  begin
    if SameText(Field.Name, AName) then
    begin
      AField := Field;
      Exit(True);
    end;
  end;
  Result := False;
end;

function SearchObject(AObject: TDfmObject; const AName: string): Boolean;
var
  Child: TDfmObject;
begin
  if SameText(AObject.Name, AName) then
  begin
    Exit(True);
  end;
  for Child in AObject.Children do
  begin
    if SearchObject(Child, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TFormMatch.HasObject(const AName: string): Boolean;
begin
  Result := SearchObject(FDocument.Root, AName);
end;

function LineIndent(const AText: string; ALine: Integer): string;
var
  Index, Line: Integer;
begin
  Result := '';
  // Anfang der Zeile ALine suchen.
  Index := 1;
  Line := 0;
  while (Line < ALine) and (Index <= Length(AText)) do
  begin
    if AText[Index] = #10 then
    begin
      Inc(Line);
    end;
    Inc(Index);
  end;
  while (Index <= Length(AText)) and CharInSet(AText[Index], [' ', #9]) do
  begin
    Result := Result + AText[Index];
    Inc(Index);
  end;
end;

function TFormMatch.FieldInsert(const AText: string; out ALine: Integer; out AIndent: string): Boolean;
var
  Index: Integer;
  First: TSyntaxNode;
begin
  // Vor dem ersten Sichtbarkeitsabschnitt, sonst vor dem end der Klasse.
  ALine := FClass.EndPos.Line;
  First := nil;
  for Index := 0 to FClass.ChildCount - 1 do
  begin
    if FClass.Children[Index].Kind = TSyntaxKind.Visibility then
    begin
      ALine := FClass.Children[Index].StartPos.Line;
      Break;
    end
    else if (First = nil) and (FClass.Children[Index].Kind in [TSyntaxKind.Field, TSyntaxKind.RoutineHeader,
      TSyntaxKind.PropertyDecl]) then
    begin
      First := FClass.Children[Index];
    end;
  end;
  if First <> nil then
  begin
    AIndent := LineIndent(AText, First.StartPos.Line);
  end
  else
  begin
    AIndent := LineIndent(AText, ALine) + '  ';
  end;
  Result := ALine > FClass.StartPos.Line;
end;

{ TFormFieldWithoutObjectRule }

function TFormFieldWithoutObjectRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-field-without-object', TRuleSeverity.Warning,
    'Komponentenfeld des Formulars ohne Objekt in der Formulardatei');
end;

procedure TFormFieldWithoutObjectRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Match: TFormMatch;
  Field: TFormField;
begin
  Match := TFormMatch.Create(AContext);
  try
    if not Match.Valid then
    begin
      Exit;
    end;
    for Field in Match.Fields do
    begin
      if Field.IsPublished and not Match.HasObject(Field.Name) then
      begin
        AReport.Add(NodeRange(Field.Node), Format('Feld %s hat kein Objekt in der Formulardatei; beim Laden ' +
          'bleibt es nil', [Field.Name]));
      end;
    end;
  finally
    Match.Free;
  end;
end;

{ TFormObjectWithoutFieldRule }

function TFormObjectWithoutFieldRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-object-without-field', TRuleSeverity.Warning,
    'Objekt der Formulardatei ohne Feld in der Formularklasse');
end;

procedure TFormObjectWithoutFieldRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Match: TFormMatch;
  Obj: TDfmObject;
  Field: TFormField;
  Line: Integer;
  Indent: string;
  Fixes: TArray<TRuleFix>;
begin
  Match := TFormMatch.Create(AContext);
  try
    if not Match.Valid then
    begin
      Exit;
    end;
    for Obj in Match.Objects do
    begin
      if not Match.FindField(Obj.Name, Field) then
      begin
        Fixes := nil;
        if Match.FieldInsert(AContext.Text, Line, Indent) then
        begin
          Fixes := [TRuleFix.Create(Format('Feld %s: %s ergänzen', [Obj.Name, Obj.TypeName]),
            [TRuleEdit.Create(TTextRange.Create(Line, 0, Line, 0),
            Indent + Obj.Name + ': ' + Obj.TypeName + ';' + TTextLines.LineBreakOf(AContext.Text))])];
        end;
        // Gemeldet wird an der Formularklasse; die Formulardatei ist nicht das geprüfte Dokument.
        AReport.Add(TTextRange.Create(Match.FClass.Parent.StartPos.Line, Match.FClass.Parent.StartPos.Character,
          Match.FClass.Parent.StartPos.Line, Match.FClass.Parent.StartPos.Character +
          Length(Match.FClass.Parent.Name)), Format('Objekt %s: %s der Formulardatei hat kein Feld ' +
          'in %s', [Obj.Name, Obj.TypeName, Match.Document.Root.TypeName]), Fixes);
      end;
    end;
  finally
    Match.Free;
  end;
end;

{ TFormFieldTypeMismatchRule }

function TFormFieldTypeMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-field-type-mismatch', TRuleSeverity.Warning,
    'Feld und Objekt der Formulardatei haben verschiedene Klassen');
end;

function KnownClass(const AIndex: ISymbolIndex; const AName: string): Boolean;
var
  Location: TSymbolLocation;
begin
  if AIndex = nil then
  begin
    Exit(True);
  end;
  for Location in AIndex.FindSymbols(ShortName(AName)) do
  begin
    if Location.Symbol.Kind = TIndexSymbolKind.ClassType then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TFormFieldTypeMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Match: TFormMatch;
  Obj: TDfmObject;
  Field: TFormField;
begin
  Match := TFormMatch.Create(AContext);
  try
    if not Match.Valid then
    begin
      Exit;
    end;
    for Obj in Match.Objects do
    begin
      if Match.FindField(Obj.Name, Field) and (Field.TypeNode <> nil) and
        not SameText(ShortName(Field.TypeName), ShortName(Obj.TypeName)) and KnownClass(AContext.Index, Obj.TypeName) then
      begin
        AReport.Add(NodeRange(Field.TypeNode), Format('Feld %s ist %s, das Objekt in der Formulardatei aber %s',
          [Field.Name, Field.TypeName, Obj.TypeName]),
          [TRuleFix.Create(Format('Typ auf %s ändern', [Obj.TypeName]),
          [TRuleEdit.Create(NodeRange(Field.TypeNode), Obj.TypeName)])]);
      end;
    end;
  finally
    Match.Free;
  end;
end;

{ TFormAccessBeforeCreateRule }

function TFormAccessBeforeCreateRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-access-before-create', TRuleSeverity.Warning,
    'Zugriff auf ein Formular, das noch nicht erzeugt ist');
end;

class function TFormAccessBeforeCreateRule.AutoCreatedForms(const AMainSource: string): TArray<string>;
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Index, Position: Integer;

  function IsText(APosition: Integer; const AText: string): Boolean;
  begin
    Result := (APosition <= High(Code)) and SameText(Tokens[Code[APosition]].Text, AText);
  end;

begin
  Result := nil;
  Tokens := TPascalLexer.Tokenize(AMainSource);
  Code := nil;
  for Index := 0 to High(Tokens) do
  begin
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Code := Code + [Index];
    end;
  end;
  // Application.CreateForm(TfrmHaupt, frmHaupt);
  for Position := 0 to High(Code) - 7 do
  begin
    if IsText(Position, 'Application') and IsText(Position + 1, '.') and IsText(Position + 2, 'CreateForm') and
      IsText(Position + 3, '(') and IsText(Position + 5, ',') and IsText(Position + 7, ')') and
      (Tokens[Code[Position + 6]].Kind = TPascalTokenKind.Identifier) then
    begin
      Result := Result + [Tokens[Code[Position + 6]].Text];
    end;
  end;
end;

class function TFormAccessBeforeCreateRule.FormsOfProgram(const APrograms: TArray<string>;
  const AUnitName: string): TArray<string>;
var
  Main: string;
begin
  for Main in APrograms do
  begin
    if MatchText(AUnitName, TUsesClauses.UsedUnits(TPascalLexer.Tokenize(Main))) then
    begin
      Exit(AutoCreatedForms(Main));
    end;
  end;
  Result := nil;
end;

class function TFormAccessBeforeCreateRule.CreateHandler(const AFormText: string): string;
var
  Line, Text: string;
begin
  // OnCreate des Formulars bzw. Datenmoduls selbst: vor dem ersten eingerückten object.
  for Line in TTextLines.SplitLines(AFormText) do
  begin
    Text := Trim(Line);
    if (Line <> TrimLeft(Line)) and (StartsText('object ', Text) or StartsText('inherited ', Text) or
      StartsText('inline ', Text)) then
    begin
      Break;
    end;
    if StartsText('OnCreate = ', Text) then
    begin
      Exit(Trim(Copy(Text, Length('OnCreate = ') + 1, MaxInt)));
    end;
  end;
  Result := '';
end;

procedure TFormAccessBeforeCreateRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Forms: TArray<string>;
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  OwnIndex: Integer;
  OwnName, OwnClass, Handler: string;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier) and SameText(Token(APosition).Text, AName);
  end;

  function CodeAt(AOffset: Integer): Integer;
  var
    mHigh, mMiddle: Integer;
  begin
    // Binär statt ab Dateianfang mit einer Kopie je Token: Code steht nach Offset sortiert (#1342).
    Result := 0;
    mHigh := Length(Code);
    while Result < mHigh do
    begin
      mMiddle := (Result + mHigh) div 2;
      if Tokens[Code[mMiddle]].Offset < AOffset then
      begin
        Result := mMiddle + 1;
      end
      else
      begin
        mHigh := mMiddle;
      end;
    end;
  end;

  function FormIndex(const AName: string): Integer;
  begin
    for Result := 0 to High(Forms) do
    begin
      if SameText(Forms[Result], AName) then
      begin
        Exit;
      end;
    end;
    Result := -1;
  end;

  // Globale Variable dieser Unit, die in der .dpr erzeugt wird und deren Klasse hier deklariert ist.
  function FindOwnForm: Boolean;
  var
    Local: TUnitIndex;
    Symbol, TypeSymbol: TIndexSymbol;
    Cache: IRuleDerivedCache;
  begin
    Cache := TRuleDerived.Open(AContext);
    Local := TRuleDerived.UnitIndex(Cache, AContext);
    for Symbol in Local.Symbols do
    begin
      if (Symbol.Kind = TIndexSymbolKind.Variable) and (Symbol.Container = '') and (FormIndex(Symbol.Name) >= 0) then
      begin
        for TypeSymbol in Local.Symbols do
        begin
          if (TypeSymbol.Kind = TIndexSymbolKind.ClassType) and (TypeSymbol.Container = '') and
            SameText(TypeSymbol.Name, Symbol.TypeName) then
          begin
            OwnName := Symbol.Name;
            OwnClass := TypeSymbol.Name;
            OwnIndex := FormIndex(Symbol.Name);
            Exit(True);
          end;
        end;
      end;
    end;
    Result := False;
  end;

  // Deklariert die Routine AName selbst (Parameter, lokale Variable)? Iterativ (Bericht M1).
  function DeclaresLocally(ANode: TSyntaxNode; const AName: string): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node, Child: TSyntaxNode;
    Index: Integer;
    Name: string;
  begin
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        for Index := 0 to Node.ChildCount - 1 do
        begin
          Child := Node[Index];
          if Child.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter,
            TSyntaxKind.ConstDecl] then
          begin
            for Name in SplitString(Child.Name, ',') do
            begin
              if SameText(Trim(Name), AName) then
              begin
                Exit(True);
              end;
            end;
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          if Node[Index].Kind <> TSyntaxKind.Block then
          begin
            Pending.Push(Node[Index]);
          end;
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Prüft oder setzt die Routine die Variable selbst (Assigned, nil-Vergleich, Zuweisung, CreateForm)?
  function Handled(AFirst, ALast: Integer; const AName: string): Boolean;
  var
    Position: Integer;
  begin
    for Position := AFirst to ALast do
    begin
      if IsName(Position, AName) and not IsSym(Position - 1, '.') then
      begin
        if (IsSym(Position - 1, '(') and IsName(Position - 2, 'Assigned')) or IsSym(Position + 1, ':=') or
          ((IsSym(Position + 1, '<>') or IsSym(Position + 1, '=')) and (Position + 2 <= High(Code)) and
          Token(Position + 2).IsKeyword('nil')) or (IsSym(Position - 1, ',') and IsName(Position - 4, 'CreateForm')) then
        begin
          Exit(True);
        end;
      end;
    end;
    Result := False;
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    First, Last, Position, Index: Integer;
    Body: TSyntaxNode;
    Reported: TArray<string>;
    Name: string;
  begin
    Body := TRoutineBody.BodyOf(ARoutine);
    if Body = nil then
    begin
      Exit;
    end;
    First := CodeAt(Body.StartOffset);
    Last := CodeAt(Body.EndOffset) - 1;
    Reported := nil;
    for Position := First to Last do
    begin
      if (Token(Position).Kind <> TPascalTokenKind.Identifier) or IsSym(Position - 1, '.') then
      begin
        Continue;
      end;
      Index := FormIndex(Token(Position).Text);
      if Index <= OwnIndex then
      begin
        Continue;
      end;
      Name := Forms[Index];
      if MatchText(Name, Reported) or DeclaresLocally(ARoutine, Name) or Handled(First, Last, Name) then
      begin
        Continue;
      end;
      Reported := Reported + [Name];
      AReport.Add(TTextRange.Create(Token(Position).StartPos, Token(Position).EndPos),
        Format('%s wird in der .dpr erst nach %s erzeugt und ist hier noch nil.', [Name, OwnName]),
        TRuleConfidence.Medium);
    end;
  end;

  // Konstruktor, AfterConstruction und OnCreate-Handler der eigenen Klasse.
  function IsCreationMethod(ARoutine: TSyntaxNode): Boolean;
  var
    Method: string;
  begin
    Result := False;
    if not StartsText(OwnClass + '.', ARoutine.Name) then
    begin
      Exit;
    end;
    Method := Copy(ARoutine.Name, Length(OwnClass) + 2, MaxInt);
    if Pos('.', Method) > 0 then
    begin
      Exit;
    end;
    Result := SameText(Method, 'AfterConstruction') or SameText(Method, Handler) or
      ((Handler = '') and MatchText(Method, ['FormCreate', 'DataModuleCreate'])) or
      Token(CodeAt(ARoutine.StartOffset)).IsKeyword('constructor');
  end;

var
  Routines: TArray<TSyntaxNode>;
  Routine: TSyntaxNode;
  Index: Integer;
begin
  Forms := AContext.AutoCreateForms;
  if (Length(Forms) < 2) or (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
  begin
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Code := Code + [Index];
    end;
  end;
  if not FindOwnForm then
  begin
    Exit;
  end;
  Handler := CreateHandler(AContext.FormText);
  Routines := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        Routines := Routines + [ANode];
      end;
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
    end);
  for Routine in Routines do
  begin
    if IsCreationMethod(Routine) then
    begin
      CheckRoutine(Routine);
    end;
  end;
end;

procedure RegisterFormFieldRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TFormFieldWithoutObjectRule.Create);
  ARegistry.Register(TFormObjectWithoutFieldRule.Create);
  ARegistry.Register(TFormFieldTypeMismatchRule.Create);
  ARegistry.Register(TFormAccessBeforeCreateRule.Create);
end;

end.
