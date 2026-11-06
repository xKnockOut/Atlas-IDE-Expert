unit Atlas.Common.Rules.Builtin.Inheritance.OverrideCase;

// Regel override-case-mismatch aus Atlas.Common.Rules.Builtin.Inheritance (#1021, Standard aus): override anders
// geschrieben als der Vorfahr (H2365) oder weniger sichtbar (H2269), Getter/Setter anders geschrieben, inline-Methode
// greift auf ein weniger sichtbares Mitglied zu.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TOverrideCaseMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  OverrideCaseMismatchRuleId = 'override-case-mismatch';

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
  Atlas.Common.Rules.Builtin.Naming,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInheritanceOverrideCaseText = (Title, Spelling, TakeSpelling, LessVisible, AccessorName, RenameTo,
    InlineVisibility);

const
  cTexts: array[TInheritanceOverrideCaseText] of TAtlasText = (
    (De: 'Schreibweise oder Sichtbarkeit weicht vom Vorfahren ab';
     En: 'Spelling or visibility differs from the ancestor'),
    (De: 'Schreibweise weicht von %s.%s ab (wie H2365).'; En: 'Spelling differs from %s.%s (like H2365).'),
    (De: 'Schreibweise vom Vorfahr übernehmen'; En: 'Take spelling from the ancestor'),
    (De: '%s.%s ist %s und damit weniger sichtbar als %s.%s (%s) (wie H2269).';
     En: '%s.%s is %s and thus less visible than %s.%s (%s) (like H2269).'),
    (De: 'Die Zugriffsmethode %s.%s sollte %s.%s geschrieben werden.';
     En: 'The access method %s.%s should be written %s.%s.'),
    (De: 'In %s umbenennen'; En: 'Rename to %s'),
    (De: 'Die inline-Methode %s.%s ist %s, greift aber auf %s (%s) zu.';
     En: 'The inline method %s.%s is %s but accesses %s (%s).'));

{$SCOPEDENUMS OFF}

{ TOverrideCaseMismatchRule }

function TOverrideCaseMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OverrideCaseMismatchRuleId, TRuleSeverity.Hint,
    cTexts[TInheritanceOverrideCaseText.Title].Text, True);
end;

/// <summary>Stufe einer Sichtbarkeit: 0 privat, 1 geschützt, 2 öffentlich (public und published). Nur Stufen
/// werden verglichen; private gegen strict protected bleibt offen.</summary>
function VisibilityTier(AVisibility: TIndexVisibility): Integer;
begin
  case AVisibility of
    TIndexVisibility.StrictPrivate, TIndexVisibility.Private:
      Result := 0;
    TIndexVisibility.StrictProtected, TIndexVisibility.Protected:
      Result := 1;
  else
    Result := 2;
  end;
end;

function VisibilityName(AVisibility: TIndexVisibility): string;
begin
  case AVisibility of
    TIndexVisibility.Published:
      Result := 'published';
    TIndexVisibility.Protected:
      Result := 'protected';
    TIndexVisibility.StrictProtected:
      Result := 'strict protected';
    TIndexVisibility.Private:
      Result := 'private';
    TIndexVisibility.StrictPrivate:
      Result := 'strict private';
  else
    Result := 'public';
  end;
end;

