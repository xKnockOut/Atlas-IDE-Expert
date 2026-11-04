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

const
  /// <summary>Hinweis, wenn /cleanuses keinen Index hat.</summary>
  CleanUsesNoIndexHint = '/cleanuses braucht den Index des Projekts';
  /// <summary>Hinweis, wenn /ignore eine Regel nennt, die in der Zeile darunter nichts meldet.</summary>
  IgnoreNoHitHint = 'Regel %s meldet in der Zeile darunter nichts';

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
  Atlas.Common.Editing.CommandSource;

{ /sortuses }

/// <summary>Ungenutzte Units laut Index (#284); nil ohne Host, Index oder bei abgeschalteter Einstellung.</summary>
function UnusedUnitsOf(const AContext: TSlashContext; const ATokens: TArray<TPascalToken>): TArray<string>;
var
  Uses_: TUsesContext;
begin
  Result := nil;
  if (AContext.Host = nil) or
    SameText(AContext.Host.Setting(AContext.Uri, TSlashSettings.SortUsesRemoveUnused), 'false') then
  begin
    Exit;
  end;
  if AContext.Host.UsesContext(AContext.Uri, Uses_) and Assigned(Uses_.Info) then
  begin
    Result := TUsesActions.UnusedUnits(ATokens, Uses_.Info, Uses_.Keep);
  end;
end;

function ExecuteSortUses(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Text: string;
  Tokens: TArray<TPascalToken>;
  Options: TUsesRewrite;
  Edits: TArray<TTextEdit>;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Text := Source.Text;
    Tokens := TPascalLexer.Tokenize(Text);
    // Sortieren, doppelte und ungenutzte streichen in einem Durchgang.
    Options := Default(TUsesRewrite);
    Options.Dedupe := True;
    Options.Sort := True;
    Options.Drop := UnusedUnitsOf(AContext, Tokens);
    if not TUsesClauses.Rewrite(Tokens, Text, Options, Source.LineBreak, Edits) then
    begin
      Edits := nil;
    end;
    AEdits := Edits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /cleanuses }

