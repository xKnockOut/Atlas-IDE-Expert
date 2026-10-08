unit BDLsp.Common.Mcp.CodeTools.Tests;

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
    procedure ReportsUnknownSymbol;
    [Test]
    procedure ListsDiagnosticsWithLocation;
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
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Index.Extractor,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Builtin,
  BDLsp.Common.Lsp.References,
  BDLsp.Common.Mcp.CodeTools;

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
