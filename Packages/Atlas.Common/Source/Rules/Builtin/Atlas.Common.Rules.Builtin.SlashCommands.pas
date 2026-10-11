unit Atlas.Common.Rules.Builtin.SlashCommands;

// Hinweis auf stehen gebliebene Schnellbefehle (#293):
//   slash-command   "/name" ist unbekannt oder passt an dieser Stelle nicht
//
// Der Befehlsrahmen löscht eine Befehlszeile nur, wenn der Befehl ausgeführt
// wurde. Bleibt sie stehen, nennt diese Regel den Grund.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TSlashCommandRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterSlashCommandRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.SlashCommands;

{ TSlashCommandRule }

function TSlashCommandRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('slash-command', TRuleSeverity.Hint,
    'Schnellbefehl wurde nicht ausgeführt');
end;

procedure TSlashCommandRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Problem: TSlashProblem;
begin
  for Problem in TSlashCommandRegistry.Shared.Problems(AContext.Text, nil, AContext.Index, AContext.DelphiVersion) do
    AReport.Add(Problem.Range, Problem.Message);
end;

procedure RegisterSlashCommandRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TSlashCommandRule.Create);
end;

end.
