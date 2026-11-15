unit Atlas.Core.UnitSearch.Plan.Tests;

// Tests für die Entscheidungen des Fensters „Units suchen“ (#777, #786):
// Aktionen der IDE, Übernahme der Taste, offenes Fenster, Gruppe, Ziele und
// Argumente an den Server.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Search')]
  TAtlasUnitSearchPlanTests = class
  public
    /// <summary>Name und Ersatztaste je Modus; Übernahme nach der Einstellung des Modus.</summary>
    [Test]
    procedure ActionsPerMode;
    /// <summary>Taste an Atlas nur eingeschaltet, übernommen, ohne Umschalt, nicht abgeschaltet.</summary>
    [Test]
    procedure TakesActionNeedsAll;
    /// <summary>Fenster bleibt im selben Modus; „Unit verwenden“ nur für dieselbe Unit.</summary>
    [Test]
    procedure KeepsWindowPerMode;
    /// <summary>Gruppe, sonst Projekt; Name des Projekts und Wurzel; Zielunit nur bei „Unit verwenden“.</summary>
    [Test]
    procedure GroupAndTarget;
    /// <summary>uses-Ziele, Namen ohne Include, Liste und geöffnete Einträge.</summary>
    [Test]
    procedure EntriesAndNames;
    /// <summary>Argumente von Vorschau und addUses.</summary>
    [Test]
    procedure ServerArguments;
  end;

implementation

uses
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.UseUnit,
  Atlas.Core.UnitSearch.Plan;

function Entry(const AName, AFileName: string; AKind: TAtlasUnitKind): TAtlasUnitEntry;
begin
  Result := Default(TAtlasUnitEntry);
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.Kind := AKind;
end;

{ TAtlasUnitSearchPlanTests }

procedure TAtlasUnitSearchPlanTests.ActionsPerMode;
begin
  Assert.AreEqual('ViewUnitCommand', TAtlasUnitSearchPlan.IdeActionName(TAtlasUnitSearchMode.Search));
  Assert.AreEqual('FileUseUnitCommand', TAtlasUnitSearchPlan.IdeActionName(TAtlasUnitSearchMode.UseUnit));
  Assert.AreEqual('ViewFormCommand', TAtlasUnitSearchPlan.IdeActionName(TAtlasUnitSearchMode.Forms));
  Assert.AreEqual('Ctrl+F12', TAtlasUnitSearchPlan.IdeActionKey(TAtlasUnitSearchMode.Search));
  Assert.AreEqual('Alt+F11', TAtlasUnitSearchPlan.IdeActionKey(TAtlasUnitSearchMode.UseUnit));
  Assert.AreEqual('Shift+F12', TAtlasUnitSearchPlan.IdeActionKey(TAtlasUnitSearchMode.Forms));
  Assert.IsTrue(TAtlasUnitSearchPlan.Replaces(TAtlasUnitSearchMode.Search, True, False, False));
  Assert.IsTrue(TAtlasUnitSearchPlan.Replaces(TAtlasUnitSearchMode.UseUnit, False, True, False));
  Assert.IsTrue(TAtlasUnitSearchPlan.Replaces(TAtlasUnitSearchMode.Forms, False, False, True));
  Assert.IsFalse(TAtlasUnitSearchPlan.Replaces(TAtlasUnitSearchMode.Forms, True, True, False));
end;

procedure TAtlasUnitSearchPlanTests.TakesActionNeedsAll;
begin
  Assert.IsTrue(TAtlasUnitSearchPlan.TakesAction(True, True, False, False));
  Assert.IsFalse(TAtlasUnitSearchPlan.TakesAction(False, True, False, False), 'aus');
  Assert.IsFalse(TAtlasUnitSearchPlan.TakesAction(True, False, False, False), 'nicht übernommen');
  Assert.IsFalse(TAtlasUnitSearchPlan.TakesAction(True, True, True, False), 'Umschalt');
  Assert.IsFalse(TAtlasUnitSearchPlan.TakesAction(True, True, False, True), 'abgeschaltet');
end;

