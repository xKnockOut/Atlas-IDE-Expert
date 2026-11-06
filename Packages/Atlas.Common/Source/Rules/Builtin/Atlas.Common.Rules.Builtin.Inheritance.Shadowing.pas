unit Atlas.Common.Rules.Builtin.Inheritance.Shadowing;

// Regel shadowed-name aus Atlas.Common.Rules.Builtin.Inheritance (#934): Parameter oder lokale Variable heißt
// wie ein Feld, eine Property (auch geerbt) oder eine globale Variable der Unit.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TShadowedNameRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Unused.Shared,
  Atlas.Common.Rules.Builtin.Naming,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Index.LibraryUnits,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInheritanceShadowingText = (Title, ReadSuffix, RenameTo, LocalVariable, ParameterWhat, AssignedLocal,
    AssignedParameter, Hides, PropertyOf, FieldOf, GlobalVariable);

const
  cTexts: array[TInheritanceShadowingText] of TAtlasText = (
    (De: 'Lokaler Name verdeckt Feld, Property oder globale Variable';
     En: 'Local name hides field, property or global variable'),
    (De: '; gelesen wird die lokale Variable, der nichts zugewiesen wird.';
     En: '; the local variable is read, but nothing is assigned to it.'),
    (De: 'In %s umbenennen'; En: 'Rename to %s'),
    (De: 'Lokale Variable'; En: 'Local variable'),
    (De: 'Parameter'; En: 'Parameter'),
    (De: '; die Zuweisung ändert nur die lokale Variable.'; En: '; the assignment only changes the local variable.'),
    (De: '; die Zuweisung ändert nur den Parameter.'; En: '; the assignment only changes the parameter.'),
    (De: '%s %s verdeckt %s'; En: '%s %s hides %s'),
    (De: 'die Property %s.%s'; En: 'the property %s.%s'),
    (De: 'das Feld %s.%s'; En: 'the field %s.%s'),
    (De: 'die globale Variable %s'; En: 'the global variable %s'));

{$SCOPEDENUMS OFF}

{ TShadowedNameRule }

const
  ShadowDefaultIgnore: array[0..1] of string = ('Sender', 'Value');
  // Ohne VCL im Index: Mitglieder von TComponent bzw. TControl, wenn die Kette an einer dieser Klassen abbricht.
  ComponentClasses: array[0..1] of string = ('TComponent', 'TDataModule');
  ComponentMembers: array[0..5] of string = ('Name', 'Tag', 'Owner', 'ComponentCount', 'ComponentIndex',
    'Components');
  ControlClasses: array[0..14] of string = ('TControl', 'TWinControl', 'TCustomControl', 'TGraphicControl', 'TForm',
    'TCustomForm', 'TFrame', 'TCustomFrame', 'TScrollingWinControl', 'TPanel', 'TCustomPanel', 'TScrollBox',
    'TPageControl', 'TTabSheet', 'TGroupBox');
  ControlMembers: array[0..20] of string = ('Left', 'Top', 'Width', 'Height', 'Caption', 'Text', 'Hint', 'Visible',
    'Enabled', 'Color', 'Font', 'Parent', 'Align', 'Anchors', 'Cursor', 'ShowHint', 'PopupMenu', 'ClientWidth',
    'ClientHeight', 'Action', 'Constraints');

