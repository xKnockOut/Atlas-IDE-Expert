unit Atlas.Common.Editing.MaintenanceCommands;

// Schnellbefehle für Pflege (#297) im Rahmen aus #293:
//   /sortuses             uses-Listen der Unit sortieren (doppelte entfernen)
//   /ignore regel [Grund] // lsp-ignore: regel -- Grund für die Zeile darunter
//   /todo Text            // TODO : Text im Format der IDE-TODO-Liste
//   /doc                  XML-Doc-Gerüst für die Routine darunter
//   /log                  OutputDebugString mit Unit- und Routinennamen

interface

uses
  Atlas.Common.Editing.SlashCommands;

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
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.ClassCommands,
  Atlas.Common.Editing.CommandSource;

{ /sortuses }

function ExecuteSortUses(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Text: string;
  Edits: TArray<TTextEdit>;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Text := Source.Text;
    if not TUsesClauses.Organize(TPascalLexer.Tokenize(Text), Text, True, Source.LineBreak, Edits) then
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

function ExecuteTodo(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
begin
  AEdits := nil;
  if AContext.Arguments = '' then
    Exit(Fail('Erwartet wird /todo Text', AReason));
  Source := TCommandSource.Create(AContext);
  try
    AEdits := [Source.ReplaceWithIndentedLines(['// TODO : ' + AContext.Arguments])];
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
    AEdits := [Source.ReplaceWithIndentedLines([Format('OutputDebugString(PChar(%s));',
      [QuotedStr(Name)])])];
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
  ARegistry.Register(Command('ignore', 'Prüfregel für die Zeile darunter unterdrücken',
    '/ignore unused-variable Absicht', ExecuteIgnore));
  ARegistry.Register(Command('todo', 'TODO-Kommentar für die IDE-TODO-Liste', '/todo Fehlerfall prüfen',
    ExecuteTodo));
  ARegistry.Register(Command('doc', 'XML-Doc-Gerüst für die Routine darunter', '/doc', ExecuteDoc));
  ARegistry.Register(Command('log', 'Protokollzeile mit Unit- und Routinennamen', '/log', ExecuteLog));
end;

end.
