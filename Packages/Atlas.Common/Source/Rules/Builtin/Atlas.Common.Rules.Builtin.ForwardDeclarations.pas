unit Atlas.Common.Rules.Builtin.ForwardDeclarations;

// Forward-Deklarationen (#685):
//   type-used-before-declaration   Typ in einer Typdeklaration benutzt, bevor er
//                                  deklariert ist (sonst erst E2003)
//   unneeded-forward-declaration   Forward-Deklaration, die niemand braucht
//   unsatisfied-forward            Vorwärtsdeklaration nie aufgelöst (#1002, Gruppe
//                                  Compiler vorab): Routine im interface-Teil
//                                  oder mit forward ohne Rumpf (E2065),
//                                  TFoo = class; bzw. IFoo = interface; ohne
//                                  vollständige Deklaration im selben
//                                  type-Abschnitt (E2086, E2420)
//
// Erkennung und Korrekturen liefert TForwardDeclarations (Editing). Mit
// refactoring.forwardDeclaration aus schweigen die ersten beiden Regeln.
//
// unsatisfied-forward liest nur den Syntaxbaum; Methoden prüft
// declared-not-implemented. Ein Rumpf passt, wenn er gleich heißt; bei
// overload muss auch die Zahl der Parameter stimmen. Ein external im
// implementation-Teil zählt als Rumpf. Deklarationen in einem {$IFDEF}-Zweig
// bleiben unbeachtet, ein Rumpf im ausschließenden Zweig zählt nicht
// (TConditionalBranches). Bindet die Datei Include-Dateien ein, schweigt die
// Regel für Routinen. Korrektur: leeren Rumpf vor initialization bzw. dem
// abschließenden end. anlegen.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TTypeUsedBeforeDeclarationRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnneededForwardDeclarationRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnsatisfiedForwardRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  UnsatisfiedForwardRuleId = 'unsatisfied-forward';

procedure RegisterForwardDeclarationRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Editing.ForwardDeclarations,
  Atlas.Text.Lines;

function FixesOf(const AFinding: TForwardFinding): TArray<TRuleFix>;
var
  Safe: Boolean;
begin
  Result := nil;
  if AFinding.Fix = TForwardFix.NoFix then
    Exit;
  // Ergänzen und Entfernen ändern nur eine Zeile und sind immer richtig.
  Safe := AFinding.Fix in [TForwardFix.AddForward, TForwardFix.RemoveForward];
  Result := [TRuleFix.Create(TForwardDeclarations.FixTitle(AFinding.Fix), AFinding.Edits, Safe)];
end;

{ TTypeUsedBeforeDeclarationRule }

function TTypeUsedBeforeDeclarationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('type-used-before-declaration', TRuleSeverity.Error,
    'Typ wird benutzt, bevor er deklariert ist');
end;

procedure TTypeUsedBeforeDeclarationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Finding: TForwardFinding;
  Message: string;
begin
  if (AContext.Tree = nil) or AContext.NoForwardDeclaration then
    Exit;
  for Finding in TForwardDeclarations.Analyze(AContext.Tree, AContext.Text) do
  begin
    if Finding.Issue <> TForwardIssue.UsedBeforeDeclaration then
      Continue;
    Message := Format('"%s" wird in %s benutzt, bevor es deklariert ist', [Finding.TypeName, Finding.UserName]);
    if Finding.Reason <> '' then
      Message := Message + Format(' (keine Korrektur: %s)', [Finding.Reason]);
    AReport.Add(Finding.Range, Message, FixesOf(Finding));
  end;
end;

{ TUnneededForwardDeclarationRule }

function TUnneededForwardDeclarationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unneeded-forward-declaration', TRuleSeverity.Hint,
    'Überflüssige Forward-Deklaration');
end;

procedure TUnneededForwardDeclarationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Finding: TForwardFinding;
begin
  if (AContext.Tree = nil) or AContext.NoForwardDeclaration then
    Exit;
  for Finding in TForwardDeclarations.Analyze(AContext.Tree, AContext.Text) do
    if Finding.Issue = TForwardIssue.UnneededForward then
      AReport.Add(Finding.Range, Format('Die Forward-Deklaration von "%s" wird nicht gebraucht: ' +
        '%s wird vor seiner Deklaration nicht benutzt', [Finding.TypeName, Finding.TypeName]), FixesOf(Finding));
