unit Atlas.Common.Editing.UnitRename;

// uses nachziehen nach dem Umbenennen einer Unit (#512): Änderungen an einer
// Datei, die den alten Namen noch verwendet.
//   - Einträge im uses (nicht contains/requires): alter Name → neuer Name.
//     Steht der neue Name schon im uses, entfällt der alte Eintrag. Einträge
//     mit Pfad ("Alt in 'Alt.pas'") pflegt die IDE selbst und bleiben.
//   - Qualifizierte Bezeichner Alt.TKlasse → Neu.TKlasse, außer die Datei
//     deklariert selbst etwas mit dem alten Namen (dann meint Alt.X dieses).
//   - Der Kopf der umbenannten Datei selbst ("unit Alt;"), wenn die IDE ihn
//     nicht angepasst hat.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TUnitRename = class
  public
    /// <summary>Unit-Name zu einer Datei: Dateiname ohne Endung; '' für andere als .pas.</summary>
    class function UnitNameOf(const AFileName: string): string; static;
    /// <summary>Änderungen in AText (Datei AFileName), die AOldName durch ANewName ersetzen; False ohne.</summary>
    class function Edits(const AFileName, AText: string; ATree: TSyntaxTree; const AOldName, ANewName: string;
      out AEdits: TArray<TTextEdit>): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.UsesClause;

function CleanName(const AName: string): string;
begin
  Result := AName;
  if Result.StartsWith('&') then
    Result := Result.Substring(1);
end;

function Contains(const AList: TArray<string>; const AName: string): Boolean;
var
  Item: string;
begin
  for Item in AList do
    if SameText(Item, AName) then
      Exit(True);
  Result := False;
end;

/// <summary>Deklariert die Datei einen Namen AName (Typ, Variable, Feld, Parameter, Routine …)?</summary>
function Declares(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Wanted: string;
begin
  Wanted := AName;
  // Search statt Rekursion (Bericht M1).
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    var
      Name: string;
    begin
      Result := TSyntaxSearchStep.Descend;
      if ACandidate.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl, TSyntaxKind.Field,
        TSyntaxKind.PropertyDecl, TSyntaxKind.Parameter, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst,
        TSyntaxKind.RoutineHeader] then
        for Name in ACandidate.Name.Split([',']) do
          if SameText(CleanName(Trim(Name)), Wanted) then
            Exit(TSyntaxSearchStep.Found);
    end) <> nil;
end;

/// <summary>Stehen ab AIndex die Teile von AParts (A . B . C)? AEnd: Index des letzten Teils.</summary>
function Matches(const ATokens: TArray<TPascalToken>; AIndex: Integer; const AParts: TArray<string>;
  out AEnd: Integer): Boolean;
var
  Part, Index: Integer;
begin
  Result := False;
  Index := AIndex;
  AEnd := -1;
  for Part := 0 to High(AParts) do
  begin
    if Part > 0 then
    begin
      Index := TRoutineBody.NextToken(ATokens, Index);
      if (Index > High(ATokens)) or not ATokens[Index].IsSymbol('.') then
        Exit;
      Index := TRoutineBody.NextToken(ATokens, Index);
    end;
    if (Index > High(ATokens)) or (ATokens[Index].Kind <> TPascalTokenKind.Identifier) or
      not SameText(CleanName(ATokens[Index].Text), AParts[Part]) then
      Exit;
  end;
  AEnd := Index;
  Result := True;
end;

class function TUnitRename.UnitNameOf(const AFileName: string): string;
begin
  Result := '';
  if SameText(ExtractFileExt(AFileName), '.pas') then
    Result := ChangeFileExt(ExtractFileName(AFileName), '');
end;