type
  /// <summary>Ergebnis einer Suche nach einem Mitglied: nicht da, gefunden, oder keine sichere Aussage (Treffer nur in
  /// einem inaktiven Zweig, bzw. bei Overridden: gleichnamig, aber nicht überschreibbar).</summary>
  TMemberLookup = (Missing, Found, Unknown);

  /// <summary>Prüfung einer Unit für override-case-mismatch: hält Kontext, Token und Vorfahrenkette der gerade
  /// geprüften Klasse, damit die Teilprüfungen ohne lange Parameterlisten auskommen.</summary>
  TOverrideCaseCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FAncestry: TAncestry;
    FTokens: TArray<TPascalToken>;
    FClass: TIndexSymbol;
    FMembers: TArray<TIndexSymbol>;
    FChain: TArray<TSymbolLocation>;
    FObjectMissing: Boolean;
    function TokenRange(AIndex: Integer): TTextRange;
    function TokenFrom(AOffset: Integer): Integer;
    function IsBodyHead(AIndex: Integer; const AOld: string): Boolean;
    function BodyHeadEdits(const AOld, ANew: string): TArray<TRuleEdit>;
    procedure PropertyTokens(const AProperty: TIndexSymbol; out AFirst, ALast: Integer);
    function AccessorEdits(const AProperty: TIndexSymbol; const AOld, ANew: string): TArray<TRuleEdit>;
    function FindVisibleMember(const AName: string; out AHit: TIndexSymbol): TMemberLookup;
    function OverriddenAt(const AOwn: TIndexSymbol; const ALocation: TSymbolLocation;
      out ATarget: TIndexSymbol): TMemberLookup;
    function Overridden(const AOwn: TIndexSymbol; out AOwner: string; out ATarget: TIndexSymbol): Boolean;
    procedure CheckOverride(const AOwn: TIndexSymbol);
    function IsAccessorAt(AIndex: Integer): Boolean;
    function RenameEdits(const AName, AExpected: string): TArray<TRuleEdit>;
    procedure CheckAccessor(const AProperty: TIndexSymbol; AIndex: Integer);
    procedure CheckAccessors(const AProperty: TIndexSymbol);
    function InlineBodyKnown(const AMethod: TIndexSymbol): Boolean;
    function IsMemberToken(AIndex: Integer; const ALocals, AReported: TArray<string>): Boolean;
    procedure CheckInlineBody(const AMethod: TIndexSymbol; ARoutine, ABody: TSyntaxNode; var AReported: TArray<string>);
    procedure CheckInline(const AMethod: TIndexSymbol);
    procedure CheckMember(const AMember: TIndexSymbol);
    procedure CheckClass(const AType: TIndexSymbol);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

/// <summary>Erstes Mitglied AName in ASymbols; mit AFilter werden für Nachfahren unsichtbare übersprungen.</summary>
function LookupIn(const AName: string; const ASymbols: TArray<TIndexSymbol>; const ALocation: TSymbolLocation;
  AFilter: Boolean; out AHit: TIndexSymbol): TMemberLookup;
var
  Symbol: TIndexSymbol;
begin
  AHit := Default(TIndexSymbol);
  Result := TMemberLookup.Missing;
  for Symbol in ASymbols do
  begin
    if not SameText(Symbol.Name, AName) then
    begin
      Continue;
    end;
    if Symbol.Unavailable then
    begin
      Exit(TMemberLookup.Unknown);
    end;
    if not AFilter or not InvisibleToDescendant(ALocation, Symbol) then
    begin
      AHit := Symbol;
      Exit(TMemberLookup.Found);
    end;
  end;
end;

/// <summary>ASymbol kann von AOwn überschrieben werden: virtuell, gleiche Parameterzahl, beide Klassenmethode oder
/// beide nicht.</summary>
function IsOverrideTarget(const ASymbol, AOwn: TIndexSymbol): Boolean;
begin
  Result := ASymbol.IsVirtual and (ASymbol.MaxArgs = AOwn.MaxArgs);
  Result := Result and (StartsText('class ', ASymbol.Signature) = StartsText('class ', AOwn.Signature));
end;

/// <summary>AOwn überschreibt eine virtuelle Methode von TObject aus der Tabelle (System nicht im Index).</summary>
function ObjectVirtual(const AOwn: TIndexSymbol; out ATarget: TIndexSymbol): Boolean;
var
  Name: string;
