unit Atlas.UI.Tests.SettingsSection;

// Abschnitte des Moduls Tests im Optionsdialog (#1456; vorher in den Teilen
// „Compiler“, „Debuggen“ und „Editor“ von Base): je Seite eine Klasse, weil die Einstellungen des Moduls auf drei
// Seiten stehen.
// - „Compiler“: Modulschalter, DUnitX-Tests ausführen (#69), betroffene Tests (#1353) und betroffene Tests beim
//   Speichern (#1775).
// - „Debuggen“: einzelnen Test im Debugger starten (#585).
// - „Editor“: Code Lens an Testmethoden, veraltete Ergebnisse (#1770) und Marke „getestet von“ (#1778).

interface

uses
  Atlas.UI.Settings.Section;

type
  TAtlasTestsCompilerSection = class(TAtlasSettingsSection)
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

  TAtlasTestsDebugSection = class(TAtlasSettingsSection)
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

  TAtlasTestsEditorSection = class(TAtlasSettingsSection)
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

const
  cTestsSettingsOwner = 'atlas.tests';

implementation

uses
  Atlas.UI.Tests.Strings;

{ TAtlasTestsCompilerSection }

function TAtlasTestsCompilerSection.OwnerId: string;
begin
  Result := cTestsSettingsOwner;
end;

function TAtlasTestsCompilerSection.AreaId: string;
begin
  Result := 'Compiler';
end;

procedure TAtlasTestsCompilerSection.BuildRows;
begin
  ModuleSwitch('tests.enabled');
  Switch('tests.run', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestRun));
  Switch('tests.buildFirst', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsBuildFirst));
  Switch('tests.afterBuild', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsAfterBuild));
  Switch('tests.affected', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsAffected));
  Number('tests.affectedDepth', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsAffectedDepth));
  Switch('tests.affectedBeforeCommit', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsAffectedBeforeCommit));
  Switch('tests.onSave', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsOnSave));
  Number('tests.onSave.max', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsOnSaveMax));
  Switch('tests.failureAtAssert', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsFailureAtAssert));
  Switch('tests.failureInline', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsFailureInline));
  Switch('tests.leaks', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsLeaks));
  Switch('tests.compare', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsCompare));
  Switch('tests.compare.format', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsCompareFormat));
  Switch('tests.approvalFiles', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsApprovalFiles));
  Switch('tests.showDuration', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsShowDuration));
  Number('tests.slowMs', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsSlowMs));
  Switch('tests.window', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsWindow));
  Switch('tests.testCaseTable', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsCaseTable));
  Switch('tests.leakSetup', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsLeakSetup));
end;

{ TAtlasTestsDebugSection }

function TAtlasTestsDebugSection.OwnerId: string;
begin
  Result := cTestsSettingsOwner;
end;

function TAtlasTestsDebugSection.AreaId: string;
begin
  Result := 'Debuggen';
end;

procedure TAtlasTestsDebugSection.BuildRows;
begin
  Switch('tests.debug', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestDebug));
  Switch('debug.testBreakAtStart', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestBreakAtStart));
  Switch('tests.fromDebugStop', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsFromDebugStop));
  Switch('tests.fromDebugStop.fields', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsFromDebugStopFields));
  Switch('tests.fromDebugStop.properties',
    TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsFromDebugStopProperties));
  Number('tests.fromDebugStop.maxArray',
    TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsFromDebugStopMaxArray));
end;

{ TAtlasTestsEditorSection }

function TAtlasTestsEditorSection.OwnerId: string;
begin
  Result := cTestsSettingsOwner;
end;

function TAtlasTestsEditorSection.AreaId: string;
begin
  Result := 'Editor';
end;

procedure TAtlasTestsEditorSection.BuildRows;
begin
  Switch('codeLens.tests', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsCodeLensTests));
  Switch('tests.stale', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsStale));
  Switch('tests.stale.units', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsStaleUnits));
  Switch('codeLens.coveredBy', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsCodeLensCoveredBy));
  Number('tests.coveredBy.depth', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsCoveredByDepth));
  Switch('tests.coveredBy.private', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsCoveredByPrivate));
  Switch('codeLens.untested', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsCodeLensUntested));
  Number('tests.untested.warnPercent', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsUntestedWarnPercent));
end;

end.
