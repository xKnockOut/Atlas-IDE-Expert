unit Atlas.Common.Leaks.Ownership.Tests;

// Tests für „Wer gibt das frei?“ (#1877): Einstufung jeder Erzeugung zusammen mit den Leck-Regeln (frei im
// Destruktor, im finally, Owner, besitzende Liste und Elemente einer anderen Liste, Referenzzählung, Rückgabe,
// Weitergabe, nie freigegeben genau wie field-not-freed, local-object-not-freed und create-without-assignment),
// raise und Records übergehen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Leaks.Ownership;

type
  [TestFixture]
  TOwnershipSitesTests = class
  private
    function Sites(const ASource: string): TArray<TOwnershipSite>;
    function SiteOf(const ASites: TArray<TOwnershipSite>; const AClassName, ATarget: string): TOwnershipSite;
  public
    [Test]
    procedure FieldFreedInDestroy;
    [Test]
    procedure FieldWithoutFreeIsNeverLikeTheRule;
    [Test]
    procedure FieldWithoutFindingIsUnknown;
    [Test]
    procedure ComponentWithOwner;
    [Test]
    procedure ObjectListsAndElements;
    [Test]
    procedure LocalFreedInFinally;
    [Test]
    procedure LocalNeverFreedLikeTheRule;
    [Test]
    procedure StatementWithoutAssignment;
    [Test]
    procedure ReturnedAndPassed;
    [Test]
    procedure InterfaceIsRefCounted;
    [Test]
    procedure SkipsRaiseAndRecords;
    [Test]
    procedure KindNamesForTheProtocol;
  end;

  [TestFixture]
  TOwnershipTreeTests = class
  public
    [Test]
    procedure RecognizesInterfaceNames;
    [Test]
    procedure ElementTypeOfGenericList;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin.FreeFields,
  Atlas.Common.Rules.Builtin.Ownership,
  Atlas.Common.Rules.Builtin.Ownership.LocalObjects,
  Atlas.Common.Leaks.Internals.OwnershipTree;

const
  cNl = #10;

function UnitText(const AInterface, AImplementation: string): string;
begin
  Result := 'unit U;' + cNl + 'interface' + cNl + 'uses' + cNl + '  System.Classes, System.Generics.Collections;' +
    cNl + 'type' + cNl + AInterface + 'implementation' + cNl + AImplementation + 'end.';
end;

function TOwnershipSitesTests.Sites(const ASource: string): TArray<TOwnershipSite>;
var
  mTree: TSyntaxTree;
  mContext: TRuleContext;
  mRules: TArray<IRule>;
  mFindings: TArray<TRuleFinding>;
  mRule: IRule;
begin
  mTree := TSyntaxTreeCache.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.Text := ASource;
    mContext.Tree := mTree;
    mRules := nil;
    // Erst in Interface-Variablen: direkt übergeben gibt Delphi die Objekte nie frei.
    mRule := TOwnedFieldNotFreedRule.Create;
    mRules := mRules + [mRule];
    mRule := TCreateWithoutAssignmentRule.Create;
    mRules := mRules + [mRule];
    mRule := TLocalObjectNotFreedRule.Create;
    mRules := mRules + [mRule];
    mRule := TCreatedResultNotFreedRule.Create;
    mRules := mRules + [mRule];
    mFindings := TRuleEngine.Run(mRules, TServerSettings.Default, mContext);
    Result := TOwnershipSites.Analyze(mTree, ASource, nil, mFindings);
  finally
    mTree.Free;
  end;
end;

function TOwnershipSitesTests.SiteOf(const ASites: TArray<TOwnershipSite>; const AClassName,
  ATarget: string): TOwnershipSite;
var
  mSite: TOwnershipSite;
begin
  for mSite in ASites do
  begin
    if SameText(mSite.ClassName, AClassName) and SameText(mSite.Target, ATarget) then
    begin
      Exit(mSite);
    end;
  end;
  Assert.Fail('Keine Erzeugung ' + AClassName + ' für ' + ATarget);
  Result := Default(TOwnershipSite);
