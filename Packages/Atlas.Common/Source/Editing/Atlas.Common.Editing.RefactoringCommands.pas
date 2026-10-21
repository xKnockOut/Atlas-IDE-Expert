unit Atlas.Common.Editing.RefactoringCommands;

// Schnellbefehle für Refactoring, Korrektur und Messung (#300) im Rahmen aus #293:
//   /extract Name  zieht die Anweisungen unter der Zeile bis zur nächsten
//                  Leerzeile (bzw. zum Blockende) in eine Methode Name aus (#50)
//   /inline        bettet den Aufruf einer Routine der Datei bzw. die Variable in
//                  der Zeile darunter ein (#103)
//   /fix           wendet die sicheren Korrekturen der Zeile darunter an (#182)
//   /explain       zeigt die Erklärung der Treffer in der Zeile darunter (#54)
//   /fmt           formatiert die umgebende Routine im Formatstil der Datei (#43)
//   /measure       misst die folgenden Anweisungen mit TStopwatch und gibt die Zeit
//                  mit slashCommands.logCall (#304) aus, sonst per OutputDebugString;
//                  trägt System.Diagnostics ein
// /fix und /explain fragen die Prüfregeln über ISlashHost.FindingsAt.

interface

uses
  Atlas.Common.Editing.SlashCommands;

const
  /// <summary>Hinweis, wenn unter /fix bzw. /explain kein Treffer steht.</summary>
  NoFindingBelowHint = 'In der Zeile darunter meldet keine Prüfregel etwas';
  /// <summary>Hinweis, wenn unter /fix nur Treffer ohne sichere Korrektur stehen.</summary>
  NoSafeFixHint = 'Für die Treffer in der Zeile darunter gibt es keine sichere Korrektur';

/// <summary>Trägt /extract, /inline, /fix, /explain, /fmt und /measure in ARegistry ein.</summary>
procedure RegisterRefactoringCommands(ARegistry: TSlashCommandRegistry);

implementation

uses
  System.SysUtils,
  System.RegularExpressions,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Extract,
  Atlas.Common.Editing.Inlining,
  Atlas.Common.Editing.Formatter,
  Atlas.Common.Editing.CommandSource;

