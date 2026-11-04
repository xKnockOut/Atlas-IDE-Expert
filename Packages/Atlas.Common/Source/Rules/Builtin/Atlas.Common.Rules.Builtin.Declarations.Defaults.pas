unit Atlas.Common.Rules.Builtin.Declarations.Defaults;

// Regel default-parameter aus Atlas.Common.Rules.Builtin.Declarations (#976, Standard aus): Parameter mit
// Vorgabewert; Korrektur: je weggelassenem Standardparameter eine Überladung, die mit dem Vorgabewert
// weiterreicht.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TDefaultParameterRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  DefaultParameterRuleId = 'default-parameter';

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Rules.Builtin.Declarations.Shared,
  Atlas.Text.Lines;

{ TDefaultParameterRule }

function TDefaultParameterRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DefaultParameterRuleId, TRuleSeverity.Warning,
    'Standardparameter statt Überladung', True);
end;

type
  TChangeParameters = TArray<Atlas.Common.Editing.ChangeSignature.TSignatureParameter>;

  /// <summary>Rumpf zu einer Deklaration: Kopf und Knoten; Found, wenn es ihn eindeutig gibt.</summary>
  TBodyMatch = record
    Header: TSignatureHeader;
    Node: TSyntaxNode;
    Found: Boolean;
  end;