type
  /// <summary>Ein Parameter einer Routine mit dem Knoten, der ihn deklariert.</summary>
  TParamEntry = record
    Name: string;
    Node: TSyntaxNode;
  end;

  /// <summary>Ein zu prüfender lokaler Name: Parameter, lokale Variable oder Inline-Variable.</summary>
  TShadowCandidate = record
    Routine: TSyntaxNode;
    /// <summary>Knoten der Deklaration (Parameter, VarDecl, InlineVar).</summary>
    Declaration: TSyntaxNode;
    ClassName: string;
    Name: string;
    IsParameter: Boolean;
    /// <summary>Stelle des Parameters in der Liste; -1 bei lokalen Variablen.</summary>
    ParamIndex: Integer;
  end;

  /// <summary>Das verdeckte Mitglied bzw. die verdeckte globale Variable.</summary>
  TShadowHit = record
    /// <summary>Beschreibung für die Meldung, z. B. "das Feld TFoo.FWert".</summary>
    Kind: string;
    /// <summary>Geerbt aus RTL, VCL oder einer anderen Bibliothek.</summary>
    Framework: Boolean;
  end;

  /// <summary>Wie oft ein Name in der Routine geschrieben, gelesen oder unklar verwendet wird.</summary>
  TNameUsage = record
    Reads: Integer;
    Writes: Integer;
    Unclear: Integer;
  end;

  /// <summary>Prüfung einer Unit für shadowed-name.</summary>
  TShadowCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FAncestry: TAncestry;
    FIgnore: TArray<string>;
    FTokens: TArray<TPascalToken>;
    FFrameworkMembers: Boolean;
    /// <summary>Globale Variablen der Unit (Name klein) mit ihrer frühesten Zeile; nil, bis zuerst gefragt.</summary>
    FGlobals: TDictionary<string, Integer>;
    function Significant(AIndex, AStep: Integer): Integer;
    function NameTokens(ANode: TSyntaxNode; const AName: string): TArray<Integer>;
    function TokenRange(AIndex: Integer): TTextRange;
    function IsSymbolIn(AIndex: Integer; const ASymbols: array of string): Boolean;
    function DeclarationHeader(const ACandidate: TShadowCandidate): TSyntaxNode;
    function GlobalVariable(ARoutine: TSyntaxNode; const AName: string): Boolean;
    function InlineInitWrites(ADeclaration: TSyntaxNode): Integer;
    function UsageOf(const ACandidate: TShadowCandidate): TNameUsage;
    function IsClassMethod(ARoutine: TSyntaxNode): Boolean;
    function Ignored(const AName: string): Boolean;
    function MemberHit(const ACandidate: TShadowCandidate; out AHit: TShadowHit): Boolean;
    function FindShadowed(const ACandidate: TShadowCandidate; out AHit: TShadowHit): Boolean;
    function FrameworkSuffix(const ACandidate: TShadowCandidate; out ASuffix: string): Boolean;
    function RenameFixes(const ACandidate: TShadowCandidate; AHeader: TSyntaxNode): TArray<TRuleFix>;
    procedure CheckName(const ACandidate: TShadowCandidate);
    procedure CheckParameters(ARoutine: TSyntaxNode; const AClassName: string);
    procedure CheckVarSection(ARoutine, ASection: TSyntaxNode; const AClassName: string);
    procedure CheckInline(ARoutine, ARoot: TSyntaxNode; const AClassName: string);
    procedure CheckRoutine(ARoutine: TSyntaxNode; const AClassName: string);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

function SplitNames(const ANames: string): TArray<string>;
var
  Name: string;
begin
  Result := nil;
  for Name in SplitString(ANames, ',') do
  begin
    if Trim(Name) <> '' then
    begin
      Result := Result + [Trim(Name)];
    end;
  end;
end;

/// <summary>Alle Parameter des Routinenkopfs AHeader (nil: keine), in ihrer Reihenfolge.</summary>
function ParamEntries(AHeader: TSyntaxNode): TArray<TParamEntry>;
var
  Params: TSyntaxNode;
  Index: Integer;
  Name: string;
  Entry: TParamEntry;
begin
  Result := nil;
  Params := nil;
  if AHeader <> nil then
  begin
    Params := AHeader.FindChild(TSyntaxKind.Parameters);
  end;
  if Params = nil then
  begin
    Exit;
  end;
  for Index := 0 to Params.ChildCount - 1 do
  begin
    if Params[Index].Kind <> TSyntaxKind.Parameter then
    begin
      Continue;
    end;
    Entry.Node := Params[Index];
    for Name in SplitNames(Params[Index].Name) do
    begin
      Entry.Name := Name;
      Result := Result + [Entry];
    end;
  end;
