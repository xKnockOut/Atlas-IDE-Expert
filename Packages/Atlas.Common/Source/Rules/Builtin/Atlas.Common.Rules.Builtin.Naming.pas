unit Atlas.Common.Rules.Builtin.Naming;

// Namenskonvention (#1111):
//   naming-prefix  Name ohne das Präfix seiner Art (Gruppe Stil, Hinweis)
//
// Arten und Standardpräfixe: lokale Variable (auch Inline-var und for var) m,
// Feld (auch class var) F, Parameter A, Konstante (const, auch lokal, in
// Klassen und Inline-const; resourcestring nicht) c. Hinter einem Präfix, das
// auf einen Buchstaben endet, muss ein Großbuchstabe oder eine Ziffer folgen
// (mIndex, nicht menu). Globale Variablen prüft die Regel nicht.
//
// Herkunft der Präfixe je Art: Option in atlas.json ("local", "field",
// "parameter", "constant"), sonst die Projektdatei .atlas (naming, über den
// Projektkontext der IDE), sonst der Standard. Ein leerer Wert schaltet die
// Art ab. Die Regel ist experimentell: Sie läuft nur, wenn atlas.json sie
// einschaltet; ohne eingestellte Konvention bleibt sie still.
//
// Ausnahmen: Schleifenzähler aus einem Buchstaben (I, J, K), Parameter
// Sender, Self und Result, Namen nach "ignore" (Muster mit * und ?),
// öffentliche Felder (public, published und Felder eines Records vor seinem
// ersten Sichtbarkeitsabschnitt: Das F gilt nach Delphi-Konvention nur für
// Felder hinter Properties, nicht für TPoint.X), Felder vor dem ersten
// Sichtbarkeitsabschnitt eines Formulars, Frames oder Datenmoduls
// (Komponenten), Parameter von Methoden
// mit override oder message, von published-Methoden, von Ereignis-Handlern
// (ein Parameter heißt Sender oder der Code weist die Methode einer Property
// OnXyz zu: FEvents.OnEditorPaintLine := PaintLine) und von Methoden, die eine
// Interface-Methode erfüllen: Sie behalten die Namen ihrer Vorlage. In einer
// Parameterliste mit einem Parameter, der genau wie das Präfix heißt
// (Vergleicher function(const A, B: T)), gelten Namen aus einem Buchstaben als
// Paar und werden nicht gemeldet. Bleibt offen, ob eine
// Methode ein Interface erfüllt (Interface weder in der Datei noch im Index),
// schweigt die Regel für ihre Parameter.
//
// Parameter werden an der Deklaration gemeldet (Klasse, interface-Abschnitt,
// forward), nicht noch einmal an der Implementierung.
//
// Korrektur „In mIndex umbenennen“: alle Vorkommen in der Routine bzw. dem
// Block ab der Inline-Deklaration, bei Parametern auch Deklaration und
// Implementierung, bei privaten Feldern und Klassenkonstanten Klasse und
// Methoden der Klasse (auch Self.Name, also read/write der Properties), bei
// Konstanten der implementation die ganze Unit. Keine Korrektur, wenn der neue
// Name in der Datei schon vorkommt, der Bereich with enthält, eine
// verschachtelte Routine den Namen neu deklariert oder der Name außerhalb der
// Datei sichtbar ist (geschützte Felder, Konstanten im interface-Abschnitt).

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cNamingPrefixRuleId = 'naming-prefix';

type
  /// <summary>Wirksame Präfixe der Regel; '' = Art nicht prüfen.</summary>
  TNamingConvention = record
    Prefixes: array[TRuleNamingKind] of string;
    Ignore: TArray<string>;
    /// <summary>Option aus atlas.json, sonst Projektdatei (AContext.Naming), sonst DefaultPrefixes.</summary>
    class function Resolve(const AContext: TRuleContext): TNamingConvention; static;
    /// <summary>Trägt AName das Präfix APrefix? Bei einem Präfix, das auf einen Buchstaben endet, folgt ein
    /// Großbuchstabe oder eine Ziffer. True für ein leeres Präfix.</summary>
    class function Follows(const AName, APrefix: string): Boolean; static;
    /// <summary>Erwarteter Name: APrefix vor AName, dessen erster Buchstabe groß, wenn das Präfix auf einen
    /// Buchstaben endet (Index → mIndex, index → mIndex).</summary>
    class function Expected(const AName, APrefix: string): string; static;
  end;

  TNamingPrefixRule = class(TInterfacedObject, IRule, IRuleNewNames)
  public const
    cRuleId = cNamingPrefixRuleId;
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Korrekturen und Refactorings bilden neue Namen mit den Präfixen dieser Regel.</summary>
    function NewNames(const AContext: TRuleContext): TPascalNamePrefixes;
  end;

const
  cDefaultNamingPrefixes: array[TRuleNamingKind] of string = ('m', 'F', 'A', 'c');

/// <summary>Präfix für Umbenennungen anderer Regeln (shadowed-name): das der Namensregel, wenn sie für die Datei
/// läuft (AContext.NewNames), sonst die Vorgabe der Projektdatei, wenn sie eines setzt, sonst ADefault.</summary>
function NamingPrefixFor(const AContext: TRuleContext; AKind: TRuleNamingKind; const ADefault: string): string;

procedure RegisterNamingRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.Types,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.EventAssignments,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Unused.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TNamingText = (Title, MissingPrefix, RenameTo, LocalVariable, FieldKind, ParameterKind, ConstantKind);

const
  cTexts: array[TNamingText] of TAtlasText = (
    (De: 'Name ohne das Präfix seiner Art'; En: 'Name without the prefix of its kind'),
    (De: '%s %s ohne Präfix %s (erwartet: %s)'; En: '%s %s without prefix %s (expected: %s)'),
    (De: 'In %s umbenennen'; En: 'Rename to %s'),
    (De: 'Lokale Variable'; En: 'Local variable'),
    (De: 'Feld'; En: 'Field'),
    (De: 'Parameter'; En: 'Parameter'),
    (De: 'Konstante'; En: 'Constant'));

{$SCOPEDENUMS OFF}

const
  cOptionKeys: array[TRuleNamingKind] of string = ('local', 'field', 'parameter', 'constant');
  cKindTexts: array[TRuleNamingKind] of TNamingText = (TNamingText.LocalVariable, TNamingText.FieldKind,
    TNamingText.ParameterKind, TNamingText.ConstantKind);
  cTypeBodies = [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType, TSyntaxKind.InterfaceType,
    TSyntaxKind.HelperType];
  // Ohne Index: Komponenten stehen vor dem ersten Sichtbarkeitsabschnitt dieser Klassen.
  cComponentHosts: array[0..2] of string = ('Form', 'Frame', 'DataModule');

