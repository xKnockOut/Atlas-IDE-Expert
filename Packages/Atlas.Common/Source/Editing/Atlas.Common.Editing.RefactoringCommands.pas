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

/// <summary>Hinweis, wenn unter /fix bzw. /explain kein Treffer steht.</summary>
function NoFindingBelowHint: string;
/// <summary>Hinweis, wenn unter /fix nur Treffer ohne sichere Korrektur stehen.</summary>
function NoSafeFixHint: string;

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
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TRefactoringCommandsText = (ExpectedIsExtractName, ExtractOnlyAppliesInThe, BelowExtractThereAreNo,
    InTheLineBelowThere, InlineOnlyAppliesInThe, BelowInlineThereIsNo, BelowThereIsNoLine, NeedsTheEditor,
    NoRulesRunForThis, FmtOnlyAppliesInThe, MeasureOnlyAppliesInThe, ExtractTheStatementsBelowInto,
    InlineTheCallOrVariable, ApplySafeFixesToThe, ExplainTheFindingsOfThe, MeasureTheRunTimeOf,
    FormatTheEnclosingRoutine, ExtractLoad, MeasureLoad, NoRuleReportsAnythingIn, ThereIsNoSafeFix);

const
  cTexts: array[TRefactoringCommandsText] of TAtlasText = (
    (De: 'Erwartet wird /extract Name'; En: 'Expected is /extract Name'),
    (De: '/extract gilt nur im Rumpf einer Routine'; En: '/extract only applies in the body of a routine'),
    (De: 'Unter /extract stehen keine Anweisungen'; En: 'Below /extract there are no statements'),
    (De: 'In der Zeile darunter steht kein Aufruf einer Routine dieser Datei und keine einbettbare Variable';
     En: 'In the line below there is no call of a routine of this file and no variable that can be inlined'),
    (De: '/inline gilt nur im Rumpf einer Routine'; En: '/inline only applies in the body of a routine'),
    (De: 'Unter /inline steht keine Anweisung'; En: 'Below /inline there is no statement'),
    (De: 'Unter /%s steht keine Zeile'; En: 'Below /%s there is no line'),
    (De: '/%s braucht den Editor'; En: '/%s needs the editor'),
    (De: 'Für diese Datei laufen keine Prüfregeln'; En: 'No rules run for this file'),
    (De: '/fmt gilt nur im Rumpf einer Routine'; En: '/fmt only applies in the body of a routine'),
    (De: '/measure gilt nur im Rumpf einer Routine'; En: '/measure only applies in the body of a routine'),
    (De: 'Anweisungen darunter in eine Methode ausziehen'; En: 'Extract the statements below into a method'),
    (De: 'Aufruf bzw. Variable in der Zeile darunter einbetten'; En: 'Inline the call or variable in the line below'),
    (De: 'Sichere Korrekturen der Zeile darunter anwenden'; En: 'Apply safe fixes to the line below'),
    (De: 'Treffer der Zeile darunter erklären'; En: 'Explain the findings of the line below'),
    (De: 'Laufzeit der folgenden Anweisungen messen'; En: 'Measure the run time of the following statements'),
    (De: 'Umgebende Routine formatieren'; En: 'Format the enclosing routine'),
    (De: '/extract Laden'; En: '/extract Load'),
    (De: '/measure Laden'; En: '/measure Load'),
    (De: 'In der Zeile darunter meldet keine Prüfregel etwas'; En: 'No rule reports anything in the line below'),
    (De: 'Für die Treffer in der Zeile darunter gibt es keine sichere Korrektur';
     En: 'There is no safe fix for the findings in the line below'));

{$SCOPEDENUMS OFF}

function NoFindingBelowHint: string;
begin
  Result := cTexts[TRefactoringCommandsText.NoRuleReportsAnythingIn].Text;
end;

function NoSafeFixHint: string;
begin
  Result := cTexts[TRefactoringCommandsText.ThereIsNoSafeFix].Text;
end;

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
  mSource: TCommandSource;
  mName, mWhy: string;
  mFirst, mLast, mIndent: Integer;
  mOptions: TExtractOptions;
  mAction: TCodeAction;
  mEdit: TTextEdit;
