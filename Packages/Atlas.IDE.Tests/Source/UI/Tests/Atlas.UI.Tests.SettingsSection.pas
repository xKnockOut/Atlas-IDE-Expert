unit Atlas.UI.Tests.SettingsSection;

// Abschnitte des Moduls Tests im Optionsdialog (#1456; vorher in den Teilen
// „Compiler“, „Debuggen“ und „Editor“ von Base): je Seite eine Klasse, weil die Einstellungen des Moduls auf drei
// Seiten stehen.
// - „Compiler“: Modulschalter, DUnitX-Tests ausführen (#69) und betroffene Tests (#1353).
// - „Debuggen“: einzelnen Test im Debugger starten (#585).
// - „Editor“: Code Lens an Testmethoden und veraltete Ergebnisse (#1770).

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
  Switch('tests.failureAtAssert', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsFailureAtAssert));
  Switch('tests.failureInline', TAtlasTestsStrings.Text(TAtlasTestsTextId.SettingsTestsFailureInline));
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
end;

end.