end;

function KindName(const ASite: TOwnershipSite): string;
begin
  Result := TOwnershipSites.cKindNames[ASite.Kind];
end;

procedure TOwnershipSitesTests.FieldFreedInDestroy;
var
  mSite: TOwnershipSite;
begin
  mSite := SiteOf(Sites(UnitText(
    '  TKunde = class' + cNl + '  private' + cNl + '    FNamen: TStringList;' + cNl + '  public' + cNl +
    '    constructor Create;' + cNl + '    destructor Destroy; override;' + cNl + '  end;' + cNl,
    'constructor TKunde.Create;' + cNl + 'begin' + cNl + '  FNamen := TStringList.Create;' + cNl + 'end;' + cNl +
    'destructor TKunde.Destroy;' + cNl + 'begin' + cNl + '  FNamen.Free;' + cNl + '  inherited;' + cNl + 'end;' +
    cNl)), 'TStringList', 'FNamen');
  Assert.AreEqual('destroy', KindName(mSite));
  Assert.AreEqual(19, mSite.FreeLine);
  Assert.AreEqual('Destroy', mSite.Detail);
  Assert.AreEqual(15, mSite.Range.StartPos.Line);
end;

const
  cFieldWithoutFree =
    '  TKunde = class' + cNl + '  private' + cNl + '    FNamen: TStringList;' + cNl + '  public' + cNl +
    '    constructor Create;' + cNl + '  end;' + cNl;
  cFieldCreated = 'constructor TKunde.Create;' + cNl + 'begin' + cNl + '  FNamen := TStringList.Create;' + cNl +
    'end;' + cNl;

procedure TOwnershipSitesTests.FieldWithoutFreeIsNeverLikeTheRule;
var
  mSite: TOwnershipSite;
begin
  mSite := SiteOf(Sites(UnitText(cFieldWithoutFree, cFieldCreated)), 'TStringList', 'FNamen');
  Assert.AreEqual('never', KindName(mSite));
  Assert.AreEqual('field-not-freed', mSite.Rule);
  Assert.IsTrue(mSite.Message <> '');
  Assert.AreEqual(-1, mSite.FreeLine);
end;

procedure TOwnershipSitesTests.FieldWithoutFindingIsUnknown;
var
  mSource: string;
  mTree: TSyntaxTree;
  mSites: TArray<TOwnershipSite>;
begin
  // Ohne Befund der Regel (abgeschaltet, ignoreTypes) bleibt die Stelle unklar statt rot.
  mSource := UnitText(cFieldWithoutFree, cFieldCreated);
  mTree := TSyntaxTreeCache.Parse(mSource);
  try
    mSites := TOwnershipSites.Analyze(mTree, mSource, nil, nil);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mSites)));
  Assert.AreEqual('unknown', KindName(mSites[0]));
  Assert.AreEqual('', mSites[0].Rule);
end;

procedure TOwnershipSitesTests.ComponentWithOwner;
var
  mSites: TArray<TOwnershipSite>;
  mSite: TOwnershipSite;
begin
  mSites := Sites(UnitText(
    '  TFenster = class(TComponent)' + cNl + '  private' + cNl + '    FTakt: TTimer;' + cNl + '  public' + cNl +
    '    procedure Lade(AOwner: TComponent);' + cNl + '  end;' + cNl,
    'procedure TFenster.Lade(AOwner: TComponent);' + cNl + 'begin' + cNl + '  FTakt := TTimer.Create(Self);' + cNl +
    '  TButton.Create(AOwner);' + cNl + 'end;' + cNl));
  mSite := SiteOf(mSites, 'TTimer', 'FTakt');
  Assert.AreEqual('owner', KindName(mSite));
  Assert.AreEqual('Self', mSite.Detail);
  mSite := SiteOf(mSites, 'TButton', '');
  Assert.AreEqual('owner', KindName(mSite));
  Assert.AreEqual('AOwner', mSite.Detail);
end;

