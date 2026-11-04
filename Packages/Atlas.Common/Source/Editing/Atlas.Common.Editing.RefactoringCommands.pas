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
  Atlas.Common.Editing.Contract;

const
  /// <summary>Hinweis, wenn unter /fix bzw. /explain kein Treffer steht.</summary>
  NoFindingBelowHint = 'In der Zeile darunter meldet keine Prüfregel etwas';
  /// <summary>Hinweis, wenn unter /fix nur Treffer ohne sichere Korrektur stehen.</summary>
  NoSafeFixHint = 'Für die Treffer in der Zeile darunter gibt es keine sichere Korrektur';

/// <summary>Trägt /extract, /inline, /fix, /explain, /fmt und /measure über ARegister ein.</summary>
procedure RegisterRefactoringCommands(const ARegister: TSlashRegister);

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
  begin
    Inc(Result);
  end;
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
  begin
    Exit(Fail('Erwartet wird /extract Name', AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
    begin
      Exit(Fail('/extract gilt nur im Rumpf einer Routine', AReason));
    end;
    First := Source.Line + 1;
    if (First > High(Source.Lines)) or (Trim(Source.Lines[First]) = '') then
    begin
      Exit(Fail('Unter /extract stehen keine Anweisungen', AReason));
    end;
    // Bis zur nächsten Leerzeile; eine weniger eingerückte Zeile (end des Blocks) beendet die Auswahl.
    Indent := LeadingOf(Source.Lines[First]);
    Last := First;
    while (Last < High(Source.Lines)) and (Trim(Source.Lines[Last + 1]) <> '') and
      (LeadingOf(Source.Lines[Last + 1]) >= Indent) do
    begin
      Inc(Last);
    end;
    Options := TExtractOptions.Default;
    Options.Style := AContext.Style;
    if not TExtractRefactoring.ExtractMethod(Source.Text, Source.Tree, TTextRange.Create(First, Indent, Last,
      Length(Source.Lines[Last])), Options, Action, Why) then
    begin
      Exit(Fail('/extract: ' + Why, AReason));
    end;
    for Edit in Action.Edits do
    begin
      AEdits := AEdits + [TTextEdit.Create(Edit.Range, TRegEx.Replace(Edit.NewText,
        '\b' + TExtractRefactoring.MethodName + '\b', Name))];
    end;
    AEdits := AEdits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /inline }

/// <summary>Bezeichner-Token in Zeile ALine.</summary>
function IdentifiersOnLine(const ATokens: TArray<TPascalToken>; ALine: Integer): TArray<TPascalToken>;
var
  mToken: TPascalToken;
begin
  Result := nil;
  for mToken in ATokens do
  begin
    if (mToken.StartPos.Line = ALine) and (mToken.Kind = TPascalTokenKind.Identifier) then
    begin
      Result := Result + [mToken];
    end;
  end;
end;

/// <summary>Bettet den ersten Aufruf unter ANames ein, dessen Routine genau einmal in der Datei steht. AWhy hält
/// den Grund des letzten Versuchs.</summary>
function InlineFirstCall(const ASource: TInlineSource; const ANames: TArray<TPascalToken>;
  const AOptions: TInlineOptions; out AAction: TCodeAction; var AWhy: string): Boolean;
var
  mToken: TPascalToken;
  mCall: TInlineCall;
  mRoutines: TArray<TSyntaxNode>;
begin
  Result := False;
  for mToken in ANames do
  begin
    if not TInlineRefactoring.CallAt(ASource.Tree, ASource.Text, mToken.StartPos, mCall) then
    begin
      Continue;
    end;
    mRoutines := TInlineRefactoring.FindRoutines(ASource.Tree, mCall.Name);
    if (Length(mRoutines) = 1) and TInlineRefactoring.InlineMethod(ASource, mToken.StartPos,
      TInlineCallee.Create(ASource, mRoutines[0]), AOptions, AAction, AWhy) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Bettet die erste Variable unter ANames ein.</summary>
function InlineFirstVariable(const ASource: TInlineSource; const ANames: TArray<TPascalToken>;
  const AOptions: TInlineOptions; out AAction: TCodeAction): Boolean;
var
  mToken: TPascalToken;
begin
  Result := False;
  for mToken in ANames do
  begin
    if TInlineRefactoring.InlineVariable(ASource, mToken.StartPos, AOptions, AAction) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Dateiname zur URI des Kontexts; '' ohne URI.</summary>
function FileNameOf(const AContext: TSlashContext): string;
begin
  Result := '';
  if AContext.Uri <> '' then
  begin
    Result := TDocumentUris.ToPath(AContext.Uri);
  end;
end;

/// <summary>Erst ein Aufruf einer Routine dieser Datei in Zeile ALine, dann eine Variable. False mit Grund.
/// </summary>
function InlineOnLine(const AContext: TSlashContext; ASource: TCommandSource; ALine: Integer;
  out AAction: TCodeAction; out AWhy: string): Boolean;
var
  mInline: TInlineSource;
  mOptions: TInlineOptions;
  mNames: TArray<TPascalToken>;
begin
  mNames := IdentifiersOnLine(ASource.Tree.Tokens, ALine);
  mInline := TInlineSource.Create(FileNameOf(AContext), ASource.Text, ASource.Tree);
  mOptions := TInlineOptions.Default;
  mOptions.Style := AContext.Style;
  AWhy := '';
  Result := InlineFirstCall(mInline, mNames, mOptions, AAction, AWhy) or
    InlineFirstVariable(mInline, mNames, mOptions, AAction);
  if not Result and (AWhy = '') then
  begin
    AWhy := 'In der Zeile darunter steht kein Aufruf einer Routine dieser Datei und keine einbettbare Variable';
  end;
end;

function ExecuteInline(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Action: TCodeAction;
  Why: string;
  Next: Integer;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
    begin
      Exit(Fail('/inline gilt nur im Rumpf einer Routine', AReason));
    end;
    Next := Source.Line + 1;
    if (Next > High(Source.Lines)) or (Trim(Source.Lines[Next]) = '') then
    begin
      Exit(Fail('Unter /inline steht keine Anweisung', AReason));
    end;
    if not InlineOnLine(AContext, Source, Next, Action, Why) then
    begin
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
  begin
    Exit(Fail(Format('Unter /%s steht keine Zeile', [AContext.Name]), AReason));
  end;
  if AContext.Host = nil then
  begin
    Exit(Fail(Format('/%s braucht den Editor', [AContext.Name]), AReason));
  end;
  if not AContext.Host.FindingsAt(AContext.Uri, ASource.Text, ASource.Line + 1, AFindings) then
  begin
    Exit(Fail('Für diese Datei laufen keine Prüfregeln', AReason));
  end;
  if AFindings = nil then
  begin
    Exit(Fail(NoFindingBelowHint, AReason));
  end;
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
    begin
      Exit(False);
    end;
    for Finding in Findings do
    begin
      AEdits := AEdits + Finding.SafeFix;
    end;
    if AEdits = nil then
    begin
      Exit(Fail(NoSafeFixHint, AReason));
    end;
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
    begin
      Exit(False);
    end;
    Text := '';
    for Finding in Findings do
    begin
      if Text <> '' then
      begin
        Text := Text + #10#10;
      end;
      Text := Text + Finding.Message;
      if Finding.Explanation <> '' then
      begin
        Text := Text + #10 + Finding.Explanation;
      end;
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
    begin
      Exit(Fail('/fmt gilt nur im Rumpf einer Routine', AReason));
    end;
    // Formatiert wird der Text ohne Befehlszeile; deren Zeile entfernt RemoveCommand.
    Text := Source.Text;
    for Edit in TFormatter.Edits(Text, TPascalLexer.Tokenize(Text), AContext.Style, Routine.StartPos.Line,
      Routine.EndPos.Line) do
    begin
      if (Edit.Range.StartPos.Line <> Source.Line) and (Edit.Range.EndPos.Line <> Source.Line) then
      begin
        AEdits := AEdits + [Edit];
      end;
    end;
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
    begin
      Exit(Fail('/measure gilt nur im Rumpf einer Routine', AReason));
    end;
    Name := Routine.Name;
    if Source.Tree.Root.Name <> '' then
    begin
      Name := Source.Tree.Root.Name + '.' + Name;
    end;
    if AContext.Arguments <> '' then
    begin
      Name := Name + ' ' + AContext.Arguments;
    end;
    // Name als Format-Argument: Prozentzeichen im Namen stören so nicht.
    Result := Wrap(Source, 'measure', ['var SW := TStopwatch.StartNew;', 'try'],
      ['finally', '  ' + LogStatement(AContext, Format('Format(''%%s: %%d ms'', [%s, SW.ElapsedMilliseconds])',
      [QuotedStr(Name)])), 'end;'], '  ', AEdits, AReason);
    if Result then
    begin
      AddUses(Source, AContext, Source.Line, ['System.Diagnostics'], AEdits);
    end;
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

procedure RegisterRefactoringCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('extract', 'Anweisungen darunter in eine Methode ausziehen', '/extract Laden',
    ExecuteExtract));
  ARegister(Command('inline', 'Aufruf bzw. Variable in der Zeile darunter einbetten', '/inline',
    ExecuteInline));
  ARegister(Command('fix', 'Sichere Korrekturen der Zeile darunter anwenden', '/fix', ExecuteFix));
  ARegister(Command('explain', 'Treffer der Zeile darunter erklären', '/explain', ExecuteExplain));
  ARegister(Command('fmt', 'Umgebende Routine formatieren', '/fmt', ExecuteFmt));
  ARegister(Command('measure', 'Laufzeit der folgenden Anweisungen messen', '/measure Laden',
    ExecuteMeasure));
end;

end.
