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
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Lsp.References,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Contract,
  Atlas.Common.Mcp.CheckTools;

procedure TMcpCheckToolsTests.ListsDiagnosticsWithLocation;
var
  mText: string;
begin
  mText := TMcpCheckTools.Diagnostics(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, 'C:\P'),
    ['C:\P\Kaputt.pas'],
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := 'unit Kaputt;'#10'interface'#10'implementation'#10'procedure X;'#10'begin'#10'  if then'#10'end;'#10'end.';
      Result := True;
    end);
  Assert.Contains(mText, 'C:\P\Kaputt.pas:6:');
  Assert.Contains(mText, 'in 1 Dateien');
end;

procedure TMcpCheckToolsTests.HookDiagnosticsReportsWarningsAsHookOutput;
var
  mText: string;
begin
  mText := TMcpCheckTools.HookDiagnostics(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, 'C:\P'),
    'C:\P\Kaputt.pas',
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := 'unit Kaputt;'#10'interface'#10'implementation'#10'procedure X;'#10'begin'#10'  if then'#10'end;'#10'end.';
      Result := True;
    end, nil, nil, TRuleSeverity.Warning);
  Assert.StartsWith('{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"', mText);
  Assert.Contains(mText, 'C:\\P\\Kaputt.pas');
  Assert.Contains(mText, '6:');
end;

procedure TMcpCheckToolsTests.HookDiagnosticsIsEmptyForOtherFiles;
var
  mRead: Boolean;
begin
  mRead := False;
  Assert.AreEqual('', TMcpCheckTools.HookDiagnostics(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, 'C:\P'),
    'C:\P\README.md',
    function(const AFileName: string; out AText: string): Boolean
    begin
      mRead := True;
      AText := 'if then';
      Result := True;
    end, nil, nil, TRuleSeverity.Warning));
  Assert.IsFalse(mRead, 'Andere Dateien liest hook_check gar nicht erst');
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
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Warning, TMcpCheckTools.ParseHookSeverity(''));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Error, TMcpCheckTools.ParseHookSeverity('Error'));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Hint, TMcpCheckTools.ParseHookSeverity('hint'));
  Assert.WillRaise(
    procedure
    begin
      TMcpCheckTools.ParseHookSeverity('laut');
    end, EMcpToolError);
end;

procedure TMcpCheckToolsTests.ReportsMetrics;
var
  mText: string;
  mReadText: TReferenceReadText;
begin
  mReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := 'unit Lang;'#10'interface'#10'implementation'#10 +
        'procedure Viele(A, B, C, D, E, F, G: Integer);'#10'begin'#10'end;'#10'end.';
      Result := True;
    end;
  mText := TMcpCheckTools.Metrics(TServerSettings.Default, 'C:\P', ['C:\P\Lang.pas'], mReadText, False);
  Assert.Contains(mText, '# Code-Metriken: P');
  Assert.Contains(mText, '| Viele | Lang.pas | 4 | 3 | 0 | 1 | 0 | **7** |');
  mText := TMcpCheckTools.Metrics(TServerSettings.Default, 'C:\P', ['C:\P\Lang.pas'], mReadText, True);
  Assert.Contains(mText, '"exceeded": ["parameters"]');
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
  mText: string;
begin
  mText := TMcpCheckTools.Todos(TServerSettings.Default, 'C:\P', ['C:\P\Kasse.pas', 'C:\P\Lager.pas'], TodoText,
    TTodoFilter.Default, False);
  Assert.Contains(mText, '# TODOs: P');
  Assert.Contains(mText, '3 offene Einträge in 2 Dateien (FIXME 1, TODO 2).');
  Assert.Contains(mText, '| 2 | TODO | 1 | GUI | Marco | Fokus setzen |');
  Assert.DoesNotContain(mText, 'Rundung');
  Assert.DoesNotContain(mText, 'fremd');
  mText := TMcpCheckTools.Todos(TServerSettings.Default, 'C:\P', ['C:\P\Kasse.pas'], TodoText,
    TTodoFilter.All, True);
  Assert.Contains(mText, '"keyword": "DONE", "done": true');
  Assert.Contains(mText, '"open": 2, "done": 1');
end;

procedure TMcpCheckToolsTests.FiltersTodos;
var
  mFilter: TTodoFilter;
  mText: string;
begin
  mFilter := TTodoFilter.Default;
  mFilter.Owner := 'anna';
  mText := TMcpCheckTools.Todos(TServerSettings.Default, 'C:\P', ['C:\P\Kasse.pas', 'C:\P\Lager.pas'], TodoText,
    mFilter, True);
  Assert.Contains(mText, '"text": "Index anlegen"');
  Assert.DoesNotContain(mText, 'Fokus');
  mFilter := TTodoFilter.Default;
  mFilter.Category := 'GUI';
  mFilter.UnitName := 'Kasse';
  mText := TMcpCheckTools.Todos(TServerSettings.Default, 'C:\P', ['C:\P\Kasse.pas', 'C:\P\Lager.pas'], TodoText,
    mFilter, True);
  Assert.Contains(mText, '"open": 1');
  Assert.Contains(mText, '"unit": "Kasse"');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpCheckToolsTests);

end.