procedure TOwnershipSitesTests.ObjectListsAndElements;
var
  mSites: TArray<TOwnershipSite>;
  mSite: TOwnershipSite;
begin
  mSites := Sites(UnitText(
    '  TPosten = class' + cNl + '  end;' + cNl + '  TAuftrag = class' + cNl + '  private' + cNl +
    '    FPosten: TObjectList<TPosten>;' + cNl + '    FOffen: TList<TPosten>;' + cNl + '  public' + cNl +
    '    constructor Create;' + cNl + '    destructor Destroy; override;' + cNl + '  end;' + cNl,
    'constructor TAuftrag.Create;' + cNl + 'begin' + cNl + '  FPosten := TObjectList<TPosten>.Create(True);' + cNl +
    '  FOffen := TList<TPosten>.Create;' + cNl + '  FPosten.Add(TPosten.Create);' + cNl + 'end;' + cNl +
    'destructor TAuftrag.Destroy;' + cNl + 'begin' + cNl + '  FOffen.Free;' + cNl + '  FPosten.Free;' + cNl +
    '  inherited;' + cNl + 'end;' + cNl));
  mSite := SiteOf(mSites, 'TObjectList<TPosten>', 'FPosten');
  Assert.AreEqual('destroy', KindName(mSite));
  Assert.AreEqual('ownsElements', TOwnershipSites.cContainerNames[mSite.Container]);
  mSite := SiteOf(mSites, 'TList<TPosten>', 'FOffen');
  Assert.AreEqual('elementsOwned', TOwnershipSites.cContainerNames[mSite.Container]);
  Assert.AreEqual('FPosten', mSite.ContainerOwner);
  mSite := SiteOf(mSites, 'TPosten', '');
  Assert.AreEqual('ownedList', KindName(mSite));
  Assert.AreEqual('FPosten', mSite.Detail);
end;

function RoutineText(const AVars, ABody: string): string;
begin
  Result := UnitText('  TProtokoll = class(TObject)' + cNl + '  end;' + cNl,
    'function Lauf(Ziel: TStrings): TStrings;' + cNl + 'var' + cNl + AVars + 'begin' + cNl + ABody + 'end;' + cNl);
end;

procedure TOwnershipSitesTests.LocalFreedInFinally;
var
  mSites: TArray<TOwnershipSite>;
  mSite: TOwnershipSite;
begin
  mSites := Sites(RoutineText('  Liste: TStringList;' + cNl + '  Zweite: TStringList;' + cNl,
    '  Liste := TStringList.Create;' + cNl + '  try' + cNl + '    Ziel.Assign(Liste);' + cNl + '  finally' + cNl +
    '    Liste.Free;' + cNl + '  end;' + cNl + '  Zweite := TStringList.Create;' + cNl + '  Zweite.Clear;' + cNl +
    '  FreeAndNil(Zweite);' + cNl));
  mSite := SiteOf(mSites, 'TStringList', 'Liste');
  Assert.AreEqual('finally', KindName(mSite));
  Assert.AreEqual(17, mSite.FreeLine);
  mSite := SiteOf(mSites, 'TStringList', 'Zweite');
  Assert.AreEqual('freed', KindName(mSite));
  Assert.AreEqual(21, mSite.FreeLine);
end;

procedure TOwnershipSitesTests.LocalNeverFreedLikeTheRule;
var
  mSite: TOwnershipSite;
begin
  mSite := SiteOf(Sites(RoutineText('  Liste: TStringList;' + cNl,
    '  Liste := TStringList.Create;' + cNl + '  Liste.Add(''a'');' + cNl + '  Ziel.Text := Liste.Text;' + cNl)),
    'TStringList', 'Liste');
  Assert.AreEqual('never', KindName(mSite));
  Assert.AreEqual(cLocalObjectNotFreedRuleId, mSite.Rule);
end;

procedure TOwnershipSitesTests.StatementWithoutAssignment;
var
  mSites: TArray<TOwnershipSite>;
