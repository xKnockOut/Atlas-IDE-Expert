unit BDLsp.Common.Editing.UsesClause;

// uses-Listen lesen und ergänzen (#180), ohne Protokollbezug.
//
// - Abschnitt: in einer Unit interface oder implementation, je nachdem, wo der
//   Cursor steht; in Programmen und Packages die uses nach dem Kopf.
// - Gibt es dort schon ein uses, kommt der Name vor dessen Semikolon; steht die
//   Liste über mehrere Zeilen, in eine eigene Zeile mit gleicher Einrückung.
//   Sonst entsteht hinter dem Abschnittswort ein neues uses.
// - Eine Unit gilt als eingebunden, wenn sie in einem der beiden uses steht,
//   auch ohne Namespace-Präfix (SysUtils für System.SysUtils, wenn "System"
//   zu den Namespaces des Projekts gehört).

interface

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Rules.Contract;

type
  TUsesClauses = class
  public
    /// <summary>Alle Unit-Namen aus den uses-Listen (interface und implementation).</summary>
    class function UsedUnits(const ATokens: TArray<TPascalToken>): TArray<string>; static;
    /// <summary>Name der eigenen Unit bzw. des Programms; '' wenn unbekannt.</summary>
    class function OwnName(const ATokens: TArray<TPascalToken>): string; static;
    /// <summary>True, wenn AUnitName eingebunden ist, auch über einen der Namespaces.</summary>
    class function IsUsed(const AUsed: TArray<string>; const AUnitName: string;
      const ANamespaces: TArray<string>): Boolean; static;
    /// <summary>Edit, das AUnitName in das uses des Abschnitts an AOffset einträgt;
    /// False, wenn kein passender Abschnitt gefunden wird.</summary>
    class function AddUnit(const ATokens: TArray<TPascalToken>; AOffset: Integer; const AUnitName: string;
      const ALineBreak: string; out AEdit: TRuleEdit): Boolean; static;
  end;

implementation

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

