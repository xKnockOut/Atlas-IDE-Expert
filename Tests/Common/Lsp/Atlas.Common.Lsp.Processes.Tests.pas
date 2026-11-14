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
    [Test]
    procedure MarkedMarkdownMarksNames;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  System.DateUtils,
  Atlas.Common.Index.Processes,
  Atlas.Common.Lsp.Processes,
  Atlas.Text.LogMarks;

function Sample(ANow: TDateTime): TLspProcessWorkspace;
var
  mLsp, mMcp: TIndexProcessInfo;
  mEvent: TIndexProcessEvent;
begin
  mLsp := Default(TIndexProcessInfo);
  mLsp.Pid := 4711;
  mLsp.Kind := TIndexProcessInfo.cKindLsp;
  mLsp.Client := 'Atlas IDE Expert';
  mLsp.State := TIndexProcessInfo.cStateBuilding;
  mLsp.Writer := True;
  mEvent.Time := IncSecond(ANow, -30);
  mEvent.Text := 'Cache-Sperre erhalten, Index wird aufgebaut';
  mLsp.Events := [mEvent];
  mMcp := Default(TIndexProcessInfo);
  mMcp.Pid := 5000;
  mMcp.Kind := TIndexProcessInfo.cKindMcp;
  mMcp.State := TIndexProcessInfo.cStateReading;
  mEvent.Time := IncSecond(ANow, -25);
  mEvent.Text := 'Sperre belegt, lade Cache nur lesend';
  mMcp.Events := [mEvent];
  Result := Default(TLspProcessWorkspace);
  Result.Name := 'Kasse';
  Result.CacheFile := 'C:' + PathDelim + 'Atlas' + PathDelim + '8f21c3' + PathDelim + 'index.atlasidx';
  Result.FormatVersion := 17;
  Result.Saved := IncSecond(ANow, -12);
  Result.Units := 412;
  Result.Processes := [mLsp, mMcp];
end;

{ TLspProcessesTests }

procedure TLspProcessesTests.AgeInWords;
var
  mNow_: TDateTime;
begin
  mNow_ := EncodeDateTime(2026, 10, 21, 10, 41, 31, 0);
  Assert.AreEqual('vor 12 s', TLspProcesses.Age(IncSecond(mNow_, -12), mNow_));
  Assert.AreEqual('vor 3 min', TLspProcesses.Age(IncMinute(mNow_, -3), mNow_));
  Assert.AreEqual('vor 2 h', TLspProcesses.Age(IncHour(mNow_, -2), mNow_));
  Assert.AreEqual('am 19.10.2026 10:41', TLspProcesses.Age(IncDay(mNow_, -2), mNow_));
  Assert.AreEqual('noch nicht gespeichert', TLspProcesses.Age(0, mNow_));
end;

procedure TLspProcessesTests.MarkdownNamesHolderAndProcesses;
var
  mNow_: TDateTime;
  mText: string;
begin
  mNow_ := EncodeDateTime(2026, 10, 21, 10, 41, 31, 0);
  mText := TLspProcesses.ToMarkdown([Sample(mNow_)], 5000, mNow_);
  Assert.IsTrue(mText.Contains('- Index-Cache: 8f21c3' + PathDelim + 'index.atlasidx'), mText);
  Assert.IsTrue(mText.Contains('- Sperre: LSP · Atlas IDE Expert (pid 4711), schreibt'), mText);
  Assert.IsTrue(mText.Contains('- Stand: vor 12 s gespeichert · Format 17 · 412 Units'), mText);
  Assert.IsTrue(mText.Contains('- MCP · unbekannter Client (pid 5000): liest Cache (dieser Prozess)'), mText);
  Assert.IsTrue(mText.Contains('- Index nur einmal aufgebaut, 2 Prozesse'), mText);
  Assert.IsTrue(mText.Contains('10:41:01 LSP: Cache-Sperre erhalten'), mText);
  Assert.IsTrue(mText.IndexOf('LSP: Cache-Sperre') < mText.IndexOf('MCP: Sperre belegt'), mText);
end;

procedure TLspProcessesTests.JsonCarriesFields;
var
  mNow_: TDateTime;
  mJson: TJSONObject;
  mItem: TJSONObject;
  mProcesses: TJSONArray;
begin
  mNow_ := EncodeDateTime(2026, 10, 21, 10, 41, 31, 0);
  mJson := TLspProcesses.ToJson([Sample(mNow_)], 4711, mNow_);
  try
    mItem := mJson.GetValue<TJSONArray>('workspaces').Items[0] as TJSONObject;
    Assert.AreEqual('Kasse', mItem.GetValue<string>('name'));
    Assert.AreEqual(17, mItem.GetValue<Integer>('format'));
    Assert.AreEqual('vor 12 s', mItem.GetValue<string>('saved'));
    Assert.IsTrue(mItem.GetValue<Boolean>('builtOnce'));
    mProcesses := mItem.GetValue<TJSONArray>('processes');
    Assert.AreEqual(2, Integer(mProcesses.Count));
    Assert.IsTrue((mProcesses.Items[0] as TJSONObject).GetValue<Boolean>('own'));
    Assert.AreEqual(2, mItem.GetValue<TJSONArray>('events').Count);
    Assert.IsTrue(mJson.GetValue<string>('markdown').StartsWith('## Prozesse am Projekt'));
  finally
    mJson.Free;
  end;
end;

procedure TLspProcessesTests.WithoutWorkspaces;
var
  mWorkspace: TLspProcessWorkspace;
begin
  Assert.IsTrue(TLspProcesses.ToMarkdown(nil, 1, Now).Contains('Kein Index-Cache'));
  mWorkspace := Default(TLspProcessWorkspace);
  Assert.IsFalse(mWorkspace.BuiltOnce);
  Assert.AreEqual('', mWorkspace.CacheName);
end;

procedure TLspProcessesTests.MarkedMarkdownMarksNames;
var
  mNow_: TDateTime;
  mText: string;
begin
  // Fürs Log sind Arbeitsbereich und Cache gekennzeichnet; ToMarkdown zeigt sie im Klartext (#1478).
  mNow_ := EncodeDateTime(2026, 10, 21, 10, 41, 31, 0);
  mText := TLspProcesses.MarkedMarkdown([Sample(mNow_)], 5000, mNow_);
  Assert.IsTrue(TLogMarks.HasMarks(mText));
  Assert.AreEqual(TLspProcesses.ToMarkdown([Sample(mNow_)], 5000, mNow_), TLogMarks.Plain(mText));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspProcessesTests);

end.
