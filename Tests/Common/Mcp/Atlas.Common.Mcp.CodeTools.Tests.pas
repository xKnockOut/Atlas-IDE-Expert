unit Atlas.Common.Mcp.CodeTools.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpCodeToolsTests = class
  public
    [Test]
    procedure FindsReferencesAcrossFiles;
    [Test]
    procedure ShowsIncomingAndOutgoingCalls;
    [Test]
    procedure GivesQualifiedName;
    [Test]
    procedure ReportsUnknownSymbol;
    [Test]
    procedure ListsDiagnosticsWithLocation;
    [Test]
    procedure ReportsMetrics;
    [Test]
    procedure ReportsTodosOfProjectFilesOnly;
    [Test]
    procedure FiltersTodos;
    [Test]
    procedure ParsesDirection;
    [Test]
    procedure ReplacesLineRange;
    [Test]
    procedure CheckCodeReportsWithoutWriting;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Lsp.References,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.CodeTools,
  Atlas.Common.Todos.Contract;

const
  WorkerFile = 'C:\P\Worker.pas';
  MainFile = 'C:\P\Main.pas';
  WorkerUnit =
    'unit Worker;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TWorker = class'#10 +
    '    procedure Step;'#10 +
    '    procedure Run;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TWorker.Step;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TWorker.Run;'#10 +
    'begin'#10 +
    '  Step;'#10 +
    'end;'#10 +
    'end.';
  MainUnit =
    'unit Main;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Worker;'#10 +
    'procedure Start;'#10 +
    'var'#10 +
    '  W: TWorker;'#10 +
    'begin'#10 +
    '  W := TWorker.Create;'#10 +
    '  W.Run;'#10 +
    'end;'#10 +
    'end.';

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, WorkerFile) then
    AText := WorkerUnit
  else if SameText(AFileName, MainFile) then
    AText := MainUnit
  else
    Result := False;
end;

function NewTools: TMcpCodeTools;
var
  Index: ISymbolIndex;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(WorkerUnit, WorkerFile, nil));
  Index.AddUnit(TIndexExtractor.ExtractText(MainUnit, MainFile, nil));
  Result := TMcpCodeTools.Create(Index, ReadText,
    function: TArray<string>
    begin
      Result := [WorkerFile, MainFile];
    end);
end;

procedure TMcpCodeToolsTests.FindsReferencesAcrossFiles;
var
  Tools: TMcpCodeTools;
  Text: string;
begin
  Tools := NewTools;
  try
    Text := Tools.References('TWorker.Run');
    Assert.Contains(Text, 'Verwendungen von TWorker.Run');
    Assert.Contains(Text, MainFile + ':10: W.Run;');
  finally
    Tools.Free;
  end;
end;

procedure TMcpCodeToolsTests.ShowsIncomingAndOutgoingCalls;
var
  Tools: TMcpCodeTools;
  Text: string;
begin
  Tools := NewTools;
  try
    Text := Tools.CallHierarchy('TWorker.Run', TMcpCallDirection.Both);
    Assert.Contains(Text, 'Aufgerufen von:');
    Assert.Contains(Text, '← Start');
    Assert.Contains(Text, '→ TWorker.Step');
    Text := Tools.CallHierarchy('TWorker.Step', TMcpCallDirection.Incoming);
    Assert.Contains(Text, '← TWorker.Run');
    Assert.DoesNotContain(Text, 'Ruft auf:');
  finally
    Tools.Free;
  end;
end;

procedure TMcpCodeToolsTests.GivesQualifiedName;
var
  Tools: TMcpCodeTools;
begin
  Tools := NewTools;
  try
    // Zeile 10, Spalte 5: "Run" in "W.Run;".
    Assert.AreEqual('Worker.TWorker.Run', Tools.QualifiedName(MainFile, 10, 5, False));
    Assert.AreEqual('Worker.TWorker.Run()', Tools.QualifiedName(MainFile, 10, 5, True));
    Assert.AreEqual('Main.Start.W', Tools.QualifiedName(MainFile, 7, 3, False));
    Assert.WillRaise(
      procedure
      begin
        Tools.QualifiedName(MainFile, 2, 1, False);
      end, EMcpToolError);
  finally
    Tools.Free;
  end;
end;

procedure TMcpCodeToolsTests.ReportsUnknownSymbol;
var
  Tools: TMcpCodeTools;
begin
  Tools := NewTools;
  try
    Assert.Contains(Tools.References('TNichts'), 'Kein Symbol');
    Assert.Contains(Tools.CallHierarchy('TNichts', TMcpCallDirection.Both), 'Kein Symbol');
  finally
    Tools.Free;
  end;
end;

procedure TMcpCodeToolsTests.ListsDiagnosticsWithLocation;
var
  Text: string;
begin
  Text := TMcpCodeTools.Diagnostics(BuiltinRules, TServerSettings.Default, 'C:\P', ['C:\P\Kaputt.pas'],
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := 'unit Kaputt;'#10'interface'#10'implementation'#10'procedure X;'#10'begin'#10'  if then'#10'end;'#10'end.';
      Result := True;
    end);
  Assert.Contains(Text, 'C:\P\Kaputt.pas:6:');
  Assert.Contains(Text, 'in 1 Dateien');
end;

procedure TMcpCodeToolsTests.ReportsMetrics;
var
  Text: string;
  ReadText: TReferenceReadText;
