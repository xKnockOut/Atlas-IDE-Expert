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
  Atlas.Common.Editing.Contract;

type
  /// <summary>Ein nicht auflösbarer Bezeichner und die Units, die ihn deklarieren.</summary>
  TSmartPasteName = record
    Name: string;
    Units: TArray<string>;
  end;

  /// <summary>interface-uses einer Unit (aus dem Index); nil, wenn unbekannt.</summary>
  TInterfaceUsesFunc = reference to function(const AUnitName: string): TArray<string>;

  /// <summary>Ziel der Einfügung für TSmartPaste.UsesEdits.</summary>
  TSmartPasteTarget = record
    Tokens: TArray<TPascalToken>;
    /// <summary>Einfügestelle; entscheidet zwischen interface- und implementation-uses.</summary>
    Position: TTextPosition;
    /// <summary>interface-uses anderer Units (Kreisverweise); nil, wenn unbekannt.</summary>
    InterfaceUses: TInterfaceUsesFunc;
    Namespaces: TArray<string>;
    LineBreak: string;
  end;

  /// <summary>Ergebnis von TSmartPaste.UsesEdits.</summary>
  TSmartPasteUses = record
    Edits: TArray<TTextEdit>;
    /// <summary>Die eingetragenen Units.</summary>
    Added: TArray<string>;
    /// <summary>Die wegen Kreisverweis ins implementation-uses verlegten Units.</summary>
    ToImplementation: TArray<string>;
  end;

  TSmartPaste = class
  public
    /// <summary>Fehlende Bezeichner in ARange (Ende ausschließlich); ohne ADeclaring leer.</summary>
    class function Missing(const ATokens: TArray<TPascalToken>; ATree: TSyntaxTree; const ARange: TTextRange;
      const ADeclaring: TUnitsDeclaringFunc; const ANamespaces: TArray<string>): TArray<TSmartPasteName>; static;
    /// <summary>Units mit genau einem Kandidaten, ohne Doppelte.</summary>
    class function Certain(const ANames: TArray<TSmartPasteName>): TArray<string>; static;
    /// <summary>Liegt APosition zwischen interface und implementation?</summary>
    class function InInterface(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Boolean; static;
    /// <summary>Edits, die AUnits an der richtigen Stelle von ATarget eintragen. False ohne Edit.</summary>
    class function UsesEdits(const ATarget: TSmartPasteTarget; const AUnits: TArray<string>;
      out AUses: TSmartPasteUses): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Editing.UsesActions,
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
  begin
    Result := Result.Substring(1);
  end;
end;

function Contains(const ANames: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TSmartPaste }

class function TSmartPaste.Missing(const ATokens: TArray<TPascalToken>; ATree: TSyntaxTree;
  const ARange: TTextRange; const ADeclaring: TUnitsDeclaringFunc;
  const ANamespaces: TArray<string>): TArray<TSmartPasteName>;
var
  mClauses: TArray<TUsesClauseInfo>;
  mIndex: Integer;
  mToken: TPascalToken;
  mSeen: TArray<string>;
  mName: string;
  mItem: TSmartPasteName;
begin
  Result := nil;
  if not Assigned(ADeclaring) then
  begin
    Exit;
  end;
  mClauses := TUsesClauses.Clauses(ATokens);
  mSeen := nil;
  for mIndex := 0 to High(ATokens) do
  begin
    mToken := ATokens[mIndex];
    if (mToken.Kind <> TPascalTokenKind.Identifier) or Before(mToken.StartPos, ARange.StartPos) or
      Before(ARange.EndPos, mToken.EndPos) then
    begin
      Continue;
    end;
    mName := Bare(mToken.Text);
    if Contains(mSeen, mName) then
    begin
      Continue;
    end;
    mSeen := mSeen + [mName];
    // Eingefügte uses-Einträge sind keine Bezeichner, die fehlen.
    if TUsesClauses.InClause(ATokens, mClauses, mToken.Offset) then
    begin
      Continue;
    end;
    mItem.Name := mName;
    mItem.Units := TUsesActions.MissingUnits(ATokens, ATree, mToken.StartPos, ADeclaring, ANamespaces);
    if mItem.Units <> nil then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class function TSmartPaste.Certain(const ANames: TArray<TSmartPasteName>): TArray<string>;
var
  mItem: TSmartPasteName;
begin
  Result := nil;
  for mItem in ANames do
  begin
    if (Length(mItem.Units) = 1) and not Contains(Result, mItem.Units[0]) then
    begin
      Result := Result + [mItem.Units[0]];
    end;
  end;
end;

class function TSmartPaste.InInterface(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Boolean;
var
  mToken: TPascalToken;
  mSeen: Boolean;
begin
  mSeen := False;
  for mToken in ATokens do
  begin
    if Before(APosition, mToken.StartPos) then
    begin
      Break;
    end;
    if mToken.IsKeyword('interface') then
    begin
      mSeen := True;
    end
    else if mToken.IsKeyword('implementation') then
    begin
      Exit(False);
    end;
  end;
  Result := mSeen;
end;

/// <summary>Offsets von interface und implementation; -1, wo das Wort fehlt.</summary>
procedure SectionOffsets(const ATokens: TArray<TPascalToken>; out AInterface, AImplementation: Integer);
var
  mIndex: Integer;
begin
  AInterface := -1;
  AImplementation := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('interface') and (AInterface < 0) then
    begin
      AInterface := ATokens[mIndex].Offset;
    end
    else if ATokens[mIndex].IsKeyword('implementation') then
    begin
      AImplementation := ATokens[mIndex].Offset;
      Break;
    end;
  end;
end;

type
  /// <summary>Verteilt Units auf interface- und implementation-uses.</summary>
  TUsesSplit = record
    ForInterface: TArray<string>;
    ForImplementation: TArray<string>;
    /// <summary>Einfügestelle im interface (bzw. im einzigen uses ohne implementation).</summary>
    Upper: Boolean;
    /// <summary>Kreisverweise sind möglich: implementation vorhanden, interface-uses bekannt, Name bekannt.</summary>
    CheckCycles: Boolean;
    Own: string;
    procedure Add(const AName: string; const AInterfaceUses: TInterfaceUsesFunc; var AUses: TSmartPasteUses);
  end;

procedure TUsesSplit.Add(const AName: string; const AInterfaceUses: TInterfaceUsesFunc;
  var AUses: TSmartPasteUses);
begin
  if Upper and CheckCycles and Contains(AInterfaceUses(AName), Own) then
  begin
    ForImplementation := ForImplementation + [AName];
    AUses.ToImplementation := AUses.ToImplementation + [AName];
  end
  else if Upper then
  begin
    ForInterface := ForInterface + [AName];
  end
  else
  begin
    ForImplementation := ForImplementation + [AName];
  end;
  AUses.Added := AUses.Added + [AName];
end;

/// <summary>Trägt AUnits (durch Komma getrennt) über TUsesClauses.AddUnit beim Abschnitt an AOffset ein.</summary>
procedure AddUnitsEdit(const ATarget: TSmartPasteTarget; AOffset: Integer; const AUnits: TArray<string>;
  var AEdits: TArray<TTextEdit>);
var
  mEdit: TTextEdit;
begin
  if (Length(AUnits) > 0) and TUsesClauses.AddUnit(ATarget.Tokens, AOffset, string.Join(', ', AUnits),
    ATarget.LineBreak, mEdit) then
  begin
    AEdits := AEdits + [mEdit];
  end;
end;

class function TSmartPaste.UsesEdits(const ATarget: TSmartPasteTarget; const AUnits: TArray<string>;
  out AUses: TSmartPasteUses): Boolean;
var
  mUsed: TArray<string>;
  mName: string;
  mInterfaceOffset, mImplementationOffset: Integer;
  mSplit: TUsesSplit;
begin
  AUses := Default(TSmartPasteUses);
  mUsed := TUsesClauses.UsedUnits(ATarget.Tokens);
  mSplit := Default(TUsesSplit);
  mSplit.Own := TUsesClauses.OwnName(ATarget.Tokens);
  SectionOffsets(ATarget.Tokens, mInterfaceOffset, mImplementationOffset);
  // Ohne implementation (Programm, Paket) gibt es nur ein uses.
  mSplit.Upper := (mImplementationOffset < 0) or InInterface(ATarget.Tokens, ATarget.Position);
  mSplit.CheckCycles := (mImplementationOffset >= 0) and Assigned(ATarget.InterfaceUses) and (mSplit.Own <> '');
  for mName in AUnits do
  begin
    if (Trim(mName) <> '') and not SameText(mName, mSplit.Own) and not Contains(AUses.Added, mName) and
      not TUsesClauses.IsUsed(mUsed, mName, ATarget.Namespaces) then
    begin
      mSplit.Add(mName, ATarget.InterfaceUses, AUses);
    end;
  end;
  AddUnitsEdit(ATarget, Max(0, mInterfaceOffset), mSplit.ForInterface, AUses.Edits);
  AddUnitsEdit(ATarget, mImplementationOffset, mSplit.ForImplementation, AUses.Edits);
  Result := Length(AUses.Edits) > 0;
  if not Result then
  begin
    AUses := Default(TSmartPasteUses);
  end;
end;

end.