/// <summary>Index des Semikolons, das die Anweisung ab AIndex abschließt; -1 ohne.</summary>
function SemicolonAfter(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while Result <= High(ATokens) do
  begin
    if ATokens[Result].IsSymbol(';') then
      Exit;
    Inc(Result);
  end;
  Result := -1;
end;

/// <summary>Erstes Token (nicht Trivia); -1 bei leerem Text.</summary>
function FirstIndex(const ATokens: TArray<TPascalToken>): Integer;
begin
  Result := NextIndex(ATokens, -1);
  if Result > High(ATokens) then
    Result := -1;
end;

/// <summary>Index des Abschnittsworts (interface/implementation) bzw. des Semikolons
/// hinter dem Programmkopf; -1, wenn nicht vorhanden.</summary>
function SectionStart(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  First, HeaderEnd, Index, Interface_, Implementation_: Integer;
begin
  Result := -1;
  First := FirstIndex(ATokens);
  if First < 0 then
    Exit;
  HeaderEnd := SemicolonAfter(ATokens, First);
  if HeaderEnd < 0 then
    Exit;
  if not ATokens[First].IsKeyword('unit') then
    // program, library, package: ein uses (bzw. contains) hinter dem Kopf.
    Exit(HeaderEnd);
  Interface_ := NextIndex(ATokens, HeaderEnd);
  if (Interface_ > High(ATokens)) or not ATokens[Interface_].IsKeyword('interface') then
    Exit;
  Implementation_ := -1;
  for Index := Interface_ + 1 to High(ATokens) do
    if ATokens[Index].IsKeyword('implementation') then
    begin
      Implementation_ := Index;
      Break;
    end;
  if (Implementation_ >= 0) and (AOffset >= ATokens[Implementation_].Offset) then
    Result := Implementation_
  else
    Result := Interface_;
end;

function ReadNames(const ATokens: TArray<TPascalToken>; AUses: Integer; var ANames: TArray<string>): Integer;
var
  Index: Integer;
  Name: string;
  AfterIn: Boolean;
begin
  // uses A, B.C in 'b.pas', D; liefert den Index des Semikolons.
  Index := AUses + 1;
  Name := '';
  AfterIn := False;
  while Index <= High(ATokens) do
  begin
    if ATokens[Index].IsSymbol(';') or ATokens[Index].IsSymbol(',') then
    begin
      if Name <> '' then
        ANames := ANames + [Name];
      Name := '';
      AfterIn := False;
      if ATokens[Index].IsSymbol(';') then
        Exit(Index);
    end
    else if ATokens[Index].IsKeyword('in') then
      AfterIn := True
    else if not AfterIn and ((ATokens[Index].Kind = TPascalTokenKind.Identifier) or ATokens[Index].IsSymbol('.')) then
      Name := Name + ATokens[Index].Text;
    Inc(Index);
  end;
  Result := -1;
end;

{ TUsesClauses }

class function TUsesClauses.UsedUnits(const ATokens: TArray<TPascalToken>): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  Index := 0;
  while Index <= High(ATokens) do
  begin
    if ATokens[Index].IsKeyword('uses') or ATokens[Index].IsKeyword('requires') then
    begin
      Index := ReadNames(ATokens, Index, Result);
      if Index < 0 then
        Exit;
    end;
    Inc(Index);
  end;
end;

class function TUsesClauses.OwnName(const ATokens: TArray<TPascalToken>): string;
var
  First, HeaderEnd, Index: Integer;
begin
  Result := '';
  First := FirstIndex(ATokens);
  if First < 0 then
    Exit;
  HeaderEnd := SemicolonAfter(ATokens, First);
  if HeaderEnd < 0 then
    Exit;
  for Index := First + 1 to HeaderEnd - 1 do
    if (ATokens[Index].Kind = TPascalTokenKind.Identifier) or ATokens[Index].IsSymbol('.') then
      Result := Result + ATokens[Index].Text
    else if not IsTrivia(ATokens[Index]) then
      Break;
end;

class function TUsesClauses.IsUsed(const AUsed: TArray<string>; const AUnitName: string;
  const ANamespaces: TArray<string>): Boolean;
var
  Used, Namespace: string;
begin
  for Used in AUsed do
  begin
    if SameText(Used, AUnitName) then
      Exit(True);
    for Namespace in ANamespaces do
      if SameText(Namespace + '.' + Used, AUnitName) then
        Exit(True);
  end;
  Result := False;
end;

class function TUsesClauses.AddUnit(const ATokens: TArray<TPascalToken>; AOffset: Integer;
  const AUnitName, ALineBreak: string; out AEdit: TRuleEdit): Boolean;
var
  Start, UsesIndex, Semicolon, LastName: Integer;
  Names: TArray<string>;
  Indent: string;
begin
  Start := SectionStart(ATokens, AOffset);
  if Start < 0 then
    Exit(False);
  UsesIndex := NextIndex(ATokens, Start);
  if (UsesIndex <= High(ATokens)) and (ATokens[UsesIndex].IsKeyword('uses')) then
  begin
    Names := nil;
    Semicolon := ReadNames(ATokens, UsesIndex, Names);
    if Semicolon < 0 then
      Exit(False);
    LastName := Semicolon - 1;
    while (LastName > UsesIndex) and IsTrivia(ATokens[LastName]) do
      Dec(LastName);
    if ATokens[LastName].StartPos.Line > ATokens[UsesIndex].StartPos.Line then
    begin
      // Mehrzeilige Liste: eigene Zeile, eingerückt wie die Zeile des letzten Eintrags.
      while (LastName > UsesIndex) and (ATokens[LastName - 1].StartPos.Line = ATokens[LastName].StartPos.Line) do
        Dec(LastName);
      Indent := StringOfChar(' ', ATokens[LastName].StartPos.Character);
      AEdit := TRuleEdit.Create(TTextRange.Create(ATokens[Semicolon].StartPos, ATokens[Semicolon].StartPos),
        ',' + ALineBreak + Indent + AUnitName);
    end
    else
      AEdit := TRuleEdit.Create(TTextRange.Create(ATokens[Semicolon].StartPos, ATokens[Semicolon].StartPos),
        ', ' + AUnitName);
    Exit(True);
  end;
  AEdit := TRuleEdit.Create(TTextRange.Create(ATokens[Start].EndPos, ATokens[Start].EndPos),
    ALineBreak + ALineBreak + 'uses' + ALineBreak + '  ' + AUnitName + ';');
  Result := True;
end;

end.
