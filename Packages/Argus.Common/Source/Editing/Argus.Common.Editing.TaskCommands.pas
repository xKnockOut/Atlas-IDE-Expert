unit Argus.Common.Editing.TaskCommands;

// Schnellbefehle für Tasks und parallele Verarbeitung (#322) im Rahmen aus #293:
//   /task              TTask.Run(procedure begin … end) um die folgenden Anweisungen;
//                      VCL-Zugriffe am Ende kommen in TThread.Queue
//   /parallel          for-Schleife darunter als TParallel.For; abgelehnt bei Break/Exit,
//                      Schreiben äußerer Variablen und VCL-Zugriffen
//   /future Name: Typ  TTask.Future<Typ> um die folgenden Anweisungen
//   /atomic            Inc/Dec bzw. F := F ± N auf einem Feld als TInterlocked
// VCL-Zugriffe erkennt der Befehl an Application, Screen, den Dialogen und an
// Variablen bzw. Feldern mit bekannten VCL-Typen (wie die Regel thread-vcl-access, #148).

interface

uses
  Argus.Common.Editing.SlashCommands;

/// <summary>Trägt /task, /parallel, /future und /atomic in ARegistry ein.</summary>
procedure RegisterTaskCommands(ARegistry: TSlashCommandRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.DeclaredTypes,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.Lexer,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.LanguageFeatures,
  Argus.Common.Index.Contract,
  Argus.Common.Editing.CommandSource;

type
  TTokens = TArray<TPascalToken>;

const
  VclNames: array[0..6] of string = ('Application', 'Screen', 'Mouse', 'ShowMessage', 'ShowMessageFmt',
    'MessageDlg', 'ShowMessagePos');
  VclTypes: array[0..31] of string = ('TLabel', 'TEdit', 'TMemo', 'TButton', 'TBitBtn', 'TSpeedButton', 'TListBox',
    'TComboBox', 'TCheckBox', 'TRadioButton', 'TPanel', 'TProgressBar', 'TStatusBar', 'TForm', 'TFrame', 'TImage',
    'TListView', 'TTreeView', 'TStringGrid', 'TDrawGrid', 'TDBGrid', 'TRichEdit', 'TPageControl', 'TTabSheet',
    'TToolBar', 'TTrackBar', 'TScrollBox', 'TGroupBox', 'TMaskEdit', 'TCanvas', 'TControl', 'TWinControl');

/// <summary>Fasst die Zeile AText VCL-Objekte an? Bezeichner werden an APosition aufgelöst.</summary>
function TouchesVcl(ASource: TCommandSource; ATypes: TDeclaredTypes; const AText: string;
  const APosition: TTextPosition): Boolean;
var
  Token: TPascalToken;
  TypeName: string;
  Symbol: TIndexSymbol;
begin
  for Token in TPascalLexer.Tokenize(AText) do
  begin
    if Token.Kind <> TPascalTokenKind.Identifier then
      Continue;
    if MatchText(Token.Text, VclNames) then
      Exit(True);
    TypeName := ATypes.DeclaredType(Token.Text, APosition);
    if TypeName = '' then
      for Symbol in ASource.UnitIndex.Symbols do
        if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Name, Token.Text) then
          TypeName := Symbol.TypeName;
    if MatchText(TypeName, VclTypes) or (StartsText('TCustom', TypeName) and EndsText('Control', TypeName)) then
      Exit(True);
  end;
  Result := False;
end;

/// <summary>Zeilen der Anweisungen nach dem Befehl bis vor das Blockende; False ohne.</summary>
function FollowingLines(ASource: TCommandSource; const AName: string; out AFirst, ALast: Integer;
  out AReason: string): Boolean;
var
  Stop: Integer;
begin
  if ASource.RoutineAt = nil then
    Exit(Fail('/' + AName + ' gilt nur im Rumpf einer Routine', AReason));
  Stop := BlockEnd(ASource, ASource.Line);
  if (Stop < 0) or (Stop <= ASource.Line + 1) then
    Exit(Fail('Nach /' + AName + ' stehen keine Anweisungen im Block', AReason));
  AFirst := ASource.Line + 1;
  ALast := Stop - 1;
  Result := True;
end;

{ /task }

