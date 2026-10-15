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
  Atlas.Common.Editing.SlashCommands;

/// <summary>Trägt /sql, /params, /loop und /transaction in ARegistry ein.</summary>
procedure RegisterDatabaseCommands(ARegistry: TSlashCommandRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.DeclaredTypes,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Editing.SqlText,
  Atlas.Common.Editing.CommandSource;

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
    Inc(Index);
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
    First := Copy(First, 1, Pos('.', First) - 1);
  Types := TDeclaredTypes.Create(ASource.Tree, ASource.Text);
  try
    Result := Types.DeclaredType(First, TTextPosition.Create(ASource.Line, 0));
  finally
    Types.Free;
  end;
  // Bei DM.Q ist der Typ von DM nicht der der Query.
  if Pos('.', AName) > 0 then
    Result := '';
end;

function IsAdo(const ATypeName: string): Boolean;
begin
  Result := StartsText('TADO', ATypeName);
end;

/// <summary>Zeile für einen Parameter, je nach Zugriff über Params oder Parameters (ADO).</summary>
function ParamLine(const AIndent, AName, ATypeName, AParam: string): string;
begin
  if IsAdo(ATypeName) then
    Result := Format('%s%s.Parameters.ParamByName(%s).Value := ;', [AIndent, AName, QuotedStr(AParam)])
  else
    Result := Format('%s%s.ParamByName(%s).Value := ;', [AIndent, AName, QuotedStr(AParam)]);
end;

{ /sql }

function ExecuteSql(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Name, Sql, Indent, TypeName, Param, Literal, Single: string;
  Lines: TArray<string>;
begin
  AEdits := nil;
  if not SplitName(AContext.Arguments, Name, Sql) or (Sql = '') then
    Exit(Fail('Erwartet werden Query und SQL, z. B. /sql Q select * from Kunde where Nr = :Nr', AReason));
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
      Exit(Fail('/sql gilt nur im Rumpf einer Routine', AReason));
    Indent := Source.Indent(Source.Line);
    TypeName := TypeOfName(Source, Name);
    Single := Format('%s%s.SQL.Text := %s;', [Indent, Name, TStringLiterals.Quote(Sql)]);
    if Length(Single) <= MaxSqlLine then
      Lines := [Single]
    else
    begin
      // Lange Abfragen: eine Zeile je Klausel, ab Delphi 12 als '''-String, sonst mit sLineBreak.
      Literal := TStringLiterals.ToLiteral(string.Join(#13#10, TSqlText.Layout(Sql, 0)), Indent + '  ', True,
        TStringLiterals.UseMultiline(TStringLiteralStyle.Auto, AContext.DelphiVersion),
        TStringLiteralBreak.SLineBreak, 0, Source.LineBreak);
      Lines := [Format('%s%s.SQL.Text :=', [Indent, Name]), Literal + ';'];
    end;
    for Param in TSqlText.Params(Sql) do
      Lines := Lines + [ParamLine(Indent, Name, TypeName, Param)];
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
    Exit;
  FileName := TDocumentUris.ToPath(AContext.Uri);
  for Extension in TArray<string>.Create('.dfm', '.fmx') do
    if AContext.Host.ReadFile(ChangeFileExt(FileName, Extension), FormText) then
    begin
      Result := TSqlText.FromForm(FormText, AName);
      if Result <> '' then
        Exit;
    end;
end;

function ExecuteParams(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Name, Rest, Sql, RoutineText, Indent, TypeName, Param: string;
  Params, Assigned, Missing, Extra, Lines: TArray<string>;
  Index: Integer;
begin
  AEdits := nil;
  if not SplitName(AContext.Arguments, Name, Rest) or (Rest <> '') then
    Exit(Fail('Erwartet wird eine Query, z. B. /params Q', AReason));
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine = nil then
      Exit(Fail('/params gilt nur im Rumpf einer Routine', AReason));
    Sql := SqlOf(AContext, Source, Name);
    if Sql = '' then
      Exit(Fail(Format('Für %s steht kein SQL-Text in der Unit oder Formulardatei', [Name]), AReason));
    Params := TSqlText.Params(Sql);
    RoutineText := '';
    for Index := Routine.StartPos.Line to Routine.EndPos.Line do
      if Index <> Source.Line then
        RoutineText := RoutineText + Source.Lines[Index] + #10;
    Assigned := TSqlText.AssignedParams(RoutineText, Name);
    Missing := TSqlText.Missing(Params, Assigned);
    Extra := TSqlText.Missing(Assigned, Params);
    if Extra <> nil then
      Exit(Fail(Format('Nicht im SQL von %s: %s', [Name, string.Join(', ', Extra)]), AReason));
    if Missing = nil then
      Exit(Fail(Format('Alle Parameter von %s sind gesetzt', [Name]), AReason));
    Indent := Source.Indent(Source.Line);
    TypeName := TypeOfName(Source, Name);
    Lines := nil;
    for Param in Missing do
      Lines := Lines + [ParamLine(Indent, Name, TypeName, Param)];
    AEdits := [Source.ReplaceWithLines(Lines)];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /loop }

function ExecuteLoop(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Name, Rest: string;
begin
  AEdits := nil;
  if not SplitName(AContext.Arguments, Name, Rest) or (Rest <> '') then
    Exit(Fail('Erwartet wird eine Datenmenge, z. B. /loop Q', AReason));
  Source := TCommandSource.Create(AContext);
  try
    // Next steht fest am Ende der Schleife: keine Endlosschleife durch ein vergessenes Next.
    Result := Wrap(Source, 'loop', [Name + '.DisableControls;', 'try', '  ' + Name + '.First;',
      '  while not ' + Name + '.Eof do', '  begin'], ['    ' + Name + '.Next;', '  end;', 'finally',
      '  ' + Name + '.EnableControls;', 'end;'], '    ', AEdits, AReason);
  finally
    Source.Free;
  end;
end;

{ /transaction }

function ExecuteTransaction(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Name, Rest, TypeName, Start, Commit, Rollback, Tx: string;
begin
  AEdits := nil;
  if not SplitName(AContext.Arguments, Name, Rest) or (Rest <> '') then
    Exit(Fail('Erwartet wird eine Verbindung, z. B. /transaction Con', AReason));
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
    Result := Wrap(Source, 'transaction', [Start, 'try'], ['  ' + Commit, 'except', '  ' + Rollback, '  raise;',
      'end;'], '  ', AEdits, AReason);
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

procedure RegisterDatabaseCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('sql', 'SQL-Text und Parameter einer Query setzen',
    '/sql Q select * from Kunde where Nr = :Nr', ExecuteSql));
  ARegistry.Register(Command('params', 'Fehlende ParamByName-Zeilen ergänzen', '/params Q', ExecuteParams));
  ARegistry.Register(Command('loop', 'Datensätze durchlaufen (DisableControls, First, Next)', '/loop Q',
    ExecuteLoop));
  ARegistry.Register(Command('transaction', 'Anweisungen in eine Transaktion fassen', '/transaction Con',
    ExecuteTransaction));
end;

end.
