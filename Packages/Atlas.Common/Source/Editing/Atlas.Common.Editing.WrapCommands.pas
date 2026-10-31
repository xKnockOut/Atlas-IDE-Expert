unit Atlas.Common.Editing.WrapCommands;

// Schnellbefehle, die Anweisungen umschließen (#296) im Rahmen aus #293:
//   /try           try … finally X.Free; end für das zuletzt erzeugte lokale Objekt
//   /lock          TMonitor bzw. vorhandene TCriticalSection um die Anweisungen
//   /sync, /sync!  TThread.Queue bzw. TThread.Synchronize
//   /ifdef SYMBOL  {$IFDEF SYMBOL} … {$ENDIF}
//   /region Name   {$REGION 'Name'} … {$ENDREGION}
//   /except        try … except on E: Exception do protokollieren und weiterwerfen (#304)
//   /case          case darunter um die fehlenden Werte seiner Aufzählung ergänzen (#50, #449)
//
// Umschlossen werden die Zeilen nach der Befehlszeile bis zum Ende des
// umgebenden Blocks (end, finally, except bzw. until).

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Trägt die Umschließen-Befehle über ARegister ein.</summary>
procedure RegisterWrapCommands(const ARegister: TSlashRegister);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CaseCompletion,
  Atlas.Common.Editing.CommandSource;

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

