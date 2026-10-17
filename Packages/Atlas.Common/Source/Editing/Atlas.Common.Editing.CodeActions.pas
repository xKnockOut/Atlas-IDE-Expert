unit Atlas.Common.Editing.CodeActions;

// Code-Aktionen ohne Protokollbezug (#42, #147):
//   - Korrekturen der Regeltreffer: Atlas.Common.Rules.CodeActions (A-11)
//   - "Regel für diese Zeile unterdrücken": eigene Kommentarzeile darüber,
//     bestehende "// lsp-ignore:"-Zeile darüber wird ergänzt
//   - "Regel für diese Datei unterdrücken": "// lsp-ignore-file:" in Zeile 1
//   - "try/finally ergänzen" nach "X := T.Create(...);" mit passendem X.Free;
//     bei "Result := T.Create(...)" stattdessen try/except, das Result nur im
//     Fehlerfall freigibt (das Objekt wird ja zurückgegeben)
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
  end;

  TCodeActions = class
  public
    class function SuppressLine(const AText: string; ALine: Integer; const ARuleId: string): TTextEdit; static;
    class function SuppressFile(const AText, ARuleId: string): TTextEdit; static;
    /// <summary>try/finally nach einer Create-Zuweisung in ALine; False, wenn nicht passend.</summary>
    class function TryFinally(const AText: string; ALine: Integer; out AAction: TCodeAction): Boolean; static;
    /// <summary>uses aufräumen (doppelte entfernen, mit ASort sortieren); False ohne Änderung.</summary>
    class function OrganizeImports(const AText: string; ASort: Boolean; out AAction: TCodeAction;
      AByNamespace: Boolean = False): Boolean; static;
    /// <summary>uses-Aktionen (#284): fehlende Unit zum Bezeichner an ARange.StartPos (Quick-Fix),
    /// interface-Units ins implementation verschieben (Rewrite). Mit ARemoveUnused zusätzlich
    /// "ungenutzte uses entfernen" (source.removeUnusedImports).</summary>
    class function UsesActions(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AContext: TUsesContext; AEditing, ARemoveUnused: Boolean): TArray<TCodeAction>; static;
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
  Atlas.Common.Pascal.Lexer,
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

/// <summary>Zeichen eines gepunkteten Namens (Unit.Typ): Bezeichnerzeichen oder ".".</summary>
function IsDottedNameChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) or (Ord(C) >= 128);
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
  Lines: TArray<string>;
  Line, Trimmed, Target, Indent, LB, Next: string;
  Assign, I: Integer;
begin
  AAction := Default(TCodeAction);
  Result := False;
  Lines := TTextLines.SplitLines(AText);
  if (ALine < 0) or (ALine > High(Lines)) then
    Exit;
  Line := Lines[ALine];
  Trimmed := Trim(Line);
  Assign := Pos(':=', Trimmed);
  if (Assign < 2) or not EndsText(';', Trimmed) or (Pos('.CREATE', UpperCase(Copy(Trimmed, Assign, MaxInt))) = 0) then
    Exit;
  Target := Trim(Copy(Trimmed, 1, Assign - 1));
  if Target = '' then
    Exit;
  for I := 1 to Length(Target) do
    if not IsDottedNameChar(Target[I]) then
      Exit;
  // Schon geschützt: Die nächste Zeile mit Inhalt beginnt mit try.
  for I := ALine + 1 to High(Lines) do
  begin
    Next := Trim(Lines[I]);
    if Next = '' then
      Continue;
    if SameText(Copy(Next, 1, 3), 'try') and ((Length(Next) = 3) or not IsDottedNameChar(Next[4])) then
      Exit;
    Break;
  end;
  Indent := TTextLines.IndentOf(Line);
  LB := TTextLines.LineBreakOf(AText);
  AAction.Kind := RewriteKind;
  if SameText(Target, 'Result') then
  begin
    AAction.Title := 'try/except ergänzen (Result bei Fehler freigeben)';
    AAction.Edits := [TTextEdit.Create(TTextRange.Create(ALine, Length(Line), ALine, Length(Line)),
      LB + Indent + 'try' + LB + LB + Indent + 'except' + LB + Indent + '  ' + Target + '.Free;' + LB +
      Indent + '  raise;' + LB + Indent + 'end;')];
  end
  else
  begin
    AAction.Title := Format('try/finally mit %s.Free ergänzen', [Target]);
    AAction.Edits := [TTextEdit.Create(TTextRange.Create(ALine, Length(Line), ALine, Length(Line)),
      LB + Indent + 'try' + LB + LB + Indent + 'finally' + LB + Indent + '  ' + Target + '.Free;' + LB + Indent + 'end;')];
  end;
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
var
  Tokens: TArray<TPascalToken>;
  Units: TArray<string>;
  UnitName: string;
  Action: TCodeAction;
  Edit: TTextEdit;
  Edits: TArray<TTextEdit>;
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
