unit Atlas.Core.Tests.LeakSetup.Tests;

// Tests des Dialogs „Leckprüfung einrichten …“ ohne VCL (#1880): Antwort
// lesen, Varianten und Vorauswahl, Zeilen des Stands, Plan lesen, Symbole in
// DCC_Define einfügen, Argumente des Serverbefehls.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasLeakSetupTests = class
  public
    [Test]
    procedure ReadsState;
    [Test]
    procedure RejectsOtherAnswers;
    [Test]
    procedure PackageAllowsNothing;
    [Test]
    procedure MissingSourceDisablesVariant;
    [Test]
    procedure OtherManagerInUsesDisablesVariant;
    [Test]
    procedure PreselectPrefersManagerInUses;
    [Test]
    procedure PreselectPrefersFastMM5;
    [Test]
    procedure StatusOfPackageIsOneLine;
    [Test]
    procedure StatusListsUsesProblems;
    [Test]
    procedure StatusOfTestProjectNamesMonitor;
    [Test]
    procedure ReadsPlan;
    [Test]
    procedure PlanNeedsPlanObject;
    [Test]
    procedure DefinesAddedOnce;
    [Test]
    procedure DefinesKeepInheritedLast;
    [Test]
    procedure ArgumentsWithAndWithoutWish;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tests.LeakSetup;

const
  cState = '{"project":"C:\\P\\App.dproj","mainSource":"C:\\P\\App.dpr","platform":"Win64",' +
    '"isPackage":false,"isTestProject":false,"leakMonitor":"","hasUses":true,"hasMainBlock":true,' +
    '"fastmm4":{"file":"","version":"","optionsFile":""},' +
    '"fastmm5":{"file":"C:\\Lib\\FastMM5.pas","version":"5.06","optionsFile":""},' +
    '"uses":{"manager":"none","first":false,"debugOnly":false},' +
    '"report":{"line":12,"debugOnly":false},"debugDefine":false,"fileReport":false,' +
    '"dll":{"name":"FastMM_FullDebugMode64.dll","file":"","source":"","target":"C:\\P\\Win64\\Debug"}}';

function State(const AJson: string): TAtlasLeakSetupInfo;
begin
  Assert.IsTrue(TAtlasLeakSetupInfo.FromJson(AJson, Result), 'Antwort lesbar');
end;

function HasLine(const AStatus: TArray<TAtlasLeakStatus>; ALine: TAtlasLeakLine; out AItem: TAtlasLeakStatus): Boolean;
var
  mItem: TAtlasLeakStatus;
begin
  AItem := Default(TAtlasLeakStatus);
  for mItem in AStatus do
  begin
    if mItem.Line = ALine then
    begin
      AItem := mItem;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasLeakSetupTests.ReadsState;
var
  mInfo: TAtlasLeakSetupInfo;
begin
  mInfo := State(cState);
  Assert.AreEqual('C:\P\App.dpr', mInfo.MainSource);
  Assert.AreEqual('Win64', mInfo.Platform);
  Assert.AreEqual('C:\Lib\FastMM5.pas', mInfo.Sources[TAtlasLeakChoice.FastMM5].FileName);
  Assert.AreEqual('5.06', mInfo.Sources[TAtlasLeakChoice.FastMM5].Version);
  Assert.AreEqual(12, mInfo.ReportLine);
  Assert.AreEqual('FastMM_FullDebugMode64.dll', mInfo.DllName);
  Assert.AreEqual('C:\P\Win64\Debug', mInfo.DllTarget);
  Assert.IsTrue(mInfo.UsesManager = TAtlasLeakChoice.Simple, 'kein Speichermanager im uses');
end;

procedure TAtlasLeakSetupTests.RejectsOtherAnswers;
var
  mInfo: TAtlasLeakSetupInfo;
begin
  Assert.IsFalse(TAtlasLeakSetupInfo.FromJson('', mInfo));
  Assert.IsFalse(TAtlasLeakSetupInfo.FromJson('[1]', mInfo));
  Assert.IsFalse(TAtlasLeakSetupInfo.FromJson('{"project":"x"}', mInfo));
end;

procedure TAtlasLeakSetupTests.PackageAllowsNothing;
var
  mInfo: TAtlasLeakSetupInfo;
