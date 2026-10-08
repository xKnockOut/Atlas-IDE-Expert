unit BDLsp.Common.Editing.WrapCommands;

// Schnellbefehle, die Anweisungen umschließen (#296) im Rahmen aus #293:
//   /try           try … finally X.Free; end für das zuletzt erzeugte lokale Objekt
//   /lock          TMonitor bzw. vorhandene TCriticalSection um die Anweisungen
//   /sync, /sync!  TThread.Queue bzw. TThread.Synchronize
//   /ifdef SYMBOL  {$IFDEF SYMBOL} … {$ENDIF}
//   /region Name   {$REGION 'Name'} … {$ENDREGION}
//   /except        try … except on E: Exception do protokollieren und weiterwerfen (#304)
//
// Umschlossen werden die Zeilen nach der Befehlszeile bis zum Ende des
// umgebenden Blocks (end, finally, except bzw. until).

interface

uses
  BDLsp.Common.Editing.SlashCommands;

/// <summary>Trägt die Umschließen-Befehle in ARegistry ein.</summary>
procedure RegisterWrapCommands(ARegistry: TSlashCommandRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Editing.CommandSource;

/// <summary>Zeile des Tokens, das den Block um ALine schließt; -1 ohne.</summary>
function BlockEnd(ASource: TCommandSource; ALine: Integer): Integer;
var
  Tokens: TArray<TPascalToken>;
  Index, Depth: Integer;
begin
  Tokens := ASource.Tree.Tokens;
  Depth := 0;
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].StartPos.Line <= ALine) or (Tokens[Index].Kind <> TPascalTokenKind.Keyword) then
      Continue;
    if Tokens[Index].IsKeyword('begin') or Tokens[Index].IsKeyword('try') or Tokens[Index].IsKeyword('case') or
      Tokens[Index].IsKeyword('repeat') or Tokens[Index].IsKeyword('asm') then
      Inc(Depth)
    else if Tokens[Index].IsKeyword('end') or Tokens[Index].IsKeyword('until') then
    begin
      if Depth = 0 then
        Exit(Tokens[Index].StartPos.Line);
      Dec(Depth);
    end
    else if (Depth = 0) and (Tokens[Index].IsKeyword('finally') or Tokens[Index].IsKeyword('except')) then
      Exit(Tokens[Index].StartPos.Line);
  end;
  Result := -1;
end;