function NamingPrefixFor(const AContext: TRuleContext; AKind: TRuleNamingKind; const ADefault: string): string;
begin
  case AKind of
    TRuleNamingKind.Local:
      Result := AContext.NewNames.LocalPrefix;
    TRuleNamingKind.Field:
      Result := AContext.NewNames.FieldPrefix;
    TRuleNamingKind.Parameter:
      Result := AContext.NewNames.ParameterPrefix;
  else
    Result := AContext.NewNames.ConstantPrefix;
  end;
  if Result <> '' then
  begin
    Exit;
  end;
  Result := ADefault;
  if AContext.Naming.Known[AKind] and (AContext.Naming.Prefixes[AKind] <> '') then
  begin
    Result := AContext.Naming.Prefixes[AKind];
  end;
end;

function IsLetter(ACh: Char): Boolean;
begin
  Result := AnsiUpperCase(ACh) <> AnsiLowerCase(ACh);
end;

function IsUpperOrDigit(ACh: Char): Boolean;
begin
  Result := CharInSet(ACh, ['0'..'9']) or (IsLetter(ACh) and (AnsiUpperCase(ACh) = ACh));
end;

{ TNamingConvention }

class function TNamingConvention.Resolve(const AContext: TRuleContext): TNamingConvention;
var
  mKind: TRuleNamingKind;
  mValue: TJSONValue;
  mMember: TJSONValue;
begin
  for mKind := Low(TRuleNamingKind) to High(TRuleNamingKind) do
  begin
    if AContext.Naming.Known[mKind] then
    begin
      Result.Prefixes[mKind] := AContext.Naming.Prefixes[mKind];
    end
    else
    begin
      Result.Prefixes[mKind] := cDefaultNamingPrefixes[mKind];
    end;
  end;
  Result.Ignore := TRuleOptions.Strings(AContext.Options, 'ignore', nil);
  if AContext.Options = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AContext.Options);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    for mKind := Low(TRuleNamingKind) to High(TRuleNamingKind) do
    begin
      mMember := TJSONObject(mValue).GetValue(cOptionKeys[mKind]);
      // TJSONNumber erbt von TJSONString; auch ein leerer Text ist eine Vorgabe (Art aus).
      if (mMember is TJSONString) and not (mMember is TJSONNumber) then
      begin
        Result.Prefixes[mKind] := Trim(mMember.Value);
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TNamingConvention.Follows(const AName, APrefix: string): Boolean;
begin
  // Eine Umsetzung für Regel und Korrekturen (TPascalNamePrefixes, Editing darf Rules nicht verwenden).
  Result := TPascalNamePrefixes.Follows(AName, APrefix);
end;

class function TNamingConvention.Expected(const AName, APrefix: string): string;
begin
  Result := TPascalNamePrefixes.Expected(AName, APrefix);
end;

{ TNamingPrefixRule }

function TNamingPrefixRule.NewNames(const AContext: TRuleContext): TPascalNamePrefixes;
var
  mConvention: TNamingConvention;
begin
  mConvention := TNamingConvention.Resolve(AContext);
  Result.LocalPrefix := mConvention.Prefixes[TRuleNamingKind.Local];
  Result.FieldPrefix := mConvention.Prefixes[TRuleNamingKind.Field];
  Result.ParameterPrefix := mConvention.Prefixes[TRuleNamingKind.Parameter];
  Result.ConstantPrefix := mConvention.Prefixes[TRuleNamingKind.Constant];
end;

function TNamingPrefixRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cRuleId, TRuleSeverity.Hint, cTexts[TNamingText.Title].Text);
end;

