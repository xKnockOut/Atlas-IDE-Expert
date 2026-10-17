unit Atlas.Common.Lsp.Refactorings;

// Code-Aktionen aus #50 mit Namensauflösung: Extrahieren (Methode, Variable,
// Konstante), „case vervollständigen“ und „with auflösen“. Die Logik liegt in
// Atlas.Common.Editing.Extract, .CaseCompletion und .WithResolution; hier
// kommen Typen, Aufzählungswerte und die Herkunft der Bezeichner im
// with-Rumpf dazu:
//   - Typen eines Ausdrucks über einen Probetext mit "var AtlasProbe := …"
//     und die Typableitung der Inlay Hints (#453), mit eigener
//     Namensauflösung je Probe (der Probebaum lebt nur kurz).
//   - Aufzählungswerte über TLspCompletion.CaseValues (#448).
//   - Herkunft über TNameResolver.WithMember.
// Dazu „Methode aus Aufruf anlegen“ (#472): Typen der Argumente über
// denselben Probetext, Rückgabetyp über den erwarteten Typ (#417), Zielklasse
// über den Typ des Qualifizierers; Klassen aus Bibliotheken bekommen nichts.
// Dazu „Variable einbetten“ und „Methode einbetten“ (#103, experimentell):
// Bedeutung der Namen über TNameResolver.ResolveChain, der Rumpf der Methode
// über die Deklaration (auch aus einer anderen Unit des Projekts, nicht aus
// Bibliotheken).
// Was refactoring.extract, .completeCase, .resolveWith, .createMethod und
// .inline abschalten, kommt nicht.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Extract,
  Atlas.Common.Editing.WithResolution,
  Atlas.Common.Editing.Inline,
  Atlas.Common.Lsp.CompletionRequest;

type
  TRefactoringContext = record
    Index: ISymbolIndex;
    EnsureUnit: TEnsureUnitFunc;
    Namespaces: TArray<string>;
    FileName: string;
    ReadText: TCompletionReadText;
    Settings: TRefactoringSettings;
    /// <summary>Inline-Variablen erlaubt (Einstellung und Sprachversion).</summary>
    InlineVar: Boolean;
    Style: TFormatStyle;
  end;

  /// <summary>Ergebnis von „Methode aus Aufruf anlegen“ (#472).</summary>
  TCreatedMethod = record
    /// <summary>„Methode CalcDiscount anlegen“, „Routine … anlegen“ bzw. „Methode … in TFoo anlegen“.</summary>
    Title: string;
    /// <summary>Kopf der Deklaration ohne Klasse.</summary>
    Detail: string;
    /// <summary>Edits in dieser Datei.</summary>
    Edits: TArray<TTextEdit>;
    /// <summary>Edits in der Datei einer anderen Klasse des Projekts; nil sonst.</summary>
    FileEdits: TArray<TFileTextEdits>;
  end;

  TLspRefactorings = class
  public
    /// <summary>Typabfrage für Probetexte der Datei AContext.FileName.</summary>
    class function Probe(const AContext: TRefactoringContext): TTypeProbe; static;
    /// <summary>Herkunft der Bezeichner im with-Rumpf über AResolver; ATree muss die Datei sein.</summary>
    class function WithLookup(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string): TWithOwnerLookup;
      static;
    /// <summary>„case vervollständigen“ bzw. „Fehlende Werte vor else ergänzen“ für die case-Anweisung an
    /// APosition.</summary>
    class function CaseAction(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext; out AAction: TCodeAction): Boolean; static;
    /// <summary>„with auflösen“ für die with-Anweisung an APosition.</summary>
    class function WithAction(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext; out AAction: TCodeAction): Boolean; static;
    /// <summary>„Methode aus Aufruf anlegen“ für den Aufruf an APosition (#472). Mit ACaretMarker steht "$0" in der
    /// leeren Zeile des Rumpfs, wenn refactoring.createMethodCaret "body" ist. False, wenn der Name bekannt ist,
    /// kein Aufruf dort steht oder die Klasse des Qualifizierers nicht zum Projekt gehört.</summary>
    class function CreateMethod(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext; ACaretMarker: Boolean;
      out ACreated: TCreatedMethod): Boolean; static;
    /// <summary>Bedeutung von Namen für das Einbetten (#103) über AResolver.</summary>
    class function InlineLookup(AResolver: TNameResolver): TInlineLookup; static;
    /// <summary>„Variable einbetten“ und „Methode einbetten“ (#103) für APosition.</summary>
    class function InlineActions(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext): TArray<TCodeAction>; static;
    /// <summary>Alle eingeschalteten Aktionen aus #50, #103 und #472 für ARange.</summary>
    class function Actions(ATree: TSyntaxTree; const AText: string; const ARange: TTextRange;
      const AContext: TRefactoringContext): TArray<TCodeAction>; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.CreateMethod,
  Atlas.Common.Editing.CaseCompletion,
  Atlas.Common.Lsp.InlayHints,
  Atlas.Common.Lsp.Completion;

