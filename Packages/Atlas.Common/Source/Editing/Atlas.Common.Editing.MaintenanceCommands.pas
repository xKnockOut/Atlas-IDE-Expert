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
  Atlas.Common.Editing.SlashCommands;

const
  /// <summary>Hinweis, wenn /cleanuses keinen Index hat.</summary>
  CleanUsesNoIndexHint = '/cleanuses braucht den Index des Projekts';
  /// <summary>Hinweis, wenn /ignore eine Regel nennt, die in der Zeile darunter nichts meldet.</summary>
  IgnoreNoHitHint = 'Regel %s meldet in der Zeile darunter nichts';

/// <summary>Trägt die Pflegebefehle in ARegistry ein.</summary>
procedure RegisterMaintenanceCommands(ARegistry: TSlashCommandRegistry);

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
    Exit;
  if AContext.Host.UsesContext(AContext.Uri, Uses_) and Assigned(Uses_.Info) then
    Result := TUsesActions.UnusedUnits(ATokens, Uses_.Info, Uses_.Keep);
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
      Edits := nil;
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
    Exit(Fail(CleanUsesNoIndexHint, AReason));
  Source := TCommandSource.Create(AContext);
  try
    Text := Source.Text;
    Tokens := TPascalLexer.Tokenize(Text);
    // Nur streichen, nicht sortieren: Die gewählte Reihenfolge bleibt.
    if not TUsesActions.RemoveUnits(Tokens, Text, TUsesActions.UnusedUnits(Tokens, Uses_.Info, Uses_.Keep),
      Source.LineBreak, Edits) then
      Edits := nil;
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
    if not CharInSet(AId[Index], ['a'..'z', 'A'..'Z', '0'..'9', '-', '_', '*']) then
      Exit(False);
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
    Space := Length(AContext.Arguments) + 1;
  Id := LowerCase(Copy(AContext.Arguments, 1, Space - 1));
  Reason := Trim(Copy(AContext.Arguments, Space + 1, MaxInt));
  if not IsRuleId(Id) then
    Exit(Fail('Erwartet wird /ignore regel [Begründung]', AReason));
  Source := TCommandSource.Create(AContext);
  try
    if (Source.Line >= High(Source.Lines)) or (Trim(Source.Lines[Source.Line + 1]) = '') then
      Exit(Fail('Unter /ignore steht keine Zeile, die unterdrückt werden kann', AReason));
    // Nur Regeln, die dort treffen; Muster mit * prüfen wir nicht.
    if (AContext.Host <> nil) and (Pos('*', Id) = 0) and
      AContext.Host.RuleIdsAt(AContext.Uri, Source.Text, Source.Line + 1, Ids) and not MatchText(Id, Ids) then
      Exit(Fail(Format(IgnoreNoHitHint, [Id]), AReason));
    Comment := '// lsp-ignore: ' + Id;
    if Reason <> '' then
      Comment := Comment + ' -- ' + Reason;
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
    Exit;
  Folder := '';
  if AContext.Uri <> '' then
    Folder := ExtractFileDir(TDocumentUris.ToPath(AContext.Uri));
  Result := TGitUser.NameFor(Folder, TGitUser.HomeFolder,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Host.ReadFile(AFileName, AText);
    end);
  if Result = '' then
    Result := GetEnvironmentVariable('USERNAME');
  if Result = '' then
    Result := GetEnvironmentVariable('USER');
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
      Space := Length(Rest) + 1;
    Word := Copy(Rest, 3, Space - 3);
    if CharInSet(Rest[2], ['o', 'O']) then
      AOwner := Word
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
    Exit(Fail('Erwartet wird /todo Text', AReason));
  // Ohne Host (Prüfung stehen gebliebener Zeilen) nur die Angaben aus der Zeile.
  if AContext.Host <> nil then
  begin
    if Owner = '' then
      Owner := DefaultOwner(AContext);
    if not HasCategory then
      Category := Trim(AContext.Host.Setting(AContext.Uri, TSlashSettings.TodoCategory));
  end;
  Comment := '// TODO';
  if Owner <> '' then
    Comment := Comment + ' -o' + Owner;
  if Category <> '' then
    Comment := Comment + ' -c' + Category;
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
    Line := Trim(Copy(Line, 7, MaxInt));
  Result := StartsStr('procedure ', Line) or StartsStr('function ', Line) or StartsStr('constructor ', Line) or
    StartsStr('destructor ', Line) or StartsStr('operator ', Line);
end;

function ExecuteDoc(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Next, Index: Integer;
  Declaration, Signature, Name: string;
  Lines: TArray<string>;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Next := Source.Line + 1;
    while (Next <= High(Source.Lines)) and (Trim(Source.Lines[Next]) = '') do
      Inc(Next);
    if (Next > High(Source.Lines)) or not IsRoutineStart(Source.Lines[Next]) then
      Exit(Fail('/doc gilt nur über einer Routine', AReason));
    // Kopf kann über mehrere Zeilen gehen.
    Declaration := '';
    for Index := Next to High(Source.Lines) do
    begin
      Declaration := Declaration + ' ' + Source.Lines[Index];
      if Pos(';', Source.Lines[Index]) > 0 then
      begin
        Signature := RoutineSignature(Declaration);
        if (Pos('(', Signature) = 0) or (Pos(')', Signature) > 0) then
          Break;
      end;
    end;
    Signature := RoutineSignature(Declaration);
    Lines := ['/// <summary></summary>'];
    for Name in ParameterNames(Signature).Split([', ']) do
      if Name <> '' then
        Lines := Lines + [Format('/// <param name="%s"></param>', [Name])];
    if StartsText('function ', Signature) or StartsText('class function ', Signature) then
      Lines := Lines + ['/// <returns></returns>'];
    AEdits := [Source.ReplaceWithIndentedLines(Lines)];
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
      Exit(Fail('/log gilt nur im Rumpf einer Routine', AReason));
    Name := Routine.Name;
    if Source.Tree.Root.Name <> '' then
      Name := Source.Tree.Root.Name + '.' + Name;
    if AContext.Arguments <> '' then
      Name := Name + ': ' + AContext.Arguments;
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

procedure RegisterMaintenanceCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('sortuses', 'uses-Listen sortieren', '/sortuses', ExecuteSortUses));
  ARegistry.Register(Command('cleanuses', 'Ungenutzte uses streichen, Reihenfolge bleibt', '/cleanuses',
    ExecuteCleanUses));
  ARegistry.Register(Command('ignore', 'Prüfregel für die Zeile darunter unterdrücken',
    '/ignore unused-local Absicht', ExecuteIgnore));
  ARegistry.Register(Command('todo', 'TODO-Kommentar für die IDE-TODO-Liste', '/todo Fehlerfall prüfen',
    ExecuteTodo));
  ARegistry.Register(Command('doc', 'XML-Doc-Gerüst für die Routine darunter', '/doc', ExecuteDoc));
  ARegistry.Register(Command('log', 'Protokollzeile mit Unit- und Routinennamen', '/log', ExecuteLog));
end;

end.