begin
  ATarget := Default(TIndexSymbol);
  Result := False;
  if AOwn.MaxArgs <> 0 then
  begin
    Exit;
  end;
  for Name in ObjectVirtualNames do
  begin
    if SameText(Name, AOwn.Name) then
    begin
      ATarget.Name := Name;
      ATarget.Visibility := TIndexVisibility.Public;
      Exit(True);
    end;
  end;
end;

/// <summary>ASame, gleichnamig mit der inline-Methode AMethod, ist ebenfalls inline auf derselben Stufe; sonst ist
/// der Rumpf nicht eindeutig zuzuordnen.</summary>
function SameInlineLevel(const ASame, AMethod: TIndexSymbol): Boolean;
begin
  Result := (ASame.Kind = TIndexSymbolKind.Method) and ASame.HasDirective('inline');
  Result := Result and (VisibilityTier(ASame.Visibility) = VisibilityTier(AMethod.Visibility)) and
    not ASame.Unavailable;
end;

/// <summary>Lokale Namen (Parameter, Variablen, Konstanten, Typen, verschachtelte Routinen) der Routine ARoutine;
/// AHasWith, wenn sie ein with enthält.</summary>
procedure CollectLocals(ARoutine: TSyntaxNode; out ALocals: TArray<string>; out AHasWith: Boolean);
var
  Stack: TArray<TSyntaxNode>;
  Node: TSyntaxNode;
  Child: Integer;
begin
  ALocals := nil;
  AHasWith := False;
  Stack := [ARoutine];
  while Stack <> nil do
  begin
    Node := Stack[High(Stack)];
    SetLength(Stack, Length(Stack) - 1);
    if (Node <> ARoutine) and (Node.Kind in [TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl,
      TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.TypeDecl, TSyntaxKind.RoutineDecl]) then
    begin
      ALocals := ALocals + Node.Name.Split([',']);
    end;
    AHasWith := AHasWith or (Node.Kind = TSyntaxKind.WithStatement);
    for Child := 0 to Node.ChildCount - 1 do
    begin
      Stack := Stack + [Node[Child]];
    end;
  end;
end;

/// <summary>Eigener Klassen- oder Record-Typ der Unit auf oberster Ebene.</summary>
function IsOwnType(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType]) and
    (ASymbol.Container = '') and not ASymbol.Unavailable;
end;

{ TOverrideCaseCheck }

constructor TOverrideCaseCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FCache := TRuleDerived.Open(AContext);
  FTokens := TRuleDerived.CodeTokens(FCache, AContext);
  FAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(FCache, AContext));
end;

destructor TOverrideCaseCheck.Destroy;
begin
  FAncestry.Free;
  inherited Destroy;
end;

function TOverrideCaseCheck.TokenRange(AIndex: Integer): TTextRange;
begin
  Result := TTextRange.Create(FTokens[AIndex].StartPos, FTokens[AIndex].EndPos);
end;

