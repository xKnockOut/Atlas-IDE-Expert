unit Atlas.Common.Editing.GuardFree;

// Freigabe absichern (#489): Nach "Liste := TStringList.Create;" bietet die
// Vervollständigung an, den folgenden Code in try…finally mit Freigabe
// einzuschließen. Hier stehen die Prüfung und die Änderung ohne Protokollbezug.
//
// Angeboten wird nur, wenn
//   - die Variable lokal ist (var-Abschnitt der Routine oder Inline-Variable)
//     und ihr deklarierter Typ nicht wie ein Interface aussieht (IFoo),
//   - der erzeugte Typ laut Namensauflösung keine Record- oder Interface-Art
//     ist und kein Owner übergeben wird (Self, Application, Owner, AOwner bzw.
//     bei TComponent-Nachfahren jedes Argument außer nil),
//   - die Variable im Rest der Routine weder freigegeben noch zurückgegeben,
//     zugewiesen oder an Add, Insert, Push, Enqueue, AddObject, AddPair bzw.
//     AddOrSetValue übergeben wird (eine Liste könnte sie besitzen),
//   - die nächste Zeile mit Inhalt nicht schon mit try beginnt.
// Wie bei TCodeActions.TryFinally (#42), aber vorsichtiger: Ein falsches
// Angebot gibt ein Objekt doppelt frei.
//
// Zwei Formen: nur eine neue Zeile im try (Standard) und, wenn die Anweisung
// direkt im Rumpf der Routine steht und danach noch Zeilen folgen, alles bis
// zum Ende der Routine im try. "$0" markiert die Cursorstelle danach.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Configuration.Contract;

type
  {$SCOPEDENUMS ON}
  /// <summary>Art des erzeugten Typs laut Namensauflösung.</summary>
  TGuardTypeKind = (Unknown, Class_, Component, Other);
  TGuardScope = (NewLine, ToRoutineEnd);
  {$SCOPEDENUMS OFF}

  /// <summary>Art des Typs ATypeName (ohne generische Argumente).</summary>
  TGuardTypeKindFunc = reference to function(const ATypeName: string): TGuardTypeKind;

  TGuardOffer = record
    Variable: string;
    /// <summary>Erzeugter Typ ohne generische Argumente.</summary>
    TypeName: string;
    Line: Integer;
    Indent: string;
    /// <summary>Zeile des end, das den Rumpf der Routine schließt.</summary>
    EndLine: Integer;
    /// <summary>Bis zum Routinenende einschließen ist möglich: Die Anweisung steht direkt im Rumpf, dahinter
    /// folgen Zeilen mit Inhalt, und das end steht am Anfang seiner Zeile.</summary>
    CanEnclose: Boolean;
  end;

  TGuardFree = class
  public
    /// <summary>Passt Zeile ALine für das Angebot? AKindOf darf nil sein.</summary>
    class function Check(ATree: TSyntaxTree; const AText: string; ALine: Integer; const AKindOf: TGuardTypeKindFunc;
      out AOffer: TGuardOffer): Boolean; static;
    /// <summary>Änderung für AScope; im Text steht "$0" an der Cursorstelle.</summary>
    class function Edit(const AText: string; const AOffer: TGuardOffer; AScope: TGuardScope;
      AStyle: TCompletionFreeStyle): TRuleEdit; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Documents.Contract;

function SplitLines(const AText: string): TArray<string>;
var
  Index: Integer;
