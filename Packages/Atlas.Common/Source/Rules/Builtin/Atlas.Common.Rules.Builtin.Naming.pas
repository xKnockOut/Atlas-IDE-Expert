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
// Sender, Self und Result, Namen nach "ignore" (Muster mit * und ?), Felder im
// published-Abschnitt und Felder vor dem ersten Sichtbarkeitsabschnitt eines
// Formulars, Frames oder Datenmoduls (Komponenten), Parameter von Methoden
// mit override oder message, von published-Methoden, von Ereignis-Handlern
// (ein Parameter heißt Sender) und von Methoden, die eine Interface-Methode
// erfüllen: Sie behalten die Namen ihrer Vorlage. Bleibt offen, ob eine
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
// Datei sichtbar ist (öffentliche Felder, Konstanten im interface-Abschnitt).

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  NamingPrefixRuleId = 'naming-prefix';

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

  TNamingPrefixRule = class(TInterfacedObject, IRule)
  public const
    RuleId = NamingPrefixRuleId;
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  DefaultNamingPrefixes: array[TRuleNamingKind] of string = ('m', 'F', 'A', 'c');

/// <summary>Präfix für Umbenennungen anderer Regeln (shadowed-name): Vorgabe der Projektdatei, wenn sie eines
/// setzt, sonst ADefault.</summary>
function NamingPrefixFor(const AContext: TRuleContext; AKind: TRuleNamingKind; const ADefault: string): string;

procedure RegisterNamingRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Unused;

const
  OptionKeys: array[TRuleNamingKind] of string = ('local', 'field', 'parameter', 'constant');
  KindTexts: array[TRuleNamingKind] of string = ('Lokale Variable', 'Feld', 'Parameter', 'Konstante');
  TypeBodies = [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType, TSyntaxKind.InterfaceType,
    TSyntaxKind.HelperType];
  // Ohne Index: Komponenten stehen vor dem ersten Sichtbarkeitsabschnitt dieser Klassen.
  ComponentHosts: array[0..2] of string = ('Form', 'Frame', 'DataModule');

function NamingPrefixFor(const AContext: TRuleContext; AKind: TRuleNamingKind; const ADefault: string): string;
begin
  Result := ADefault;
  if AContext.Naming.Known[AKind] and (AContext.Naming.Prefixes[AKind] <> '') then
    Result := AContext.Naming.Prefixes[AKind];
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
  Kind: TRuleNamingKind;
  Value: TJSONValue;
  Member: TJSONValue;
begin
  for Kind := Low(TRuleNamingKind) to High(TRuleNamingKind) do
    if AContext.Naming.Known[Kind] then
      Result.Prefixes[Kind] := AContext.Naming.Prefixes[Kind]
    else
      Result.Prefixes[Kind] := DefaultNamingPrefixes[Kind];
  Result.Ignore := TRuleOptions.Strings(AContext.Options, 'ignore', nil);
  if AContext.Options = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AContext.Options);
  try
    if not (Value is TJSONObject) then
      Exit;
    for Kind := Low(TRuleNamingKind) to High(TRuleNamingKind) do
    begin
      Member := TJSONObject(Value).GetValue(OptionKeys[Kind]);
      // TJSONNumber erbt von TJSONString; auch ein leerer Text ist eine Vorgabe (Art aus).
      if (Member is TJSONString) and not (Member is TJSONNumber) then
        Result.Prefixes[Kind] := Trim(Member.Value);
    end;
  finally
    Value.Free;
  end;
end;

class function TNamingConvention.Follows(const AName, APrefix: string): Boolean;
begin
  if APrefix = '' then
    Exit(True);
  if (Length(AName) <= Length(APrefix)) or not StartsStr(APrefix, AName) then
    Exit(False);
  Result := not IsLetter(APrefix[Length(APrefix)]) or IsUpperOrDigit(AName[Length(APrefix) + 1]);
end;

class function TNamingConvention.Expected(const AName, APrefix: string): string;
begin
  if (APrefix <> '') and IsLetter(APrefix[Length(APrefix)]) and (AName <> '') then
    Result := APrefix + AnsiUpperCase(AName[1]) + Copy(AName, 2, MaxInt)
  else
    Result := APrefix + AName;
end;

{ TNamingPrefixRule }

function TNamingPrefixRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(RuleId, TRuleSeverity.Hint, 'Name ohne das Präfix seiner Art', True);
end;

