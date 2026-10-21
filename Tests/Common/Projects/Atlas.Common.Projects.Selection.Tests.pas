unit Atlas.Common.Projects.Selection.Tests;

// Tests der gemerkten Projektwahl (#46): Konfiguration und Plattform je
// Projekt, gewähltes Projekt je Arbeitsbereich, Datei über Neustarts, kaputte
// Datei, Aufheben der Wahl.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TProjectSelectionTests = class
  public
    [Test]
    procedure BuildIsMergedAndIgnoresCase;
    [Test]
    procedure ProjectCanBeCleared;
    [Test]
    procedure SurvivesRestart;
    [Test]
    procedure BrokenFileStartsEmpty;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Projects.Selection;

{ TProjectSelectionTests }

procedure TProjectSelectionTests.BuildIsMergedAndIgnoresCase;
var
  Selection: TProjectSelection;
  Choice: TProjectBuildChoice;
begin
  Selection := TProjectSelection.Create('');
  try
    Assert.IsFalse(Selection.Build('C:\P\App.dproj', Choice));
    Selection.SetBuild('C:\P\App.dproj', 'Release', '');
    Selection.SetBuild('c:\p\app.dproj', '', 'Win64');
    Assert.IsTrue(Selection.Build('C:\P\APP.DPROJ', Choice));
    Assert.AreEqual('Release', Choice.Config);
    Assert.AreEqual('Win64', Choice.Platform);
    Selection.SetBuild('C:\P\App.dproj', '', '');
    Assert.IsFalse(Selection.Build('C:\P\App.dproj', Choice));
  finally
    Selection.Free;
  end;
end;

procedure TProjectSelectionTests.ProjectCanBeCleared;
var
  Selection: TProjectSelection;
begin
  Selection := TProjectSelection.Create('');
  try
    Assert.AreEqual('', Selection.Project('file:///c%3A/P'));
    Selection.SetProject('file:///c%3A/P', 'C:\P\Kern.dproj');
    Assert.AreEqual('C:\P\Kern.dproj', Selection.Project('FILE:///C%3A/P'));
    Selection.SetProject('file:///c%3A/P', '');
    Assert.AreEqual('', Selection.Project('file:///c%3A/P'));
  finally
    Selection.Free;
  end;
end;

procedure TProjectSelectionTests.SurvivesRestart;
var
  FileName: string;
  Selection: TProjectSelection;
  Choice: TProjectBuildChoice;
begin
  FileName := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'AtlasAuswahlTest'), 'projektauswahl.json');
  if TFile.Exists(FileName) then
    TFile.Delete(FileName);
  Selection := TProjectSelection.Create(FileName);
  try
    Selection.SetBuild('C:\P\App.dproj', 'Debug', 'Win32');
    Selection.SetProject('Gruppe', 'C:\P\App.dproj');
  finally
    Selection.Free;
  end;
  Assert.IsTrue(TFile.Exists(FileName));
  Selection := TProjectSelection.Create(FileName);
  try
    Assert.IsTrue(Selection.Build('C:\P\App.dproj', Choice));
    Assert.AreEqual('Debug', Choice.Config);
    Assert.AreEqual('Win32', Choice.Platform);
    Assert.AreEqual('C:\P\App.dproj', Selection.Project('Gruppe'));
    // Schlüssel behalten ihre Schreibweise.
    Assert.IsTrue(Selection.ToText.Contains('"C:\\P\\App.dproj":{'), Selection.ToText);
  finally
    Selection.Free;
    TFile.Delete(FileName);
  end;
end;

procedure TProjectSelectionTests.BrokenFileStartsEmpty;
var
  Selection: TProjectSelection;
begin
  Selection := TProjectSelection.Create('');
  try
    Selection.LoadText('{"projects": {"Gruppe": "C:\\P\\App.dproj"}}');
    Assert.AreEqual('C:\P\App.dproj', Selection.Project('Gruppe'));
    Selection.LoadText('{kaputt');
    Assert.AreEqual('', Selection.Project('Gruppe'));
    Selection.LoadText('{"builds": [], "projects": {"Gruppe": 3}}');
    Assert.AreEqual('', Selection.Project('Gruppe'));
  finally
    Selection.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectSelectionTests);

end.