end;

{ TUnsatisfiedForwardRule }

function TUnsatisfiedForwardRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UnsatisfiedForwardRuleId, TRuleSeverity.Error,
    'Vorwärtsdeklaration nie aufgelöst');
end;

procedure TUnsatisfiedForwardRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
  HasIncludes: Boolean;
  Implementation_: TSyntaxNode;

  /// <summary>Erstes Token ab AOffset (Index); Length(Tokens) ohne.</summary>
  function TokenAt(AOffset: Integer): Integer;
  var
    Low, High, Middle: Integer;
  begin
    Low := 0;
    High := Length(Tokens);
    while Low < High do
    begin
      Middle := (Low + High) div 2;
      if Tokens[Middle].Offset < AOffset then
        Low := Middle + 1
      else
        High := Middle;
    end;
    Result := Low;
  end;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, TokenAt(ANode.StartOffset));
  end;

  /// <summary>Bereich des ersten Bezeichners AName ab dem Anfang von ANode; der ganze Knoten ohne.</summary>
  function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
  var
    Index: Integer;
  begin
    Index := TokenAt(ANode.StartOffset);
    while (Index < Length(Tokens)) and (Tokens[Index].Offset < ANode.EndOffset) do
    begin
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) then
        Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
      Inc(Index);
    end;
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  function HasDirective(AHeader: TSyntaxNode; const ADirective: string): Boolean;
  var
    Index: Integer;
  begin
    for Index := 0 to AHeader.ChildCount - 1 do
      if (AHeader[Index].Kind = TSyntaxKind.Directive) and SameText(AHeader[Index].Name, ADirective) then
        Exit(True);
    Result := False;
  end;

  function ParamCount(AHeader: TSyntaxNode): Integer;
  var
    Params: TSyntaxNode;
    Index: Integer;
  begin
    Result := 0;
    Params := AHeader.FindChild(TSyntaxKind.Parameters);
    if Params <> nil then
      for Index := 0 to Params.ChildCount - 1 do
        if Params[Index].Kind = TSyntaxKind.Parameter then
          Inc(Result, Length(Params[Index].Name.Split([','])));
  end;

  /// <summary>Rumpf (oder external) im Sinn des Compilers: Block, asm-Block oder external.</summary>
  function IsBody(ARoutine: TSyntaxNode): Boolean;
  var
    Header: TSyntaxNode;
  begin
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    Result := (ARoutine.FindChild(TSyntaxKind.Block) <> nil) or (ARoutine.FindChild(TSyntaxKind.AsmBlock) <> nil) or
      ((Header <> nil) and HasDirective(Header, 'external'));
  end;

  /// <summary>Gibt es unter AContainer ab dem Kind AFrom einen Rumpf zur Deklaration ADecl, der mit ihr übersetzt
  /// wird?</summary>
  function Satisfied(AContainer: TSyntaxNode; AFrom: Integer; ADecl: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Header, Other: TSyntaxNode;
    Overloaded: Boolean;
  begin
    Header := ADecl.FindChild(TSyntaxKind.RoutineHeader);
    Overloaded := HasDirective(Header, 'overload');
    for Index := AFrom to AContainer.ChildCount - 1 do
    begin
      Other := AContainer[Index];
      if (Other = ADecl) or (Other.Kind <> TSyntaxKind.RoutineDecl) or not SameText(Other.Name, ADecl.Name) or
        not IsBody(Other) or TConditionalBranches.Exclusive(PathOf(ADecl), PathOf(Other)) then
        Continue;
      if not Overloaded or (Other.FindChild(TSyntaxKind.RoutineHeader) = nil) or
        (ParamCount(Other.FindChild(TSyntaxKind.RoutineHeader)) = ParamCount(Header)) then
        Exit(True);
    end;
    Result := False;
  end;

  /// <summary>Kopf bis zum ersten ";" ohne Standardwerte und Zeilenumbrüche, z. B.
  /// "function Pruefsumme(const Daten: TBytes): Cardinal;"; '' ohne ";".</summary>
  function HeadText(AHeader: TSyntaxNode): string;
  var
    Index, First, Stop, Depth: Integer;
    Text: string;
    Quoted, Skipping, Space: Boolean;
  begin
    Result := '';
    First := TokenAt(AHeader.StartOffset);
    Stop := -1;
    Depth := 0;
    for Index := First to High(Tokens) do
      if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('[') then
        Inc(Depth)
      else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
        Dec(Depth)
      else if (Depth = 0) and Tokens[Index].IsSymbol(';') then
      begin
        Stop := Index;
        Break;
      end;
    if Stop < 0 then
      Exit;
    Text := Copy(AContext.Text, Tokens[First].Offset + 1, Tokens[Stop].Offset + 1 - Tokens[First].Offset);
    Depth := 0;
    Quoted := False;
    Skipping := False;
    Space := False;
    for Index := 1 to Length(Text) do
    begin
      if Text[Index] = '''' then
        Quoted := not Quoted;
      if not Quoted then
        case Text[Index] of
          '(', '[':
            Inc(Depth);
          ')', ']':
            begin
              Dec(Depth);
              if Depth = 0 then
                Skipping := False;
            end;
          ';':
            if Depth = 1 then
              Skipping := False;
          '=':
            if Depth = 1 then
              Skipping := True;
        end;
      if Skipping then
        Continue;
      if not Quoted and CharInSet(Text[Index], [' ', #9, #10, #13]) then
      begin
        Space := Result <> '';
        Continue;
      end;
      if Space and not CharInSet(Text[Index], [';', ')', ']', ',']) then
        Result := Result + ' ';
      Space := False;
      Result := Result + Text[Index];
    end;
  end;

  /// <summary>Korrektur: leeren Rumpf vor initialization bzw. dem abschließenden "end." einfügen.</summary>
  function CreateBody(ADecl: TSyntaxNode): TArray<TRuleFix>;
  var
    Header, Section: TSyntaxNode;
    Head, Break_: string;
    Index: Integer;
    At: TTextPosition;
    Found: Boolean;
  begin
    Result := nil;
    Header := ADecl.FindChild(TSyntaxKind.RoutineHeader);
    if (Header = nil) or (Implementation_ = nil) then
      Exit;
    Head := HeadText(Header);
    if Head = '' then
      Exit;
    if HasDirective(Header, 'overload') then
      Head := Head + ' overload;';
    Found := False;
    At := Default(TTextPosition);
    Section := AContext.Tree.Root.FindChild(TSyntaxKind.InitializationSection);
    if Section <> nil then
    begin
      At := Section.StartPos;
      Found := True;
    end
    else
      for Index := High(Tokens) downto 1 do
        if Tokens[Index].IsSymbol('.') and Tokens[Index - 1].IsKeyword('end') then
        begin
          At := Tokens[Index - 1].StartPos;
          Found := True;
          Break;
        end;
    if not Found or (At.Character <> 0) then
      Exit;
    Break_ := TTextLines.LineBreakOf(AContext.Text);
    Result := [TRuleFix.Create(Format('Leeren Rumpf für %s anlegen', [ADecl.Name]),
      [TRuleEdit.Create(TTextRange.Create(At, At), Head + Break_ + 'begin' + Break_ + 'end;' + Break_ + Break_)])];
  end;

  procedure CheckRoutines(AContainer: TSyntaxNode);
  var
    Index: Integer;
    Child, Header: TSyntaxNode;
  begin
    for Index := 0 to AContainer.ChildCount - 1 do
    begin
      Child := AContainer[Index];
      if Child.Kind <> TSyntaxKind.RoutineDecl then
        Continue;
      Header := Child.FindChild(TSyntaxKind.RoutineHeader);
      if (Header <> nil) and HasDirective(Header, 'forward') and (Pos('.', Child.Name) = 0) and
        (PathOf(Child) = '') and not Satisfied(AContainer, Index + 1, Child) then
        if AContainer = Implementation_ then
          AReport.Add(NameRange(Header, Child.Name), Format('%s ist forward deklariert, aber nicht implementiert ' +
            '(wie E2065).', [Child.Name]), TRuleConfidence.High, CreateBody(Child))
        else
          AReport.Add(NameRange(Header, Child.Name), Format('%s ist forward deklariert, aber nicht implementiert ' +
            '(wie E2065).', [Child.Name]), TRuleConfidence.High);
      // Lokale Routinen mit forward.
      CheckRoutines(Child);
    end;
  end;

  procedure CheckInterface(ASection: TSyntaxNode);
  var
    Index: Integer;
    Child, Header: TSyntaxNode;
  begin
    for Index := 0 to ASection.ChildCount - 1 do
    begin
      Child := ASection[Index];
      if Child.Kind <> TSyntaxKind.RoutineDecl then
        Continue;
      Header := Child.FindChild(TSyntaxKind.RoutineHeader);
      if (Header = nil) or HasDirective(Header, 'external') or HasDirective(Header, 'forward') or
        (Pos('.', Child.Name) > 0) or (PathOf(Child) <> '') then
        Continue;
      if not Satisfied(Implementation_, 0, Child) then
        AReport.Add(NameRange(Header, Child.Name), Format('%s ist im interface deklariert, aber nicht implementiert ' +
          '(wie E2065).', [Child.Name]), TRuleConfidence.High, CreateBody(Child));
    end;
  end;

  procedure CheckTypes(ASection: TSyntaxNode);
  var
    Index, Later: Integer;
    Decl, Other, Forward_: TSyntaxNode;
    Complete: Boolean;
    Code: string;
  begin
    for Index := 0 to ASection.ChildCount - 1 do
    begin
      Decl := ASection[Index];
      if Decl.Kind <> TSyntaxKind.TypeDecl then
        Continue;
      Forward_ := Decl.FindChild(TSyntaxKind.ForwardType);
      if (Forward_ = nil) or (PathOf(Decl) <> '') then
        Continue;
      Complete := False;
      for Later := Index + 1 to ASection.ChildCount - 1 do
      begin
        Other := ASection[Later];
        if (Other.Kind = TSyntaxKind.TypeDecl) and SameText(Other.Name, Decl.Name) and
          (Other.FindChild(TSyntaxKind.ForwardType) = nil) and
          not TConditionalBranches.Exclusive(PathOf(Decl), PathOf(Other)) then
        begin
          Complete := True;
          Break;
        end;
      end;
      if Complete then
        Continue;
      if SameText(Forward_.Name, 'class') then
        Code := 'E2086'
      else
        Code := 'E2420';
      AReport.Add(NameRange(Decl, Decl.Name), Format('%s ist nur vorwärts deklariert; die vollständige ' +
        'Deklaration fehlt in diesem type-Abschnitt (wie %s).', [Decl.Name, Code]), TRuleConfidence.High);
    end;
  end;

  procedure VisitTypes(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.TypeSection then
      CheckTypes(ANode);
    // Nur Deklarationscontainer (#1094).
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
        TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl, TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
        TSyntaxKind.RecordType, TSyntaxKind.RoutineDecl] then
        VisitTypes(ANode[Index]);
  end;

var
  Token: TPascalToken;
  Interface_: TSyntaxNode;
  Text: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  HasIncludes := False;
  for Token in Tokens do
    if Token.Kind = TPascalTokenKind.Directive then
    begin
      Text := UpperCase(Token.Text);
      // {$I+} und {$I-} schalten die E/A-Prüfung um und sind keine Includes.
      if StartsStr('{$INCLUDE ', Text) or StartsStr('{$I ', Text) then
        HasIncludes := True;
    end;
  VisitTypes(AContext.Tree.Root);
  if HasIncludes then
    Exit;
  Implementation_ := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  Interface_ := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  if (Interface_ <> nil) and (Implementation_ <> nil) then
    CheckInterface(Interface_);
  if Implementation_ <> nil then
    CheckRoutines(Implementation_)
  else if AContext.Tree.Root.Kind in [TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile] then
    CheckRoutines(AContext.Tree.Root);
end;

procedure RegisterForwardDeclarationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TTypeUsedBeforeDeclarationRule.Create);
  ARegistry.Register(TUnneededForwardDeclarationRule.Create);
  ARegistry.Register(TUnsatisfiedForwardRule.Create);
end;

end.
