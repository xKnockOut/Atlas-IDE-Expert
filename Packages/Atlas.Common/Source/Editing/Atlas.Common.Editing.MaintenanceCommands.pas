unit Atlas.Common.Editing.MaintenanceCommands;

// Schnellbefehle für Pflege (#297) im Rahmen aus #293:
//   /sortuses             uses-Listen der Unit sortieren (doppelte entfernen); mit Index
//                         auch ungenutzte Units streichen, solche mit initialization
//                         und die aus usesKeep bleiben (#284, sortUsesRemoveUnused)
//   /cleanuses            nur ungenutzte Units streichen, Reihenfolge bleibt (#297)
//   /ignore regel [Grund] // lsp-ignore: regel -- Grund für die Zeile darunter; nur
//                         Regeln, die dort treffen, sonst ein Hinweis
//   /todo [-oName] [-cKat] Text
//                         // TODO -oName -cKat : Text im Format der IDE-TODO-Liste;
//                         Name aus todoOwner bzw. git config user.name, Kategorie aus
//                         todoCategory
//   /doc                  XML-Doc-Gerüst für die Routine darunter
//   /log                  Protokollzeile mit Unit- und Routinennamen (slashCommands.logCall, #304)

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Hinweis, wenn /cleanuses keinen Index hat.</summary>
function CleanUsesNoIndexHint: string;
/// <summary>Hinweis, wenn /ignore eine Regel nennt, die in der Zeile darunter nichts meldet.</summary>
function IgnoreNoHitHint: string;

/// <summary>Trägt die Pflegebefehle über ARegister ein.</summary>
procedure RegisterMaintenanceCommands(const ARegister: TSlashRegister);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.GitUser,
  Atlas.Common.Editing.ClassCommands,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TMaintenanceCommandsText = (ExpectedIsIgnoreRuleReason, BelowIgnoreThereIsNo, ExpectedIsTodoText,
    DocOnlyAppliesAboveA, LogOnlyAppliesInThe, SuppressARuleForThe, TODOCommentForTheIDE, TodoCheckErrorCase,
    XMLDocSkeletonForThe, LogLineWithUnitAnd, SortUsesLists, StrikeUnusedUsesOrderStays, CleanusesNeedsTheIndexOf,
    RuleReportsNothingInThe);

const
  cTexts: array[TMaintenanceCommandsText] of TAtlasText = (
    (De: 'Erwartet wird /ignore regel [Begründung]'; En: 'Expected is /ignore rule [reason]'),
    (De: 'Unter /ignore steht keine Zeile, die unterdrückt werden kann';
     En: 'Below /ignore there is no line that can be suppressed'),
    (De: 'Erwartet wird /todo Text'; En: 'Expected is /todo Text'),
    (De: '/doc gilt nur über einer Routine'; En: '/doc only applies above a routine'),
    (De: '/log gilt nur im Rumpf einer Routine'; En: '/log only applies in the body of a routine'),
    (De: 'Prüfregel für die Zeile darunter unterdrücken'; En: 'Suppress a rule for the line below'),
    (De: 'TODO-Kommentar für die IDE-TODO-Liste'; En: 'TODO comment for the IDE to-do list'),
    (De: '/todo Fehlerfall prüfen'; En: '/todo Check error case'),
    (De: 'XML-Doc-Gerüst für die Routine darunter'; En: 'XML doc skeleton for the routine below'),
    (De: 'Protokollzeile mit Unit- und Routinennamen'; En: 'Log line with unit and routine name'),
    (De: 'uses-Listen sortieren'; En: 'Sort uses lists'),
    (De: 'Ungenutzte uses streichen, Reihenfolge bleibt'; En: 'Strike unused uses, order stays'),
    (De: '/cleanuses braucht den Index des Projekts'; En: '/cleanuses needs the index of the project'),
    (De: 'Regel %s meldet in der Zeile darunter nichts'; En: 'Rule %s reports nothing in the line below'));

{$SCOPEDENUMS OFF}

function CleanUsesNoIndexHint: string;
begin
  Result := cTexts[TMaintenanceCommandsText.CleanusesNeedsTheIndexOf].Text;
