unit BDLsp.Common.Editing.CodeActions;

// Code-Aktionen ohne Protokollbezug (#42, #147):
//   - Korrekturen der Regeltreffer (TRuleFix)
//   - "Regel für diese Zeile unterdrücken": eigene Kommentarzeile darüber,
//     bestehende "// lsp-ignore:"-Zeile darüber wird ergänzt
//   - "Regel für diese Datei unterdrücken": "// lsp-ignore-file:" in Zeile 1
//   - "try/finally ergänzen" nach "X := T.Create(...);" mit passendem X.Free;
//     bei "Result := T.Create(...)" stattdessen try/except, das Result nur im
//     Fehlerfall freigibt (das Objekt wird ja zurückgegeben)

interface

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Rules.Contract;

const
  QuickFixKind = 'quickfix';
  RewriteKind = 'refactor.rewrite';
  // Für editor.codeActionsOnSave (#182).
  OrganizeImportsKind = 'source.organizeImports';
  FixAllKind = 'source.fixAll';

type
  TCodeAction = record
    Title: string;
    Kind: string;
    Edits: TArray<TRuleEdit>;
    IsPreferred: Boolean;
    /// <summary>Regelkennung des behobenen Treffers, sonst ''.</summary>
    RuleId: string;
    /// <summary>Bereich des behobenen Treffers, wenn RuleId gesetzt ist.</summary>
    DiagnosticRange: TTextRange;
  end;

  TCodeActions = class
  public
    /// <summary>Aktionen zu allen Treffern, die Zeilen aus ARange berühren.</summary>
    class function ForFindings(const AFindings: TArray<TRuleFinding>; const AText: string;
      const ARange: TTextRange): TArray<TCodeAction>; static;
    class function SuppressLine(const AText: string; ALine: Integer; const ARuleId: string): TRuleEdit; static;
    class function SuppressFile(const AText, ARuleId: string): TRuleEdit; static;
    /// <summary>try/finally nach einer Create-Zuweisung in ALine; False, wenn nicht passend.</summary>
    class function TryFinally(const AText: string; ALine: Integer; out AAction: TCodeAction): Boolean; static;
    /// <summary>Alle Aktionen für ARange: Treffer und try/finally in der Startzeile.</summary>
    class function ForRange(const AFindings: TArray<TRuleFinding>; const AText: string;
      const ARange: TTextRange): TArray<TCodeAction>; static;
    /// <summary>Alle als sicher markierten Korrekturen der Datei in einer Aktion; überlappende
    /// Edits werden ausgelassen. False ohne sichere Korrektur.</summary>
    class function FixAll(const AFindings: TArray<TRuleFinding>; out AAction: TCodeAction): Boolean; static;
    /// <summary>uses aufräumen (doppelte entfernen, mit ASort sortieren); False ohne Änderung.</summary>
    class function OrganizeImports(const AText: string; ASort: Boolean; out AAction: TCodeAction): Boolean; static;
    /// <summary>True, wenn AKind unter einer der angefragten Arten liegt (LSP "only"); leeres AOnly = alle.</summary>
    class function KindRequested(const AKind: string; const AOnly: TArray<string>): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  BDLsp.Common.Pascal.Lexer,
  BDLsp.Common.Editing.UsesClause;

function SplitLines(const AText: string): TArray<string>;
var
  I, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for I := 1 to Length(AText) do
    if AText[I] = #10 then
    begin
      Result := Result + [Copy(AText, Start, I - Start)];
      Start := I + 1;
    end;
  Result := Result + [Copy(AText, Start, MaxInt)];
end;