procedure TDefaultParameterRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
  Lines: TArray<string>;
  LineBreak: string;
  Bodies, Calls: TArray<TSyntaxNode>;

  // Bezeichner des Namens im Kopf (beim Rumpf TFoo.Bar der letzte Teil); -1 ohne.
  function NameToken(AHeader: TSyntaxNode): Integer;
  var
    Index: Integer;
    Name: string;
  begin
    Name := BareName(AHeader.Name);
    Result := -1;
    for Index := TokenAtOffset(Tokens, AHeader.StartOffset) to High(Tokens) do
    begin
      if (Tokens[Index].Offset >= AHeader.EndOffset) or Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol(':') or
        Tokens[Index].IsSymbol(';') then
      begin
        Break;
      end;
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, Name) then
      begin
        Result := Index;
      end;
    end;
  end;

  // Modifizierer und Typen ohne Namen und Standardwerte, kleingeschrieben.
  function ParamKey(const AParameters: TChangeParameters): string;
  var
    Index: Integer;
  begin
    Result := '';
    for Index := 0 to High(AParameters) do
    begin
      Result := Result + LowerCase(AParameters[Index].Modifier + ' ' + AParameters[Index].TypeName) + ';';
    end;
  end;

  function IndentAt(AToken: Integer): string;
  begin
    Result := '';
    if Tokens[AToken].StartPos.Line <= High(Lines) then
    begin
      Result := TTextLines.IndentOf(Lines[Tokens[AToken].StartPos.Line]);
    end;
  end;

  function Conditional(const AHeader: TSignatureHeader): Boolean;
  begin
    Result := TConditionalBranches.PathAt(Paths, AHeader.StartToken) <> '';
  end;

  // Rumpf zur Deklaration: gleicher (qualifizierter) Name und gleiche Parameter, ohne Parameterliste nur eindeutig.
  function BodyOf(const AName: string; const ADecl: TSignatureHeader): TBodyMatch;
  var
    Node: TSyntaxNode;
    Candidate: TSignatureHeader;
    Count: Integer;
  begin
    Result := Default(TBodyMatch);
    Count := 0;
    for Node in Bodies do
    begin
      if SameText(StringReplace(Node.Name, ' ', '', [rfReplaceAll]), AName) and
        TChangeSignature.ReadHeader(AContext.Text, Tokens, NameToken(Node), Candidate) and
        (Candidate.StartToken > ADecl.LastToken) and
        ((Candidate.OpenToken < 0) or (ParamKey(Candidate.Parameters) = ParamKey(ADecl.Parameters))) then
      begin
        Inc(Count);
        Result.Header := Candidate;
        Result.Node := Node;
      end;
    end;
    Result.Found := Count = 1;
  end;

  // Steht der Name irgendwo nicht als Aufruf (Methodenzeiger, @Routine)? Dann wäre er nach der Korrektur mehrdeutig.
  function UsedAsValue(const AName: string): Boolean;
  var
    Node: TSyntaxNode;
  begin
    for Node in Calls do
    begin
      if SameText(Node.Name, AName) and (Node.Parent <> nil) and (Node.Parent.Kind <> TSyntaxKind.CallStatement) and
        not ((Node.Parent.Kind = TSyntaxKind.Call) and (Node.Parent[0] = Node)) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // " = Wert" hinter den Parametern des Kopfs AHeader entfernen; Zeilenumbrüche der Liste bleiben.
  function DefaultRemovals(AHeader: TSyntaxNode): TArray<TRuleEdit>;
  var
    Params, Param: TSyntaxNode;
    Index: Integer;
  begin
    Result := nil;
    Params := AHeader.FindChild(TSyntaxKind.Parameters);
    if Params <> nil then
    begin
      for Index := 0 to Params.ChildCount - 1 do
      begin
        Param := Params[Index];
        if (Param.Kind = TSyntaxKind.Parameter) and (Param.ChildCount > 1) then
        begin
          Result := Result + [TRuleEdit.Create(TTextRange.Create(Param[0].EndPos, Param[Param.ChildCount - 1].EndPos),
            '')];
        end;
      end;
    end;
  end;

  // Neue Routinen bzw. Köpfe vor ADecl: je eine Überladung ohne die letzten Standardparameter.
  function Fix(const ADecl: TSignatureHeader; ADeclNode: TSyntaxNode; const ABody: TBodyMatch; ADeclIsBody: Boolean;
    AFirst: Integer): TArray<TRuleEdit>;
  var
    Count, Index: Integer;
    Prefix: TChangeParameters;
    Changes: TArray<TParameterChange>;
    Parameter: Atlas.Common.Editing.ChangeSignature.TSignatureParameter;
    Indent, Declarations, Routines, Name: string;

    function Routine(const AHeader: TSignatureHeader; const AQualified, ADirectives: string): string;
    begin
      Result := TChangeSignature.HeaderText(AHeader, AQualified, Prefix, False) + ADirectives + LineBreak + 'begin' +
        LineBreak + '  ' + TChangeSignature.ForwardCall(AHeader, Prefix, Changes) + LineBreak + 'end;' + LineBreak +
        LineBreak;
    end;

  begin
    Indent := IndentAt(ADecl.StartToken);
    Name := BareName(ADecl.QualifiedName);
    Declarations := '';
    Routines := '';
    for Count := AFirst to High(ADecl.Parameters) do
    begin
      Prefix := Copy(ADecl.Parameters, 0, Count);
      Changes := nil;
      for Index := 0 to High(ADecl.Parameters) do
      begin
        Parameter := ADecl.Parameters[Index];
        if Index < Count then
        begin
          Changes := Changes + [TParameterChange.Kept(Index, Parameter.Name)];
        end
        else
        begin
          Changes := Changes + [TParameterChange.Added(Parameter.Name, Parameter.TypeName, Parameter.Modifier,
            Parameter.DefaultValue)];
        end;
      end;
      if ADeclIsBody then
      begin
        Declarations := Declarations + Routine(ADecl, ADecl.QualifiedName,
          TChangeSignature.OverloadDirectives(ADecl, False)) + Indent;
      end
      else
      begin
        Declarations := Declarations + TChangeSignature.HeaderText(ADecl, Name, Prefix, False) +
          TChangeSignature.OverloadDirectives(ADecl, False) + LineBreak + Indent;
        if ABody.Found then
        begin
          Routines := Routines + Routine(ABody.Header, ABody.Header.QualifiedName, '');
        end;
      end;
    end;
    Result := [TRuleEdit.Create(TTextRange.Create(Tokens[ADecl.StartToken].StartPos, Tokens[ADecl.StartToken].StartPos),
      Declarations)] + DefaultRemovals(ADeclNode);
    if not ADecl.HasDirective('overload') then
    begin
      Result := Result + [TRuleEdit.Create(TTextRange.Create(Tokens[ADecl.EndToken].EndPos,
        Tokens[ADecl.EndToken].EndPos), ' overload;')];
    end;
    if ABody.Found then
    begin
      Result := Result + [TRuleEdit.Create(TTextRange.Create(Tokens[ABody.Header.StartToken].StartPos,
        Tokens[ABody.Header.StartToken].StartPos), Routines)];
      // Ein im Rumpf wiederholter Standardwert fällt ebenfalls weg.
      Result := Result + DefaultRemovals(ABody.Node);
    end;
  end;

  // Sieht keine andere Unit die Routine? implementation-Teil (auch Methoden dort deklarierter Typen und lokale
  // Routinen) oder Programmdatei. Dann prüft UsedAsValue alle Verwendungen als Wert, und die Korrektur ist sicher;
  // eine Routine aus dem interface-Teil könnte eine andere Unit als Methodenzeiger nehmen (dann mehrdeutig).
  function UnitPrivate(AHeader: TSyntaxNode): Boolean;
  var
    Node: TSyntaxNode;
  begin
    Node := AHeader.Parent;
    while Node <> nil do
    begin
      case Node.Kind of
        TSyntaxKind.InterfaceSection:
          Exit(False);
        TSyntaxKind.ImplementationSection, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile:
          Exit(True);
      else
        // Weiter nach oben.
      end;
      Node := Node.Parent;
    end;
    Result := False;
  end;

  // Vorfahren, Nachfahren oder Aufrufer von außen geben die Signatur vor.
  function SignatureGiven(const AHeader: TSignatureHeader): Boolean;
  var
    Directive: string;
  begin
    for Directive in AHeader.Directives do
    begin
      if MatchText(Directive, ['virtual', 'dynamic', 'abstract', 'override', 'external', 'export']) or
        StartsText('message ', Directive) or StartsText('external ', Directive) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Namen der Parameter mit Vorgabewert; AFirst: Index des ersten, -1 ohne.
  function DefaultNames(const ADecl: TSignatureHeader; out AFirst: Integer): TArray<string>;
  var
    Index: Integer;
  begin
    AFirst := -1;
    Result := nil;
    for Index := High(ADecl.Parameters) downto 0 do
    begin
      if ADecl.Parameters[Index].DefaultValue <> '' then
      begin
        AFirst := Index;
        Result := [ADecl.Parameters[Index].Name] + Result;
      end;
    end;
  end;

  function DefaultMessage(const ANames: TArray<string>): string;
  begin
    if Length(ANames) = 1 then
    begin
      Result := Format('Standardparameter; eine Überladung ohne %s hält den Vorgabewert in der Bibliothek.',
        [ANames[0]]);
    end
    else
    begin
      Result := Format('Standardparameter; Überladungen ohne %s halten die Vorgabewerte in der Bibliothek.',
        [JoinedList(ANames)]);
    end;
  end;

  // Gibt es im Bereich AScope eine andere Routine gleichen Namens wie AHeader?
  function HasNamesake(AHeader: TSyntaxNode; const AScope: TArray<TSyntaxNode>): Boolean;
  var
    Node: TSyntaxNode;
  begin
    Result := False;
    for Node in AScope do
    begin
      Result := Result or ((Node <> AHeader) and SameText(BareName(Node.Name), BareName(AHeader.Name)));
    end;
  end;

  // Korrektur nur, wo die neuen Überladungen sicher eindeutig sind und niemand die Signatur vorgibt.
  function FixAllowed(AHeader: TSyntaxNode; const ADecl: TSignatureHeader; const AScope: TArray<TSyntaxNode>;
    AType: TSyntaxNode): Boolean;
  begin
    Result := not Conditional(ADecl) and not UsedAsValue(BareName(AHeader.Name));
    Result := Result and ((AType = nil) or (AType.Kind <> TSyntaxKind.InterfaceType)) and
      not SignatureGiven(ADecl) and not HasNamesake(AHeader, AScope);
  end;

  // Steht AHeader in einer Routine mit Rumpf (keine Deklaration im interface oder Typ)?
  function IsBodyHeader(AHeader: TSyntaxNode): Boolean;
  begin
    Result := (AHeader.Parent <> nil) and (AHeader.Parent.Kind = TSyntaxKind.RoutineDecl) and
      (AHeader.Parent.FindChild(TSyntaxKind.Block) <> nil);
  end;

  // Name des Rumpfs zu AHeader (bei Methoden TFoo.Bar); False bei verschachtelten und generischen Typen, deren
  // Rumpf sich nicht sicher zuordnen lässt.
  function BodyName(AHeader, AType: TSyntaxNode; out AName: string): Boolean;
  begin
    AName := BareName(AHeader.Name);
    Result := AType = nil;
    if Result then
    begin
      Exit;
    end;
    Result := not ((AType.Parent = nil) or (AType.Parent.Kind <> TSyntaxKind.TypeDecl) or
      (AType.Parent.Parent = nil) or (AType.Parent.Parent.Kind <> TSyntaxKind.TypeSection) or
      (Pos('<', AType.Parent.Name) > 0));
    if Result then
    begin
      AName := AType.Parent.Name + '.' + AName;
    end;
  end;

  // Rumpf zur Deklaration AHeader außerhalb von {$IF…}-Zweigen; Found False, wenn es keinen sicheren gibt.
  function FixBody(AHeader: TSyntaxNode; const ADecl: TSignatureHeader; AType: TSyntaxNode): TBodyMatch;
  var
    Qualified: string;
  begin
    Result := Default(TBodyMatch);
    if BodyName(AHeader, AType, Qualified) then
    begin
      Result := BodyOf(Qualified, ADecl);
      Result.Found := Result.Found and not Conditional(Result.Header);
    end;
  end;

  // Meldung am ersten Parameter mit Vorgabewert bis zum Ende der Liste.
  procedure ReportAt(AParams: TSyntaxNode; const AMessage: string; const AFixes: TArray<TRuleFix>);
  var
    Index: Integer;
  begin
    for Index := 0 to AParams.ChildCount - 1 do
    begin
      if (AParams[Index].Kind = TSyntaxKind.Parameter) and (AParams[Index].ChildCount > 1) then
      begin
        AReport.Add(TTextRange.Create(AParams[Index].StartPos, AParams[AParams.ChildCount - 1].EndPos), AMessage,
          TRuleConfidence.High, AFixes);
        Break;
      end;
    end;
  end;

  // Meldet die Deklaration AHeader; AScope: andere Köpfe desselben Bereichs, AType: Typ bei Methoden.
  procedure CheckHeader(AHeader: TSyntaxNode; const AScope: TArray<TSyntaxNode>; AType: TSyntaxNode);
  var
    Decl: TSignatureHeader;
    Body: TBodyMatch;
    Params: TSyntaxNode;
    First: Integer;
    Names: TArray<string>;
    DeclIsBody, CanFix: Boolean;
    Fixes: TArray<TRuleFix>;
  begin
    Params := AHeader.FindChild(TSyntaxKind.Parameters);
    if (Params = nil) or not TChangeSignature.ReadHeader(AContext.Text, Tokens, NameToken(AHeader), Decl) then
    begin
      Exit;
    end;
    Names := DefaultNames(Decl, First);
    if First < 0 then
    begin
      Exit;
    end;
    CanFix := FixAllowed(AHeader, Decl, AScope, AType);
    Body := Default(TBodyMatch);
    DeclIsBody := IsBodyHeader(AHeader);
    if CanFix and not DeclIsBody then
    begin
      Body := FixBody(AHeader, Decl, AType);
      CanFix := Body.Found;
    end;
    Fixes := nil;
    // Sicher (auch für --fix und die Sammelkorrektur), wenn keine andere Unit die Routine sieht.
    if CanFix then
    begin
      Fixes := [TRuleFix.Create('Überladungen statt Standardparameter', Fix(Decl, AHeader, Body, DeclIsBody, First),
        UnitPrivate(AHeader))];
    end;
    ReportAt(Params, DefaultMessage(Names), Fixes);
  end;

  // Köpfe von Routinen direkt unter ANode; Rümpfe zu einer früheren Deklaration zählen nicht.
  procedure CheckRoutines(ANode: TSyntaxNode; var AScope: TArray<TSyntaxNode>);
  var
    Index: Integer;
    Header: TSyntaxNode;
  begin
    if ANode = nil then
    begin
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[Index].Kind = TSyntaxKind.RoutineDecl then
      begin
        Header := ANode[Index].FindChild(TSyntaxKind.RoutineHeader);
        if (Header <> nil) and (Pos('.', Header.Name) = 0) then
        begin
          AScope := AScope + [Header];
        end;
      end;
    end;
  end;

  // Methodenköpfe des Typs AType, jeder gegen die übrigen geprüft.
  procedure CheckType(AType: TSyntaxNode);
  var
    Scope: TArray<TSyntaxNode>;
    Header: TSyntaxNode;
    Index: Integer;
  begin
    Scope := nil;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      if AType[Index].Kind = TSyntaxKind.RoutineHeader then
      begin
        Scope := Scope + [AType[Index]];
      end;
    end;
    for Header in Scope do
    begin
      CheckHeader(Header, Scope, AType);
    end;
  end;

  // Ist AOther eine frühere Deklaration ohne Rumpf (interface, forward) zum Rumpf AHeader (Kopf ADecl) mit
  // gleichen Parametern bzw. zur Kurzform ohne Parameterliste?
  function DeclaresEarlier(AOther, AHeader: TSyntaxNode; const ADecl: TSignatureHeader): Boolean;
  var
    Earlier: TSignatureHeader;
  begin
    Result := (AOther <> AHeader) and (AOther.Parent.FindChild(TSyntaxKind.Block) = nil) and
      SameText(AOther.Name, AHeader.Name) and (AOther.StartOffset < AHeader.StartOffset);
    Result := Result and TChangeSignature.ReadHeader(AContext.Text, Tokens, NameToken(AOther), Earlier) and
      ((ADecl.OpenToken < 0) or (ParamKey(ADecl.Parameters) = ParamKey(Earlier.Parameters)));
  end;

  // Rumpf zu einer früheren Deklaration (interface, forward) mit gleichen Parametern?
  function IsLaterBody(AHeader: TSyntaxNode; const AScope: TArray<TSyntaxNode>): Boolean;
  var
    Decl: TSignatureHeader;
    Other: TSyntaxNode;
  begin
    Result := False;
    if (AHeader.Parent.FindChild(TSyntaxKind.Block) = nil) or
      not TChangeSignature.ReadHeader(AContext.Text, Tokens, NameToken(AHeader), Decl) then
    begin
      Exit;
    end;
    for Other in AScope do
    begin
      Result := Result or DeclaresEarlier(Other, AHeader, Decl);
    end;
  end;

  // Routinen der Unit, des Programms, der Bibliothek bzw. lokale Routinen von ANode.
  procedure CheckScope(ANode: TSyntaxNode);
  var
    Scope, Declared: TArray<TSyntaxNode>;
    Header: TSyntaxNode;
  begin
    Scope := nil;
    if ANode.Kind = TSyntaxKind.UnitFile then
    begin
      CheckRoutines(ANode.FindChild(TSyntaxKind.InterfaceSection), Scope);
      CheckRoutines(ANode.FindChild(TSyntaxKind.ImplementationSection), Scope);
    end
    else
    begin
      CheckRoutines(ANode, Scope);
    end;
    Declared := nil;
    for Header in Scope do
    begin
      if not IsLaterBody(Header, Scope) then
      begin
        Declared := Declared + [Header];
      end;
    end;
    for Header in Declared do
    begin
      CheckHeader(Header, Declared, nil);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Node: TSyntaxNode;
    Index: Integer;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
          TSyntaxKind.HelperType:
            CheckType(Node);
          TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile, TSyntaxKind.RoutineDecl:
            CheckScope(Node);
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Bodies := nil;
  Calls := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind = TSyntaxKind.RoutineDecl) and (ANode.Parent.FindChild(TSyntaxKind.Block) <> nil) then
      begin
        Bodies := Bodies + [ANode];
      end
      else if ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
      begin
        Calls := Calls + [ANode];
      end;
      Result := True;
    end);
  Visit(AContext.Tree.Root);
end;

end.