procedure TAtlasUnitSearchPlanTests.KeepsWindowPerMode;
begin
  Assert.IsTrue(TAtlasUnitSearchPlan.KeepsWindow(TAtlasUnitSearchMode.Search, TAtlasUnitSearchMode.Search,
    'C:\P\A.pas', 'C:\P\B.pas'));
  Assert.IsFalse(TAtlasUnitSearchPlan.KeepsWindow(TAtlasUnitSearchMode.Search, TAtlasUnitSearchMode.Forms, '', ''));
  Assert.IsTrue(TAtlasUnitSearchPlan.KeepsWindow(TAtlasUnitSearchMode.UseUnit, TAtlasUnitSearchMode.UseUnit,
    'C:\P\A.pas', 'c:\p\a.pas'));
  Assert.IsFalse(TAtlasUnitSearchPlan.KeepsWindow(TAtlasUnitSearchMode.UseUnit, TAtlasUnitSearchMode.UseUnit,
    'C:\P\A.pas', 'C:\P\B.pas'), 'andere Unit');
end;

procedure TAtlasUnitSearchPlanTests.GroupAndTarget;
var
  mGroup, mActive, mRoot: string;
begin
  TAtlasUnitSearchPlan.GroupInfo('C:\P\All.groupproj', 'C:\P\App\App.dproj', mGroup, mActive, mRoot);
  Assert.AreEqual('C:\P\All.groupproj', mGroup);
  Assert.AreEqual('App', mActive);
  Assert.AreEqual('C:\P', mRoot);
  TAtlasUnitSearchPlan.GroupInfo('', 'C:\P\App\App.dproj', mGroup, mActive, mRoot);
  Assert.AreEqual('C:\P\App\App.dproj', mGroup, 'ohne Gruppe das Projekt');
  Assert.AreEqual('C:\P\App', mRoot);
  TAtlasUnitSearchPlan.GroupInfo('', '', mGroup, mActive, mRoot);
  Assert.AreEqual('', mGroup);
  Assert.AreEqual('', mActive);
  Assert.AreEqual('', mRoot);
  Assert.AreEqual('Main', TAtlasUnitSearchPlan.TargetUnit(TAtlasUnitSearchMode.UseUnit, 'C:\P\Main.pas'));
  Assert.AreEqual('', TAtlasUnitSearchPlan.TargetUnit(TAtlasUnitSearchMode.Search, 'C:\P\Main.pas'));
end;

procedure TAtlasUnitSearchPlanTests.EntriesAndNames;
var
  mEntries: TAtlasUnitEntries;
  mNames: TArray<string>;
begin
  Assert.IsTrue(TAtlasUnitSearchPlan.UsesTarget('C:\P\A.PAS'));
  Assert.IsTrue(TAtlasUnitSearchPlan.UsesTarget('C:\P\App.dpr'));
  Assert.IsTrue(TAtlasUnitSearchPlan.UsesTarget('C:\P\Pkg.dpk'));
  Assert.IsFalse(TAtlasUnitSearchPlan.UsesTarget('C:\P\A.inc'));
  Assert.IsFalse(TAtlasUnitSearchPlan.UsesTarget(''));
  mEntries := TAtlasUnitEntries.Create(Entry('A', 'C:\P\A.pas', TAtlasUnitKind.Unit_),
    Entry('Defs', 'C:\P\Defs.inc', TAtlasUnitKind.Include), Entry('B', 'C:\P\B.pas', TAtlasUnitKind.Form));
  mNames := TAtlasUnitSearchPlan.UsesNames(mEntries);
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('A', mNames[0]);
  Assert.AreEqual('B', mNames[1]);
  Assert.AreEqual('A, Defs, B', TAtlasUnitSearchPlan.UnitList(mEntries));
  TAtlasUnitSearchPlan.MarkOpen(mEntries, TArray<string>.Create('c:\p\b.pas'));
  Assert.IsFalse(mEntries[0].IsOpen);
  Assert.IsTrue(mEntries[2].IsOpen, 'Groß/klein egal');
  mEntries := nil;
  mNames := nil;
end;

procedure TAtlasUnitSearchPlanTests.ServerArguments;
begin
  Assert.AreEqual('["file:///c:/p/a.pas",{"form":true,"usedBy":false}]',
    TAtlasUnitSearchPlan.PreviewArguments('file:///c:/p/a.pas', True, False));
  Assert.AreEqual('["file:///c:/p/a.pas",["B","C"]]',
    TAtlasUnitSearchPlan.AddUsesArguments('file:///c:/p/a.pas', TArray<string>.Create('B', 'C')));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnitSearchPlanTests);

end.
