unit Atlas.Common.Editing.SuggestConst;

// Glühbirne „Als Konstante deklarieren“ (#712, refactoring.suggestConst): Eine
// lokale Variable, die genau einmal sicher geschrieben und nie womöglich
// geändert wird (TReassignedSymbol.IsConstCandidate), wird eine
// Inline-Konstante.
//   - var X := E; bzw. var X: T := E;  ->  const X = E; bzw. const X: T = E;
//   - X aus dem var-Abschnitt mit genau einer Zuweisung X := E; direkt im
//     Rumpf der Routine (nicht in einer Schleife oder Verzweigung), vor der
//     keine Stelle X liest: An der Zuweisung steht const X: T = E; mit dem
//     Typ aus dem var-Abschnitt (der Wert behält so seinen Typ), der Eintrag
//     im var-Abschnitt verschwindet. Nennt eine verschachtelte Routine X,
//     bleibt es bei der Variablen: Sie sähe die Inline-Konstante nicht.
// Ob die Sprachversion Inline-Konstanten kennt, prüft der Aufrufer.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow.Signatures,
  Atlas.Common.Editing.CodeActions;

type
  TSuggestConst = class
  public
    /// <summary>Aktion für den Namen an APosition; ALookup nennt die Übergabeart von Argumenten (nil: nur die
    /// Datei und die Standardroutinen). False, wenn er kein Kandidat ist.</summary>
    class function Action(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TFlowSignatureLookup; out AAction: TCodeAction): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.Reassigned,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSuggestConstText = (DeclareAsConstantConst);

const
  cTexts: array[TSuggestConstText] of TAtlasText = (
    (De: 'Als Konstante deklarieren (const %s)'; En: 'Declare as constant (const %s)'));

{$SCOPEDENUMS OFF}

function InlineAction(ATree: TSyntaxTree; const ASymbol: TReassignedSymbol; out AAction: TCodeAction): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mKeyword, mAssign: Integer;
begin
  Result := False;
  if not ASymbol.Initialized or (Pos(',', ASymbol.Decl.Name) > 0) then
  begin
    Exit;
  end;
  mTokens := ATree.Tokens;
  mKeyword := TRoutineBody.TokenAt(mTokens, ASymbol.Decl.StartOffset);
  if (mKeyword > High(mTokens)) or not mTokens[mKeyword].IsKeyword('var') then
  begin
    Exit;
  end;
  mAssign := mKeyword;
  while (mAssign <= High(mTokens)) and (mTokens[mAssign].Offset < ASymbol.Decl.EndOffset) and
    not mTokens[mAssign].IsSymbol(':=') do
  begin
    Inc(mAssign);
  end;
  if (mAssign > High(mTokens)) or (mTokens[mAssign].Offset >= ASymbol.Decl.EndOffset) then
  begin
    Exit;
  end;
  AAction := Default(TCodeAction);
  AAction.Title := cTexts[TSuggestConstText.DeclareAsConstantConst].Fmt([ASymbol.Name]);
  AAction.Kind := cRewriteKind;
  AAction.Edits := [TTextEdit.Create(TTextRange.Create(mTokens[mKeyword].StartPos, mTokens[mKeyword].EndPos), 'const'),
    TTextEdit.Create(TTextRange.Create(mTokens[mAssign].StartPos, mTokens[mAssign].EndPos), '=')];
  Result := True;
end;

/// <summary>Anweisung der (letzten) schreibenden Stelle von ASymbol; nil ohne.</summary>
function WritingStatement(const ASymbol: TReassignedSymbol): TSyntaxNode;
var
  mOccurrence: TReassignedOccurrence;
begin
  Result := nil;
  for mOccurrence in ASymbol.Occurrences do
  begin
    if mOccurrence.Write = TReassignedWrite.Write then
    begin
      Result := mOccurrence.Node.Parent;
    end;
  end;
end;