begin
  mInfo := State(StringReplace(cState, '"isPackage":false', '"isPackage":true', []));
  Assert.IsFalse(mInfo.Available(TAtlasLeakChoice.Simple));
  Assert.IsFalse(mInfo.Available(TAtlasLeakChoice.FastMM5));
end;

procedure TAtlasLeakSetupTests.MissingSourceDisablesVariant;
var
  mInfo: TAtlasLeakSetupInfo;
begin
  mInfo := State(cState);
  Assert.IsTrue(mInfo.Available(TAtlasLeakChoice.Simple));
  Assert.IsFalse(mInfo.Available(TAtlasLeakChoice.FastMM4), 'FastMM4 nicht gefunden');
  Assert.IsTrue(mInfo.Available(TAtlasLeakChoice.FastMM5));
end;

procedure TAtlasLeakSetupTests.OtherManagerInUsesDisablesVariant;
var
  mInfo: TAtlasLeakSetupInfo;
begin
  mInfo := State(StringReplace(StringReplace(cState, '"manager":"none"', '"manager":"fastmm4"', []),
    '"fastmm4":{"file":""', '"fastmm4":{"file":"C:\\Lib\\FastMM4.pas"', []));
  Assert.IsTrue(mInfo.Available(TAtlasLeakChoice.FastMM4));
  Assert.IsFalse(mInfo.Available(TAtlasLeakChoice.FastMM5), 'FastMM4 steht schon im uses');
end;

procedure TAtlasLeakSetupTests.PreselectPrefersManagerInUses;
var
  mInfo: TAtlasLeakSetupInfo;
begin
  mInfo := State(StringReplace(cState, '"manager":"none"', '"manager":"fastmm4"', []));
  Assert.IsTrue(mInfo.Preselect = TAtlasLeakChoice.FastMM4);
end;

procedure TAtlasLeakSetupTests.PreselectPrefersFastMM5;
var
  mInfo: TAtlasLeakSetupInfo;
begin
  Assert.IsTrue(State(cState).Preselect = TAtlasLeakChoice.FastMM5);
  mInfo := State(StringReplace(cState, '"file":"C:\\Lib\\FastMM5.pas"', '"file":""', []));
  Assert.IsTrue(mInfo.Preselect = TAtlasLeakChoice.Simple, 'ohne FastMM bleibt Einfach');
end;

procedure TAtlasLeakSetupTests.StatusOfPackageIsOneLine;
var
  mStatus: TArray<TAtlasLeakStatus>;
begin
  mStatus := State(StringReplace(cState, '"isPackage":false', '"isPackage":true', [])).Status;
  Assert.AreEqual(1, Integer(Length(mStatus)));
  Assert.IsTrue(mStatus[0].Line = TAtlasLeakLine.Package);
  Assert.IsFalse(mStatus[0].Ok);
  Assert.AreEqual('App.dpr', mStatus[0].Value);
end;

procedure TAtlasLeakSetupTests.StatusListsUsesProblems;
var
  mStatus: TArray<TAtlasLeakStatus>;
  mItem: TAtlasLeakStatus;
begin
  mStatus := State(StringReplace(cState, '"manager":"none"', '"manager":"fastmm5"', [])).Status;
  Assert.IsTrue(HasLine(mStatus, TAtlasLeakLine.Source5, mItem));
  Assert.IsTrue(mItem.Ok);
  Assert.AreEqual('5.06 · C:\Lib\FastMM5.pas', mItem.Value);
  Assert.IsTrue(HasLine(mStatus, TAtlasLeakLine.UsesUnit, mItem));
  Assert.AreEqual('FastMM5', mItem.Value);
  Assert.IsTrue(HasLine(mStatus, TAtlasLeakLine.UsesNotFirst, mItem), 'nicht erste Unit');
  Assert.IsTrue(HasLine(mStatus, TAtlasLeakLine.UsesNotDebug, mItem), 'nicht nur im Debug');
  Assert.IsTrue(HasLine(mStatus, TAtlasLeakLine.ReportNotDebug, mItem));
  Assert.AreEqual('12', mItem.Value);
  Assert.IsTrue(HasLine(mStatus, TAtlasLeakLine.Dll, mItem));
  Assert.IsFalse(mItem.Ok);
  Assert.AreEqual('FastMM_FullDebugMode64.dll', mItem.Value);
  Assert.IsFalse(HasLine(mStatus, TAtlasLeakLine.LeakMonitor, mItem), 'kein Testprojekt');
