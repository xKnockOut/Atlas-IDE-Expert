unit Atlas.Common.Editing.SmartPaste;

// Einfügen mit uses-Ergänzung (#515), Server-Kern ohne Protokollbezug:
// - Missing: Bezeichner im eingefügten Bereich, die in der Ziel-Unit nicht
//   auflösbar sind und die eine noch nicht eingebundene Unit auf Unit-Ebene
//   deklariert (dieselbe Prüfung wie der Quick-Fix aus #284: nicht nach einem
//   Punkt, nicht im Dokument deklariert, keine Kandidat-Unit schon im uses).
//   Je Name einmal, in Reihenfolge des ersten Vorkommens; ein Name mit
//   mehreren Kandidaten bleibt mehrdeutig, Atlas wählt dann nicht selbst.
// - UsesEdits trägt die gewählten Units ein: Liegt die Einfügestelle im
//   interface-Teil, ins interface-uses, sonst ins implementation-uses (bei
//   Programmen und Units ohne implementation ins einzige uses). Eine Unit,
//   deren interface-uses die Ziel-Unit nennt, käme im interface als
//   Kreisverweis: Sie geht ins implementation-uses. Schon eingebundene
//   Units (auch über Namespaces), doppelte und die eigene entfallen.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.UsesActions;

type
  /// <summary>Ein nicht auflösbarer Bezeichner und die Units, die ihn deklarieren.</summary>
  TSmartPasteName = record
    Name: string;
    Units: TArray<string>;
  end;

  /// <summary>interface-uses einer Unit (aus dem Index); nil, wenn unbekannt.</summary>
  TInterfaceUsesFunc = reference to function(const AUnitName: string): TArray<string>;

  TSmartPaste = class
  public
    /// <summary>Fehlende Bezeichner in ARange (Ende ausschließlich); ohne ADeclaring leer.</summary>
    class function Missing(const ATokens: TArray<TPascalToken>; ATree: TSyntaxTree; const ARange: TTextRange;
      const ADeclaring: TUnitsDeclaringFunc; const ANamespaces: TArray<string>): TArray<TSmartPasteName>; static;
    /// <summary>Units mit genau einem Kandidaten, ohne Doppelte.</summary>
    class function Certain(const ANames: TArray<TSmartPasteName>): TArray<string>; static;
    /// <summary>Liegt APosition zwischen interface und implementation?</summary>
    class function InInterface(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Boolean; static;
    /// <summary>Edits, die AUnits an der richtigen Stelle eintragen; AAdded nennt die eingetragenen, AToImplementation
    /// die wegen Kreisverweis ins implementation-uses verlegten. False ohne Edit.</summary>
    class function UsesEdits(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
      const AUnits: TArray<string>; const AInterfaceUses: TInterfaceUsesFunc; const ANamespaces: TArray<string>;
      const ALineBreak: string; out AEdits: TArray<TTextEdit>; out AAdded, AToImplementation: TArray<string>):
      Boolean; static;
  end;

implementation

uses
  System.Math,
  Atlas.Common.Editing.UsesClause;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function Bare(const AIdentifier: string): string;
begin
  Result := AIdentifier;
  if Result.StartsWith('&') then
    Result := Result.Substring(1);
end;

function Contains(const ANames: TArray<string>; const AName: string): Boolean;
var
  Name: string;
begin
  for Name in ANames do
    if SameText(Name, AName) then
      Exit(True);
  Result := False;
end;

{ TSmartPaste }

class function TSmartPaste.Missing(const ATokens: TArray<TPascalToken>; ATree: TSyntaxTree;
  const ARange: TTextRange; const ADeclaring: TUnitsDeclaringFunc;
  const ANamespaces: TArray<string>): TArray<TSmartPasteName>;
var
  Clauses: TArray<TUsesClauseInfo>;
  Clause: TUsesClauseInfo;
  Index: Integer;
  Token: TPascalToken;
  Seen: TArray<string>;
  Name: string;
  InUses: Boolean;
  Item: TSmartPasteName;
begin
  Result := nil;
  if not Assigned(ADeclaring) then
    Exit;
  Clauses := TUsesClauses.Clauses(ATokens);
  Seen := nil;
  for Index := 0 to High(ATokens) do
  begin
    Token := ATokens[Index];
    if (Token.Kind <> TPascalTokenKind.Identifier) or Before(Token.StartPos, ARange.StartPos) or
      Before(ARange.EndPos, Token.EndPos) then
      Continue;
    Name := Bare(Token.Text);
    if Contains(Seen, Name) then
      Continue;
    Seen := Seen + [Name];
    // Eingefügte uses-Einträge sind keine Bezeichner, die fehlen.
    InUses := False;
    for Clause in Clauses do
      if (Token.Offset > ATokens[Clause.UsesIndex].Offset) and (Token.Offset < ATokens[Clause.Semicolon].Offset) then
        InUses := True;
    if InUses then
      Continue;
    Item.Name := Name;
    Item.Units := TUsesActions.MissingUnits(ATokens, ATree, Token.StartPos, ADeclaring, ANamespaces);
    if Item.Units <> nil then
      Result := Result + [Item];
  end;
end;

class function TSmartPaste.Certain(const ANames: TArray<TSmartPasteName>): TArray<string>;
var
  Item: TSmartPasteName;
begin
  Result := nil;
  for Item in ANames do
    if (Length(Item.Units) = 1) and not Contains(Result, Item.Units[0]) then
      Result := Result + [Item.Units[0]];
end;

class function TSmartPaste.InInterface(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Boolean;
var
  Token: TPascalToken;
  Seen: Boolean;
begin
  Seen := False;
  for Token in ATokens do
  begin
    if Before(APosition, Token.StartPos) then
      Break;
    if Token.IsKeyword('interface') then
      Seen := True
    else if Token.IsKeyword('implementation') then
      Exit(False);
  end;
  Result := Seen;
end;

class function TSmartPaste.UsesEdits(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
  const AUnits: TArray<string>; const AInterfaceUses: TInterfaceUsesFunc; const ANamespaces: TArray<string>;
  const ALineBreak: string; out AEdits: TArray<TTextEdit>; out AAdded, AToImplementation: TArray<string>): Boolean;
var
  Used, ForInterface, ForImplementation: TArray<string>;
  Own, Name: string;
  Index, InterfaceOffset, ImplementationOffset: Integer;
  Upper: Boolean;
  Edit: TTextEdit;
begin
  AEdits := nil;
  AAdded := nil;
  AToImplementation := nil;
  Used := TUsesClauses.UsedUnits(ATokens);
  Own := TUsesClauses.OwnName(ATokens);
  InterfaceOffset := -1;
  ImplementationOffset := -1;
  for Index := 0 to High(ATokens) do
    if ATokens[Index].IsKeyword('interface') and (InterfaceOffset < 0) then
      InterfaceOffset := ATokens[Index].Offset
    else if ATokens[Index].IsKeyword('implementation') then
    begin
      ImplementationOffset := ATokens[Index].Offset;
      Break;
    end;
  // Ohne implementation (Programm, Paket) gibt es nur ein uses.
  Upper := (ImplementationOffset < 0) or InInterface(ATokens, APosition);
  ForInterface := nil;
  ForImplementation := nil;
  for Name in AUnits do
  begin
    if (Trim(Name) = '') or SameText(Name, Own) or Contains(AAdded, Name) or
      TUsesClauses.IsUsed(Used, Name, ANamespaces) then
      Continue;
    if Upper and (ImplementationOffset >= 0) and Assigned(AInterfaceUses) and (Own <> '') and
      Contains(AInterfaceUses(Name), Own) then
    begin
      ForImplementation := ForImplementation + [Name];
      AToImplementation := AToImplementation + [Name];
    end
    else if Upper then
      ForInterface := ForInterface + [Name]
    else
      ForImplementation := ForImplementation + [Name];
    AAdded := AAdded + [Name];
  end;
  if (Length(ForInterface) > 0) and TUsesClauses.AddUnit(ATokens, Max(0, InterfaceOffset),
    string.Join(', ', ForInterface), ALineBreak, Edit) then
    AEdits := AEdits + [Edit];
  if (Length(ForImplementation) > 0) and TUsesClauses.AddUnit(ATokens, ImplementationOffset,
    string.Join(', ', ForImplementation), ALineBreak, Edit) then
    AEdits := AEdits + [Edit];
  Result := Length(AEdits) > 0;
  if not Result then
  begin
    AAdded := nil;
    AToImplementation := nil;
  end;
end;

end.
