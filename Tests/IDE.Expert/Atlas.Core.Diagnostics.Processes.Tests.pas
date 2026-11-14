unit Atlas.Core.Diagnostics.Processes.Tests;

// Antwort von atlas.server.processes für „Prozesse am Projekt“ (#62):
// Arbeitsbereiche, Prozesse, Protokoll, Zählung und ungespeicherte Dateien.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProcessesViewTests = class
  public
    [Test]
    procedure ParsesWorkspaceProcessesAndEvents;
    [Test]
    procedure UnknownAnswerGivesNothing;
    [Test]
    procedure CaptionNamesUnknownClient;
    [Test]
    procedure DirtyNamesAreSortedWithoutDuplicates;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Diagnostics.Processes;

const
  cAnswer =
    '{"workspaces":[{"name":"Gruppe","project":"C:\\p\\App.dproj","cache":"3f9a\\Gruppe.idx","format":17,' +
    '"saved":"vor 12 s","units":412,"lockHolder":"LSP · Atlas IDE Expert (pid 4711)","builtOnce":true,' +
    '"processes":[{"pid":4711,"kind":"LSP","client":"Atlas IDE Expert","state":"baut Index","writer":true,' +
    '"own":true},{"pid":5120,"kind":"MCP","client":"Claude Code","state":"liest Cache","writer":false,' +
    '"own":false}],"events":[{"time":"10:00:01","text":"LSP 4711: Cache-Sperre erhalten"},' +
    '{"time":"10:00:02","text":"MCP 5120: Sperre belegt"}]},{"name":"Zweite","processes":[],"events":[]}],' +
    '"markdown":"## Prozesse am Projekt"}';

procedure TAtlasProcessesViewTests.ParsesWorkspaceProcessesAndEvents;
var
  mValue: TJSONValue;
  mWorkspaces: TArray<TAtlasProcessWorkspace>;
begin
  mValue := TJSONObject.ParseJSONValue(cAnswer);
  try
    mWorkspaces := TAtlasProcessesView.Parse(mValue);
    Assert.AreEqual(2, Integer(Length(mWorkspaces)));
    Assert.AreEqual('Gruppe', mWorkspaces[0].Name);
    Assert.AreEqual('3f9a\Gruppe.idx', mWorkspaces[0].Cache);
    Assert.AreEqual(17, mWorkspaces[0].Format);
    Assert.AreEqual('vor 12 s', mWorkspaces[0].Saved);
    Assert.AreEqual(412, mWorkspaces[0].Units);
    Assert.AreEqual('LSP · Atlas IDE Expert (pid 4711)', mWorkspaces[0].LockHolder);
    Assert.IsTrue(mWorkspaces[0].BuiltOnce);
    Assert.AreEqual(2, Integer(Length(mWorkspaces[0].Processes)));
    Assert.AreEqual(4711, mWorkspaces[0].Processes[0].Pid);
    Assert.IsTrue(mWorkspaces[0].Processes[0].Writer);
    Assert.IsTrue(mWorkspaces[0].Processes[0].Own);
    Assert.AreEqual('MCP', mWorkspaces[0].Processes[1].Kind);
    Assert.AreEqual('liest Cache', mWorkspaces[0].Processes[1].State);
    Assert.IsFalse(mWorkspaces[0].Processes[1].Own);
    Assert.IsTrue(mWorkspaces[0].HasMcp);
    Assert.IsFalse(mWorkspaces[1].HasMcp);
    Assert.AreEqual(2, Integer(Length(mWorkspaces[0].Events)));
    Assert.AreEqual('10:00:02', mWorkspaces[0].Events[1].Time);
    Assert.AreEqual('Gruppe', TAtlasProcessesView.GroupName(mWorkspaces));
    Assert.AreEqual(2, TAtlasProcessesView.ProcessCount(mWorkspaces));
    Assert.AreEqual('## Prozesse am Projekt', TAtlasProcessesView.Markdown(mValue));
  finally
    mValue.Free;
  end;
end;

procedure TAtlasProcessesViewTests.UnknownAnswerGivesNothing;
var
  mValue: TJSONValue;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasProcessesView.Parse(nil))));
  Assert.AreEqual('', TAtlasProcessesView.Markdown(nil));
  Assert.AreEqual('', TAtlasProcessesView.GroupName(nil));
  mValue := TJSONObject.ParseJSONValue('{"workspaces":"falsch"}');
  try
    Assert.AreEqual(0, Integer(Length(TAtlasProcessesView.Parse(mValue))));
  finally
    mValue.Free;
  end;
end;

procedure TAtlasProcessesViewTests.CaptionNamesUnknownClient;
var
  mRow: TAtlasProcessRow;
begin
  mRow := Default(TAtlasProcessRow);
  mRow.Pid := 42;
  Assert.AreEqual('unbekannter Client (pid 42)', mRow.Caption);
  mRow.Client := 'Claude Code';
  Assert.AreEqual('Claude Code (pid 42)', mRow.Caption);
end;

procedure TAtlasProcessesViewTests.DirtyNamesAreSortedWithoutDuplicates;
var
  mNames: TArray<string>;
begin
  mNames := TAtlasProcessesView.DirtyNames(['C:\p\Zeta.pas', 'C:\p\Alpha.pas', '', 'D:\q\alpha.pas']);
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('Alpha.pas', mNames[0]);
  Assert.AreEqual('Zeta.pas', mNames[1]);
end;

end.
