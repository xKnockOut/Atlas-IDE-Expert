unit Atlas.Common.Rules.Builtin.FreeFields;

// Felder im Destruktor freigeben (#666):
//   field-not-freed           im Konstruktor erzeugtes Objektfeld, das die
//                             Klasse nirgends freigibt; Korrektur „Im
//                             Destruktor freigeben“. Bis #918 hieß die Regel
//                             owned-field-not-freed (Alias). Komponenten mit
//                             Owner, Interfaces und Klassen aus ignoreTypes
//                             bleiben stumm.
//   owned-field-free-unclear  erzeugtes Feld, das zurückgegeben oder
//                             weitergereicht wird; ob die Klasse es freigeben
//                             muss, entscheidet der Entwickler (ohne Aktion)
//   initialization-not-finalized  (#971) in initialization bzw. class
//                             constructor erzeugtes Objekt einer Unit- bzw.
//                             class-Variablen, das die Unit nirgends freigibt;
//                             Korrektur FreeAndNil in finalization bzw. class
//                             destructor (legt beide bei Bedarf an)
//
// Erkennung und Änderungen liefert TFreeFields (Editing). Mit
// refactoring.freeFields aus schweigen die ersten beiden Regeln.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Editing.FreeFields;

type
  TOwnedFieldNotFreedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>True, wenn AField eine Klasse aus AIgnoreTypes erzeugt oder so deklariert ist (#918).</summary>
    class function Ignored(const AField: TOwnedField; const AIgnoreTypes: TArray<string>): Boolean; static;
  end;

  TOwnedFieldFreeUnclearRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInitializationNotFinalizedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterFreeFieldRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines;

{ TOwnedFieldNotFreedRule }

function TOwnedFieldNotFreedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('field-not-freed', TRuleSeverity.Warning,
    'Im Konstruktor erzeugtes Feld wird nicht freigegeben');
end;

class function TOwnedFieldNotFreedRule.Ignored(const AField: TOwnedField; const AIgnoreTypes: TArray<string>): Boolean;
var
  Declared: string;
begin
  // Generische Typen vergleichen ohne Typparameter: TObjectList<TFoo> -> TObjectList.
  Declared := AField.TypeName;
  if Pos('<', Declared) > 0 then
    Declared := Copy(Declared, 1, Pos('<', Declared) - 1);
  Result := MatchText(Trim(AField.CreatedType), AIgnoreTypes) or MatchText(Trim(Declared), AIgnoreTypes) or
    MatchText(Trim(AField.TypeName), AIgnoreTypes);
end;

procedure TOwnedFieldNotFreedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Field: TOwnedField;
  Style: TFreeFieldsStyle;
  Edits: TArray<TTextEdit>;
  Fixes: TArray<TRuleFix>;
  IgnoreTypes: TArray<string>;
begin
  if (AContext.Tree = nil) or AContext.NoFreeFields then
    Exit;
  IgnoreTypes := TRuleOptions.Strings(AContext.Options, 'ignoreTypes', nil);
  Style := TFreeFieldsStyle.Free;
  if AContext.FreeFieldsFreeAndNil then
    Style := TFreeFieldsStyle.FreeAndNil;
  for Field in TFreeFields.Analyze(AContext.Tree, AContext.Text, AContext.Index) do
  begin
    if (Field.State <> TOwnedFieldState.NotFreed) or Ignored(Field, IgnoreTypes) then
      Continue;
    Fixes := nil;
    // Nicht sicher: Ob die Klasse das Objekt besitzt, weiß nur der Entwickler.
    if TFreeFields.Edits(AContext.Tree, AContext.Text, [Field], Style, Edits) then
      Fixes := [TRuleFix.Create(TFreeFields.FieldTitle, Edits, False)];
    // Mittel: Ob das Objekt anderswo freigegeben wird, sieht die Regel nicht immer.
    AReport.Add(Field.Range, Format('%s wird im Konstruktor erzeugt, aber im Destruktor nicht freigegeben ' +
      '(Speicherleck).', [Field.Name]), TRuleConfidence.Medium, Fixes);
  end;
end;

{ TOwnedFieldFreeUnclearRule }

function TOwnedFieldFreeUnclearRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('owned-field-free-unclear', TRuleSeverity.Hint,
    'Unklar, ob ein erzeugtes Feld freigegeben werden muss');
end;

procedure TOwnedFieldFreeUnclearRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Field: TOwnedField;
begin
  if (AContext.Tree = nil) or AContext.NoFreeFields then
    Exit;
  for Field in TFreeFields.Analyze(AContext.Tree, AContext.Text, AContext.Index) do
    if Field.State = TOwnedFieldState.Unclear then
      AReport.Add(Field.Range, Format('"%s" wird in %s erzeugt und nicht freigegeben; ob %s es freigeben muss, ' +
        'ist unklar: Es %s', [Field.Name, Field.CreatedIn, Field.ClassName, Field.Reason]));
end;

{ TInitializationNotFinalizedRule }

const
  InitializationNotFinalizedRuleId = 'initialization-not-finalized';
  /// <summary>Aufrufe am Objekt, die es freigeben.</summary>
  ReleasingMethods: array[0..3] of string = ('Free', 'Destroy', 'DisposeOf', 'Release');

type
  /// <summary>Ein in initialization bzw. class constructor erzeugtes Objekt (#971).</summary>
  TInitCreation = record
    Name: string;
    /// <summary>Die Zuweisung mit Create; dort steht die Meldung.</summary>
    Assignment: TSyntaxNode;
    /// <summary>Klasse der class var; nil bei einer Unit-Variablen.</summary>
    ClassDecl: TSyntaxNode;
    /// <summary>Andere Units erreichen die Variable (interface-Abschnitt, nicht private).</summary>
    Visible: Boolean;
    /// <summary>Offsets der Deklaration: Name und Typ.</summary>
    DeclStart, DeclEnd: Integer;
  end;

  /// <summary>Unit- bzw. class-Variable mit Objekttyp.</summary>
  TInitVariable = record
    Name: string;
    ClassDecl: TSyntaxNode;
    Visible: Boolean;
    DeclStart, DeclEnd: Integer;
  end;

  /// <summary>Sucht alle Erwähnungen einer Variablen in der Unit: gibt die Unit sie frei, oder gibt sie sie
  /// weiter? Nur harmlose Erwähnungen (Mitglied lesen oder aufrufen, mit nil vergleichen, Assigned, neu
  /// erzeugen oder nil zuweisen) lassen die Meldung zu; jede andere könnte das Objekt übergeben.</summary>
  TInitUses = class
  private
    FContext: TRuleContext;
    FName: string;
    FClassName: string;
    FFreed: Boolean;
    FEscaped: Boolean;
    FHarmless: TArray<TSyntaxNode>;
    function IsRef(ANode: TSyntaxNode): Boolean;
    procedure Harmless(ANode: TSyntaxNode);
    procedure Visit(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const ACreation: TInitCreation);
    /// <summary>True, wenn die Unit das Objekt nirgends freigibt und nirgends weitergibt.</summary>
    function Leaks(const ACreation: TInitCreation): Boolean;
  end;

constructor TInitUses.Create(const AContext: TRuleContext; const ACreation: TInitCreation);
begin
  inherited Create;
  FContext := AContext;
  FName := ACreation.Name;
  if ACreation.ClassDecl <> nil then
    FClassName := ACreation.ClassDecl.Name;
end;

function TInitUses.IsRef(ANode: TSyntaxNode): Boolean;
begin
  Result := False;
  if ANode = nil then
    Exit;
  if ANode.Kind = TSyntaxKind.Identifier then
    Exit(SameText(ANode.Name, FName));
  // Self.FInstanz bzw. TKlasse.FInstanz
  Result := (FClassName <> '') and (ANode.Kind = TSyntaxKind.MemberAccess) and SameText(ANode.Name, FName) and
    (ANode.ChildCount = 1) and (ANode[0].Kind = TSyntaxKind.Identifier) and
    (SameText(ANode[0].Name, 'Self') or SameText(ANode[0].Name, FClassName));
end;

procedure TInitUses.Harmless(ANode: TSyntaxNode);
begin
  FHarmless := FHarmless + [ANode];
end;

procedure TInitUses.Visit(ANode: TSyntaxNode);
var
  Index: Integer;
  TypeName: string;
  Owned: Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.MemberAccess:
      if (ANode.ChildCount >= 1) and IsRef(ANode[0]) then
      begin
        if MatchText(ANode.Name, ReleasingMethods) then
          FFreed := True
        else if SameText(ANode.Name, 'FreeOnTerminate') then
          // Ein Thread, der sich selbst freigibt.
          FEscaped := True
        else
          Harmless(ANode[0]);
      end;
    TSyntaxKind.Call:
      if (ANode.ChildCount = 2) and (ANode[0].Kind = TSyntaxKind.Identifier) and IsRef(ANode[1]) then
      begin
        if SameText(ANode[0].Name, 'FreeAndNil') then
          FFreed := True
        else if SameText(ANode[0].Name, 'Assigned') then
          Harmless(ANode[1]);
      end;
    TSyntaxKind.BinaryExpr:
      if (ANode.Name = '=') or (ANode.Name = '<>') then
        for Index := 0 to ANode.ChildCount - 1 do
          if IsRef(ANode[Index]) then
            Harmless(ANode[Index]);
    TSyntaxKind.AssignStatement:
      if (ANode.ChildCount >= 2) and IsRef(ANode[0]) and (((ANode[1].Kind = TSyntaxKind.Literal) and
        SameText(ANode[1].Name, 'nil')) or (TFreeFields.ObjectCreation(FContext.Tree, FContext.Text,
        FContext.Index, ANode[1], TypeName, Owned) and not Owned)) then
        Harmless(ANode[0]);
  end;
  for Index := 0 to ANode.ChildCount - 1 do
    Visit(ANode[Index]);
end;

function TInitUses.Leaks(const ACreation: TInitCreation): Boolean;
var
  Token: TPascalToken;
  Node: TSyntaxNode;
  Known: Boolean;
begin
  Visit(FContext.Tree.Root);
  if FFreed or FEscaped then
    Exit(False);
  // Jede Erwähnung im Text muss eine der harmlosen sein (auch in Properties, with und asm).
  for Token in FContext.Tree.Tokens do
  begin
    if (Token.Kind <> TPascalTokenKind.Identifier) or not SameText(Token.Text, FName) or
      ((Token.Offset >= ACreation.DeclStart) and (Token.Offset < ACreation.DeclEnd)) then
      Continue;
    Known := False;
    for Node in FHarmless do
      if (Token.Offset >= Node.StartOffset) and (Token.Offset < Node.EndOffset) then
        Known := True;
    if not Known then
      Exit(False);
  end;
  Result := True;
end;

/// <summary>Verwendet eine andere Unit des Index den Namen? Dann könnte sie das Objekt freigeben.</summary>
function UsedElsewhere(const AContext: TRuleContext; const AName: string): Boolean;
var
  UnitIndex: TUnitIndex;
  Usage: TIndexUsage;
begin
  Result := False;
  if AContext.Index = nil then
    Exit;
  for UnitIndex in AContext.Index.Units do
    if not SameText(UnitIndex.UnitName, AContext.UnitName) then
      for Usage in UnitIndex.Usages do
        if SameText(Usage.Name, AName) then
          Exit(True);
end;

/// <summary>Typname der Deklaration, '' ohne einfachen Typverweis.</summary>
function DeclaredType(const AText: string; ADecl: TSyntaxNode): string;
var
  TypeRef: TSyntaxNode;
begin
  Result := '';
  TypeRef := ADecl.FindChild(TSyntaxKind.TypeReference);
  if TypeRef <> nil then
    Result := Trim(Copy(AText, TypeRef.StartOffset + 1, TypeRef.EndOffset - TypeRef.StartOffset));
end;

/// <summary>Steht vor ANode das Schlüsselwort class (class var)?</summary>
function AfterClassKeyword(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := High(ATokens) downto 0 do
    if ATokens[Index].Offset < ANode.StartOffset then
    begin
      if ATokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
        Continue;
      Exit(ATokens[Index].IsKeyword('class'));
    end;
end;

/// <summary>Variablen mit Objekttyp aus dem Abschnitt ASection: Unit-Variablen (var) und class vars der
/// Klassen darin.</summary>
procedure ReadVariables(const AContext: TRuleContext; ASection: TSyntaxNode; AVisible: Boolean;
  var AVariables: TArray<TInitVariable>);
var
  Child, TypeDecl, ClassNode, Member, Decl: TSyntaxNode;
  Index, TypeIndex, MemberIndex, DeclIndex: Integer;
  Variable: TInitVariable;
  Name, Visibility: string;
begin
  for Index := 0 to ASection.ChildCount - 1 do
  begin
    Child := ASection[Index];
    if (Child.Kind = TSyntaxKind.VarSection) and SameText(Child.Name, 'var') then
      for DeclIndex := 0 to Child.ChildCount - 1 do
      begin
        Decl := Child[DeclIndex];
        if (Decl.Kind <> TSyntaxKind.VarDecl) or (DeclaredType(AContext.Text, Decl) = '') or
          not TFreeFields.IsObjectType(AContext.Tree, AContext.Text, AContext.Index,
          DeclaredType(AContext.Text, Decl)) then
          Continue;
        for Name in Decl.Name.Split([',']) do
        begin
          Variable := Default(TInitVariable);
          Variable.Name := Trim(Name);
          Variable.Visible := AVisible;
          Variable.DeclStart := Decl.StartOffset;
          Variable.DeclEnd := Decl.EndOffset;
          AVariables := AVariables + [Variable];
        end;
      end;
    if Child.Kind <> TSyntaxKind.TypeSection then
      Continue;
    for TypeIndex := 0 to Child.ChildCount - 1 do
    begin
      TypeDecl := Child[TypeIndex];
      ClassNode := TypeDecl.FindChild(TSyntaxKind.ClassType);
      if (TypeDecl.Kind <> TSyntaxKind.TypeDecl) or (ClassNode = nil) then
        Continue;
      Visibility := 'public';
      for MemberIndex := 0 to ClassNode.ChildCount - 1 do
      begin
        Member := ClassNode[MemberIndex];
        if Member.Kind = TSyntaxKind.Visibility then
          Visibility := Member.Name;
        if (Member.Kind <> TSyntaxKind.VarSection) or not AfterClassKeyword(AContext.Tree.Tokens, Member) then
          Continue;
        for DeclIndex := 0 to Member.ChildCount - 1 do
        begin
          Decl := Member[DeclIndex];
          if (Decl.Kind <> TSyntaxKind.VarDecl) or (DeclaredType(AContext.Text, Decl) = '') or
            not TFreeFields.IsObjectType(AContext.Tree, AContext.Text, AContext.Index,
            DeclaredType(AContext.Text, Decl)) then
            Continue;
          for Name in Decl.Name.Split([',']) do
          begin
            Variable := Default(TInitVariable);
            Variable.Name := Trim(Name);
            Variable.ClassDecl := TypeDecl;
            Variable.Visible := AVisible and not ContainsText(Visibility, 'private');
            Variable.DeclStart := Decl.StartOffset;
            Variable.DeclEnd := Decl.EndOffset;
            AVariables := AVariables + [Variable];
          end;
        end;
      end;
    end;
  end;
end;

/// <summary>Zuweisungen Variable := TKlasse.Create… in ANode (ohne anonyme Methoden); AClassDecl nil für
/// initialization, sonst die Klasse des class constructor.</summary>
procedure FindCreations(const AContext: TRuleContext; ANode, AClassDecl: TSyntaxNode;
  const AVariables: TArray<TInitVariable>; var ACreations: TArray<TInitCreation>);
var
  Index: Integer;
  Variable: TInitVariable;
  Creation: TInitCreation;
  Target: TSyntaxNode;
  TypeName, Name: string;
  Owned, Known: Boolean;
begin
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
    Exit;
  if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount >= 2) then
  begin
    Target := ANode[0];
    Name := '';
    if Target.Kind = TSyntaxKind.Identifier then
      Name := Target.Name
    else if (AClassDecl <> nil) and (Target.Kind = TSyntaxKind.MemberAccess) and (Target.ChildCount = 1) and
      (Target[0].Kind = TSyntaxKind.Identifier) and (SameText(Target[0].Name, 'Self') or
      SameText(Target[0].Name, AClassDecl.Name)) then
      Name := Target.Name;
    Known := False;
    for Creation in ACreations do
      if SameText(Creation.Name, Name) and (Creation.ClassDecl = AClassDecl) then
        Known := True;
    if (Name <> '') and not Known and TFreeFields.ObjectCreation(AContext.Tree, AContext.Text, AContext.Index,
      ANode[1], TypeName, Owned) and not Owned then
      for Variable in AVariables do
        if SameText(Variable.Name, Name) and (Variable.ClassDecl = AClassDecl) then
        begin
          Creation := Default(TInitCreation);
          Creation.Name := Variable.Name;
          Creation.Assignment := ANode;
          Creation.ClassDecl := AClassDecl;
          Creation.Visible := Variable.Visible;
          Creation.DeclStart := Variable.DeclStart;
          Creation.DeclEnd := Variable.DeclEnd;
          ACreations := ACreations + [Creation];
          Break;
        end;
  end;
  for Index := 0 to ANode.ChildCount - 1 do
    FindCreations(AContext, ANode[Index], AClassDecl, AVariables, ACreations);
end;

/// <summary>"FreeAndNil(X);" vor das "end." der Unit, in finalization; fehlt sie, wird sie angelegt.
/// ACreated: finalization wurde angelegt.</summary>
function FinalizationEdits(const AContext: TRuleContext; const AStatement: string; out AEdits: TArray<TTextEdit>;
  out ACreated: Boolean): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Lines: TArray<string>;
  LineBreak, Text: string;
  Index, EndIndex, Previous: Integer;
  Section: TSyntaxNode;
begin
  AEdits := nil;
  ACreated := False;
  Result := False;
  Tokens := AContext.Tree.Tokens;
  // "end" vor dem letzten Punkt.
  EndIndex := -1;
  for Index := High(Tokens) downto 1 do
    if Tokens[Index].IsSymbol('.') then
    begin
      Previous := Index - 1;
      while (Previous >= 0) and (Tokens[Previous].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
        Dec(Previous);
      if (Previous >= 0) and Tokens[Previous].IsKeyword('end') then
        EndIndex := Previous;
      Break;
    end;
  if EndIndex < 1 then
    Exit;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  // Nur wenn "end." am Zeilenanfang steht; sonst gäbe es keine saubere Stelle.
  if (Tokens[EndIndex].StartPos.Line > High(Lines)) or
    (Trim(Copy(Lines[Tokens[EndIndex].StartPos.Line], 1, Tokens[EndIndex].StartPos.Character)) <> '') then
    Exit;
  Section := AContext.Tree.Root.FindChild(TSyntaxKind.FinalizationSection);
  Previous := EndIndex - 1;
  while (Previous >= 0) and (Tokens[Previous].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Dec(Previous);
  if Section <> nil then
  begin
    // Letzte Anweisung ohne Semikolon: erst eins ergänzen.
    if (Previous >= 0) and not Tokens[Previous].IsSymbol(';') and not Tokens[Previous].IsKeyword('finalization') then
      AEdits := [TTextEdit.Create(TTextRange.Create(Tokens[Previous].EndPos, Tokens[Previous].EndPos), ';')];
    Text := '  ' + AStatement + LineBreak;
  end
  else
  begin
    ACreated := True;
    Text := 'finalization' + LineBreak + '  ' + AStatement + LineBreak;
    if (Tokens[EndIndex].StartPos.Line = 0) or (Trim(Lines[Tokens[EndIndex].StartPos.Line - 1]) <> '') then
      Text := LineBreak + Text;
  end;
  AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(Tokens[EndIndex].StartPos.Line, 0),
    TTextPosition.Create(Tokens[EndIndex].StartPos.Line, 0)), Text)];
  Result := True;
