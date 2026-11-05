unit Atlas.Common.Lsp.Refactorings;

// Code-Aktionen aus #50 mit Namensauflösung: Extrahieren (Methode, Variable,
// Konstante), „case vervollständigen“ und „with auflösen“. Die Logik liegt in
// Atlas.Common.Editing.Extract, .CaseCompletion und .WithResolution; hier
// kommen Typen, Aufzählungswerte und die Herkunft der Bezeichner im
// with-Rumpf dazu:
//   - Typen eines Ausdrucks über einen Probetext mit "var AtlasProbe := …"
//     und die Typableitung der Inlay Hints (#453), mit eigener
//     Namensauflösung je Probe (der Probebaum lebt nur kurz).
//   - Aufzählungswerte über TCompletionValues.CaseValues (#448).
//   - Herkunft über TNameResolver.Queries.WithMember.
// Dazu „Methode aus Aufruf anlegen“ (#472): Typen der Argumente über
// denselben Probetext, Rückgabetyp über den erwarteten Typ (#417), Zielklasse
// über den Typ des Qualifizierers; Klassen aus Bibliotheken bekommen nichts.
// Dazu „Variable einbetten“ und „Methode einbetten“ (#103, experimentell):
// Bedeutung der Namen über TNameResolver.ResolveChain, der Rumpf der Methode
// über die Deklaration (auch aus einer anderen Unit des Projekts, nicht aus
// Bibliotheken).
// Dazu „In case umwandeln“ und „In if-Kette umwandeln“ (#646): Typ des
// verglichenen Ausdrucks und Konstanten über TIfCaseLookup.FromResolver.
// Dazu die Umformungen von Bedingungen (#656) aus Atlas.Common.Editing.Conditions,
// ohne Namensauflösung.
// Dazu if-Anweisung und Bedingungsausdruck ineinander umwandeln und IfThen
// ersetzen (#684): Typen der Werte und Herkunft von IfThen über
// TConditionalLookup.FromResolver; vor Delphi 13 nur „In if-Anweisung umwandeln“.
// Dazu lokale Routine und Methode ineinander umwandeln (#663): Records,
// Objekte und Interfaces für const über TNestedRoutineLookup.FromResolver.
// Was refactoring.extract, .completeCase, .resolveWith, .createMethod,
// .inline, .ifCase, .conditions, .conditionalExpression und .nestedRoutine
// abschalten, kommt nicht.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Extract,
  Atlas.Common.Editing.WithResolution,
  Atlas.Common.Editing.Inlining,
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
    /// <summary>Bedingungsausdrücke erlaubt (Sprachversion, #684); sonst nur der Rückweg zur if-Anweisung.</summary>
    IfExpression: Boolean;
    Style: TFormatStyle;
    /// <summary>Präfixe neuer Namen nach der Namensregel (#1111, TRuleEngine.NewNames); ohne leer.</summary>
    NewNames: TPascalNamePrefixes;
    /// <summary>"$0" für die Schreibmarke in den Rumpf neuer Methoden (#472, nur aus der Vervollständigung).</summary>
    CaretMarker: Boolean;
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
    /// <summary>Optionen für Extrahieren und „with auflösen“ zur Datei AContext.FileName (#657).</summary>
    class function ExtractOptions(const AContext: TRefactoringContext): TExtractOptions; static;
    /// <summary>„case vervollständigen“ bzw. „Fehlende Werte vor else ergänzen“ für die case-Anweisung an
    /// APosition.</summary>
    class function CaseAction(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext; out AAction: TCodeAction): Boolean; static;
    /// <summary>„with auflösen“ für die with-Anweisung an APosition.</summary>
    class function WithAction(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext; out AAction: TCodeAction): Boolean; static;
    /// <summary>„Methode aus Aufruf anlegen“ für den Aufruf an APosition (#472). Mit AContext.CaretMarker steht "$0"
    /// in der leeren Zeile des Rumpfs, wenn refactoring.createMethodCaret "body" ist. False, wenn der Name bekannt
    /// ist, kein Aufruf dort steht oder die Klasse des Qualifizierers nicht zum Projekt gehört.</summary>
    class function CreateMethod(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext; out ACreated: TCreatedMethod): Boolean;
      static;
    /// <summary>Bedeutung von Namen für das Einbetten (#103) über AResolver.</summary>
    class function InlineLookup(AResolver: TNameResolver): TInlineLookup; static;
    /// <summary>„Variable einbetten“ und „Methode einbetten“ (#103) für APosition.</summary>
    class function InlineActions(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext): TArray<TCodeAction>; static;
    /// <summary>„In case umwandeln“ bzw. „In if-Kette umwandeln“ (#646) für den Kopf an APosition.</summary>
    class function IfCaseActions(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext): TArray<TCodeAction>; static;
    /// <summary>Bedingung umkehren, früher Ausstieg, if zusammenfassen, doppelte Verneinung (#656).</summary>
    class function ConditionActions(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      const AContext: TRefactoringContext): TArray<TCodeAction>; static;
    /// <summary>In bedingten Ausdruck bzw. if-Anweisung umwandeln, IfThen ersetzen (#684).</summary>
    class function ConditionalExpressionActions(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext): TArray<TCodeAction>; static;
    /// <summary>Lokale Routine herauslösen bzw. Routine als lokale einbetten (#663).</summary>
    class function NestedRoutineActions(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext): TArray<TCodeAction>; static;
    /// <summary>Alle eingeschalteten Aktionen aus #50, #103, #472, #646, #656, #663 und #684 für ARange.</summary>
    class function Actions(ATree: TSyntaxTree; const AText: string; const ARange: TTextRange;
      const AContext: TRefactoringContext): TArray<TCodeAction>; static;
  end;