function OptionsOf(const AContext: TRefactoringContext): TExtractOptions;
begin
  Result := TExtractOptions.Default;
  Result.InlineVar := AContext.InlineVar;
  Result.Style := AContext.Style;
  Result.Probe := TLspRefactorings.Probe(AContext);
end;

function NewResolver(const AContext: TRefactoringContext): TNameResolver;
begin
  Result := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  Result.Namespaces := AContext.Namespaces;
end;

class function TLspRefactorings.Probe(const AContext: TRefactoringContext): TTypeProbe;
var
  Context: TRefactoringContext;
begin
  Context := AContext;
  Result :=
    function(const AText: string; const ANamePos: TTextPosition): TProbedType
    var
      Tree: TSyntaxTree;
      Resolver: TNameResolver;
      Found: TInferredType;
      Resolved: TResolvedSymbol;
      Owner: TUnitIndex;
      Base: string;
      Offset: Integer;
    begin
      Result := Default(TProbedType);
      Tree := TPascalParser.Parse(AText);
      Resolver := NewResolver(Context);
      try
        for Found in TLspInlayHints.Inferred(Resolver, Tree, Context.FileName, TTextRange.Create(ANamePos.Line, 0,
          ANamePos.Line, MaxInt)) do
          if (Found.NameStart.Line = ANamePos.Line) and (Found.NameStart.Character = ANamePos.Character) then
          begin
            Result.Name := Found.TypeName;
            Result.TypeUnit := Found.TypeUnit;
            Base := Found.TypeName;
            if Pos('<', Base) > 0 then
              Base := Copy(Base, 1, Pos('<', Base) - 1);
            Offset := TLineTable.Build(AText).OffsetAt(ANamePos);
            Resolved := Resolver.ResolveChain(Tree, Context.FileName, Base.Split(['.']), Offset);
            if Resolved.Found and Resolved.IsType then
              // Sichtbar: kein uses nötig.
              Result.UnitName := ''
            else
            begin
              Result.UnitName := Found.TypeUnit;
              if not ((Found.Origin.Name <> '') and Resolver.DeclaringUnit(Found.Origin, Owner) and
                Resolver.ResolveTypeFrom(Owner, Base, Resolved)) then
                Resolved := Default(TResolvedSymbol);
            end;
            if Resolved.Found and Resolved.IsType then
              if Resolved.Builtin then
                Result.IsValue := True
              else
                case Resolved.SymbolKind of
                  TIndexSymbolKind.ClassType:
                    Result.IsReference := True;
                  TIndexSymbolKind.InterfaceType:
                  begin
                    Result.IsReference := True;
                    Result.IsInterface := True;
                  end;
                  TIndexSymbolKind.RecordType, TIndexSymbolKind.ObjectType:
                  begin
                    Result.IsValue := True;
                    Result.IsRecord := True;
                  end;
                  TIndexSymbolKind.EnumType:
                    Result.IsValue := True;
                end;
            if (Result.TypeUnit = '') and Resolved.Found and not Resolved.Builtin then
              Result.TypeUnit := Resolved.UnitName;
            Break;
          end;
      finally
        Resolver.Free;
        Tree.Free;
      end;
    end;
end;