end;

function TInitializationNotFinalizedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(InitializationNotFinalizedRuleId, TRuleSeverity.Warning,
    'Beim Start erzeugtes Objekt wird nicht freigegeben');
end;

procedure TInitializationNotFinalizedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Variables: TArray<TInitVariable>;
  Creations: TArray<TInitCreation>;
  Creation: TInitCreation;
  Section, Decl, Header: TSyntaxNode;
  Index: Integer;
  Variable: TInitVariable;
  Scan: TInitUses;
  Leaks, Created, Safe: Boolean;
  Edits: TArray<TTextEdit>;
  UsesEdit: TTextEdit;
  Fixes: TArray<TRuleFix>;
  Statement, Message, Title: string;
  Classes: TArray<TSyntaxNode>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Variables := nil;
  Section := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  if Section <> nil then
    ReadVariables(AContext, Section, True, Variables);
  Section := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section <> nil then
    ReadVariables(AContext, Section, False, Variables);
  if Variables = nil then
    Exit;
  Creations := nil;
  Section := AContext.Tree.Root.FindChild(TSyntaxKind.InitializationSection);
  if Section <> nil then
    FindCreations(AContext, Section, nil, Variables, Creations);
  // class constructor der Klassen mit class vars
  Classes := nil;
  for Variable in Variables do
    if (Variable.ClassDecl <> nil) and not ((Classes <> nil) and (Classes[High(Classes)] = Variable.ClassDecl)) then
      Classes := Classes + [Variable.ClassDecl];
  Section := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if (Section <> nil) and (Classes <> nil) then
    for Index := 0 to Section.ChildCount - 1 do
    begin
      Decl := Section[Index];
      Header := Decl.FindChild(TSyntaxKind.RoutineHeader);
      if (Decl.Kind <> TSyntaxKind.RoutineDecl) or (Header = nil) or (Decl.FindChild(TSyntaxKind.Block) = nil) or
        not TRegEx.IsMatch(Copy(AContext.Text, Header.StartOffset + 1, Header.EndOffset - Header.StartOffset),
        '^class\s+constructor\b', [roIgnoreCase]) then
        Continue;
      for Variable in Variables do
        if (Variable.ClassDecl <> nil) and StartsText(Variable.ClassDecl.Name + '.', Decl.Name) then
        begin
          FindCreations(AContext, Decl.FindChild(TSyntaxKind.Block), Variable.ClassDecl, Variables, Creations);
          Break;
        end;
    end;
  for Creation in Creations do
  begin
    Scan := TInitUses.Create(AContext, Creation);
    try
      Leaks := Scan.Leaks(Creation);
    finally
      Scan.Free;
    end;
    if not Leaks or (Creation.Visible and UsedElsewhere(AContext, Creation.Name)) then
      Continue;
    Statement := Format('FreeAndNil(%s);', [Creation.Name]);
    if Creation.ClassDecl = nil then
    begin
      Message := Format('%s wird in initialization erzeugt, aber in finalization nicht freigegeben.', [Creation.Name]);
      Title := 'In finalization freigeben';
      Safe := FinalizationEdits(AContext, Statement, Edits, Created);
      Safe := Safe and not Created;
    end
    else
    begin
      Message := Format('%s wird im class constructor erzeugt, aber im class destructor nicht freigegeben.',
        [Creation.Name]);
      Title := 'Im class destructor freigeben';
      if not TFreeFields.ClassDestructorEdits(AContext.Tree, AContext.Text, Creation.ClassDecl, [Statement],
        Edits) then
        Edits := nil;
      Safe := Length(Edits) = 1;
    end;
    // Mehrere neu angelegte Abschnitte oder uses-Einträge an derselben Stelle vertragen sich nicht:
    // solche Korrekturen nur einzeln (nicht sicher).
    if (Edits <> nil) and not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(AContext.Tree.Tokens), 'System.SysUtils',
      AContext.Namespaces) then
      if TUsesClauses.AddUnit(AContext.Tree.Tokens, Creation.Assignment.StartOffset, 'System.SysUtils',
        TTextLines.LineBreakOf(AContext.Text), UsesEdit) then
      begin
        Edits := Edits + [UsesEdit];
        Safe := False;
      end
      else
        Edits := nil;
    Fixes := nil;
    if Edits <> nil then
      Fixes := [TRuleFix.Create(Title, Edits, Safe)];
    AReport.Add(TTextRange.Create(Creation.Assignment[0].StartPos, Creation.Assignment[0].EndPos), Message,
      TRuleConfidence.High, Fixes);
  end;
end;

procedure RegisterFreeFieldRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOwnedFieldNotFreedRule.Create);
  ARegistry.Register(TOwnedFieldFreeUnclearRule.Create);
  ARegistry.Register(TInitializationNotFinalizedRule.Create);
end;

end.