class function TUnitRename.Edits(const AFileName, AText: string; ATree: TSyntaxTree; const AOldName,
  ANewName: string; out AEdits: TArray<TTextEdit>): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Lines: TLineTable;
  Clauses: TArray<TUsesClauseInfo>;
  Clause: TUsesClauseInfo;
  Reference: TUsesReference;
  Parts: TArray<string>;
  Index, Last, Next, Previous, HeaderEnd, Offset: Integer;
  InUses, HasNew: Boolean;
  Options: TUsesRewrite;
  Dropped: TArray<TTextEdit>;
  LineBreak: string;
begin
  AEdits := nil;
  if (ATree = nil) or (AOldName = '') or (ANewName = '') or SameText(AOldName, ANewName) then
    Exit(False);
  Tokens := ATree.Tokens;
  Lines := TLineTable.Build(AText);
  LineBreak := TTextLines.LineBreakOf(AText);
  Parts := AOldName.Split(['.']);
  // Kopf der umbenannten Datei.
  HeaderEnd := -1;
  Index := TRoutineBody.NextToken(Tokens, -1);
  if (Index <= High(Tokens)) and Tokens[Index].IsKeyword('unit') then
  begin
    Next := TRoutineBody.NextToken(Tokens, Index);
    if (Next <= High(Tokens)) and Matches(Tokens, Next, Parts, Last) then
    begin
      HeaderEnd := Tokens[Last].Offset;
      if SameText(UnitNameOf(AFileName), ANewName) then
        AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Tokens[Next].StartPos, Tokens[Last].EndPos),
          ANewName)];
    end;
  end;
  // uses-Einträge.
  Clauses := TUsesClauses.Clauses(Tokens);
  HasNew := Contains(TUsesClauses.UsedUnits(Tokens), ANewName);
  if HasNew then
  begin
    Options := Default(TUsesRewrite);
    Options.Drop := [AOldName];
    if TUsesClauses.Rewrite(Tokens, AText, Options, LineBreak, Dropped) then
      AEdits := AEdits + Dropped;
  end
  else
    for Reference in TUsesClauses.References(Tokens) do
    begin
      if not SameText(Reference.Name, AOldName) then
        Continue;
      Offset := Lines.OffsetAt(Reference.Range.StartPos);
      InUses := False;
      for Clause in Clauses do
        if (Offset > Tokens[Clause.UsesIndex].Offset) and (Offset < Tokens[Clause.Semicolon].Offset) then
          InUses := True;
      if not InUses then
        Continue;
      // "Alt in 'Alt.pas'" pflegt die IDE.
      Next := TRoutineBody.NextToken(Tokens, TRoutineBody.TokenAt(Tokens, Lines.OffsetAt(Reference.Range.EndPos)) - 1);
      if (Next <= High(Tokens)) and Tokens[Next].IsKeyword('in') then
        Continue;
      AEdits := AEdits + [TTextEdit.Create(Reference.Range, ANewName)];
    end;
  // Qualifizierte Bezeichner, sofern die Datei den Namen nicht selbst deklariert.
  if not Declares(ATree.Root, Parts[0]) then
    for Index := TSyntaxTree.FirstTokenOf(Tokens, HeaderEnd + 1) to High(Tokens) do
    begin
      if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or (Tokens[Index].Offset <= HeaderEnd) or
        not SameText(CleanName(Tokens[Index].Text), Parts[0]) then
        Continue;
      InUses := False;
      for Clause in Clauses do
        if (Tokens[Index].Offset > Tokens[Clause.UsesIndex].Offset) and
          (Tokens[Index].Offset < Tokens[Clause.Semicolon].Offset) then
          InUses := True;
      if InUses then
        Continue;
      Previous := TRoutineBody.PreviousToken(Tokens, Index);
      if (Previous >= 0) and Tokens[Previous].IsSymbol('.') then
        Continue;
      if not Matches(Tokens, Index, Parts, Last) then
        Continue;
      Next := TRoutineBody.NextToken(Tokens, Last);
      if (Next > High(Tokens)) or not Tokens[Next].IsSymbol('.') then
        Continue;
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Last].EndPos),
        ANewName)];
    end;
  Result := AEdits <> nil;
end;

end.
