unit Atlas.Common.Rules.Builtin.SlashCommands;

// Hinweis auf stehen gebliebene Schnellbefehle (#293):
//   slash-command   "/name" ist unbekannt oder passt an dieser Stelle nicht
//
// Der Befehlsrahmen löscht eine Befehlszeile nur, wenn der Befehl ausgeführt
// wurde. Bleibt sie stehen, nennt diese Regel den Grund. Nach allen anderen
// Regeln meldet sie "/ignore regel", wenn die Regel in der Zeile darunter
// nichts findet (#297); Muster mit * und nicht gelaufene Regeln zählen nicht.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TSlashCommandRule = class(TInterfacedObject, IRule, IRuleAfterFindings)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure CheckFindings(const AContext: TRuleContext; const AFindings: TArray<TRuleFinding>;
      const ARanIds: TArray<string>; const AReport: IRuleReport);
  end;

procedure RegisterSlashCommandRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.MaintenanceCommands,
  Atlas.Text.Lines;

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

function HitsLine(const AFindings: TArray<TRuleFinding>; const AId: string; ALine: Integer): Boolean;
var
  Finding: TRuleFinding;
begin
  for Finding in AFindings do
    if (Finding.Range.StartPos.Line = ALine) and SameText(Finding.RuleId, AId) then
      Exit(True);
  Result := False;
end;

procedure TSlashCommandRule.CheckFindings(const AContext: TRuleContext; const AFindings: TArray<TRuleFinding>;
  const ARanIds: TArray<string>; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  Tokens: TArray<TPascalToken>;
  Index, Space: Integer;
  Name, Arguments, Id: string;
begin
  if Pos('/ignore', AContext.Text) = 0 then
    Exit;
  Lines := TTextLines.SplitLines(AContext.Text);
  Tokens := nil;
  for Index := 0 to High(Lines) - 1 do
  begin
    if not TSlashCommandRegistry.Split(Lines[Index], Name, Arguments) or not SameText(Name, 'ignore') or
      (Trim(Lines[Index + 1]) = '') then
      Continue;
    Space := Pos(' ', Arguments + ' ');
    Id := LowerCase(Copy(Arguments, 1, Space - 1));
    if (Id = '') or (Pos('*', Id) > 0) or not MatchText(Id, ARanIds) or HitsLine(AFindings, Id, Index + 1) then
      Continue;
    if Tokens = nil then
    begin
      if AContext.Tree <> nil then
        Tokens := AContext.Tree.Tokens
      else
        Tokens := TPascalLexer.Tokenize(AContext.Text);
    end;
    if TSlashCommandRegistry.IsCodeLine(Tokens, Index) then
      AReport.Add(TTextRange.Create(TTextPosition.Create(Index, 0), TTextPosition.Create(Index, Length(Lines[Index]))),
        Format(IgnoreNoHitHint, [Id]));
  end;
end;

procedure RegisterSlashCommandRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TSlashCommandRule.Create);
end;

end.