/// <summary>Liegen alle Stellen von ASymbol in ABody, und liest keine vor dem Ende von AStatement?</summary>
function OccurrencesAfter(const ASymbol: TReassignedSymbol; ABody, AStatement: TSyntaxNode): Boolean;
var
  mOccurrence: TReassignedOccurrence;
begin
  Result := True;
  for mOccurrence in ASymbol.Occurrences do
  begin
    if (mOccurrence.Node <> nil) and ((mOccurrence.Offset < ABody.StartOffset) or
      (mOccurrence.Offset > ABody.EndOffset) or ((mOccurrence.Write = TReassignedWrite.None) and
      (mOccurrence.Offset < AStatement.EndOffset))) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Die eine Zuweisung an ASymbol, wenn sie eine Anweisung direkt im Rumpf ist und keine Stelle davor
/// den Namen liest; sonst nil.</summary>
function ConstStatement(const ASymbol: TReassignedSymbol): TSyntaxNode;
var
  mBody: TSyntaxNode;
begin
  Result := nil;
  mBody := TRoutineBody.BodyOf(ASymbol.Routine);
  if mBody = nil then
  begin
    Exit;
  end;
  Result := WritingStatement(ASymbol);
  if (Result <> nil) and ((Result.Kind <> TSyntaxKind.AssignStatement) or (Result.Parent <> mBody) or
    not OccurrencesAfter(ASymbol, mBody, Result)) then
  begin
    Result := nil;
  end;
end;

function SectionAction(const AText: string; ATree: TSyntaxTree; const ASymbol: TReassignedSymbol;
  out AAction: TCodeAction): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mStatement: TSyntaxNode;
  mAssign: Integer;
  mTypeText: string;
  mEdits: TArray<TTextEdit>;
begin
  Result := False;
  mStatement := ConstStatement(ASymbol);
  if mStatement = nil then
  begin
    Exit;
  end;
  mTypeText := Trim(TRoutineLocals.TypeChildText(AText, ASymbol.Decl));
  if mTypeText = '' then
  begin
    Exit;
  end;
  mTokens := ATree.Tokens;
  mAssign := TRoutineBody.TokenAt(mTokens, mStatement[0].EndOffset);
  while (mAssign <= High(mTokens)) and (mTokens[mAssign].Offset < mStatement.EndOffset) and
    not mTokens[mAssign].IsSymbol(':=') do
  begin
    Inc(mAssign);
  end;
  if (mAssign > High(mTokens)) or (mTokens[mAssign].Offset >= mStatement.EndOffset) then
  begin
    Exit;
  end;
  mEdits := [TTextEdit.Create(TTextRange.Create(mStatement.StartPos, mTokens[mAssign].EndPos),
    Format('const %s: %s =', [ASymbol.Name, mTypeText]))];
  TRoutineLocals.RemoveVariables(ATree, ASymbol.Decl, [ASymbol.Name], mEdits);
  AAction := Default(TCodeAction);
  AAction.Title := cTexts[TSuggestConstText.DeclareAsConstantConst].Fmt([ASymbol.Name]);
  AAction.Kind := cRewriteKind;
  AAction.Edits := mEdits;
  Result := True;
end;

class function TSuggestConst.Action(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TFlowSignatureLookup; out AAction: TCodeAction): Boolean;
var
  mSymbol: TReassignedSymbol;
begin
  AAction := Default(TCodeAction);
  Result := False;
  if (ATree = nil) or not TReassigned.SymbolAt(TReassigned.Analyze(AText, ATree, ALookup), APosition, mSymbol) or
    not mSymbol.IsConstCandidate then
  begin
    Exit;
  end;
  if mSymbol.Kind = TReassignedKind.InlineVariable then
  begin
    Result := InlineAction(ATree, mSymbol, AAction);
  end
  else if mSymbol.Decl.Kind = TSyntaxKind.VarDecl then
  begin
    Result := SectionAction(AText, ATree, mSymbol, AAction);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.SuggestConst', cTexts);

end.