type
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
    function ShortName(const AName: string): string;
    function BareTypeName(const AName: string): string;
    function TokenIn(AIndex: Integer; ANode: TSyntaxNode): Boolean;
    /// <summary>Token des Namens in [AStart, AEnd), nicht hinter einem Punkt; hinter AQualifier. (Self, Typname)
    /// doch.</summary>
    function NameTokens(AStart, AEnd: Integer; const AName: string; const AQualifiers: array of string):
      TArray<Integer>;
    /// <summary>Kommt AName irgendwo hinter einem Punkt vor, dessen Qualifizierer nicht in AQualifiers steht?
    /// </summary>
    function QualifiedElsewhere(const AName: string; const AQualifiers: array of string): Boolean;
    function FirstNameToken(ANode: TSyntaxNode; const AName: string; out AIndex: Integer): Boolean;
    function OccursInFile(const AName: string): Boolean;
    function InAny(AIndex: Integer; const ANodes: TArray<TSyntaxNode>): Boolean;
    function ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
    /// <summary>Deklariert ein Knoten unter ANode außer ADeclaration den Namen (Variable, Parameter, Konstante)?
    /// </summary>
    function Redeclares(ANode, ADeclaration: TSyntaxNode; const AName: string): Boolean;
    function DeclaresName(ANode: TSyntaxNode; const AName: string): Boolean;
    /// <summary>Deklariert der Rumpf von ARoutine (ohne Kopf) den Namen neu?</summary>
    function RedeclaresInBody(ARoutine: TSyntaxNode; const AName: string): Boolean;
    function IsInlineFor(AFor: TSyntaxNode): Boolean;
    function EnclosingScope(ANode: TSyntaxNode): TSyntaxNode;
    function OwnerType(ANode: TSyntaxNode): TSyntaxNode;
    function TypeDeclOf(ABody: TSyntaxNode): TSyntaxNode;
    function IsComponentHost(ABody: TSyntaxNode): Boolean;
    function VisibilityOf(ABody, AMember: TSyntaxNode; out AImplicit: Boolean): string;
    function MethodsOf(const ATypeName: string): TArray<TSyntaxNode>;
    function ParameterNames(AParams: TSyntaxNode): TArray<string>;
    function ParameterPosition(AParams, AParam: TSyntaxNode; const AName: string): Integer;
    function HasDirective(AHeader: TSyntaxNode; const ANames: array of string): Boolean;
    function ImplementsInterface(ABody: TSyntaxNode; const AMethod: string; out AKnown: Boolean): Boolean;
    function IsForwardOrInterface(ARoutine: TSyntaxNode): Boolean;
    function ImplementationOf(const AQualified: string; APosition: Integer; const AName: string): TSyntaxNode;
    function DeclarationOf(ARoutine: TSyntaxNode): TSyntaxNode;
    function EditsFor(const AIndexes: TArray<Integer>; const ANewName: string): TArray<TRuleEdit>;
    procedure Report(AKind: TRuleNamingKind; ADeclaration: TSyntaxNode; const AName: string;
      const AEdits: TArray<Integer>; ACanFix: Boolean);
    function Wanted(AKind: TRuleNamingKind; const AName: string): Boolean;
    procedure CheckLocal(ADecl: TSyntaxNode; const AName: string; AKind: TRuleNamingKind);
    procedure CheckInlineFor(AFor: TSyntaxNode);
    procedure CheckMember(ABody, ADecl: TSyntaxNode; const AName: string; AKind: TRuleNamingKind);
    procedure CheckUnitConstant(ADecl: TSyntaxNode);
    procedure CheckParameters(AParams: TSyntaxNode);
    procedure Visit(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

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
end;

function TNamingCheck.ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function TNamingCheck.BareTypeName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

function TNamingCheck.TokenIn(AIndex: Integer; ANode: TSyntaxNode): Boolean;
begin
  Result := (FTokens[AIndex].Offset >= ANode.StartOffset) and (FTokens[AIndex].Offset < ANode.EndOffset);
end;

function TNamingCheck.NameTokens(AStart, AEnd: Integer; const AName: string; const AQualifiers: array of string):
  TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(FTokens) do
  begin
    if FTokens[Index].Offset >= AEnd then
      Break;
    if (FTokens[Index].Offset < AStart) or
      not (FTokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) or
      not SameText(FTokens[Index].Text, AName) then
      Continue;
    // Obj.Name ist ein anderes Symbol; Self.Name und TTyp.Name nur bei Mitgliedern.
    if (Index > 0) and FTokens[Index - 1].IsSymbol('.') and
      not ((Index > 1) and MatchText(FTokens[Index - 2].Text, AQualifiers)) then
      Continue;
    Result := Result + [Index];
  end;
end;

function TNamingCheck.QualifiedElsewhere(const AName: string; const AQualifiers: array of string): Boolean;
var
  Index: Integer;
begin
  for Index := 2 to High(FTokens) do
    if (FTokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      SameText(FTokens[Index].Text, AName) and FTokens[Index - 1].IsSymbol('.') and
      not MatchText(FTokens[Index - 2].Text, AQualifiers) then
      Exit(True);
  Result := False;
end;

function TNamingCheck.FirstNameToken(ANode: TSyntaxNode; const AName: string; out AIndex: Integer): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to High(FTokens) do
  begin
    if FTokens[Index].Offset >= ANode.EndOffset then
      Break;
    if (FTokens[Index].Offset >= ANode.StartOffset) and
      (FTokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      SameText(FTokens[Index].Text, AName) then
    begin
      AIndex := Index;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TNamingCheck.InAny(AIndex: Integer; const ANodes: TArray<TSyntaxNode>): Boolean;
var
  Node: TSyntaxNode;
begin
  for Node in ANodes do
    if TokenIn(AIndex, Node) then
      Exit(True);
  Result := False;
end;

function TNamingCheck.OccursInFile(const AName: string): Boolean;
var
  Token: TPascalToken;
begin
  for Token in FTokens do
    if (Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and SameText(Token.Text, AName) then
      Exit(True);
  Result := False;
end;

function TNamingCheck.ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  Kind: TSyntaxKind;
begin
  Kind := AKind;
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if AVisited.Kind = Kind then
        Exit(TSyntaxSearchStep.Found);
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

function TNamingCheck.DeclaresName(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Name: string;
begin
  Result := False;
  if ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.ConstDecl,
    TSyntaxKind.Parameter, TSyntaxKind.Field] then
    for Name in SplitString(ANode.Name, ',') do
      if SameText(Trim(Name), AName) then
        Exit(True);
  // for var I (Inline-Schleifenvariable): Der Name steht am for.
  if (ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and SameText(ANode.Name, AName) then
    Result := True;
end;

function TNamingCheck.Redeclares(ANode, ADeclaration: TSyntaxNode; const AName: string): Boolean;
var
  Name: string;
  Declaration: TSyntaxNode;
  Self_: TNamingCheck;
begin
  Name := AName;
  Declaration := ADeclaration;
  Self_ := Self;
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      // Eine for-Schleife über die vorhandene Variable deklariert nichts.
      if (AVisited <> Declaration) and Self_.DeclaresName(AVisited, Name) and
        not ((AVisited.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and
        not Self_.IsInlineFor(AVisited)) then
        Result := TSyntaxSearchStep.Found;
    end) <> nil;
end;

function TNamingCheck.RedeclaresInBody(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to ARoutine.ChildCount - 1 do
    if (ARoutine[Index].Kind <> TSyntaxKind.RoutineHeader) and Redeclares(ARoutine[Index], nil, AName) then
      Exit(True);
  Result := False;
end;

function TNamingCheck.EnclosingScope(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not (Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
    Result := Result.Parent;
end;

function TNamingCheck.OwnerType(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not (Result.Kind in TypeBodies) do
  begin
    if Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod, TSyntaxKind.TypeDecl] then
      Exit(nil);
    Result := Result.Parent;
  end;
end;

function TNamingCheck.TypeDeclOf(ABody: TSyntaxNode): TSyntaxNode;
begin
  Result := ABody.Parent;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.TypeDecl) do
    Result := Result.Parent;
end;

function TNamingCheck.IsComponentHost(ABody: TSyntaxNode): Boolean;
var
  Index: Integer;
  Host: string;
begin
  if FContext.FormText <> '' then
    Exit(True);
  for Index := 0 to ABody.ChildCount - 1 do
    if ABody[Index].Kind = TSyntaxKind.TypeReference then
    begin
      for Host in ComponentHosts do
        if EndsText(Host, BareTypeName(ABody[Index].Name)) then
          Exit(True);
      Break;
    end;
  Result := False;
end;

function TNamingCheck.VisibilityOf(ABody, AMember: TSyntaxNode; out AImplicit: Boolean): string;
var
  Index: Integer;
  Member: TSyntaxNode;
begin
  // Mitglied direkt im Typ oder in einem class var-Abschnitt bzw. varianten Teil darunter.
  Member := AMember;
  while (Member.Parent <> nil) and (Member.Parent <> ABody) do
    Member := Member.Parent;
  Result := '';
  AImplicit := True;
  for Index := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[Index] = Member then
      Break;
    if ABody[Index].Kind = TSyntaxKind.Visibility then
    begin
      Result := LowerCase(ABody[Index].Name);
      AImplicit := False;
    end;
  end;
end;

function TNamingCheck.MethodsOf(const ATypeName: string): TArray<TSyntaxNode>;
var
  Routine: TSyntaxNode;
  Owner: string;
begin
  Result := nil;
  for Routine in FRoutineDecls do
    if Pos('.', Routine.Name) > 0 then
    begin
      Owner := Copy(Routine.Name, 1, LastDelimiter('.', Routine.Name) - 1);
      if SameText(BareTypeName(Owner), ATypeName) then
        Result := Result + [Routine];
    end;
end;

function TNamingCheck.ParameterNames(AParams: TSyntaxNode): TArray<string>;
var
  Index: Integer;
  Name: string;
begin
  Result := nil;
  for Index := 0 to AParams.ChildCount - 1 do
    if AParams[Index].Kind = TSyntaxKind.Parameter then
      for Name in SplitString(AParams[Index].Name, ',') do
        if Trim(Name) <> '' then
          Result := Result + [Trim(Name)];
end;

function TNamingCheck.ParameterPosition(AParams, AParam: TSyntaxNode; const AName: string): Integer;
var
  Index: Integer;
  Name: string;
begin
  Result := 0;
  for Index := 0 to AParams.ChildCount - 1 do
    if AParams[Index].Kind = TSyntaxKind.Parameter then
      for Name in SplitString(AParams[Index].Name, ',') do
        if Trim(Name) <> '' then
        begin
          if (AParams[Index] = AParam) and SameText(Trim(Name), AName) then
            Exit;
          Inc(Result);
        end;
  Result := -1;
end;

function TNamingCheck.HasDirective(AHeader: TSyntaxNode; const ANames: array of string): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to AHeader.ChildCount - 1 do
    if (AHeader[Index].Kind = TSyntaxKind.Directive) and MatchText(AHeader[Index].Name, ANames) then
      Exit(True);
  Result := False;
end;

function TNamingCheck.ImplementsInterface(ABody: TSyntaxNode; const AMethod: string; out AKnown: Boolean): Boolean;
var
  Index, Count: Integer;
  Pending: TList<string>;
  Seen: TList<string>;
  InterfaceName: string;
  Found, Members: TSyntaxNode;
  Location, Member: TSymbolLocation;
  Resolved: Boolean;
begin
  Result := False;
  AKnown := True;
  if ABody.Kind <> TSyntaxKind.ClassType then
    Exit;
  Pending := TList<string>.Create;
  Seen := TList<string>.Create;
  try
    // Ab dem zweiten Eintrag der Liste stehen Interfaces; der erste ist eines, wenn er wie eines heißt.
    Count := 0;
    for Index := 0 to ABody.ChildCount - 1 do
      if ABody[Index].Kind = TSyntaxKind.TypeReference then
      begin
        InterfaceName := BareTypeName(ABody[Index].Name);
        if (Count > 0) or ((Length(InterfaceName) > 1) and (InterfaceName[1] = 'I') and
          IsUpperOrDigit(InterfaceName[2])) then
          Pending.Add(InterfaceName);
        Inc(Count);
      end;
    // Auch die Vorfahren der Interfaces (IFoo = interface(IBar)).
    while Pending.Count > 0 do
    begin
      InterfaceName := Pending[Pending.Count - 1];
      Pending.Delete(Pending.Count - 1);
      if Seen.IndexOf(LowerCase(InterfaceName)) >= 0 then
        Continue;
      Seen.Add(LowerCase(InterfaceName));
      Resolved := False;
      Found := FRoot.Search(
        function(AVisited: TSyntaxNode): TSyntaxSearchStep
        begin
          Result := TSyntaxSearchStep.Descend;
          if (AVisited.Kind = TSyntaxKind.TypeDecl) and SameText(AVisited.Name, InterfaceName) and
            (AVisited.FindChild(TSyntaxKind.InterfaceType) <> nil) then
            Result := TSyntaxSearchStep.Found;
        end);
      if Found <> nil then
      begin
        Resolved := True;
        Members := Found.FindChild(TSyntaxKind.InterfaceType);
        for Index := 0 to Members.ChildCount - 1 do
          if (Members[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(Members[Index].Name, AMethod) then
            Exit(True)
          else if Members[Index].Kind = TSyntaxKind.TypeReference then
            Pending.Add(BareTypeName(Members[Index].Name));
      end
      else if FIndex <> nil then
        for Location in FIndex.FindSymbols(InterfaceName) do
          if Location.Symbol.Kind = TIndexSymbolKind.InterfaceType then
          begin
            Resolved := True;
            for Member in FIndex.FindSymbols(AMethod) do
              if SameText(Member.Symbol.Container, InterfaceName) then
                Exit(True);
            for Index := 0 to High(Location.Symbol.Ancestors) do
              Pending.Add(BareTypeName(Location.Symbol.Ancestors[Index]));
          end;
      // IInterface und IUnknown haben nur _AddRef, _Release und QueryInterface.
      if not Resolved and not MatchText(InterfaceName, ['IInterface', 'IUnknown', 'IDispatch']) then
        AKnown := False;
    end;
  finally
    Seen.Free;
    Pending.Free;
  end;
end;

function TNamingCheck.IsForwardOrInterface(ARoutine: TSyntaxNode): Boolean;
begin
  Result := ARoutine.FindChild(TSyntaxKind.Block) = nil;
end;

function TNamingCheck.DeclarationOf(ARoutine: TSyntaxNode): TSyntaxNode;
var
  Routine: TSyntaxNode;
begin
  // Routine mit Rumpf ohne Punkt: Deklaration im interface-Abschnitt oder forward davor.
  for Routine in FRoutineDecls do
    if (Routine <> ARoutine) and IsForwardOrInterface(Routine) and SameText(Routine.Name, ARoutine.Name) and
      (EnclosingScope(Routine) = EnclosingScope(ARoutine)) then
      Exit(Routine);
  Result := nil;
end;

function TNamingCheck.ImplementationOf(const AQualified: string; APosition: Integer; const AName: string):
  TSyntaxNode;
var
  Routine, Header, Params: TSyntaxNode;
  Names: TArray<string>;
  TypeName, Method: string;
begin
  TypeName := '';
  Method := AQualified;
  if Pos('.', AQualified) > 0 then
  begin
    TypeName := BareTypeName(Copy(AQualified, 1, LastDelimiter('.', AQualified) - 1));
    Method := ShortName(AQualified);
  end;
  for Routine in FRoutineDecls do
  begin
    if IsForwardOrInterface(Routine) then
      Continue;
    if TypeName <> '' then
    begin
      if (Pos('.', Routine.Name) = 0) or not SameText(ShortName(Routine.Name), Method) or
        not SameText(BareTypeName(Copy(Routine.Name, 1, LastDelimiter('.', Routine.Name) - 1)), TypeName) then
        Continue;
    end
    else if not SameText(Routine.Name, Method) then
      Continue;
    Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
    if Header = nil then
      Continue;
    Params := Header.FindChild(TSyntaxKind.Parameters);
    if Params = nil then
      Continue;
    Names := ParameterNames(Params);
    // Überladungen: derselbe Name an derselben Stelle.
    if (APosition < Length(Names)) and SameText(Names[APosition], AName) then
      Exit(Routine);
  end;
  Result := nil;
end;

function TNamingCheck.EditsFor(const AIndexes: TArray<Integer>; const ANewName: string): TArray<TRuleEdit>;
var
  Index: Integer;
begin
  Result := nil;
  for Index in AIndexes do
    Result := Result + [TRuleEdit.Create(TTextRange.Create(FTokens[Index].StartPos, FTokens[Index].EndPos),
      ANewName)];
end;

function TNamingCheck.Wanted(AKind: TRuleNamingKind; const AName: string): Boolean;
var
  Pattern: string;
begin
  Result := (FConvention.Prefixes[AKind] <> '') and (AName <> '') and not MatchText(AName, ['Self', 'Result']) and
    not TNamingConvention.Follows(AName, FConvention.Prefixes[AKind]);
  if Result then
    for Pattern in FConvention.Ignore do
      if MatchesWildcard(AName, Pattern) then
        Exit(False);
end;

procedure TNamingCheck.Report(AKind: TRuleNamingKind; ADeclaration: TSyntaxNode; const AName: string;
  const AEdits: TArray<Integer>; ACanFix: Boolean);
var
  NewName, Message: string;
  At: Integer;
  Fixes: TArray<TRuleFix>;
begin
  if not FirstNameToken(ADeclaration, AName, At) then
    Exit;
  NewName := TNamingConvention.Expected(AName, FConvention.Prefixes[AKind]);
  Message := Format('%s %s ohne Präfix %s (erwartet: %s)', [KindTexts[AKind], AName, FConvention.Prefixes[AKind],
    NewName]);
  Fixes := nil;
  if ACanFix and (Length(AEdits) > 0) and not OccursInFile(NewName) then
    Fixes := [TRuleFix.Create(Format('In %s umbenennen', [NewName]), EditsFor(AEdits, NewName))];
  FReport.Add(TTextRange.Create(FTokens[At].StartPos, FTokens[At].EndPos), Message, TRuleConfidence.High, Fixes);
end;

procedure TNamingCheck.CheckLocal(ADecl: TSyntaxNode; const AName: string; AKind: TRuleNamingKind);
var
  Scope: TSyntaxNode;
  Start, Stop: Integer;
  CanFix: Boolean;
begin
  if not Wanted(AKind, AName) then
    Exit;
  Scope := EnclosingScope(ADecl);
  if Scope = nil then
    Exit;
  // Inline-Deklarationen gelten ab der Deklaration bis zum Ende ihres Blocks.
  if ADecl.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
  begin
    Start := ADecl.StartOffset;
    Stop := ADecl.Parent.EndOffset;
  end
  else
  begin
    Start := Scope.StartOffset;
    Stop := Scope.EndOffset;
  end;
  CanFix := not ContainsKind(Scope, TSyntaxKind.WithStatement) and not Redeclares(Scope, ADecl, AName);
  Report(AKind, ADecl, AName, NameTokens(Start, Stop, AName, []), CanFix);
end;

function TNamingCheck.IsInlineFor(AFor: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 0 to High(FTokens) - 1 do
    if FTokens[Index].Offset >= AFor.StartOffset then
      Exit(FTokens[Index].IsKeyword('for') and FTokens[Index + 1].IsKeyword('var'));
end;

procedure TNamingCheck.CheckInlineFor(AFor: TSyntaxNode);
var
  CanFix: Boolean;
  Scope: TSyntaxNode;
begin
  if (Length(AFor.Name) = 1) or not IsInlineFor(AFor) or not Wanted(TRuleNamingKind.Local, AFor.Name) then
    Exit;
  Scope := EnclosingScope(AFor);
  CanFix := (Scope <> nil) and not ContainsKind(AFor, TSyntaxKind.WithStatement) and
    not Redeclares(AFor, AFor, AFor.Name);
  Report(TRuleNamingKind.Local, AFor, AFor.Name, NameTokens(AFor.StartOffset, AFor.EndOffset, AFor.Name, []),
    CanFix);
end;

procedure TNamingCheck.CheckMember(ABody, ADecl: TSyntaxNode; const AName: string; AKind: TRuleNamingKind);
var
  Visibility, TypeName: string;
  Implicit, CanFix: Boolean;
  TypeDecl, Method: TSyntaxNode;
  Methods: TArray<TSyntaxNode>;
  Edits: TArray<Integer>;
  Index: Integer;
begin
  Visibility := VisibilityOf(ABody, ADecl, Implicit);
  // Komponenten und gestreamte Felder: Ihre Namen stehen in der Formulardatei.
  if (AKind = TRuleNamingKind.Field) and (ABody.Kind = TSyntaxKind.ClassType) and
    ((Visibility = 'published') or (Implicit and IsComponentHost(ABody))) then
    Exit;
  if not Wanted(AKind, AName) then
    Exit;
  TypeDecl := TypeDeclOf(ABody);
  CanFix := (TypeDecl <> nil) and (ABody.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType,
    TSyntaxKind.ObjectType]) and ((Visibility = 'private') or (Visibility = 'strict private'));
  Edits := nil;
  if CanFix then
  begin
    TypeName := BareTypeName(TypeDecl.Name);
    // Obj.Name eines anderen Objekts derselben Klasse ließe sich nicht sicher zuordnen.
    CanFix := not QualifiedElsewhere(AName, ['Self', TypeName]);
    Edits := NameTokens(ABody.StartOffset, ABody.EndOffset, AName, ['Self', TypeName]);
    Methods := MethodsOf(TypeName);
    for Method in Methods do
      if ContainsKind(Method, TSyntaxKind.WithStatement) or RedeclaresInBody(Method, AName) then
        CanFix := False;
    // Ab dem Ende der Klasse: Methoden (unqualifiziert, Self.Name) und TTyp.Name überall.
    for Index := 0 to High(FTokens) do
      if (FTokens[Index].Offset >= ABody.EndOffset) and SameText(FTokens[Index].Text, AName) and
        (FTokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
        ((FTokens[Index - 1].IsSymbol('.') and MatchText(FTokens[Index - 2].Text, ['Self', TypeName])) or
        (not FTokens[Index - 1].IsSymbol('.') and InAny(Index, Methods))) then
        Edits := Edits + [Index];
  end;
  Report(AKind, ADecl, AName, Edits, CanFix);
end;

procedure TNamingCheck.CheckUnitConstant(ADecl: TSyntaxNode);
var
  Section: TSyntaxNode;
  CanFix: Boolean;
begin
  if not Wanted(TRuleNamingKind.Constant, ADecl.Name) then
    Exit;
  Section := ADecl.Parent;
  while (Section <> nil) and not (Section.Kind in [TSyntaxKind.InterfaceSection,
    TSyntaxKind.ImplementationSection]) do
    Section := Section.Parent;
  // Im interface-Abschnitt sehen andere Units die Konstante; dort keine Korrektur. Verdeckt eine Routine den
  // Namen, wäre das Umbenennen aller Vorkommen falsch.
  CanFix := ((Section = nil) or (Section.Kind = TSyntaxKind.ImplementationSection)) and
    not ContainsKind(FRoot, TSyntaxKind.WithStatement) and not Redeclares(FRoot, ADecl, ADecl.Name);
  Report(TRuleNamingKind.Constant, ADecl, ADecl.Name, NameTokens(ADecl.StartOffset, FRoot.EndOffset, ADecl.Name,
    []), CanFix);
end;

procedure TNamingCheck.CheckParameters(AParams: TSyntaxNode);
var
  Owner, Header, Body, Scope, Routine, Implementation_: TSyntaxNode;
  Names: TArray<string>;
  Index, Position: Integer;
  Name, Method, Visibility: string;
  Implicit, Known, CanFix: Boolean;
  Edits: TArray<Integer>;
  Param: TSyntaxNode;
begin
  Names := ParameterNames(AParams);
  // Ereignis-Handler: Die Namen gibt der Ereignistyp vor (FormClose(Sender; var Action)).
  for Name in Names do
    if SameText(Name, 'Sender') then
      Exit;
  Owner := AParams.Parent;
  if Owner = nil then
    Exit;
  Header := nil;
  Body := nil;
  Scope := nil;
  Implementation_ := nil;
  case Owner.Kind of
    TSyntaxKind.RoutineHeader:
      begin
        Header := Owner;
        if (Owner.Parent <> nil) and (Owner.Parent.Kind in TypeBodies) then
        begin
          // Methode in der Typdeklaration.
          Body := Owner.Parent;
          if HasDirective(Header, ['override', 'message']) then
            Exit;
          Visibility := VisibilityOf(Body, Header, Implicit);
          if Visibility = 'published' then
            Exit;
          if ImplementsInterface(Body, Header.Name, Known) or not Known then
            Exit;
        end
        else if (Owner.Parent <> nil) and (Owner.Parent.Kind = TSyntaxKind.RoutineDecl) then
        begin
          Routine := Owner.Parent;
          // Implementierung einer Methode oder einer anderswo deklarierten Routine: dort gemeldet.
          if not IsForwardOrInterface(Routine) and ((Pos('.', Routine.Name) > 0) or (DeclarationOf(Routine) <> nil))
            then
            Exit;
          if not IsForwardOrInterface(Routine) then
            Scope := Routine;
        end
        else
          Exit;
      end;
    TSyntaxKind.AnonymousMethod:
      Scope := Owner;
    TSyntaxKind.ProcedureType:
      ;
  else
    Exit;
  end;
  for Index := 0 to AParams.ChildCount - 1 do
  begin
    Param := AParams[Index];
    if Param.Kind <> TSyntaxKind.Parameter then
      Continue;
    for Name in SplitString(Param.Name, ',') do
    begin
      if not Wanted(TRuleNamingKind.Parameter, Trim(Name)) then
        Continue;
      Edits := NameTokens(Param.StartOffset, Param.EndOffset, Trim(Name), []);
      CanFix := True;
      if Scope <> nil then
      begin
        // Rumpf der Routine bzw. der anonymen Methode (ohne die Parameterliste selbst).
        CanFix := not ContainsKind(Scope, TSyntaxKind.WithStatement) and not Redeclares(Scope, Param, Trim(Name));
        Edits := Edits + NameTokens(AParams.EndOffset, Scope.EndOffset, Trim(Name), []);
      end
      else if Header <> nil then
      begin
        // Deklaration: die Implementierung mit demselben Parameter an derselben Stelle umbenennen.
        Position := ParameterPosition(AParams, Param, Trim(Name));
        Method := Header.Name;
        if Body <> nil then
          Method := BareTypeName(TypeDeclOf(Body).Name) + '.' + Header.Name;
        Implementation_ := ImplementationOf(Method, Position, Trim(Name));
        if Implementation_ <> nil then
        begin
          CanFix := not ContainsKind(Implementation_, TSyntaxKind.WithStatement) and
            not RedeclaresInBody(Implementation_, Trim(Name));
          Edits := Edits + NameTokens(Implementation_.StartOffset, Implementation_.EndOffset, Trim(Name), []);
        end;
      end;
      Report(TRuleNamingKind.Parameter, Param, Trim(Name), Edits, CanFix);
    end;
  end;
end;

procedure TNamingCheck.Visit(ANode: TSyntaxNode);
var
  Name: string;
  Section, Body: TSyntaxNode;
begin
  case ANode.Kind of
    TSyntaxKind.VarDecl:
      begin
        Section := ANode.Parent;
        if (Section = nil) or (Section.Parent = nil) then
          Exit;
        if Section.Parent.Kind = TSyntaxKind.RoutineDecl then
        begin
          for Name in SplitString(ANode.Name, ',') do
            // Schleifenzähler aus einem Buchstaben.
            if Length(Trim(Name)) > 1 then
              CheckLocal(ANode, Trim(Name), TRuleNamingKind.Local);
        end
        else if Section.Parent.Kind in TypeBodies then
          for Name in SplitString(ANode.Name, ',') do
            CheckMember(Section.Parent, ANode, Trim(Name), TRuleNamingKind.Field);
      end;
    TSyntaxKind.InlineVar:
      for Name in SplitString(ANode.Name, ',') do
        if Length(Trim(Name)) > 1 then
          CheckLocal(ANode, Trim(Name), TRuleNamingKind.Local);
    TSyntaxKind.InlineConst:
      CheckLocal(ANode, Trim(ANode.Name), TRuleNamingKind.Constant);
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
      CheckInlineFor(ANode);
    TSyntaxKind.Field:
      begin
        Body := OwnerType(ANode);
        if Body <> nil then
          for Name in SplitString(ANode.Name, ',') do
            CheckMember(Body, ANode, Trim(Name), TRuleNamingKind.Field);
      end;
    TSyntaxKind.ConstDecl:
      begin
        Section := ANode.Parent;
        if (Section = nil) or (Section.Kind <> TSyntaxKind.ConstSection) or (Section.Name <> 'const') or
          (Section.Parent = nil) then
          Exit;
        if Section.Parent.Kind = TSyntaxKind.RoutineDecl then
          CheckLocal(ANode, ANode.Name, TRuleNamingKind.Constant)
        else if Section.Parent.Kind in TypeBodies then
          CheckMember(Section.Parent, ANode, ANode.Name, TRuleNamingKind.Constant)
        else
          CheckUnitConstant(ANode);
      end;
    TSyntaxKind.Parameters:
      CheckParameters(ANode);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TNamingCheck.Run;
var
  Found: TList<TSyntaxNode>;
  Self_: TNamingCheck;
begin
  Found := TList<TSyntaxNode>.Create;
  try
    FRoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if ANode.Kind = TSyntaxKind.RoutineDecl then
          Found.Add(ANode);
        Result := True;
      end);
    FRoutineDecls := Found.ToArray;
  finally
    Found.Free;
  end;
  Self_ := Self;
  FRoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Self_.Visit(ANode);
      Result := True;
    end);
end;

procedure TNamingPrefixRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TNamingCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Check := TNamingCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

procedure RegisterNamingRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TNamingPrefixRule.Create);
end;

end.