function ExecuteTry(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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

function ExecuteLock(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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

function ExecuteSync(const AContext: TSlashContext; const AMethod: string; out AEdits: TArray<TTextEdit>;
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

function ExecuteIfdef(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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

function ExecuteRegion(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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

function ExecuteExcept(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
begin
  Source := TCommandSource.Create(AContext);
  try
    // Nie ein leeres except: protokollieren und weiterwerfen.
    Result := Wrap(Source, 'except', ['try'], ['except', '  on E: Exception do', '  begin',
      '    ' + LogStatement(AContext, 'E.ClassName + '': '' + E.Message'), '    raise;', '  end;', 'end;'], '  ',
      AEdits, AReason);
  finally
    Source.Free;
  end;
end;

{ /case }

/// <summary>Unit der Deklaration von AType: die eigene aus dem Baum, sonst aus dem Index.</summary>
function OwnerOf(AResolver: TNameResolver; ASource: TCommandSource; const AIndex: ISymbolIndex;
  const AFileName: string; const AType: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  if SameText(AType.FileName, AFileName) then
  begin
    AUnit := AResolver.ExtractedUnit(ASource.Tree, AFileName);
    Exit(True);
  end;
  Result := (AIndex <> nil) and AIndex.FindFile(AType.FileName, AUnit);
end;

/// <summary>Werte der Aufzählung AType in Deklarationsreihenfolge, Aliase verfolgt; False, wenn AType keine
/// Aufzählung ist.</summary>
function EnumValues(AResolver: TNameResolver; ASource: TCommandSource; const AIndex: ISymbolIndex;
  const AFileName: string; AType: TResolvedSymbol; out AName: string; out AValues: TArray<string>): Boolean;
var
  Owner: TUnitIndex;
  Symbol: TIndexSymbol;
  Step: Integer;
begin
  AName := '';
  AValues := nil;
  Result := False;
  for Step := 1 to 4 do
  begin
    if not AType.Found or not AType.IsType or not OwnerOf(AResolver, ASource, AIndex, AFileName, AType, Owner) then
      Exit;
    if AType.SymbolKind = TIndexSymbolKind.EnumType then
    begin
      for Symbol in Owner.Symbols do
        if (Symbol.Kind = TIndexSymbolKind.EnumMember) and (SameText(Symbol.Container, AType.QualifiedName) or
          SameText(Symbol.Container, AType.Name)) then
          AValues := AValues + [Symbol.Name];
      AName := AType.Name;
      Exit(AValues <> nil);
    end;
    if (AType.SymbolKind <> TIndexSymbolKind.TypeAlias) or (AType.TypeName = '') or
      not AResolver.ResolveTypeFrom(Owner, AType.TypeName, AType) then
      Exit;
  end;
end;

/// <summary>Steht {$SCOPEDENUMS ON} vor der Deklaration von AType in seiner Datei?</summary>
function ScopedEnum(const AContext: TSlashContext; ASource: TCommandSource; const AFileName: string;
  const AType: TResolvedSymbol): Boolean;
var
  Text: string;
  Token: TPascalToken;
  Directive: string;
begin
  Result := False;
  if SameText(AType.FileName, AFileName) then
    Text := ASource.Text
  else if (AContext.Host = nil) or not AContext.Host.ReadFile(AType.FileName, Text) then
    Exit;
  for Token in TPascalLexer.Tokenize(Text) do
  begin
    if (Token.StartPos.Line > AType.Range.StartPos.Line) then
      Break;
    if Token.Kind <> TPascalTokenKind.Directive then
      Continue;
    Directive := UpperCase(StringReplace(Token.Text, ' ', '', [rfReplaceAll]));
    if StartsStr('{$SCOPEDENUMSON', Directive) then
      Result := True
    else if StartsStr('{$SCOPEDENUMSOFF', Directive) then
      Result := False;
  end;
end;

function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and (ATokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
    Inc(Result);
end;

function ExecuteCase(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
const
  Usage = '/case erwartet darunter eine case-Anweisung über einer Aufzählung';
var
  Source: TCommandSource;
  Tokens: TArray<TPascalToken>;
  CaseIndex, OfIndex, Index, Depth, LastIndex: Integer;
  Names, Missing, Values: TArray<string>;
  Resolver: TNameResolver;
  Owner, EnumType: TResolvedSymbol;
  TypeFound, Scoped: Boolean;
  FileName, EnumName, Prefix, Text, Label_: string;
  Slot: TCaseBranchSlot;
  InsertAt: TTextPosition;
begin
  AEdits := nil;
  if AContext.Arguments <> '' then
    Exit(Fail('/case hat keine Argumente', AReason));
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
      Exit(Fail('/case gilt nur im Rumpf einer Routine', AReason));
    Tokens := TPascalLexer.Tokenize(Source.Text);
    // Erstes Token unter der Befehlszeile muss "case" sein.
    CaseIndex := 0;
    while (CaseIndex <= High(Tokens)) and ((Tokens[CaseIndex].StartPos.Line <= Source.Line) or
      (Tokens[CaseIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive])) do
      Inc(CaseIndex);
    if (CaseIndex > High(Tokens)) or not Tokens[CaseIndex].IsKeyword('case') then
      Exit(Fail(Usage, AReason));
    // Auswahlausdruck: nur Namen und Punkte (A, Self.FArt, Kunde.Art).
    Names := nil;
    OfIndex := NextCode(Tokens, CaseIndex);
    while (OfIndex <= High(Tokens)) and not Tokens[OfIndex].IsKeyword('of') do
    begin
      if Tokens[OfIndex].Kind = TPascalTokenKind.Identifier then
        Names := Names + [Tokens[OfIndex].Text]
      else if not Tokens[OfIndex].IsSymbol('.') then
        Exit(Fail('/case versteht als Auswahl nur einen Namen wie Art oder Kunde.Art', AReason));
      OfIndex := NextCode(Tokens, OfIndex);
    end;
    if (OfIndex > High(Tokens)) or (Names = nil) then
      Exit(Fail(Usage, AReason));
    FileName := '';
    if AContext.Uri <> '' then
      FileName := TDocumentUris.ToPath(AContext.Uri);
    Resolver := TNameResolver.Create(AContext.Index);
    try
      if not Resolver.ChainType(Source.Tree, FileName, Names, Tokens[CaseIndex].Offset, Owner, EnumType,
        TypeFound) or not TypeFound or
        not EnumValues(Resolver, Source, AContext.Index, FileName, EnumType, EnumName, Values) then
        Exit(Fail(Format('Der Typ von %s ist keine bekannte Aufzählung', [string.Join('.', Names)]), AReason));
      Scoped := ScopedEnum(AContext, Source, FileName, EnumType);
    finally
      Resolver.Free;
    end;
    // Vorhandene Marken und Einrückung wie bei der Vervollständigung (#449).
    if not TCaseCompletion.BranchSlot(Source.Text, Tokens, Tokens[OfIndex].EndPos, Slot) then
      Exit(Fail(Usage, AReason));
    if not TCaseCompletion.Missing(Values, Slot.Labels, Missing) then
      Exit(Fail(Format('Eine Marke im case ist kein Wert von %s', [EnumName]), AReason));
    if Missing = nil then
      Exit(Fail(Format('Der case behandelt schon alle Werte von %s', [EnumName]), AReason));
    for Label_ in Slot.Labels do
      if Pos('.', Label_) > 0 then
        Scoped := True;
    Prefix := '';
    if Scoped then
      Prefix := EnumName + '.';
    // Letztes Token der Zweige: vor else bzw. end des case auf Ebene 0.
    LastIndex := OfIndex;
    Depth := 0;
    Index := NextCode(Tokens, OfIndex);
    while Index <= High(Tokens) do
    begin
      if Depth = 0 then
      begin
        if Tokens[Index].IsKeyword('end') or (Tokens[Index].IsKeyword('else') and
          (Tokens[LastIndex].IsSymbol(';') or (LastIndex = OfIndex))) then
          Break;
      end;
      if Tokens[Index].IsKeyword('begin') or Tokens[Index].IsKeyword('try') or Tokens[Index].IsKeyword('case') or
        Tokens[Index].IsKeyword('repeat') or Tokens[Index].IsKeyword('asm') then
        Inc(Depth)
      else if Tokens[Index].IsKeyword('end') or Tokens[Index].IsKeyword('until') then
        Dec(Depth);
      LastIndex := Index;
      Index := NextCode(Tokens, Index);
    end;
    InsertAt := Tokens[LastIndex].EndPos;
    Text := '';
    if (LastIndex <> OfIndex) and not Tokens[LastIndex].IsSymbol(';') then
      Text := ';';
    for Label_ in Missing do
      Text := Text + Source.LineBreak + Slot.BranchIndent + Prefix + Label_ + ': ;';
    if not Slot.HasEnd then
      Text := Text + Source.LineBreak + Slot.CaseIndent + 'end;';
    AEdits := [TTextEdit.Create(TTextRange.Create(InsertAt, InsertAt), Text), Source.RemoveCommand];
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

procedure RegisterWrapCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('try', 'try … finally Free um die folgenden Anweisungen', '/try', ExecuteTry));
  ARegister(Command('lock', 'Folgende Anweisungen sperren', '/lock', ExecuteLock));
  ARegister(Command('sync', 'Folgende Anweisungen per TThread.Queue im Hauptthread', '/sync',
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteSync(AContext, 'Queue', AEdits, AReason);
    end));
  ARegister(Command('sync!', 'Folgende Anweisungen per TThread.Synchronize im Hauptthread', '/sync!',
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteSync(AContext, 'Synchronize', AEdits, AReason);
    end));
  ARegister(Command('ifdef', 'Folgende Anweisungen in {$IFDEF}', '/ifdef DEBUG', ExecuteIfdef));
  ARegister(Command('except', 'Folgende Anweisungen mit Protokoll und raise absichern', '/except',
    ExecuteExcept));
  ARegister(Command('region', 'Folgende Anweisungen in {$REGION}', '/region Laden', ExecuteRegion));
  ARegister(Command('case', 'Fehlende Werte der Aufzählung im case darunter ergänzen', '/case', ExecuteCase));
end;

end.