begin
  AEdits := nil;
  mName := Trim(AContext.Arguments);
  if not IsValidIdent(mName) then
  begin
    Exit(Fail(cTexts[TRefactoringCommandsText.ExpectedIsExtractName].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if mSource.RoutineAt = nil then
    begin
      Exit(Fail(cTexts[TRefactoringCommandsText.ExtractOnlyAppliesInThe].Text, AReason));
    end;
    mFirst := mSource.Line + 1;
    if (mFirst > High(mSource.Lines)) or (Trim(mSource.Lines[mFirst]) = '') then
    begin
      Exit(Fail(cTexts[TRefactoringCommandsText.BelowExtractThereAreNo].Text, AReason));
    end;
    // Bis zur nächsten Leerzeile; eine weniger eingerückte Zeile (end des Blocks) beendet die Auswahl.
    mIndent := LeadingOf(mSource.Lines[mFirst]);
    mLast := mFirst;
    while (mLast < High(mSource.Lines)) and (Trim(mSource.Lines[mLast + 1]) <> '') and
      (LeadingOf(mSource.Lines[mLast + 1]) >= mIndent) do
    begin
      Inc(mLast);
    end;
    mOptions := TExtractOptions.Default;
    mOptions.Style := AContext.Style;
    if not TExtractRefactoring.ExtractMethod(mSource.Text, mSource.Tree, TTextRange.Create(mFirst, mIndent, mLast,
      Length(mSource.Lines[mLast])), mOptions, mAction, mWhy) then
    begin
      Exit(Fail('/extract: ' + mWhy, AReason));
    end;
    for mEdit in mAction.Edits do
    begin
      AEdits := AEdits + [TTextEdit.Create(mEdit.Range, TRegEx.Replace(mEdit.NewText,
        '\b' + TExtractRefactoring.cMethodName + '\b', mName))];
    end;
    AEdits := AEdits + [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
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
    AWhy := cTexts[TRefactoringCommandsText.InTheLineBelowThere].Text;
  end;
end;

function ExecuteInline(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mAction: TCodeAction;
  mWhy: string;
  mNext: Integer;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if mSource.RoutineAt = nil then
    begin
      Exit(Fail(cTexts[TRefactoringCommandsText.InlineOnlyAppliesInThe].Text, AReason));
    end;
    mNext := mSource.Line + 1;
    if (mNext > High(mSource.Lines)) or (Trim(mSource.Lines[mNext]) = '') then
    begin
      Exit(Fail(cTexts[TRefactoringCommandsText.BelowInlineThereIsNo].Text, AReason));
    end;
    if not InlineOnLine(AContext, mSource, mNext, mAction, mWhy) then
    begin
      Exit(Fail('/inline: ' + mWhy, AReason));
    end;
    AEdits := mAction.Edits + [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
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
    Exit(Fail(cTexts[TRefactoringCommandsText.BelowThereIsNoLine].Fmt([AContext.Name]), AReason));
  end;
  if AContext.Host = nil then
  begin
    Exit(Fail(cTexts[TRefactoringCommandsText.NeedsTheEditor].Fmt([AContext.Name]), AReason));
  end;
  if not AContext.Host.FindingsAt(AContext.Uri, ASource.Text, ASource.Line + 1, AFindings) then
  begin
    Exit(Fail(cTexts[TRefactoringCommandsText.NoRulesRunForThis].Text, AReason));
  end;
  if AFindings = nil then
  begin
    Exit(Fail(NoFindingBelowHint, AReason));
  end;
  Result := True;
end;

function ExecuteFix(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mFindings: TArray<TSlashFinding>;
  mFinding: TSlashFinding;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not FindingsBelow(AContext, mSource, mFindings, AReason) then
    begin
      Exit(False);
    end;
    for mFinding in mFindings do
    begin
      AEdits := AEdits + mFinding.SafeFix;
    end;
    if AEdits = nil then
    begin
      Exit(Fail(NoSafeFixHint, AReason));
    end;
    AEdits := AEdits + [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

function ExecuteExplain(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mFindings: TArray<TSlashFinding>;
  mFinding: TSlashFinding;
  mHost: ISlashHost;
  mUri, mText: string;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not FindingsBelow(AContext, mSource, mFindings, AReason) then
    begin
      Exit(False);
    end;
    mText := '';
    for mFinding in mFindings do
    begin
      if mText <> '' then
      begin
        mText := mText + #10#10;
      end;
      mText := mText + mFinding.Message;
      if mFinding.Explanation <> '' then
      begin
        mText := mText + #10 + mFinding.Explanation;
      end;
    end;
    // Der Code bleibt; nur die Befehlszeile geht. Die Erklärung kommt nach den Änderungen.
    mHost := AContext.Host;
    mUri := AContext.Uri;
    AContext.Defer(
      procedure
      begin
        mHost.Notify(mUri, mText);
      end);
    AEdits := [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /fmt }

function ExecuteFmt(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine: TSyntaxNode;
  mEdit: TTextEdit;
  mText: string;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if mRoutine = nil then
    begin
      Exit(Fail(cTexts[TRefactoringCommandsText.FmtOnlyAppliesInThe].Text, AReason));
    end;
    // Formatiert wird der Text ohne Befehlszeile; deren Zeile entfernt RemoveCommand.
    mText := mSource.Text;
    for mEdit in TFormatter.Edits(mText, TPascalLexer.Tokenize(mText), AContext.Style, mRoutine.StartPos.Line,
      mRoutine.EndPos.Line) do
    begin
      if (mEdit.Range.StartPos.Line <> mSource.Line) and (mEdit.Range.EndPos.Line <> mSource.Line) then
      begin
        AEdits := AEdits + [mEdit];
      end;
    end;
    AEdits := AEdits + [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /measure }

function ExecuteMeasure(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine: TSyntaxNode;
  mName: string;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if mRoutine = nil then
    begin
      Exit(Fail(cTexts[TRefactoringCommandsText.MeasureOnlyAppliesInThe].Text, AReason));
    end;
    mName := mRoutine.Name;
    if mSource.Tree.Root.Name <> '' then
    begin
      mName := mSource.Tree.Root.Name + '.' + mName;
    end;
    if AContext.Arguments <> '' then
    begin
      mName := mName + ' ' + AContext.Arguments;
    end;
    // Name als Format-Argument: Prozentzeichen im Namen stören so nicht.
    Result := Wrap(mSource, 'measure', TWrapFrame.Create(['var SW := TStopwatch.StartNew;', 'try'],
      ['finally', '  ' + LogStatement(AContext, Format('Format(''%%s: %%d ms'', [%s, SW.ElapsedMilliseconds])',
      [QuotedStr(mName)])), 'end;'], '  '), AEdits, AReason);
    if Result then
    begin
      AddUses(mSource, AContext, mSource.Line, ['System.Diagnostics'], AEdits);
    end;
  finally
    mSource.Free;
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
  ARegister(Command('extract', cTexts[TRefactoringCommandsText.ExtractTheStatementsBelowInto].Text,
    cTexts[TRefactoringCommandsText.ExtractLoad].Text,
    ExecuteExtract));
  ARegister(Command('inline', cTexts[TRefactoringCommandsText.InlineTheCallOrVariable].Text, '/inline',
    ExecuteInline));
  ARegister(Command('fix', cTexts[TRefactoringCommandsText.ApplySafeFixesToThe].Text, '/fix', ExecuteFix));
  ARegister(Command('explain', cTexts[TRefactoringCommandsText.ExplainTheFindingsOfThe].Text, '/explain',
    ExecuteExplain));
  ARegister(Command('fmt', cTexts[TRefactoringCommandsText.FormatTheEnclosingRoutine].Text, '/fmt', ExecuteFmt));
  ARegister(Command('measure', cTexts[TRefactoringCommandsText.MeasureTheRunTimeOf].Text,
    cTexts[TRefactoringCommandsText.MeasureLoad].Text,
    ExecuteMeasure));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.RefactoringCommands', cTexts);

end.
