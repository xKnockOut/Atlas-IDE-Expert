unit Atlas.Common.Editing.CodeActions;

// Code-Aktionen ohne Protokollbezug (#42, #147):
//   - Korrekturen der Regeltreffer: Atlas.Common.Rules.CodeActions (A-11)
//   - "Regel für diese Zeile unterdrücken": eigene Kommentarzeile darüber,
//     bestehende "// lsp-ignore:"-Zeile darüber wird ergänzt
//   - "Regel für diese Datei unterdrücken": "// lsp-ignore-file:" in Zeile 1
//   - "try/finally ergänzen" nach "X := T.Create(...);" mit passendem X.Free;
//     bei "Result := T.Create(...)" stattdessen try/except, das Result nur im
//     Fehlerfall freigibt (das Objekt wird ja zurückgegeben). Die Entscheidung
//     trifft der Syntaxbaum: nur lokale Variablen (auch "var X := …"), keine
//     Felder und kein Self.F; der Aufruf darf über mehrere Zeilen gehen. Der
//     try-Block schließt die folgenden Anweisungen bis zum Blockende ein, bei
//     einer Auswahl bis zu deren Ende; steht dort schon "X.Free;", wandert es
//     ins finally. Einrückung nach dem Formatstil (#43).
//   - uses-Aktionen (#284): fehlende Unit ergänzen, ungenutzte entfernen,
//     ins implementation verschieben (Logik in Editing.UsesActions)
//   - Zuweisungen umkehren (#313, Logik in Editing.AssignmentSwap)
//   - "Als String-Literal" und "Als Klartext kopieren" (#312, Logik in Editing.StringLiterals)

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.AssignmentSwap;

const
  QuickFixKind = 'quickfix';
  RewriteKind = 'refactor.rewrite';
  // Für editor.codeActionsOnSave (#182).
  OrganizeImportsKind = 'source.organizeImports';
  FixAllKind = 'source.fixAll';
  /// <summary>Ungenutzte uses entfernen (#284).</summary>
  RemoveUnusedKind = 'source.removeUnusedImports';
  /// <summary>Client-Befehl, der das erste Argument in die Zwischenablage legt (#312).</summary>
  CopyTextCommand = 'atlas.copyText';
  /// <summary>Kennungen der uses-Aktionen für den Hover des Plugins (#621), in data.tag.</summary>
  UsesRemoveTag = 'uses.remove';
  UsesRemoveAllTag = 'uses.removeAll';
  UsesMoveTag = 'uses.move';
  /// <summary>Fehlende Methodenrümpfe (#42) und fehlende case-Zweige (#50); „Anweisung vervollständigen“ des
  /// Plugins sucht sie (#697).</summary>
  ClassBodiesTag = 'class.bodies';
  CaseCompleteTag = 'case.complete';

