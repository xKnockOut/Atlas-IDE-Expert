unit Atlas.UI.Debug.DialogSmoke.Tests;

// Rauchtest der Dialoge von Atlas.IDE.Debugger: Jeder Dialog entsteht mit kleinster Eingabe, bekommt Fenster für
// sich und alle Steuerelemente, durchläuft DoShow wie beim Zeigen und wird freigegeben (TAtlasDialogSmoke).
// Dialoge mit eigenen Tests stehen dort; Tools/Check-DialogTests.ps1 prüft, dass jeder Dialog gebaut wird.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.EditValue;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebuggerDialogSmokeTests = class
  private
    procedure RealizeEditValue(const AInfo: TAtlasEditInfo);
  public
    [Test]
    procedure Viewer;
    [Test]
    procedure EditValuePlain;
    [Test]
    procedure EditValueEnum;
    [Test]
    procedure EditValueSet;
    [Test]
    procedure LaunchGroups;
    [Test]
    procedure Logpoint;
    [Test]
    procedure ProcessChoice;
  end;

implementation

uses
  Atlas.Core.Debug.LaunchGroups,
  Atlas.Core.Debug.Reattach,
  Atlas.UI.Debug.EditValueDialog,
  Atlas.UI.Debug.LaunchGroupsDialog,
  Atlas.UI.Debug.LogpointDialog,
  Atlas.UI.Debug.ProcessChoice,
  Atlas.UI.Debug.Viewer,
  Atlas.Tests.DialogSmoke;

{ TAtlasDebuggerDialogSmokeTests }

procedure TAtlasDebuggerDialogSmokeTests.RealizeEditValue(const AInfo: TAtlasEditInfo);
var
  mDialog: TAtlasEditValueDialog;
begin
  mDialog := TAtlasEditValueDialog.CreateFor(nil, AInfo, 'Rot');
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDebuggerDialogSmokeTests.Viewer;
var
  mDialog: TAtlasDebugViewer;
begin
  mDialog := TAtlasDebugViewer.CreateViewer(nil);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    mDialog.MarkUnavailable('Prozess beendet');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDebuggerDialogSmokeTests.EditValuePlain;
begin
  RealizeEditValue(TAtlasEditInfo.Plain('mText'));
end;

procedure TAtlasDebuggerDialogSmokeTests.EditValueEnum;
var
  mInfo: TAtlasEditInfo;
begin
  mInfo := TAtlasEditInfo.Plain('mFarbe');
  mInfo.Kind := TAtlasEditKind.Enum;
  mInfo.TypeName := 'TFarbe';
  mInfo.Values := TArray<string>.Create('Rot', 'Gruen');
  RealizeEditValue(mInfo);
end;

procedure TAtlasDebuggerDialogSmokeTests.EditValueSet;
var
  mInfo: TAtlasEditInfo;
begin
  mInfo := TAtlasEditInfo.Plain('mFarben');
  mInfo.Kind := TAtlasEditKind.Set_;
  mInfo.TypeName := 'TFarben';
  mInfo.Values := TArray<string>.Create('Rot', 'Gruen');
  RealizeEditValue(mInfo);
end;

procedure TAtlasDebuggerDialogSmokeTests.LaunchGroups;
var
  mGroup: TAtlasLaunchGroup;
  mItem: TAtlasLaunchItem;
  mDialog: TAtlasLaunchGroupsDialog;
begin
  mItem := Default(TAtlasLaunchItem);
  mItem.Project := 'Server.dproj';
  mItem.Debug := True;
  mGroup := Default(TAtlasLaunchGroup);
  mGroup.Name := 'Alle';
  mGroup.Items := TArray<TAtlasLaunchItem>.Create(mItem);
  mDialog := TAtlasLaunchGroupsDialog.CreateFor(nil, TArray<TAtlasLaunchGroup>.Create(mGroup), 'Alle');
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDebuggerDialogSmokeTests.Logpoint;
var
  mDialog: TAtlasLogpointDialog;
begin
  mDialog := TAtlasLogpointDialog.CreateFor(nil, 'Unit1.pas:12', True);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDebuggerDialogSmokeTests.ProcessChoice;
var
  mDialog: TAtlasProcessChoiceDialog;
begin
  mDialog := TAtlasProcessChoiceDialog.CreateFor(nil, 'Kunden.exe',
    TArray<TAtlasReattachProcess>.Create(TAtlasReattachProcess.Create(42, 'C:\Kunden\Kunden.exe', 'Kunden.exe')));
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.AreEqual(1, mDialog.List.Items.Count, 'Prozesse nach DoShow');
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebuggerDialogSmokeTests);

end.