end;

procedure TAtlasLeakSetupTests.StatusOfTestProjectNamesMonitor;
var
  mStatus: TArray<TAtlasLeakStatus>;
  mItem: TAtlasLeakStatus;
begin
  mStatus := State(StringReplace(StringReplace(cState, '"isTestProject":false', '"isTestProject":true', []),
    '"leakMonitor":""', '"leakMonitor":"DUnitX.MemoryLeakMonitor.FastMM5"', [])).Status;
  Assert.IsTrue(HasLine(mStatus, TAtlasLeakLine.LeakMonitor, mItem));
  Assert.IsTrue(mItem.Ok);
  Assert.AreEqual('DUnitX.MemoryLeakMonitor.FastMM5', mItem.Value);
  Assert.IsFalse(HasLine(mStatus, TAtlasLeakLine.UsesNotFirst, mItem), 'ohne Speichermanager keine Folgezeilen');
end;

procedure TAtlasLeakSetupTests.ReadsPlan;
var
  mPlan: TAtlasLeakSetupPlan;
begin
  Assert.IsTrue(TAtlasLeakSetupPlan.FromJson('{"mainSource":"x","plan":{"manager":"fastmm5","fileReport":true,' +
    '"edit":{"changes":{}},"defines":["FastMM_FullDebugMode"],"copyDll":true,"empty":false}}', mPlan));
  Assert.IsTrue(mPlan.Choice = TAtlasLeakChoice.FastMM5);
  Assert.IsTrue(mPlan.FileReport);
  Assert.AreEqual('{"changes":{}}', mPlan.EditJson);
  Assert.AreEqual(1, Integer(Length(mPlan.Defines)));
  Assert.AreEqual('FastMM_FullDebugMode', mPlan.Defines[0]);
  Assert.IsTrue(mPlan.CopyDll);
  Assert.IsFalse(mPlan.Empty);
end;

procedure TAtlasLeakSetupTests.PlanNeedsPlanObject;
var
  mPlan: TAtlasLeakSetupPlan;
begin
  Assert.IsFalse(TAtlasLeakSetupPlan.FromJson(cState, mPlan));
  Assert.IsFalse(TAtlasLeakSetupPlan.FromJson('kein JSON', mPlan));
end;

procedure TAtlasLeakSetupTests.DefinesAddedOnce;
begin
  Assert.AreEqual('DEBUG;FullDebugMode', TAtlasLeakSetup.WithDefines('DEBUG', ['FullDebugMode']));
  Assert.AreEqual('DEBUG;fulldebugmode', TAtlasLeakSetup.WithDefines('DEBUG;fulldebugmode', ['FullDebugMode']),
    'Groß-/Kleinschreibung egal');
  Assert.AreEqual('FullDebugMode', TAtlasLeakSetup.WithDefines('', ['FullDebugMode']));
end;

procedure TAtlasLeakSetupTests.DefinesKeepInheritedLast;
begin
  Assert.AreEqual('DEBUG;FastMM_FullDebugMode;$(DCC_Define)', TAtlasLeakSetup.WithDefines('DEBUG;$(DCC_Define)',
    ['FastMM_FullDebugMode']));
end;

procedure TAtlasLeakSetupTests.ArgumentsWithAndWithoutWish;
var
  mPlain, mWish: string;
begin
  mPlain := TAtlasLeakSetup.ArgumentsJson('C:\P\App.dproj', False, TAtlasLeakChoice.Simple, False);
  Assert.IsTrue(mPlain.StartsWith('["file:'), mPlain);
  Assert.IsFalse(mPlain.Contains('manager'), mPlain);
  mWish := TAtlasLeakSetup.ArgumentsJson('C:\P\App.dproj', True, TAtlasLeakChoice.FastMM4, True);
  Assert.IsTrue(mWish.Contains('"manager":"fastmm4"'), mWish);
  Assert.IsTrue(mWish.Contains('"fileReport":true'), mWish);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLeakSetupTests);

end.
