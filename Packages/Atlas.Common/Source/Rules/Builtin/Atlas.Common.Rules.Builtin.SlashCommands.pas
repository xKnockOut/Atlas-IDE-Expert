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
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.MaintenanceCommands,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TSlashCommandsText = (Title);

const
  cTexts: array[TSlashCommandsText] of TAtlasText = (
    (De: 'Schnellbefehl wurde nicht ausgeführt'; En: 'Quick command was not executed'));

{$SCOPEDENUMS OFF}

{ TSlashCommandRule }

function TSlashCommandRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('slash-command', TRuleSeverity.Hint,
    cTexts[TSlashCommandsText.Title].Text);
end;

procedure TSlashCommandRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mProblem: TSlashProblem;
begin
  for mProblem in TSlashCommandRegistry.Shared.Problems(AContext.Text, nil, AContext.Index, AContext.DelphiVersion) do
  begin
    AReport.Add(mProblem.Range, mProblem.Message);
  end;
end;

function HitsLine(const AFindings: TArray<TRuleFinding>; const AId: string; ALine: Integer): Boolean;
var
  mFinding: TRuleFinding;
begin
  for mFinding in AFindings do
  begin
    if (mFinding.Range.StartPos.Line = ALine) and SameText(mFinding.RuleId, AId) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Token des Kontexts: aus dem Syntaxbaum oder neu zerlegt.</summary>
function ContextTokens(const AContext: TRuleContext): TArray<TPascalToken>;
begin
  if AContext.Tree <> nil then
  begin
    Result := AContext.Tree.Tokens;
  end
  else
  begin
    Result := TPascalLexer.Tokenize(AContext.Text);
  end;
end;

procedure TSlashCommandRule.CheckFindings(const AContext: TRuleContext; const AFindings: TArray<TRuleFinding>;
  const ARanIds: TArray<string>; const AReport: IRuleReport);
var
  mLines: TArray<string>;
  mTokens: TArray<TPascalToken>;
  mIndex, mSpace: Integer;
  mName, mArguments, mId: string;
begin
  if Pos('/ignore', AContext.Text) = 0 then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AContext.Text);
  mTokens := nil;
  for mIndex := 0 to High(mLines) - 1 do
  begin
    if not TSlashCommandRegistry.Split(mLines[mIndex], mName, mArguments) or not SameText(mName, 'ignore') or
      (Trim(mLines[mIndex + 1]) = '') then
    begin
      Continue;
    end;
    mSpace := Pos(' ', mArguments + ' ');
    mId := LowerCase(Copy(mArguments, 1, mSpace - 1));
    if (mId = '') or (Pos('*', mId) > 0) or not MatchText(mId, ARanIds) or HitsLine(AFindings, mId, mIndex + 1) then
    begin
      Continue;
    end;
    if mTokens = nil then
    begin
      mTokens := ContextTokens(AContext);
    end;
    if TSlashCommandRegistry.IsCodeLine(mTokens, mIndex) then
    begin
      AReport.Add(TTextRange.Create(TTextPosition.Create(mIndex, 0),
        TTextPosition.Create(mIndex, Length(mLines[mIndex]))),
        Format(IgnoreNoHitHint, [mId]));
    end;
  end;
end;

procedure RegisterSlashCommandRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TSlashCommandRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.SlashCommands', cTexts);

end.