class function TLspRefactorings.WithLookup(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TWithOwnerLookup;
var
  FileName: string;
begin
  FileName := AFileName;
  Result :=
    function(AWith, AIdentifier: TSyntaxNode; out AElement: Integer): TWithOwner
    var
      Owner: TSyntaxNode;
      Unknown: Boolean;
    begin
      AElement := -1;
      if AResolver.WithMember(ATree, FileName, AIdentifier.Name, AIdentifier.StartOffset, Owner, AElement,
        Unknown) then
      begin
        if Owner = AWith then
          Result := TWithOwner.Element
        else
          Result := TWithOwner.Other;
      end
      else if Unknown then
        Result := TWithOwner.Unknown
      else
        Result := TWithOwner.Other;
    end;
end;

class function TLspRefactorings.CaseAction(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext; out AAction: TCodeAction): Boolean;
var
  CaseNode: TSyntaxNode;
  OfPos: TTextPosition;
  Values: TArray<string>;
  Prefix: string;
  Edits: TArray<TTextEdit>;
  Count: Integer;
  HasElse: Boolean;
begin
  AAction := Default(TCodeAction);
  Result := False;
  CaseNode := TCaseCompletion.CaseAt(ATree, APosition);
  if (CaseNode = nil) or not TCaseCompletion.OfPosition(ATree, CaseNode, OfPos) or
    not TLspCompletion.CaseValues(AResolver, AContext.Index, ATree, AText, AContext.FileName, OfPos,
    AContext.ReadText, Values, Prefix) or
    not TCaseCompletion.Complete(AText, ATree, CaseNode, Values, Prefix, Edits, Count, HasElse) then
    Exit;
  if HasElse then
    AAction.Title := 'Fehlende Werte vor else ergänzen'
  else
  begin
    AAction.Title := Format('case vervollständigen (%d fehlende Werte)', [Count]);
    AAction.IsPreferred := True;
  end;
  AAction.Kind := RewriteKind;
  AAction.Tag := CaseCompleteTag;
  AAction.Edits := Edits;
  Result := True;
end;

class function TLspRefactorings.WithAction(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext; out AAction: TCodeAction): Boolean;
var
  WithNode: TSyntaxNode;
begin
  AAction := Default(TCodeAction);
  WithNode := TWithResolution.WithAt(ATree, APosition);
  Result := (WithNode <> nil) and TWithResolution.Resolve(AText, ATree, WithNode,
    WithLookup(AResolver, ATree, AContext.FileName), OptionsOf(AContext), AAction);
end;

class function TLspRefactorings.CreateMethod(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext; ACaretMarker: Boolean;
  out ACreated: TCreatedMethod): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Site: TCreateCallSite;
  Routine, ClassBody: TSyntaxNode;
  Probe: TTypeProbe;
  Plan: TCreateMethodPlan;
  Parameter: TCreateParameter;
  Probed, Owner: TProbedType;
  Names: TArray<string>;
  Units: TArray<string>;
  StatementOffset, Index, Offset: Integer;
  StatementPos: TTextPosition;
  Resolved: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  OwnerName, OtherText, LineBreak, UnitName: string;
  OtherTree: TSyntaxTree;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
  Files: TFileTextEdits;

  function ProbeOf(const AExpression: string): TProbedType;
  begin
    // "var AtlasProbe := Ausdruck; " direkt vor der Anweisung, damit dieselben Namen sichtbar sind.
    Result := Probe(Copy(AText, 1, StatementOffset) + 'var ' + TExtractRefactoring.ProbeName + ' := ' + AExpression +
      '; ' + Copy(AText, StatementOffset + 1, MaxInt), TTextPosition.Create(StatementPos.Line,
      StatementPos.Character + 4));
  end;

begin
  ACreated := Default(TCreatedMethod);
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Tokens := ATree.Tokens;
  if not TCreateMethod.Site(Tokens, APosition, Site) then
    Exit;
  Routine := TRoutineBody.RoutineAt(ATree, Tokens[Site.NameIndex].Offset);
  if (Routine = nil) or AResolver.Resolve(ATree, AContext.FileName, Site.NameRange.StartPos).Found then
    Exit;
  Probe := TLspRefactorings.Probe(AContext);
  StatementOffset := Tokens[Site.StatementStart].Offset;
  StatementPos := Tokens[Site.StatementStart].StartPos;
  Plan := Default(TCreateMethodPlan);
  Plan.Name := Site.Name;
  Plan.Style := AContext.Style;
  Plan.Section := AContext.Settings.CreateMethodSection;
  Plan.CaretInBody := ACaretMarker and AContext.Settings.CreateMethodCaretInBody;
  // Parameter: Typ aus dem Literal bzw. über den Probetext, Name aus dem Argument bzw. dem Typ.
  Names := nil;
  Units := nil;
  for Index := 0 to High(Site.Arguments) do
  begin
    Parameter := Default(TCreateParameter);
    Probed := Default(TProbedType);
    Parameter.TypeName := TCreateMethod.LiteralType(Tokens, Site.Arguments[Index]);
    if Parameter.TypeName = '' then
    begin
      Probed := ProbeOf(Site.Arguments[Index].Text);
      Parameter.TypeName := Probed.Name;
      if Probed.TypeUnit <> '' then
        Units := Units + [Probed.TypeUnit];
    end;
    if Parameter.TypeName = '' then
      Parameter.TypeName := TCreateMethod.TypePlaceholder;
    Parameter.IsConst := AContext.Settings.ConstParameters and TCreateMethod.WantsConst(Parameter.TypeName,
      Probed.IsRecord, Probed.IsInterface);
    Parameter.Name := TCreateMethod.ArgumentName(Tokens, Site.Arguments[Index]);
    if Parameter.Name = '' then
      Parameter.Name := TCreateMethod.NameFromType(Parameter.TypeName);
    Names := Names + [Parameter.Name];
    Plan.Parameters := Plan.Parameters + [Parameter];
  end;
  Names := TCreateMethod.UniqueNames(Names);
  for Index := 0 to High(Plan.Parameters) do
    Plan.Parameters[Index].Name := Names[Index];
  // Rückgabe: Prozedur als eigene Anweisung, Boolean in Bedingungen, sonst der erwartete Typ.
  case Site.Context of
    TCallContext.Statement:
      Plan.ResultType := '';
    TCallContext.Condition:
      Plan.ResultType := 'Boolean';
  else
    Plan.ResultType := TLspCompletion.ExpectedType(AResolver, ATree, AContext.FileName, Site.NameRange.StartPos);
    if (Plan.ResultType = '') and (Site.Target <> '') then
    begin
      Probed := ProbeOf(Site.Target);
      Plan.ResultType := Probed.Name;
      if Probed.TypeUnit <> '' then
        Units := Units + [Probed.TypeUnit];
    end;
    if Plan.ResultType = '' then
      Plan.ResultType := TCreateMethod.TypePlaceholder;
  end;
  // Ziel: ohne Qualifizierer (oder Self) die eigene Klasse bzw. eine Routine davor.
  if (Site.Qualifier = '') or SameText(Site.Qualifier, 'Self') then
  begin
    if Pos('.', Routine.Name) > 0 then
    begin
      Plan.TypeName := Copy(Routine.Name, 1, LastDelimiter('.', Routine.Name) - 1);
      Index := TRoutineBody.TokenAt(Tokens, Routine.StartOffset);
      Plan.IsClassMethod := (Index <= High(Tokens)) and Tokens[Index].IsKeyword('class');
      if not TCreateMethod.MethodEdits(AText, ATree, Plan, ACreated.Edits) then
        Exit;
      ACreated.Title := Format('Methode %s anlegen', [Plan.Name]);
    end
    else if SameText(Site.Qualifier, 'Self') then
      Exit
    else
    begin
      ACreated.Edits := [TCreateMethod.RoutineEdit(AText, Routine, Plan)];
      ACreated.Title := Format('Routine %s anlegen', [Plan.Name]);
    end;
    ACreated.Detail := TCreateMethod.Header(Plan, False);
    Exit(True);
  end;
  // Mit Qualifizierer: Klasse bzw. Record des Objekts, nur aus dem Projekt.
  Owner := ProbeOf(Site.Qualifier);
  if (Owner.Name = '') or Owner.IsInterface or not (Owner.IsReference or Owner.IsRecord) then
    Exit;
  OwnerName := Owner.Name;
  if Pos('<', OwnerName) > 0 then
    Exit;
  Offset := Tokens[Site.CallStart].Offset;
  Resolved := AResolver.ResolveChain(ATree, AContext.FileName, OwnerName.Split(['.']), Offset);
  if not (Resolved.Found and Resolved.IsType) or Resolved.Builtin or
    not AResolver.DeclaringUnit(Resolved, OwnerUnit) or OwnerUnit.Library_ then
    Exit;
  Plan.TypeName := Resolved.Name;
  if (Resolved.Container <> '') and (Pos('.', Plan.TypeName) = 0) then
    Plan.TypeName := Resolved.Container + '.' + Plan.TypeName;
  ACreated.Title := Format('Methode %s in %s anlegen', [Plan.Name, Plan.TypeName]);
  if SameText(OwnerUnit.FileName, AContext.FileName) then
  begin
    if not TCreateMethod.MethodEdits(AText, ATree, Plan, ACreated.Edits) then
      Exit;
  end
  else
  begin
    // Andere Unit: public, damit der Aufruf übersetzt; fehlende Units der Parametertypen ins uses.
    if not (Assigned(AContext.ReadText) and AContext.ReadText(OwnerUnit.FileName, OtherText)) then
      Exit;
    Plan.Section := 'public';
    Plan.CaretInBody := False;
    OtherTree := TPascalParser.Parse(OtherText);
    try
      if not TCreateMethod.MethodEdits(OtherText, OtherTree, Plan, Edits) then
        Exit;
      LineBreak := TTextLines.LineBreakOf(OtherText);
      ClassBody := TRoutineBody.TypeBody(OtherTree.Root, Resolved.Name);
      for UnitName in Units do
        if not SameText(UnitName, OwnerUnit.UnitName) and
          not TUsesClauses.IsUsed(OwnerUnit.InterfaceUses, UnitName, AContext.Namespaces) and
          TUsesClauses.AddUnit(OtherTree.Tokens, ClassBody.StartOffset, UnitName, LineBreak, Edit) then
        begin
          Edits := Edits + [Edit];
          OwnerUnit.InterfaceUses := OwnerUnit.InterfaceUses + [UnitName];
        end;
    finally
      OtherTree.Free;
    end;
    Files.FileName := OwnerUnit.FileName;
    Files.Edits := Edits;
    ACreated.FileEdits := [Files];
  end;
  ACreated.Detail := TCreateMethod.Header(Plan, False);
  Result := True;
end;

class function TLspRefactorings.InlineLookup(AResolver: TNameResolver): TInlineLookup;
begin
  Result :=
    function(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer): TInlineMeaning
    var
      Resolved: TResolvedSymbol;
    begin
      Result := Default(TInlineMeaning);
      Resolved := AResolver.ResolveChain(ATree, AFileName, ANames, AOffset);
      if not Resolved.Found then
        Exit;
      Result.Found := True;
      // Gleiche Deklaration: gleiche Art, Unit, Datei, Name und Stelle.
      Result.Key := LowerCase(Format('%d|%s|%s|%s|%d:%d', [Ord(Resolved.Kind), Resolved.UnitName, Resolved.FileName,
        Resolved.QualifiedName, Resolved.Range.StartPos.Line, Resolved.Range.StartPos.Character]));
      Result.IsType := Resolved.IsType;
      Result.IsRoutine := Resolved.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
        TIndexSymbolKind.Routine];
      Result.IsMember := (Resolved.Kind = TResolvedKind.Symbol) and (Resolved.Container <> '') and
        (Resolved.SymbolKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Method,
        TIndexSymbolKind.Constructor_]);
      Result.Container := Resolved.Container;
      case Resolved.Visibility of
        TIndexVisibility.Protected:
          Result.Visibility := TInlineVisibility.Protected;
        TIndexVisibility.StrictProtected:
          Result.Visibility := TInlineVisibility.StrictProtected;
        TIndexVisibility.Private:
          Result.Visibility := TInlineVisibility.Private;
        TIndexVisibility.StrictPrivate:
          Result.Visibility := TInlineVisibility.StrictPrivate;
      else
        Result.Visibility := TInlineVisibility.Public;
      end;
    end;