function LeadingOf(const ALine: string): Integer;
begin
  Result := 0;
  while (Result < Length(ALine)) and CharInSet(ALine[Result + 1], [' ', #9]) do
    Inc(Result);
end;

{ /extract }

function ExecuteExtract(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Name, Why: string;
  First, Last, Indent: Integer;
  Options: TExtractOptions;
  Action: TCodeAction;
  Edit: TTextEdit;
begin
  AEdits := nil;
  Name := Trim(AContext.Arguments);
  if not IsValidIdent(Name) then
    Exit(Fail('Erwartet wird /extract Name', AReason));
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
      Exit(Fail('/extract gilt nur im Rumpf einer Routine', AReason));
    First := Source.Line + 1;
    if (First > High(Source.Lines)) or (Trim(Source.Lines[First]) = '') then
      Exit(Fail('Unter /extract stehen keine Anweisungen', AReason));
    // Bis zur nächsten Leerzeile; eine weniger eingerückte Zeile (end des Blocks) beendet die Auswahl.
    Indent := LeadingOf(Source.Lines[First]);
    Last := First;
    while (Last < High(Source.Lines)) and (Trim(Source.Lines[Last + 1]) <> '') and
      (LeadingOf(Source.Lines[Last + 1]) >= Indent) do
      Inc(Last);
    Options := TExtractOptions.Default;
    Options.Style := AContext.Style;
    if not TExtractRefactoring.ExtractMethod(Source.Text, Source.Tree, TTextRange.Create(First, Indent, Last,
      Length(Source.Lines[Last])), Options, Action, Why) then
      Exit(Fail('/extract: ' + Why, AReason));
    for Edit in Action.Edits do
      AEdits := AEdits + [TTextEdit.Create(Edit.Range, TRegEx.Replace(Edit.NewText,
        '\b' + TExtractRefactoring.MethodName + '\b', Name))];
    AEdits := AEdits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /inline }

function ExecuteInline(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Inline_: TInlineSource;
  Options: TInlineOptions;
  Token: TPascalToken;
  Names: TArray<TPascalToken>;
  Call: TInlineCall;
  Routines: TArray<TSyntaxNode>;
  Action: TCodeAction;
  Why, FileName: string;
  Next: Integer;
  Found: Boolean;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
      Exit(Fail('/inline gilt nur im Rumpf einer Routine', AReason));
    Next := Source.Line + 1;
    if (Next > High(Source.Lines)) or (Trim(Source.Lines[Next]) = '') then
      Exit(Fail('Unter /inline steht keine Anweisung', AReason));
    Names := nil;
    for Token in Source.Tree.Tokens do
      if (Token.StartPos.Line = Next) and (Token.Kind = TPascalTokenKind.Identifier) then
        Names := Names + [Token];
    FileName := '';
    if AContext.Uri <> '' then
      FileName := TDocumentUris.ToPath(AContext.Uri);
    Inline_ := TInlineSource.Create(FileName, Source.Text, Source.Tree);
    Options := TInlineOptions.Default;
    Options.Style := AContext.Style;
    Why := '';
    Found := False;
    // Erst ein Aufruf einer Routine dieser Datei, dann eine Variable.
    for Token in Names do
      if TInlineRefactoring.CallAt(Source.Tree, Source.Text, Token.StartPos, Call) then
      begin
        Routines := TInlineRefactoring.FindRoutines(Source.Tree, Call.Name);
        if Length(Routines) = 1 then
        begin
          Found := TInlineRefactoring.InlineMethod(Inline_, Token.StartPos, Inline_, Routines[0], Options, Action,
            Why);
          if Found then
            Break;
        end;
      end;
    if not Found then
      for Token in Names do
      begin
        Found := TInlineRefactoring.InlineVariable(Inline_, Token.StartPos, Options, Action);
        if Found then
          Break;
      end;
    if not Found then
    begin
      if Why = '' then
        Why := 'In der Zeile darunter steht kein Aufruf einer Routine dieser Datei und keine einbettbare Variable';
      Exit(Fail('/inline: ' + Why, AReason));
    end;
    AEdits := Action.Edits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /fix und /explain }

/// <summary>Treffer in der Zeile unter dem Befehl, geprüft am Text ohne Befehlszeile; False mit Grund.</summary>
function FindingsBelow(const AContext: TSlashContext; ASource: TCommandSource; out AFindings: TArray<TSlashFinding>;
  out AReason: string): Boolean;
begin
  AFindings := nil;
  if (ASource.Line >= High(ASource.Lines)) or (Trim(ASource.Lines[ASource.Line + 1]) = '') then
    Exit(Fail(Format('Unter /%s steht keine Zeile', [AContext.Name]), AReason));
  if AContext.Host = nil then
    Exit(Fail(Format('/%s braucht den Editor', [AContext.Name]), AReason));
  if not AContext.Host.FindingsAt(AContext.Uri, ASource.Text, ASource.Line + 1, AFindings) then
    Exit(Fail('Für diese Datei laufen keine Prüfregeln', AReason));
  if AFindings = nil then
    Exit(Fail(NoFindingBelowHint, AReason));
  Result := True;
end;

function ExecuteFix(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Findings: TArray<TSlashFinding>;
  Finding: TSlashFinding;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not FindingsBelow(AContext, Source, Findings, AReason) then
      Exit(False);
    for Finding in Findings do
      AEdits := AEdits + Finding.SafeFix;
    if AEdits = nil then
      Exit(Fail(NoSafeFixHint, AReason));
    AEdits := AEdits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

function ExecuteExplain(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Findings: TArray<TSlashFinding>;
  Finding: TSlashFinding;
  Host: ISlashHost;
  Uri, Text: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not FindingsBelow(AContext, Source, Findings, AReason) then
      Exit(False);
    Text := '';
    for Finding in Findings do
    begin
      if Text <> '' then
        Text := Text + #10#10;
      Text := Text + Finding.Message;
      if Finding.Explanation <> '' then
        Text := Text + #10 + Finding.Explanation;
    end;
    // Der Code bleibt; nur die Befehlszeile geht. Die Erklärung kommt nach den Änderungen.
    Host := AContext.Host;
    Uri := AContext.Uri;
    AContext.Defer(
      procedure
      begin
        Host.Notify(Uri, Text);
      end);
    AEdits := [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /fmt }

function ExecuteFmt(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Edit: TTextEdit;
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
    for Edit in TFormatter.Edits(Text, TPascalLexer.Tokenize(Text), AContext.Style, Routine.StartPos.Line,
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

function ExecuteMeasure(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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
      ['finally', '  ' + LogStatement(AContext, Format('Format(''%%s: %%d ms'', [%s, SW.ElapsedMilliseconds])',
      [QuotedStr(Name)])), 'end;'], '  ', AEdits, AReason);
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
  ARegistry.Register(Command('extract', 'Anweisungen darunter in eine Methode ausziehen', '/extract Laden',
    ExecuteExtract));
  ARegistry.Register(Command('inline', 'Aufruf bzw. Variable in der Zeile darunter einbetten', '/inline',
    ExecuteInline));
  ARegistry.Register(Command('fix', 'Sichere Korrekturen der Zeile darunter anwenden', '/fix', ExecuteFix));
  ARegistry.Register(Command('explain', 'Treffer der Zeile darunter erklären', '/explain', ExecuteExplain));
  ARegistry.Register(Command('fmt', 'Umgebende Routine formatieren', '/fmt', ExecuteFmt));
  ARegistry.Register(Command('measure', 'Laufzeit der folgenden Anweisungen messen', '/measure Laden',
    ExecuteMeasure));
end;

end.