end;

/// <summary>Zuweisung "AName := …" irgendwo unter ANode.</summary>
function Assigned_(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while not Result and (Pending.Count > 0) do
    begin
      Node := Pending.Pop;
      Result := (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
        (Node[0].Kind = TSyntaxKind.Identifier) and SameText(Node[0].Name, AName);
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Kopf ARoutineHeader hat an Stelle AParamIndex den Parameter AParam.</summary>
function HasParamAt(AHeader: TSyntaxNode; const AParam: string; AParamIndex: Integer): Boolean;
var
  Entries: TArray<TParamEntry>;
begin
  Entries := ParamEntries(AHeader);
  Result := (AParamIndex >= 0) and (AParamIndex <= High(Entries)) and SameText(Entries[AParamIndex].Name, AParam);
end;

/// <summary>Legt die Kinder von ANode rückwärts auf die Stapel, jeweils mit AInClass.</summary>
procedure PushChildren(APending: TStack<TSyntaxNode>; APendingInClass: TStack<Boolean>; ANode: TSyntaxNode;
  AInClass: Boolean);
var
  Index: Integer;
begin
  for Index := ANode.ChildCount - 1 downto 0 do
  begin
    APending.Push(ANode[Index]);
    APendingInClass.Push(AInClass);
  end;
end;

/// <summary>Deklaration der Methode AMethod in der Klasse AClassName unter ARoot: Kopf mit gleichem Namen und dem
/// Parameter AParam an der Stelle AParamIndex; nil ohne.</summary>
function FindDeclarationHeader(ARoot: TSyntaxNode; const AClassName, AMethod, AParam: string;
  AParamIndex: Integer): TSyntaxNode;
var
  Node: TSyntaxNode;
  InClass, IsHeader: Boolean;
  Pending: TStack<TSyntaxNode>;
  PendingInClass: TStack<Boolean>;
begin
  // Iterativ (Bericht M1): zu jedem Knoten auf dem Stapel, ob er in der Klasse AClassName liegt.
  Result := nil;
  Pending := TStack<TSyntaxNode>.Create;
  PendingInClass := TStack<Boolean>.Create;
  try
    Pending.Push(ARoot);
    PendingInClass.Push(False);
    while (Result = nil) and (Pending.Count > 0) do
    begin
      Node := Pending.Pop;
      InClass := PendingInClass.Pop;
      if Node.Kind = TSyntaxKind.TypeDecl then
      begin
        InClass := SameText(Node.Name, AClassName);
      end;
      IsHeader := InClass and (Node.Kind = TSyntaxKind.RoutineHeader) and SameText(Node.Name, AMethod);
      if IsHeader and HasParamAt(Node, AParam, AParamIndex) then
      begin
        Result := Node;
      end;
      if not IsHeader and not (Node.Kind in [TSyntaxKind.ImplementationSection, TSyntaxKind.RoutineDecl]) then
      begin
        PushChildren(Pending, PendingInClass, Node, InClass);
      end;
    end;
  finally
    PendingInClass.Free;
    Pending.Free;
  end;
end;

function HasDirective(AHeader: TSyntaxNode; const ANames: array of string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if AHeader = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and MatchText(AHeader[mIndex].Name, ANames) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>override und message: Die Signatur gibt der Vorfahr bzw. die Botschaft vor, z. B.
/// DoClose(var Action: TCloseAction).</summary>
function SignatureFixed(ARoutine, AHeader: TSyntaxNode): Boolean;
begin
  Result := HasDirective(AHeader, ['override', 'message']) or
    HasDirective(ARoutine.FindChild(TSyntaxKind.RoutineHeader), ['override', 'message']);
end;

/// <summary>Ohne VCL im Index: AName ist ein Mitglied von TComponent bzw. TControl, an dessen Klasse AUnresolved die
/// Kette abbricht. Diese Mitglieder gehören alle zur Instanz.</summary>
function FrameworkMember(const AUnresolved, AName: string): Boolean;
begin
  Result := (MatchText(AUnresolved, ComponentClasses) or MatchText(AUnresolved, ControlClasses)) and
    MatchText(AName, ComponentMembers);
  Result := Result or (MatchText(AUnresolved, ControlClasses) and MatchText(AName, ControlMembers));
end;

/// <summary>Klasse der Methode ARoutine ("TFoo.Bar" → "TFoo"), sonst AClassName der umgebenden Methode.</summary>
function OwnerClassName(ARoutine: TSyntaxNode; const AClassName: string): string;
begin
  Result := AClassName;
  if (Result = '') and (Pos('.', ARoutine.Name) > 0) then
  begin
    Result := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

/// <summary>Meldungstext: was verdeckt wird, und ob eine Zuweisung nur den lokalen Namen ändert.</summary>
function ShadowMessage(const ACandidate: TShadowCandidate; const AKind, ASuffix: string): string;
const
  cWhat: array[Boolean] of TInheritanceShadowingText = (TInheritanceShadowingText.LocalVariable,
    TInheritanceShadowingText.ParameterWhat);
  cAssigned: array[Boolean] of TInheritanceShadowingText = (TInheritanceShadowingText.AssignedLocal,
    TInheritanceShadowingText.AssignedParameter);
begin
  Result := cTexts[TInheritanceShadowingText.Hides].Fmt([cTexts[cWhat[ACandidate.IsParameter]].Text, ACandidate.Name,
    AKind]);
  if ASuffix <> '' then
  begin
    Result := Result + ASuffix;
  end
  else if Assigned_(ACandidate.Routine, ACandidate.Name) then
  begin
    Result := Result + cTexts[cAssigned[ACandidate.IsParameter]].Text;
  end
  else
  begin
    Result := Result + '.';
  end;
end;

function TShadowedNameRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('shadowed-name', TRuleSeverity.Hint,
    cTexts[TInheritanceShadowingText.Title].Text);
end;

procedure TShadowedNameRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TShadowCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Check := TShadowCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

{ TShadowCheck }

constructor TShadowCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Defaults: TArray<string>;
  Name: string;
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  Defaults := nil;
  for Name in ShadowDefaultIgnore do
  begin
    Defaults := Defaults + [Name];
  end;
  FIgnore := TRuleOptions.Strings(AContext.Options, 'ignore', Defaults);
  FFrameworkMembers := TRuleOptions.Bool(AContext.Options, 'frameworkMembers', False);
  FTokens := AContext.Tree.Tokens;
  FCache := TRuleDerived.Open(AContext);
  FAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(FCache, AContext));
end;

destructor TShadowCheck.Destroy;
begin
  FGlobals.Free;
  FAncestry.Free;
  inherited Destroy;
end;

/// <summary>Nächstes bzw. voriges Token ohne Kommentare und Direktiven; -1 ohne.</summary>
function TShadowCheck.Significant(AIndex, AStep: Integer): Integer;
begin
  Result := AIndex + AStep;
  while (Result >= 0) and (Result <= High(FTokens)) and
    (FTokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Inc(Result, AStep);
  end;
  if (Result < 0) or (Result > High(FTokens)) then
  begin
    Result := -1;
  end;
end;

/// <summary>Bezeichner-Token AName in ANode, die nicht hinter einem Punkt stehen (Self.Caption bleibt).</summary>
function TShadowCheck.NameTokens(ANode: TSyntaxNode; const AName: string): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  Index := TSyntaxTree.FirstTokenOf(FTokens, ANode.StartOffset);
  while (Index <= High(FTokens)) and (FTokens[Index].Offset < ANode.EndOffset) do
  begin
    if (FTokens[Index].Offset >= ANode.StartOffset) and (FTokens[Index].Kind in [TPascalTokenKind.Identifier,
      TPascalTokenKind.Keyword]) and SameText(FTokens[Index].Text, AName) and not IsSymbolIn(Significant(Index, -1),
      ['.']) then
    begin
      Result := Result + [Index];
    end;
    Inc(Index);
  end;
end;

function TShadowCheck.TokenRange(AIndex: Integer): TTextRange;
begin
  Result := TTextRange.Create(FTokens[AIndex].StartPos, FTokens[AIndex].EndPos);
end;

/// <summary>Das Token AIndex (-1: keins) ist eines der Symbole ASymbols.</summary>
function TShadowCheck.IsSymbolIn(AIndex: Integer; const ASymbols: array of string): Boolean;
var
  Symbol: string;
begin
  Result := False;
  if AIndex < 0 then
  begin
    Exit;
  end;
  for Symbol in ASymbols do
  begin
    Result := Result or FTokens[AIndex].IsSymbol(Symbol);
  end;
end;

/// <summary>Deklaration der Methode in der Klasse für einen Parameter; nil für lokale Variablen und Routinen
/// außerhalb einer Klasse.</summary>
function TShadowCheck.DeclarationHeader(const ACandidate: TShadowCandidate): TSyntaxNode;
begin
  Result := nil;
  if ACandidate.IsParameter and (ACandidate.ClassName <> '') then
  begin
    Result := FindDeclarationHeader(FContext.Tree.Root, ACandidate.ClassName, Copy(ACandidate.Routine.Name,
      LastDelimiter('.', ACandidate.Routine.Name) + 1, MaxInt), ACandidate.Name, ACandidate.ParamIndex);
  end;
end;

/// <summary>Globale Variable der Unit vor ARoutine. Die Variablen sammelt der erste Aufruf einmal: Vorher lief
/// jeder geprüfte Name über alle Symbole der Unit, quadratisch in ihrer Länge.</summary>
function TShadowCheck.GlobalVariable(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mSymbol: TIndexSymbol;
  mLine: Integer;
  mKey: string;
begin
  if FGlobals = nil then
  begin
    FGlobals := TDictionary<string, Integer>.Create;
    for mSymbol in FAncestry.Local.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.Variable) and (mSymbol.Container = '') then
      begin
        mKey := LowerCase(mSymbol.Name);
        if not FGlobals.TryGetValue(mKey, mLine) or (mSymbol.Range.StartPos.Line < mLine) then
        begin
          FGlobals.AddOrSetValue(mKey, mSymbol.Range.StartPos.Line);
        end;
      end;
    end;
  end;
  Result := FGlobals.TryGetValue(LowerCase(AName), mLine) and (mLine < ARoutine.StartPos.Line);
end;

/// <summary>1, wenn die Inline-Variable ADeclaration vorbelegt wird (var X := …), sonst 0.</summary>
function TShadowCheck.InlineInitWrites(ADeclaration: TSyntaxNode): Integer;
var
  Index: Integer;
begin
  Result := 0;
  if ADeclaration.Kind <> TSyntaxKind.InlineVar then
  begin
    Exit;
  end;
  Index := TSyntaxTree.FirstTokenOf(FTokens, ADeclaration.StartOffset);
  while (Result = 0) and (Index <= High(FTokens)) and (FTokens[Index].Offset < ADeclaration.EndOffset) do
  begin
    if FTokens[Index].IsSymbol(':=') then
    begin
      Result := 1;
    end;
    Inc(Index);
  end;
end;

/// <summary>Verwendung des Namens in der Routine außerhalb seiner Deklaration: Writes zählt Zuweisungen
/// (X := …, for X in …, auch die Vorbelegung einer Inline-Variable), Reads reine Lesezugriffe, Unclear alles, was
/// beides sein kann (Argument eines Aufrufs, @X, X.Feld, X[I]).</summary>
function TShadowCheck.UsageOf(const ACandidate: TShadowCandidate): TNameUsage;
var
  Index, Next, Previous: Integer;
begin
  Result := Default(TNameUsage);
  Result.Writes := InlineInitWrites(ACandidate.Declaration);
  for Index in NameTokens(ACandidate.Routine, ACandidate.Name) do
  begin
    if (FTokens[Index].Offset >= ACandidate.Declaration.StartOffset) and
      (FTokens[Index].Offset < ACandidate.Declaration.EndOffset) then
    begin
      Continue;
    end;
    Next := Significant(Index, 1);
    Previous := Significant(Index, -1);
    if IsSymbolIn(Next, [':=']) or ((Previous >= 0) and FTokens[Previous].IsKeyword('for')) then
    begin
      Inc(Result.Writes);
    end
    else if IsSymbolIn(Next, ['.', '[', '^']) or IsSymbolIn(Previous, ['(', ',', '@']) then
    begin
      Inc(Result.Unclear);
    end
    else
    begin
      Inc(Result.Reads);
    end;
  end;
end;

/// <summary>class procedure/function: Felder und Properties der Instanz sind dort nicht erreichbar.</summary>
function TShadowCheck.IsClassMethod(ARoutine: TSyntaxNode): Boolean;
var
  mHeader: TSyntaxNode;
  mIndex: Integer;
begin
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  Result := False;
  if mHeader <> nil then
  begin
    mIndex := TSyntaxTree.FirstTokenOf(FTokens, mHeader.StartOffset);
    Result := (mIndex >= 0) and (mIndex <= High(FTokens)) and FTokens[mIndex].IsKeyword('class');
  end;
end;

function TShadowCheck.Ignored(const AName: string): Boolean;
var
  Pattern: string;
begin
  Result := False;
  for Pattern in FIgnore do
  begin
    Result := Result or MatchesWildcard(AName, Pattern);
  end;
end;

/// <summary>Feld oder Property der Klasse (auch geerbt) mit dem Namen des Kandidaten. In class-Methoden zählen nur
/// class var und class property.</summary>
function TShadowCheck.MemberHit(const ACandidate: TShadowCandidate; out AHit: TShadowHit): Boolean;
const
  cKind: array[Boolean] of TInheritanceShadowingText = (TInheritanceShadowingText.PropertyOf,
    TInheritanceShadowingText.FieldOf);
var
  Member: TIndexSymbol;
  Unresolved, mUnitName: string;
  mClassMethod: Boolean;
begin
  AHit := Default(TShadowHit);
  mClassMethod := IsClassMethod(ACandidate.Routine);
  if FAncestry.FindMember(ACandidate.ClassName, ACandidate.Name, Member, Unresolved, mUnitName) then
  begin
    AHit.Framework := (mUnitName <> '') and TLibraryUnits.IsLibrary(FContext.Index, mUnitName);
    AHit.Kind := cTexts[cKind[Member.Kind = TIndexSymbolKind.Field]].Fmt([ACandidate.ClassName, Member.Name]);
    Exit(not mClassMethod or MatchText('class', Member.Directives));
  end;
  Result := not mClassMethod and FrameworkMember(Unresolved, ACandidate.Name);
  AHit.Framework := True;
  AHit.Kind := cTexts[TInheritanceShadowingText.PropertyOf].Fmt([ACandidate.ClassName, ACandidate.Name]);
end;

/// <summary>Was der Kandidat verdeckt: Mitglied der Klasse oder globale Variable der Unit.</summary>
function TShadowCheck.FindShadowed(const ACandidate: TShadowCandidate; out AHit: TShadowHit): Boolean;
begin
  Result := (ACandidate.ClassName <> '') and MemberHit(ACandidate, AHit);
  if not Result and GlobalVariable(ACandidate.Routine, ACandidate.Name) then
  begin
    Result := True;
    AHit.Framework := False;
    AHit.Kind := cTexts[TInheritanceShadowingText.GlobalVariable].Fmt([ACandidate.Name]);
  end;
end;

/// <summary>Geerbt aus RTL, VCL oder einer anderen Bibliothek: Left, Text oder Name als Hilfsvariable sind dort
/// üblich. Gemeldet wird nur, wo das Mitglied gemeint sein könnte: eine lokale Variable, die nur zugewiesen oder
/// nur gelesen wird, ein Werteparameter, dem etwas zugewiesen wird. False: nicht melden.</summary>
function TShadowCheck.FrameworkSuffix(const ACandidate: TShadowCandidate; out ASuffix: string): Boolean;
var
  Usage: TNameUsage;
begin
  ASuffix := '';
  Usage := UsageOf(ACandidate);
  if ACandidate.IsParameter then
  begin
    Exit(not (ACandidate.Declaration.Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam]) and
      (Usage.Writes <> 0));
  end;
  Result := Usage.Unclear = 0;
  if Result and (Usage.Reads > 0) and (Usage.Writes = 0) then
  begin
    ASuffix := cTexts[TInheritanceShadowingText.ReadSuffix].Text;
  end
  else
  begin
    Result := Result and (Usage.Reads = 0) and (Usage.Writes <> 0);
  end;
end;

/// <summary>Umbenennen: AName für Parameter, LName für lokale Variablen, mit den Präfixen der Projektdatei .atlas
/// (#1111, z. B. mName); alle Vorkommen in der Routine und im Kopf der Deklaration AHeader.</summary>
function TShadowCheck.RenameFixes(const ACandidate: TShadowCandidate; AHeader: TSyntaxNode): TArray<TRuleFix>;
var
  NewName: string;
  Edits: TArray<TRuleEdit>;
  Index: Integer;
begin
  Result := nil;
  if ACandidate.IsParameter then
  begin
    NewName := TNamingConvention.Expected(ACandidate.Name, NamingPrefixFor(FContext, TRuleNamingKind.Parameter, 'A'));
  end
  else
  begin
    NewName := TNamingConvention.Expected(ACandidate.Name, NamingPrefixFor(FContext, TRuleNamingKind.Local, 'L'));
  end;
  if (NameTokens(ACandidate.Routine, NewName) <> nil) or ((AHeader <> nil) and (NameTokens(AHeader, NewName) <> nil))
    then
  begin
    Exit;
  end;
  Edits := nil;
  for Index in NameTokens(ACandidate.Routine, ACandidate.Name) do
  begin
    Edits := Edits + [TRuleEdit.Create(TokenRange(Index), NewName)];
  end;
  if AHeader <> nil then
  begin
    for Index in NameTokens(AHeader, ACandidate.Name) do
    begin
      Edits := Edits + [TRuleEdit.Create(TokenRange(Index), NewName)];
    end;
  end;
  Result := [TRuleFix.Create(cTexts[TInheritanceShadowingText.RenameTo].Fmt([NewName]), Edits)];
end;

procedure TShadowCheck.CheckName(const ACandidate: TShadowCandidate);
var
  Hit: TShadowHit;
  Header: TSyntaxNode;
  Suffix: string;
  Positions: TArray<Integer>;
begin
  if Ignored(ACandidate.Name) or not FindShadowed(ACandidate, Hit) then
  begin
    Exit;
  end;
  Header := DeclarationHeader(ACandidate);
  Suffix := '';
  if ACandidate.IsParameter and SignatureFixed(ACandidate.Routine, Header) then
  begin
    Exit;
  end;
  if Hit.Framework and not FFrameworkMembers and not FrameworkSuffix(ACandidate, Suffix) then
  begin
    Exit;
  end;
  Positions := NameTokens(ACandidate.Declaration, ACandidate.Name);
  if Positions <> nil then
  begin
    FReport.Add(TokenRange(Positions[0]), ShadowMessage(ACandidate, Hit.Kind, Suffix), TRuleConfidence.High,
      RenameFixes(ACandidate, Header));
  end;
end;

/// <summary>Parameter der Routine; Ereignis-Handler (mit Sender) bleiben, ihre Signatur gibt der Ereignistyp vor,
/// z. B. FormClose(…; var Action).</summary>
procedure TShadowCheck.CheckParameters(ARoutine: TSyntaxNode; const AClassName: string);
var
  Entries: TArray<TParamEntry>;
  Entry: TParamEntry;
  Candidate: TShadowCandidate;
  Position: Integer;
begin
  Entries := ParamEntries(ARoutine.FindChild(TSyntaxKind.RoutineHeader));
  for Entry in Entries do
  begin
    if SameText(Entry.Name, 'Sender') then
    begin
      Exit;
    end;
  end;
  Candidate := Default(TShadowCandidate);
  Candidate.Routine := ARoutine;
  Candidate.ClassName := AClassName;
  Candidate.IsParameter := True;
  for Position := 0 to High(Entries) do
  begin
    Candidate.Name := Entries[Position].Name;
    Candidate.Declaration := Entries[Position].Node;
    Candidate.ParamIndex := Position;
    CheckName(Candidate);
  end;
end;

/// <summary>Variablen des var-Abschnitts ASection der Routine.</summary>
procedure TShadowCheck.CheckVarSection(ARoutine, ASection: TSyntaxNode; const AClassName: string);
var
  Inner: Integer;
  Name: string;
  Candidate: TShadowCandidate;
begin
  Candidate := Default(TShadowCandidate);
  Candidate.Routine := ARoutine;
  Candidate.ClassName := AClassName;
  Candidate.ParamIndex := -1;
  for Inner := 0 to ASection.ChildCount - 1 do
  begin
    if ASection[Inner].Kind <> TSyntaxKind.VarDecl then
    begin
      Continue;
    end;
    Candidate.Declaration := ASection[Inner];
    for Name in SplitNames(ASection[Inner].Name) do
    begin
      Candidate.Name := Name;
      CheckName(Candidate);
    end;
  end;
end;

/// <summary>Inline-Variablen im Rumpf ARoot, ohne verschachtelte Routinen und anonyme Methoden.</summary>
procedure TShadowCheck.CheckInline(ARoutine, ARoot: TSyntaxNode; const AClassName: string);
var
  Item: Integer;
  Name: string;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
  Candidate: TShadowCandidate;
begin
  Candidate := Default(TShadowCandidate);
  Candidate.Routine := ARoutine;
  Candidate.ClassName := AClassName;
  Candidate.ParamIndex := -1;
  // Iterativ (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      Candidate.Declaration := Node;
      if Node.Kind = TSyntaxKind.InlineVar then
      begin
        for Name in SplitNames(Node.Name) do
        begin
          Candidate.Name := Name;
          CheckName(Candidate);
        end;
      end;
      if not (Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      begin
        for Item := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Item]);
        end;
      end;
    end;
  finally
    Pending.Free;
  end;
end;

procedure TShadowCheck.CheckRoutine(ARoutine: TSyntaxNode; const AClassName: string);
var
  Index: Integer;
  Child: TSyntaxNode;
  ClassName: string;
begin
  ClassName := OwnerClassName(ARoutine, AClassName);
  CheckParameters(ARoutine, ClassName);
  for Index := 0 to ARoutine.ChildCount - 1 do
  begin
    Child := ARoutine[Index];
    if Child.Kind = TSyntaxKind.VarSection then
    begin
      CheckVarSection(ARoutine, Child, ClassName);
    end
    else if Child.Kind = TSyntaxKind.Block then
    begin
      CheckInline(ARoutine, Child, ClassName);
    end
    else if Child.Kind = TSyntaxKind.RoutineDecl then
    begin
      // Die Rekursion bleibt (Bericht M1): sie geht nur über verschachtelte Routinendeklarationen.
      CheckRoutine(Child, ClassName);
    end;
  end;
end;

procedure TShadowCheck.Run;
var
  Index: Integer;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(FContext.Tree.Root);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if Node.Kind = TSyntaxKind.RoutineDecl then
      begin
        CheckRoutine(Node, '');
        Continue;
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inheritance.Shadowing', cTexts);

end.