end;

/// <summary>Passt der Rumpf ARoutine zu ACount Argumenten (Pflichtparameter bis alle Parameter)?</summary>
function AcceptsArguments(ARoutine: TSyntaxNode; ACount: Integer): Boolean;
var
  Header, Parameters: TSyntaxNode;
  Index, Total, Required, Names: Integer;
begin
  Total := 0;
  Required := 0;
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  Parameters := nil;
  if Header <> nil then
    Parameters := Header.FindChild(TSyntaxKind.Parameters);
  if Parameters <> nil then
    for Index := 0 to Parameters.ChildCount - 1 do
    begin
      Names := Length(Parameters[Index].Name.Split([',']));
      Inc(Total, Names);
      if Parameters[Index].ChildCount < 2 then
        Inc(Required, Names);
    end;
  Result := (ACount >= Required) and (ACount <= Total);
end;

class function TLspRefactorings.InlineActions(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext): TArray<TCodeAction>;
var
  Options: TInlineOptions;
  Source, Callee: TInlineSource;
  Action: TCodeAction;
  Call: TInlineCall;
  Resolved: TResolvedSymbol;
  Owner: TUnitIndex;
  Name, CalleeText: string;
  CalleeTree: TSyntaxTree;
  Routine, Candidate: TSyntaxNode;
  Count: Integer;
