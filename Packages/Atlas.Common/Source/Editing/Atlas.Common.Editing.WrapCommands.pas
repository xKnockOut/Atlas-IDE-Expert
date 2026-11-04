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
  begin
    Line := Trim(Copy(Line, 5, MaxInt));
  end;
  Assign := Pos(':=', Line);
  if (Assign = 0) or (Pos('.create', LowerCase(Copy(Line, Assign, MaxInt))) = 0) then
  begin
    Exit;
  end;
  Result := Trim(Copy(Line, 1, Assign - 1));
  // Inline-Variable mit Typ: "Liste: TStringList".
  if Pos(':', Result) > 0 then
  begin
    Result := Trim(Copy(Result, 1, Pos(':', Result) - 1));
  end;
  if not IsValidIdent(Result) then
  begin
    Result := '';
  end;
end;

function IsField(ASource: TCommandSource; const AName: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in ASource.UnitIndex.Symbols do
  begin
    if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Name, AName) then
    begin
      Exit(True);
    end;
  end;
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
    begin
      Exit(Fail('/try gilt nur im Rumpf einer Routine', AReason));
    end;
    Variable := '';
    for Index := Source.Line - 1 downto Routine.StartPos.Line do
    begin
      Variable := CreatedVariable(Source.Lines[Index]);
      if Variable <> '' then
      begin
        Break;
      end;
    end;
    if (Variable = '') or IsField(Source, Variable) then
    begin
      Exit(Fail('Vor /try wird kein lokales Objekt erzeugt', AReason));
    end;
    // Result gehört dem Aufrufer: nur bei einer Ausnahme freigeben.
    if SameText(Variable, 'Result') then
    begin
      Result := Wrap(Source, 'try', TWrapFrame.Create(['try'], ['except', '  Result.Free;', '  raise;', 'end;'], '  '),
        AEdits, AReason);
    end
    else
    begin
      Result := Wrap(Source, 'try', TWrapFrame.Create(['try'], ['finally', '  ' + Variable + '.Free;', 'end;'], '  '),
        AEdits, AReason);
    end;
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
    begin
      for Symbol in Source.UnitIndex.Symbols do
      begin
        if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, ClassSymbol.Name) and
          (SameText(Symbol.TypeName, 'TCriticalSection') or SameText(Symbol.TypeName, 'TSyncObjs.TCriticalSection')) then
        begin
          Section := Symbol.Name;
          Break;
        end;
      end;
    end;
    if Section <> '' then
    begin
      Result := Wrap(Source, 'lock', TWrapFrame.Create([Section + '.Enter;', 'try'], ['finally',
        '  ' + Section + '.Leave;', 'end;'], '  '), AEdits, AReason);
    end
    else
    begin
      Result := Wrap(Source, 'lock', TWrapFrame.Create(['TMonitor.Enter(Self);', 'try'], ['finally',
        '  TMonitor.Exit(Self);', 'end;'], '  '), AEdits, AReason);
    end;
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
    Result := Wrap(Source, AContext.Name, TWrapFrame.Create(['TThread.' + AMethod + '(nil,', '  procedure', '  begin'],
      ['  end);'], '    '), AEdits, AReason);
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
  begin
    Exit(Fail('Erwartet wird /ifdef SYMBOL', AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    Result := Wrap(Source, 'ifdef', TWrapFrame.Create(['{$IFDEF ' + AContext.Arguments + '}'], ['{$ENDIF}'], ''),
      AEdits, AReason);
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
  begin
    Exit(Fail('Erwartet wird /region Name', AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    Result := Wrap(Source, 'region', TWrapFrame.Create(['{$REGION ''' + StringReplace(AContext.Arguments, '''', '''''',
      [rfReplaceAll]) + '''}'], ['{$ENDREGION}'], ''), AEdits, AReason);
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
    Result := Wrap(Source, 'except', TWrapFrame.Create(['try'], ['except', '  on E: Exception do', '  begin',
      '    ' + LogStatement(AContext, 'E.ClassName + '': '' + E.Message'), '    raise;', '  end;', 'end;'], '  '),
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

/// <summary>Werte der Aufzählung AType in Deklarationsreihenfolge.</summary>
function EnumMembers(const AOwner: TUnitIndex; const AType: TResolvedSymbol): TArray<string>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in AOwner.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.EnumMember) and (SameText(mSymbol.Container, AType.QualifiedName) or
      SameText(mSymbol.Container, AType.Name)) then
    begin
      Result := Result + [mSymbol.Name];
    end;
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
  begin
    Text := ASource.Text;
  end
  else if (AContext.Host = nil) or not AContext.Host.ReadFile(AType.FileName, Text) then
  begin
    Exit;
  end;
  for Token in TPascalLexer.Tokenize(Text) do
  begin
    if (Token.StartPos.Line > AType.Range.StartPos.Line) then
    begin
      Break;
    end;
    if Token.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    Directive := UpperCase(StringReplace(Token.Text, ' ', '', [rfReplaceAll]));
    if StartsStr('{$SCOPEDENUMSON', Directive) then
    begin
      Result := True;
    end
    else if StartsStr('{$SCOPEDENUMSOFF', Directive) then
    begin
      Result := False;
    end;
  end;
end;

function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and (ATokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Öffnet das Token einen Block, den ein end bzw. until schließt?</summary>
function OpensBlock(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('begin') or AToken.IsKeyword('try') or AToken.IsKeyword('case') or
    AToken.IsKeyword('repeat') or AToken.IsKeyword('asm');
end;

const
  cCaseUsage = '/case erwartet darunter eine case-Anweisung über einer Aufzählung';

type
  /// <summary>Ablauf von /case: fehlende Werte der Aufzählung als Zweige ergänzen.</summary>
  TCaseCommand = class
  private
    FContext: TSlashContext;
    FSource: TCommandSource;
    FTokens: TArray<TPascalToken>;
    FCaseIndex: Integer;
    FOfIndex: Integer;
    FNames: TArray<string>;
    FFileName: string;
    FEnumName: string;
    FValues: TArray<string>;
    FScoped: Boolean;
    FSlot: TCaseBranchSlot;
    FMissing: TArray<string>;
    FReason: string;
    function Fail(const AReason: string): Boolean;
    /// <summary>case unter der Befehlszeile und sein Auswahlausdruck (nur Namen und Punkte).</summary>
    function FindCase: Boolean;
    /// <summary>Werte der Aufzählung AType, Aliase verfolgt; False, wenn AType keine Aufzählung ist.</summary>
    function EnumValues(AResolver: TNameResolver; AType: TResolvedSymbol): Boolean;
    /// <summary>Typ des Auswahlausdrucks als Aufzählung bestimmen.</summary>
    function ResolveEnum: Boolean;
    /// <summary>Vorhandene Marken lesen und die fehlenden bestimmen.</summary>
    function FindMissing: Boolean;
    /// <summary>Letztes Token der Zweige: vor else bzw. end des case auf Ebene 0.</summary>
    function LastBranchToken: Integer;
    /// <summary>Text der neuen Zweige hinter dem Token ALastIndex.</summary>
    function BranchText(ALastIndex: Integer): string;
  public
    constructor Create(const AContext: TSlashContext);
    destructor Destroy; override;
    function Run(out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
  end;

constructor TCaseCommand.Create(const AContext: TSlashContext);
begin
  inherited Create;
  FContext := AContext;
  FSource := TCommandSource.Create(AContext);
end;

destructor TCaseCommand.Destroy;
begin
  FSource.Free;
  inherited;
end;

function TCaseCommand.Fail(const AReason: string): Boolean;
begin
  FReason := AReason;
  Result := False;
end;

function TCaseCommand.FindCase: Boolean;
begin
  FTokens := TPascalLexer.Tokenize(FSource.Text);
  // Erstes Token unter der Befehlszeile muss "case" sein.
  FCaseIndex := 0;
  while (FCaseIndex <= High(FTokens)) and ((FTokens[FCaseIndex].StartPos.Line <= FSource.Line) or
    (FTokens[FCaseIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive])) do
  begin
    Inc(FCaseIndex);
  end;
  if (FCaseIndex > High(FTokens)) or not FTokens[FCaseIndex].IsKeyword('case') then
  begin
    Exit(Fail(cCaseUsage));
  end;
  // Auswahlausdruck: nur Namen und Punkte (A, Self.FArt, Kunde.Art).
  FNames := nil;
  FOfIndex := NextCode(FTokens, FCaseIndex);
  while (FOfIndex <= High(FTokens)) and not FTokens[FOfIndex].IsKeyword('of') do
  begin
    if FTokens[FOfIndex].Kind = TPascalTokenKind.Identifier then
    begin
      FNames := FNames + [FTokens[FOfIndex].Text];
    end
    else if not FTokens[FOfIndex].IsSymbol('.') then
    begin
      Exit(Fail('/case versteht als Auswahl nur einen Namen wie Art oder Kunde.Art'));
    end;
    FOfIndex := NextCode(FTokens, FOfIndex);
  end;
  Result := (FOfIndex <= High(FTokens)) and (FNames <> nil);
  if not Result then
  begin
    FReason := cCaseUsage;
  end;
end;

function TCaseCommand.EnumValues(AResolver: TNameResolver; AType: TResolvedSymbol): Boolean;
var
  mOwner: TUnitIndex;
  mStep: Integer;
begin
  Result := False;
  for mStep := 1 to 4 do
  begin
    if not AType.Found or not AType.IsType or not OwnerOf(AResolver, FSource, FContext.Index, FFileName, AType,
      mOwner) then
    begin
      Exit;
    end;
    if AType.SymbolKind = TIndexSymbolKind.EnumType then
    begin
      FValues := EnumMembers(mOwner, AType);
      FEnumName := AType.Name;
      Exit(FValues <> nil);
    end;
    if (AType.SymbolKind <> TIndexSymbolKind.TypeAlias) or (AType.TypeName = '') or
      not AResolver.ResolveTypeFrom(mOwner, AType.TypeName, AType) then
    begin
      Exit;
    end;
  end;
end;

function TCaseCommand.ResolveEnum: Boolean;
var
  mResolver: TNameResolver;
  mChain: TResolvedChainType;
begin
  FFileName := '';
  if FContext.Uri <> '' then
  begin
    FFileName := TDocumentUris.ToPath(FContext.Uri);
  end;
  mResolver := TNameResolver.Create(FContext.Index);
  try
    Result := mResolver.ChainType(FSource.Tree, FFileName, FNames, FTokens[FCaseIndex].Offset, mChain) and
      mChain.TypeFound and EnumValues(mResolver, mChain.TypeInfo);
    if not Result then
    begin
      Exit(Fail(Format('Der Typ von %s ist keine bekannte Aufzählung', [string.Join('.', FNames)])));
    end;
    FScoped := ScopedEnum(FContext, FSource, FFileName, mChain.TypeInfo);
  finally
    mResolver.Free;
  end;
end;

function TCaseCommand.FindMissing: Boolean;
var
  mLabel: string;
begin
  // Vorhandene Marken und Einrückung wie bei der Vervollständigung (#449).
  if not TCaseCompletion.BranchSlot(FSource.Text, FTokens, FTokens[FOfIndex].EndPos, FSlot) then
  begin
    Exit(Fail(cCaseUsage));
  end;
  if not TCaseCompletion.Missing(FValues, FSlot.Labels, FMissing) then
  begin
    Exit(Fail(Format('Eine Marke im case ist kein Wert von %s', [FEnumName])));
  end;
  if FMissing = nil then
  begin
    Exit(Fail(Format('Der case behandelt schon alle Werte von %s', [FEnumName])));
  end;
  for mLabel in FSlot.Labels do
  begin
    FScoped := FScoped or (Pos('.', mLabel) > 0);
  end;
  Result := True;
end;

function TCaseCommand.LastBranchToken: Integer;
var
  mIndex, mDepth: Integer;
begin
  Result := FOfIndex;
  mDepth := 0;
  mIndex := NextCode(FTokens, FOfIndex);
  while mIndex <= High(FTokens) do
  begin
    if (mDepth = 0) and (FTokens[mIndex].IsKeyword('end') or (FTokens[mIndex].IsKeyword('else') and
      (FTokens[Result].IsSymbol(';') or (Result = FOfIndex)))) then
    begin
      Break;
    end;
    if OpensBlock(FTokens[mIndex]) then
    begin
      Inc(mDepth);
    end
    else if FTokens[mIndex].IsKeyword('end') or FTokens[mIndex].IsKeyword('until') then
    begin
      Dec(mDepth);
    end;
    Result := mIndex;
    mIndex := NextCode(FTokens, mIndex);
  end;
end;

function TCaseCommand.BranchText(ALastIndex: Integer): string;
var
  mPrefix, mLabel: string;
begin
  mPrefix := '';
  if FScoped then
  begin
    mPrefix := FEnumName + '.';
  end;
  Result := '';
  if (ALastIndex <> FOfIndex) and not FTokens[ALastIndex].IsSymbol(';') then
  begin
    Result := ';';
  end;
  for mLabel in FMissing do
  begin
    Result := Result + FSource.LineBreak + FSlot.BranchIndent + mPrefix + mLabel + ': ;';
  end;
  if not FSlot.HasEnd then
  begin
    Result := Result + FSource.LineBreak + FSlot.CaseIndent + 'end;';
  end;
end;

function TCaseCommand.Run(out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mLastIndex: Integer;
  mInsertAt: TTextPosition;
begin
  AEdits := nil;
  if FContext.Arguments <> '' then
  begin
    FReason := '/case hat keine Argumente';
    Result := False;
  end
  else if FSource.RoutineAt = nil then
  begin
    FReason := '/case gilt nur im Rumpf einer Routine';
    Result := False;
  end
  else
  begin
    Result := FindCase and ResolveEnum and FindMissing;
  end;
  AReason := FReason;
  if not Result then
  begin
    Exit;
  end;
  mLastIndex := LastBranchToken;
  mInsertAt := FTokens[mLastIndex].EndPos;
  AEdits := [TTextEdit.Create(TTextRange.Create(mInsertAt, mInsertAt), BranchText(mLastIndex)),
    FSource.RemoveCommand];
end;

function ExecuteCase(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mCommand: TCaseCommand;
begin
  mCommand := TCaseCommand.Create(AContext);
  try
    Result := mCommand.Run(AEdits, AReason);
  finally
    mCommand.Free;
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
