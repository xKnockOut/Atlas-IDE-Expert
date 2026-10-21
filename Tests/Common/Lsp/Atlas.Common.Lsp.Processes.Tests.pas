unit Atlas.Common.Lsp.Processes.Tests;

// Tests der Antwort von atlas.server.processes (#62): Cache, Sperre, Stand,
// Prozesse, „nur einmal aufgebaut“, Ereignisse und Markdown.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspProcessesTests = class
  public
    [Test]
    procedure AgeInWords;
    [Test]
    procedure MarkdownNamesHolderAndProcesses;
    [Test]
    procedure JsonCarriesFields;
    [Test]
    procedure WithoutWorkspaces;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  System.DateUtils,
  Atlas.Common.Index.Processes,
  Atlas.Common.Lsp.Processes;

function Sample(ANow: TDateTime): TLspProcessWorkspace;
var
  Lsp, Mcp: TIndexProcessInfo;
  Event: TIndexProcessEvent;
begin
  Lsp := Default(TIndexProcessInfo);
  Lsp.Pid := 4711;
  Lsp.Kind := TIndexProcessInfo.KindLsp;
  Lsp.Client := 'Atlas IDE Expert';
  Lsp.State := TIndexProcessInfo.StateBuilding;
  Lsp.Writer := True;
  Event.Time := IncSecond(ANow, -30);
  Event.Text := 'Cache-Sperre erhalten, Index wird aufgebaut';
  Lsp.Events := [Event];
  Mcp := Default(TIndexProcessInfo);
  Mcp.Pid := 5000;
  Mcp.Kind := TIndexProcessInfo.KindMcp;
  Mcp.State := TIndexProcessInfo.StateReading;
  Event.Time := IncSecond(ANow, -25);
  Event.Text := 'Sperre belegt, lade Cache nur lesend';
  Mcp.Events := [Event];
  Result := Default(TLspProcessWorkspace);
  Result.Name := 'Kasse';
  Result.CacheFile := 'C:' + PathDelim + 'Atlas' + PathDelim + '8f21c3' + PathDelim + 'index.atlasidx';
  Result.FormatVersion := 17;
  Result.Saved := IncSecond(ANow, -12);
  Result.Units := 412;
  Result.Processes := [Lsp, Mcp];
end;

{ TLspProcessesTests }

procedure TLspProcessesTests.AgeInWords;
var
  Now_: TDateTime;
begin
  Now_ := EncodeDateTime(2026, 10, 21, 10, 41, 31, 0);
  Assert.AreEqual('vor 12 s', TLspProcesses.Age(IncSecond(Now_, -12), Now_));
  Assert.AreEqual('vor 3 min', TLspProcesses.Age(IncMinute(Now_, -3), Now_));
  Assert.AreEqual('vor 2 h', TLspProcesses.Age(IncHour(Now_, -2), Now_));
  Assert.AreEqual('am 19.10.2026 10:41', TLspProcesses.Age(IncDay(Now_, -2), Now_));
  Assert.AreEqual('noch nicht gespeichert', TLspProcesses.Age(0, Now_));
end;

procedure TLspProcessesTests.MarkdownNamesHolderAndProcesses;
var
  Now_: TDateTime;
  Text: string;
begin
  Now_ := EncodeDateTime(2026, 10, 21, 10, 41, 31, 0);
  Text := TLspProcesses.ToMarkdown([Sample(Now_)], 5000, Now_);
  Assert.IsTrue(Text.Contains('- Index-Cache: 8f21c3' + PathDelim + 'index.atlasidx'), Text);
  Assert.IsTrue(Text.Contains('- Sperre: LSP · Atlas IDE Expert (pid 4711), schreibt'), Text);
  Assert.IsTrue(Text.Contains('- Stand: vor 12 s gespeichert · Format 17 · 412 Units'), Text);
  Assert.IsTrue(Text.Contains('- MCP · unbekannter Client (pid 5000): liest Cache (dieser Prozess)'), Text);
  Assert.IsTrue(Text.Contains('- Index nur einmal aufgebaut, 2 Prozesse'), Text);
  Assert.IsTrue(Text.Contains('10:41:01 LSP: Cache-Sperre erhalten'), Text);
  Assert.IsTrue(Text.IndexOf('LSP: Cache-Sperre') < Text.IndexOf('MCP: Sperre belegt'), Text);
end;

procedure TLspProcessesTests.JsonCarriesFields;
var
  Now_: TDateTime;
  Json: TJSONObject;
  Item: TJSONObject;
  Processes: TJSONArray;
begin
  Now_ := EncodeDateTime(2026, 10, 21, 10, 41, 31, 0);
  Json := TLspProcesses.ToJson([Sample(Now_)], 4711, Now_);
  try
    Item := Json.GetValue<TJSONArray>('workspaces').Items[0] as TJSONObject;
    Assert.AreEqual('Kasse', Item.GetValue<string>('name'));
    Assert.AreEqual(17, Item.GetValue<Integer>('format'));
    Assert.AreEqual('vor 12 s', Item.GetValue<string>('saved'));
    Assert.IsTrue(Item.GetValue<Boolean>('builtOnce'));
    Processes := Item.GetValue<TJSONArray>('processes');
    Assert.AreEqual(2, Integer(Processes.Count));
    Assert.IsTrue((Processes.Items[0] as TJSONObject).GetValue<Boolean>('own'));
    Assert.AreEqual(2, Item.GetValue<TJSONArray>('events').Count);
    Assert.IsTrue(Json.GetValue<string>('markdown').StartsWith('## Prozesse am Projekt'));
  finally
    Json.Free;
  end;
end;

procedure TLspProcessesTests.WithoutWorkspaces;
var
  Workspace: TLspProcessWorkspace;
begin
  Assert.IsTrue(TLspProcesses.ToMarkdown(nil, 1, Now).Contains('Kein Index-Cache'));
  Workspace := Default(TLspProcessWorkspace);
  Assert.IsFalse(Workspace.BuiltOnce);
  Assert.AreEqual('', Workspace.CacheName);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspProcessesTests);

end.
