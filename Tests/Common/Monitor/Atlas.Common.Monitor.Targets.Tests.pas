unit Atlas.Common.Monitor.Targets.Tests;

// Tests für Zielliste und gemerkten Stand des Prüffensters von AtlasMonitor (#1900): Art nach Endung, keine
// doppelten Ziele, Listendatei, Abschnitt "check" in monitor.json, Befehl des Editors.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMonitorTargetsTests = class
  public
    [Setup]
    procedure Setup;
    [Test]
    procedure KindFromExtension;
    [Test]
    procedure AddsEachPathOnce;
    [Test]
    procedure ListFileRoundTrip;
    [Test]
    procedure StateRoundTrip;
    [Test]
    procedure StateReadsLeniently;
    [Test]
    procedure EditorCommandFillsPlaceholders;
    [Test]
    procedure SettingsKeepCheckState;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Monitor.Commands,
  Atlas.Common.Monitor.Settings,
  Atlas.Common.Monitor.Targets;

function TargetOf(const APath: string): TMonitorTarget;
begin
  Result := Default(TMonitorTarget);
  Result.Path := APath;
  Result.Enabled := True;
end;

procedure TMonitorTargetsTests.Setup;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMonitorTargetsTests.KindFromExtension;
begin
  Assert.AreEqual<TMonitorTargetKind>(TMonitorTargetKind.Folder, TargetOf('C:\Src').Kind);
  Assert.AreEqual<TMonitorTargetKind>(TMonitorTargetKind.Project, TargetOf('C:\Src\App.DPROJ').Kind);
  Assert.AreEqual<TMonitorTargetKind>(TMonitorTargetKind.Group, TargetOf('C:\Src\Alle.groupproj').Kind);
  Assert.AreEqual<TMonitorTargetKind>(TMonitorTargetKind.SourceFile, TargetOf('C:\Src\Main.pas').Kind);
  Assert.AreEqual('Projektgruppe', TargetOf('a.groupproj').KindText);
end;

procedure TMonitorTargetsTests.AddsEachPathOnce;
var
  mList: TMonitorTargetList;
begin
  mList := Default(TMonitorTargetList);
  Assert.IsTrue(mList.Add('C:\A'));
  Assert.IsFalse(mList.Add('c:\a'), 'ohne Groß-/Kleinschreibung');
  Assert.IsFalse(mList.Add('  '));
  Assert.IsTrue(mList.Add('C:\B\B.dproj'));
  mList.Items[0].Enabled := False;
  Assert.AreEqual(1, Integer(Length(mList.EnabledPaths)));
  Assert.AreEqual('C:\B\B.dproj', mList.EnabledPaths[0]);
  mList.Delete(0);
  mList.Delete(5);
  Assert.AreEqual(1, Integer(Length(mList.Items)));
  Assert.AreEqual(0, mList.IndexOf('c:\b\b.dproj'));
  mList := Default(TMonitorTargetList);
end;

procedure TMonitorTargetsTests.ListFileRoundTrip;
var
  mList, mRead: TMonitorTargetList;
begin
  mList := Default(TMonitorTargetList);
  mList.Add('C:\A');
  mList.Add('C:\B.groupproj');
  mList.Items[1].Enabled := False;
  mRead := TMonitorTargetList.FromText(mList.ToText);
  Assert.AreEqual(2, Integer(Length(mRead.Items)));
  Assert.AreEqual('C:\B.groupproj', mRead.Items[1].Path);
  Assert.IsFalse(mRead.Items[1].Enabled);
  Assert.AreEqual(0, Integer(Length(TMonitorTargetList.FromText('kaputt').Items)));
  Assert.AreEqual(1, Integer(Length(TMonitorTargetList.FromText(
    '{"targets": [{"path": "X"}, 3, {"enabled": true}]}').Items)), 'Unbekanntes übergangen');
  mList := Default(TMonitorTargetList);
  mRead := Default(TMonitorTargetList);
end;

procedure TMonitorTargetsTests.StateRoundTrip;
var
  mState, mRead: TMonitorCheckState;
  mJson: TJSONObject;
begin
  mState := TMonitorCheckState.Defaults;
  mState.Targets.Add('C:\A');
  mState.Command := TMonitorCommand.Hotspots;
  mState.Options.Rules := 'a,b';
  mState.Options.ChangedLines := True;
  mState.Options.ReplayFile := 'r.json';
  mState.Editor := 'code -g "%file%:%line%"';
  mJson := mState.ToJson;
  try
    Assert.IsNull(mJson.GetValue('noIndex'), 'Aus wird nicht geschrieben');
    mRead := TMonitorCheckState.FromJson(mJson);
  finally
    mJson.Free;
  end;
  Assert.AreEqual<TMonitorCommand>(TMonitorCommand.Hotspots, mRead.Command);
  Assert.AreEqual('a,b', mRead.Options.Rules);
  Assert.IsTrue(mRead.Options.ChangedLines);
  Assert.IsFalse(mRead.Options.NoIndex);
  Assert.AreEqual('r.json', mRead.Options.ReplayFile);
  Assert.AreEqual('code -g "%file%:%line%"', mRead.Editor);
  Assert.AreEqual('C:\A', mRead.Targets.Items[0].Path);
  mState := Default(TMonitorCheckState);
  mRead := Default(TMonitorCheckState);
end;

procedure TMonitorTargetsTests.StateReadsLeniently;
var
  mState: TMonitorCheckState;
  mJson: TJSONObject;
begin
  mState := TMonitorCheckState.FromJson(nil);
  Assert.AreEqual<TMonitorCommand>(TMonitorCommand.Check, mState.Command);
  mJson := TJSONObject.ParseJSONValue('{"command": "gibtsnicht", "rules": 5}') as TJSONObject;
  try
    mState := TMonitorCheckState.FromJson(mJson);
  finally
    mJson.Free;
  end;
  Assert.AreEqual<TMonitorCommand>(TMonitorCommand.Check, mState.Command);
  Assert.AreEqual('', mState.Options.Rules);
  mState := Default(TMonitorCheckState);
end;

procedure TMonitorTargetsTests.EditorCommandFillsPlaceholders;
begin
  Assert.AreEqual('', TMonitorCheckState.EditorCommand(' ', 'a.pas', 1, 2));
  Assert.AreEqual('code -g "C:\A.pas:12:5"', TMonitorCheckState.EditorCommand('code -g "%FILE%:%line%:%column%"',
    'C:\A.pas', 12, 5));
end;

procedure TMonitorTargetsTests.SettingsKeepCheckState;
var
  mSettings: TMonitorSettings;
  mText: string;
begin
  mSettings := TMonitorSettings.Defaults;
  mSettings.Check.Targets.Add('C:\A');
  mSettings.Check.Command := TMonitorCommand.Query;
  mText := mSettings.ToText('{"other": 1}');
  Assert.IsTrue(mText.Contains('"other"'), mText);
  mSettings := TMonitorSettings.FromText(mText);
  Assert.AreEqual<TMonitorCommand>(TMonitorCommand.Query, mSettings.Check.Command);
  Assert.AreEqual(1, Integer(Length(mSettings.Check.Targets.Items)));
  Assert.AreEqual<TMonitorCommand>(TMonitorCommand.Check, TMonitorSettings.FromText('').Check.Command);
  mSettings := Default(TMonitorSettings);
  mText := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TMonitorTargetsTests);

end.
