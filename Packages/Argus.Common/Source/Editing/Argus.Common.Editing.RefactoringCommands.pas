unit Argus.Common.Editing.RefactoringCommands;

// Schnellbefehle für Formatierung und Messung (#300) im Rahmen aus #293:
//   /fmt       formatiert die umgebende Routine (Formatter aus #43, Standardstil)
//   /measure   misst die folgenden Anweisungen mit TStopwatch und gibt die Zeit
//              per OutputDebugString aus; trägt System.Diagnostics ein
// /extract, /inline, /fix und /explain aus #300 folgen mit #50, #103 und #54.

interface

uses
  Argus.Common.Editing.SlashCommands;

/// <summary>Trägt /fmt und /measure in ARegistry ein.</summary>
procedure RegisterRefactoringCommands(ARegistry: TSlashCommandRegistry);

implementation

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Configuration.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Lexer,
  Argus.Common.Editing.Formatter,
  Argus.Common.Editing.CommandSource;

{ /fmt }

function ExecuteFmt(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Edit: TRuleEdit;
  Text: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine = nil then
      Exit(Fail('/fmt gilt nur im Rumpf einer Routine', AReason));
    // Formatiert wird der Text ohne Befehlszeile; deren Zeile entfernt RemoveCommand.
    Text := Source.Text;
    for Edit in TFormatter.Edits(Text, TPascalLexer.Tokenize(Text), TFormatStyle.Default, Routine.StartPos.Line,
      Routine.EndPos.Line) do
      if (Edit.Range.StartPos.Line <> Source.Line) and (Edit.Range.EndPos.Line <> Source.Line) then
        AEdits := AEdits + [Edit];
    AEdits := AEdits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /measure }

function ExecuteMeasure(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Name: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine = nil then
      Exit(Fail('/measure gilt nur im Rumpf einer Routine', AReason));
    Name := Routine.Name;
    if Source.Tree.Root.Name <> '' then
      Name := Source.Tree.Root.Name + '.' + Name;
    if AContext.Arguments <> '' then
      Name := Name + ' ' + AContext.Arguments;
    // Name als Format-Argument: Prozentzeichen im Namen stören so nicht.
    Result := Wrap(Source, 'measure', ['var SW := TStopwatch.StartNew;', 'try'],
      ['finally', Format('  OutputDebugString(PChar(Format(''%%s: %%d ms'', [%s, SW.ElapsedMilliseconds])));',
      [QuotedStr(Name)]), 'end;'], '  ', AEdits, AReason);
    if Result then
      AddUses(Source, AContext, Source.Line, ['System.Diagnostics'], AEdits);
  finally
    Source.Free;
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterRefactoringCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('fmt', 'Umgebende Routine formatieren', '/fmt', ExecuteFmt));
  ARegistry.Register(Command('measure', 'Laufzeit der folgenden Anweisungen messen', '/measure Laden',
    ExecuteMeasure));
end;

end.