begin
  ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := 'unit Lang;'#10'interface'#10'implementation'#10 +
        'procedure Viele(A, B, C, D, E, F, G: Integer);'#10'begin'#10'end;'#10'end.';
      Result := True;
    end;
  Text := TMcpCodeTools.Metrics(TServerSettings.Default, 'C:\P', ['C:\P\Lang.pas'], ReadText, False);
  Assert.Contains(Text, '# Code-Metriken: P');
  Assert.Contains(Text, '| Viele | Lang.pas | 4 | 3 | 0 | 1 | 0 | **7** |');
  Text := TMcpCodeTools.Metrics(TServerSettings.Default, 'C:\P', ['C:\P\Lang.pas'], ReadText, True);
  Assert.Contains(Text, '"exceeded": ["parameters"]');
end;

/// <summary>Zwei Projektdateien mit TODOs; Fremd.pas läge auch im Ordner, gehört aber nicht zum Projekt.</summary>
function TodoText(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if AFileName.EndsWith('Kasse.pas') then
    AText := 'unit Kasse;'#10'// TODO 1 -oMarco -cGUI : Fokus setzen'#10'{ DONE -oAnna : Rundung }'#10 +
      '// FIXME: Rabatt doppelt'#10'end.'
  else if AFileName.EndsWith('Lager.pas') then
    AText := 'unit Lager;'#10'{ TODO 2 -oAnna -cDaten : Index anlegen }'#10'end.'
  else
    AText := 'unit Fremd;'#10'// TODO fremd'#10'end.';
end;

procedure TMcpCodeToolsTests.ReportsTodosOfProjectFilesOnly;
var
  Text: string;
begin
  Text := TMcpCodeTools.Todos(TServerSettings.Default, 'C:\P', ['C:\P\Kasse.pas', 'C:\P\Lager.pas'], TodoText,
    TTodoFilter.Default, False);
  Assert.Contains(Text, '# TODOs: P');
  Assert.Contains(Text, '3 offene Einträge in 2 Dateien (FIXME 1, TODO 2).');
  Assert.Contains(Text, '| 2 | TODO | 1 | GUI | Marco | Fokus setzen |');
  Assert.DoesNotContain(Text, 'Rundung');
  Assert.DoesNotContain(Text, 'fremd');
  Text := TMcpCodeTools.Todos(TServerSettings.Default, 'C:\P', ['C:\P\Kasse.pas'], TodoText,
    TTodoFilter.All, True);
  Assert.Contains(Text, '"keyword": "DONE", "done": true');
  Assert.Contains(Text, '"open": 2, "done": 1');
end;

procedure TMcpCodeToolsTests.FiltersTodos;
var
  Filter: TTodoFilter;
  Text: string;
begin
  Filter := TTodoFilter.Default;
  Filter.Owner := 'anna';
  Text := TMcpCodeTools.Todos(TServerSettings.Default, 'C:\P', ['C:\P\Kasse.pas', 'C:\P\Lager.pas'], TodoText,
    Filter, True);
  Assert.Contains(Text, '"text": "Index anlegen"');
  Assert.DoesNotContain(Text, 'Fokus');
  Filter := TTodoFilter.Default;
  Filter.Category := 'GUI';
  Filter.UnitName := 'Kasse';
  Text := TMcpCodeTools.Todos(TServerSettings.Default, 'C:\P', ['C:\P\Kasse.pas', 'C:\P\Lager.pas'], TodoText,
    Filter, True);
  Assert.Contains(Text, '"open": 1');
  Assert.Contains(Text, '"unit": "Kasse"');
end;

procedure TMcpCodeToolsTests.ReplacesLineRange;
begin
  Assert.AreEqual('a'#13#10'X'#13#10'c', TMcpCodeTools.ReplaceLines('a'#13#10'b'#13#10'c', 'X', 2, 2));
  // Einfügen vor Zeile 2 (endLine = startLine - 1).
  Assert.AreEqual('a'#10'X'#10'b', TMcpCodeTools.ReplaceLines('a'#10'b', 'X', 2, 1));
  Assert.AreEqual('a'#10'b'#10'X', TMcpCodeTools.ReplaceLines('a'#10'b'#10, 'X', 3, 2));
  Assert.WillRaise(
    procedure
    begin
      TMcpCodeTools.ReplaceLines('a', 'X', 3, 3);
    end);
end;

procedure TMcpCodeToolsTests.CheckCodeReportsWithoutWriting;
var
  Tools: TMcpCodeTools;
  Text: string;
begin
  Tools := NewTools;
  try
    // Zeile 9 ("begin") bleibt, Zeile 10 "W.Run;" wird durch fehlerhaften Code ersetzt.
    Text := Tools.CheckCode(BuiltinRules, TServerSettings.Default, 'C:\P', MainFile, '  if then', 10, 10);
    Assert.Contains(Text, '10:');
    Assert.Contains(Text, '[syntax]');
    // Ohne System im Index werden Bezeichner nicht geprüft, und das steht dabei.
    Assert.Contains(Text, 'Unit System ist nicht im Index');
    Text := Tools.CheckCode(BuiltinRules, TServerSettings.Default, 'C:\P', MainFile, MainUnit, 0, 0);
    Assert.Contains(Text, 'Keine Befunde');
  finally
    Tools.Free;
  end;
end;

procedure TMcpCodeToolsTests.ParsesDirection;
begin
  Assert.AreEqual(Ord(TMcpCallDirection.Incoming), Ord(TMcpCodeTools.ParseDirection('Incoming')));
  Assert.AreEqual(Ord(TMcpCallDirection.Outgoing), Ord(TMcpCodeTools.ParseDirection('outgoing')));
  Assert.AreEqual(Ord(TMcpCallDirection.Both), Ord(TMcpCodeTools.ParseDirection('')));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpCodeToolsTests);

end.
