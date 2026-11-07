unit Shell.Commands.Tests;

// Fachlogik der Befehle atlas.selectBuild, Formulare umwandeln und Index löschen
// außerhalb von TServerComposition (Code-Review S-02).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellCommandsTests = class
  public
    [Test]
    procedure SelectBuildArgs_Empty_NoChanges;
    [Test]
    procedure SelectBuildArgs_ReadsAllFields;
    [Test]
    procedure SelectBuildArgs_EmptyDefinesStillReplace;
    [Test]
    procedure ProjectItem_PrefersChosenValues;
    [Test]
    procedure FormFiles_UriGivesThatFile;
    [Test]
    procedure FormFiles_CollectsExistingForms;
    [Test]
    procedure IndexAnswer_HasCounts;
    [Test]
    procedure ClearCaches_RemovesCacheFiles;
    [Test]
    procedure SelectProjectArgs_QueryClearAndChoose;
    [Test]
    procedure ProjectChoices_NamesSelectedAndActive;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract,
  Shell.Commands.Build,
  Shell.Commands.Index;

function Args(const AJson: string): TJSONArray;
begin
  Result := TJSONObject.ParseJSONValue(AJson) as TJSONArray;
end;

procedure TShellCommandsTests.SelectBuildArgs_Empty_NoChanges;
var
  mParsed: TSelectBuildArgs;
begin
  mParsed := TSelectBuildArgs.Parse(nil);
  Assert.IsFalse(mParsed.Changes);
  Assert.AreEqual('', mParsed.Uri);
end;

procedure TShellCommandsTests.SelectProjectArgs_QueryClearAndChoose;
var
  mList: TJSONArray;
  mParsed: TSelectProjectArgs;
begin
  mParsed := TSelectProjectArgs.Parse(nil);
  Assert.IsFalse(mParsed.HasProject);
  mList := Args('[{"project": 3}]');
  try
    Assert.IsFalse(TSelectProjectArgs.Parse(mList).HasProject, 'Keine Zahl');
  finally
    mList.Free;
  end;
  mList := Args('[{"project": ""}]');
  try
    mParsed := TSelectProjectArgs.Parse(mList);
  finally
    mList.Free;
  end;
  Assert.IsTrue(mParsed.HasProject);
  Assert.AreEqual('', mParsed.Project);
  mList := Args('[{"project": " Kern "}]');
  try
    mParsed := TSelectProjectArgs.Parse(mList);
  finally
    mList.Free;
  end;
  Assert.AreEqual('Kern', mParsed.Project);
end;

procedure TShellCommandsTests.ProjectChoices_NamesSelectedAndActive;
var
  mItems: TArray<TProjectChoiceItem>;
  mAnswer: TJSONObject;
begin
  SetLength(mItems, 2);
  mItems[0].Name := 'App';
  mItems[0].Project := 'C:\P\App.dproj';
  mItems[0].Active := True;
  mItems[1].Name := 'Kern';
  mItems[1].Project := 'C:\P\Kern.dproj';
  mItems[1].Selected := True;
  Assert.AreEqual(1, TBuildCommands.FindProject(mItems, 'kern'));
  Assert.AreEqual(0, TBuildCommands.FindProject(mItems, 'c:\p\app.dproj'));
  Assert.AreEqual(-1, TBuildCommands.FindProject(mItems, 'Fehlt'));
  mAnswer := TBuildCommands.ProjectChoices(mItems);
  try
    Assert.AreEqual('C:\P\Kern.dproj', mAnswer.GetValue<string>('selected'));
    Assert.AreEqual('C:\P\App.dproj', mAnswer.GetValue<string>('active'));
    Assert.AreEqual(2, mAnswer.GetValue<TJSONArray>('projects').Count);
  finally
    mAnswer.Free;
  end;
end;

procedure TShellCommandsTests.SelectBuildArgs_ReadsAllFields;
var
  mList: TJSONArray;
  mParsed: TSelectBuildArgs;
