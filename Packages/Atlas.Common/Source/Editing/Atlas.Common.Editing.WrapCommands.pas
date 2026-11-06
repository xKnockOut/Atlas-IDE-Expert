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
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TWrapCommandsText = (TryOnlyAppliesInThe, NoLocalObjectIsCreated, ExpectedIsIfdefSYMBOL, ExpectedIsRegionName,
    CaseOnlyUnderstandsAName, TheTypeOfIsNot, ALabelInTheCase, TheCaseAlreadyHandlesAll, CaseHasNoArguments,
    CaseOnlyAppliesInThe, TryFinallyFreeAroundThe, GuardTheFollowingStatementsWith, AddTheMissingValuesOf,
    FollowingStatementsViaTThreadQueue, FollowingStatementsViaTThreadSynchronize, LockTheFollowingStatements,
    FollowingStatementsInIFDEF, FollowingStatementsInREGION, RegionLoad, CaseExpectsACaseStatement);

const
  cTexts: array[TWrapCommandsText] of TAtlasText = (
    (De: '/try gilt nur im Rumpf einer Routine'; En: '/try only applies in the body of a routine'),
    (De: 'Vor /try wird kein lokales Objekt erzeugt'; En: 'No local object is created before /try'),
    (De: 'Erwartet wird /ifdef SYMBOL'; En: 'Expected is /ifdef SYMBOL'),
    (De: 'Erwartet wird /region Name'; En: 'Expected is /region Name'),
    (De: '/case versteht als Auswahl nur einen Namen wie Art oder Kunde.Art';
     En: '/case only understands a name like Kind or Customer.Kind as selector'),
    (De: 'Der Typ von %s ist keine bekannte Aufzählung'; En: 'The type of %s is not a known enumeration'),
    (De: 'Eine Marke im case ist kein Wert von %s'; En: 'A label in the case is not a value of %s'),
    (De: 'Der case behandelt schon alle Werte von %s'; En: 'The case already handles all values of %s'),
    (De: '/case hat keine Argumente'; En: '/case has no arguments'),
    (De: '/case gilt nur im Rumpf einer Routine'; En: '/case only applies in the body of a routine'),
    (De: 'try … finally Free um die folgenden Anweisungen'; En: 'try … finally Free around the following statements'),
    (De: 'Folgende Anweisungen mit Protokoll und raise absichern';
     En: 'Guard the following statements with logging and raise'),
    (De: 'Fehlende Werte der Aufzählung im case darunter ergänzen';
     En: 'Add the missing values of the enumeration to the case below'),
    (De: 'Folgende Anweisungen per TThread.Queue im Hauptthread';
     En: 'Following statements via TThread.Queue in the main thread'),
    (De: 'Folgende Anweisungen per TThread.Synchronize im Hauptthread';
     En: 'Following statements via TThread.Synchronize in the main thread'),
    (De: 'Folgende Anweisungen sperren'; En: 'Lock the following statements'),
    (De: 'Folgende Anweisungen in {$IFDEF}'; En: 'Following statements in {$IFDEF}'),
    (De: 'Folgende Anweisungen in {$REGION}'; En: 'Following statements in {$REGION}'),
    (De: '/region Laden'; En: '/region Load'),
    (De: '/case erwartet darunter eine case-Anweisung über einer Aufzählung';
     En: '/case expects a case statement over an enumeration below'));

{$SCOPEDENUMS OFF}

{ /try }

/// <summary>Variable aus "X := T….Create(…)" bzw. "var X := …Create"; '' sonst.</summary>
function CreatedVariable(const ALine: string): string;
var
  mLine: string;
  mAssign: Integer;
begin
  Result := '';
  mLine := Trim(ALine);
  if StartsText('var ', mLine) then
  begin
    mLine := Trim(Copy(mLine, 5, MaxInt));
  end;
  mAssign := Pos(':=', mLine);
  if (mAssign = 0) or (Pos('.create', LowerCase(Copy(mLine, mAssign, MaxInt))) = 0) then
  begin
    Exit;
  end;
  Result := Trim(Copy(mLine, 1, mAssign - 1));
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
  mSymbol: TIndexSymbol;