/// <summary>Erstes Token ab AOffset; Length(FTokens) ohne.</summary>
function TOverrideCaseCheck.TokenFrom(AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(FTokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if FTokens[Middle].Offset < AOffset then
    begin
      Low := Middle + 1;
    end
    else
    begin
      High := Middle;
    end;
  end;
  Result := Low;
end;

/// <summary>Ab AIndex steht der Rumpfkopf "procedure Klasse.AOld" der geprüften Klasse (AIndex zeigt auf den
/// Klassennamen).</summary>
function TOverrideCaseCheck.IsBodyHead(AIndex: Integer; const AOld: string): Boolean;
begin
  Result := (FTokens[AIndex - 1].Kind = TPascalTokenKind.Keyword) and MatchText(FTokens[AIndex - 1].Text,
    ['procedure', 'function', 'constructor', 'destructor']);
  Result := Result and SameText(FTokens[AIndex].Text, FClass.Name) and FTokens[AIndex + 1].IsSymbol('.');
  Result := Result and (FTokens[AIndex + 2].Kind = TPascalTokenKind.Identifier) and
    SameText(FTokens[AIndex + 2].Text, AOld);
end;

/// <summary>Edits, die den Namen AOld in den Rumpfköpfen der geprüften Klasse durch ANew ersetzen.</summary>
function TOverrideCaseCheck.BodyHeadEdits(const AOld, ANew: string): TArray<TRuleEdit>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 1 to High(FTokens) - 2 do
  begin
    if IsBodyHead(Index, AOld) and (FTokens[Index + 2].Text <> ANew) then
    begin
      Result := Result + [TRuleEdit.Create(TokenRange(Index + 2), ANew)];
    end;
  end;
end;

/// <summary>Token der Property AProperty: vom Namen bis vor das abschließende ";".</summary>
procedure TOverrideCaseCheck.PropertyTokens(const AProperty: TIndexSymbol; out AFirst, ALast: Integer);
begin
  AFirst := 0;
  while (AFirst <= High(FTokens)) and ((FTokens[AFirst].StartPos.Line < AProperty.Range.StartPos.Line) or
    ((FTokens[AFirst].StartPos.Line = AProperty.Range.StartPos.Line) and
    (FTokens[AFirst].StartPos.Character < AProperty.Range.StartPos.Character))) do
  begin
    Inc(AFirst);
  end;
  ALast := AFirst;
  while (ALast < High(FTokens)) and not FTokens[ALast].IsSymbol(';') do
  begin
    Inc(ALast);
  end;
end;

/// <summary>Edits, die hinter read/write der Property AProperty den Namen AOld durch ANew ersetzen.</summary>
function TOverrideCaseCheck.AccessorEdits(const AProperty: TIndexSymbol; const AOld, ANew: string): TArray<TRuleEdit>;
var
  Index, First, Last: Integer;
begin
  Result := nil;
  PropertyTokens(AProperty, First, Last);
  for Index := First + 1 to Last - 1 do
  begin
    if SameText(FTokens[Index].Text, AOld) and MatchText(FTokens[Index - 1].Text, ['read', 'write']) then
    begin
      Result := Result + [TRuleEdit.Create(TokenRange(Index), ANew)];
    end;
  end;
end;

/// <summary>Mitglied AName der eigenen Members oder der nächsten Stufe der Kette, die es dort sichtbar gibt.</summary>
function TOverrideCaseCheck.FindVisibleMember(const AName: string; out AHit: TIndexSymbol): TMemberLookup;
var
  Location: TSymbolLocation;
begin
  Result := LookupIn(AName, FMembers, Default(TSymbolLocation), False, AHit);
  for Location in FChain do
  begin
    if Result <> TMemberLookup.Missing then
    begin
      Exit;
    end;
    Result := LookupIn(AName, FAncestry.Members(Location), Location, True, AHit);
  end;
end;

/// <summary>Die von AOwn überschriebene Methode auf der Stufe ALocation. Unknown, wenn die Suche hier ohne Treffer
/// endet (gleichnamig sichtbar, aber nicht überschreibbar, oder nur in inaktivem Zweig).</summary>
function TOverrideCaseCheck.OverriddenAt(const AOwn: TIndexSymbol; const ALocation: TSymbolLocation;
  out ATarget: TIndexSymbol): TMemberLookup;
var
  Symbol: TIndexSymbol;
begin
  ATarget := Default(TIndexSymbol);
  Result := TMemberLookup.Missing;
  for Symbol in FAncestry.Methods(ALocation) do
  begin
    if not SameText(Symbol.Name, AOwn.Name) then
    begin
      Continue;
    end;
    if Symbol.Unavailable then
    begin
      Exit(TMemberLookup.Unknown);
    end;
    if InvisibleToDescendant(ALocation, Symbol) then
    begin
      Continue;
    end;
    Result := TMemberLookup.Unknown;
    if IsOverrideTarget(Symbol, AOwn) then
    begin
      ATarget := Symbol;
      Exit(TMemberLookup.Found);
    end;
  end;
end;

/// <summary>Die überschriebene Methode: nächste Stufe mit gleichnamiger, sichtbarer, virtueller Methode gleicher
/// Parameterzahl; TObject über die Tabelle, wenn System nicht im Index steht. False ohne sichere Aussage.</summary>
function TOverrideCaseCheck.Overridden(const AOwn: TIndexSymbol; out AOwner: string;
  out ATarget: TIndexSymbol): Boolean;
var
  Location: TSymbolLocation;
  State: TMemberLookup;
begin
  AOwner := '';
  ATarget := Default(TIndexSymbol);
  for Location in FChain do
  begin
    State := OverriddenAt(AOwn, Location, ATarget);
    if State <> TMemberLookup.Missing then
    begin
      AOwner := Location.Symbol.Name;
      Exit(State = TMemberLookup.Found);
    end;
  end;
  Result := FObjectMissing and ObjectVirtual(AOwn, ATarget);
  if Result then
  begin
    AOwner := 'TObject';
  end;
end;

procedure TOverrideCaseCheck.CheckOverride(const AOwn: TIndexSymbol);
var
  Owner: string;
  Target: TIndexSymbol;
begin
  if not Overridden(AOwn, Owner, Target) then
  begin
    Exit;
  end;
  if Target.Name <> AOwn.Name then
  begin
    FReport.Add(AOwn.SelectionRange, cTexts[TInheritanceOverrideCaseText.Spelling].Fmt([Owner, Target.Name]),
      TRuleConfidence.High, [TRuleFix.Create(cTexts[TInheritanceOverrideCaseText.TakeSpelling].Text,
      [TRuleEdit.Create(AOwn.SelectionRange, Target.Name)] + BodyHeadEdits(AOwn.Name, Target.Name))]);
  end;
  // Nur für Klassen im interface-Teil (die Sichtbarkeit sieht man nur dort von außen).
  if FClass.InInterface and (VisibilityTier(AOwn.Visibility) < VisibilityTier(Target.Visibility)) then
  begin
    FReport.Add(AOwn.SelectionRange, cTexts[TInheritanceOverrideCaseText.LessVisible].Fmt(
      [FClass.Name, AOwn.Name, VisibilityName(AOwn.Visibility), Owner, Target.Name,
      VisibilityName(Target.Visibility)]), TRuleConfidence.High);
  end;
end;

/// <summary>Bei AIndex steht "read Name" oder "write Name" ohne folgenden Punkt.</summary>
function TOverrideCaseCheck.IsAccessorAt(AIndex: Integer): Boolean;
begin
  Result := (AIndex + 2 <= High(FTokens)) and (FTokens[AIndex].Kind in [TPascalTokenKind.Identifier,
    TPascalTokenKind.Keyword]);
  Result := Result and MatchText(FTokens[AIndex].Text, ['read', 'write']) and
    (FTokens[AIndex + 1].Kind = TPascalTokenKind.Identifier) and not FTokens[AIndex + 2].IsSymbol('.');
end;

/// <summary>Methode AName der geprüften Klasse: alle gleichnamigen Mitglieder sind Methoden.</summary>
function AccessorMethod(const AName: string; const AMembers: TArray<TIndexSymbol>; out AMethod: TIndexSymbol): Boolean;
var
  Member: TIndexSymbol;
begin
  Result := False;
  AMethod := Default(TIndexSymbol);
  for Member in AMembers do
  begin
    if SameText(Member.Name, AName) then
    begin
      Result := Member.Kind = TIndexSymbolKind.Method;
      AMethod := Member;
      if not Result then
      begin
        Exit;
      end;
    end;
  end;
end;

/// <summary>Umbenennen der Methode AName in AExpected in der Klasse (Deklaration, Properties) und in den
/// Rumpfköpfen.</summary>
function TOverrideCaseCheck.RenameEdits(const AName, AExpected: string): TArray<TRuleEdit>;
var
  Member: TIndexSymbol;
begin
  Result := nil;
  for Member in FMembers do
  begin
    if (Member.Kind = TIndexSymbolKind.Method) and SameText(Member.Name, AName) then
    begin
      Result := Result + [TRuleEdit.Create(Member.SelectionRange, AExpected)];
    end;
  end;
  for Member in FMembers do
  begin
    if Member.Kind = TIndexSymbolKind.Property_ then
    begin
      Result := Result + AccessorEdits(Member, AName, AExpected);
    end;
  end;
  Result := Result + BodyHeadEdits(AName, AExpected);
end;

/// <summary>Der Zugriff bei AIndex ("read Name"/"write Name") nennt Get&lt;Property&gt; bzw. Set&lt;Property&gt;
/// anders geschrieben.</summary>
procedure TOverrideCaseCheck.CheckAccessor(const AProperty: TIndexSymbol; AIndex: Integer);
var
  Expected, Name: string;
  Method: TIndexSymbol;
begin
  Name := FTokens[AIndex + 1].Text;
  if SameText(FTokens[AIndex].Text, 'read') then
  begin
    Expected := 'Get' + AProperty.Name;
  end
  else
  begin
    Expected := 'Set' + AProperty.Name;
  end;
  if not AccessorMethod(Name, FMembers, Method) or not SameText(Name, Expected) or (Name = Expected) then
  begin
    Exit;
  end;
  FReport.Add(TokenRange(AIndex + 1), cTexts[TInheritanceOverrideCaseText.AccessorName].Fmt(
    [FClass.Name, Method.Name, FClass.Name, Expected]), TRuleConfidence.High,
    [TRuleFix.Create(cTexts[TInheritanceOverrideCaseText.RenameTo].Fmt([Expected]), RenameEdits(Name, Expected))]);
end;

/// <summary>Getter oder Setter heißt Get&lt;Property&gt; bzw. Set&lt;Property&gt;, nur anders geschrieben.
/// </summary>
procedure TOverrideCaseCheck.CheckAccessors(const AProperty: TIndexSymbol);
var
  Index, Last: Integer;
begin
  PropertyTokens(AProperty, Index, Last);
  while Index < Last do
  begin
    if IsAccessorAt(Index) then
    begin
      CheckAccessor(AProperty, Index);
    end;
    Inc(Index);
  end;
end;

/// <summary>Alle gleichnamigen Deklarationen von AMethod sind inline und auf derselben Stufe.</summary>
function TOverrideCaseCheck.InlineBodyKnown(const AMethod: TIndexSymbol): Boolean;
var
  Same: TIndexSymbol;
begin
  Result := True;
  for Same in FMembers do
  begin
    if SameText(Same.Name, AMethod.Name) and not SameInlineLevel(Same, AMethod) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Das Token AIndex kann ein Mitglied der Klasse sein: Bezeichner, weder lokal noch schon gemeldet, und
/// nicht hinter einem Punkt (Obj.FWert gehört einem anderen Ausdruck; nur Self.FWert zählt).</summary>
function TOverrideCaseCheck.IsMemberToken(AIndex: Integer; const ALocals, AReported: TArray<string>): Boolean;
begin
  Result := (FTokens[AIndex].Kind = TPascalTokenKind.Identifier) and not MatchText(FTokens[AIndex].Text, ALocals) and
    not MatchText(FTokens[AIndex].Text, AReported);
  if Result and (AIndex > 0) and FTokens[AIndex - 1].IsSymbol('.') then
  begin
    Result := (AIndex >= 2) and SameText(FTokens[AIndex - 2].Text, 'Self');
  end;
end;

/// <summary>Meldet im Rumpf ABody der Routine ARoutine jeden Zugriff auf ein weniger sichtbares Mitglied.</summary>
procedure TOverrideCaseCheck.CheckInlineBody(const AMethod: TIndexSymbol; ARoutine, ABody: TSyntaxNode;
  var AReported: TArray<string>);
var
  Locals: TArray<string>;
  HasWith: Boolean;
  Level: Integer;
  Hit: TIndexSymbol;
begin
  CollectLocals(ARoutine, Locals, HasWith);
  if HasWith then
  begin
    Exit;
  end;
  Level := TokenFrom(ABody.StartOffset);
  while (Level <= High(FTokens)) and (FTokens[Level].Offset < ABody.EndOffset) do
  begin
    if IsMemberToken(Level, Locals, AReported) and (FindVisibleMember(FTokens[Level].Text, Hit) = TMemberLookup.Found)
      and (VisibilityTier(Hit.Visibility) < VisibilityTier(AMethod.Visibility)) then
    begin
      AReported := AReported + [FTokens[Level].Text];
      FReport.Add(TokenRange(Level), cTexts[TInheritanceOverrideCaseText.InlineVisibility].Fmt(
        [FClass.Name, AMethod.Name, VisibilityName(AMethod.Visibility), Hit.Name, VisibilityName(Hit.Visibility)]),
        TRuleConfidence.High);
    end;
    Inc(Level);
  end;
end;

/// <summary>Die inline-Methode AMethod greift im Rumpf auf ein weniger sichtbares Mitglied zu.</summary>
procedure TOverrideCaseCheck.CheckInline(const AMethod: TIndexSymbol);
var
  Section, Routine, Body: TSyntaxNode;
  Index: Integer;
  Reported: TArray<string>;
begin
  if not InlineBodyKnown(AMethod) then
  begin
    Exit;
  end;
  Section := FContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section = nil then
  begin
    Exit;
  end;
  Reported := nil;
  for Index := 0 to Section.ChildCount - 1 do
  begin
    Routine := Section[Index];
    if (Routine.Kind = TSyntaxKind.RoutineDecl) and SameText(Routine.Name, FClass.Name + '.' + AMethod.Name) then
    begin
      Body := Routine.FindChild(TSyntaxKind.Block);
      if Body <> nil then
      begin
        CheckInlineBody(AMethod, Routine, Body, Reported);
      end;
    end;
  end;
end;

procedure TOverrideCaseCheck.CheckMember(const AMember: TIndexSymbol);
begin
  if (AMember.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
    AMember.HasDirective('override') and (FClass.Kind = TIndexSymbolKind.ClassType) then
  begin
    CheckOverride(AMember);
  end;
  if AMember.Kind = TIndexSymbolKind.Property_ then
  begin
    CheckAccessors(AMember);
  end;
  if (AMember.Kind = TIndexSymbolKind.Method) and AMember.HasDirective('inline') then
  begin
    CheckInline(AMember);
  end;
end;

procedure TOverrideCaseCheck.CheckClass(const AType: TIndexSymbol);
var
  Location: TSymbolLocation;
  Member: TIndexSymbol;
  Complete: Boolean;
begin
  FClass := AType;
  Location := Default(TSymbolLocation);
  Location.Symbol := AType;
  FMembers := FAncestry.Members(Location);
  FChain := nil;
  FObjectMissing := False;
  if AType.Kind = TIndexSymbolKind.ClassType then
  begin
    FChain := FAncestry.Ancestors(AType.Name, Complete, FObjectMissing);
  end;
  for Member in FMembers do
  begin
    if not Member.Unavailable then
    begin
      CheckMember(Member);
    end;
  end;
end;

procedure TOverrideCaseCheck.Run;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in FAncestry.Local.Symbols do
  begin
    if IsOwnType(Symbol) then
    begin
      CheckClass(Symbol);
    end;
  end;
end;

procedure TOverrideCaseMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TOverrideCaseCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Check := TOverrideCaseCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inheritance.OverrideCase', cTexts);

end.
