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
  mSelection: TProjectSelection;
  mChoice: TProjectBuildChoice;
begin
  mSelection := TProjectSelection.Create('');
  try
    Assert.IsFalse(mSelection.Build('C:\P\App.dproj', mChoice));
    mSelection.SetBuild('C:\P\App.dproj', 'Release', '');
    mSelection.SetBuild('c:\p\app.dproj', '', 'Win64');
    Assert.IsTrue(mSelection.Build('C:\P\APP.DPROJ', mChoice));
    Assert.AreEqual('Release', mChoice.Config);
    Assert.AreEqual('Win64', mChoice.Platform);
    mSelection.SetBuild('C:\P\App.dproj', '', '');
    Assert.IsFalse(mSelection.Build('C:\P\App.dproj', mChoice));
  finally
    mSelection.Free;
  end;
end;

procedure TProjectSelectionTests.ProjectCanBeCleared;
var
  mSelection: TProjectSelection;
begin
  mSelection := TProjectSelection.Create('');
  try
    Assert.AreEqual('', mSelection.Project('file:///c%3A/P'));
    mSelection.SetProject('file:///c%3A/P', 'C:\P\Kern.dproj');
    Assert.AreEqual('C:\P\Kern.dproj', mSelection.Project('FILE:///C%3A/P'));
    mSelection.SetProject('file:///c%3A/P', '');
    Assert.AreEqual('', mSelection.Project('file:///c%3A/P'));
  finally
    mSelection.Free;
  end;
end;

procedure TProjectSelectionTests.SurvivesRestart;
var
  mFileName: string;
  mSelection: TProjectSelection;
  mChoice: TProjectBuildChoice;
begin
  mFileName := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'AtlasAuswahlTest'), 'projektauswahl.json');
  if TFile.Exists(mFileName) then
  begin
    TFile.Delete(mFileName);
  end;
  mSelection := TProjectSelection.Create(mFileName);
  try
    mSelection.SetBuild('C:\P\App.dproj', 'Debug', 'Win32');
    mSelection.SetProject('Gruppe', 'C:\P\App.dproj');
  finally
    mSelection.Free;
  end;
  Assert.IsTrue(TFile.Exists(mFileName));
  mSelection := TProjectSelection.Create(mFileName);
  try
    Assert.IsTrue(mSelection.Build('C:\P\App.dproj', mChoice));
    Assert.AreEqual('Debug', mChoice.Config);
    Assert.AreEqual('Win32', mChoice.Platform);
    Assert.AreEqual('C:\P\App.dproj', mSelection.Project('Gruppe'));
    // Schlüssel behalten ihre Schreibweise.
    Assert.IsTrue(mSelection.ToText.Contains('"C:\\P\\App.dproj":{'), mSelection.ToText);
  finally
    mSelection.Free;
    TFile.Delete(mFileName);
  end;
end;

procedure TProjectSelectionTests.BrokenFileStartsEmpty;
var
  mSelection: TProjectSelection;
begin
  mSelection := TProjectSelection.Create('');
  try
    mSelection.LoadText('{"projects": {"Gruppe": "C:\\P\\App.dproj"}}');
    Assert.AreEqual('C:\P\App.dproj', mSelection.Project('Gruppe'));
    mSelection.LoadText('{kaputt');
    Assert.AreEqual('', mSelection.Project('Gruppe'));
    mSelection.LoadText('{"builds": [], "projects": {"Gruppe": 3}}');
    Assert.AreEqual('', mSelection.Project('Gruppe'));
  finally
    mSelection.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectSelectionTests);

end.
