unit Atlas.Common.Rules.CodeActions;

// Brücke von Regeltreffern zu Code-Aktionen (#42, #182): Korrekturen der Treffer,
// "Regel unterdrücken" und "Alle sicheren Korrekturen anwenden". Lag bis A-11 in
// Editing.CodeActions; dort bleiben TCodeAction und die Aktionen ohne Regelbezug,
// damit Editing nicht von Rules abhängt (Rules -> Editing ist erlaubt).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
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
      const ARange: TTextRange): TArray<TCodeAction>; overload; static;
    /// <summary>Wie oben mit vorhandenem Syntaxbaum und dem Formatstil der Datei für try/finally (#42).</summary>
    class function ForRange(const AFindings: TArray<TRuleFinding>; const AText: string; ATree: TSyntaxTree;
      const ARange: TTextRange; const AStyle: TFormatStyle): TArray<TCodeAction>; overload; static;
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

function FileEditsIndex(const AAction: TCodeAction; const AFileName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(AAction.FileEdits) do
    if SameText(AAction.FileEdits[Index].FileName, AFileName) then
      Exit(Index);
  Result := -1;
end;

/// <summary>Edits der Korrektur in die Aktion: ins Dokument oder in die Datei der Korrektur (#309).</summary>
procedure AddFixEdits(var AAction: TCodeAction; const AFix: TRuleFix);
var
  Index: Integer;
  Entry: TFileTextEdits;
begin
  if AFix.FileName = '' then
  begin
    AAction.Edits := AAction.Edits + AFix.Edits;
    Exit;
  end;
  Index := FileEditsIndex(AAction, AFix.FileName);
  if Index < 0 then
  begin
    Entry.FileName := AFix.FileName;
    Entry.Edits := AFix.Edits;
    AAction.FileEdits := AAction.FileEdits + [Entry];
  end
  else
    AAction.FileEdits[Index].Edits := AAction.FileEdits[Index].Edits + AFix.Edits;
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
      AddFixEdits(Action, Fix);
      // Sprung zu einer anderen Stelle der Datei (#915), z. B. zur Freigabe.
      if Fix.HasJump then
      begin
        Action.Command := GoToPositionCommand;
        Action.CommandArguments := [IntToStr(Fix.JumpTo.Line), IntToStr(Fix.JumpTo.Character)];
      end;
      Action.IsPreferred := First and not Fix.Alternative;
      Action.RuleId := Finding.RuleId;
      Action.DiagnosticRange := Finding.Range;
      // Fenster „Atlas-Prüfung“ und Befund-Hover suchen die Schnellkorrektur über das Tag (#909).
      if Action.IsPreferred then
        Action.Tag := RuleFixTag;
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
    Action.Tag := RuleSuppressLineTag;
    Result := Result + [Action];
    Action.Title := Format('"%s" für diese Datei unterdrücken', [Finding.RuleId]);
    Action.Edits := [TCodeActions.SuppressFile(AText, Finding.RuleId)];
    Action.Tag := RuleSuppressFileTag;
    Result := Result + [Action];
  end;
end;

class function TRuleCodeActions.FixAll(const AFindings: TArray<TRuleFinding>; out AAction: TCodeAction): Boolean;
var
  Finding: TRuleFinding;
  Fix: TRuleFix;
  Edit, Taken: TTextEdit;
  Fits: Boolean;
  Target: Integer;
  Existing: TArray<TTextEdit>;
begin
  AAction := Default(TCodeAction);
  AAction.Title := 'Alle sicheren Korrekturen anwenden';
  AAction.Kind := FixAllKind;
  for Finding in AFindings do
    for Fix in Finding.Fixes do
    begin
      if not Fix.Safe then
        Continue;
      // Überlappung je Datei: das Dokument oder z. B. die Formulardatei (#309).
      Target := FileEditsIndex(AAction, Fix.FileName);
      if Fix.FileName = '' then
        Existing := AAction.Edits
      else if Target >= 0 then
        Existing := AAction.FileEdits[Target].Edits
      else
        Existing := nil;
      Fits := True;
      for Edit in Fix.Edits do
        for Taken in Existing do
          if Overlaps(Edit.Range, Taken.Range) then
            Fits := False;
      // Eine Korrektur ganz oder gar nicht; die übersprungene kommt beim nächsten Lauf.
      if Fits then
        AddFixEdits(AAction, Fix);
      Break;
    end;
  Result := (AAction.Edits <> nil) or (AAction.FileEdits <> nil);
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

class function TRuleCodeActions.ForRange(const AFindings: TArray<TRuleFinding>; const AText: string;
  ATree: TSyntaxTree; const ARange: TTextRange; const AStyle: TFormatStyle): TArray<TCodeAction>;
var
  Action: TCodeAction;
begin
  Result := ForFindings(AFindings, AText, ARange);
  if TCodeActions.TryFinally(AText, ATree, ARange, AStyle, Action) then
    Result := Result + [Action];
end;

end.