end;

function IgnoreNoHitHint: string;
begin
  Result := cTexts[TMaintenanceCommandsText.RuleReportsNothingInThe].Text;
end;

{ /sortuses }

/// <summary>Ungenutzte Units laut Index (#284); nil ohne Host, Index oder bei abgeschalteter Einstellung.</summary>
function UnusedUnitsOf(const AContext: TSlashContext; const ATokens: TArray<TPascalToken>): TArray<string>;
var
  mUses_: TUsesContext;
begin
  Result := nil;
  if (AContext.Host = nil) or
    SameText(AContext.Host.Setting(AContext.Uri, TSlashSettings.cSortUsesRemoveUnused), 'false') then
  begin
    Exit;
  end;
  if AContext.Host.UsesContext(AContext.Uri, mUses_) and Assigned(mUses_.Info) then
  begin
    Result := TUsesActions.UnusedUnits(ATokens, mUses_.Info, mUses_.Keep);
  end;
end;

function ExecuteSortUses(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mText: string;
  mTokens: TArray<TPascalToken>;
  mOptions: TUsesRewrite;
  mEdits: TArray<TTextEdit>;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mText := mSource.Text;
    mTokens := TPascalLexer.Tokenize(mText);
    // Sortieren, doppelte und ungenutzte streichen in einem Durchgang.
    mOptions := Default(TUsesRewrite);
    mOptions.Dedupe := True;
    mOptions.Sort := True;
    mOptions.Drop := UnusedUnitsOf(AContext, mTokens);
    if not TUsesClauses.Rewrite(mTokens, mText, mOptions, mSource.LineBreak, mEdits) then
    begin
      mEdits := nil;
    end;
    AEdits := mEdits + [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /cleanuses }

function ExecuteCleanUses(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mText: string;
  mTokens: TArray<TPascalToken>;
  mUses_: TUsesContext;
  mEdits: TArray<TTextEdit>;
begin
  AEdits := nil;
  if (AContext.Host = nil) or not AContext.Host.UsesContext(AContext.Uri, mUses_) or not Assigned(mUses_.Info) then
  begin
    Exit(Fail(CleanUsesNoIndexHint, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    mText := mSource.Text;
    mTokens := TPascalLexer.Tokenize(mText);
    // Nur streichen, nicht sortieren: Die gewählte Reihenfolge bleibt.
    if not TUsesActions.RemoveUnits(mTokens, mText, TUsesActions.UnusedUnits(mTokens, mUses_.Info, mUses_.Keep),
      mSource.LineBreak, mEdits) then
    begin
      mEdits := nil;
    end;
    AEdits := mEdits + [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /ignore }

function IsRuleId(const AId: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AId <> '';
  for mIndex := 1 to Length(AId) do
  begin
    if not CharInSet(AId[mIndex], ['a'..'z', 'A'..'Z', '0'..'9', '-', '_', '*']) then
    begin
      Exit(False);
    end;
  end;
end;

function ExecuteIgnore(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mId, mReason, mComment: string;
  mSpace: Integer;
  mIds: TArray<string>;
begin
  AEdits := nil;
  mSpace := Pos(' ', AContext.Arguments);
  if mSpace = 0 then
  begin
    mSpace := Length(AContext.Arguments) + 1;
  end;
  mId := LowerCase(Copy(AContext.Arguments, 1, mSpace - 1));
  mReason := Trim(Copy(AContext.Arguments, mSpace + 1, MaxInt));
  if not IsRuleId(mId) then
  begin
    Exit(Fail(cTexts[TMaintenanceCommandsText.ExpectedIsIgnoreRuleReason].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if (mSource.Line >= High(mSource.Lines)) or (Trim(mSource.Lines[mSource.Line + 1]) = '') then
    begin
      Exit(Fail(cTexts[TMaintenanceCommandsText.BelowIgnoreThereIsNo].Text, AReason));
    end;
    // Nur Regeln, die dort treffen; Muster mit * prüfen wir nicht.
    if (AContext.Host <> nil) and (Pos('*', mId) = 0) and
      AContext.Host.RuleIdsAt(AContext.Uri, mSource.Text, mSource.Line + 1, mIds) and not MatchText(mId, mIds) then
    begin
      Exit(Fail(Format(IgnoreNoHitHint, [mId]), AReason));
    end;
    mComment := '// lsp-ignore: ' + mId;
    if mReason <> '' then
    begin
      mComment := mComment + ' -- ' + mReason;
    end;
    AEdits := [mSource.ReplaceWithIndentedLines([mComment])];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /todo }

/// <summary>Name für -o ohne Angabe: Einstellung todoOwner, git config user.name, dann der Anmeldename.</summary>
function DefaultOwner(const AContext: TSlashContext): string;
var
  mHost: ISlashHost;
  mFolder: string;
begin
  mHost := AContext.Host;
  Result := Trim(mHost.Setting(AContext.Uri, TSlashSettings.cTodoOwner));
  if Result <> '' then
  begin
    Exit;
  end;
  mFolder := '';
  if AContext.Uri <> '' then
  begin
    mFolder := ExtractFileDir(TDocumentUris.ToPath(AContext.Uri));
  end;
  Result := TGitUser.NameFor(mFolder, TGitUser.HomeFolder,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := mHost.ReadFile(AFileName, AText);
    end);
  if Result = '' then
  begin
    Result := GetEnvironmentVariable('USERNAME');
  end;
  if Result = '' then
  begin
    Result := GetEnvironmentVariable('USER');
  end;
end;

/// <summary>Zerlegt führende -oName und -cKat; AText ist der Rest. -o ohne Namen nimmt den Standardnamen,
/// -c ohne Kategorie lässt die Kategorie weg (AHasCategory).</summary>
procedure SplitTodo(const AArguments: string; out AOwner, ACategory, AText: string; out AHasCategory: Boolean);
var
  mRest, mWord: string;
  mSpace: Integer;
begin
  AOwner := '';
  ACategory := '';
  AHasCategory := False;
  mRest := Trim(AArguments);
  while (Length(mRest) >= 2) and (mRest[1] = '-') and CharInSet(mRest[2], ['o', 'O', 'c', 'C']) do
  begin
    mSpace := Pos(' ', mRest);
    if mSpace = 0 then
    begin
      mSpace := Length(mRest) + 1;
    end;
    mWord := Copy(mRest, 3, mSpace - 3);
    if CharInSet(mRest[2], ['o', 'O']) then
    begin
      AOwner := mWord;
    end
    else
    begin
      ACategory := mWord;
      AHasCategory := True;
    end;
    mRest := Trim(Copy(mRest, mSpace + 1, MaxInt));
  end;
  AText := mRest;
end;

function ExecuteTodo(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mOwner, mCategory, mText, mComment: string;
  mHasCategory: Boolean;
begin
  AEdits := nil;
  SplitTodo(AContext.Arguments, mOwner, mCategory, mText, mHasCategory);
  if mText = '' then
  begin
    Exit(Fail(cTexts[TMaintenanceCommandsText.ExpectedIsTodoText].Text, AReason));
  end;
  // Ohne Host (Prüfung stehen gebliebener Zeilen) nur die Angaben aus der Zeile.
  if AContext.Host <> nil then
  begin
    if mOwner = '' then
    begin
      mOwner := DefaultOwner(AContext);
    end;
    if not mHasCategory then
    begin
      mCategory := Trim(AContext.Host.Setting(AContext.Uri, TSlashSettings.cTodoCategory));
    end;
  end;
  mComment := '// TODO';
  if mOwner <> '' then
  begin
    mComment := mComment + ' -o' + mOwner;
  end;
  if mCategory <> '' then
  begin
    mComment := mComment + ' -c' + mCategory;
  end;
  mComment := mComment + ' : ' + mText;
  mSource := TCommandSource.Create(AContext);
  try
    AEdits := [mSource.ReplaceWithIndentedLines([mComment])];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /doc }

function IsRoutineStart(const ALine: string): Boolean;
var
  mLine: string;
begin
  mLine := LowerCase(Trim(ALine));
  if StartsStr('class ', mLine) then
  begin
    mLine := Trim(Copy(mLine, 7, MaxInt));
  end;
  Result := StartsStr('procedure ', mLine) or StartsStr('function ', mLine) or StartsStr('constructor ', mLine) or
    StartsStr('destructor ', mLine) or StartsStr('operator ', mLine);
end;

/// <summary>Signatur des Routinenkopfs ab Zeile AFirst; der Kopf kann über mehrere Zeilen gehen.</summary>
function RoutineSignatureFrom(const ALines: TArray<string>; const AFirst: Integer): string;
var
  mDeclaration: string;
  mIndex: Integer;
begin
  mDeclaration := '';
  for mIndex := AFirst to High(ALines) do
  begin
    mDeclaration := mDeclaration + ' ' + ALines[mIndex];
    if Pos(';', ALines[mIndex]) > 0 then
    begin
      Result := RoutineSignature(mDeclaration);
      if (Pos('(', Result) = 0) or (Pos(')', Result) > 0) then
      begin
        Exit;
      end;
    end;
  end;
  Result := RoutineSignature(mDeclaration);
end;

/// <summary>XML-Dokumentation mit summary, je Parameter param und bei Funktionen returns.</summary>
function DocCommentLines(const ASignature: string): TArray<string>;
var
  mName: string;
begin
  Result := ['/// <summary></summary>'];
  for mName in ParameterNames(ASignature).Split([', ']) do
  begin
    if mName <> '' then
    begin
      Result := Result + [Format('/// <param name="%s"></param>', [mName])];
    end;
  end;
  if StartsText('function ', ASignature) or StartsText('class function ', ASignature) then
  begin
    Result := Result + ['/// <returns></returns>'];
  end;
end;

function ExecuteDoc(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mNext: Integer;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mNext := mSource.Line + 1;
    while (mNext <= High(mSource.Lines)) and (Trim(mSource.Lines[mNext]) = '') do
    begin
      Inc(mNext);
    end;
    if (mNext > High(mSource.Lines)) or not IsRoutineStart(mSource.Lines[mNext]) then
    begin
      Exit(Fail(cTexts[TMaintenanceCommandsText.DocOnlyAppliesAboveA].Text, AReason));
    end;
    AEdits := [mSource.ReplaceWithIndentedLines(DocCommentLines(RoutineSignatureFrom(mSource.Lines, mNext)))];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /log }

function ExecuteLog(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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
      Exit(Fail(cTexts[TMaintenanceCommandsText.LogOnlyAppliesInThe].Text, AReason));
    end;
    mName := mRoutine.Name;
    if mSource.Tree.Root.Name <> '' then
    begin
      mName := mSource.Tree.Root.Name + '.' + mName;
    end;
    if AContext.Arguments <> '' then
    begin
      mName := mName + ': ' + AContext.Arguments;
    end;
    AEdits := [mSource.ReplaceWithIndentedLines([LogStatement(AContext, QuotedStr(mName))])];
    Result := True;
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

procedure RegisterMaintenanceCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('sortuses', cTexts[TMaintenanceCommandsText.SortUsesLists].Text, '/sortuses', ExecuteSortUses));
  ARegister(Command('cleanuses', cTexts[TMaintenanceCommandsText.StrikeUnusedUsesOrderStays].Text, '/cleanuses',
    ExecuteCleanUses));
  ARegister(Command('ignore', cTexts[TMaintenanceCommandsText.SuppressARuleForThe].Text,
    '/ignore unused-local Absicht', ExecuteIgnore));
  ARegister(Command('todo', cTexts[TMaintenanceCommandsText.TODOCommentForTheIDE].Text,
    cTexts[TMaintenanceCommandsText.TodoCheckErrorCase].Text,
    ExecuteTodo));
  ARegister(Command('doc', cTexts[TMaintenanceCommandsText.XMLDocSkeletonForThe].Text, '/doc', ExecuteDoc));
  ARegister(Command('log', cTexts[TMaintenanceCommandsText.LogLineWithUnitAnd].Text, '/log', ExecuteLog));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.MaintenanceCommands', cTexts);

end.