implementation

uses
  Atlas.Common.Lsp.Completion.Context,
  Atlas.Common.Lsp.Completion.Values,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.CreateMethod,
  Atlas.Common.Editing.CaseCompletion,
  Atlas.Common.Editing.StatementText,
  Atlas.Common.Editing.IfCase,
  Atlas.Common.Editing.Conditions,
  Atlas.Common.Editing.ConditionalExpression,
  Atlas.Common.Editing.NestedRoutines,
  Atlas.Common.Lsp.InlayHints,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TRefactoringsText = (AddMissingValuesBeforeElse, CompleteCaseMissingValues, CreateMethod, CreateRoutine,
    CreateMethodIn);

const
  cTexts: array[TRefactoringsText] of TAtlasText = (
    (De: 'Fehlende Werte vor else ergänzen'; En: 'Add missing values before else'),
    (De: 'case vervollständigen (%d fehlende Werte)'; En: 'Complete case (%d missing values)'),
    (De: 'Methode %s anlegen'; En: 'Create method %s'),
    (De: 'Routine %s anlegen'; En: 'Create routine %s'),
    (De: 'Methode %s in %s anlegen'; En: 'Create method %s in %s'));

{$SCOPEDENUMS OFF}

function OptionsOf(const AContext: TRefactoringContext): TExtractOptions;
begin
  Result := TExtractOptions.Default;
  Result.InlineVar := AContext.InlineVar;
  Result.Style := AContext.Style;
  Result.Probe := TLspRefactorings.Probe(AContext);
  Result.Names := AContext.NewNames;
end;

function NewResolver(const AContext: TRefactoringContext): TNameResolver;
begin
  Result := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  Result.Namespaces := AContext.Namespaces;
end;

class function TLspRefactorings.ExtractOptions(const AContext: TRefactoringContext): TExtractOptions;
begin
  Result := OptionsOf(AContext);
end;

/// <summary>Trägt die Art des Typs AResolved (Wert, Referenz, Interface, Record) in AProbed ein.</summary>
procedure MarkKind(const AResolved: TResolvedSymbol; var AProbed: TProbedType);
begin
  if not (AResolved.Found and AResolved.IsType) then
  begin
    Exit;
  end;
  if AResolved.Builtin then
  begin
    AProbed.IsValue := True;
    Exit;
  end;
  case AResolved.SymbolKind of
    TIndexSymbolKind.ClassType:
      AProbed.IsReference := True;
    TIndexSymbolKind.InterfaceType:
    begin
      AProbed.IsReference := True;
      AProbed.IsInterface := True;
    end;
    TIndexSymbolKind.RecordType, TIndexSymbolKind.ObjectType:
    begin
      AProbed.IsValue := True;
      AProbed.IsRecord := True;
    end;
    TIndexSymbolKind.EnumType:
      AProbed.IsValue := True;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Löst den abgeleiteten Typ AFound an AOffset auf; AProbed.UnitName bleibt leer, wenn er sichtbar
/// ist (kein uses nötig).</summary>
function ResolveFound(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string; AOffset: Integer;
  const AFound: TInferredType; var AProbed: TProbedType): TResolvedSymbol;
var
  mBase: string;
  mOwner: TUnitIndex;
