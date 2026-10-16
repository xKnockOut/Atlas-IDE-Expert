unit Atlas.Common.Rules.CodeActions;

// Brücke von Regeltreffern zu Code-Aktionen (#42, #182): Korrekturen der Treffer,
// "Regel unterdrücken" und "Alle sicheren Korrekturen anwenden". Lag bis A-11 in
// Editing.CodeActions; dort bleiben TCodeAction und die Aktionen ohne Regelbezug,
// damit Editing nicht von Rules abhängt (Rules -> Editing ist erlaubt).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.CodeActions;

type
  TRuleCodeActions = class
  public
    /// <summary>Aktionen zu allen Treffern, die Zeilen aus ARange berühren.</summary>
    class function ForFindings(const AFindings: TArray<TRuleFinding>; const AText: string;
      const ARange: TTextRange): TArray<TCodeAction>; static;
    /// <summary>Alle Aktionen für ARange: Treffer und try/finally in der Startzeile.</summary>
    class function ForRange(const AFindings: TArray<TRuleFinding>; const AText: string;
      const ARange: TTextRange): TArray<TCodeAction>; static;
    /// <summary>Alle als sicher markierten Korrekturen der Datei in einer Aktion; überlappende
    /// Edits werden ausgelassen. False ohne sichere Korrektur.</summary>
    class function FixAll(const AFindings: TArray<TRuleFinding>; out AAction: TCodeAction): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

function Overlaps(const A, B: TTextRange): Boolean;

  function Before(const X, Y: TTextPosition): Boolean;
  begin
    Result := (X.Line < Y.Line) or ((X.Line = Y.Line) and (X.Character <= Y.Character));
  end;

begin
  // Bereiche, die sich nur berühren, überlappen nicht.
  Result := not (Before(A.EndPos, B.StartPos) or Before(B.EndPos, A.StartPos));
end;

{ TRuleCodeActions }

class function TRuleCodeActions.ForFindings(const AFindings: TArray<TRuleFinding>; const AText: string;
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
      Action.IsPreferred := First and not Fix.Alternative;
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
    Action.Edits := [TCodeActions.SuppressLine(AText, Finding.Range.StartPos.Line, Finding.RuleId)];
    Action.RuleId := Finding.RuleId;
    Action.DiagnosticRange := Finding.Range;
    Result := Result + [Action];
    Action.Title := Format('"%s" für diese Datei unterdrücken', [Finding.RuleId]);
    Action.Edits := [TCodeActions.SuppressFile(AText, Finding.RuleId)];
    Result := Result + [Action];
  end;
end;

class function TRuleCodeActions.FixAll(const AFindings: TArray<TRuleFinding>; out AAction: TCodeAction): Boolean;
var
  Finding: TRuleFinding;
  Fix: TRuleFix;
  Edit, Taken: TTextEdit;
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

class function TRuleCodeActions.ForRange(const AFindings: TArray<TRuleFinding>; const AText: string;
  const ARange: TTextRange): TArray<TCodeAction>;
var
  Action: TCodeAction;
begin
  Result := ForFindings(AFindings, AText, ARange);
  if TCodeActions.TryFinally(AText, ARange.StartPos.Line, Action) then
    Result := Result + [Action];
end;

end.