/// <summary>Ersetzt Befehlszeile und folgende Anweisungen durch AHead, die eingerückten Anweisungen und ATail.
/// ABodyIndent ist die zusätzliche Einrückung der Anweisungen.</summary>
function Wrap(ASource: TCommandSource; const AName: string; const AHead, ATail: array of string;
  const ABodyIndent: string; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Stop, Index: Integer;
  Indent, Text: string;
begin
  AEdits := nil;
  if ASource.RoutineAt = nil then
    Exit(Fail('/' + AName + ' gilt nur im Rumpf einer Routine', AReason));
  Stop := BlockEnd(ASource, ASource.Line);
  if (Stop < 0) or (Stop <= ASource.Line + 1) then
    Exit(Fail('Nach /' + AName + ' stehen keine Anweisungen im Block', AReason));
  Indent := ASource.Indent(ASource.Line);
  Text := '';
  for Index := 0 to High(AHead) do
    Text := Text + Indent + AHead[Index] + ASource.LineBreak;
  for Index := ASource.Line + 1 to Stop - 1 do
    if Trim(ASource.Lines[Index]) = '' then
      Text := Text + ASource.LineBreak
    else
      Text := Text + ABodyIndent + ASource.Lines[Index] + ASource.LineBreak;
  for Index := 0 to High(ATail) do
    Text := Text + Indent + ATail[Index] + ASource.LineBreak;
  AEdits := [TRuleEdit.Create(TTextRange.Create(ASource.Line, 0, Stop, 0), Text)];
  Result := True;
end;

{ /try }

/// <summary>Variable aus "X := T….Create(…)" bzw. "var X := …Create"; '' sonst.</summary>
function CreatedVariable(const ALine: string): string;
var
  Line: string;
  Assign: Integer;
begin
  Result := '';
  Line := Trim(ALine);
  if StartsText('var ', Line) then
    Line := Trim(Copy(Line, 5, MaxInt));
  Assign := Pos(':=', Line);
  if (Assign = 0) or (Pos('.create', LowerCase(Copy(Line, Assign, MaxInt))) = 0) then
    Exit;
  Result := Trim(Copy(Line, 1, Assign - 1));
  // Inline-Variable mit Typ: "Liste: TStringList".
  if Pos(':', Result) > 0 then
    Result := Trim(Copy(Result, 1, Pos(':', Result) - 1));
  if not IsValidIdent(Result) then
    Result := '';
end;

function IsField(ASource: TCommandSource; const AName: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in ASource.UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Name, AName) then
      Exit(True);
  Result := False;
end;

function ExecuteTry(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Index: Integer;
  Variable: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine = nil then
      Exit(Fail('/try gilt nur im Rumpf einer Routine', AReason));
    Variable := '';
    for Index := Source.Line - 1 downto Routine.StartPos.Line do
    begin
      Variable := CreatedVariable(Source.Lines[Index]);
      if Variable <> '' then
        Break;
    end;
    if (Variable = '') or IsField(Source, Variable) then
      Exit(Fail('Vor /try wird kein lokales Objekt erzeugt', AReason));
    // Result gehört dem Aufrufer: nur bei einer Ausnahme freigeben.
    if SameText(Variable, 'Result') then
      Result := Wrap(Source, 'try', ['try'], ['except', '  Result.Free;', '  raise;', 'end;'], '  ', AEdits,
        AReason)
    else
      Result := Wrap(Source, 'try', ['try'], ['finally', '  ' + Variable + '.Free;', 'end;'], '  ', AEdits,
        AReason);
  finally
    Source.Free;
  end;
end;

{ /lock }

function ExecuteLock(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Symbol: TIndexSymbol;
  Section: string;
begin
  Source := TCommandSource.Create(AContext);
  try
    Section := '';
    if Source.ClassAt(ClassSymbol) then
      for Symbol in Source.UnitIndex.Symbols do
        if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, ClassSymbol.Name) and
          (SameText(Symbol.TypeName, 'TCriticalSection') or SameText(Symbol.TypeName, 'TSyncObjs.TCriticalSection')) then
        begin
          Section := Symbol.Name;
          Break;
        end;
    if Section <> '' then
      Result := Wrap(Source, 'lock', [Section + '.Enter;', 'try'], ['finally', '  ' + Section + '.Leave;', 'end;'],
        '  ', AEdits, AReason)
    else
      Result := Wrap(Source, 'lock', ['TMonitor.Enter(Self);', 'try'], ['finally', '  TMonitor.Exit(Self);',
        'end;'], '  ', AEdits, AReason);
  finally
    Source.Free;
  end;
end;

{ /sync, /ifdef, /region }

function ExecuteSync(const AContext: TSlashContext; const AMethod: string; out AEdits: TArray<TRuleEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
begin
  Source := TCommandSource.Create(AContext);
  try
    Result := Wrap(Source, AContext.Name, ['TThread.' + AMethod + '(nil,', '  procedure', '  begin'],
      ['  end);'], '    ', AEdits, AReason);
  finally
    Source.Free;
  end;
end;

function ExecuteIfdef(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
begin
  AEdits := nil;
  if not IsValidIdent(AContext.Arguments) then
    Exit(Fail('Erwartet wird /ifdef SYMBOL', AReason));
  Source := TCommandSource.Create(AContext);
  try
    Result := Wrap(Source, 'ifdef', ['{$IFDEF ' + AContext.Arguments + '}'], ['{$ENDIF}'], '', AEdits, AReason);
  finally
    Source.Free;
  end;
end;

function ExecuteRegion(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
begin
  AEdits := nil;
  if AContext.Arguments = '' then
    Exit(Fail('Erwartet wird /region Name', AReason));
  Source := TCommandSource.Create(AContext);
  try
    Result := Wrap(Source, 'region', ['{$REGION ''' + StringReplace(AContext.Arguments, '''', '''''',
      [rfReplaceAll]) + '''}'], ['{$ENDREGION}'], '', AEdits, AReason);
  finally
    Source.Free;
  end;
end;

{ /except }

function ExecuteExcept(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
begin
  Source := TCommandSource.Create(AContext);
  try
    // Nie ein leeres except: protokollieren und weiterwerfen.
    Result := Wrap(Source, 'except', ['try'], ['except', '  on E: Exception do', '  begin',
      '    OutputDebugString(PChar(E.ClassName + '': '' + E.Message));', '    raise;', '  end;', 'end;'], '  ',
      AEdits, AReason);
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

procedure RegisterWrapCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('try', 'try … finally Free um die folgenden Anweisungen', '/try', ExecuteTry));
  ARegistry.Register(Command('lock', 'Folgende Anweisungen sperren', '/lock', ExecuteLock));
  ARegistry.Register(Command('sync', 'Folgende Anweisungen per TThread.Queue im Hauptthread', '/sync',
    function(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteSync(AContext, 'Queue', AEdits, AReason);
    end));
  ARegistry.Register(Command('sync!', 'Folgende Anweisungen per TThread.Synchronize im Hauptthread', '/sync!',
    function(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteSync(AContext, 'Synchronize', AEdits, AReason);
    end));
  ARegistry.Register(Command('ifdef', 'Folgende Anweisungen in {$IFDEF}', '/ifdef DEBUG', ExecuteIfdef));
  ARegistry.Register(Command('except', 'Folgende Anweisungen mit Protokoll und raise absichern', '/except',
    ExecuteExcept));
  ARegistry.Register(Command('region', 'Folgende Anweisungen in {$REGION}', '/region Laden', ExecuteRegion));
end;

end.
