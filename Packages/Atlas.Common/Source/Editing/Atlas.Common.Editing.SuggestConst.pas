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
  Atlas.Common.Semantics.ControlFlow,
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
  Atlas.Common.Editing.RoutineLocals;

function InlineAction(ATree: TSyntaxTree; const ASymbol: TReassignedSymbol; out AAction: TCodeAction): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Keyword, Assign: Integer;
begin
  Result := False;
  if not ASymbol.Initialized or (Pos(',', ASymbol.Decl.Name) > 0) then
    Exit;
  Tokens := ATree.Tokens;
  Keyword := TRoutineBody.TokenAt(Tokens, ASymbol.Decl.StartOffset);
  if (Keyword > High(Tokens)) or not Tokens[Keyword].IsKeyword('var') then
    Exit;
  Assign := Keyword;
  while (Assign <= High(Tokens)) and (Tokens[Assign].Offset < ASymbol.Decl.EndOffset) and
    not Tokens[Assign].IsSymbol(':=') do
    Inc(Assign);
  if (Assign > High(Tokens)) or (Tokens[Assign].Offset >= ASymbol.Decl.EndOffset) then
    Exit;
  AAction := Default(TCodeAction);
  AAction.Title := Format('Als Konstante deklarieren (const %s)', [ASymbol.Name]);
  AAction.Kind := RewriteKind;
  AAction.Edits := [TTextEdit.Create(TTextRange.Create(Tokens[Keyword].StartPos, Tokens[Keyword].EndPos), 'const'),
    TTextEdit.Create(TTextRange.Create(Tokens[Assign].StartPos, Tokens[Assign].EndPos), '=')];
  Result := True;
end;

function SectionAction(const AText: string; ATree: TSyntaxTree; const ASymbol: TReassignedSymbol;
  out AAction: TCodeAction): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Body, Statement: TSyntaxNode;
  Occurrence: TReassignedOccurrence;
  Assign: Integer;
  TypeText: string;
  Edits: TArray<TTextEdit>;
begin
  Result := False;
  Body := TRoutineBody.BodyOf(ASymbol.Routine);
  if Body = nil then
    Exit;
  Statement := nil;
  for Occurrence in ASymbol.Occurrences do
    if Occurrence.Write = TReassignedWrite.Write then
      Statement := Occurrence.Node.Parent;
  // Die eine Zuweisung muss eine Anweisung direkt im Rumpf sein.
  if (Statement = nil) or (Statement.Kind <> TSyntaxKind.AssignStatement) or (Statement.Parent <> Body) then
    Exit;
  for Occurrence in ASymbol.Occurrences do
    if Occurrence.Node <> nil then
      if (Occurrence.Offset < Body.StartOffset) or (Occurrence.Offset > Body.EndOffset) or
        ((Occurrence.Write = TReassignedWrite.None) and (Occurrence.Offset < Statement.EndOffset)) then
        Exit;
  TypeText := Trim(TRoutineLocals.TypeChildText(AText, ASymbol.Decl));
  if TypeText = '' then
    Exit;
  Tokens := ATree.Tokens;
  Assign := TRoutineBody.TokenAt(Tokens, Statement[0].EndOffset);
  while (Assign <= High(Tokens)) and (Tokens[Assign].Offset < Statement.EndOffset) and
    not Tokens[Assign].IsSymbol(':=') do
    Inc(Assign);
  if (Assign > High(Tokens)) or (Tokens[Assign].Offset >= Statement.EndOffset) then
    Exit;
  Edits := [TTextEdit.Create(TTextRange.Create(Statement.StartPos, Tokens[Assign].EndPos),
    Format('const %s: %s =', [ASymbol.Name, TypeText]))];
  TRoutineLocals.RemoveVariables(ATree, ASymbol.Decl, [ASymbol.Name], Edits);
  AAction := Default(TCodeAction);
  AAction.Title := Format('Als Konstante deklarieren (const %s)', [ASymbol.Name]);
  AAction.Kind := RewriteKind;
  AAction.Edits := Edits;
  Result := True;
end;

class function TSuggestConst.Action(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TFlowSignatureLookup; out AAction: TCodeAction): Boolean;
var
  Symbol: TReassignedSymbol;
begin
  AAction := Default(TCodeAction);
  Result := False;
  if (ATree = nil) or not TReassigned.SymbolAt(TReassigned.Analyze(AText, ATree, ALookup), APosition, Symbol) or
    not Symbol.IsConstCandidate then
    Exit;
  if Symbol.Kind = TReassignedKind.InlineVariable then
    Result := InlineAction(ATree, Symbol, AAction)
  else if Symbol.Decl.Kind = TSyntaxKind.VarDecl then
    Result := SectionAction(AText, ATree, Symbol, AAction);
end;

end.