begin
  Result := nil;
  Options := TInlineOptions.Default;
  Options.InlineVar := AContext.InlineVar;
  Options.Style := AContext.Style;
  Options.Lookup := InlineLookup(AResolver);
  Source := TInlineSource.Create(AContext.FileName, AText, ATree);
  if TInlineRefactoring.InlineVariable(Source, APosition, Options, Action) then
    Result := Result + [Action];
  if not TInlineRefactoring.CallAt(ATree, AText, APosition, Call) then
    Exit;
  Resolved := AResolver.Resolve(ATree, AContext.FileName, Call.NamePos);
  if not Resolved.Found or (Resolved.Kind <> TResolvedKind.Symbol) or
    not (Resolved.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) or
    not AResolver.DeclaringUnit(Resolved, Owner) or Owner.Library_ then
    Exit;
  Name := Resolved.Name;
  if Resolved.Container <> '' then
    Name := Resolved.Container + '.' + Name;
  CalleeTree := nil;
  try
    if SameText(Owner.FileName, AContext.FileName) then
      Callee := Source
    else
    begin
      if not (Assigned(AContext.ReadText) and AContext.ReadText(Owner.FileName, CalleeText)) then
        Exit;
      CalleeTree := TPascalParser.Parse(CalleeText);
      Callee := TInlineSource.Create(Owner.FileName, CalleeText, CalleeTree);
      AResolver.PinTree(CalleeTree, Owner.FileName);
    end;
    try
      // Überladungen: der einzige Rumpf, der zur Zahl der Argumente passt.
      Routine := nil;
      Count := 0;
      for Candidate in TInlineRefactoring.FindRoutines(Callee.Tree, Name) do
        if AcceptsArguments(Candidate, Length(Call.Arguments)) then
        begin
          Routine := Candidate;
          Inc(Count);
        end;
      if (Count = 1) and TInlineRefactoring.InlineMethod(Source, APosition, Callee, Routine, Options, Action) then
        Result := Result + [Action];
    finally
      if CalleeTree <> nil then
        AResolver.UnpinTree;
    end;
  finally
    CalleeTree.Free;
  end;