begin
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function ExecuteTry(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine: TSyntaxNode;
  mIndex: Integer;
  mVariable: string;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if mRoutine = nil then
    begin
      Exit(Fail(cTexts[TWrapCommandsText.TryOnlyAppliesInThe].Text, AReason));
    end;
    mVariable := '';
    for mIndex := mSource.Line - 1 downto mRoutine.StartPos.Line do
    begin
      mVariable := CreatedVariable(mSource.Lines[mIndex]);
      if mVariable <> '' then
      begin
        Break;
      end;
    end;
    if (mVariable = '') or IsField(mSource, mVariable) then
    begin
      Exit(Fail(cTexts[TWrapCommandsText.NoLocalObjectIsCreated].Text, AReason));
    end;
    // Result gehört dem Aufrufer: nur bei einer Ausnahme freigeben.
    if SameText(mVariable, 'Result') then
    begin
      Result := Wrap(mSource, 'try', TWrapFrame.Create(['try'], ['except', '  Result.Free;', '  raise;', 'end;'], '  '),
        AEdits, AReason);
    end
    else
    begin
      Result := Wrap(mSource, 'try', TWrapFrame.Create(['try'], ['finally', '  ' + mVariable + '.Free;', 'end;'], '  '),
        AEdits, AReason);
    end;
  finally
    mSource.Free;
  end;
end;

{ /lock }

function ExecuteLock(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClassSymbol, mSymbol: TIndexSymbol;
  mSection: string;
begin
  mSource := TCommandSource.Create(AContext);
  try
    mSection := '';
    if mSource.ClassAt(mClassSymbol) then
    begin
      for mSymbol in mSource.UnitIndex.Symbols do
      begin
        if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, mClassSymbol.Name) and
          (SameText(mSymbol.TypeName, 'TCriticalSection') or SameText(mSymbol.TypeName, 'TSyncObjs.TCriticalSection')) then
        begin
          mSection := mSymbol.Name;
          Break;
        end;
      end;
    end;
    if mSection <> '' then
    begin
      Result := Wrap(mSource, 'lock', TWrapFrame.Create([mSection + '.Enter;', 'try'], ['finally',
        '  ' + mSection + '.Leave;', 'end;'], '  '), AEdits, AReason);
    end
    else
    begin
      Result := Wrap(mSource, 'lock', TWrapFrame.Create(['TMonitor.Enter(Self);', 'try'], ['finally',
        '  TMonitor.Exit(Self);', 'end;'], '  '), AEdits, AReason);
    end;
  finally
    mSource.Free;
  end;
end;

{ /sync, /ifdef, /region }

function ExecuteSync(const AContext: TSlashContext; const AMethod: string; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mSource: TCommandSource;
begin
  mSource := TCommandSource.Create(AContext);
  try
    Result := Wrap(mSource, AContext.Name, TWrapFrame.Create(['TThread.' + AMethod + '(nil,', '  procedure', '  begin'],
      ['  end);'], '    '), AEdits, AReason);
  finally
    mSource.Free;
  end;
end;

function ExecuteIfdef(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
begin
  AEdits := nil;
  if not IsValidIdent(AContext.Arguments) then
  begin
    Exit(Fail(cTexts[TWrapCommandsText.ExpectedIsIfdefSYMBOL].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    Result := Wrap(mSource, 'ifdef', TWrapFrame.Create(['{$IFDEF ' + AContext.Arguments + '}'], ['{$ENDIF}'], ''),
      AEdits, AReason);
  finally
    mSource.Free;
  end;
end;

function ExecuteRegion(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
begin
  AEdits := nil;
  if AContext.Arguments = '' then
  begin
    Exit(Fail(cTexts[TWrapCommandsText.ExpectedIsRegionName].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    Result := Wrap(mSource, 'region', TWrapFrame.Create(['{$REGION ''' + StringReplace(AContext.Arguments, '''', '''''',
      [rfReplaceAll]) + '''}'], ['{$ENDREGION}'], ''), AEdits, AReason);
  finally
    mSource.Free;
  end;
end;

{ /except }

function ExecuteExcept(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
begin
  mSource := TCommandSource.Create(AContext);
  try
    // Nie ein leeres except: protokollieren und weiterwerfen.
    Result := Wrap(mSource, 'except', TWrapFrame.Create(['try'], ['except', '  on E: Exception do', '  begin',
      '    ' + LogStatement(AContext, 'E.ClassName + '': '' + E.Message'), '    raise;', '  end;', 'end;'], '  '),
      AEdits, AReason);
  finally
    mSource.Free;
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
  mText: string;
  mToken: TPascalToken;
  mDirective: string;
begin
  Result := False;
  if SameText(AType.FileName, AFileName) then
  begin
    mText := ASource.Text;
  end
  else if (AContext.Host = nil) or not AContext.Host.ReadFile(AType.FileName, mText) then
  begin
    Exit;
  end;
  for mToken in TPascalLexer.Tokenize(mText) do
  begin
    if (mToken.StartPos.Line > AType.Range.StartPos.Line) then
    begin
      Break;
    end;
    if mToken.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    mDirective := UpperCase(StringReplace(mToken.Text, ' ', '', [rfReplaceAll]));
    if StartsStr('{$SCOPEDENUMSON', mDirective) then
    begin
      Result := True;
    end
    else if StartsStr('{$SCOPEDENUMSOFF', mDirective) then
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
    Exit(Fail(cTexts[TWrapCommandsText.CaseExpectsACaseStatement].Text));
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
      Exit(Fail(cTexts[TWrapCommandsText.CaseOnlyUnderstandsAName].Text));
    end;
    FOfIndex := NextCode(FTokens, FOfIndex);
  end;
  Result := (FOfIndex <= High(FTokens)) and (FNames <> nil);
  if not Result then
  begin
    FReason := cTexts[TWrapCommandsText.CaseExpectsACaseStatement].Text;
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
      Exit(Fail(cTexts[TWrapCommandsText.TheTypeOfIsNot].Fmt([string.Join('.', FNames)])));
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
    Exit(Fail(cTexts[TWrapCommandsText.CaseExpectsACaseStatement].Text));
  end;
  if not TCaseCompletion.Missing(FValues, FSlot.Labels, FMissing) then
  begin
    Exit(Fail(cTexts[TWrapCommandsText.ALabelInTheCase].Fmt([FEnumName])));
  end;
  if FMissing = nil then
  begin
    Exit(Fail(cTexts[TWrapCommandsText.TheCaseAlreadyHandlesAll].Fmt([FEnumName])));
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
    FReason := cTexts[TWrapCommandsText.CaseHasNoArguments].Text;
    Result := False;
  end
  else if FSource.RoutineAt = nil then
  begin
    FReason := cTexts[TWrapCommandsText.CaseOnlyAppliesInThe].Text;
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
  ARegister(Command('try', cTexts[TWrapCommandsText.TryFinallyFreeAroundThe].Text, '/try', ExecuteTry));
  ARegister(Command('lock', cTexts[TWrapCommandsText.LockTheFollowingStatements].Text, '/lock', ExecuteLock));
  ARegister(Command('sync', cTexts[TWrapCommandsText.FollowingStatementsViaTThreadQueue].Text, '/sync',
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteSync(AContext, 'Queue', AEdits, AReason);
    end));
  ARegister(Command('sync!', cTexts[TWrapCommandsText.FollowingStatementsViaTThreadSynchronize].Text, '/sync!',
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteSync(AContext, 'Synchronize', AEdits, AReason);
    end));
  ARegister(Command('ifdef', cTexts[TWrapCommandsText.FollowingStatementsInIFDEF].Text, '/ifdef DEBUG', ExecuteIfdef));
  ARegister(Command('except', cTexts[TWrapCommandsText.GuardTheFollowingStatementsWith].Text, '/except',
    ExecuteExcept));
  ARegister(Command('region', cTexts[TWrapCommandsText.FollowingStatementsInREGION].Text,
    cTexts[TWrapCommandsText.RegionLoad].Text, ExecuteRegion));
  ARegister(Command('case', cTexts[TWrapCommandsText.AddTheMissingValuesOf].Text, '/case', ExecuteCase));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.WrapCommands', cTexts);

end.
