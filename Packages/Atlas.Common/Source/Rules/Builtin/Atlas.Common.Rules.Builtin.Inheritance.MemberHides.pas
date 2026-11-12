unit Atlas.Common.Rules.Builtin.Inheritance.MemberHides;

// Regel member-hides-ancestor aus Atlas.Common.Rules.Builtin.Inheritance (#1003): Property heißt wie ein Feld des
// Vorfahren (W1009), Feld wie ein Feld oder eine Property, nicht virtuelle Methode wie eine gleich aufgebaute nicht
// virtuelle des Vorfahren; strict private des Vorfahren nur mit ignoreStrictPrivate = false. Methoden, die eine
// Methode eines Interfaces aus der eigenen Vorfahrenliste umsetzen (QueryInterface über TInterfacedObject), gelten
// nicht: Über das Interface ruft Delphi die neue Methode, das Verdecken ist dort der übliche Weg.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TMemberHidesAncestorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  cMemberHidesAncestorRuleId = 'member-hides-ancestor';

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInheritanceMemberHidesText = (Title, RenameInUnit, Hides, LikeW1009);

const
  cTexts: array[TInheritanceMemberHidesText] of TAtlasText = (
    (De: 'Member verdeckt einen gleichnamigen Member des Vorfahren';
     En: 'Member hides a member of the same name in the ancestor'),
    (De: 'In %s umbenennen (in dieser Unit)'; En: 'Rename to %s (in this unit)'),
    (De: '%s verdeckt %s.%s'; En: '%s hides %s.%s'),
    (De: ' (wie W1009)'; En: ' (like W1009)'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Ergebnis einer Stufe der Vorfahrenkette: kein gleichnamiger Member, verdeckter Member gefunden, oder
  /// die Suche endet hier ohne Treffer (gleichnamig, aber anderer Art, oder nur in inaktivem Zweig).</summary>
  TLevelResult = (Missing, Found, Stop);

  /// <summary>Prüfung einer Unit für member-hides-ancestor.</summary>
  TMemberHidesCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FAncestry: TAncestry;
    FTokens: TArray<TPascalToken>;
    FIgnoreStrictPrivate: Boolean;
    function Visible(const AType: TSymbolLocation; const ASymbol: TIndexSymbol): Boolean;
    function NameInUse(const AName: string): Boolean;
    function ClassBodies(const AClass: TIndexSymbol): TArray<TSyntaxNode>;
    function IsRenameToken(AIndex: Integer; const AClass, AOwn: TIndexSymbol;
      const ABodies: TArray<TSyntaxNode>): Boolean;
    function RenameFix(const AClass, AOwn: TIndexSymbol): TArray<TRuleFix>;
    function ImplementsInterface(const AClass, AOwn: TIndexSymbol): Boolean;
    function HiddenAt(const AOwn: TIndexSymbol; const ALocation: TSymbolLocation;
      out AHidden: TIndexSymbol): TLevelResult;
    procedure ReportHidden(const AClass, AOwn: TIndexSymbol; const ALocation: TSymbolLocation;
      const AHidden: TIndexSymbol);
    procedure CheckMember(const AClass, AOwn: TIndexSymbol; const AChain: TArray<TSymbolLocation>);
    procedure CheckClass(const AClass: TIndexSymbol);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

function IsClassMember(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := ASymbol.HasDirective('class') or StartsText('class ', ASymbol.Signature);
end;

/// <summary>Kann AOwn einen Member des Vorfahren verdecken? Neu veröffentlichte Properties (property Caption;),
/// Konstruktoren, Klassenmethoden und bewusst gelöste Fälle nicht.</summary>
function IsHidingCandidate(const AOwn: TIndexSymbol): Boolean;
begin
  if AOwn.Unavailable then
  begin
    Exit(False);
  end;
  case AOwn.Kind of
    TIndexSymbolKind.Field:
      Result := True;
    TIndexSymbolKind.Property_:
      Result := (AOwn.TypeName <> '') and not IsClassMember(AOwn);
    TIndexSymbolKind.Method:
      begin
        Result := not IsClassMember(AOwn) and not AOwn.IsVirtual and not AOwn.HasDirective('reintroduce');
        Result := Result and not AOwn.HasDirective('overload') and not AOwn.HasDirective('message');
      end;
  else
    Result := False;
  end;
end;

/// <summary>Verdeckt AOwn den gleichnamigen Member ASymbol des Vorfahren? Virtuelle Methoden meldet hides-virtual.
/// </summary>
function HidesKind(const AOwn, ASymbol: TIndexSymbol): Boolean;
begin
  case AOwn.Kind of
    TIndexSymbolKind.Field:
      Result := ASymbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_];
    TIndexSymbolKind.Property_:
      Result := ASymbol.Kind = TIndexSymbolKind.Field;
    TIndexSymbolKind.Method:
      Result := (ASymbol.Kind = TIndexSymbolKind.Method) and not ASymbol.IsVirtual and not IsClassMember(ASymbol) and
        SameSignature(ASymbol, AOwn);
  else
    Result := False;
  end;
end;

/// <summary>Kurzname der Klasse ohne führendes T ("TKunde" → "Kunde").</summary>
function ShortName(const AClassName: string): string;
begin
  Result := AClassName;
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 't']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
end;

/// <summary>Neuer Name für AOwn: Kurzname der Klasse davor, bei Feldern hinter dem F ("FName" → "FKundeName").
/// </summary>
function RenamedName(const AClass, AOwn: TIndexSymbol): string;
var
  mPrefix: string;
begin
  if AOwn.Kind <> TIndexSymbolKind.Field then
  begin
    Exit(ShortName(AClass.Name) + AOwn.Name);
  end;
  mPrefix := '';
  if (Length(AOwn.Name) > 1) and CharInSet(AOwn.Name[1], ['F', 'f']) and CharInSet(AOwn.Name[2], ['A'..'Z']) then
  begin
    mPrefix := Copy(AOwn.Name, 1, 1);
  end;
  Result := mPrefix + ShortName(AClass.Name) + Copy(AOwn.Name, Length(mPrefix) + 1, MaxInt);
end;

/// <summary>Liegt AOffset in einem der Knoten ABodies?</summary>
function InBodies(AOffset: Integer; const ABodies: TArray<TSyntaxNode>): Boolean;
var
  mBody: TSyntaxNode;
begin
  Result := False;
  for mBody in ABodies do
  begin
    Result := Result or ((AOffset >= mBody.StartOffset) and (AOffset < mBody.EndOffset));
  end;
end;

/// <summary>Klasse der Unit auf oberster Ebene mit Vorfahren.</summary>
function IsCheckedClass(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.ClassType) and (ASymbol.Container = '') and not ASymbol.Unavailable and
    (ASymbol.Ancestors <> nil);
end;

{ TMemberHidesAncestorRule }

function TMemberHidesAncestorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cMemberHidesAncestorRuleId, TRuleSeverity.Warning,
    cTexts[TInheritanceMemberHidesText.Title].Text);
