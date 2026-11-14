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
    procedure ParsesDirection;
    [Test]
    procedure ReplacesLineRange;
    [Test]
    procedure CheckCodeReportsWithoutWriting;
    /// <summary>check_code und get_diagnostics prüfen mit den Symbolen des Projekts (#860): Für Win64 ist der
    /// {$ELSE}-Zweig für Win32 inaktiv und meldet nichts.</summary>
    [Test]
    procedure CheckCodeUsesProjectDefines;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Lsp.References,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Contract,
  Atlas.Common.Mcp.CodeTools,
  Atlas.Common.Mcp.CheckTools;

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
    // Start wird verwendet, sonst meldet unused-declaration (#64) es bei check_code.
    'initialization'#10 +
    '  Start;'#10 +
    'end.';

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, WorkerFile) then
  begin
    AText := WorkerUnit;
  end
  else if SameText(AFileName, MainFile) then
  begin
    AText := MainUnit;
  end
  else
  begin
    Result := False;
  end;
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
    Text := Tools.CheckCode(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, 'C:\P'),
      MainFile, '  if then', 10, 10);
    Assert.Contains(Text, '10:');
    Assert.Contains(Text, '[syntax]');
    // Ohne System im Index werden Bezeichner nicht geprüft, und das steht dabei.
    Assert.Contains(Text, 'Unit System ist nicht im Index');
    Text := Tools.CheckCode(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, 'C:\P'),
      MainFile, MainUnit, 0, 0);
    Assert.Contains(Text, 'Keine Befunde');
  finally
    Tools.Free;
  end;
end;

procedure TMcpCodeToolsTests.CheckCodeUsesProjectDefines;
const
  // Der WIN64-Zweig ist sonst sauber: Datei und Unit heißen gleich, X ruft sich nicht selbst auf und wird im
  // initialization-Teil verwendet (unused-declaration, #64).
  ZielFile = 'C:\P\Ziel.pas';
  Win64Unit =
    'unit Ziel;'#10'interface'#10'implementation'#10'procedure X;'#10'begin'#10 +
    '{$IFDEF WIN64}'#10'  Exit;'#10'{$ELSE}'#10'  if then'#10'{$ENDIF}'#10'end;'#10 +
    'initialization'#10'  X;'#10'end.';
var
  Tools: TMcpCodeTools;
  Win64: TCheckSourceFunc;
  ReadWin64: TReferenceReadText;
begin
  Win64 :=
    function(const AFileName: string): TCheckSource
    begin
      Result := TCheckSource.Create(AFileName, TPascalPreprocessor.PredefinedSymbols('Win64', 37), nil);
    end;
  ReadWin64 :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := Win64Unit;
      Result := True;
    end;
  Tools := NewTools;
  try
    // Ohne Projekt gelten Win32 und Delphi 13: Der {$ELSE}-Zweig ist aktiv und kaputt.
    Assert.Contains(Tools.CheckCode(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, 'C:\P'),
      ZielFile, Win64Unit, 0, 0),
      '[syntax]');
    Tools.CheckSource := Win64;
    Assert.Contains(Tools.CheckCode(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, 'C:\P'),
      ZielFile, Win64Unit, 0, 0),
      'Keine Befunde');
  finally
    Tools.Free;
  end;
  Assert.Contains(TMcpCheckTools.Diagnostics(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, 'C:\P'),
    [ZielFile],
    ReadWin64), '[syntax]');
  Assert.Contains(TMcpCheckTools.Diagnostics(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, 'C:\P'),
    [ZielFile],
    ReadWin64, Win64), '0 Befunde');
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
