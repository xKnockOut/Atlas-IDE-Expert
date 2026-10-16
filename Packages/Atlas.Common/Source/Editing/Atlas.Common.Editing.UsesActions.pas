unit Atlas.Common.Editing.UsesActions;

// uses-Aktionen (#284), ohne Protokollbezug: ungenutzte Units entfernen,
// Units ins implementation-uses verschieben und fehlende Units vorschlagen.
//
// - Eine Unit gilt als benutzt, wenn ein Bezeichner außerhalb der uses-Listen
//   einem ihrer interface-Symbole (auch Mitgliedern) oder dem letzten Teil
//   ihres Namens gleicht. Das ist großzügig: lieber eine Unit stehen lassen
//   als eine benötigte entfernen.
// - Nie entfernt werden Units, die der Index nicht kennt, Units mit
//   initialization/finalization (Registrierungen, Treiber, Testfixtures),
//   Units aus "usesKeep" und Einträge in Listen mit {$IFDEF} oder Kommentaren.
// - Verschoben wird eine interface-Unit, deren Symbole nur im implementation-
//   Teil vorkommen, sofern das implementation-uses schlicht ist.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Was der Index über eine Unit weiß.</summary>
  TUsesUnitInfo = record
    Known: Boolean;
    HasInitialization: Boolean;
    /// <summary>Namen der interface-Symbole, auch Mitglieder.</summary>
    Names: TArray<string>;
  end;

  TUsesUnitInfoFunc = reference to function(const AUnitName: string): TUsesUnitInfo;

  /// <summary>Units, deren interface ein Symbol AName auf Unit-Ebene deklariert.</summary>
  TUnitsDeclaringFunc = reference to function(const AName: string): TArray<string>;

  /// <summary>Alles, was die uses-Aktionen für ein Dokument brauchen.</summary>
  TUsesContext = record
    Info: TUsesUnitInfoFunc;
    Declaring: TUnitsDeclaringFunc;
    /// <summary>Einstellung "usesKeep".</summary>
    Keep: TArray<string>;
    /// <summary>Unit-Namespaces des Projekts (System für SysUtils).</summary>
    Namespaces: TArray<string>;
  end;

  TUsesActions = class
  public
    /// <summary>Entfernbare Units in Reihenfolge der uses-Listen.</summary>
    class function UnusedUnits(const ATokens: TArray<TPascalToken>; const AInfo: TUsesUnitInfoFunc;
      const AKeep: TArray<string>): TArray<string>; static;
    /// <summary>interface-Units, die nur im implementation-Teil gebraucht werden.</summary>
    class function MovableUnits(const ATokens: TArray<TPascalToken>; const AInfo: TUsesUnitInfoFunc): TArray<string>; static;
    /// <summary>Edits, die AUnits aus allen schlichten Listen streichen.</summary>
    class function RemoveUnits(const ATokens: TArray<TPascalToken>; const AText: string;
      const AUnits: TArray<string>; const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Edits, die AUnits aus dem interface- ins implementation-uses verschieben.</summary>
    class function MoveUnits(const ATokens: TArray<TPascalToken>; const AText: string;
      const AUnits: TArray<string>; const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Units, die den Bezeichner an APosition deklarieren und noch nicht eingebunden sind.
    /// Leer, wenn dort kein Bezeichner steht, er im Dokument deklariert wird oder eine
    /// eingebundene Unit ihn schon liefert.</summary>
    class function MissingUnits(const ATokens: TArray<TPascalToken>; ATree: TSyntaxTree;
      const APosition: TTextPosition; const ADeclaring: TUnitsDeclaringFunc;
      const ANamespaces: TArray<string>): TArray<string>; static;
    /// <summary>Edits, die AUnits ins uses eintragen (#777, „In uses aufnehmen“): ins interface, wenn der
    /// interface-Teil schon ein Symbol nennt, das die Unit auf Unit-Ebene deklariert (ADeclaring), sonst ins
    /// implementation-uses (bei
    /// Programmen ins einzige uses). Schon eingebundene Units (auch über Namespaces), doppelte Namen und
    /// die eigene Unit entfallen; AAdded nennt die eingetragenen. False ohne Edit.</summary>
    class function AddUnits(const ATokens: TArray<TPascalToken>; const AUnits: TArray<string>;
      const ADeclaring: TUnitsDeclaringFunc; const ANamespaces: TArray<string>; const ALineBreak: string;
      out AEdits: TArray<TTextEdit>; out AAdded: TArray<string>): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  Atlas.Common.Editing.UsesClause;

const
  InInterfacePart = 1;
  InImplementationPart = 2;

function Bare(const AIdentifier: string): string;
begin
  if (AIdentifier <> '') and (AIdentifier[1] = '&') then
    Result := Copy(AIdentifier, 2, MaxInt)
  else
    Result := AIdentifier;
end;

function ContainsText_(const ANames: TArray<string>; const AName: string): Boolean;
var
  Name: string;
begin
  for Name in ANames do
    if SameText(Name, AName) then
      Exit(True);
  Result := False;
end;

/// <summary>Bezeichner außerhalb der uses-Listen mit Bitmaske des Teils (interface/implementation).</summary>
function CollectIdentifiers(const ATokens: TArray<TPascalToken>;
  const AClauses: TArray<TUsesClauseInfo>): TDictionary<string, Integer>;
var
  Index, ClauseIndex, Part, Mask: Integer;
  IsUnit: Boolean;
  Key: string;
begin
  Result := TDictionary<string, Integer>.Create;
  IsUnit := False;
  for Index := 0 to High(ATokens) do
    if not (ATokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      IsUnit := ATokens[Index].IsKeyword('unit');
      Break;
    end;
  if IsUnit then
    Part := InInterfacePart
  else
    Part := InImplementationPart;
  ClauseIndex := 0;
  Index := 0;
  while Index <= High(ATokens) do
  begin
    if (ClauseIndex <= High(AClauses)) and (Index = AClauses[ClauseIndex].UsesIndex) then
    begin
      Index := AClauses[ClauseIndex].Semicolon + 1;
      Inc(ClauseIndex);
      Continue;
    end;
    if ATokens[Index].IsKeyword('implementation') then
      Part := InImplementationPart
    else if ATokens[Index].Kind = TPascalTokenKind.Identifier then
    begin
      Key := LowerCase(Bare(ATokens[Index].Text));
      if not Result.TryGetValue(Key, Mask) then
        Mask := 0;
      Result.AddOrSetValue(Key, Mask or Part);
    end;
    Inc(Index);
  end;
end;

/// <summary>Teile (Bitmaske), in denen die Unit benutzt wird.</summary>
function UsageOf(const AUnitName: string; const AInfo: TUsesUnitInfo;
  AIdentifiers: TDictionary<string, Integer>): Integer;
var
  Name: string;
  Mask: Integer;
begin
  Result := 0;
  // Qualifizierter Zugriff wie SysUtils.Format oder System.SysUtils.Format.
  if AIdentifiers.TryGetValue(LowerCase(Copy(AUnitName, LastDelimiter('.', AUnitName) + 1, MaxInt)), Mask) then
    Result := Result or Mask;
  for Name in AInfo.Names do
    if AIdentifiers.TryGetValue(LowerCase(Name), Mask) then
    begin
      Result := Result or Mask;
      if Result = InInterfacePart or InImplementationPart then
        Exit;
    end;
end;

class function TUsesActions.UnusedUnits(const ATokens: TArray<TPascalToken>; const AInfo: TUsesUnitInfoFunc;
  const AKeep: TArray<string>): TArray<string>;
var
  Clauses: TArray<TUsesClauseInfo>;
  Clause: TUsesClauseInfo;
  Identifiers: TDictionary<string, Integer>;
  Name: string;
  Info: TUsesUnitInfo;
begin
  Result := nil;
  Clauses := TUsesClauses.Clauses(ATokens);
  Identifiers := CollectIdentifiers(ATokens, Clauses);
  try
    for Clause in Clauses do
      if Clause.Plain then
        for Name in Clause.Names do
        begin
          if ContainsText_(AKeep, Name) or ContainsText_(Result, Name) then
            Continue;
          Info := AInfo(Name);
          if Info.Known and not Info.HasInitialization and (UsageOf(Name, Info, Identifiers) = 0) then
            Result := Result + [Name];
        end;
  finally
    Identifiers.Free;
  end;
end;

class function TUsesActions.MovableUnits(const ATokens: TArray<TPascalToken>;
  const AInfo: TUsesUnitInfoFunc): TArray<string>;
var
  Clauses: TArray<TUsesClauseInfo>;
  Clause: TUsesClauseInfo;
  Identifiers: TDictionary<string, Integer>;
  Name: string;
  Info: TUsesUnitInfo;
begin
  Result := nil;
  Clauses := TUsesClauses.Clauses(ATokens);
  // Ein implementation-uses mit Direktiven fassen wir nicht an.
  for Clause in Clauses do
    if not Clause.InInterface and not Clause.Plain then
      Exit;
  Identifiers := CollectIdentifiers(ATokens, Clauses);
  try
    for Clause in Clauses do
      if Clause.InInterface and Clause.Plain then
        for Name in Clause.Names do
        begin
          Info := AInfo(Name);
          // Initialisierungsreihenfolge kann zählen; solche Units bleiben, wo sie sind.
          if Info.Known and not Info.HasInitialization and (UsageOf(Name, Info, Identifiers) = InImplementationPart) then
            Result := Result + [Name];
        end;
  finally
    Identifiers.Free;
  end;
end;

class function TUsesActions.RemoveUnits(const ATokens: TArray<TPascalToken>; const AText: string;
  const AUnits: TArray<string>; const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean;
var
  Options: TUsesRewrite;
begin
  AEdits := nil;
  if AUnits = nil then
    Exit(False);
  Options := Default(TUsesRewrite);
  Options.Drop := AUnits;
  Result := TUsesClauses.Rewrite(ATokens, AText, Options, ALineBreak, AEdits);
end;

class function TUsesActions.MoveUnits(const ATokens: TArray<TPascalToken>; const AText: string;
  const AUnits: TArray<string>; const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean;
var
  Index, Implementation_: Integer;
  Added: TTextEdit;
begin
  AEdits := nil;
  if AUnits = nil then
    Exit(False);
  Implementation_ := -1;
  for Index := 0 to High(ATokens) do
    if ATokens[Index].IsKeyword('implementation') then
    begin
      Implementation_ := Index;
      Break;
    end;
  if (Implementation_ < 0) or not RemoveUnits(ATokens, AText, AUnits, ALineBreak, AEdits) or
    not TUsesClauses.AddUnit(ATokens, ATokens[Implementation_].Offset + 1, string.Join(', ', AUnits),
    ALineBreak, Added) then
  begin
    AEdits := nil;
    Exit(False);
  end;
  AEdits := AEdits + [Added];
  Result := True;
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function IsDeclaredIn(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
  Part: string;
begin
  if ANode.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl, TSyntaxKind.Field,
    TSyntaxKind.PropertyDecl, TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader, TSyntaxKind.Parameter,
    TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
    for Part in ANode.Name.Split([',', '.']) do
      if SameText(Bare(Trim(Part)), AName) then
        Exit(True);
  // Aufzählungswerte stehen als Bezeichner im EnumType.
  if (ANode.Kind = TSyntaxKind.Identifier) and (ANode.Parent <> nil) and
    (ANode.Parent.Kind = TSyntaxKind.EnumType) and SameText(ANode.Name, AName) then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if IsDeclaredIn(ANode[Index], AName) then
      Exit(True);
  Result := False;
end;

class function TUsesActions.MissingUnits(const ATokens: TArray<TPascalToken>; ATree: TSyntaxTree;
  const APosition: TTextPosition; const ADeclaring: TUnitsDeclaringFunc;
  const ANamespaces: TArray<string>): TArray<string>;
var
  Index, Previous: Integer;
  Name, Candidate, Own: string;
  Used, Candidates: TArray<string>;
begin
  Result := nil;
  Index := -1;
  for Previous := 0 to High(ATokens) do
    if (ATokens[Previous].Kind = TPascalTokenKind.Identifier) and not Before(APosition, ATokens[Previous].StartPos) and
      not Before(ATokens[Previous].EndPos, APosition) then
    begin
      Index := Previous;
      Break;
    end;
  if Index < 0 then
    Exit;
  // Nach einem Punkt ist es ein Mitglied oder ein qualifizierter Name.
  Previous := Index - 1;
  while (Previous >= 0) and (ATokens[Previous].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Dec(Previous);
  if (Previous >= 0) and ATokens[Previous].IsSymbol('.') then
    Exit;
  Name := Bare(ATokens[Index].Text);
  if (ATree <> nil) and IsDeclaredIn(ATree.Root, Name) then
    Exit;
  Candidates := ADeclaring(Name);
  if Candidates = nil then
    Exit;
  Used := TUsesClauses.UsedUnits(ATokens);
  Own := TUsesClauses.OwnName(ATokens);
  for Candidate in Candidates do
    if SameText(Candidate, Own) or TUsesClauses.IsUsed(Used, Candidate, ANamespaces) then
      Exit(nil);
  for Candidate in Candidates do
    if not ContainsText_(Result, Candidate) then
      Result := Result + [Candidate];
end;

class function TUsesActions.AddUnits(const ATokens: TArray<TPascalToken>; const AUnits: TArray<string>;
  const ADeclaring: TUnitsDeclaringFunc; const ANamespaces: TArray<string>; const ALineBreak: string;
  out AEdits: TArray<TTextEdit>; out AAdded: TArray<string>): Boolean;
var
  Used, ForInterface, ForImplementation, InterfaceNeeds: TArray<string>;
  Identifiers: TDictionary<string, Integer>;
  Pair: TPair<string, Integer>;
  Name, Own: string;
  Index, InterfaceOffset, ImplementationOffset: Integer;
  Edit: TTextEdit;
begin
  AEdits := nil;
  AAdded := nil;
  Used := TUsesClauses.UsedUnits(ATokens);
  Own := TUsesClauses.OwnName(ATokens);
  ForInterface := nil;
  ForImplementation := nil;
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
  // Units, die Bezeichner des interface-Teils deklarieren.
  InterfaceNeeds := nil;
  if (InterfaceOffset >= 0) and (ImplementationOffset >= 0) and Assigned(ADeclaring) then
  begin
    Identifiers := CollectIdentifiers(ATokens, TUsesClauses.Clauses(ATokens));
    try
      for Pair in Identifiers do
        if Pair.Value and InInterfacePart <> 0 then
          for Name in ADeclaring(Pair.Key) do
            if ContainsText_(AUnits, Name) and not ContainsText_(InterfaceNeeds, Name) then
              InterfaceNeeds := InterfaceNeeds + [Name];
    finally
      Identifiers.Free;
    end;
  end;
  for Name in AUnits do
  begin
    if (Trim(Name) = '') or SameText(Name, Own) or ContainsText_(AAdded, Name) or
      TUsesClauses.IsUsed(Used, Name, ANamespaces) then
      Continue;
    if ContainsText_(InterfaceNeeds, Name) or (ImplementationOffset < 0) then
      ForInterface := ForInterface + [Name]
    else
      ForImplementation := ForImplementation + [Name];
    AAdded := AAdded + [Name];
  end;
  // Ein Edit je Abschnitt; Programme und Units ohne implementation haben nur ein uses.
  if (Length(ForInterface) > 0) and TUsesClauses.AddUnit(ATokens, Max(0, InterfaceOffset),
    string.Join(', ', ForInterface), ALineBreak, Edit) then
    AEdits := AEdits + [Edit];
  if (Length(ForImplementation) > 0) and TUsesClauses.AddUnit(ATokens, ImplementationOffset,
    string.Join(', ', ForImplementation), ALineBreak, Edit) then
    AEdits := AEdits + [Edit];
  Result := Length(AEdits) > 0;
  if not Result then
    AAdded := nil;
end;

end.