end;

procedure TMemberHidesAncestorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TMemberHidesCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mCheck := TMemberHidesCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

{ TMemberHidesCheck }

constructor TMemberHidesCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FIgnoreStrictPrivate := TRuleOptions.Bool(AContext.Options, 'ignoreStrictPrivate', True);
  FCache := TRuleDerived.Open(AContext);
  FTokens := TRuleDerived.CodeTokens(FCache, AContext);
  FAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(FCache, AContext));
end;

destructor TMemberHidesCheck.Destroy;
begin
  FAncestry.Free;
  inherited Destroy;
end;

/// <summary>Sieht der Nachfahre den Member ASymbol des Vorfahren auf AType?</summary>
function TMemberHidesCheck.Visible(const AType: TSymbolLocation; const ASymbol: TIndexSymbol): Boolean;
begin
  if ASymbol.Visibility = TIndexVisibility.StrictPrivate then
  begin
    Result := not FIgnoreStrictPrivate and (AType.FileName = '');
  end
  else
  begin
    Result := (ASymbol.Visibility <> TIndexVisibility.Private) or (AType.FileName = '');
  end;
end;

/// <summary>Gibt es den Bezeichner AName in der Datei schon?</summary>
function TMemberHidesCheck.NameInUse(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(FTokens) do
  begin
    Result := Result or ((FTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      SameText(FTokens[mIndex].Text, AName));
  end;
end;

/// <summary>Rümpfe der Methoden der Klasse (TKunde.X) aus dem implementation-Teil.</summary>
function TMemberHidesCheck.ClassBodies(const AClass: TIndexSymbol): TArray<TSyntaxNode>;
var
  mSection: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mSection := FContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mSection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mSection.ChildCount - 1 do
  begin
    if (mSection[mIndex].Kind = TSyntaxKind.RoutineDecl) and StartsText(AClass.Name + '.', mSection[mIndex].Name) then
    begin
      Result := Result + [mSection[mIndex]];
    end;
  end;
end;

/// <summary>Das Token AIndex nennt AOwn in der Klassendeklaration oder einem Rumpf der Klasse. Obj.FName: nur
/// Self.FName zählt; im Rumpfkopf "procedure TKunde.Name" ist es der Methodenname.</summary>
function TMemberHidesCheck.IsRenameToken(AIndex: Integer; const AClass, AOwn: TIndexSymbol;
  const ABodies: TArray<TSyntaxNode>): Boolean;
begin
  Result := (FTokens[AIndex].Kind = TPascalTokenKind.Identifier) and SameText(FTokens[AIndex].Text, AOwn.Name);
  Result := Result and (InBodies(FTokens[AIndex].Offset, ABodies) or
    ContainsLine(AClass.Range, FTokens[AIndex].StartPos.Line));
  if Result and (AIndex > 0) and FTokens[AIndex - 1].IsSymbol('.') then
  begin
    Result := (AIndex >= 2) and SameText(FTokens[AIndex - 2].Text, 'Self');
  end;
end;

/// <summary>Korrektur: AOwn in der Klassendeklaration und in den Rümpfen der Klasse umbenennen. Zugriffe über einen
/// anderen Ausdruck (Obj.FName) und andere Units bleiben unverändert.</summary>
function TMemberHidesCheck.RenameFix(const AClass, AOwn: TIndexSymbol): TArray<TRuleFix>;
var
  mNewName: string;
  mIndex: Integer;
  mEdits: TArray<TRuleEdit>;
  mBodies: TArray<TSyntaxNode>;
begin
  Result := nil;
  mNewName := RenamedName(AClass, AOwn);
  if NameInUse(mNewName) then
  begin
    Exit;
  end;
  mBodies := ClassBodies(AClass);
  mEdits := nil;
  for mIndex := 0 to High(FTokens) do
  begin
    if IsRenameToken(mIndex, AClass, AOwn, mBodies) then
    begin
      mEdits := mEdits + [TRuleEdit.Create(TTextRange.Create(FTokens[mIndex].StartPos, FTokens[mIndex].EndPos),
        mNewName)];
    end;
  end;
  if mEdits <> nil then
  begin
    Result := [TRuleFix.Create(cTexts[TInheritanceMemberHidesText.RenameInUnit].Fmt([mNewName]), mEdits)];
  end;
end;

/// <summary>Setzt die Methode AOwn eine Methode eines Interfaces aus der Vorfahrenliste von AClass um? Die
/// Methoden von IInterface (QueryInterface, _AddRef, _Release) gehören zu jedem Interface, auch wenn der Index
/// System nicht kennt.</summary>
function TMemberHidesCheck.ImplementsInterface(const AClass, AOwn: TIndexSymbol): Boolean;
var
  mIndex: Integer;
  mType: TSymbolLocation;
  mMember: TIndexSymbol;
begin
  Result := False;
  if (AOwn.Kind <> TIndexSymbolKind.Method) or (Length(AClass.Ancestors) < 2) then
  begin
    Exit;
  end;
  if IndexText(AOwn.Name, ['QueryInterface', '_AddRef', '_Release']) >= 0 then
  begin
    Exit(True);
  end;
  for mIndex := 1 to High(AClass.Ancestors) do
  begin
    if not FAncestry.FindAnyType(AClass.Ancestors[mIndex], mType) then
    begin
      Continue;
    end;
    for mMember in FAncestry.Members(mType) do
    begin
      if SameText(mMember.Name, AOwn.Name) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

/// <summary>Der von AOwn verdeckte Member auf der Stufe ALocation.</summary>
function TMemberHidesCheck.HiddenAt(const AOwn: TIndexSymbol; const ALocation: TSymbolLocation;
  out AHidden: TIndexSymbol): TLevelResult;
var
  mSymbol: TIndexSymbol;
begin
  AHidden := Default(TIndexSymbol);
  Result := TLevelResult.Missing;
  for mSymbol in FAncestry.Members(ALocation) do
  begin
    if not SameText(mSymbol.Name, AOwn.Name) then
    begin
      Continue;
    end;
    // Nur in einem inaktiven Zweig: keine Aussage.
    if mSymbol.Unavailable then
    begin
      Exit(TLevelResult.Stop);
    end;
    if not Visible(ALocation, mSymbol) then
    begin
      Continue;
    end;
    Result := TLevelResult.Stop;
    if HidesKind(AOwn, mSymbol) then
    begin
      AHidden := mSymbol;
      Exit(TLevelResult.Found);
    end;
  end;
end;

/// <summary>dcc meldet W1009 nur, wenn eine Property ein Feld verdeckt; Feld über Feld oder Property und statische
/// Methode über statische Methode übersetzt Delphi 13 still (#1383). Methoden meldet die Regel darum mit niedriger
/// Konfidenz: In der FP-Prüfung vom 28.10.2026 waren rund 80 % davon gewollt (Ereignisbehandlungen geerbter
/// Formulare, Hilfsmethoden gleichen Namens).</summary>
procedure TMemberHidesCheck.ReportHidden(const AClass, AOwn: TIndexSymbol; const ALocation: TSymbolLocation;
  const AHidden: TIndexSymbol);
var
  mMessage: string;
begin
  mMessage := cTexts[TInheritanceMemberHidesText.Hides].Fmt([AOwn.Name, ALocation.Symbol.Name, AHidden.Name]);
  if AOwn.Kind = TIndexSymbolKind.Property_ then
  begin
    mMessage := mMessage + cTexts[TInheritanceMemberHidesText.LikeW1009].Text;
  end;
  if AOwn.Kind = TIndexSymbolKind.Method then
  begin
    FReport.Add(AOwn.SelectionRange, mMessage + '.', TRuleConfidence.Low);
  end
  else
  begin
    FReport.Add(AOwn.SelectionRange, mMessage + '.', TRuleConfidence.High, RenameFix(AClass, AOwn));
  end;
end;

/// <summary>Die nächste Stufe mit gleichnamigem Member entscheidet.</summary>
procedure TMemberHidesCheck.CheckMember(const AClass, AOwn: TIndexSymbol; const AChain: TArray<TSymbolLocation>);
var
  mLocation: TSymbolLocation;
  mHidden: TIndexSymbol;
  mState: TLevelResult;
begin
  for mLocation in AChain do
  begin
    mState := HiddenAt(AOwn, mLocation, mHidden);
    if mState = TLevelResult.Found then
    begin
      ReportHidden(AClass, AOwn, mLocation, mHidden);
    end;
    if mState <> TLevelResult.Missing then
    begin
      Exit;
    end;
  end;
end;

procedure TMemberHidesCheck.CheckClass(const AClass: TIndexSymbol);
var
  mMember: TIndexSymbol;
  mLocation: TSymbolLocation;
  mChain: TArray<TSymbolLocation>;
  mComplete, mObjectMissing: Boolean;
begin
  mChain := FAncestry.Ancestors(AClass.Name, mComplete, mObjectMissing);
  if mChain = nil then
  begin
    Exit;
  end;
  mLocation := Default(TSymbolLocation);
  mLocation.Symbol := AClass;
  for mMember in FAncestry.Members(mLocation) do
  begin
    if IsHidingCandidate(mMember) and not ImplementsInterface(AClass, mMember) then
    begin
      CheckMember(AClass, mMember, mChain);
    end;
  end;
end;

procedure TMemberHidesCheck.Run;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if IsCheckedClass(mSymbol) then
    begin
      CheckClass(mSymbol);
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inheritance.MemberHides', cTexts);

end.