begin
  mSites := Sites(RoutineText('', '  TStringList.Create;' + cNl));
  Assert.AreEqual(1, Integer(Length(mSites)));
  Assert.AreEqual('never', KindName(mSites[0]));
  Assert.AreEqual('create-without-assignment', mSites[0].Rule);
end;

procedure TOwnershipSitesTests.ReturnedAndPassed;
var
  mSites: TArray<TOwnershipSite>;
begin
  mSites := Sites(RoutineText('  Liste: TStringList;' + cNl,
    '  Ziel.AddObject(''a'', TProtokoll.Create);' + cNl + '  if Ziel = nil then' + cNl +
    '    Exit(TStringList.Create);' + cNl + '  Liste := TStringList.Create;' + cNl + '  Result := Liste;' + cNl));
  Assert.AreEqual(3, Integer(Length(mSites)));
  Assert.AreEqual('passed', KindName(mSites[0]));
  Assert.AreEqual('Ziel.AddObject', mSites[0].Detail);
  Assert.AreEqual('returned', KindName(mSites[1]));
  Assert.AreEqual('returned', KindName(mSites[2]));
  Assert.AreEqual('Liste', mSites[2].Target);
end;

procedure TOwnershipSitesTests.InterfaceIsRefCounted;
var
  mSites: TArray<TOwnershipSite>;
begin
  mSites := Sites(RoutineText('  Wert: IInterface;' + cNl, '  Wert := TInterfacedObject.Create;' + cNl +
    '  Ziel.Add((TInterfacedObject.Create as IInterface).ToString);' + cNl));
  Assert.AreEqual(2, Integer(Length(mSites)));
  Assert.AreEqual('interface', KindName(mSites[0]));
  Assert.AreEqual('interface', KindName(mSites[1]));
end;

procedure TOwnershipSitesTests.SkipsRaiseAndRecords;
var
  mSites: TArray<TOwnershipSite>;
begin
  mSites := Sites(RoutineText('  Takt: TStopwatch;' + cNl, '  Takt := TStopwatch.Create;' + cNl +
    '  raise EArgumentException.Create(''x'');' + cNl));
  Assert.AreEqual(0, Integer(Length(mSites)));
end;

procedure TOwnershipSitesTests.KindNamesForTheProtocol;
begin
  Assert.AreEqual('destroy', TOwnershipSites.cKindNames[TOwnershipKind.InDestroy]);
  Assert.AreEqual('interface', TOwnershipSites.cKindNames[TOwnershipKind.RefCounted]);
  Assert.AreEqual('never', TOwnershipSites.cKindNames[TOwnershipKind.Never]);
  Assert.IsTrue(TOwnershipSites.IsOwnershipRule('field-not-freed'));
  Assert.IsFalse(TOwnershipSites.IsOwnershipRule('owned-item-freed'));
end;

{ TOwnershipTreeTests }

procedure TOwnershipTreeTests.RecognizesInterfaceNames;
begin
  Assert.IsTrue(TOwnershipTree.LooksLikeInterface('IStream'));
  Assert.IsTrue(TOwnershipTree.LooksLikeInterface('System.Classes.IInterfaceList'));
  Assert.IsTrue(TOwnershipTree.LooksLikeInterface('IList<TItem>'));
  Assert.IsFalse(TOwnershipTree.LooksLikeInterface('Item'));
  Assert.IsFalse(TOwnershipTree.LooksLikeInterface('Inventory'));
  Assert.IsFalse(TOwnershipTree.LooksLikeInterface('I'));
end;

procedure TOwnershipTreeTests.ElementTypeOfGenericList;
begin
  Assert.AreEqual('TItem', TOwnershipTree.ElementType('TObjectList<TItem>'));
  Assert.AreEqual('TList<TItem>', TOwnershipTree.ElementType('TObjectList< TList<TItem> >'));
  Assert.AreEqual('', TOwnershipTree.ElementType('TStringList'));
end;

initialization
  TDUnitX.RegisterTestFixture(TOwnershipSitesTests);
  TDUnitX.RegisterTestFixture(TOwnershipTreeTests);

end.
