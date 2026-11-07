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
  begin
    Result := Result.Substring(1);
  end;
end;

function Contains(const AList: TArray<string>; const AName: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SameText(mItem, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Deklariert die Datei einen Namen AName (Typ, Variable, Feld, Parameter, Routine …)?</summary>
function Declares(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mWanted: string;
begin
  mWanted := AName;
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
      begin
        for Name in ACandidate.Name.Split([',']) do
        begin
          if SameText(CleanName(Trim(Name)), mWanted) then
          begin
            Exit(TSyntaxSearchStep.Found);
          end;
        end;
      end;
    end) <> nil;
end;

/// <summary>Stehen ab AIndex die Teile von AParts (A . B . C)? AEnd: Index des letzten Teils.</summary>
function Matches(const ATokens: TArray<TPascalToken>; AIndex: Integer; const AParts: TArray<string>;
  out AEnd: Integer): Boolean;
var
  mPart, mIndex: Integer;
begin
  Result := False;
  mIndex := AIndex;
  AEnd := -1;
  for mPart := 0 to High(AParts) do
  begin
    if mPart > 0 then
    begin
      mIndex := TRoutineBody.NextToken(ATokens, mIndex);
      if (mIndex > High(ATokens)) or not ATokens[mIndex].IsSymbol('.') then
      begin
        Exit;
      end;
      mIndex := TRoutineBody.NextToken(ATokens, mIndex);
    end;
    if (mIndex > High(ATokens)) or (ATokens[mIndex].Kind <> TPascalTokenKind.Identifier) or
      not SameText(CleanName(ATokens[mIndex].Text), AParts[mPart]) then
    begin
      Exit;
    end;
  end;
  AEnd := mIndex;
  Result := True;
end;

class function TUnitRename.UnitNameOf(const AFileName: string): string;
begin
  Result := '';
  if SameText(ExtractFileExt(AFileName), '.pas') then
  begin
    Result := ChangeFileExt(ExtractFileName(AFileName), '');
  end;
end;

/// <summary>Kopf "unit Alt;" der umbenannten Datei an ANewName anpassen, wenn die Datei schon so heißt.
/// Liefert den Offset des letzten Namensteils im Kopf, -1 ohne passenden Kopf.</summary>
function HeaderEdits(const AFileName: string; const ATokens: TArray<TPascalToken>; const AParts: TArray<string>;
  const ANewName: string; var AEdits: TArray<TTextEdit>): Integer;
var
  mIndex, mNext, mLast: Integer;
begin
  Result := -1;
  mIndex := TRoutineBody.NextToken(ATokens, -1);
  if (mIndex > High(ATokens)) or not ATokens[mIndex].IsKeyword('unit') then
  begin
    Exit;
  end;
  mNext := TRoutineBody.NextToken(ATokens, mIndex);
  if (mNext <= High(ATokens)) and Matches(ATokens, mNext, AParts, mLast) then
  begin
    Result := ATokens[mLast].Offset;
    if SameText(TUnitRename.UnitNameOf(AFileName), ANewName) then
    begin
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(ATokens[mNext].StartPos, ATokens[mLast].EndPos),
        ANewName)];
    end;
  end;
end;

/// <summary>Steht AReference in einer uses-Klausel ohne "in 'Datei.pas'" (den Pfad pflegt die IDE)?</summary>
function IsPlainUsesEntry(const ATokens: TArray<TPascalToken>; const ALines: TLineTable;
  const AClauses: TArray<TUsesClauseInfo>; const AReference: TUsesReference): Boolean;
var
  mNext: Integer;
begin
  Result := False;
  if not TUsesClauses.InClause(ATokens, AClauses, ALines.OffsetAt(AReference.Range.StartPos)) then
  begin
    Exit;
  end;
  mNext := TRoutineBody.NextToken(ATokens, TRoutineBody.TokenAt(ATokens,
    ALines.OffsetAt(AReference.Range.EndPos)) - 1);
  Result := (mNext > High(ATokens)) or not ATokens[mNext].IsKeyword('in');
end;

/// <summary>uses-Einträge: alter Name → neuer Name; steht der neue Name schon im uses, entfällt der alte.</summary>
function UsesEdits(const AText: string; const ATokens: TArray<TPascalToken>;
  const AClauses: TArray<TUsesClauseInfo>; const AOldName, ANewName: string): TArray<TTextEdit>;