function ExecuteTask(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Types: TDeclaredTypes;
  First, Last, Split, Line: Integer;
  Indent, LB, Text: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not FollowingLines(Source, 'task', First, Last, AReason) then
      Exit(False);
    // VCL-Zeilen am Ende kommen in TThread.Queue.
    Types := TDeclaredTypes.Create(Source.Tree, Source.Text);
    try
      Split := Last + 1;
      while (Split > First) and ((Trim(Source.Lines[Split - 1]) = '') or
        TouchesVcl(Source, Types, Source.Lines[Split - 1], TTextPosition.Create(Split - 1, 0))) do
        Dec(Split);
      while (Split <= Last) and (Trim(Source.Lines[Split]) = '') do
        Inc(Split);
    finally
      Types.Free;
    end;
    Indent := Source.Indent(Source.Line);
    LB := Source.LineBreak;
    Text := Indent + 'TTask.Run(' + LB + Indent + '  procedure' + LB + Indent + '  begin' + LB;
    for Line := First to Split - 1 do
      if Trim(Source.Lines[Line]) = '' then
        Text := Text + LB
      else
        Text := Text + '    ' + Source.Lines[Line] + LB;
    if Split <= Last then
    begin
      Text := Text + Indent + '    TThread.Queue(nil,' + LB + Indent + '      procedure' + LB + Indent +
        '      begin' + LB;
      for Line := Split to Last do
        if Trim(Source.Lines[Line]) = '' then
          Text := Text + LB
        else
          Text := Text + '        ' + Source.Lines[Line] + LB;
      Text := Text + Indent + '      end);' + LB;
    end;
    Text := Text + Indent + '  end);' + LB;
    AEdits := [TRuleEdit.Create(TTextRange.Create(Source.Line, 0, Last + 1, 0), Text)];
    AddUses(Source, AContext, Source.Line, ['System.Threading', 'System.Classes'], AEdits);
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /parallel }