begin
  mBase := AFound.TypeName;
  if Pos('<', mBase) > 0 then
  begin
    mBase := Copy(mBase, 1, Pos('<', mBase) - 1);
  end;
  Result := AResolver.ResolveChain(ATree, AFileName, mBase.Split(['.']), AOffset);
  if Result.Found and Result.IsType then
  begin
    AProbed.UnitName := '';
    Exit;
  end;
  AProbed.UnitName := AFound.TypeUnit;
  if not ((AFound.Origin.Name <> '') and AResolver.DeclaringUnit(AFound.Origin, mOwner) and
    AResolver.ResolveTypeFrom(mOwner, mBase, Result)) then
  begin
    Result := Default(TResolvedSymbol);
  end;
end;

/// <summary>Typ des Namens an ANamePos im Probetext AText der Datei AContext.FileName.</summary>
function ProbeType(const AContext: TRefactoringContext; const AText: string;
  const ANamePos: TTextPosition): TProbedType;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mFound: TInferredType;
  mResolved: TResolvedSymbol;
begin
  Result := Default(TProbedType);
  mTree := TSyntaxTreeCache.Parse(AText);
  mResolver := NewResolver(AContext);
  try
    for mFound in TLspInlayHints.Inferred(mResolver, mTree, AContext.FileName, TTextRange.Create(ANamePos.Line, 0,
      ANamePos.Line, MaxInt)) do
    begin
      if (mFound.NameStart.Line = ANamePos.Line) and (mFound.NameStart.Character = ANamePos.Character) then
      begin
        Result.Name := mFound.TypeName;
        Result.TypeUnit := mFound.TypeUnit;
        mResolved := ResolveFound(mResolver, mTree, AContext.FileName, TLineTable.Build(AText).OffsetAt(ANamePos),
          mFound, Result);
        MarkKind(mResolved, Result);
        if (Result.TypeUnit = '') and mResolved.Found and not mResolved.Builtin then
        begin
          Result.TypeUnit := mResolved.UnitName;
        end;
        Break;
      end;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

class function TLspRefactorings.Probe(const AContext: TRefactoringContext): TTypeProbe;
var
  mContext: TRefactoringContext;
begin
  mContext := AContext;
  Result :=
    function(const AText: string; const ANamePos: TTextPosition): TProbedType
    begin
      Result := ProbeType(mContext, AText, ANamePos);
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
      mWith: TResolvedWithMember;
    begin
      AElement := -1;
      if AResolver.Queries.WithMember(ATree, FileName, AIdentifier.Name, AIdentifier.StartOffset, mWith) then
      begin
        AElement := mWith.Element;
        if mWith.Statement = AWith then
        begin
          Result := TWithOwner.Element;
        end
        else
        begin
          Result := TWithOwner.Other;
        end;
      end
      else if mWith.Unknown then
      begin
        Result := TWithOwner.Unknown;
      end
      else
      begin
        Result := TWithOwner.Other;
      end;
    end;
end;

/// <summary>Was TCompletionValues.CaseValues zum Auflösen der Aufzählung braucht.</summary>
function CaseLookup(AResolver: TNameResolver; const AContext: TRefactoringContext; ATree: TSyntaxTree;
  const AText: string): TEnumLookup;
begin
  Result.Resolver := AResolver;
  Result.Index := AContext.Index;
  Result.Tree := ATree;
  Result.Text := AText;
  Result.FileName := AContext.FileName;
  Result.ReadText := AContext.ReadText;
end;

class function TLspRefactorings.CaseAction(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext; out AAction: TCodeAction): Boolean;
var
  CaseNode: TSyntaxNode;
  OfPos: TTextPosition;
  Values: TArray<string>;
  Prefix: string;
  Completion: TCaseCompletionEdits;
begin
  AAction := Default(TCodeAction);
  Result := False;
  CaseNode := TCaseCompletion.CaseAt(ATree, APosition);
  if (CaseNode = nil) or not TCaseCompletion.OfPosition(ATree, CaseNode, OfPos) or
    not TCompletionValues.CaseValues(CaseLookup(AResolver, AContext, ATree, AText), OfPos, Values, Prefix) or
    not TCaseCompletion.Complete(AText, ATree, CaseNode, Values, Prefix, Completion) then
  begin
    Exit;
  end;
  if Completion.HasElse then
  begin
    AAction.Title := cTexts[TRefactoringsText.AddMissingValuesBeforeElse].Text;
  end
  else
  begin
    AAction.Title := cTexts[TRefactoringsText.CompleteCaseMissingValues].Fmt([Completion.Count]);
    AAction.IsPreferred := True;
  end;
  AAction.Kind := RewriteKind;
  AAction.Tag := CaseCompleteTag;
  AAction.Edits := Completion.Edits;
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

