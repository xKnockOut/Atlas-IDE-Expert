unit Atlas.Common.Editing.DatabaseCommands;

// Schnellbefehle für Datenbankcode (#302) im Rahmen aus #293:
//   /sql Q select … where Nr = :Nr   SQL.Text und je Parameter eine ParamByName-Zeile
//   /params Q                        fehlende ParamByName-Zeilen ergänzen, überzählige melden
//   /loop DS                         Datensatzschleife mit DisableControls und Next
//   /transaction Con                 Transaktion mit Commit und Rollback
// Der Typ der Variable wählt die Variante: ADO (Parameters, BeginTrans),
// dbExpress (TDBXTransaction), IBX (DefaultTransaction), sonst der Weg über
// TDataSet bzw. FireDAC. SQL steht immer als Text, Werte nur über Parameter.

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Trägt /sql, /params, /loop und /transaction über ARegister ein.</summary>
procedure RegisterDatabaseCommands(const ARegister: TSlashRegister);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Editing.SqlText,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDatabaseCommandsText = (ExpectedAreQueryAndSQL, SqlOnlyAppliesInThe, ExpectedIsAQueryE, ParamsOnlyAppliesInThe,
    ThereIsNoSQLText, NotInTheSQLOf, AllParametersOfAreSet, ExpectedIsADatasetE, ExpectedIsAConnectionE,
    SetSQLTextAndParameters, AddMissingParamByNameLines, IterateRecordsDisableControlsFirstNext,
    WrapStatementsInATransaction);

const
  cTexts: array[TDatabaseCommandsText] of TAtlasText = (
    (De: 'Erwartet werden Query und SQL, z. B. /sql Q select * from Kunde where Nr = :Nr';
     En: 'Expected are query and SQL, e.g. /sql Q select * from Customer where No = :No'),
    (De: '/sql gilt nur im Rumpf einer Routine'; En: '/sql only applies in the body of a routine'),
    (De: 'Erwartet wird eine Query, z. B. /params Q'; En: 'Expected is a query, e.g. /params Q'),
    (De: '/params gilt nur im Rumpf einer Routine'; En: '/params only applies in the body of a routine'),
    (De: 'Für %s steht kein SQL-Text in der Unit oder Formulardatei';
     En: 'There is no SQL text for %s in the unit or form file'),
    (De: 'Nicht im SQL von %s: %s'; En: 'Not in the SQL of %s: %s'),
    (De: 'Alle Parameter von %s sind gesetzt'; En: 'All parameters of %s are set'),
    (De: 'Erwartet wird eine Datenmenge, z. B. /loop Q'; En: 'Expected is a dataset, e.g. /loop Q'),
    (De: 'Erwartet wird eine Verbindung, z. B. /transaction Con';
     En: 'Expected is a connection, e.g. /transaction Con'),
    (De: 'SQL-Text und Parameter einer Query setzen'; En: 'Set SQL text and parameters of a query'),
    (De: 'Fehlende ParamByName-Zeilen ergänzen'; En: 'Add missing ParamByName lines'),
    (De: 'Datensätze durchlaufen (DisableControls, First, Next)';
     En: 'Iterate records (DisableControls, First, Next)'),
    (De: 'Anweisungen in eine Transaktion fassen'; En: 'Wrap statements in a transaction'));

{$SCOPEDENUMS OFF}

const
  /// <summary>Ab dieser Länge der Zeile "Q.SQL.Text := '…';" wird der Text verteilt.</summary>
  cMaxSqlLine = 100;