type
  /// <summary>Edits in einer anderen Datei als dem Dokument der Aktion, z. B. der Formulardatei (#309).</summary>
  TFileTextEdits = record
    FileName: string;
    Edits: TArray<TTextEdit>;
  end;

  TCodeAction = record
    Title: string;
    Kind: string;
    /// <summary>Edits im Dokument der Aktion.</summary>
    Edits: TArray<TTextEdit>;
    /// <summary>Edits in weiteren Dateien (#309); nil = keine.</summary>
    FileEdits: TArray<TFileTextEdits>;
    IsPreferred: Boolean;
    /// <summary>Regelkennung des behobenen Treffers, sonst ''.</summary>
    RuleId: string;
    /// <summary>Bereich des behobenen Treffers, wenn RuleId gesetzt ist.</summary>
    DiagnosticRange: TTextRange;
    /// <summary>Befehl statt oder nach den Edits, z. B. für Dateiumwandlungen; '' ohne.</summary>
    Command: string;
    CommandArguments: TArray<string>;
    /// <summary>Kennung für Clients, die eine bestimmte Aktion suchen (UsesRemoveTag, #621); '' ohne.</summary>
    Tag: string;
  end;

  TCodeActions = class
  public
    class function SuppressLine(const AText: string; ALine: Integer; const ARuleId: string): TTextEdit; static;
    class function SuppressFile(const AText, ARuleId: string): TTextEdit; static;
    /// <summary>try/finally nach einer Create-Zuweisung in ALine mit Standard-Formatstil; parst AText selbst.
    /// False, wenn nicht passend.</summary>
    class function TryFinally(const AText: string; ALine: Integer; out AAction: TCodeAction): Boolean; overload;
      static;
    /// <summary>try/finally nach der Create-Zuweisung, die in ARange.StartPos.Line beginnt. Reicht ARange über
    /// die Anweisung hinaus, endet der try-Block mit der Auswahl, sonst mit dem umgebenden Block. Einrückung
    /// nach AStyle. False, wenn nicht passend.</summary>
    class function TryFinally(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean; overload; static;
    /// <summary>uses aufräumen (doppelte entfernen, mit ASort sortieren); False ohne Änderung.</summary>
    class function OrganizeImports(const AText: string; ASort: Boolean; out AAction: TCodeAction;
      AByNamespace: Boolean = False): Boolean; static;
    /// <summary>uses-Aktionen (#284): fehlende Unit zum Bezeichner an ARange.StartPos (Quick-Fix),
    /// interface-Units ins implementation verschieben (Rewrite). Mit ARemoveUnused zusätzlich
    /// "ungenutzte uses entfernen" (source.removeUnusedImports).</summary>
    class function UsesActions(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AContext: TUsesContext; AEditing, ARemoveUnused: Boolean): TArray<TCodeAction>; overload; static;
    /// <summary>Wie oben, dazu für die Einträge an ARange (#621): „X entfernen“, „Alle ungenutzten uses
    /// entfernen“ (ab zwei) und „X ins implementation-uses verschieben“, mit Tag. AInactive: inaktive Zweige,
    /// die bei der Prüfung nicht zählen.</summary>
    class function UsesActions(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AContext: TUsesContext; const AInactive: TArray<TTextRange>; AEditing,
      ARemoveUnused: Boolean): TArray<TCodeAction>; overload; static;
    /// <summary>"Zuweisungen umkehren" für die Zeilen von ARange (#313); False, wenn keine passt.</summary>
    class function SwapAssignments(const AText: string; const ARange: TTextRange; const AReadOnly: TReadOnlyCheck;
      out AAction: TCodeAction): Boolean; static;
    /// <summary>#312: Bei einer Markierung, die kein Literal ist, "Als String-Literal" (ganze Zeilen);
    /// auf einem Literal "Als Klartext kopieren" über CopyTextCommand.</summary>
    class function StringLiteralActions(const AText: string; const ARange: TTextRange;
      const ASettings: TStringLiteralSettings; AMultiline: Boolean): TArray<TCodeAction>; static;
    /// <summary>True, wenn AKind unter einer der angefragten Arten liegt (LSP "only"); leeres AOnly = alle.</summary>
    class function KindRequested(const AKind: string; const AOnly: TArray<string>): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  System.RegularExpressions,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.GuardFree,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Text.Lines;

/// <summary>Offset des ersten Tokens ab APosition (für die Wahl des uses-Abschnitts).</summary>
function OffsetNear(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  Token: TPascalToken;
begin
  Result := 0;
  for Token in ATokens do
  begin
    Result := Token.Offset;
    if (Token.EndPos.Line > APosition.Line) or
      ((Token.EndPos.Line = APosition.Line) and (Token.EndPos.Character >= APosition.Character)) then
      Exit;
  end;
end;


/// <summary>Anweisung, die ein try-Block einschließen kann.</summary>
function IsStatement(AKind: TSyntaxKind): Boolean;
begin
  Result := AKind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement,
    TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement,
    TSyntaxKind.TryStatement, TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement,
    TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement];
end;

/// <summary>Knoten mit einer Folge von Anweisungen, in der try/finally Platz hat.</summary>
function IsStatementList(AKind: TSyntaxKind): Boolean;
begin
  Result := AKind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock,
    TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement, TSyntaxKind.CaseElse];
end;

/// <summary>Zuweisung oder Inline-Variable, die in Zeile ALine beginnt und direkt in einer Anweisungsfolge steht.</summary>
function CreateStatementAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (Found <> nil) or (ANode.StartPos.Line > ALine) or (ANode.EndPos.Line < ALine) then
        Exit(False);
      if (ANode.StartPos.Line = ALine) and (ANode.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.InlineVar]) and
        (ANode.Parent <> nil) and IsStatementList(ANode.Parent.Kind) then
      begin
        Found := ANode;
        Exit(False);
      end;
      Result := True;
    end);
  Result := Found;