begin
  Result := AText.Split([#10]);
  for Index := 0 to High(Result) do
    if EndsStr(#13, Result[Index]) then
      Result[Index] := Copy(Result[Index], 1, Length(Result[Index]) - 1);
end;

function LineBreakOf(const AText: string): string;
begin
  if Pos(#13#10, AText) > 0 then
    Result := #13#10
  else
    Result := #10;
end;

/// <summary>Innerste Routine mit Rumpf, deren begin…end Zeile ALine enthält; nil sonst.</summary>
function RoutineAt(ANode: TSyntaxNode; ALine: Integer): TSyntaxNode;
var
  Index: Integer;
  Block, Inner: TSyntaxNode;
begin
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if (ANode[Index].StartPos.Line > ALine) or (ANode[Index].EndPos.Line < ALine) then
      Continue;
    if ANode[Index].Kind = TSyntaxKind.RoutineDecl then
    begin
      Block := ANode[Index].FindChild(TSyntaxKind.Block);
      if (Block <> nil) and (Block.StartPos.Line < ALine) and (Block.EndPos.Line > ALine) then
        Result := ANode[Index];
    end;
    Inner := RoutineAt(ANode[Index], ALine);
    if Inner <> nil then
      Exit(Inner);
  end;
end;

/// <summary>Typ hinter dem Doppelpunkt einer Deklaration "A, B: T = …;"; '' ohne.</summary>
function TypeOfDecl(const AText: string; ANode: TSyntaxNode): string;
var
  Source: string;
  Colon, Stop: Integer;
begin
  Source := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  Colon := Pos(':', Source);
  if (Colon = 0) or (Copy(Source, Colon, 2) = ':=') then
    Exit('');
  Result := Copy(Source, Colon + 1, MaxInt);
  Stop := Pos(':=', Result);
  if Stop = 0 then
    Stop := Pos('=', Result);
  if Stop > 0 then
    Result := Copy(Result, 1, Stop - 1);
  Result := Trim(StringReplace(Result, ';', '', [rfReplaceAll]));
end;

function HasName(const ANames, AName: string): Boolean;
var
  Name: string;
begin
  for Name in SplitString(ANames, ',') do
    if SameText(Trim(Name), AName) then
      Exit(True);
  Result := False;
end;

/// <summary>Deklarierter Typ der lokalen Variable AName in ARoutine vor ALine; False, wenn sie nicht lokal ist.</summary>
function LocalType(ANode: TSyntaxNode; const AText, AName: string; ALine: Integer; out AType: string): Boolean;
var
  Index, Inner: Integer;
  Child: TSyntaxNode;
  Nested: string;
begin
  Result := False;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.StartPos.Line > ALine then
      Break;
    case Child.Kind of
      TSyntaxKind.VarSection:
        for Inner := 0 to Child.ChildCount - 1 do
          if (Child[Inner].Kind = TSyntaxKind.VarDecl) and HasName(Child[Inner].Name, AName) then
          begin
            AType := TypeOfDecl(AText, Child[Inner]);
            Result := True;
          end;
      TSyntaxKind.InlineVar:
        if HasName(Child.Name, AName) then
        begin
          AType := TypeOfDecl(AText, Child);
          Result := True;
        end;
      // Verschachtelte Routinen haben eigene Variablen.
      TSyntaxKind.RoutineDecl:
        ;
    else
      // Eigene Variable: out leert das Argument schon beim Aufruf.
      if LocalType(Child, AText, AName, ALine, Nested) then
      begin
        AType := Nested;
        Result := True;
      end;
    end;
  end;
end;

/// <summary>Erstes Argument auf oberster Ebene aus "(A, B(C, D))"; '' ohne.</summary>
function FirstArgument(const AArgs: string): string;
var
  Index, Depth: Integer;
begin
  Result := Trim(AArgs);
  if not StartsStr('(', Result) then
    Exit('');
  Result := Copy(Result, 2, Length(Result) - 2);
  Depth := 0;
  for Index := 1 to Length(Result) do
    case Result[Index] of
      '(', '[':
        Inc(Depth);
      ')', ']':
        Dec(Depth);
      ',':
        if Depth = 0 then
          Exit(Trim(Copy(Result, 1, Index - 1)));
    end;
  Result := Trim(Result);
end;

/// <summary>Steht die Anweisung in Zeile ALine direkt im Rumpf von ABlock (nicht in if, with usw.)?</summary>
function TopLevel(ABlock: TSyntaxNode; ALine: Integer): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to ABlock.ChildCount - 1 do
    if ABlock[Index].StartPos.Line = ALine then
      Exit(True);
  Result := False;
end;

class function TGuardFree.Check(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  const AKindOf: TGuardTypeKindFunc; out AOffer: TGuardOffer): Boolean;
const
  Owners: array[0..3] of string = ('Self', 'Application', 'Owner', 'AOwner');
var
  Lines: TArray<string>;
  Match: TMatch;
  Routine, Block: TSyntaxNode;
  Name, DeclaredType, Argument, Rest, Escaped, Next: string;
  Kind: TGuardTypeKind;
  Index: Integer;
begin
  AOffer := Default(TGuardOffer);
  Result := False;
  Lines := SplitLines(AText);
  if (ATree = nil) or (ATree.Root = nil) or (ALine < 0) or (ALine > High(Lines)) then
    Exit;
  // Einrückung, "var ", Name, ": Typ", Klasse, Konstruktor, Argumente. Leere Alternativen halten jede Gruppe belegt.
  Match := TRegEx.Match(Lines[ALine], '^(\s*)(var\s+|)(\w+)\s*(:[^:=]+|):=\s*([A-Za-z_][\w.]*)(<[^;()]*>|)\s*\.\s*' +
    '(Create\w*)\s*(\(.*\)|)\s*;\s*(//.*|)$', [roIgnoreCase]);
  if not Match.Success then
    Exit;
  Name := Match.Groups[3].Value;
  if SameText(Name, 'Result') or SameText(Name, 'Self') then
    Exit;
  Routine := RoutineAt(ATree.Root, ALine);
  if Routine = nil then
    Exit;
  Block := Routine.FindChild(TSyntaxKind.Block);
  // Lokal: Inline-Variable in dieser Zeile, sonst var-Abschnitt oder frühere Inline-Variable der Routine.
  if Match.Groups[2].Value <> '' then
    DeclaredType := Trim(Copy(Match.Groups[4].Value, 2, MaxInt))
  else if not LocalType(Routine, AText, Name, ALine - 1, DeclaredType) then
    Exit;
  if TRegEx.IsMatch(DeclaredType, '^I[A-Z]') then
    Exit;
  AOffer.TypeName := Match.Groups[5].Value;
  if Assigned(AKindOf) then
    Kind := AKindOf(AOffer.TypeName)
  else
    Kind := TGuardTypeKind.Unknown;
  if Kind = TGuardTypeKind.Other then
    Exit;
  // Owner übernimmt die Freigabe.
  Argument := FirstArgument(Match.Groups[8].Value);
  if MatchText(Argument, Owners) then
    Exit;
  if (Kind = TGuardTypeKind.Component) and (Argument <> '') and not SameText(Argument, 'nil') then
    Exit;
  // Schon geschützt: Die nächste Zeile mit Inhalt beginnt mit try.
  for Index := ALine + 1 to High(Lines) do
  begin
    Next := Trim(Lines[Index]);
    if Next = '' then
      Continue;
    if TRegEx.IsMatch(Next, '^try\b', [roIgnoreCase]) then
      Exit;
    Break;
  end;
  // Rest der Routine: freigegeben, zurückgegeben, zugewiesen oder an eine Liste übergeben?
  Rest := '';
  for Index := ALine + 1 to Min(Block.EndPos.Line, High(Lines)) do
    Rest := Rest + Lines[Index] + #10;
  Escaped := TRegEx.Escape(Name);
  if TRegEx.IsMatch(Rest, '\b' + Escaped + '\s*\.\s*(Free|DisposeOf|Destroy)\b', [roIgnoreCase]) or
    TRegEx.IsMatch(Rest, '\bFreeAndNil\s*\(\s*' + Escaped + '\s*\)', [roIgnoreCase]) or
    TRegEx.IsMatch(Rest, ':=\s*' + Escaped + '\s*[;)]', [roIgnoreCase]) or
    TRegEx.IsMatch(Rest, '\.\s*(Add|Insert|Push|Enqueue|AddObject|AddPair|AddOrSetValue)\s*\(([^;]*[^\w.])?' +
      Escaped + '\s*[,)]', [roIgnoreCase]) then
    Exit;
  AOffer.Variable := Name;
  AOffer.Line := ALine;
  AOffer.Indent := Match.Groups[1].Value;
  AOffer.EndLine := Block.EndPos.Line;
  AOffer.CanEnclose := TopLevel(Block, ALine) and (AOffer.EndLine <= High(Lines)) and
    TRegEx.IsMatch(Lines[AOffer.EndLine], '^\s*end\b', [roIgnoreCase]);
  if AOffer.CanEnclose then
  begin
    AOffer.CanEnclose := False;
    for Index := ALine + 1 to AOffer.EndLine - 1 do
      if Trim(Lines[Index]) <> '' then
        AOffer.CanEnclose := True;
  end;
  Result := True;
end;

class function TGuardFree.Edit(const AText: string; const AOffer: TGuardOffer; AScope: TGuardScope;
  AStyle: TCompletionFreeStyle): TRuleEdit;
var
  Lines: TArray<string>;
  LB, Indent, Release, Body: string;
  Index, Last: Integer;
begin
  Lines := SplitLines(AText);
  LB := LineBreakOf(AText);
  Indent := AOffer.Indent;
  if AStyle = TCompletionFreeStyle.FreeAndNil then
    Release := 'FreeAndNil(' + AOffer.Variable + ');'
  else
    Release := AOffer.Variable + '.Free;';
  if AScope = TGuardScope.NewLine then
    Exit(TRuleEdit.Create(TTextRange.Create(AOffer.Line, Length(Lines[AOffer.Line]), AOffer.Line,
      Length(Lines[AOffer.Line])), LB + Indent + 'try' + LB + Indent + '  $0' + LB + Indent + 'finally' + LB +
      Indent + '  ' + Release + LB + Indent + 'end;'));
  // Bis zum Routinenende: die Zeilen dazwischen um zwei Zeichen einrücken, Cursor hinter die letzte.
  Last := AOffer.Line;
  for Index := AOffer.Line + 1 to AOffer.EndLine - 1 do
    if Trim(Lines[Index]) <> '' then
      Last := Index;
  Body := '';
  for Index := AOffer.Line + 1 to AOffer.EndLine - 1 do
  begin
    if Trim(Lines[Index]) <> '' then
      Body := Body + '  ' + Lines[Index];
    if Index = Last then
      Body := Body + '$0';
    Body := Body + LB;
  end;
  Result := TRuleEdit.Create(TTextRange.Create(AOffer.Line, Length(Lines[AOffer.Line]), AOffer.EndLine, 0),
    LB + Indent + 'try' + LB + Body + Indent + 'finally' + LB + Indent + '  ' + Release + LB + Indent + 'end;' + LB);
end;

end.