type
  /// <summary>Ein Lauf von „Methode aus Aufruf anlegen“ (#472).</summary>
  TCreateMethodRun = class
  private
    FResolver: TNameResolver;
    FTree: TSyntaxTree;
    FText: string;
    FContext: TRefactoringContext;
    FTokens: TArray<TPascalToken>;
    FSite: TCreateCallSite;
    FProbe: TTypeProbe;
    FPlan: TCreateMethodPlan;
    FUnits: TArray<string>;
    FCreated: TCreatedMethod;
    function ProbeOf(const AExpression: string): TProbedType;
    function ProbeWithUnit(const AExpression: string): TProbedType;
    function NewParameter(const AArgument: TCallArgument): TCreateParameter;
    procedure AddParameters;
    function ResultType: string;
    function LocalTarget(ARoutine: TSyntaxNode): Boolean;
    function OwnerType(out AResolved: TResolvedSymbol; out AOwner: TUnitIndex): Boolean;
    function OtherUnitEdits(const AResolved: TResolvedSymbol; const AOwner: TUnitIndex): Boolean;
    function QualifiedTarget: Boolean;
  public
    constructor Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const AContext: TRefactoringContext);
    function Run(const APosition: TTextPosition): Boolean;
    property Created: TCreatedMethod read FCreated;
  end;

{ TCreateMethodRun }

constructor TCreateMethodRun.Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const AContext: TRefactoringContext);
begin
  inherited Create;
  FResolver := AResolver;
  FTree := ATree;
  FText := AText;
  FContext := AContext;
  FTokens := ATree.Tokens;
  FProbe := TLspRefactorings.Probe(AContext);
end;

function TCreateMethodRun.ProbeOf(const AExpression: string): TProbedType;
var
  mOffset: Integer;
  mPos: TTextPosition;
begin
  // "var AtlasProbe := Ausdruck; " direkt vor der Anweisung, damit dieselben Namen sichtbar sind.
  mOffset := FTokens[FSite.StatementStart].Offset;
  mPos := FTokens[FSite.StatementStart].StartPos;
  Result := FProbe(Copy(FText, 1, mOffset) + 'var ' + TExtractRefactoring.ProbeName + ' := ' + AExpression + '; ' +
    Copy(FText, mOffset + 1, MaxInt), TTextPosition.Create(mPos.Line, mPos.Character + 4));
end;

function TCreateMethodRun.ProbeWithUnit(const AExpression: string): TProbedType;
begin
  Result := ProbeOf(AExpression);
  if Result.TypeUnit <> '' then
  begin
    FUnits := FUnits + [Result.TypeUnit];
  end;
end;

function TCreateMethodRun.NewParameter(const AArgument: TCallArgument): TCreateParameter;
var
  mProbed: TProbedType;
begin
  // Typ aus dem Literal bzw. über den Probetext, Name aus dem Argument bzw. dem Typ.
  Result := Default(TCreateParameter);
  mProbed := Default(TProbedType);
  Result.TypeName := TCreateMethod.LiteralType(FTokens, AArgument);
  if Result.TypeName = '' then
  begin
    mProbed := ProbeWithUnit(AArgument.Text);
    Result.TypeName := mProbed.Name;
  end;
  if Result.TypeName = '' then
  begin
    Result.TypeName := TCreateMethod.TypePlaceholder;
  end;
  Result.IsConst := FContext.Settings.ConstParameters and TCreateMethod.WantsConst(Result.TypeName,
    mProbed.IsRecord, mProbed.IsInterface);
  Result.Name := TCreateMethod.ArgumentName(FTokens, AArgument);
  if Result.Name = '' then
  begin
    Result.Name := TCreateMethod.NameFromType(Result.TypeName);
  end;
  // Präfix der Namensregel (APreis statt Preis), sonst meldet naming-prefix die neue Methode gleich.
  Result.Name := FContext.NewNames.Parameter(Result.Name);
end;

procedure TCreateMethodRun.AddParameters;
var
  mArgument: TCallArgument;
  mNames: TArray<string>;
  mIndex: Integer;
begin
  mNames := nil;
  for mArgument in FSite.Arguments do
  begin
    FPlan.Parameters := FPlan.Parameters + [NewParameter(mArgument)];
    mNames := mNames + [FPlan.Parameters[High(FPlan.Parameters)].Name];
  end;
  mNames := TCreateMethod.UniqueNames(mNames);
  for mIndex := 0 to High(FPlan.Parameters) do
  begin
    FPlan.Parameters[mIndex].Name := mNames[mIndex];
  end;
end;

function TCreateMethodRun.ResultType: string;
begin
  // Prozedur als eigene Anweisung, Boolean in Bedingungen, sonst der erwartete Typ.
  case FSite.Context of
    TCallContext.Statement:
      Result := '';
    TCallContext.Condition:
      Result := 'Boolean';
  else
    Result := TCompletionContexts.ExpectedType(FResolver, FTree, FContext.FileName, FSite.NameRange.StartPos);
    if (Result = '') and (FSite.Target <> '') then
    begin
      Result := ProbeWithUnit(FSite.Target).Name;
    end;
    if Result = '' then
    begin
      Result := TCreateMethod.TypePlaceholder;
    end;
  end;
