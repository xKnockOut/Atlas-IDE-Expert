unit Atlas.Common.Rules.CodeActions;

// Brücke von Regeltreffern zu Code-Aktionen (#42, #182): Korrekturen der Treffer,
// "Regel unterdrücken" und "Alle sicheren Korrekturen anwenden". In
// Editing.CodeActions bleiben TCodeAction und die Aktionen ohne Regelbezug,
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
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TCodeActionsText = (SuppressLine, SuppressFile, ApplyAllSafe);

const
  cTexts: array[TCodeActionsText] of TAtlasText = (
    (De: '"%s" für diese Zeile unterdrücken'; En: 'Suppress "%s" for this line'),
    (De: '"%s" für diese Datei unterdrücken'; En: 'Suppress "%s" for this file'),
    (De: 'Alle sicheren Korrekturen anwenden'; En: 'Apply all safe fixes'));

{$SCOPEDENUMS OFF}

function Overlaps(const A, B: TTextRange): Boolean;

  function Before(const AX, AY: TTextPosition): Boolean;
  begin
    Result := (AX.Line < AY.Line) or ((AX.Line = AY.Line) and (AX.Character <= AY.Character));
  end;

begin
  // Bereiche, die sich nur berühren, überlappen nicht.
  Result := not (Before(A.EndPos, B.StartPos) or Before(B.EndPos, A.StartPos));
end;