function FindFor(ANode: TSyntaxNode; ALine: Integer): TSyntaxNode;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.ForStatement) and (ANode.StartPos.Line = ALine) then
    Exit(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
    if (ANode[Index].StartPos.Line <= ALine) and (ANode[Index].EndPos.Line >= ALine) then
    begin
      Result := FindFor(ANode[Index], ALine);
      if Result <> nil then
        Exit;
    end;
  Result := nil;
end;

/// <summary>Quelltext von ANode aus ALines.</summary>
function NodeText(const ALines: TArray<string>; ANode: TSyntaxNode): string;
var
  Line: Integer;
begin
  if ANode.StartPos.Line = ANode.EndPos.Line then
    Exit(Copy(ALines[ANode.StartPos.Line], ANode.StartPos.Character + 1,
      ANode.EndPos.Character - ANode.StartPos.Character));
  Result := Copy(ALines[ANode.StartPos.Line], ANode.StartPos.Character + 1, MaxInt);
  for Line := ANode.StartPos.Line + 1 to ANode.EndPos.Line - 1 do
    Result := Result + ' ' + Trim(ALines[Line]);
  Result := Result + ' ' + Trim(Copy(ALines[ANode.EndPos.Line], 1, ANode.EndPos.Character));
end;

/// <summary>Grund, warum der Rumpf nicht parallel laufen darf; '' wenn er darf.</summary>
function ParallelProblem(ASource: TCommandSource; ATypes: TDeclaredTypes; const ALoopVar: string;
  AFirst, ALast: Integer): string;
var
  Tokens: TTokens;
  Text: string;
  Line, Index, Prev: Integer;
  Locals: TArray<string>;
begin
  Text := '';
  for Line := AFirst to ALast do
  begin
    if TouchesVcl(ASource, ATypes, ASource.Lines[Line], TTextPosition.Create(Line, 0)) then
      Exit(Format('Zeile %d fasst VCL-Objekte an', [Line + 1]));
    Text := Text + ASource.Lines[Line] + #10;
  end;
  Tokens := TPascalLexer.Tokenize(Text);
  Locals := [ALoopVar];
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Kind = TPascalTokenKind.Comment then
      Continue;
    if MatchText(Tokens[Index].Text, ['Break', 'Exit']) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
      Exit(Tokens[Index].Text + ' ist in TParallel.For nicht möglich');
    // Inline-Variablen im Rumpf sind lokal.
    if Tokens[Index].IsKeyword('var') and (Index < High(Tokens)) then
      Locals := Locals + [Tokens[Index + 1].Text];
    if Tokens[Index].IsSymbol(':=') and (Index > 0) then
    begin
      Prev := Index - 1;
      // Ziel ist ein einfacher Name: davor beginnt die Anweisung.
      if (Tokens[Prev].Kind = TPascalTokenKind.Identifier) and ((Prev = 0) or Tokens[Prev - 1].IsSymbol(';') or
        (Tokens[Prev - 1].Kind = TPascalTokenKind.Keyword)) and (IndexText(Tokens[Prev].Text, Locals) < 0) and
        not SameText(Tokens[Prev].Text, 'Result') then
        Exit(Format('Der Rumpf schreibt die äußere Variable %s; TInterlocked verwenden', [Tokens[Prev].Text]));
    end;
    if MatchText(Tokens[Index].Text, ['Inc', 'Dec']) and (Index + 2 <= High(Tokens)) and
      Tokens[Index + 1].IsSymbol('(') and (Tokens[Index + 2].Kind = TPascalTokenKind.Identifier) and
      ((Index + 3 > High(Tokens)) or not Tokens[Index + 3].IsSymbol('.')) and
      (IndexText(Tokens[Index + 2].Text, Locals) < 0) then
      Exit(Format('Der Rumpf schreibt die äußere Variable %s; TInterlocked verwenden', [Tokens[Index + 2].Text]));
  end;
  Result := '';
end;

function ExecuteParallel(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Types: TDeclaredTypes;
  ForNode, Body: TSyntaxNode;
  Expressions: TArray<TSyntaxNode>;
  Index, First, Last, Line, Common, Spaces: Integer;
  Indent, LB, Text, Problem, Header: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
      Exit(Fail('/parallel gilt nur im Rumpf einer Routine', AReason));
    ForNode := FindFor(Source.Tree.Root, Source.Line + 1);
    if (ForNode = nil) or (ForNode.ChildCount < 3) then
      Exit(Fail('Unter /parallel steht keine Schleife for I := A to B do', AReason));
    Header := Source.Lines[ForNode.StartPos.Line];
    if ContainsText(Header, ' downto ') then
      Exit(Fail('TParallel.For zählt nur aufwärts (kein downto)', AReason));
    Expressions := nil;
    for Index := 0 to ForNode.ChildCount - 2 do
      if ForNode[Index].Kind <> TSyntaxKind.TypeReference then
        Expressions := Expressions + [ForNode[Index]];
    if Length(Expressions) <> 2 then
      Exit(Fail('Unter /parallel steht keine Schleife for I := A to B do', AReason));
    Body := ForNode[ForNode.ChildCount - 1];
    if Body.Kind = TSyntaxKind.Block then
    begin
      First := Body.StartPos.Line + 1;
      Last := Body.EndPos.Line - 1;
    end
    else
    begin
      First := Body.StartPos.Line;
      Last := Body.EndPos.Line;
    end;
    if (First > Last) or (First = ForNode.StartPos.Line) then
      Exit(Fail('Rumpf der Schleife bitte auf eigene Zeilen setzen', AReason));
    Types := TDeclaredTypes.Create(Source.Tree, Source.Text);
    try
      Problem := ParallelProblem(Source, Types, ForNode.Name, First, Last);
    finally
      Types.Free;
    end;
    if Problem <> '' then
      Exit(Fail(Problem, AReason));
    // Rumpf neu einrücken: gemeinsame Einrückung weg, dann unter "begin" der anonymen Methode.
    Common := MaxInt;
    for Line := First to Last do
      if Trim(Source.Lines[Line]) <> '' then
      begin
        Spaces := Length(Source.Lines[Line]) - Length(TrimLeft(Source.Lines[Line]));
        if Spaces < Common then
          Common := Spaces;
      end;
    Indent := Source.Indent(ForNode.StartPos.Line);
    LB := Source.LineBreak;
    Text := Indent + Format('TParallel.For(%s, %s,', [NodeText(Source.Lines, Expressions[0]),
      NodeText(Source.Lines, Expressions[1])]) + LB + Indent + Format('  procedure(%s: Integer)',
      [ForNode.Name]) + LB + Indent + '  begin' + LB;
    for Line := First to Last do
      if Trim(Source.Lines[Line]) = '' then
        Text := Text + LB
      else
        Text := Text + Indent + '    ' + Copy(Source.Lines[Line], Common + 1, MaxInt) + LB;
    Text := Text + Indent + '  end);' + LB;
    AEdits := [TRuleEdit.Create(TTextRange.Create(Source.Line, 0, ForNode.EndPos.Line + 1, 0), Text)];
    AddUses(Source, AContext, Source.Line, ['System.Threading'], AEdits);
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /future }

function ExecuteFuture(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Name, TypeName, Head: string;
  Inline: Boolean;
begin
  AEdits := nil;
  if not SplitDeclaration(AContext.Arguments, ':', Name, TypeName) then
    Exit(Fail('Erwartet wird /future Name: Typ', AReason));
  Source := TCommandSource.Create(AContext);
  try
    Inline := TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, AContext.DelphiVersion);
    if Inline then
      Head := Format('var %s := TTask.Future<%s>(', [Name, TypeName])
    else
      Head := Format('%s := TTask.Future<%s>(', [Name, TypeName]);
    Result := Wrap(Source, 'future', [Head, Format('  function: %s', [TypeName]), '  begin'], ['  end);'], '    ',
      AEdits, AReason);
    if not Result then
      Exit;
    // Ohne Inline-Variablen (vor Delphi 10.3) in den var-Abschnitt.
    if not Inline then
      AEdits := AEdits + [AddLocal(Source, Source.RoutineAt, TSyntaxKind.VarSection, 'var',
        Format('%s: IFuture<%s>;', [Name, TypeName]))];
    AddUses(Source, AContext, Source.Line, ['System.Threading'], AEdits);
  finally
    Source.Free;
  end;
end;

{ /atomic }

function IsField(ASource: TCommandSource; const AName: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in ASource.UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Name, AName) then
      Exit(True);
  Result := False;
end;

function ExecuteAtomic(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Line, Indent, Statement, Target, Amount, Call, Inner: string;
  Comma, Assign: Integer;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
      Exit(Fail('/atomic gilt nur im Rumpf einer Routine', AReason));
    if Source.Line + 1 > High(Source.Lines) then
      Exit(Fail('Unter /atomic steht keine Anweisung', AReason));
    Line := Source.Lines[Source.Line + 1];
    Indent := Copy(Line, 1, Length(Line) - Length(TrimLeft(Line)));
    Statement := Trim(Line);
    if not EndsStr(';', Statement) then
      Exit(Fail('Unter /atomic steht keine einzeilige Anweisung', AReason));
    Statement := Trim(Copy(Statement, 1, Length(Statement) - 1));
    Call := '';
    if (StartsText('Inc(', Statement) or StartsText('Dec(', Statement)) and EndsStr(')', Statement) then
    begin
      Inner := Copy(Statement, 5, Length(Statement) - 5);
      Comma := Pos(',', Inner);
      if Comma > 0 then
      begin
        Target := Trim(Copy(Inner, 1, Comma - 1));
        Amount := Trim(Copy(Inner, Comma + 1, MaxInt));
        if StartsText('Dec', Statement) then
          Amount := '-(' + Amount + ')';
        Call := Format('TInterlocked.Add(%s, %s);', [Target, Amount]);
      end
      else
      begin
        Target := Trim(Inner);
        Call := Format('TInterlocked.%s(%s);', [IfThen(StartsText('Inc', Statement), 'Increment', 'Decrement'),
          Target]);
      end;
    end
    else
    begin
      Assign := Pos(':=', Statement);
      if Assign > 0 then
      begin
        Target := Trim(Copy(Statement, 1, Assign - 1));
        Inner := Trim(Copy(Statement, Assign + 2, MaxInt));
        if StartsText(Target + ' + ', Inner) then
          Call := Format('TInterlocked.Add(%s, %s);', [Target, Trim(Copy(Inner, Length(Target) + 4, MaxInt))])
        else if StartsText(Target + ' - ', Inner) then
          Call := Format('TInterlocked.Add(%s, -(%s));', [Target, Trim(Copy(Inner, Length(Target) + 4, MaxInt))]);
      end;
    end;
    if Call = '' then
      Exit(Fail('Erwartet wird darunter Inc(F), Dec(F) oder F := F + N', AReason));
    if not IsField(Source, Target) then
      Exit(Fail(Format('%s ist kein Feld; /atomic gilt für Felder', [Target]), AReason));
    AEdits := [TRuleEdit.Create(TTextRange.Create(Source.Line, 0, Source.Line + 2, 0), Indent + Call +
      Source.LineBreak)];
    AddUses(Source, AContext, Source.Line, ['System.SyncObjs'], AEdits);
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

procedure RegisterTaskCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('task', 'Folgende Anweisungen in TTask.Run', '/task', ExecuteTask));
  ARegistry.Register(Command('parallel', 'for-Schleife darunter als TParallel.For', '/parallel', ExecuteParallel));
  ARegistry.Register(Command('future', 'Folgende Anweisungen als TTask.Future', '/future Summe: Integer',
    ExecuteFuture));
  ARegistry.Register(Command('atomic', 'Inc/Dec auf einem Feld als TInterlocked', '/atomic', ExecuteAtomic));
end;

end.