type
  /// <summary>Wo Parameter stehen: Kopf der Routine, Typ der Methodendeklaration, Rumpf zum Umbenennen.</summary>
  TParameterOwner = record
    Header: TSyntaxNode;
    Body: TSyntaxNode;
    Scope: TSyntaxNode;
  end;

  /// <summary>Eine Prüfung: Name, Art, Deklaration und der Bereich der Korrektur.</summary>
  TNamingCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FConvention: TNamingConvention;
    FCache: IRuleDerivedCache;
    FTokens: TArray<TPascalToken>;
    FIndex: ISymbolIndex;
    // Wurzel und alle RoutineDecl in Baumreihenfolge.
    FRoot: TSyntaxNode;
    FRoutineDecls: TArray<TSyntaxNode>;
    /// <summary>Methoden, die der Code einer Property OnXyz zuweist (TEventAssignments).</summary>
    FEventMethods: TArray<string>;
    /// <summary>Token des Namens in [AStart, AEnd), nicht hinter einem Punkt; hinter AQualifier. (Self, Typname)
    /// doch.</summary>
    function NameTokens(AStart, AEnd: Integer; const AName: string; const AQualifiers: array of string):
      TArray<Integer>;
    /// <summary>Kommt AName irgendwo hinter einem Punkt vor, dessen Qualifizierer nicht in AQualifiers steht?
    /// </summary>
    function QualifiedElsewhere(const AName: string; const AQualifiers: array of string): Boolean;
    /// <summary>Deklariert ein Knoten unter ANode außer ADeclaration den Namen (Variable, Parameter, Konstante)?
    /// </summary>
    function Redeclares(ANode, ADeclaration: TSyntaxNode; const AName: string): Boolean;
    /// <summary>Deklariert der Rumpf von ARoutine (ohne Kopf) den Namen neu?</summary>
    function RedeclaresInBody(ARoutine: TSyntaxNode; const AName: string): Boolean;
    function IsInlineFor(AFor: TSyntaxNode): Boolean;
    function IsComponentHost(ABody: TSyntaxNode): Boolean;
    function MethodsOf(const ATypeName: string): TArray<TSyntaxNode>;
    function ImplementationOf(const AQualified: string; APosition: Integer; const AName: string): TSyntaxNode;
    function DeclarationOf(ARoutine: TSyntaxNode): TSyntaxNode;
    procedure Report(AKind: TRuleNamingKind; ADeclaration: TSyntaxNode; const AName: string;
      const AEdits: TArray<Integer>; ACanFix: Boolean;
    const AScopes: TArray<TPoint>);
    function Wanted(AKind: TRuleNamingKind; const AName: string): Boolean;
    procedure CheckLocal(ADecl: TSyntaxNode; const AName: string; AKind: TRuleNamingKind);
    procedure CheckInlineFor(AFor: TSyntaxNode);
    procedure CheckMember(ABody, ADecl: TSyntaxNode; const AName: string; AKind: TRuleNamingKind);
    function IsExemptField(ABody: TSyntaxNode; const AVisibility: string; AImplicit: Boolean): Boolean;
    function MemberEdits(ABody: TSyntaxNode; const AName, ATypeName: string; out AMethods: TArray<TSyntaxNode>;
      out AEdits: TArray<Integer>): Boolean;
    function IsMemberUse(AIndex: Integer; const ATypeName: string; const AMethods: TArray<TSyntaxNode>): Boolean;
    procedure CheckUnitConstant(ADecl: TSyntaxNode);
    function IsEventMethod(AParams: TSyntaxNode): Boolean;
    procedure CheckParameters(AParams: TSyntaxNode);
    function ParameterOwner(AParams: TSyntaxNode; out AOwner: TParameterOwner): Boolean;
    function HeaderOwner(AHeader: TSyntaxNode; var AOwner: TParameterOwner): Boolean;
    procedure CheckParameter(AParams, AParam: TSyntaxNode; const AName: string; const AOwner: TParameterOwner);
    function DeclaredParameterEdits(AParams, AParam: TSyntaxNode; const AName: string; const AOwner: TParameterOwner;
      var AEdits: TArray<Integer>; var AScopes: TArray<TPoint>): Boolean;
    procedure Visit(ANode: TSyntaxNode);
    procedure CheckLocals(ADecl: TSyntaxNode);
    procedure CheckFields(ABody, ADecl: TSyntaxNode);
    procedure VisitVarDecl(ANode: TSyntaxNode);
    procedure VisitConstDecl(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

function ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function BareTypeName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

function ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  mKind: TSyntaxKind;
begin
  mKind := AKind;
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if AVisited.Kind = mKind then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

function DeclaresName(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  if ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.ConstDecl,
    TSyntaxKind.Parameter, TSyntaxKind.Field] then
  begin
    for mName in SplitString(ANode.Name, ',') do
    begin
      if SameText(Trim(mName), AName) then
      begin
        Exit(True);
      end;
    end;
  end;
  // for var I (Inline-Schleifenvariable): Der Name steht am for.
  if (ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and SameText(ANode.Name, AName) then
  begin
    Result := True;
  end;
end;

function EnclosingScope(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not (Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
  begin
    Result := Result.Parent;
  end;
end;

function OwnerType(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not (Result.Kind in cTypeBodies) do
  begin
    if Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod, TSyntaxKind.TypeDecl] then
    begin
      Exit(nil);
    end;
    Result := Result.Parent;
  end;
end;

function TypeDeclOf(ABody: TSyntaxNode): TSyntaxNode;
begin
  Result := ABody.Parent;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.TypeDecl) do
  begin
    Result := Result.Parent;
  end;
end;

function VisibilityOf(ABody, AMember: TSyntaxNode; out AImplicit: Boolean): string;
var
  mIndex: Integer;
  mMember: TSyntaxNode;
begin
  // Mitglied direkt im Typ oder in einem class var-Abschnitt bzw. varianten Teil darunter.
  mMember := AMember;
  while (mMember.Parent <> nil) and (mMember.Parent <> ABody) do
  begin
    mMember := mMember.Parent;
  end;
  Result := '';
  AImplicit := True;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[mIndex] = mMember then
    begin
      Break;
    end;
    if ABody[mIndex].Kind = TSyntaxKind.Visibility then
    begin
      Result := LowerCase(ABody[mIndex].Name);
      AImplicit := False;
    end;
  end;
end;

function ParameterNames(AParams: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
  mName: string;
begin
  Result := nil;
  for mIndex := 0 to AParams.ChildCount - 1 do
  begin
    if AParams[mIndex].Kind = TSyntaxKind.Parameter then
    begin
      for mName in SplitString(AParams[mIndex].Name, ',') do
      begin
        if Trim(mName) <> '' then
        begin
          Result := Result + [Trim(mName)];
        end;
      end;
    end;
  end;
end;

function ParameterPosition(AParams, AParam: TSyntaxNode; const AName: string): Integer;
var
  mIndex: Integer;
  mName: string;
begin
  Result := 0;
  for mIndex := 0 to AParams.ChildCount - 1 do
  begin
    if AParams[mIndex].Kind <> TSyntaxKind.Parameter then
    begin
      Continue;
    end;
    for mName in SplitString(AParams[mIndex].Name, ',') do
    begin
      if (AParams[mIndex] = AParam) and SameText(Trim(mName), AName) then
      begin
        Exit;
      end;
      if Trim(mName) <> '' then
      begin
        Inc(Result);
      end;
    end;
  end;
  Result := -1;
end;

function HasDirective(AHeader: TSyntaxNode; const ANames: array of string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and MatchText(AHeader[mIndex].Name, ANames) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function IsForwardOrInterface(ARoutine: TSyntaxNode): Boolean;
begin
  Result := ARoutine.FindChild(TSyntaxKind.Block) = nil;
end;

/// <summary>Interfaces der Vorfahrenliste: ab dem zweiten Eintrag alle, der erste, wenn er wie eines heißt.</summary>
function InterfaceNames(ABody: TSyntaxNode): TArray<string>;
var
  mIndex, mCount: Integer;
  mName: string;
begin
  Result := nil;
  mCount := 0;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[mIndex].Kind <> TSyntaxKind.TypeReference then
    begin
      Continue;
    end;
    mName := BareTypeName(ABody[mIndex].Name);
    if (mCount > 0) or (Length(mName) > 1) and (mName[1] = 'I') and IsUpperOrDigit(mName[2]) then
    begin
      Result := Result + [mName];
    end;
    Inc(mCount);
  end;
end;

function FindInterfaceDecl(ARoot: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mName: string;
begin
  mName := AName;
  Result := ARoot.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (AVisited.Kind = TSyntaxKind.TypeDecl) and SameText(AVisited.Name, mName) and
        (AVisited.FindChild(TSyntaxKind.InterfaceType) <> nil) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

/// <summary>Heißt ARoutine AMethod und gehört (mit ATypeName) zu diesem Typ bzw. (ohne) zu keinem?</summary>
function IsRoutineNamed(ARoutine: TSyntaxNode; const ATypeName, AMethod: string): Boolean;
begin
  if ATypeName = '' then
  begin
    Exit(SameText(ARoutine.Name, AMethod));
  end;
  Result := (Pos('.', ARoutine.Name) > 0) and SameText(ShortName(ARoutine.Name), AMethod) and
    SameText(BareTypeName(Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1)), ATypeName);
end;

/// <summary>Überladungen: derselbe Parametername an derselben Stelle.</summary>
function HasParameterAt(ARoutine: TSyntaxNode; APosition: Integer; const AName: string): Boolean;
var
  mHeader, mParams: TSyntaxNode;
  mNames: TArray<string>;
begin
  Result := False;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  mParams := nil;
  if mHeader <> nil then
  begin
    mParams := mHeader.FindChild(TSyntaxKind.Parameters);
  end;
  if mParams <> nil then
  begin
    mNames := ParameterNames(mParams);
    Result := (APosition < Length(mNames)) and SameText(mNames[APosition], AName);
  end;
end;

/// <summary>Interface in dieser Unit: hat es AMethod? Seine Vorfahren kommen nach APending.</summary>
function LocalInterfaceHas(ARoot: TSyntaxNode; const AName, AMethod: string; APending: TList<string>;
  out AResolved: Boolean): Boolean;
var
  mFound, mMembers: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mFound := FindInterfaceDecl(ARoot, AName);
  AResolved := mFound <> nil;
  if mFound = nil then
  begin
    Exit;
  end;
  mMembers := mFound.FindChild(TSyntaxKind.InterfaceType);
  for mIndex := 0 to mMembers.ChildCount - 1 do
  begin
    if (mMembers[mIndex].Kind = TSyntaxKind.RoutineHeader) and SameText(mMembers[mIndex].Name, AMethod) then
    begin
      Exit(True);
    end;
    if mMembers[mIndex].Kind = TSyntaxKind.TypeReference then
    begin
      APending.Add(BareTypeName(mMembers[mIndex].Name));
    end;
  end;
end;

function IndexMemberOf(const AIndex: ISymbolIndex; const AContainer, AMethod: string): Boolean;
var
  mMember: TSymbolLocation;
begin
  for mMember in AIndex.FindSymbols(AMethod) do
  begin
    if SameText(mMember.Symbol.Container, AContainer) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Interface aus dem Index: hat es AMethod? Seine Vorfahren kommen nach APending.</summary>
function IndexInterfaceHas(const AIndex: ISymbolIndex; const AName, AMethod: string; APending: TList<string>;
  out AResolved: Boolean): Boolean;
var
  mLocation: TSymbolLocation;
  mIndex: Integer;
begin
  Result := False;
  AResolved := False;
  if AIndex = nil then
  begin
    Exit;
  end;
  for mLocation in AIndex.FindSymbols(AName) do
  begin
    if mLocation.Symbol.Kind <> TIndexSymbolKind.InterfaceType then
    begin
      Continue;
    end;
    AResolved := True;
    if IndexMemberOf(AIndex, AName, AMethod) then
    begin
      Exit(True);
    end;
    for mIndex := 0 to High(mLocation.Symbol.Ancestors) do
    begin
      APending.Add(BareTypeName(mLocation.Symbol.Ancestors[mIndex]));
    end;
  end;
end;

function ImplementsInterface(ARoot: TSyntaxNode; const AIndex: ISymbolIndex; ABody: TSyntaxNode;
  const AMethod: string; out AKnown: Boolean): Boolean;
var
  mPending: TList<string>;
  mSeen: TList<string>;
  mName: string;
  mResolved: Boolean;
begin
  Result := False;
  AKnown := True;
  if ABody.Kind <> TSyntaxKind.ClassType then
  begin
    Exit;
  end;
  mPending := TList<string>.Create;
  mSeen := TList<string>.Create;
  try
    mPending.AddRange(InterfaceNames(ABody));
    // Auch die Vorfahren der Interfaces (IFoo = interface(IBar)).
    while mPending.Count > 0 do
    begin
      mName := mPending[mPending.Count - 1];
      mPending.Delete(mPending.Count - 1);
      if mSeen.IndexOf(LowerCase(mName)) >= 0 then
      begin
        Continue;
      end;
      mSeen.Add(LowerCase(mName));
      if LocalInterfaceHas(ARoot, mName, AMethod, mPending, mResolved) or
        not mResolved and IndexInterfaceHas(AIndex, mName, AMethod, mPending, mResolved) then
      begin
        Exit(True);
      end;
      // IInterface und IUnknown haben nur _AddRef, _Release und QueryInterface.
      if not mResolved and not MatchText(mName, ['IInterface', 'IUnknown', 'IDispatch']) then
      begin
        AKnown := False;
      end;
    end;
  finally
    mSeen.Free;
    mPending.Free;
  end;
end;

function TokenIn(const ATokens: TArray<TPascalToken>; AIndex: Integer; ANode: TSyntaxNode): Boolean;
begin
  Result := (ATokens[AIndex].Offset >= ANode.StartOffset) and (ATokens[AIndex].Offset < ANode.EndOffset);
end;

function InAny(const ATokens: TArray<TPascalToken>; AIndex: Integer; const ANodes: TArray<TSyntaxNode>): Boolean;
var
  mNode: TSyntaxNode;
begin
  for mNode in ANodes do
  begin
    if TokenIn(ATokens, AIndex, mNode) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function OccursInFile(const ATokens: TArray<TPascalToken>; const AName: string): Boolean;
var
  mToken: TPascalToken;
begin
  for mToken in ATokens do
  begin
    if (mToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and SameText(mToken.Text, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function OccursIn(const ATokens: TArray<TPascalToken>; const AName: string;
  const AScopes: TArray<TPoint>): Boolean;
var
  mScope: TPoint;
  mIndex: Integer;
begin
  if AScopes = nil then
  begin
    Exit(OccursInFile(ATokens, AName));
  end;
  // Je Bereich binär zum ersten Token statt jedes Mal die ganze Datei (#1323).
  for mScope in AScopes do
  begin
    mIndex := TRoutineBody.TokenAt(ATokens, mScope.X);
    while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < mScope.Y) do
    begin
      if (ATokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
        SameText(ATokens[mIndex].Text, AName) then
      begin
        Exit(True);
      end;
      Inc(mIndex);
    end;
  end;
  Result := False;
end;

function EditsFor(const ATokens: TArray<TPascalToken>; const AIndexes: TArray<Integer>;
  const ANewName: string): TArray<TRuleEdit>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex in AIndexes do
  begin
    Result := Result + [TRuleEdit.Create(TTextRange.Create(ATokens[mIndex].StartPos, ATokens[mIndex].EndPos),
      ANewName)];
  end;
end;

function FirstNameToken(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode; const AName: string;
  out AIndex: Integer): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := TSyntaxTree.FirstTokenOf(ATokens, ANode.StartOffset) to High(ATokens) do
  begin
    if ATokens[mIndex].Offset >= ANode.EndOffset then
    begin
      Break;
    end;
    if (ATokens[mIndex].Offset >= ANode.StartOffset) and
      (ATokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      SameText(ATokens[mIndex].Text, AName) then
    begin
      AIndex := mIndex;
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TNamingCheck }

constructor TNamingCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FConvention := TNamingConvention.Resolve(AContext);
  FCache := TRuleDerived.Open(AContext);
  FTokens := TRuleDerived.CodeTokens(FCache, AContext);
  FIndex := AContext.Index;
  FRoot := AContext.Tree.Root;
  FEventMethods := TEventAssignments.Names(AContext.Tree.Tokens);
end;

function TNamingCheck.NameTokens(AStart, AEnd: Integer; const AName: string; const AQualifiers: array of string):
  TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := TSyntaxTree.FirstTokenOf(FTokens, AStart) to High(FTokens) do
  begin
    if FTokens[mIndex].Offset >= AEnd then
    begin
      Break;
    end;
    if (FTokens[mIndex].Offset < AStart) or
      not (FTokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) or
      not SameText(FTokens[mIndex].Text, AName) then
    begin
      Continue;
    end;
    // Obj.Name ist ein anderes Symbol; Self.Name und TTyp.Name nur bei Mitgliedern.
    if (mIndex > 0) and FTokens[mIndex - 1].IsSymbol('.') and
      not ((mIndex > 1) and MatchText(FTokens[mIndex - 2].Text, AQualifiers)) then
    begin
      Continue;
    end;
    Result := Result + [mIndex];
  end;
end;

function TNamingCheck.QualifiedElsewhere(const AName: string; const AQualifiers: array of string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 2 to High(FTokens) do
  begin
    if (FTokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      SameText(FTokens[mIndex].Text, AName) and FTokens[mIndex - 1].IsSymbol('.') and
      not MatchText(FTokens[mIndex - 2].Text, AQualifiers) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TNamingCheck.Redeclares(ANode, ADeclaration: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
  mDeclaration: TSyntaxNode;
  mSelf_: TNamingCheck;
begin
  mName := AName;
  mDeclaration := ADeclaration;
  mSelf_ := Self;
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      // Eine for-Schleife über die vorhandene Variable deklariert nichts.
      if (AVisited <> mDeclaration) and DeclaresName(AVisited, mName) and
        not ((AVisited.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and
        not mSelf_.IsInlineFor(AVisited)) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

function TNamingCheck.RedeclaresInBody(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if (ARoutine[mIndex].Kind <> TSyntaxKind.RoutineHeader) and Redeclares(ARoutine[mIndex], nil, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TNamingCheck.IsComponentHost(ABody: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  mHost: string;
begin
  if FContext.FormText <> '' then
  begin
    Exit(True);
  end;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[mIndex].Kind = TSyntaxKind.TypeReference then
    begin
      for mHost in cComponentHosts do
      begin
        if EndsText(mHost, BareTypeName(ABody[mIndex].Name)) then
        begin
          Exit(True);
        end;
      end;
      Break;
    end;
  end;
  Result := False;
end;

function TNamingCheck.MethodsOf(const ATypeName: string): TArray<TSyntaxNode>;
var
  mRoutine: TSyntaxNode;
  mOwner: string;
begin
  Result := nil;
  for mRoutine in FRoutineDecls do
  begin
    if Pos('.', mRoutine.Name) > 0 then
    begin
      mOwner := Copy(mRoutine.Name, 1, LastDelimiter('.', mRoutine.Name) - 1);
      if SameText(BareTypeName(mOwner), ATypeName) then
      begin
        Result := Result + [mRoutine];
      end;
    end;
  end;
end;

function TNamingCheck.DeclarationOf(ARoutine: TSyntaxNode): TSyntaxNode;
var
  mRoutine: TSyntaxNode;
begin
  // Routine mit Rumpf ohne Punkt: Deklaration im interface-Abschnitt oder forward davor.
  for mRoutine in FRoutineDecls do
  begin
    if (mRoutine <> ARoutine) and IsForwardOrInterface(mRoutine) and SameText(mRoutine.Name, ARoutine.Name) and
      (EnclosingScope(mRoutine) = EnclosingScope(ARoutine)) then
    begin
      Exit(mRoutine);
    end;
  end;
  Result := nil;
end;

function TNamingCheck.ImplementationOf(const AQualified: string; APosition: Integer; const AName: string):
  TSyntaxNode;
var
  mRoutine: TSyntaxNode;
  mTypeName, mMethod: string;
begin
  mTypeName := '';
  mMethod := AQualified;
  if Pos('.', AQualified) > 0 then
  begin
    mTypeName := BareTypeName(Copy(AQualified, 1, LastDelimiter('.', AQualified) - 1));
    mMethod := ShortName(AQualified);
  end;
  for mRoutine in FRoutineDecls do
  begin
    if not IsForwardOrInterface(mRoutine) and IsRoutineNamed(mRoutine, mTypeName, mMethod) and
      HasParameterAt(mRoutine, APosition, AName) then
    begin
      Exit(mRoutine);
    end;
  end;
  Result := nil;
end;

function TNamingCheck.Wanted(AKind: TRuleNamingKind; const AName: string): Boolean;
var
  mPattern: string;
begin
  Result := (FConvention.Prefixes[AKind] <> '') and (AName <> '') and not MatchText(AName, ['Self', 'Result']) and
    not TNamingConvention.Follows(AName, FConvention.Prefixes[AKind]);
  if Result then
  begin
    for mPattern in FConvention.Ignore do
    begin
      if MatchesWildcard(AName, mPattern) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

procedure TNamingCheck.Report(AKind: TRuleNamingKind; ADeclaration: TSyntaxNode; const AName: string;
  const AEdits: TArray<Integer>; ACanFix: Boolean;
  const AScopes: TArray<TPoint>);
var
  mNewName, mMessage: string;
  mAt: Integer;
  mFixes: TArray<TRuleFix>;
begin
  if not FirstNameToken(FTokens, ADeclaration, AName, mAt) then
  begin
    Exit;
  end;
  mNewName := TNamingConvention.Expected(AName, FConvention.Prefixes[AKind]);
  mMessage := cTexts[TNamingText.MissingPrefix].Fmt([cTexts[cKindTexts[AKind]].Text, AName, FConvention.Prefixes[AKind],
    mNewName]);
  mFixes := nil;
  // Nur wo umbenannt wird, kann der neue Name kollidieren (ABuf als Parameter einer anderen Methode stört nicht).
  // Ein reserviertes Wort als neuer Name übersetzt nicht (Parameter S würde zu AS).
  if ACanFix and (Length(AEdits) > 0) and not OccursIn(FTokens, mNewName, AScopes) and
    not TPascalLexer.IsReservedWord(mNewName) then
  begin
    mFixes := [TRuleFix.Create(cTexts[TNamingText.RenameTo].Fmt([mNewName]), EditsFor(FTokens, AEdits, mNewName))];
  end;
  FReport.Add(TTextRange.Create(FTokens[mAt].StartPos, FTokens[mAt].EndPos), mMessage, TRuleConfidence.High, mFixes);
end;

procedure TNamingCheck.CheckLocal(ADecl: TSyntaxNode; const AName: string; AKind: TRuleNamingKind);
var
  mScope: TSyntaxNode;
  mStart, mStop: Integer;
  mCanFix: Boolean;
begin
  if not Wanted(AKind, AName) then
  begin
    Exit;
  end;
  mScope := EnclosingScope(ADecl);
  if mScope = nil then
  begin
    Exit;
  end;
  // Inline-Deklarationen gelten ab der Deklaration bis zum Ende ihres Blocks.
  if ADecl.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
  begin
    mStart := ADecl.StartOffset;
    mStop := ADecl.Parent.EndOffset;
  end
  else
  begin
    mStart := mScope.StartOffset;
    mStop := mScope.EndOffset;
  end;
  mCanFix := not ContainsKind(mScope, TSyntaxKind.WithStatement) and not Redeclares(mScope, ADecl, AName);
  Report(AKind, ADecl, AName, NameTokens(mStart, mStop, AName, []), mCanFix,
    [Point(mScope.StartOffset, mScope.EndOffset)]);
end;

function TNamingCheck.IsInlineFor(AFor: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  // Binär zum Anfang der Schleife statt ab Dateianfang (#1342).
  mIndex := TSyntaxTree.FirstTokenOf(FTokens, AFor.StartOffset);
  Result := (mIndex < High(FTokens)) and FTokens[mIndex].IsKeyword('for') and FTokens[mIndex + 1].IsKeyword('var');
end;

procedure TNamingCheck.CheckInlineFor(AFor: TSyntaxNode);
var
  mCanFix: Boolean;
  mScope: TSyntaxNode;
begin
  if (Length(AFor.Name) = 1) or not IsInlineFor(AFor) or not Wanted(TRuleNamingKind.Local, AFor.Name) then
  begin
    Exit;
  end;
  mScope := EnclosingScope(AFor);
  mCanFix := (mScope <> nil) and not ContainsKind(AFor, TSyntaxKind.WithStatement) and
    not Redeclares(AFor, AFor, AFor.Name);
  if mScope = nil then
  begin
    mScope := AFor;
  end;
  Report(TRuleNamingKind.Local, AFor, AFor.Name, NameTokens(AFor.StartOffset, AFor.EndOffset, AFor.Name, []),
    mCanFix, [Point(mScope.StartOffset, mScope.EndOffset)]);
end;

procedure TNamingCheck.CheckMember(ABody, ADecl: TSyntaxNode; const AName: string; AKind: TRuleNamingKind);
var
  mVisibility: string;
  mImplicit, mCanFix: Boolean;
  mTypeDecl, mMethod: TSyntaxNode;
  mMethods: TArray<TSyntaxNode>;
  mEdits: TArray<Integer>;
  mScopes: TArray<TPoint>;
begin
  mMethods := nil;
  mVisibility := VisibilityOf(ABody, ADecl, mImplicit);
  if (AKind = TRuleNamingKind.Field) and IsExemptField(ABody, mVisibility, mImplicit) or not Wanted(AKind, AName) then
  begin
    Exit;
  end;
  mTypeDecl := TypeDeclOf(ABody);
  mCanFix := (mTypeDecl <> nil) and (ABody.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType,
    TSyntaxKind.ObjectType]) and ((mVisibility = 'private') or (mVisibility = 'strict private'));
  mEdits := nil;
  if mCanFix then
  begin
    mCanFix := MemberEdits(ABody, AName, BareTypeName(mTypeDecl.Name), mMethods, mEdits);
  end;
  // Kollisionen in der Klasse und ihren Methoden; ein gleichnamiges Feld einer anderen Klasse stört nicht.
  mScopes := [Point(ABody.StartOffset, ABody.EndOffset)];
  for mMethod in mMethods do
  begin
    mScopes := mScopes + [Point(mMethod.StartOffset, mMethod.EndOffset)];
  end;
  Report(AKind, ADecl, AName, mEdits, mCanFix, mScopes);
end;

/// <summary>Öffentliche Felder (auch die eines Records ohne Abschnitt) tragen kein F; Komponenten vor dem ersten
/// Abschnitt: Ihre Namen stehen in der Formulardatei.</summary>
function TNamingCheck.IsExemptField(ABody: TSyntaxNode; const AVisibility: string; AImplicit: Boolean): Boolean;
begin
  if AImplicit then
  begin
    Result := (ABody.Kind = TSyntaxKind.RecordType) or (ABody.Kind = TSyntaxKind.ClassType) and IsComponentHost(ABody);
  end
  else
  begin
    Result := (AVisibility = 'public') or (AVisibility = 'published');
  end;
end;

/// <summary>Stellen zum Umbenennen eines privaten Mitglieds: in der Klasse, in ihren Methoden (unqualifiziert,
/// Self.Name) und TTyp.Name überall; False, wenn das Umbenennen nicht sicher ist.</summary>
function TNamingCheck.MemberEdits(ABody: TSyntaxNode; const AName, ATypeName: string;
  out AMethods: TArray<TSyntaxNode>; out AEdits: TArray<Integer>): Boolean;
var
  mMethod: TSyntaxNode;
  mIndex: Integer;
begin
  // Obj.Name eines anderen Objekts derselben Klasse ließe sich nicht sicher zuordnen.
  Result := not QualifiedElsewhere(AName, ['Self', ATypeName]);
  AEdits := NameTokens(ABody.StartOffset, ABody.EndOffset, AName, ['Self', ATypeName]);
  AMethods := MethodsOf(ATypeName);
  for mMethod in AMethods do
  begin
    if ContainsKind(mMethod, TSyntaxKind.WithStatement) or RedeclaresInBody(mMethod, AName) then
    begin
      Result := False;
    end;
  end;
  // Ab dem Ende der Klasse: Methoden (unqualifiziert, Self.Name) und TTyp.Name überall.
  for mIndex := TSyntaxTree.FirstTokenOf(FTokens, ABody.EndOffset) to High(FTokens) do
  begin
    if (FTokens[mIndex].Offset >= ABody.EndOffset) and SameText(FTokens[mIndex].Text, AName) and
      (FTokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      IsMemberUse(mIndex, ATypeName, AMethods) then
    begin
      AEdits := AEdits + [mIndex];
    end;
  end;
end;

/// <summary>Token AIndex ist Self.Name bzw. TTyp.Name oder unqualifiziert in einer der Methoden.</summary>
function TNamingCheck.IsMemberUse(AIndex: Integer; const ATypeName: string;
  const AMethods: TArray<TSyntaxNode>): Boolean;
begin
  if FTokens[AIndex - 1].IsSymbol('.') then
  begin
    Result := MatchText(FTokens[AIndex - 2].Text, ['Self', ATypeName]);
  end
  else
  begin
    Result := InAny(FTokens, AIndex, AMethods);
  end;
end;

procedure TNamingCheck.CheckUnitConstant(ADecl: TSyntaxNode);
var
  mSection: TSyntaxNode;
  mCanFix: Boolean;
begin
  if not Wanted(TRuleNamingKind.Constant, ADecl.Name) then
  begin
    Exit;
  end;
  mSection := ADecl.Parent;
  while (mSection <> nil) and not (mSection.Kind in [TSyntaxKind.InterfaceSection,
    TSyntaxKind.ImplementationSection]) do
  begin
    mSection := mSection.Parent;
  end;
  // Im interface-Abschnitt sehen andere Units die Konstante; dort keine Korrektur. Verdeckt eine Routine den
  // Namen, wäre das Umbenennen aller Vorkommen falsch.
  mCanFix := ((mSection = nil) or (mSection.Kind = TSyntaxKind.ImplementationSection)) and
    not ContainsKind(FRoot, TSyntaxKind.WithStatement) and not Redeclares(FRoot, ADecl, ADecl.Name);
  Report(TRuleNamingKind.Constant, ADecl, ADecl.Name, NameTokens(ADecl.StartOffset, FRoot.EndOffset, ADecl.Name,
    []), mCanFix, nil);
end;

/// <summary>Gehören die Parameter AParams zu einer Methode, die der Code einem Ereignis zuweist?</summary>
function TNamingCheck.IsEventMethod(AParams: TSyntaxNode): Boolean;
var
  mName: string;
begin
  Result := False;
  if (AParams.Parent = nil) or not (AParams.Parent.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl]) or
    (FEventMethods = nil) then
  begin
    Exit;
  end;
  mName := AParams.Parent.Name;
  mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  Result := MatchText(mName, FEventMethods);
end;

procedure TNamingCheck.CheckParameters(AParams: TSyntaxNode);
var
  mOwner: TParameterOwner;
  mIndex: Integer;
  mName: string;
  mPair: Boolean;
begin
  // Ereignis-Handler: Die Namen gibt der Ereignistyp vor (FormClose(Sender; var Action)).
  if (MatchText('Sender', ParameterNames(AParams))) or not ParameterOwner(AParams, mOwner) or
    IsEventMethod(AParams) then
  begin
    Exit;
  end;
  mPair := MatchText(FConvention.Prefixes[TRuleNamingKind.Parameter], ParameterNames(AParams));
  for mIndex := 0 to AParams.ChildCount - 1 do
  begin
    if AParams[mIndex].Kind <> TSyntaxKind.Parameter then
    begin
      Continue;
    end;
    for mName in SplitString(AParams[mIndex].Name, ',') do
    begin
      if Wanted(TRuleNamingKind.Parameter, Trim(mName)) and not (mPair and (Length(Trim(mName)) = 1)) then
      begin
        CheckParameter(AParams, AParams[mIndex], Trim(mName), mOwner);
      end;
    end;
  end;
end;

/// <summary>Wo die Parameter stehen: Kopf, Typ (Methode in der Typdeklaration) und Rumpf zum Umbenennen;
/// False, wenn die Namen nicht hier geprüft werden (override, message, published, Interface-Methode,
/// Implementierung einer anderswo deklarierten Routine).</summary>
function TNamingCheck.ParameterOwner(AParams: TSyntaxNode; out AOwner: TParameterOwner): Boolean;
var
  mOwner: TSyntaxNode;
begin
  AOwner.Header := nil;
  AOwner.Body := nil;
  AOwner.Scope := nil;
  mOwner := AParams.Parent;
  if mOwner = nil then
  begin
    Exit(False);
  end;
  case mOwner.Kind of
    TSyntaxKind.RoutineHeader:
      begin
        AOwner.Header := mOwner;
        Result := HeaderOwner(mOwner, AOwner);
      end;
    TSyntaxKind.AnonymousMethod:
      begin
        AOwner.Scope := mOwner;
        Result := True;
      end;
    TSyntaxKind.ProcedureType:
      Result := True;
  else
    Result := False;
  end;
end;

function TNamingCheck.HeaderOwner(AHeader: TSyntaxNode; var AOwner: TParameterOwner): Boolean;
var
  mKnown, mImplicit: Boolean;
  mRoutine: TSyntaxNode;
begin
  if (AHeader.Parent <> nil) and (AHeader.Parent.Kind in cTypeBodies) then
  begin
    // Methode in der Typdeklaration.
    AOwner.Body := AHeader.Parent;
    Result := not HasDirective(AHeader, ['override', 'message']) and
      (VisibilityOf(AOwner.Body, AHeader, mImplicit) <> 'published') and
      not ImplementsInterface(FRoot, FIndex, AOwner.Body, AHeader.Name, mKnown) and mKnown;
  end
  else if (AHeader.Parent <> nil) and (AHeader.Parent.Kind = TSyntaxKind.RoutineDecl) then
  begin
    mRoutine := AHeader.Parent;
    // Implementierung einer Methode oder einer anderswo deklarierten Routine: dort gemeldet.
    if IsForwardOrInterface(mRoutine) then
    begin
      Exit(True);
    end;
    AOwner.Scope := mRoutine;
    Result := (Pos('.', mRoutine.Name) = 0) and (DeclarationOf(mRoutine) = nil);
  end
  else
  begin
    Result := False;
  end;
end;

procedure TNamingCheck.CheckParameter(AParams, AParam: TSyntaxNode; const AName: string;
  const AOwner: TParameterOwner);
var
  mEdits: TArray<Integer>;
  mCanFix: Boolean;
  mScopes: TArray<TPoint>;
begin
  mEdits := NameTokens(AParam.StartOffset, AParam.EndOffset, AName, []);
  mCanFix := True;
  // Kollisionen in der Parameterliste und dort, wo umbenannt wird (Rumpf bzw. Implementierung).
  mScopes := [Point(AParams.StartOffset, AParams.EndOffset)];
  if AOwner.Scope <> nil then
  begin
    // Rumpf der Routine bzw. der anonymen Methode (ohne die Parameterliste selbst).
    mCanFix := not ContainsKind(AOwner.Scope, TSyntaxKind.WithStatement) and
      not Redeclares(AOwner.Scope, AParam, AName);
    mEdits := mEdits + NameTokens(AParams.EndOffset, AOwner.Scope.EndOffset, AName, []);
    mScopes := mScopes + [Point(AOwner.Scope.StartOffset, AOwner.Scope.EndOffset)];
  end
  else if AOwner.Header <> nil then
  begin
    mCanFix := DeclaredParameterEdits(AParams, AParam, AName, AOwner, mEdits, mScopes);
  end;
  Report(TRuleNamingKind.Parameter, AParam, AName, mEdits, mCanFix, mScopes);
end;

/// <summary>Deklaration: die Implementierung mit demselben Parameter an derselben Stelle mit umbenennen.</summary>
function TNamingCheck.DeclaredParameterEdits(AParams, AParam: TSyntaxNode; const AName: string;
  const AOwner: TParameterOwner; var AEdits: TArray<Integer>; var AScopes: TArray<TPoint>): Boolean;
var
  mMethod: string;
  mImplementation: TSyntaxNode;
begin
  Result := True;
  mMethod := AOwner.Header.Name;
  if AOwner.Body <> nil then
  begin
    mMethod := BareTypeName(TypeDeclOf(AOwner.Body).Name) + '.' + AOwner.Header.Name;
  end;
  mImplementation := ImplementationOf(mMethod, ParameterPosition(AParams, AParam, AName), AName);
  if mImplementation <> nil then
  begin
    Result := not ContainsKind(mImplementation, TSyntaxKind.WithStatement) and
      not RedeclaresInBody(mImplementation, AName);
    AEdits := AEdits + NameTokens(mImplementation.StartOffset, mImplementation.EndOffset, AName, []);
    AScopes := AScopes + [Point(mImplementation.StartOffset, mImplementation.EndOffset)];
  end;
end;

procedure TNamingCheck.Visit(ANode: TSyntaxNode);
var
  mBody: TSyntaxNode;
begin
  case ANode.Kind of
    TSyntaxKind.VarDecl:
      VisitVarDecl(ANode);
    TSyntaxKind.InlineVar:
      CheckLocals(ANode);
    TSyntaxKind.InlineConst:
      CheckLocal(ANode, Trim(ANode.Name), TRuleNamingKind.Constant);
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
      CheckInlineFor(ANode);
    TSyntaxKind.Field:
      begin
        mBody := OwnerType(ANode);
        if mBody <> nil then
        begin
          CheckFields(mBody, ANode);
        end;
      end;
    TSyntaxKind.ConstDecl:
      VisitConstDecl(ANode);
    TSyntaxKind.Parameters:
      CheckParameters(ANode);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Lokale Variablen einer Deklaration; Schleifenzähler aus einem Buchstaben bleiben.</summary>
procedure TNamingCheck.CheckLocals(ADecl: TSyntaxNode);
var
  mName: string;
begin
  for mName in SplitString(ADecl.Name, ',') do
  begin
    if Length(Trim(mName)) > 1 then
    begin
      CheckLocal(ADecl, Trim(mName), TRuleNamingKind.Local);
    end;
  end;
end;

procedure TNamingCheck.CheckFields(ABody, ADecl: TSyntaxNode);
var
  mName: string;
begin
  for mName in SplitString(ADecl.Name, ',') do
  begin
    CheckMember(ABody, ADecl, Trim(mName), TRuleNamingKind.Field);
  end;
end;

procedure TNamingCheck.VisitVarDecl(ANode: TSyntaxNode);
var
  mSection: TSyntaxNode;
begin
  mSection := ANode.Parent;
  if (mSection = nil) or (mSection.Parent = nil) then
  begin
    Exit;
  end;
  if mSection.Parent.Kind = TSyntaxKind.RoutineDecl then
  begin
    CheckLocals(ANode);
  end
  else if mSection.Parent.Kind in cTypeBodies then
  begin
    CheckFields(mSection.Parent, ANode);
  end;
end;

procedure TNamingCheck.VisitConstDecl(ANode: TSyntaxNode);
var
  mSection: TSyntaxNode;
begin
  mSection := ANode.Parent;
  if (mSection = nil) or (mSection.Kind <> TSyntaxKind.ConstSection) or (mSection.Name <> 'const') or
    (mSection.Parent = nil) then
  begin
    Exit;
  end;
  if mSection.Parent.Kind = TSyntaxKind.RoutineDecl then
  begin
    CheckLocal(ANode, ANode.Name, TRuleNamingKind.Constant);
  end
  else if mSection.Parent.Kind in cTypeBodies then
  begin
    CheckMember(mSection.Parent, ANode, ANode.Name, TRuleNamingKind.Constant);
  end
  else
  begin
    CheckUnitConstant(ANode);
  end;
end;

procedure TNamingCheck.Run;
var
  mFound: TList<TSyntaxNode>;
  mSelf_: TNamingCheck;
begin
  mFound := TList<TSyntaxNode>.Create;
  try
    FRoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if ANode.Kind = TSyntaxKind.RoutineDecl then
        begin
          mFound.Add(ANode);
        end;
        Result := True;
      end);
    FRoutineDecls := mFound.ToArray;
  finally
    mFound.Free;
  end;
  mSelf_ := Self;
  FRoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      mSelf_.Visit(ANode);
      Result := True;
    end);
end;

procedure TNamingPrefixRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TNamingCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mCheck := TNamingCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

procedure RegisterNamingRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TNamingPrefixRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Naming', cTexts);

end.