function FileEditsIndex(const AAction: TCodeAction; const AFileName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AAction.FileEdits) do
  begin
    if SameText(AAction.FileEdits[mIndex].FileName, AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure AddFileEdits(var AAction: TCodeAction; const AFileName: string; const AEdits: TArray<TTextEdit>);
var
  mIndex: Integer;
  mEntry: TFileTextEdits;
begin
  if AFileName = '' then
  begin
    AAction.Edits := AAction.Edits + AEdits;
    Exit;
  end;
  mIndex := FileEditsIndex(AAction, AFileName);
  if mIndex < 0 then
  begin
    mEntry.FileName := AFileName;
    mEntry.Edits := AEdits;
    AAction.FileEdits := AAction.FileEdits + [mEntry];
  end
  else
  begin
    AAction.FileEdits[mIndex].Edits := AAction.FileEdits[mIndex].Edits + AEdits;
  end;
end;

/// <summary>Edits der Korrektur in die Aktion: ins Dokument oder in die Datei der Korrektur (#309), dazu die
/// weiterer Dateien (#1105).</summary>
procedure AddFixEdits(var AAction: TCodeAction; const AFix: TRuleFix);
var
  mOther: TRuleFileEdits;
begin
  AddFileEdits(AAction, AFix.FileName, AFix.Edits);
  for mOther in AFix.OtherFiles do
  begin
    AddFileEdits(AAction, mOther.FileName, mOther.Edits);
  end;
end;

/// <summary>Schnellkorrektur zu AFix an AFinding; AFirst macht sie zur bevorzugten, wenn sie keine Alternative
/// ist.</summary>
function FixAction(const AFinding: TRuleFinding; const AFix: TRuleFix; AFirst: Boolean): TCodeAction;
begin
  Result := Default(TCodeAction);
  Result.Title := AFix.Title;
  Result.Kind := cQuickFixKind;
  AddFixEdits(Result, AFix);
  // Sprung zu einer anderen Stelle der Datei (#915), z. B. zur Freigabe; mit Parameter-Hint (#1007).
  if AFix.HasJump and AFix.OpensSignature then
  begin
    Result.Command := cShowSignatureHelpCommand;
  end
  else if AFix.HasJump then
  begin
    Result.Command := cGoToPositionCommand;
  end;
  if AFix.HasJump then
  begin
    Result.CommandArguments := [IntToStr(AFix.JumpTo.Line), IntToStr(AFix.JumpTo.Character)];
  end;
  // „Graph zeigen“ an einem Unit-Zyklus (#896): der Client öffnet die Unit-Beziehungen.
  if AFix.ShowsUnitRelations then
  begin
    Result.Command := cShowUnitRelationsCommand;
  end;
  Result.IsPreferred := AFirst and not AFix.Alternative;
  Result.RuleId := AFinding.RuleId;
  Result.DiagnosticRange := AFinding.Range;
  // Fenster „Atlas-Prüfung“ und Befund-Hover suchen die Schnellkorrektur über das Tag (#909).
  if Result.IsPreferred then
  begin
    Result.Tag := cRuleFixTag;
  end;
end;

/// <summary>"Für diese Zeile/Datei unterdrücken" zu AFinding. Syntaxfehler und Sprachmerkmale (#1126) laufen nicht
/// über die Engine, ein lsp-ignore wirkt dort nicht; Sprachmerkmale für neuere Versionen gehören in
/// {$IF CompilerVersion >= …}.</summary>
function SuppressActions(const AFinding: TRuleFinding; const AText: string): TArray<TCodeAction>;
var
  mAction: TCodeAction;
begin
  Result := nil;
  if MatchText(AFinding.RuleId, ['unused-suppression', 'syntax', 'language-feature']) then
  begin
    Exit;
  end;
  mAction := Default(TCodeAction);
  mAction.Title := cTexts[TCodeActionsText.SuppressLine].Fmt([AFinding.RuleId]);
  mAction.Kind := cQuickFixKind;
  mAction.Edits := [TCodeActions.SuppressLine(AText, AFinding.Range.StartPos.Line, AFinding.RuleId)];
  mAction.RuleId := AFinding.RuleId;
  mAction.DiagnosticRange := AFinding.Range;
  mAction.Tag := cRuleSuppressLineTag;
  Result := Result + [mAction];
  mAction.Title := cTexts[TCodeActionsText.SuppressFile].Fmt([AFinding.RuleId]);
  mAction.Edits := [TCodeActions.SuppressFile(AText, AFinding.RuleId)];
  mAction.Tag := cRuleSuppressFileTag;
  Result := Result + [mAction];
end;

{ TRuleCodeActions }

class function TRuleCodeActions.ForFindings(const AFindings: TArray<TRuleFinding>; const AText: string;
  const ARange: TTextRange): TArray<TCodeAction>;
var
  mFinding: TRuleFinding;
  mIndex: Integer;
begin
  Result := nil;
  for mFinding in AFindings do
  begin
    if (mFinding.Range.EndPos.Line >= ARange.StartPos.Line) and (mFinding.Range.StartPos.Line <= ARange.EndPos.Line)
      then
    begin
      for mIndex := 0 to High(mFinding.Fixes) do
      begin
        Result := Result + [FixAction(mFinding, mFinding.Fixes[mIndex], mIndex = 0)];
      end;
      Result := Result + SuppressActions(mFinding, AText);
    end;
  end;
end;

/// <summary>Die erste sichere Korrektur von AFinding, die nur das Dokument oder eine Datei ändert; Korrekturen
/// über mehrere Dateien (#1105) nie beim Speichern.</summary>
function FirstSafeFix(const AFinding: TRuleFinding; out AFix: TRuleFix): Boolean;
var
  mFix: TRuleFix;
begin
  Result := False;
  for mFix in AFinding.Fixes do
  begin
    if mFix.Safe and (mFix.OtherFiles = nil) then
    begin
      AFix := mFix;
      Exit(True);
    end;
  end;
end;

/// <summary>Schon gesammelte Änderungen an AFileName: das Dokument ('') oder z. B. die Formulardatei (#309).</summary>
function ExistingEdits(const AAction: TCodeAction; const AFileName: string): TArray<TTextEdit>;
var
  mTarget: Integer;
begin
  Result := nil;
  mTarget := FileEditsIndex(AAction, AFileName);
  if AFileName = '' then
  begin
    Result := AAction.Edits;
  end
  else if mTarget >= 0 then
  begin
    Result := AAction.FileEdits[mTarget].Edits;
  end;
end;

/// <summary>Überlappt keine Änderung aus AEdits eine aus AExisting?</summary>
function Fits(const AEdits, AExisting: TArray<TTextEdit>): Boolean;
var
  mEdit, mTaken: TTextEdit;
begin
  for mEdit in AEdits do
  begin
    for mTaken in AExisting do
    begin
      if Overlaps(mEdit.Range, mTaken.Range) then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := True;
end;

class function TRuleCodeActions.FixAll(const AFindings: TArray<TRuleFinding>; out AAction: TCodeAction): Boolean;
var
  mFinding: TRuleFinding;
  mFix: TRuleFix;
begin
  AAction := Default(TCodeAction);
  AAction.Title := cTexts[TCodeActionsText.ApplyAllSafe].Text;
  AAction.Kind := cFixAllKind;
  for mFinding in AFindings do
  begin
    // Eine Korrektur ganz oder gar nicht; die übersprungene kommt beim nächsten Lauf.
    if FirstSafeFix(mFinding, mFix) and Fits(mFix.Edits, ExistingEdits(AAction, mFix.FileName)) then
    begin
      AddFixEdits(AAction, mFix);
    end;
  end;
  Result := (AAction.Edits <> nil) or (AAction.FileEdits <> nil);
end;

class function TRuleCodeActions.ForRange(const AFindings: TArray<TRuleFinding>; const AText: string;
  const ARange: TTextRange): TArray<TCodeAction>;
var
  mAction: TCodeAction;
begin
  Result := ForFindings(AFindings, AText, ARange);
  if TCodeActions.TryFinally(AText, ARange.StartPos.Line, mAction) then
  begin
    Result := Result + [mAction];
  end;
end;

class function TRuleCodeActions.ForRange(const AFindings: TArray<TRuleFinding>; const AText: string;
  ATree: TSyntaxTree; const ARange: TTextRange; const AStyle: TFormatStyle): TArray<TCodeAction>;
var
  mAction: TCodeAction;
begin
  Result := ForFindings(AFindings, AText, ARange);
  if TCodeActions.TryFinally(AText, ATree, ARange, AStyle, mAction) then
  begin
    Result := Result + [mAction];
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.CodeActions', cTexts);

end.