function StripCr(const ALine: string): string;
begin
  if (ALine <> '') and (ALine[Length(ALine)] = #13) then
    Result := Copy(ALine, 1, Length(ALine) - 1)
  else
    Result := ALine;
end;

function LineBreakOf(const AText: string): string;
begin
  if Pos(#13#10, AText) > 0 then
    Result := #13#10
  else
    Result := #10;
end;

function IndentOf(const ALine: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(ALine)) and CharInSet(ALine[I], [' ', #9]) do
    Inc(I);
  Result := Copy(ALine, 1, I - 1);
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) or (Ord(C) >= 128);
end;

{ TCodeActions }

class function TCodeActions.SuppressLine(const AText: string; ALine: Integer; const ARuleId: string): TRuleEdit;
var
  Lines: TArray<string>;
  Above, Line: string;
begin
  Lines := SplitLines(AText);
  if (ALine > 0) and (ALine <= High(Lines)) then
  begin
    Above := StripCr(Lines[ALine - 1]);
    if StartsText('// lsp-ignore:', TrimLeft(Above)) then
      Exit(TRuleEdit.Create(TTextRange.Create(ALine - 1, Length(Above), ALine - 1, Length(Above)), ', ' + ARuleId));
  end;
  if (ALine >= 0) and (ALine <= High(Lines)) then
    Line := StripCr(Lines[ALine])
  else
    Line := '';
  Result := TRuleEdit.Create(TTextRange.Create(ALine, 0, ALine, 0),
    IndentOf(Line) + '// lsp-ignore: ' + ARuleId + LineBreakOf(AText));
end;

class function TCodeActions.SuppressFile(const AText, ARuleId: string): TRuleEdit;
begin
  Result := TRuleEdit.Create(TTextRange.Create(0, 0, 0, 0), '// lsp-ignore-file: ' + ARuleId + LineBreakOf(AText));
end;

class function TCodeActions.ForFindings(const AFindings: TArray<TRuleFinding>; const AText: string;
  const ARange: TTextRange): TArray<TCodeAction>;
var
  Finding: TRuleFinding;
  Fix: TRuleFix;
  Action: TCodeAction;
  First: Boolean;
begin
  Result := nil;
  for Finding in AFindings do
  begin
    if (Finding.Range.EndPos.Line < ARange.StartPos.Line) or (Finding.Range.StartPos.Line > ARange.EndPos.Line) then
      Continue;
    First := True;
    for Fix in Finding.Fixes do
    begin
      Action := Default(TCodeAction);
      Action.Title := Fix.Title;
      Action.Kind := QuickFixKind;
      Action.Edits := Fix.Edits;
      Action.IsPreferred := First;
      Action.RuleId := Finding.RuleId;
      Action.DiagnosticRange := Finding.Range;
      Result := Result + [Action];
      First := False;
    end;
    if SameText(Finding.RuleId, 'unused-suppression') or SameText(Finding.RuleId, 'syntax') then
      Continue;
    Action := Default(TCodeAction);
    Action.Title := Format('"%s" für diese Zeile unterdrücken', [Finding.RuleId]);
    Action.Kind := QuickFixKind;
    Action.Edits := [SuppressLine(AText, Finding.Range.StartPos.Line, Finding.RuleId)];
    Action.RuleId := Finding.RuleId;
    Action.DiagnosticRange := Finding.Range;
    Result := Result + [Action];
    Action.Title := Format('"%s" für diese Datei unterdrücken', [Finding.RuleId]);
    Action.Edits := [SuppressFile(AText, Finding.RuleId)];
    Result := Result + [Action];
  end;
end;

class function TCodeActions.TryFinally(const AText: string; ALine: Integer; out AAction: TCodeAction): Boolean;
var
  Lines: TArray<string>;
  Line, Trimmed, Target, Indent, LB, Next: string;
  Assign, I: Integer;
begin
  AAction := Default(TCodeAction);
  Result := False;
  Lines := SplitLines(AText);
  if (ALine < 0) or (ALine > High(Lines)) then
    Exit;
  Line := StripCr(Lines[ALine]);
  Trimmed := Trim(Line);
  Assign := Pos(':=', Trimmed);
  if (Assign < 2) or not EndsText(';', Trimmed) or (Pos('.CREATE', UpperCase(Copy(Trimmed, Assign, MaxInt))) = 0) then
    Exit;
  Target := Trim(Copy(Trimmed, 1, Assign - 1));
  if Target = '' then
    Exit;
  for I := 1 to Length(Target) do
    if not IsIdentChar(Target[I]) then
      Exit;
  // Schon geschützt: Die nächste Zeile mit Inhalt beginnt mit try.
  for I := ALine + 1 to High(Lines) do
  begin
    Next := Trim(StripCr(Lines[I]));
    if Next = '' then
      Continue;
    if SameText(Copy(Next, 1, 3), 'try') and ((Length(Next) = 3) or not IsIdentChar(Next[4])) then
      Exit;
    Break;
  end;
  Indent := IndentOf(Line);
  LB := LineBreakOf(AText);
  AAction.Kind := RewriteKind;
  if SameText(Target, 'Result') then
  begin
    AAction.Title := 'try/except ergänzen (Result bei Fehler freigeben)';
    AAction.Edits := [TRuleEdit.Create(TTextRange.Create(ALine, Length(Line), ALine, Length(Line)),
      LB + Indent + 'try' + LB + LB + Indent + 'except' + LB + Indent + '  ' + Target + '.Free;' + LB +
      Indent + '  raise;' + LB + Indent + 'end;')];
  end
  else
  begin
    AAction.Title := Format('try/finally mit %s.Free ergänzen', [Target]);
    AAction.Edits := [TRuleEdit.Create(TTextRange.Create(ALine, Length(Line), ALine, Length(Line)),
      LB + Indent + 'try' + LB + LB + Indent + 'finally' + LB + Indent + '  ' + Target + '.Free;' + LB + Indent + 'end;')];
  end;
  Result := True;
end;

function Overlaps(const A, B: TTextRange): Boolean;

  function Before(const X, Y: TTextPosition): Boolean;
  begin
    Result := (X.Line < Y.Line) or ((X.Line = Y.Line) and (X.Character <= Y.Character));
  end;

begin
  // Bereiche, die sich nur berühren, überlappen nicht.
  Result := not (Before(A.EndPos, B.StartPos) or Before(B.EndPos, A.StartPos));
end;

class function TCodeActions.FixAll(const AFindings: TArray<TRuleFinding>; out AAction: TCodeAction): Boolean;
var
  Finding: TRuleFinding;
  Fix: TRuleFix;
  Edit, Taken: TRuleEdit;
  Fits: Boolean;
begin
  AAction := Default(TCodeAction);
  AAction.Title := 'Alle sicheren Korrekturen anwenden';
  AAction.Kind := FixAllKind;
  for Finding in AFindings do
    for Fix in Finding.Fixes do
    begin
      if not Fix.Safe then
        Continue;
      Fits := True;
      for Edit in Fix.Edits do
        for Taken in AAction.Edits do
          if Overlaps(Edit.Range, Taken.Range) then
            Fits := False;
      // Eine Korrektur ganz oder gar nicht; die übersprungene kommt beim nächsten Lauf.
      if Fits then
        AAction.Edits := AAction.Edits + Fix.Edits;
      Break;
    end;
  Result := AAction.Edits <> nil;
end;

class function TCodeActions.OrganizeImports(const AText: string; ASort: Boolean; out AAction: TCodeAction): Boolean;
var
  Edits: TArray<TRuleEdit>;
begin
  AAction := Default(TCodeAction);
  Result := TUsesClauses.Organize(TPascalLexer.Tokenize(AText), AText, ASort, LineBreakOf(AText), Edits);
  if not Result then
    Exit;
  AAction.Title := 'uses aufräumen';
  AAction.Kind := OrganizeImportsKind;
  AAction.Edits := Edits;
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

class function TCodeActions.ForRange(const AFindings: TArray<TRuleFinding>; const AText: string;
  const ARange: TTextRange): TArray<TCodeAction>;
var
  Action: TCodeAction;
begin
  Result := ForFindings(AFindings, AText, ARange);
  if TryFinally(AText, ARange.StartPos.Line, Action) then
    Result := Result + [Action];
end;

end.
