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
  cOverrideCaseMismatchRuleId = 'override-case-mismatch';

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
  Atlas.Common.Rules.Builtin.Naming,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
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
  Result := TRuleDescriptor.Create(cOverrideCaseMismatchRuleId, TRuleSeverity.Hint,
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
  mSymbol: TIndexSymbol;
begin
  AHit := Default(TIndexSymbol);
  Result := TMemberLookup.Missing;
  for mSymbol in ASymbols do
  begin
    if not SameText(mSymbol.Name, AName) then
    begin
      Continue;
    end;
    if mSymbol.Unavailable then
    begin
      Exit(TMemberLookup.Unknown);
    end;
    if not AFilter or not InvisibleToDescendant(ALocation, mSymbol) then
    begin
      AHit := mSymbol;
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
  mName: string;
begin
  ATarget := Default(TIndexSymbol);
  Result := False;
  if AOwn.MaxArgs <> 0 then
  begin
    Exit;
  end;
  for mName in cObjectVirtualNames do
  begin
    if SameText(mName, AOwn.Name) then
    begin
      ATarget.Name := mName;
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
  mStack: TArray<TSyntaxNode>;
  mNode: TSyntaxNode;
  mChild: Integer;
begin
  ALocals := nil;
  AHasWith := False;
  mStack := [ARoutine];
  while mStack <> nil do
  begin
    mNode := mStack[High(mStack)];
    SetLength(mStack, Length(mStack) - 1);
    if (mNode <> ARoutine) and (mNode.Kind in [TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl,
      TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.TypeDecl, TSyntaxKind.RoutineDecl]) then
    begin
      ALocals := ALocals + mNode.Name.Split([',']);
    end;
    AHasWith := AHasWith or (mNode.Kind = TSyntaxKind.WithStatement);
    for mChild := 0 to mNode.ChildCount - 1 do
    begin
      mStack := mStack + [mNode[mChild]];
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
  mLow, mHigh, mMiddle: Integer;
begin
  mLow := 0;
  mHigh := Length(FTokens);
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if FTokens[mMiddle].Offset < AOffset then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
  Result := mLow;
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
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 1 to High(FTokens) - 2 do
  begin
    if IsBodyHead(mIndex, AOld) and (FTokens[mIndex + 2].Text <> ANew) then
    begin
      Result := Result + [TRuleEdit.Create(TokenRange(mIndex + 2), ANew)];
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
  mIndex, mFirst, mLast: Integer;
begin
  Result := nil;
  PropertyTokens(AProperty, mFirst, mLast);
  for mIndex := mFirst + 1 to mLast - 1 do
  begin
    if SameText(FTokens[mIndex].Text, AOld) and MatchText(FTokens[mIndex - 1].Text, ['read', 'write']) then
    begin
      Result := Result + [TRuleEdit.Create(TokenRange(mIndex), ANew)];
    end;
  end;
end;

/// <summary>Mitglied AName der eigenen Members oder der nächsten Stufe der Kette, die es dort sichtbar gibt.</summary>
function TOverrideCaseCheck.FindVisibleMember(const AName: string; out AHit: TIndexSymbol): TMemberLookup;
var
  mLocation: TSymbolLocation;
begin
  Result := LookupIn(AName, FMembers, Default(TSymbolLocation), False, AHit);
  for mLocation in FChain do
  begin
    if Result <> TMemberLookup.Missing then
    begin
      Exit;
    end;
    Result := LookupIn(AName, FAncestry.Members(mLocation), mLocation, True, AHit);
  end;
end;

/// <summary>Die von AOwn überschriebene Methode auf der Stufe ALocation. Unknown, wenn die Suche hier ohne Treffer
/// endet (gleichnamig sichtbar, aber nicht überschreibbar, oder nur in inaktivem Zweig).</summary>
function TOverrideCaseCheck.OverriddenAt(const AOwn: TIndexSymbol; const ALocation: TSymbolLocation;
  out ATarget: TIndexSymbol): TMemberLookup;
var
  mSymbol: TIndexSymbol;
begin
  ATarget := Default(TIndexSymbol);
  Result := TMemberLookup.Missing;
  for mSymbol in FAncestry.Methods(ALocation) do
  begin
    if not SameText(mSymbol.Name, AOwn.Name) then
    begin
      Continue;
    end;
    if mSymbol.Unavailable then
    begin
      Exit(TMemberLookup.Unknown);
    end;
    if InvisibleToDescendant(ALocation, mSymbol) then
    begin
      Continue;
    end;
    Result := TMemberLookup.Unknown;
    if IsOverrideTarget(mSymbol, AOwn) then
    begin
      ATarget := mSymbol;
      Exit(TMemberLookup.Found);
    end;
  end;
end;

/// <summary>Die überschriebene Methode: nächste Stufe mit gleichnamiger, sichtbarer, virtueller Methode gleicher
/// Parameterzahl; TObject über die Tabelle, wenn System nicht im Index steht. False ohne sichere Aussage.</summary>
function TOverrideCaseCheck.Overridden(const AOwn: TIndexSymbol; out AOwner: string;
  out ATarget: TIndexSymbol): Boolean;
var
  mLocation: TSymbolLocation;
  mState: TMemberLookup;
begin
  AOwner := '';
  ATarget := Default(TIndexSymbol);
  for mLocation in FChain do
  begin
    mState := OverriddenAt(AOwn, mLocation, ATarget);
    if mState <> TMemberLookup.Missing then
    begin
      AOwner := mLocation.Symbol.Name;
      Exit(mState = TMemberLookup.Found);
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
  mOwner: string;
  mTarget: TIndexSymbol;
begin
  if not Overridden(AOwn, mOwner, mTarget) then
  begin
    Exit;
  end;
  if mTarget.Name <> AOwn.Name then
  begin
    FReport.Add(AOwn.SelectionRange, cTexts[TInheritanceOverrideCaseText.Spelling].Fmt([mOwner, mTarget.Name]),
      TRuleConfidence.High, [TRuleFix.Create(cTexts[TInheritanceOverrideCaseText.TakeSpelling].Text,
      [TRuleEdit.Create(AOwn.SelectionRange, mTarget.Name)] + BodyHeadEdits(AOwn.Name, mTarget.Name))]);
  end;
  // Nur für Klassen im interface-Teil (die Sichtbarkeit sieht man nur dort von außen).
  if FClass.InInterface and (VisibilityTier(AOwn.Visibility) < VisibilityTier(mTarget.Visibility)) then
  begin
    FReport.Add(AOwn.SelectionRange, cTexts[TInheritanceOverrideCaseText.LessVisible].Fmt(
      [FClass.Name, AOwn.Name, VisibilityName(AOwn.Visibility), mOwner, mTarget.Name,
      VisibilityName(mTarget.Visibility)]), TRuleConfidence.High);
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
  mMember: TIndexSymbol;
begin
  Result := False;
  AMethod := Default(TIndexSymbol);
  for mMember in AMembers do
  begin
    if SameText(mMember.Name, AName) then
    begin
      Result := mMember.Kind = TIndexSymbolKind.Method;
      AMethod := mMember;
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
  mMember: TIndexSymbol;
begin
  Result := nil;
  for mMember in FMembers do
  begin
    if (mMember.Kind = TIndexSymbolKind.Method) and SameText(mMember.Name, AName) then
    begin
      Result := Result + [TRuleEdit.Create(mMember.SelectionRange, AExpected)];
    end;
  end;
  for mMember in FMembers do
  begin
    if mMember.Kind = TIndexSymbolKind.Property_ then
    begin
      Result := Result + AccessorEdits(mMember, AName, AExpected);
    end;
  end;
  Result := Result + BodyHeadEdits(AName, AExpected);
end;

/// <summary>Der Zugriff bei AIndex ("read Name"/"write Name") nennt Get&lt;Property&gt; bzw. Set&lt;Property&gt;
/// anders geschrieben.</summary>
procedure TOverrideCaseCheck.CheckAccessor(const AProperty: TIndexSymbol; AIndex: Integer);
var
  mExpected, mName: string;
  mMethod: TIndexSymbol;
begin
  mName := FTokens[AIndex + 1].Text;
  if SameText(FTokens[AIndex].Text, 'read') then
  begin
    mExpected := 'Get' + AProperty.Name;
  end
  else
  begin
    mExpected := 'Set' + AProperty.Name;
  end;
  if not AccessorMethod(mName, FMembers, mMethod) or not SameText(mName, mExpected) or (mName = mExpected) then
  begin
    Exit;
  end;
  FReport.Add(TokenRange(AIndex + 1), cTexts[TInheritanceOverrideCaseText.AccessorName].Fmt(
    [FClass.Name, mMethod.Name, FClass.Name, mExpected]), TRuleConfidence.High,
    [TRuleFix.Create(cTexts[TInheritanceOverrideCaseText.RenameTo].Fmt([mExpected]), RenameEdits(mName, mExpected))]);
end;

/// <summary>Getter oder Setter heißt Get&lt;Property&gt; bzw. Set&lt;Property&gt;, nur anders geschrieben.
/// </summary>
procedure TOverrideCaseCheck.CheckAccessors(const AProperty: TIndexSymbol);
var
  mIndex, mLast: Integer;
begin
  PropertyTokens(AProperty, mIndex, mLast);
  while mIndex < mLast do
  begin
    if IsAccessorAt(mIndex) then
    begin
      CheckAccessor(AProperty, mIndex);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Alle gleichnamigen Deklarationen von AMethod sind inline und auf derselben Stufe.</summary>
function TOverrideCaseCheck.InlineBodyKnown(const AMethod: TIndexSymbol): Boolean;
var
  mSame: TIndexSymbol;
begin
  Result := True;
  for mSame in FMembers do
  begin
    if SameText(mSame.Name, AMethod.Name) and not SameInlineLevel(mSame, AMethod) then
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
  mLocals: TArray<string>;
  mHasWith: Boolean;
  mLevel: Integer;
  mHit: TIndexSymbol;
begin
  CollectLocals(ARoutine, mLocals, mHasWith);
  if mHasWith then
  begin
    Exit;
  end;
  mLevel := TokenFrom(ABody.StartOffset);
  while (mLevel <= High(FTokens)) and (FTokens[mLevel].Offset < ABody.EndOffset) do
  begin
    if IsMemberToken(mLevel, mLocals, AReported) and
      (FindVisibleMember(FTokens[mLevel].Text, mHit) = TMemberLookup.Found)
      and (VisibilityTier(mHit.Visibility) < VisibilityTier(AMethod.Visibility)) then
    begin
      AReported := AReported + [FTokens[mLevel].Text];
      FReport.Add(TokenRange(mLevel), cTexts[TInheritanceOverrideCaseText.InlineVisibility].Fmt(
        [FClass.Name, AMethod.Name, VisibilityName(AMethod.Visibility), mHit.Name, VisibilityName(mHit.Visibility)]),
        TRuleConfidence.High);
    end;
    Inc(mLevel);
  end;
end;

/// <summary>Die inline-Methode AMethod greift im Rumpf auf ein weniger sichtbares Mitglied zu.</summary>
procedure TOverrideCaseCheck.CheckInline(const AMethod: TIndexSymbol);
var
  mSection, mRoutine, mBody: TSyntaxNode;
  mIndex: Integer;
  mReported: TArray<string>;
begin
  if not InlineBodyKnown(AMethod) then
  begin
    Exit;
  end;
  mSection := FContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mSection = nil then
  begin
    Exit;
  end;
  mReported := nil;
  for mIndex := 0 to mSection.ChildCount - 1 do
  begin
    mRoutine := mSection[mIndex];
    if (mRoutine.Kind = TSyntaxKind.RoutineDecl) and SameText(mRoutine.Name, FClass.Name + '.' + AMethod.Name) then
    begin
      mBody := mRoutine.FindChild(TSyntaxKind.Block);
      if mBody <> nil then
      begin
        CheckInlineBody(AMethod, mRoutine, mBody, mReported);
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
  mLocation: TSymbolLocation;
  mMember: TIndexSymbol;
  mComplete: Boolean;
begin
  FClass := AType;
  mLocation := Default(TSymbolLocation);
  mLocation.Symbol := AType;
  FMembers := FAncestry.Members(mLocation);
  FChain := nil;
  FObjectMissing := False;
  if AType.Kind = TIndexSymbolKind.ClassType then
  begin
    FChain := FAncestry.Ancestors(AType.Name, mComplete, FObjectMissing);
  end;
  for mMember in FMembers do
  begin
    if not mMember.Unavailable then
    begin
      CheckMember(mMember);
    end;
  end;
end;

procedure TOverrideCaseCheck.Run;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if IsOwnType(mSymbol) then
    begin
      CheckClass(mSymbol);
    end;
  end;
end;

procedure TOverrideCaseMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TOverrideCaseCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mCheck := TOverrideCaseCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inheritance.OverrideCase', cTexts);

end.
