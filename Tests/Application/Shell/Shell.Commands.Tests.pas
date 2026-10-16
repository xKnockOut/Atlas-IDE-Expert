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
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Projects.Contract,
  Shell.Commands.Build,
  Shell.Commands.Index;

function Args(const AJson: string): TJSONArray;
begin
  Result := TJSONObject.ParseJSONValue(AJson) as TJSONArray;
end;

procedure TShellCommandsTests.SelectBuildArgs_Empty_NoChanges;
var
  Parsed: TSelectBuildArgs;
begin
  Parsed := TSelectBuildArgs.Parse(nil);
  Assert.IsFalse(Parsed.Changes);
  Assert.AreEqual('', Parsed.Uri);
end;

procedure TShellCommandsTests.SelectBuildArgs_ReadsAllFields;
var
  List: TJSONArray;
  Parsed: TSelectBuildArgs;
begin
  List := Args('[{"config": "Release", "platform": "Win64", "uri": "file:///c%3A/a.pas", "defines": ["A", {}, "B"]}]');
  try
    Parsed := TSelectBuildArgs.Parse(List);
  finally
    List.Free;
  end;
  Assert.AreEqual('Release', Parsed.Config);
  Assert.AreEqual('Win64', Parsed.Platform);
  Assert.AreEqual('file:///c%3A/a.pas', Parsed.Uri);
  Assert.IsTrue(Parsed.HasDefines);
  Assert.AreEqual(2, Integer(Length(Parsed.Defines)), 'Nur Strings');
  Assert.IsTrue(Parsed.Changes);
end;

procedure TShellCommandsTests.SelectBuildArgs_EmptyDefinesStillReplace;
var
  List: TJSONArray;
  Parsed: TSelectBuildArgs;
begin
  List := Args('[{"defines": []}]');
  try
    Parsed := TSelectBuildArgs.Parse(List);
  finally
    List.Free;
  end;
  Assert.IsTrue(Parsed.HasDefines);
  Assert.IsTrue(Parsed.Changes);
end;

procedure TShellCommandsTests.ProjectItem_PrefersChosenValues;
var
  Project: TProjectInfo;
  Chosen: TSelectBuildArgs;
  Item: TJSONObject;
begin
  Project := Default(TProjectInfo);
  Project.FileName := 'App.dproj';
  Project.Config := 'Debug';
  Project.Platform := 'Win32';
  Project.Configs := ['Debug', 'Release'];
  Project.Platforms := ['Win32', 'Win64'];
  Chosen := Default(TSelectBuildArgs);
  Chosen.Platform := 'Win64';
  Item := TBuildCommands.ProjectItem('App', Project, Chosen);
  try
    Assert.AreEqual('App', Item.GetValue<string>('folder'));
    Assert.AreEqual('App.dproj', Item.GetValue<string>('project'));
    Assert.AreEqual('Debug', Item.GetValue<string>('config'));
    Assert.AreEqual('Win64', Item.GetValue<string>('platform'));
    Assert.AreEqual(2, Item.GetValue<TJSONArray>('configs').Count);
  finally
    Item.Free;
  end;
end;

procedure TShellCommandsTests.FormFiles_UriGivesThatFile;
var
  List: TJSONArray;
  Files: TArray<string>;
begin
  List := Args('["file:///c%3A/P/Main.dfm"]');
  try
    Files := TBuildCommands.FormFiles(List, ['x.pas'],
      function(AFileName: string): Boolean
      begin
        Result := True;
      end);
  finally
    List.Free;
  end;
  Assert.AreEqual(1, Integer(Length(Files)));
  Assert.IsTrue(Files[0].EndsWith('Main.dfm'));
end;

procedure TShellCommandsTests.FormFiles_CollectsExistingForms;
var
  Files: TArray<string>;
begin
  Files := TBuildCommands.FormFiles(nil, ['A.pas', 'B.pas', 'C.pas'],
    function(AFileName: string): Boolean
    begin
      Result := (AFileName = 'A.dfm') or (AFileName = 'C.fmx');
    end);
  Assert.AreEqual(2, Integer(Length(Files)));
  Assert.AreEqual('A.dfm', Files[0]);
  Assert.AreEqual('C.fmx', Files[1]);
end;

procedure TShellCommandsTests.IndexAnswer_HasCounts;
var
  Answer: TJSONObject;
begin
  Answer := TIndexCommands.Answer(3, 2048);
  try
    Assert.AreEqual(3, Answer.GetValue<Integer>('removed'));
    Assert.AreEqual(Int64(2048), Answer.GetValue<Int64>('freedBytes'));
  finally
    Answer.Free;
  end;
end;

procedure TShellCommandsTests.ClearCaches_RemovesCacheFiles;
var
  Root: string;
  Freed: Int64;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'AtlasClear' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Root);
  try
    TFile.WriteAllText(TPath.Combine(Root, 'index-abc.json'), '{"x": 1}');
    Assert.AreEqual(1, TIndexCommands.ClearCaches(Root, Freed));
    Assert.IsTrue(Freed > 0);
    Assert.IsFalse(TFile.Exists(TPath.Combine(Root, 'index-abc.json')));
  finally
    if TDirectory.Exists(Root) then
      TDirectory.Delete(Root, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCommandsTests);

end.
