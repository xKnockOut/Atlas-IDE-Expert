unit Argus.Common.Rules.Builtin.SlashCommands;

// Hinweis auf stehen gebliebene Schnellbefehle (#293):
//   slash-command   "/name" ist unbekannt oder passt an dieser Stelle nicht
//
// Der Befehlsrahmen löscht eine Befehlszeile nur, wenn der Befehl ausgeführt
// wurde. Bleibt sie stehen, nennt diese Regel den Grund.

interface

uses
  System.SysUtils,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Registry;

type
  TSlashCommandRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterSlashCommandRules(const ARegistry: TRuleRegistry);

implementation

uses
  Argus.Common.Configuration.Contract,
  Argus.Common.Editing.SlashCommands;

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
  for Problem in TSlashCommandRegistry.Shared.Problems(AContext.Text, nil) do
    AReport.Add(Problem.Range, Problem.Message);
end;

procedure RegisterSlashCommandRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TSlashCommandRule.Create);
end;

end.
