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
  MaxSqlLine = 100;

/// <summary>Erstes Wort von AArguments als Name (mit Punkten), Rest in ARest.</summary>
function SplitName(const AArguments: string; out AName, ARest: string): Boolean;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(AArguments)) and (AArguments[Index] > ' ') do
  begin
    Inc(Index);
  end;
  AName := Copy(AArguments, 1, Index - 1);
  ARest := Trim(Copy(AArguments, Index, MaxInt));
  Result := (AName <> '') and IsValidIdent(AName, True);
end;

/// <summary>Deklarierter Typ des ersten Namensteils an der Befehlszeile; '' wenn unbekannt.</summary>
function TypeOfName(ASource: TCommandSource; const AName: string): string;
var
  Types: TDeclaredTypes;
  First: string;
begin
  First := AName;
  if Pos('.', First) > 0 then
  begin
    First := Copy(First, 1, Pos('.', First) - 1);
  end;
  Types := TDeclaredTypes.Create(ASource.Tree, ASource.Text);
  try
    Result := Types.DeclaredType(First, TTextPosition.Create(ASource.Line, 0));
  finally
    Types.Free;
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
  Source: TCommandSource;
  Name, Sql, Indent, TypeName, Param, Literal, Single: string;
  Lines: TArray<string>;
begin
  AEdits := nil;
  if not SplitName(AContext.Arguments, Name, Sql) or (Sql = '') then
  begin
    Exit(Fail(cTexts[TDatabaseCommandsText.ExpectedAreQueryAndSQL].Text, AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
    begin
      Exit(Fail(cTexts[TDatabaseCommandsText.SqlOnlyAppliesInThe].Text, AReason));
    end;
    Indent := Source.Indent(Source.Line);
    TypeName := TypeOfName(Source, Name);
    Single := Format('%s%s.SQL.Text := %s;', [Indent, Name, TStringLiterals.Quote(Sql)]);
    if Length(Single) <= MaxSqlLine then
    begin
      Lines := [Single];
    end
    else
    begin
      // Lange Abfragen: eine Zeile je Klausel, ab Delphi 12 als '''-String, sonst mit sLineBreak.
      Literal := TStringLiterals.ToLiteral(string.Join(#13#10, TSqlText.Layout(Sql, 0)), Indent + '  ', True,
        TStringLiterals.UseMultiline(TStringLiteralStyle.Auto, AContext.DelphiVersion),
        TStringLiteralSettings.Default, Source.LineBreak);
      Lines := [Format('%s%s.SQL.Text :=', [Indent, Name]), Literal + ';'];
    end;
    for Param in TSqlText.Params(Sql) do
    begin
      Lines := Lines + [ParamLine(Indent, Name, TypeName, Param)];
    end;
    AEdits := [Source.ReplaceWithLines(Lines)];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /params }

/// <summary>SQL-Text von AName aus der Unit, sonst aus der Formulardatei daneben.</summary>
function SqlOf(const AContext: TSlashContext; ASource: TCommandSource; const AName: string): string;
var
  FileName, FormText, Extension: string;
begin
  Result := TSqlText.FromSource(ASource.Text, AName);
  if (Result <> '') or (AContext.Host = nil) or (AContext.Uri = '') then
  begin
    Exit;
  end;
  FileName := TDocumentUris.ToPath(AContext.Uri);
  for Extension in TArray<string>.Create('.dfm', '.fmx') do
  begin
    if AContext.Host.ReadFile(ChangeFileExt(FileName, Extension), FormText) then
    begin
      Result := TSqlText.FromForm(FormText, AName);
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  end;
end;

function ExecuteParams(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Name, Rest, Sql, RoutineText, Indent, TypeName, Param: string;
  Params, Assigned, Missing, Extra, Lines: TArray<string>;
  Index: Integer;
begin
  AEdits := nil;
  if not SplitName(AContext.Arguments, Name, Rest) or (Rest <> '') then
  begin
    Exit(Fail(cTexts[TDatabaseCommandsText.ExpectedIsAQueryE].Text, AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine = nil then
    begin
      Exit(Fail(cTexts[TDatabaseCommandsText.ParamsOnlyAppliesInThe].Text, AReason));
    end;
    Sql := SqlOf(AContext, Source, Name);
    if Sql = '' then
    begin
      Exit(Fail(cTexts[TDatabaseCommandsText.ThereIsNoSQLText].Fmt([Name]), AReason));
    end;
    Params := TSqlText.Params(Sql);
    RoutineText := '';
    for Index := Routine.StartPos.Line to Routine.EndPos.Line do
    begin
      if Index <> Source.Line then
      begin
        RoutineText := RoutineText + Source.Lines[Index] + #10;
      end;
    end;
    Assigned := TSqlText.AssignedParams(RoutineText, Name);
    Missing := TSqlText.Missing(Params, Assigned);
    Extra := TSqlText.Missing(Assigned, Params);
    if Extra <> nil then
    begin
      Exit(Fail(cTexts[TDatabaseCommandsText.NotInTheSQLOf].Fmt([Name, string.Join(', ', Extra)]), AReason));
    end;
    if Missing = nil then
    begin
      Exit(Fail(cTexts[TDatabaseCommandsText.AllParametersOfAreSet].Fmt([Name]), AReason));
    end;
    Indent := Source.Indent(Source.Line);
    TypeName := TypeOfName(Source, Name);
    Lines := nil;
    for Param in Missing do
    begin
      Lines := Lines + [ParamLine(Indent, Name, TypeName, Param)];
    end;
    AEdits := [Source.ReplaceWithLines(Lines)];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /loop }

function ExecuteLoop(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Name, Rest: string;
begin
  AEdits := nil;
  if not SplitName(AContext.Arguments, Name, Rest) or (Rest <> '') then
  begin
    Exit(Fail(cTexts[TDatabaseCommandsText.ExpectedIsADatasetE].Text, AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    // Next steht fest am Ende der Schleife: keine Endlosschleife durch ein vergessenes Next.
    Result := Wrap(Source, 'loop', TWrapFrame.Create([Name + '.DisableControls;', 'try', '  ' + Name + '.First;',
      '  while not ' + Name + '.Eof do', '  begin'], ['    ' + Name + '.Next;', '  end;', 'finally',
      '  ' + Name + '.EnableControls;', 'end;'], '    '), AEdits, AReason);
  finally
    Source.Free;
  end;
end;

{ /transaction }

function ExecuteTransaction(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Name, Rest, TypeName, Start, Commit, Rollback, Tx: string;
begin
  AEdits := nil;
  if not SplitName(AContext.Arguments, Name, Rest) or (Rest <> '') then
  begin
    Exit(Fail(cTexts[TDatabaseCommandsText.ExpectedIsAConnectionE].Text, AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    TypeName := TypeOfName(Source, Name);
    Tx := '';
    if IsAdo(TypeName) then
    begin
      Start := Name + '.BeginTrans;';
      Commit := Name + '.CommitTrans;';
      Rollback := Name + '.RollbackTrans;';
    end
    else if SameText(TypeName, 'TSQLConnection') then
    begin
      Tx := 'Transaktion';
      Start := Tx + ' := ' + Name + '.BeginTransaction;';
      Commit := Name + '.CommitFreeAndNil(' + Tx + ');';
      Rollback := Name + '.RollbackFreeAndNil(' + Tx + ');';
    end
    else if SameText(TypeName, 'TIBDatabase') then
    begin
      Start := Name + '.DefaultTransaction.StartTransaction;';
      Commit := Name + '.DefaultTransaction.Commit;';
      Rollback := Name + '.DefaultTransaction.Rollback;';
    end
    else
    begin
      Start := Name + '.StartTransaction;';
      Commit := Name + '.Commit;';
      Rollback := Name + '.Rollback;';
    end;
    Result := Wrap(Source, 'transaction', TWrapFrame.Create([Start, 'try'], ['  ' + Commit, 'except',
      '  ' + Rollback, '  raise;', 'end;'], '  '), AEdits, AReason);
    if Result and (Tx <> '') then
    begin
      AEdits := AEdits + [AddLocal(Source, Routine, TSyntaxKind.VarSection, 'var', Tx + ': TDBXTransaction;')];
      AddUses(Source, AContext, Source.Line, ['Data.DBXCommon'], AEdits);
    end;
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