var
  mLines: TLineTable;
  mReference: TUsesReference;
  mOptions: TUsesRewrite;
begin
  Result := nil;
  if Contains(TUsesClauses.UsedUnits(ATokens), ANewName) then
  begin
    mOptions := Default(TUsesRewrite);
    mOptions.Drop := [AOldName];
    if not TUsesClauses.Rewrite(ATokens, AText, mOptions, TTextLines.LineBreakOf(AText), Result) then
    begin
      Result := nil;
    end;
    Exit;
  end;
  mLines := TLineTable.Build(AText);
  for mReference in TUsesClauses.References(ATokens) do
  begin
    if SameText(mReference.Name, AOldName) and IsPlainUsesEntry(ATokens, mLines, AClauses, mReference) then
    begin
      Result := Result + [TTextEdit.Create(mReference.Range, ANewName)];
    end;
  end;
end;

/// <summary>Beginnt an AIndex ein qualifizierter Bezeichner Alt.X außerhalb von uses? ALast: letzter Teil von
/// Alt.</summary>
function QualifiedAt(const ATokens: TArray<TPascalToken>; const AClauses: TArray<TUsesClauseInfo>;
  const AParts: TArray<string>; AIndex: Integer; out ALast: Integer): Boolean;
var
  mPrevious, mNext: Integer;
begin
  ALast := -1;
  Result := False;
  if (ATokens[AIndex].Kind <> TPascalTokenKind.Identifier) or
    not SameText(CleanName(ATokens[AIndex].Text), AParts[0]) or
    TUsesClauses.InClause(ATokens, AClauses, ATokens[AIndex].Offset) then
  begin
    Exit;
  end;
  mPrevious := TRoutineBody.PreviousToken(ATokens, AIndex);
  if ((mPrevious >= 0) and ATokens[mPrevious].IsSymbol('.')) or not Matches(ATokens, AIndex, AParts, ALast) then
  begin
    Exit;
  end;
  mNext := TRoutineBody.NextToken(ATokens, ALast);
  Result := (mNext <= High(ATokens)) and ATokens[mNext].IsSymbol('.');
end;

/// <summary>Qualifizierte Bezeichner Alt.X → Neu.X hinter dem Kopf (Offset AHeaderEnd).</summary>
function QualifiedEdits(const ATokens: TArray<TPascalToken>; const AClauses: TArray<TUsesClauseInfo>;
  const AParts: TArray<string>; AHeaderEnd: Integer; const ANewName: string): TArray<TTextEdit>;
var
  mIndex, mLast: Integer;
begin
  Result := nil;
  for mIndex := TSyntaxTree.FirstTokenOf(ATokens, AHeaderEnd + 1) to High(ATokens) do
  begin
    if (ATokens[mIndex].Offset > AHeaderEnd) and QualifiedAt(ATokens, AClauses, AParts, mIndex, mLast) then
    begin
      Result := Result + [TTextEdit.Create(TTextRange.Create(ATokens[mIndex].StartPos, ATokens[mLast].EndPos),
        ANewName)];
    end;
  end;
end;

class function TUnitRename.Edits(const AFileName, AText: string; ATree: TSyntaxTree; const AOldName,
  ANewName: string; out AEdits: TArray<TTextEdit>): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mClauses: TArray<TUsesClauseInfo>;
  mParts: TArray<string>;
  mHeaderEnd: Integer;
begin
  AEdits := nil;
  if (ATree = nil) or (AOldName = '') or (ANewName = '') or SameText(AOldName, ANewName) then
  begin
    Exit(False);
  end;
  mTokens := ATree.Tokens;
  mParts := AOldName.Split(['.']);
  mHeaderEnd := HeaderEdits(AFileName, mTokens, mParts, ANewName, AEdits);
  mClauses := TUsesClauses.Clauses(mTokens);
  AEdits := AEdits + UsesEdits(AText, mTokens, mClauses, AOldName, ANewName);
  // Qualifizierte Bezeichner, sofern die Datei den Namen nicht selbst deklariert.
  if not Declares(ATree.Root, mParts[0]) then
  begin
    AEdits := AEdits + QualifiedEdits(mTokens, mClauses, mParts, mHeaderEnd, ANewName);
  end;
  Result := AEdits <> nil;
end;

end.