end;

function IndexInParent(ANode: TSyntaxNode): Integer;
var
  Index: Integer;
begin
  for Index := 0 to ANode.Parent.ChildCount - 1 do
    if ANode.Parent[Index] = ANode then
      Exit(Index);
  Result := -1;
end;

/// <summary>Leerraum und Zeilenumbrüche zu je einem Leerzeichen zusammengefasst.</summary>
function CollapseSpace(const AText: string): string;
var
  Index: Integer;
  Space: Boolean;
begin
  Result := '';
  Space := False;
  for Index := 1 to Length(AText) do
    if CharInSet(AText[Index], [' ', #9, #10, #13]) then
      Space := True
    else
    begin
      if Space and (Result <> '') then
        Result := Result + ' ';
      Space := False;
      Result := Result + AText[Index];
    end;
end;

function SourceOf(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Steht ANode allein auf seinen Zeilen: davor nur Leerraum, danach höchstens ";" und ein //-Kommentar?</summary>
function OwnsLines(const ALines: TArray<string>; ANode: TSyntaxNode): Boolean;
var
  After: string;
begin
  Result := False;
  if (ANode.StartPos.Line > High(ALines)) or (ANode.EndPos.Line > High(ALines)) then
    Exit;
  if Trim(Copy(ALines[ANode.StartPos.Line], 1, ANode.StartPos.Character)) <> '' then
    Exit;
  After := Trim(Copy(ALines[ANode.EndPos.Line], ANode.EndPos.Character + 1, MaxInt));
  if StartsStr(';', After) then
    After := Trim(Copy(After, 2, MaxInt));
  Result := (After = '') or StartsStr('//', After);
end;

/// <summary>Gibt die Anweisung AVariable frei (X.Free, X.DisposeOf, FreeAndNil(X))?</summary>
function IsRelease(const ASource, AVariable: string): Boolean;
var
  Escaped: string;
begin
  Escaped := TRegEx.Escape(AVariable);
  Result := TRegEx.IsMatch(ASource, '^\s*(' + Escaped + '\s*\.\s*(Free|DisposeOf)|FreeAndNil\s*\(\s*' + Escaped +
    '\s*\))\s*;?\s*$', [roIgnoreCase]);
end;

/// <summary>Freigegeben, zurückgegeben, zugewiesen oder an eine Liste übergeben: Dann gehört das Objekt nicht
/// in ein finally.</summary>
function EscapesOrFrees(const ASource, AVariable: string): Boolean;
var
  Escaped: string;
begin
  Escaped := TRegEx.Escape(AVariable);
  Result := TRegEx.IsMatch(ASource, '\b' + Escaped + '\s*\.\s*(Free|DisposeOf|Destroy)\b', [roIgnoreCase]) or
    TRegEx.IsMatch(ASource, '\bFreeAndNil\s*\(\s*' + Escaped + '\s*\)', [roIgnoreCase]) or
    TRegEx.IsMatch(ASource, ':=\s*' + Escaped + '\s*[;)]', [roIgnoreCase]) or
    TRegEx.IsMatch(ASource, '\bExit\s*\(\s*' + Escaped + '\s*\)', [roIgnoreCase]) or
    TRegEx.IsMatch(ASource, '\.\s*(Add|Insert|Push|Enqueue|AddObject|AddPair|AddOrSetValue)\s*\(([^;]*[^\w.])?' +
      Escaped + '\s*[,)]', [roIgnoreCase]);
end;

function IndentUnit(const AStyle: TFormatStyle): string;
begin
  if AStyle.UseTabs then
    Exit(#9);
  if AStyle.IndentSize > 0 then
    Result := StringOfChar(' ', AStyle.IndentSize)
  else
    Result := '  ';
end;

{ TCodeActions }

class function TCodeActions.SuppressLine(const AText: string; ALine: Integer; const ARuleId: string): TTextEdit;
var
  Lines: TArray<string>;
  Above, Line: string;
begin
  Lines := TTextLines.SplitLines(AText);
  if (ALine > 0) and (ALine <= High(Lines)) then
  begin
    Above := Lines[ALine - 1];
    if StartsText('// lsp-ignore:', TrimLeft(Above)) then
      Exit(TTextEdit.Create(TTextRange.Create(ALine - 1, Length(Above), ALine - 1, Length(Above)), ', ' + ARuleId));
  end;
  if (ALine >= 0) and (ALine <= High(Lines)) then
    Line := Lines[ALine]
  else
    Line := '';
  Result := TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, 0),
    TTextLines.IndentOf(Line) + '// lsp-ignore: ' + ARuleId + TTextLines.LineBreakOf(AText));
end;

class function TCodeActions.SuppressFile(const AText, ARuleId: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(0, 0, 0, 0),
    '// lsp-ignore-file: ' + ARuleId + TTextLines.LineBreakOf(AText));
end;

class function TCodeActions.TryFinally(const AText: string; ALine: Integer; out AAction: TCodeAction): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TryFinally(AText, Tree, TTextRange.Create(ALine, 0, ALine, 0), TFormatStyle.Default, AAction);
  finally
    Tree.Free;
  end;
end;

class function TCodeActions.TryFinally(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
  const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
var
  Lines: TArray<string>;
  Statement, Parent, Last, ReleaseNode: TSyntaxNode;
  Match: TMatch;
  Target, DeclaredType, Indent, Step, LB, Release, Body, Rest: string;
  SelectionEnd, Index, First, BodyEnd, Line: Integer;
  IsResult: Boolean;
begin
  AAction := Default(TCodeAction);
  Result := False;
  Lines := TTextLines.SplitLines(AText);
  if (ATree = nil) or (ATree.Root = nil) or (ARange.StartPos.Line < 0) or (ARange.StartPos.Line > High(Lines)) then
    Exit;
  Statement := CreateStatementAt(ATree, ARange.StartPos.Line);
  if (Statement = nil) or not OwnsLines(Lines, Statement) then
    Exit;
  // Ziel ist ein einfacher Name: Self.F und F[I] sind keine Zuweisung an eine lokale Variable.
  if (Statement.Kind = TSyntaxKind.AssignStatement) and
    ((Statement.ChildCount < 2) or (Statement[0].Kind <> TSyntaxKind.Identifier)) then
    Exit;
  // Leerraum und Zeilenumbrüche zusammenfassen: Der Aufruf darf über mehrere Zeilen gehen. Leere Alternativen
  // halten jede Gruppe belegt.
  Match := TRegEx.Match(CollapseSpace(SourceOf(AText, Statement)),
    '^(var |)(\w+) ?(:|)([^:=]*):= ?([A-Za-z_][\w.]*)(<[^;()]*>|) ?\. ?Create\w* ?(\(.*\)|) ?;?$',
    [roIgnoreCase]);
  if not Match.Success then
    Exit;
  Target := Match.Groups[2].Value;
  IsResult := SameText(Target, 'Result');
  if SameText(Target, 'Self') then
    Exit;
  if Statement.Kind = TSyntaxKind.InlineVar then
    DeclaredType := Trim(Match.Groups[4].Value)
  else if not IsResult and not TGuardFree.LocalVariableType(ATree, AText, Target, Statement.StartPos.Line,
    DeclaredType) then
    // Feld, globale Variable oder Parameter: Wem das Objekt gehört, sieht man hier nicht.
    Exit;
  if TRegEx.IsMatch(DeclaredType, '^I[A-Z]') then
    Exit;
  // Ein Owner gibt frei.
  if TRegEx.IsMatch(Match.Groups[7].Value, '^\( ?(Self|Application|Owner|AOwner) ?[,)]', [roIgnoreCase]) then
    Exit;
  // Folgende Anweisungen bis zum Blockende bzw. bis zum Ende der Auswahl.
  SelectionEnd := ARange.EndPos.Line;
  if (SelectionEnd > ARange.StartPos.Line) and (ARange.EndPos.Character = 0) then
    Dec(SelectionEnd);
  if SelectionEnd <= Statement.EndPos.Line then
    SelectionEnd := MaxInt;
  Parent := Statement.Parent;
  First := IndexInParent(Statement) + 1;
  // Schon geschützt.
  if (First < Parent.ChildCount) and (Parent[First].Kind = TSyntaxKind.TryStatement) then
    Exit;
  Last := nil;
  Index := First;
  while (Index < Parent.ChildCount) and IsStatement(Parent[Index].Kind) and
    (Parent[Index].StartPos.Line <= SelectionEnd) do
  begin
    if Parent[Index].Kind <> TSyntaxKind.EmptyStatement then
      Last := Parent[Index];
    Inc(Index);
  end;
  if (Last = nil) or not OwnsLines(Lines, Last) or (Parent[First].StartPos.Line <= Statement.EndPos.Line) then
    Exit;
  // Eine Freigabe als letzte Anweisung wandert ins finally; jede andere Freigabe oder Weitergabe verbietet die
  // Aktion, auch hinter dem eingeschlossenen Teil.
  ReleaseNode := nil;
  if not IsResult and IsRelease(SourceOf(AText, Last), Target) then
    ReleaseNode := Last;
  Rest := '';
  for Index := First to Parent.ChildCount - 1 do
    if Parent[Index] <> ReleaseNode then
      Rest := Rest + SourceOf(AText, Parent[Index]) + ';' + #10;
  if not IsResult and EscapesOrFrees(Rest, Target) then
    Exit;
  BodyEnd := Last.EndPos.Line;
  if ReleaseNode <> nil then
  begin
    BodyEnd := ReleaseNode.StartPos.Line - 1;
    // Nur die Freigabe: Der try-Block bliebe leer.
    if ReleaseNode = Parent[First] then
      Exit;
  end;
  while (BodyEnd > Statement.EndPos.Line) and (Trim(Lines[BodyEnd]) = '') do
    Dec(BodyEnd);
  Indent := TTextLines.IndentOf(Lines[Statement.StartPos.Line]);
  Step := IndentUnit(AStyle);
  LB := TTextLines.LineBreakOf(AText);
  Body := '';
  for Line := Statement.EndPos.Line + 1 to BodyEnd do
  begin
    if Trim(Lines[Line]) <> '' then
      Body := Body + Step + Lines[Line];
    Body := Body + LB;
  end;
  AAction.Kind := RewriteKind;
  if IsResult then
  begin
    AAction.Title := 'try/except ergänzen (Result bei Fehler freigeben)';
    Body := Body + Indent + 'except' + LB + Indent + Step + 'Result.Free;' + LB + Indent + Step + 'raise;';
  end
  else
  begin
    AAction.Title := Format('try/finally mit %s.Free ergänzen', [Target]);
    if ReleaseNode <> nil then
      Release := Trim(SourceOf(AText, ReleaseNode)) + ';'
    else
      Release := Target + '.Free;';
    Body := Body + Indent + 'finally' + LB + Indent + Step + Release;
  end;
  AAction.Edits := [TTextEdit.Create(TTextRange.Create(Statement.EndPos.Line, Length(Lines[Statement.EndPos.Line]),
    Last.EndPos.Line, Length(Lines[Last.EndPos.Line])), LB + Indent + 'try' + LB + Body + LB + Indent + 'end;')];
  Result := True;
end;

class function TCodeActions.OrganizeImports(const AText: string; ASort: Boolean; out AAction: TCodeAction;
  AByNamespace: Boolean): Boolean;
var
  Edits: TArray<TTextEdit>;
begin
  AAction := Default(TCodeAction);
  Result := TUsesClauses.Organize(TPascalLexer.Tokenize(AText), AText, ASort, TTextLines.LineBreakOf(AText), Edits,
    AByNamespace);
  if not Result then
    Exit;
  AAction.Title := 'uses aufräumen';
  AAction.Kind := OrganizeImportsKind;
  AAction.Edits := Edits;
end;

class function TCodeActions.UsesActions(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
  const AContext: TUsesContext; AEditing, ARemoveUnused: Boolean): TArray<TCodeAction>;
begin
  Result := UsesActions(AText, ATree, ARange, AContext, nil, AEditing, ARemoveUnused);
end;

/// <summary>Überschneiden sich die Bereiche? Enden zählen mit, damit ein Cursor am Namen trifft.</summary>
function Touches(const A, B: TTextRange): Boolean;

  function Before(const X, Y: TTextPosition): Boolean;
  begin
    Result := (X.Line < Y.Line) or ((X.Line = Y.Line) and (X.Character < Y.Character));
  end;

begin
  Result := not (Before(A.EndPos, B.StartPos) or Before(B.EndPos, A.StartPos));
end;

class function TCodeActions.UsesActions(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
  const AContext: TUsesContext; const AInactive: TArray<TTextRange>; AEditing,
  ARemoveUnused: Boolean): TArray<TCodeAction>;
var
  Tokens: TArray<TPascalToken>;
  Units, Movable: TArray<string>;
  UnitName: string;
  Action: TCodeAction;
  Edit: TTextEdit;
  Edits: TArray<TTextEdit>;
  Entries: TArray<TUsesEntry>;
  Entry: TUsesEntry;
  Unused: TArray<TTextRange>;
  Index: Integer;
begin
  Result := nil;
  if not Assigned(AContext.Info) then
    Exit;
  Tokens := TPascalLexer.Tokenize(AText);
  if AEditing and Assigned(AContext.Declaring) then
    for UnitName in TUsesActions.MissingUnits(Tokens, ATree, ARange.StartPos, AContext.Declaring,
      AContext.Namespaces) do
      if TUsesClauses.AddUnit(Tokens, OffsetNear(Tokens, ARange.StartPos), UnitName, TTextLines.LineBreakOf(AText),
        Edit) then
      begin
        Action := Default(TCodeAction);
        Action.Title := Format('uses %s ergänzen', [UnitName]);
        Action.Kind := QuickFixKind;
        Action.Edits := [Edit];
        Result := Result + [Action];
      end;
  if AEditing then
  begin
    Units := TUsesActions.MovableUnits(Tokens, AContext.Info);
    Movable := Units;
    if TUsesActions.MoveUnits(Tokens, AText, Units, TTextLines.LineBreakOf(AText), Edits) then
    begin
      Action := Default(TCodeAction);
      Action.Title := Format('%s ins implementation-uses verschieben', [string.Join(', ', Units)]);
      Action.Kind := RewriteKind;
      Action.Edits := Edits;
      Result := Result + [Action];
    end;
  end;
  if ARemoveUnused then
  begin
    Units := TUsesActions.UnusedUnits(Tokens, AContext.Info, AContext.Keep);
    if TUsesActions.RemoveUnits(Tokens, AText, Units, TTextLines.LineBreakOf(AText), Edits) then
    begin
      Action := Default(TCodeAction);
      Action.Title := Format('Ungenutzte uses entfernen (%s)', [string.Join(', ', Units)]);
      Action.Kind := RemoveUnusedKind;
      Action.Edits := Edits;
      Result := Result + [Action];
    end;
  end;
  if not AEditing then
    Exit;
  // Einzelne Einträge an der Stelle (#621), auch in Listen mit {$IFDEF}.
  Entries := TUsesActions.Entries(Tokens, AInactive, AContext.Info, AContext.Keep);
  Unused := nil;
  for Entry in Entries do
    if Entry.State = TUsesEntryState.Unused then
      Unused := Unused + [Entry.Range];
  for Entry in Entries do
  begin
    if not Touches(Entry.Range, ARange) then
      Continue;
    if Entry.State = TUsesEntryState.Unused then
    begin
      if TUsesActions.RemoveEntries(AText, [Entry.Range], Edit) then
      begin
        Action := Default(TCodeAction);
        Action.Title := Format('%s entfernen', [Entry.Name]);
        Action.Kind := QuickFixKind;
        Action.Edits := [Edit];
        Action.IsPreferred := True;
        Action.Tag := UsesRemoveTag;
        Result := Result + [Action];
      end;
      if (Length(Unused) > 1) and TUsesActions.RemoveEntries(AText, Unused, Edit) then
      begin
        Action := Default(TCodeAction);
        Action.Title := Format('Alle ungenutzten uses entfernen (%d)', [Length(Unused)]);
        Action.Kind := QuickFixKind;
        Action.Edits := [Edit];
        Action.Tag := UsesRemoveAllTag;
        Result := Result + [Action];
      end;
    end
    else if Entry.State <> TUsesEntryState.OnlyImplementation then
      Continue
    // Allein verschiebbar: Die Aktion für alle oben hat schon denselben Titel und bekommt die Kennung.
    else if (Length(Movable) = 1) and SameText(Movable[0], Entry.Name) then
    begin
      for Index := 0 to High(Result) do
        if (Result[Index].Kind = RewriteKind) and
          SameText(Result[Index].Title, Format('%s ins implementation-uses verschieben', [Entry.Name])) then
          Result[Index].Tag := UsesMoveTag;
    end
    else if TUsesActions.MoveUnits(Tokens, AText, [Entry.Name], TTextLines.LineBreakOf(AText), Edits) then
    begin
      Action := Default(TCodeAction);
      Action.Title := Format('%s ins implementation-uses verschieben', [Entry.Name]);
      Action.Kind := RewriteKind;
      Action.Edits := Edits;
      Action.Tag := UsesMoveTag;
      Result := Result + [Action];
    end;
  end;
end;

class function TCodeActions.KindRequested(const AKind: string; const AOnly: TArray<string>): Boolean;
var
  Only: string;
begin
  if AOnly = nil then
    Exit(True);
  // "source" umfasst "source.fixAll", aber nicht "sourceX".
  for Only in AOnly do
    if SameText(AKind, Only) or StartsText(Only + '.', AKind) then
      Exit(True);
  Result := False;
end;

class function TCodeActions.SwapAssignments(const AText: string; const ARange: TTextRange;
  const AReadOnly: TReadOnlyCheck; out AAction: TCodeAction): Boolean;
begin
  AAction := Default(TCodeAction);
  Result := TAssignmentSwap.Swap(AText, ARange, AReadOnly, AAction.Edits);
  if Result then
  begin
    AAction.Title := 'Zuweisungen umkehren';
    AAction.Kind := RewriteKind;
  end;
end;

class function TCodeActions.StringLiteralActions(const AText: string; const ARange: TTextRange;
  const ASettings: TStringLiteralSettings; AMultiline: Boolean): TArray<TCodeAction>;
var
  Lines: TArray<string>;
  Action: TCodeAction;
  Literal: TTextRange;
  Plain, Indent: string;
  First, Last, Line, Common: Integer;
begin
  Result := nil;
  if TStringLiterals.LiteralAt(AText, ARange.StartPos, Literal) and
    TStringLiterals.PlainText(TStringLiterals.TextOf(AText, Literal), Plain) then
  begin
    Action := Default(TCodeAction);
    Action.Title := 'Als Klartext kopieren';
    Action.Kind := RewriteKind;
    Action.Command := CopyTextCommand;
    Action.CommandArguments := [Plain];
    Result := [Action];
    Exit;
  end;
  if (ARange.StartPos.Line = ARange.EndPos.Line) and (ARange.StartPos.Character = ARange.EndPos.Character) then
    Exit;
  Lines := TTextLines.SplitLines(AText);
  First := ARange.StartPos.Line;
  Last := ARange.EndPos.Line;
  if (Last > First) and (ARange.EndPos.Character = 0) then
    Dec(Last);
  if Last > High(Lines) then
    Last := High(Lines);
  if (First < 0) or (First > Last) then
    Exit;
  // Gemeinsame Einrückung entfernen; die erste Zeile gibt die Einrückung des Literals vor.
  Common := MaxInt;
  for Line := First to Last do
    if (Trim(Lines[Line]) <> '') and (Length(TTextLines.IndentOf(Lines[Line])) < Common) then
      Common := Length(TTextLines.IndentOf(Lines[Line]));
  if Common = MaxInt then
    Exit;
  Indent := TTextLines.IndentOf(Lines[First]);
  Plain := '';
  for Line := First to Last do
  begin
    if Line > First then
      Plain := Plain + #10;
    Plain := Plain + Copy(Lines[Line], Common + 1, MaxInt);
  end;
  Action := Default(TCodeAction);
  Action.Title := 'Als String-Literal';
  Action.Kind := RewriteKind;
  Action.Edits := [TTextEdit.Create(TTextRange.Create(First, 0, Last, Length(Lines[Last])),
    TStringLiterals.ToLiteral(Plain, Indent, True, AMultiline, ASettings.LineBreak, ASettings.MaxLineLength,
    TTextLines.LineBreakOf(AText)))];
  Result := [Action];
end;

end.