begin
  mList := Args('[{"config": "Release", "platform": "Win64", "uri": "file:///c%3A/a.pas", "defines": ["A", {}, "B"]}]');
  try
    mParsed := TSelectBuildArgs.Parse(mList);
  finally
    mList.Free;
  end;
  Assert.AreEqual('Release', mParsed.Config);
  Assert.AreEqual('Win64', mParsed.Platform);
  Assert.AreEqual('file:///c%3A/a.pas', mParsed.Uri);
  Assert.IsTrue(mParsed.HasDefines);
  Assert.AreEqual(2, Integer(Length(mParsed.Defines)), 'Nur Strings');
  Assert.IsTrue(mParsed.Changes);
end;

procedure TShellCommandsTests.SelectBuildArgs_EmptyDefinesStillReplace;
var
  mList: TJSONArray;
  mParsed: TSelectBuildArgs;
begin
  mList := Args('[{"defines": []}]');
  try
    mParsed := TSelectBuildArgs.Parse(mList);
  finally
    mList.Free;
  end;
  Assert.IsTrue(mParsed.HasDefines);
  Assert.IsTrue(mParsed.Changes);
end;

procedure TShellCommandsTests.ProjectItem_PrefersChosenValues;
var
  mProject: TProjectInfo;
  mChosen: TSelectBuildArgs;
  mItem: TJSONObject;
begin
  mProject := Default(TProjectInfo);
  mProject.FileName := 'App.dproj';
  mProject.Config := 'Debug';
  mProject.Platform := 'Win32';
  mProject.Configs := ['Debug', 'Release'];
  mProject.Platforms := ['Win32', 'Win64'];
  mChosen := Default(TSelectBuildArgs);
  mChosen.Platform := 'Win64';
  mItem := TBuildCommands.ProjectItem('App', mProject, mChosen);
  try
    Assert.AreEqual('App', mItem.GetValue<string>('folder'));
    Assert.AreEqual('App.dproj', mItem.GetValue<string>('project'));
    Assert.AreEqual('Debug', mItem.GetValue<string>('config'));
    Assert.AreEqual('Win64', mItem.GetValue<string>('platform'));
    Assert.AreEqual(2, mItem.GetValue<TJSONArray>('configs').Count);
  finally
    mItem.Free;
  end;
end;

procedure TShellCommandsTests.FormFiles_UriGivesThatFile;
var
  mList: TJSONArray;
  mFiles: TArray<string>;
begin
  mList := Args('["file:///c%3A/P/Main.dfm"]');
  try
    mFiles := TBuildCommands.FormFiles(mList, ['x.pas'],
      function(AFileName: string): Boolean
      begin
        Result := True;
      end);
  finally
    mList.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mFiles)));
  Assert.IsTrue(mFiles[0].EndsWith('Main.dfm'));
end;

procedure TShellCommandsTests.FormFiles_CollectsExistingForms;
var
  mFiles: TArray<string>;
begin
  mFiles := TBuildCommands.FormFiles(nil, ['A.pas', 'B.pas', 'C.pas'],
    function(AFileName: string): Boolean
    begin
      Result := (AFileName = 'A.dfm') or (AFileName = 'C.fmx');
    end);
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.AreEqual('A.dfm', mFiles[0]);
  Assert.AreEqual('C.fmx', mFiles[1]);
end;

procedure TShellCommandsTests.IndexAnswer_HasCounts;
var
  mAnswer: TJSONObject;
begin
  mAnswer := TIndexCommands.Answer(3, 2048);
  try
    Assert.AreEqual(3, mAnswer.GetValue<Integer>('removed'));
    Assert.AreEqual(Int64(2048), mAnswer.GetValue<Int64>('freedBytes'));
  finally
    mAnswer.Free;
  end;
end;

procedure TShellCommandsTests.ClearCaches_RemovesCacheFiles;
var
  mRoot: string;
  mFreed: Int64;
begin
  mRoot := TPath.Combine(TPath.GetTempPath, 'AtlasClear' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(mRoot);
  try
    TFile.WriteAllText(TPath.Combine(mRoot, 'index-abc.json'), '{"x": 1}');
    Assert.AreEqual(1, TIndexCommands.ClearCaches(mRoot, mFreed));
    Assert.IsTrue(mFreed > 0);
    Assert.IsFalse(TFile.Exists(TPath.Combine(mRoot, 'index-abc.json')));
  finally
    if TDirectory.Exists(mRoot) then
    begin
      TDirectory.Delete(mRoot, True);
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCommandsTests);

end.
