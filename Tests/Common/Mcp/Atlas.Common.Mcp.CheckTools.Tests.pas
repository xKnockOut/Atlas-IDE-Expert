unit Atlas.Common.Mcp.CheckTools.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpCheckToolsTests = class
  public
    [Test]
    procedure ListsDiagnosticsWithLocation;
    [Test]
    procedure HookDiagnosticsReportsWarningsAsHookOutput;
    [Test]
    procedure HookDiagnosticsIsEmptyForOtherFiles;
    [Test]
    procedure HookDiagnosticsIsEmptyWithoutFindings;
    [Test]
    procedure ParsesHookSeverity;
    [Test]
    procedure ReportsMetrics;
    [Test]
    procedure ReportsTodosOfProjectFilesOnly;
    [Test]
    procedure FiltersTodos;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Lsp.References,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Contract,
  Atlas.Common.Mcp.CheckTools;

procedure TMcpCheckToolsTests.ListsDiagnosticsWithLocation;
var
  Text: string;
begin
  Text := TMcpCheckTools.Diagnostics(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, 'C:\P'),
    ['C:\P\Kaputt.pas'],
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := 'unit Kaputt;'#10'interface'#10'implementation'#10'procedure X;'#10'begin'#10'  if then'#10'end;'#10'end.';
      Result := True;
    end);
  Assert.Contains(Text, 'C:\P\Kaputt.pas:6:');
  Assert.Contains(Text, 'in 1 Dateien');
end;

procedure TMcpCheckToolsTests.HookDiagnosticsReportsWarningsAsHookOutput;
var
  Text: string;
begin
  Text := TMcpCheckTools.HookDiagnostics(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, 'C:\P'),
    'C:\P\Kaputt.pas',
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := 'unit Kaputt;'#10'interface'#10'implementation'#10'procedure X;'#10'begin'#10'  if then'#10'end;'#10'end.';
      Result := True;
    end, nil, nil, TRuleSeverity.Warning);
  Assert.StartsWith('{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"', Text);
  Assert.Contains(Text, 'C:\\P\\Kaputt.pas');
  Assert.Contains(Text, '6:');
end;

procedure TMcpCheckToolsTests.HookDiagnosticsIsEmptyForOtherFiles;
var
  Read: Boolean;
begin
  Read := False;
  Assert.AreEqual('', TMcpCheckTools.HookDiagnostics(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, 'C:\P'),
    'C:\P\README.md',
    function(const AFileName: string; out AText: string): Boolean
    begin
      Read := True;
      AText := 'if then';
      Result := True;
    end, nil, nil, TRuleSeverity.Warning));
  Assert.IsFalse(Read, 'Andere Dateien liest hook_check gar nicht erst');
end;

procedure TMcpCheckToolsTests.HookDiagnosticsIsEmptyWithoutFindings;
begin
  Assert.AreEqual('', TMcpCheckTools.HookDiagnostics(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, 'C:\P'),
    'C:\P\Gut.pas',
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := 'unit Gut;'#10'interface'#10'implementation'#10'end.';
      Result := True;
    end, nil, nil, TRuleSeverity.Error));
end;

procedure TMcpCheckToolsTests.ParsesHookSeverity;
begin
  Assert.IsTrue(TMcpCheckTools.ParseHookSeverity('') = TRuleSeverity.Warning);
  Assert.IsTrue(TMcpCheckTools.ParseHookSeverity('Error') = TRuleSeverity.Error);
  Assert.IsTrue(TMcpCheckTools.ParseHookSeverity('hint') = TRuleSeverity.Hint);
  Assert.WillRaise(
    procedure
    begin
      TMcpCheckTools.ParseHookSeverity('laut');
    end, EMcpToolError);
end;

procedure TMcpCheckToolsTests.ReportsMetrics;
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
  Text := TMcpCheckTools.Metrics(TServerSettings.Default, 'C:\P', ['C:\P\Lang.pas'], ReadText, False);
  Assert.Contains(Text, '# Code-Metriken: P');
  Assert.Contains(Text, '| Viele | Lang.pas | 4 | 3 | 0 | 1 | 0 | **7** |');
  Text := TMcpCheckTools.Metrics(TServerSettings.Default, 'C:\P', ['C:\P\Lang.pas'], ReadText, True);
  Assert.Contains(Text, '"exceeded": ["parameters"]');
end;

/// <summary>Zwei Projektdateien mit TODOs; Fremd.pas läge auch im Ordner, gehört aber nicht zum Projekt.</summary>
function TodoText(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if AFileName.EndsWith('Kasse.pas') then
  begin
    AText := 'unit Kasse;'#10'// TODO 1 -oMarco -cGUI : Fokus setzen'#10'{ DONE -oAnna : Rundung }'#10 +
      '// FIXME: Rabatt doppelt'#10'end.';
  end
  else if AFileName.EndsWith('Lager.pas') then
  begin
    AText := 'unit Lager;'#10'{ TODO 2 -oAnna -cDaten : Index anlegen }'#10'end.';
  end
  else
  begin
    AText := 'unit Fremd;'#10'// TODO fremd'#10'end.';
  end;
end;

procedure TMcpCheckToolsTests.ReportsTodosOfProjectFilesOnly;
var
  Text: string;
begin
  Text := TMcpCheckTools.Todos(TServerSettings.Default, 'C:\P', ['C:\P\Kasse.pas', 'C:\P\Lager.pas'], TodoText,
    TTodoFilter.Default, False);
  Assert.Contains(Text, '# TODOs: P');
  Assert.Contains(Text, '3 offene Einträge in 2 Dateien (FIXME 1, TODO 2).');
  Assert.Contains(Text, '| 2 | TODO | 1 | GUI | Marco | Fokus setzen |');
  Assert.DoesNotContain(Text, 'Rundung');
  Assert.DoesNotContain(Text, 'fremd');
  Text := TMcpCheckTools.Todos(TServerSettings.Default, 'C:\P', ['C:\P\Kasse.pas'], TodoText,
    TTodoFilter.All, True);
  Assert.Contains(Text, '"keyword": "DONE", "done": true');
  Assert.Contains(Text, '"open": 2, "done": 1');
end;

procedure TMcpCheckToolsTests.FiltersTodos;
var
  Filter: TTodoFilter;
  Text: string;
begin
  Filter := TTodoFilter.Default;
  Filter.Owner := 'anna';
  Text := TMcpCheckTools.Todos(TServerSettings.Default, 'C:\P', ['C:\P\Kasse.pas', 'C:\P\Lager.pas'], TodoText,
    Filter, True);
  Assert.Contains(Text, '"text": "Index anlegen"');
  Assert.DoesNotContain(Text, 'Fokus');
  Filter := TTodoFilter.Default;
  Filter.Category := 'GUI';
  Filter.UnitName := 'Kasse';
  Text := TMcpCheckTools.Todos(TServerSettings.Default, 'C:\P', ['C:\P\Kasse.pas', 'C:\P\Lager.pas'], TodoText,
    Filter, True);
  Assert.Contains(Text, '"open": 1');
  Assert.Contains(Text, '"unit": "Kasse"');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpCheckToolsTests);

end.