/// <summary>Erstes Wort von AArguments als Name (mit Punkten), Rest in ARest.</summary>
function SplitName(const AArguments: string; out AName, ARest: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := 1;
  while (mIndex <= Length(AArguments)) and (AArguments[mIndex] > ' ') do
  begin
    Inc(mIndex);
  end;
  AName := Copy(AArguments, 1, mIndex - 1);
  ARest := Trim(Copy(AArguments, mIndex, MaxInt));
  Result := (AName <> '') and IsValidIdent(AName, True);
end;

/// <summary>Deklarierter Typ des ersten Namensteils an der Befehlszeile; '' wenn unbekannt.</summary>
function TypeOfName(ASource: TCommandSource; const AName: string): string;
var
  mTypes: TDeclaredTypes;
  mFirst: string;
begin
  mFirst := AName;
  if Pos('.', mFirst) > 0 then
  begin
    mFirst := Copy(mFirst, 1, Pos('.', mFirst) - 1);
  end;
  mTypes := TDeclaredTypes.Create(ASource.Tree, ASource.Text);
  try
    Result := mTypes.DeclaredType(mFirst, TTextPosition.Create(ASource.Line, 0));
  finally
    mTypes.Free;
  end;
  // Bei DM.Q ist der Typ von DM nicht der der Query.
  if Pos('.', AName) > 0 then
  begin
    Result := '';
  end;
end;

function IsAdo(const ATypeName: string): Boolean;
begin
  Result := StartsText('TADO', ATypeName);
end;

/// <summary>Zeile für einen Parameter, je nach Zugriff über Params oder Parameters (ADO).</summary>
function ParamLine(const AIndent, AName, ATypeName, AParam: string): string;
begin
  if IsAdo(ATypeName) then
  begin
    Result := Format('%s%s.Parameters.ParamByName(%s).Value := ;', [AIndent, AName, QuotedStr(AParam)]);
  end
  else
  begin
    Result := Format('%s%s.ParamByName(%s).Value := ;', [AIndent, AName, QuotedStr(AParam)]);
  end;
end;

{ /sql }

function ExecuteSql(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mName, mSql, mIndent, mTypeName, mParam, mLiteral, mSingle: string;
  mLines: TArray<string>;
begin
  AEdits := nil;
  if not SplitName(AContext.Arguments, mName, mSql) or (mSql = '') then
  begin
    Exit(Fail(cTexts[TDatabaseCommandsText.ExpectedAreQueryAndSQL].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if mSource.RoutineAt = nil then
    begin
      Exit(Fail(cTexts[TDatabaseCommandsText.SqlOnlyAppliesInThe].Text, AReason));
    end;
    mIndent := mSource.Indent(mSource.Line);
    mTypeName := TypeOfName(mSource, mName);
    mSingle := Format('%s%s.SQL.Text := %s;', [mIndent, mName, TStringLiterals.Quote(mSql)]);
    if Length(mSingle) <= cMaxSqlLine then
    begin
      mLines := [mSingle];
    end
    else
    begin
      // Lange Abfragen: eine Zeile je Klausel, ab Delphi 12 als '''-String, sonst mit sLineBreak.
      mLiteral := TStringLiterals.ToLiteral(string.Join(#13#10, TSqlText.Layout(mSql, 0)), mIndent + '  ', True,
        TStringLiterals.UseMultiline(TStringLiteralStyle.Auto, AContext.DelphiVersion),
        TStringLiteralSettings.Default, mSource.LineBreak);
      mLines := [Format('%s%s.SQL.Text :=', [mIndent, mName]), mLiteral + ';'];
    end;
    for mParam in TSqlText.Params(mSql) do
    begin
      mLines := mLines + [ParamLine(mIndent, mName, mTypeName, mParam)];
    end;
    AEdits := [mSource.ReplaceWithLines(mLines)];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /params }

/// <summary>SQL-Text von AName aus der Unit, sonst aus der Formulardatei daneben.</summary>
function SqlOf(const AContext: TSlashContext; ASource: TCommandSource; const AName: string): string;
var
  mFileName, mFormText, mExtension: string;
begin
  Result := TSqlText.FromSource(ASource.Text, AName);
  if (Result <> '') or (AContext.Host = nil) or (AContext.Uri = '') then
  begin
    Exit;
  end;
  mFileName := TDocumentUris.ToPath(AContext.Uri);
  for mExtension in TArray<string>.Create('.dfm', '.fmx') do
  begin
    if AContext.Host.ReadFile(ChangeFileExt(mFileName, mExtension), mFormText) then
    begin
      Result := TSqlText.FromForm(mFormText, AName);
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  end;
end;

function ExecuteParams(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine: TSyntaxNode;
  mName, mRest, mSql, mRoutineText, mIndent, mTypeName, mParam: string;
  mParams, mAssigned, mMissing, mExtra, mLines: TArray<string>;
  mIndex: Integer;
begin
  AEdits := nil;
  if not SplitName(AContext.Arguments, mName, mRest) or (mRest <> '') then
  begin
    Exit(Fail(cTexts[TDatabaseCommandsText.ExpectedIsAQueryE].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if mRoutine = nil then
    begin
      Exit(Fail(cTexts[TDatabaseCommandsText.ParamsOnlyAppliesInThe].Text, AReason));
    end;
    mSql := SqlOf(AContext, mSource, mName);
    if mSql = '' then
    begin
      Exit(Fail(cTexts[TDatabaseCommandsText.ThereIsNoSQLText].Fmt([mName]), AReason));
    end;
    mParams := TSqlText.Params(mSql);
    mRoutineText := '';
    for mIndex := mRoutine.StartPos.Line to mRoutine.EndPos.Line do
    begin
      if mIndex <> mSource.Line then
      begin
        mRoutineText := mRoutineText + mSource.Lines[mIndex] + #10;
      end;
    end;
    mAssigned := TSqlText.AssignedParams(mRoutineText, mName);
    mMissing := TSqlText.Missing(mParams, mAssigned);
    mExtra := TSqlText.Missing(mAssigned, mParams);
    if mExtra <> nil then
    begin
      Exit(Fail(cTexts[TDatabaseCommandsText.NotInTheSQLOf].Fmt([mName, string.Join(', ', mExtra)]), AReason));
    end;
    if mMissing = nil then
    begin
      Exit(Fail(cTexts[TDatabaseCommandsText.AllParametersOfAreSet].Fmt([mName]), AReason));
    end;
    mIndent := mSource.Indent(mSource.Line);
    mTypeName := TypeOfName(mSource, mName);
    mLines := nil;
    for mParam in mMissing do
    begin
      mLines := mLines + [ParamLine(mIndent, mName, mTypeName, mParam)];
    end;
    AEdits := [mSource.ReplaceWithLines(mLines)];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /loop }

function ExecuteLoop(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mName, mRest: string;
begin
  AEdits := nil;
  if not SplitName(AContext.Arguments, mName, mRest) or (mRest <> '') then
  begin
    Exit(Fail(cTexts[TDatabaseCommandsText.ExpectedIsADatasetE].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    // Next steht fest am Ende der Schleife: keine Endlosschleife durch ein vergessenes Next.
    Result := Wrap(mSource, 'loop', TWrapFrame.Create([mName + '.DisableControls;', 'try', '  ' + mName + '.First;',
      '  while not ' + mName + '.Eof do', '  begin'], ['    ' + mName + '.Next;', '  end;', 'finally',
      '  ' + mName + '.EnableControls;', 'end;'], '    '), AEdits, AReason);
  finally
    mSource.Free;
  end;
end;

{ /transaction }

function ExecuteTransaction(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine: TSyntaxNode;
  mName, mRest, mTypeName, mStart, mCommit, mRollback, mTx: string;
begin
  AEdits := nil;
  if not SplitName(AContext.Arguments, mName, mRest) or (mRest <> '') then
  begin
    Exit(Fail(cTexts[TDatabaseCommandsText.ExpectedIsAConnectionE].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    mTypeName := TypeOfName(mSource, mName);
    mTx := '';
    if IsAdo(mTypeName) then
    begin
      mStart := mName + '.BeginTrans;';
      mCommit := mName + '.CommitTrans;';
      mRollback := mName + '.RollbackTrans;';
    end
    else if SameText(mTypeName, 'TSQLConnection') then
    begin
      mTx := 'Transaktion';
      mStart := mTx + ' := ' + mName + '.BeginTransaction;';
      mCommit := mName + '.CommitFreeAndNil(' + mTx + ');';
      mRollback := mName + '.RollbackFreeAndNil(' + mTx + ');';
    end
    else if SameText(mTypeName, 'TIBDatabase') then
    begin
      mStart := mName + '.DefaultTransaction.StartTransaction;';
      mCommit := mName + '.DefaultTransaction.Commit;';
      mRollback := mName + '.DefaultTransaction.Rollback;';
    end
    else
    begin
      mStart := mName + '.StartTransaction;';
      mCommit := mName + '.Commit;';
      mRollback := mName + '.Rollback;';
    end;
    Result := Wrap(mSource, 'transaction', TWrapFrame.Create([mStart, 'try'], ['  ' + mCommit, 'except',
      '  ' + mRollback, '  raise;', 'end;'], '  '), AEdits, AReason);
    if Result and (mTx <> '') then
    begin
      AEdits := AEdits + [AddLocal(mSource, mRoutine, TSyntaxKind.VarSection, 'var', mTx + ': TDBXTransaction;')];
      AddUses(mSource, AContext, mSource.Line, ['Data.DBXCommon'], AEdits);
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

procedure RegisterDatabaseCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('sql', cTexts[TDatabaseCommandsText.SetSQLTextAndParameters].Text,
    '/sql Q select * from Kunde where Nr = :Nr', ExecuteSql));
  ARegister(Command('params', cTexts[TDatabaseCommandsText.AddMissingParamByNameLines].Text, '/params Q',
    ExecuteParams));
  ARegister(Command('loop', cTexts[TDatabaseCommandsText.IterateRecordsDisableControlsFirstNext].Text, '/loop Q',
    ExecuteLoop));
  ARegister(Command('transaction', cTexts[TDatabaseCommandsText.WrapStatementsInATransaction].Text, '/transaction Con',
    ExecuteTransaction));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.DatabaseCommands', cTexts);

end.