end;

function TCreateMethodRun.LocalTarget(ARoutine: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  // Ohne Qualifizierer (oder Self) die eigene Klasse bzw. eine Routine davor.
  Result := False;
  if Pos('.', ARoutine.Name) > 0 then
  begin
    FPlan.TypeName := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
    mIndex := TRoutineBody.TokenAt(FTokens, ARoutine.StartOffset);
    FPlan.IsClassMethod := (mIndex <= High(FTokens)) and FTokens[mIndex].IsKeyword('class');
    if not TCreateMethod.MethodEdits(FText, FTree, FPlan, FCreated.Edits) then
    begin
      Exit;
    end;
    FCreated.Title := cTexts[TRefactoringsText.CreateMethod].Fmt([FPlan.Name]);
  end
  else if SameText(FSite.Qualifier, 'Self') then
  begin
    Exit;
  end
  else
  begin
    FCreated.Edits := [TCreateMethod.RoutineEdit(FText, ARoutine, FPlan)];
    FCreated.Title := cTexts[TRefactoringsText.CreateRoutine].Fmt([FPlan.Name]);
  end;
  FCreated.Detail := TCreateMethod.Header(FPlan, False);
  Result := True;
end;

function TCreateMethodRun.OwnerType(out AResolved: TResolvedSymbol; out AOwner: TUnitIndex): Boolean;
var
  mOwner: TProbedType;
begin
  // Klasse bzw. Record des Objekts, nur aus dem Projekt und nicht generisch.
  AResolved := Default(TResolvedSymbol);
  AOwner := Default(TUnitIndex);
  mOwner := ProbeOf(FSite.Qualifier);
  if (mOwner.Name = '') or mOwner.IsInterface or not (mOwner.IsReference or mOwner.IsRecord) or
    (Pos('<', mOwner.Name) > 0) then
  begin
    Exit(False);
  end;
  AResolved := FResolver.ResolveChain(FTree, FContext.FileName, mOwner.Name.Split(['.']),
    FTokens[FSite.CallStart].Offset);
  Result := AResolved.Found and AResolved.IsType and not AResolved.Builtin and
    FResolver.DeclaringUnit(AResolved, AOwner) and not AOwner.Library_;
end;

function TCreateMethodRun.OtherUnitEdits(const AResolved: TResolvedSymbol; const AOwner: TUnitIndex): Boolean;
var
  mOtherText, mLineBreak, mUnitName: string;
  mOtherTree: TSyntaxTree;
  mClassBody: TSyntaxNode;
  mUses: TArray<string>;
  mEdits: TArray<TTextEdit>;
  mEdit: TTextEdit;
  mFiles: TFileTextEdits;
begin
  // Andere Unit: public, damit der Aufruf übersetzt; fehlende Units der Parametertypen ins uses.
  Result := False;
  if not (Assigned(FContext.ReadText) and FContext.ReadText(AOwner.FileName, mOtherText)) then
  begin
    Exit;
  end;
  FPlan.Section := 'public';
  FPlan.CaretInBody := False;
  mUses := AOwner.InterfaceUses;
  mOtherTree := TSyntaxTreeCache.Parse(mOtherText);
  try
    if not TCreateMethod.MethodEdits(mOtherText, mOtherTree, FPlan, mEdits) then
    begin
      Exit;
    end;
    mLineBreak := TTextLines.LineBreakOf(mOtherText);
    mClassBody := TRoutineBody.TypeBody(mOtherTree.Root, AResolved.Name);
    for mUnitName in FUnits do
    begin
      if not SameText(mUnitName, AOwner.UnitName) and not TUsesClauses.IsUsed(mUses, mUnitName,
        FContext.Namespaces) and TUsesClauses.AddUnit(mOtherTree.Tokens, mClassBody.StartOffset, mUnitName,
        mLineBreak, mEdit) then
      begin
        mEdits := mEdits + [mEdit];
        mUses := mUses + [mUnitName];
      end;
    end;
  finally
    mOtherTree.Free;
  end;
  mFiles := Default(TFileTextEdits);
  mFiles.FileName := AOwner.FileName;
  mFiles.Edits := mEdits;
  FCreated.FileEdits := [mFiles];
  Result := True;
end;

function TCreateMethodRun.QualifiedTarget: Boolean;
var
  mResolved: TResolvedSymbol;
  mOwner: TUnitIndex;
begin
  Result := False;
  if not OwnerType(mResolved, mOwner) then
  begin
    Exit;
  end;
  FPlan.TypeName := mResolved.Name;
  if (mResolved.Container <> '') and (Pos('.', FPlan.TypeName) = 0) then
  begin
    FPlan.TypeName := mResolved.Container + '.' + FPlan.TypeName;
  end;
  FCreated.Title := cTexts[TRefactoringsText.CreateMethodIn].Fmt([FPlan.Name, FPlan.TypeName]);
  if SameText(mOwner.FileName, FContext.FileName) then
  begin
    Result := TCreateMethod.MethodEdits(FText, FTree, FPlan, FCreated.Edits);
  end
  else
  begin
    Result := OtherUnitEdits(mResolved, mOwner);
  end;
  if Result then
  begin
    FCreated.Detail := TCreateMethod.Header(FPlan, False);
  end;
end;

function TCreateMethodRun.Run(const APosition: TTextPosition): Boolean;
var
  mRoutine: TSyntaxNode;
begin
  Result := False;
  if not TCreateMethod.Site(FTokens, APosition, FSite) then
  begin
    Exit;
  end;
  mRoutine := TRoutineBody.RoutineAt(FTree, FTokens[FSite.NameIndex].Offset);
  if (mRoutine = nil) or FResolver.Resolve(FTree, FContext.FileName, FSite.NameRange.StartPos).Found then
  begin
    Exit;
  end;
  FPlan := Default(TCreateMethodPlan);
  FPlan.Name := FSite.Name;
  FPlan.Style := FContext.Style;
  FPlan.Section := FContext.Settings.CreateMethodSection;
  FPlan.CaretInBody := FContext.CaretMarker and FContext.Settings.CreateMethodCaretInBody;
  AddParameters;
  FPlan.ResultType := ResultType;
  if (FSite.Qualifier = '') or SameText(FSite.Qualifier, 'Self') then
  begin
    Result := LocalTarget(mRoutine);
  end
  else
  begin
    Result := QualifiedTarget;
  end;
end;

class function TLspRefactorings.CreateMethod(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext; out ACreated: TCreatedMethod): Boolean;
var
  mRun: TCreateMethodRun;
begin
  ACreated := Default(TCreatedMethod);
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit(False);
  end;
  mRun := TCreateMethodRun.Create(AResolver, ATree, AText, AContext);
  try
    Result := mRun.Run(APosition);
    ACreated := mRun.Created;
  finally
    mRun.Free;
  end;
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
      begin
        Exit;
      end;
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
  begin
    Parameters := Header.FindChild(TSyntaxKind.Parameters);
  end;
  if Parameters <> nil then
  begin
    for Index := 0 to Parameters.ChildCount - 1 do
    begin
      Names := Length(Parameters[Index].Name.Split([',']));
      Inc(Total, Names);
      if Parameters[Index].ChildCount < 2 then
      begin
        Inc(Required, Names);
      end;
    end;
  end;
  Result := (ACount >= Required) and (ACount <= Total);
end;

/// <summary>Gerufene Routine an ACall, wenn sie zum Projekt gehört; AName mit Klasse davor.</summary>
function CalleeOf(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string; const ACall: TInlineCall;
  out AOwner: TUnitIndex; out AName: string): Boolean;
var
  mResolved: TResolvedSymbol;
begin
  AName := '';
  mResolved := AResolver.Resolve(ATree, AFileName, ACall.NamePos);
  Result := mResolved.Found and (mResolved.Kind = TResolvedKind.Symbol) and
    (mResolved.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and
    AResolver.DeclaringUnit(mResolved, AOwner) and not AOwner.Library_;
  if not Result then
  begin
    Exit;
  end;
  AName := mResolved.Name;
  if mResolved.Container <> '' then
  begin
    AName := mResolved.Container + '.' + AName;
  end;
end;

/// <summary>„Methode einbetten“ mit dem einzigen Rumpf AName in ACallee, der zu den Argumenten passt
/// (Überladungen); leer sonst.</summary>
function MethodAction(const ASource, ACallee: TInlineSource; const APosition: TTextPosition;
  const ACall: TInlineCall; const AName: string; const AOptions: TInlineOptions): TArray<TCodeAction>;
var
  mRoutine, mCandidate: TSyntaxNode;
  mCount: Integer;
  mAction: TCodeAction;
begin
  Result := nil;
  mRoutine := nil;
  mCount := 0;
  for mCandidate in TInlineRefactoring.FindRoutines(ACallee.Tree, AName) do
  begin
    if AcceptsArguments(mCandidate, Length(ACall.Arguments)) then
    begin
      mRoutine := mCandidate;
      Inc(mCount);
    end;
  end;
  if (mCount = 1) and TInlineRefactoring.InlineMethod(ASource, APosition, TInlineCallee.Create(ACallee, mRoutine),
    AOptions, mAction) then
  begin
    Result := [mAction];
  end;
end;

class function TLspRefactorings.InlineActions(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext): TArray<TCodeAction>;
var
  mOptions: TInlineOptions;
  mSource: TInlineSource;
  mAction: TCodeAction;
  mCall: TInlineCall;
  mOwner: TUnitIndex;
  mName, mCalleeText: string;
  mCalleeTree: TSyntaxTree;
begin
  Result := nil;
  mOptions := TInlineOptions.Default;
  mOptions.InlineVar := AContext.InlineVar;
  mOptions.Style := AContext.Style;
  mOptions.Lookup := InlineLookup(AResolver);
  mSource := TInlineSource.Create(AContext.FileName, AText, ATree);
  if TInlineRefactoring.InlineVariable(mSource, APosition, mOptions, mAction) then
  begin
    Result := Result + [mAction];
  end;
  if not TInlineRefactoring.CallAt(ATree, AText, APosition, mCall) or
    not CalleeOf(AResolver, ATree, AContext.FileName, mCall, mOwner, mName) then
  begin
    Exit;
  end;
  if SameText(mOwner.FileName, AContext.FileName) then
  begin
    Result := Result + MethodAction(mSource, mSource, APosition, mCall, mName, mOptions);
    Exit;
  end;
  if not (Assigned(AContext.ReadText) and AContext.ReadText(mOwner.FileName, mCalleeText)) then
  begin
    Exit;
  end;
  mCalleeTree := TSyntaxTreeCache.Parse(mCalleeText);
  try
    AResolver.PinTree(mCalleeTree, mOwner.FileName);
    try
      Result := Result + MethodAction(mSource, TInlineSource.Create(mOwner.FileName, mCalleeText, mCalleeTree),
        APosition, mCall, mName, mOptions);
    finally
      AResolver.UnpinTree;
    end;
  finally
    mCalleeTree.Free;
  end;
end;

class function TLspRefactorings.IfCaseActions(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext): TArray<TCodeAction>;
var
  Lookup: TIfCaseLookup;
  Layout: TStatementLayout;
  Conversion: TIfCaseConversion;

  procedure Add;
  var
    Action: TCodeAction;
  begin
    Action := Default(TCodeAction);
    Action.Title := Conversion.Title;
    Action.Kind := RewriteKind;
    Action.Edits := [Conversion.Edit];
    Result := Result + [Action];
  end;

begin
  Result := nil;
  Lookup := TIfCaseLookup.FromResolver(AResolver, ATree, AContext.FileName);
  Layout := TStatementLayout.Create('', TRoutineBody.IndentUnit(AContext.Style), TTextLines.LineBreakOf(AText));
  if TIfCase.ToCase(AText, ATree, APosition, Lookup, Layout, Conversion) then
  begin
    Add;
  end;
  if TIfCase.ToIf(AText, ATree, APosition, Lookup, Layout, Conversion) then
  begin
    Add;
  end;
end;

class function TLspRefactorings.ConditionActions(ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext): TArray<TCodeAction>;
var
  Rewrite: TStatementRewrite;
  Action: TCodeAction;
begin
  Result := nil;
  for Rewrite in TConditions.Actions(AText, ATree, APosition, TStatementLayout.Create('',
    TRoutineBody.IndentUnit(AContext.Style), TTextLines.LineBreakOf(AText))) do
  begin
    Action := Default(TCodeAction);
    Action.Title := Rewrite.Title;
    Action.Kind := RewriteKind;
    Action.Edits := [Rewrite.Edit];
    Result := Result + [Action];
  end;
end;

class function TLspRefactorings.ConditionalExpressionActions(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AText: string; const APosition: TTextPosition; const AContext: TRefactoringContext): TArray<TCodeAction>;
var
  Lookup: TConditionalLookup;
  Rewrite: TStatementRewrite;

  procedure Add;
  var
    Action: TCodeAction;
  begin
    Action := Default(TCodeAction);
    Action.Title := Rewrite.Title;
    Action.Kind := RewriteKind;
    Action.Edits := [Rewrite.Edit];
    Result := Result + [Action];
  end;

begin
  Result := nil;
  Lookup := TConditionalLookup.FromResolver(AResolver, ATree, AContext.FileName);
  if AContext.IfExpression then
  begin
    if TConditionalExpression.ToExpression(AText, ATree, APosition, Lookup, Rewrite) then
    begin
      Add;
    end;
    if TConditionalExpression.ReplaceIfThen(AText, ATree, APosition, Lookup, Rewrite) then
    begin
      Add;
    end;
  end;
  if TConditionalExpression.ToStatement(AText, ATree, APosition, TStatementLayout.Create('',
    TRoutineBody.IndentUnit(AContext.Style), TTextLines.LineBreakOf(AText)), Rewrite) then
  begin
    Add;
  end;
end;

class function TLspRefactorings.NestedRoutineActions(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AText: string; const APosition: TTextPosition; const AContext: TRefactoringContext): TArray<TCodeAction>;
begin
  Result := TNestedRoutines.Actions(AText, ATree, APosition, TNestedRoutineLookup.FromResolver(AResolver, ATree,
    AContext.FileName), AContext.Style);
end;

/// <summary>True, wenn eine eingeschaltete Aktion die Namensauflösung braucht.</summary>
function NeedsResolver(const ASettings: TRefactoringSettings): Boolean;
begin
  Result := ASettings.CompleteCase or ASettings.ResolveWith or ASettings.CreateMethod or ASettings.InlineCode;
  if not Result then
  begin
    Result := ASettings.IfCase or ASettings.ConditionalExpression or ASettings.NestedRoutine;
  end;
end;

/// <summary>Code-Aktion zu „Methode aus Aufruf anlegen“.</summary>
function CreatedAction(const ACreated: TCreatedMethod): TCodeAction;
begin
  Result := Default(TCodeAction);
  Result.Title := ACreated.Title;
  Result.Kind := QuickFixKind;
  Result.Edits := ACreated.Edits;
  Result.FileEdits := ACreated.FileEdits;
end;

/// <summary>case vervollständigen, with auflösen und Methode anlegen über AResolver.</summary>
function QuickActions(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext): TArray<TCodeAction>;
var
  mAction: TCodeAction;
  mCreated: TCreatedMethod;
begin
  Result := nil;
  if AContext.Settings.CompleteCase and TLspRefactorings.CaseAction(AResolver, ATree, AText, APosition, AContext,
    mAction) then
  begin
    Result := Result + [mAction];
  end;
  if AContext.Settings.ResolveWith and TLspRefactorings.WithAction(AResolver, ATree, AText, APosition, AContext,
    mAction) then
  begin
    Result := Result + [mAction];
  end;
  if AContext.Settings.CreateMethod and TLspRefactorings.CreateMethod(AResolver, ATree, AText, APosition, AContext,
    mCreated) then
  begin
    Result := Result + [CreatedAction(mCreated)];
  end;
end;

/// <summary>Umformungen über AResolver: einbetten, if/case, Bedingungsausdruck, lokale Routinen.</summary>
function ResolvedRewrites(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext): TArray<TCodeAction>;
begin
  Result := nil;
  if AContext.Settings.InlineCode then
  begin
    Result := Result + TLspRefactorings.InlineActions(AResolver, ATree, AText, APosition, AContext);
  end;
  if AContext.Settings.IfCase then
  begin
    Result := Result + TLspRefactorings.IfCaseActions(AResolver, ATree, AText, APosition, AContext);
  end;
  if AContext.Settings.ConditionalExpression then
  begin
    Result := Result + TLspRefactorings.ConditionalExpressionActions(AResolver, ATree, AText, APosition, AContext);
  end;
  if AContext.Settings.NestedRoutine then
  begin
    Result := Result + TLspRefactorings.NestedRoutineActions(AResolver, ATree, AText, APosition, AContext);
  end;
end;

class function TLspRefactorings.Actions(ATree: TSyntaxTree; const AText: string; const ARange: TTextRange;
  const AContext: TRefactoringContext): TArray<TCodeAction>;
var
  mResolver: TNameResolver;
  mContext: TRefactoringContext;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  if AContext.Settings.Extract then
  begin
    Result := Result + TExtractRefactoring.Actions(AText, ATree, ARange, OptionsOf(AContext));
  end;
  if AContext.Settings.Conditions then
  begin
    Result := Result + ConditionActions(ATree, AText, ARange.StartPos, AContext);
  end;
  if not NeedsResolver(AContext.Settings) then
  begin
    Exit;
  end;
  // Code-Aktionen setzen keine Schreibmarke in den Rumpf.
  mContext := AContext;
  mContext.CaretMarker := False;
  mResolver := NewResolver(mContext);
  try
    mResolver.PinTree(ATree, mContext.FileName);
    try
      Result := Result + QuickActions(mResolver, ATree, AText, ARange.StartPos, mContext) +
        ResolvedRewrites(mResolver, ATree, AText, ARange.StartPos, mContext);
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
end;


initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Refactorings', cTexts);

end.
