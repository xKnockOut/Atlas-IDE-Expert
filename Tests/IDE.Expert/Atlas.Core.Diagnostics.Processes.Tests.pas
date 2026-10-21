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
  Atlas.Core.Diagnostics.Processes;

const
  Answer =
    '{"workspaces":[{"name":"Gruppe","project":"C:\\p\\App.dproj","cache":"3f9a\\Gruppe.idx","format":17,' +
    '"saved":"vor 12 s","units":412,"lockHolder":"LSP · Atlas IDE Expert (pid 4711)","builtOnce":true,' +
    '"processes":[{"pid":4711,"kind":"LSP","client":"Atlas IDE Expert","state":"baut Index","writer":true,' +
    '"own":true},{"pid":5120,"kind":"MCP","client":"Claude Code","state":"liest Cache","writer":false,' +
    '"own":false}],"events":[{"time":"10:00:01","text":"LSP 4711: Cache-Sperre erhalten"},' +
    '{"time":"10:00:02","text":"MCP 5120: Sperre belegt"}]},{"name":"Zweite","processes":[],"events":[]}],' +
    '"markdown":"## Prozesse am Projekt"}';

procedure TAtlasProcessesViewTests.ParsesWorkspaceProcessesAndEvents;
var
  Value: TJSONValue;
  Workspaces: TArray<TAtlasProcessWorkspace>;
begin
  Value := TJSONObject.ParseJSONValue(Answer);
  try
    Workspaces := TAtlasProcessesView.Parse(Value);
    Assert.AreEqual(2, Integer(Length(Workspaces)));
    Assert.AreEqual('Gruppe', Workspaces[0].Name);
    Assert.AreEqual('3f9a\Gruppe.idx', Workspaces[0].Cache);
    Assert.AreEqual(17, Workspaces[0].Format);
    Assert.AreEqual('vor 12 s', Workspaces[0].Saved);
    Assert.AreEqual(412, Workspaces[0].Units);
    Assert.AreEqual('LSP · Atlas IDE Expert (pid 4711)', Workspaces[0].LockHolder);
    Assert.IsTrue(Workspaces[0].BuiltOnce);
    Assert.AreEqual(2, Integer(Length(Workspaces[0].Processes)));
    Assert.AreEqual(4711, Workspaces[0].Processes[0].Pid);
    Assert.IsTrue(Workspaces[0].Processes[0].Writer);
    Assert.IsTrue(Workspaces[0].Processes[0].Own);
    Assert.AreEqual('MCP', Workspaces[0].Processes[1].Kind);
    Assert.AreEqual('liest Cache', Workspaces[0].Processes[1].State);
    Assert.IsFalse(Workspaces[0].Processes[1].Own);
    Assert.IsTrue(Workspaces[0].HasMcp);
    Assert.IsFalse(Workspaces[1].HasMcp);
    Assert.AreEqual(2, Integer(Length(Workspaces[0].Events)));
    Assert.AreEqual('10:00:02', Workspaces[0].Events[1].Time);
    Assert.AreEqual('Gruppe', TAtlasProcessesView.GroupName(Workspaces));
    Assert.AreEqual(2, TAtlasProcessesView.ProcessCount(Workspaces));
    Assert.AreEqual('## Prozesse am Projekt', TAtlasProcessesView.Markdown(Value));
  finally
    Value.Free;
  end;
end;

procedure TAtlasProcessesViewTests.UnknownAnswerGivesNothing;
var
  Value: TJSONValue;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasProcessesView.Parse(nil))));
  Assert.AreEqual('', TAtlasProcessesView.Markdown(nil));
  Assert.AreEqual('', TAtlasProcessesView.GroupName(nil));
  Value := TJSONObject.ParseJSONValue('{"workspaces":"falsch"}');
  try
    Assert.AreEqual(0, Integer(Length(TAtlasProcessesView.Parse(Value))));
  finally
    Value.Free;
  end;
end;

procedure TAtlasProcessesViewTests.CaptionNamesUnknownClient;
var
  Row: TAtlasProcessRow;
begin
  Row := Default(TAtlasProcessRow);
  Row.Pid := 42;
  Assert.AreEqual('unbekannter Client (pid 42)', Row.Caption);
  Row.Client := 'Claude Code';
  Assert.AreEqual('Claude Code (pid 42)', Row.Caption);
end;

procedure TAtlasProcessesViewTests.DirtyNamesAreSortedWithoutDuplicates;
var
  Names: TArray<string>;
begin
  Names := TAtlasProcessesView.DirtyNames(['C:\p\Zeta.pas', 'C:\p\Alpha.pas', '', 'D:\q\alpha.pas']);
  Assert.AreEqual(2, Integer(Length(Names)));
  Assert.AreEqual('Alpha.pas', Names[0]);
  Assert.AreEqual('Zeta.pas', Names[1]);
end;

end.