function ExecuteCleanUses(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Text: string;
  Tokens: TArray<TPascalToken>;
  Uses_: TUsesContext;
  Edits: TArray<TTextEdit>;
begin
  AEdits := nil;
  if (AContext.Host = nil) or not AContext.Host.UsesContext(AContext.Uri, Uses_) or not Assigned(Uses_.Info) then
  begin
    Exit(Fail(CleanUsesNoIndexHint, AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    Text := Source.Text;
    Tokens := TPascalLexer.Tokenize(Text);
    // Nur streichen, nicht sortieren: Die gewählte Reihenfolge bleibt.
    if not TUsesActions.RemoveUnits(Tokens, Text, TUsesActions.UnusedUnits(Tokens, Uses_.Info, Uses_.Keep),
      Source.LineBreak, Edits) then
    begin
      Edits := nil;
    end;
    AEdits := Edits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /ignore }

function IsRuleId(const AId: string): Boolean;
var
  Index: Integer;
begin
  Result := AId <> '';
  for Index := 1 to Length(AId) do
  begin
    if not CharInSet(AId[Index], ['a'..'z', 'A'..'Z', '0'..'9', '-', '_', '*']) then
    begin
      Exit(False);
    end;
  end;
end;

function ExecuteIgnore(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Id, Reason, Comment: string;
  Space: Integer;
  Ids: TArray<string>;
begin
  AEdits := nil;
  Space := Pos(' ', AContext.Arguments);
  if Space = 0 then
  begin
    Space := Length(AContext.Arguments) + 1;
  end;
  Id := LowerCase(Copy(AContext.Arguments, 1, Space - 1));
  Reason := Trim(Copy(AContext.Arguments, Space + 1, MaxInt));
  if not IsRuleId(Id) then
  begin
    Exit(Fail('Erwartet wird /ignore regel [Begründung]', AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    if (Source.Line >= High(Source.Lines)) or (Trim(Source.Lines[Source.Line + 1]) = '') then
    begin
      Exit(Fail('Unter /ignore steht keine Zeile, die unterdrückt werden kann', AReason));
    end;
    // Nur Regeln, die dort treffen; Muster mit * prüfen wir nicht.
    if (AContext.Host <> nil) and (Pos('*', Id) = 0) and
      AContext.Host.RuleIdsAt(AContext.Uri, Source.Text, Source.Line + 1, Ids) and not MatchText(Id, Ids) then
    begin
      Exit(Fail(Format(IgnoreNoHitHint, [Id]), AReason));
    end;
    Comment := '// lsp-ignore: ' + Id;
    if Reason <> '' then
    begin
      Comment := Comment + ' -- ' + Reason;
    end;
    AEdits := [Source.ReplaceWithIndentedLines([Comment])];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /todo }

/// <summary>Name für -o ohne Angabe: Einstellung todoOwner, git config user.name, dann der Anmeldename.</summary>
function DefaultOwner(const AContext: TSlashContext): string;
var
  Host: ISlashHost;
  Folder: string;
begin
  Host := AContext.Host;
  Result := Trim(Host.Setting(AContext.Uri, TSlashSettings.TodoOwner));
  if Result <> '' then
  begin
    Exit;
  end;
  Folder := '';
  if AContext.Uri <> '' then
  begin
    Folder := ExtractFileDir(TDocumentUris.ToPath(AContext.Uri));
  end;
  Result := TGitUser.NameFor(Folder, TGitUser.HomeFolder,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Host.ReadFile(AFileName, AText);
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
  Rest, Word: string;
  Space: Integer;
begin
  AOwner := '';
  ACategory := '';
  AHasCategory := False;
  Rest := Trim(AArguments);
  while (Length(Rest) >= 2) and (Rest[1] = '-') and CharInSet(Rest[2], ['o', 'O', 'c', 'C']) do
  begin
    Space := Pos(' ', Rest);
    if Space = 0 then
    begin
      Space := Length(Rest) + 1;
    end;
    Word := Copy(Rest, 3, Space - 3);
    if CharInSet(Rest[2], ['o', 'O']) then
    begin
      AOwner := Word;
    end
    else
    begin
      ACategory := Word;
      AHasCategory := True;
    end;
    Rest := Trim(Copy(Rest, Space + 1, MaxInt));
  end;
  AText := Rest;
end;

function ExecuteTodo(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Owner, Category, Text, Comment: string;
  HasCategory: Boolean;
begin
  AEdits := nil;
  SplitTodo(AContext.Arguments, Owner, Category, Text, HasCategory);
  if Text = '' then
  begin
    Exit(Fail('Erwartet wird /todo Text', AReason));
  end;
  // Ohne Host (Prüfung stehen gebliebener Zeilen) nur die Angaben aus der Zeile.
  if AContext.Host <> nil then
  begin
    if Owner = '' then
    begin
      Owner := DefaultOwner(AContext);
    end;
    if not HasCategory then
    begin
      Category := Trim(AContext.Host.Setting(AContext.Uri, TSlashSettings.TodoCategory));
    end;
  end;
  Comment := '// TODO';
  if Owner <> '' then
  begin
    Comment := Comment + ' -o' + Owner;
  end;
  if Category <> '' then
  begin
    Comment := Comment + ' -c' + Category;
  end;
  Comment := Comment + ' : ' + Text;
  Source := TCommandSource.Create(AContext);
  try
    AEdits := [Source.ReplaceWithIndentedLines([Comment])];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /doc }

function IsRoutineStart(const ALine: string): Boolean;
var
  Line: string;
begin
  Line := LowerCase(Trim(ALine));
  if StartsStr('class ', Line) then
  begin
    Line := Trim(Copy(Line, 7, MaxInt));
  end;
  Result := StartsStr('procedure ', Line) or StartsStr('function ', Line) or StartsStr('constructor ', Line) or
    StartsStr('destructor ', Line) or StartsStr('operator ', Line);
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
  Source: TCommandSource;
  Next: Integer;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Next := Source.Line + 1;
    while (Next <= High(Source.Lines)) and (Trim(Source.Lines[Next]) = '') do
    begin
      Inc(Next);
    end;
    if (Next > High(Source.Lines)) or not IsRoutineStart(Source.Lines[Next]) then
    begin
      Exit(Fail('/doc gilt nur über einer Routine', AReason));
    end;
    AEdits := [Source.ReplaceWithIndentedLines(DocCommentLines(RoutineSignatureFrom(Source.Lines, Next)))];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /log }

function ExecuteLog(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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
      Exit(Fail('/log gilt nur im Rumpf einer Routine', AReason));
    end;
    Name := Routine.Name;
    if Source.Tree.Root.Name <> '' then
    begin
      Name := Source.Tree.Root.Name + '.' + Name;
    end;
    if AContext.Arguments <> '' then
    begin
      Name := Name + ': ' + AContext.Arguments;
    end;
    AEdits := [Source.ReplaceWithIndentedLines([LogStatement(AContext, QuotedStr(Name))])];
    Result := True;
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

procedure RegisterMaintenanceCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('sortuses', 'uses-Listen sortieren', '/sortuses', ExecuteSortUses));
  ARegister(Command('cleanuses', 'Ungenutzte uses streichen, Reihenfolge bleibt', '/cleanuses',
    ExecuteCleanUses));
  ARegister(Command('ignore', 'Prüfregel für die Zeile darunter unterdrücken',
    '/ignore unused-local Absicht', ExecuteIgnore));
  ARegister(Command('todo', 'TODO-Kommentar für die IDE-TODO-Liste', '/todo Fehlerfall prüfen',
    ExecuteTodo));
  ARegister(Command('doc', 'XML-Doc-Gerüst für die Routine darunter', '/doc', ExecuteDoc));
  ARegister(Command('log', 'Protokollzeile mit Unit- und Routinennamen', '/log', ExecuteLog));
end;

end.