end;

class function TLspRefactorings.Actions(ATree: TSyntaxTree; const AText: string; const ARange: TTextRange;
  const AContext: TRefactoringContext): TArray<TCodeAction>;
var
  Resolver: TNameResolver;
  Action: TCodeAction;
  Created: TCreatedMethod;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  if AContext.Settings.Extract then
    Result := Result + TExtractRefactoring.Actions(AText, ATree, ARange, OptionsOf(AContext));
  if not (AContext.Settings.CompleteCase or AContext.Settings.ResolveWith or AContext.Settings.CreateMethod or
    AContext.Settings.InlineCode) then
    Exit;
  Resolver := NewResolver(AContext);
  try
    Resolver.PinTree(ATree, AContext.FileName);
    try
      if AContext.Settings.CompleteCase and CaseAction(Resolver, ATree, AText, ARange.StartPos, AContext, Action) then
        Result := Result + [Action];
      if AContext.Settings.ResolveWith and WithAction(Resolver, ATree, AText, ARange.StartPos, AContext, Action) then
        Result := Result + [Action];
      if AContext.Settings.CreateMethod and CreateMethod(Resolver, ATree, AText, ARange.StartPos, AContext, False,
        Created) then
      begin
        Action := Default(TCodeAction);
        Action.Title := Created.Title;
        Action.Kind := QuickFixKind;
        Action.Edits := Created.Edits;
        Action.FileEdits := Created.FileEdits;
        Result := Result + [Action];
      end;
      if AContext.Settings.InlineCode then
        Result := Result + InlineActions(Resolver, ATree, AText, ARange.StartPos, AContext);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

end.
