unit Atlas.Common.Rules.Builtin.Testing.LeakMonitor;

// Regel aus Atlas.Common.Rules.Builtin.Testing (#1774); angemeldet wird sie dort:
//   dunitx-leak-monitor  Testprogramm (.dpr mit DUnitX.TestFramework im uses) ohne Leckmonitor von DUnitX: Ohne
//                        DUnitX.MemoryLeakMonitor.FastMM4 bzw. .FastMM5 misst DUnitX keine Lecks je Test, die
//                        Testmarken im Editor zeigen sie dann nie. DUnitX.MemoryLeakMonitor.Default zählt nicht,
//                        er misst nichts. Gemeldet am Eintrag DUnitX.TestFramework. Korrektur: den Monitor ins uses
//                        eintragen; FastMM5, wenn das Programm FastMM5 verwendet, sonst FastMM4 (er arbeitet auch
//                        mit dem Speichermanager der RTL, FastMM4.pas ist dafür nicht nötig). Still, wenn eine Unit
//                        des Projekts einen eigenen Monitor anmeldet (IMemoryLeakMonitor laut Index verwendet).

interface

uses
  Atlas.Common.Rules.Contract;

const
  cDUnitXLeakMonitorRuleId = 'dunitx-leak-monitor';

type
  TDUnitXLeakMonitorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Monitor für ein Programm mit den Units AUsed: .FastMM5 bei FastMM5, sonst .FastMM4.</summary>
    class function MonitorFor(const AUsed: TArray<string>): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TLeakMonitorText = (Title, NoMonitor, AddMonitor);

const
  cTexts: array[TLeakMonitorText] of TAtlasText = (
    (De: 'DUnitX-Testprogramm ohne Leckmonitor'; En: 'DUnitX test program without leak monitor'),
    (De: 'Ohne Leckmonitor misst DUnitX keine Lecks je Test: %s fehlt im uses.';
     En: 'Without a leak monitor DUnitX measures no leaks per test: %s is missing from uses.'),
    (De: '%s ergänzen'; En: 'Add %s'));

{$SCOPEDENUMS OFF}

const
  cFramework = 'DUnitX.TestFramework';
  cMonitorPrefix = 'DUnitX.MemoryLeakMonitor.';
  cNoMonitor = 'DUnitX.MemoryLeakMonitor.Default';
  cMonitorFastMM4 = 'DUnitX.MemoryLeakMonitor.FastMM4';
  cMonitorFastMM5 = 'DUnitX.MemoryLeakMonitor.FastMM5';
  cMonitorInterface = 'IMemoryLeakMonitor';
  cFastMM5 = 'FastMM5';

{ TDUnitXLeakMonitorRule }

function TDUnitXLeakMonitorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDUnitXLeakMonitorRuleId, TRuleSeverity.Hint, cTexts[TLeakMonitorText.Title].Text);
end;

class function TDUnitXLeakMonitorRule.MonitorFor(const AUsed: TArray<string>): string;
begin
  Result := cMonitorFastMM4;
  if MatchText(cFastMM5, AUsed) then
  begin
    Result := cMonitorFastMM5;
  end;
end;

/// <summary>Meldet eine Unit des Projekts einen eigenen Leckmonitor an
/// (TDUnitXIoC.DefaultContainer.RegisterType<IMemoryLeakMonitor>)? Bibliotheken wie DUnitX selbst zählen nicht.
/// </summary>
function HasOwnMonitor(const AContext: TRuleContext): Boolean;
begin
  Result := (AContext.Index <> nil) and (AContext.Index.UsageCount(cMonitorInterface) > 0);
end;

procedure TDUnitXLeakMonitorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mReference: TUsesReference;
  mFramework: TUsesReference;
  mFound: Boolean;
  mUsed: TArray<string>;
  mMonitor: string;
  mEdit: TTextEdit;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.Tree.Root.Kind <> TSyntaxKind.ProgramFile) or
    HasOwnMonitor(AContext) then
  begin
    Exit;
  end;
  mFound := False;
  mFramework := Default(TUsesReference);
  mUsed := nil;
  for mReference in TUsesClauses.References(AContext.Tree.Tokens) do
  begin
    if StartsText(cMonitorPrefix, mReference.Name) and not SameText(cNoMonitor, mReference.Name) then
    begin
      Exit;
    end;
    if (not mFound) and SameText(cFramework, mReference.Name) then
    begin
      mFramework := mReference;
      mFound := True;
    end;
    mUsed := mUsed + [mReference.Name];
  end;
  if not mFound then
  begin
    Exit;
  end;
  mMonitor := MonitorFor(mUsed);
  if TUsesClauses.AddUnit(AContext.Tree.Tokens, TLineTable.Build(AContext.Text).OffsetAt(mFramework.Range.StartPos),
    mMonitor, TTextLines.LineBreakOf(AContext.Text), mEdit) then
  begin
    AReport.Add(mFramework.Range, cTexts[TLeakMonitorText.NoMonitor].Fmt([mMonitor]), TRuleConfidence.High,
      [TRuleFix.Create(cTexts[TLeakMonitorText.AddMonitor].Fmt([mMonitor]), [mEdit])]);
  end
  else
  begin
    AReport.Add(mFramework.Range, cTexts[TLeakMonitorText.NoMonitor].Fmt([mMonitor]), TRuleConfidence.High);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Testing.LeakMonitor', cTexts);

end.
