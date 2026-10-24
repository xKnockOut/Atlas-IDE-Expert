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
// - Entries (#621) nennt je Eintrag, warum er im Editor auffällt: ungenutzt
//   (abgeblendet), ungenutzt, aber wegen initialization oder "usesKeep"
//   behalten, oder nur in der implementation gebraucht. Inaktive Zweige der
//   bedingten Kompilierung zählen dabei nicht, so werden auch Listen mit
//   {$IFDEF} geprüft. RemoveEntries streicht einzelne Einträge auch dort.

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

  {$SCOPEDENUMS ON}
  /// <summary>Warum ein uses-Eintrag im Editor auffällt (#621).</summary>
  TUsesEntryState = (
    /// <summary>Aus der Unit wird nichts verwendet: abblenden.</summary>
    Unused,
    /// <summary>Ungenutzt, aber mit initialization/finalization: bleibt.</summary>
    KeptForInitialization,
    /// <summary>Ungenutzt, aber in "usesKeep": bleibt.</summary>
    KeptByAllowlist,
    /// <summary>Steht im interface, gebraucht wird sie nur in der implementation.</summary>
    OnlyImplementation);
  {$SCOPEDENUMS OFF}

  /// <summary>Ein auffälliger uses-Eintrag mit Position des Namens (#621).</summary>
  TUsesEntry = record
    Name: string;
    Range: TTextRange;
    State: TUsesEntryState;
  end;

  TUsesActions = class
  public
    /// <summary>Auffällige Einträge der uses-Listen in Quelltextreihenfolge (#621). Token in AInactive
    /// (inaktive Zweige) zählen nicht: weder ihre Einträge noch ihre Bezeichner. Unbekannte Units entfallen,
    /// ebenso benutzte, die richtig stehen.</summary>
    class function Entries(const ATokens: TArray<TPascalToken>; const AInactive: TArray<TTextRange>;
      const AInfo: TUsesUnitInfoFunc; const AKeep: TArray<string>): TArray<TUsesEntry>; static;
    /// <summary>Ein Edit, das die Einträge an ARanges (Bereiche der Namen) streicht (#621), auch aus Listen mit
    /// Direktiven oder Kommentaren: mit dem Komma davor oder dahinter, der einzige Eintrag mit dem ganzen uses.
    /// False, wenn ein Bereich keinen Eintrag trifft oder das Komma nur über eine Direktive hinweg zu erreichen
    /// wäre.</summary>
    class function RemoveEntries(const AText: string; const ARanges: TArray<TTextRange>;
      out AEdit: TTextEdit): Boolean; static;
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
    /// <summary>Edits, die AUnits aus dem implementation- ins interface-uses verschieben (#593); False in
    /// Programmen, ohne interface-Teil oder wenn eine Liste nicht schlicht ist.</summary>
    class function MoveUnitsToInterface(const ATokens: TArray<TPascalToken>; const AText: string;
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
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Text.Lines;

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

function IsBefore(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function InsideAny(const APosition: TTextPosition; const ARanges: TArray<TTextRange>): Boolean;
var
  Range: TTextRange;
begin
  for Range in ARanges do
    if not IsBefore(APosition, Range.StartPos) and IsBefore(APosition, Range.EndPos) then
      Exit(True);
  Result := False;
end;

class function TUsesActions.Entries(const ATokens: TArray<TPascalToken>; const AInactive: TArray<TTextRange>;
  const AInfo: TUsesUnitInfoFunc; const AKeep: TArray<string>): TArray<TUsesEntry>;
var
  Active: TArray<TPascalToken>;
  Count, Index, Usage: Integer;
  Clauses: TArray<TUsesClauseInfo>;
  Clause: TUsesClauseInfo;
  References: TArray<TUsesReference>;
  Reference: TUsesReference;
  Identifiers: TDictionary<string, Integer>;
  Seen: TArray<string>;
  Info: TUsesUnitInfo;
  Entry: TUsesEntry;
begin
  Result := nil;
  if not Assigned(AInfo) then
    Exit;
  // Nur der aktive Zweig: so gelten auch Listen mit {$IFDEF}.
  if AInactive = nil then
    Active := ATokens
  else
  begin
    SetLength(Active, Length(ATokens));
    Count := 0;
    for Index := 0 to High(ATokens) do
      if not InsideAny(ATokens[Index].StartPos, AInactive) then
      begin
        Active[Count] := ATokens[Index];
        Inc(Count);
      end;
    SetLength(Active, Count);
  end;
  Clauses := TUsesClauses.Clauses(Active);
  References := TUsesClauses.References(Active);
  Seen := nil;
  Identifiers := CollectIdentifiers(Active, Clauses);
  try
    for Clause in Clauses do
      for Reference in References do
      begin
        if IsBefore(Reference.Range.StartPos, Active[Clause.UsesIndex].EndPos) or
          IsBefore(Active[Clause.Semicolon].StartPos, Reference.Range.EndPos) then
          Continue;
        // Doppelte Einträge räumt "uses aufräumen" auf, nicht das Abblenden.
        if ContainsText_(Seen, Reference.Name) then
          Continue;
        Seen := Seen + [Reference.Name];
        Info := AInfo(Reference.Name);
        if not Info.Known then
          Continue;
        Usage := UsageOf(Reference.Name, Info, Identifiers);
        Entry.Name := Reference.Name;
        Entry.Range := Reference.Range;
        if Usage = 0 then
        begin
          if ContainsText_(AKeep, Reference.Name) then
            Entry.State := TUsesEntryState.KeptByAllowlist
          else if Info.HasInitialization then
            Entry.State := TUsesEntryState.KeptForInitialization
          else
            Entry.State := TUsesEntryState.Unused;
        end
        else if Clause.InInterface and (Usage = InImplementationPart) and not Info.HasInitialization then
          Entry.State := TUsesEntryState.OnlyImplementation
        else
          Continue;
        Result := Result + [Entry];
      end;
  finally
    Identifiers.Free;
  end;
end;

type
  TCut = record
    First: Integer;
    Till: Integer;
  end;

/// <summary>Nächstes Token ohne Kommentare ab AIndex in Richtung AStep; ABlocked, wenn dabei eine Direktive
/// liegt, ACommented bei Kommentaren. -1 am Rand.</summary>
function Significant(const ATokens: TArray<TPascalToken>; AIndex, AStep: Integer;
  out ABlocked, ACommented: Boolean): Integer;
begin
  ABlocked := False;
  ACommented := False;
  Result := AIndex + AStep;
  while (Result >= 0) and (Result <= High(ATokens)) do
  begin
    if ATokens[Result].Kind = TPascalTokenKind.Directive then
      ABlocked := True
    else if ATokens[Result].Kind = TPascalTokenKind.Comment then
      ACommented := True
    else
      Exit;
    Inc(Result, AStep);
  end;
  Result := -1;
end;

function TokenEnd(const AToken: TPascalToken): Integer;
begin
  Result := AToken.Offset + Length(AToken.Text);
end;

/// <summary>Was zu streichen ist, um den Eintrag an ARange zu entfernen; False, wenn es nicht sicher geht.</summary>
function CutsFor(const ATokens: TArray<TPascalToken>; const AText: string; const ARange: TTextRange;
  out ACuts: TArray<TCut>): Boolean;
var
  Index, First, Last, Previous, Next, LineStart, LineEnd: Integer;
  PreviousBlocked, NextBlocked, PreviousCommented, NextCommented, Blocked, Commented: Boolean;
  Cut: TCut;
begin
  ACuts := nil;
  First := -1;
  Last := -1;
  for Index := 0 to High(ATokens) do
  begin
    if (ATokens[Index].StartPos = ARange.StartPos) and (ATokens[Index].Kind = TPascalTokenKind.Identifier) then
      First := Index;
    if (First >= 0) and (ATokens[Index].EndPos = ARange.EndPos) then
    begin
      Last := Index;
      Break;
    end;
  end;
  if (First < 0) or (Last < 0) then
    Exit(False);
  Next := Significant(ATokens, Last, 1, NextBlocked, NextCommented);
  // "in 'datei.pas'" gehört zum Eintrag.
  if (Next >= 0) and ATokens[Next].IsKeyword('in') then
  begin
    Last := Significant(ATokens, Next, 1, Blocked, Commented);
    if (Last < 0) or Blocked or (ATokens[Last].Kind <> TPascalTokenKind.StringLiteral) then
      Exit(False);
    Next := Significant(ATokens, Last, 1, NextBlocked, NextCommented);
  end;
  if Next < 0 then
    Exit(False);
  Previous := Significant(ATokens, First, -1, PreviousBlocked, PreviousCommented);
  if Previous < 0 then
    Exit(False);
  if ATokens[Previous].IsSymbol(',') and not PreviousBlocked then
  begin
    // "A, B" → "A"; mit Kommentar dazwischen bleibt er stehen, nur Komma und Name gehen.
    if PreviousCommented then
    begin
      Cut.First := ATokens[Previous].Offset;
      Cut.Till := TokenEnd(ATokens[Previous]);
      ACuts := ACuts + [Cut];
      Cut.First := ATokens[First].Offset;
    end
    else
      Cut.First := ATokens[Previous].Offset;
    Cut.Till := TokenEnd(ATokens[Last]);
    ACuts := ACuts + [Cut];
    Exit(True);
  end;
  if ATokens[Next].IsSymbol(',') and not NextBlocked then
  begin
    Cut.First := ATokens[First].Offset;
    if NextCommented then
    begin
      Cut.Till := TokenEnd(ATokens[Last]);
      ACuts := ACuts + [Cut];
      Cut.First := ATokens[Next].Offset;
      Cut.Till := TokenEnd(ATokens[Next]);
    end
    else
    begin
      // "A, B" → "B", auch über den Zeilenumbruch einer mehrzeiligen Liste.
      Cut.Till := TokenEnd(ATokens[Next]);
      while (Cut.Till < Length(AText)) and CharInSet(AText[Cut.Till + 1], [' ', #9, #13, #10]) do
        Inc(Cut.Till);
    end;
    ACuts := ACuts + [Cut];
    Exit(True);
  end;
  // Einziger Eintrag: das ganze uses, mit der Zeile, wenn sonst nichts darauf steht.
  if not (ATokens[Previous].IsKeyword('uses') and ATokens[Next].IsSymbol(';')) or PreviousBlocked or
    NextBlocked or PreviousCommented or NextCommented then
    Exit(False);
  Cut.First := ATokens[Previous].Offset;
  Cut.Till := TokenEnd(ATokens[Next]);
  LineStart := Cut.First;
  while (LineStart > 0) and CharInSet(AText[LineStart], [' ', #9]) do
    Dec(LineStart);
  LineEnd := Cut.Till;
  while (LineEnd < Length(AText)) and CharInSet(AText[LineEnd + 1], [' ', #9]) do
    Inc(LineEnd);
  if ((LineStart = 0) or CharInSet(AText[LineStart], [#13, #10])) and
    ((LineEnd = Length(AText)) or CharInSet(AText[LineEnd + 1], [#13, #10])) then
  begin
    Cut.First := LineStart;
    Cut.Till := LineEnd;
    if (Cut.Till < Length(AText)) and (AText[Cut.Till + 1] = #13) then
      Inc(Cut.Till);
    if (Cut.Till < Length(AText)) and (AText[Cut.Till + 1] = #10) then
      Inc(Cut.Till);
  end;
  ACuts := ACuts + [Cut];
  Result := True;
end;

class function TUsesActions.RemoveEntries(const AText: string; const ARanges: TArray<TTextRange>;
  out AEdit: TTextEdit): Boolean;
var
  Sorted: TArray<TTextRange>;
  Swap: TTextRange;
  Text: string;
  Index, Other, Prefix, Suffix: Integer;
  Cuts: TArray<TCut>;
  Lines: TLineTable;
begin
  AEdit := Default(TTextEdit);
  if ARanges = nil then
    Exit(False);
  // Von hinten nach vorn: Was weiter vorn steht, behält seine Position.
  Sorted := Copy(ARanges);
  for Index := 0 to High(Sorted) - 1 do
    for Other := Index + 1 to High(Sorted) do
      if IsBefore(Sorted[Index].StartPos, Sorted[Other].StartPos) then
      begin
        Swap := Sorted[Index];
        Sorted[Index] := Sorted[Other];
        Sorted[Other] := Swap;
      end;
  Text := AText;
  for Index := 0 to High(Sorted) do
  begin
    if not CutsFor(TPascalLexer.Tokenize(Text), Text, Sorted[Index], Cuts) then
      Exit(False);
    // Die Schnitte liegen aufsteigend: von hinten streichen.
    for Other := High(Cuts) downto 0 do
      Delete(Text, Cuts[Other].First + 1, Cuts[Other].Till - Cuts[Other].First);
  end;
  // Ein Edit über den geänderten Teil.
  Prefix := 0;
  while (Prefix < Length(Text)) and (Prefix < Length(AText)) and (Text[Prefix + 1] = AText[Prefix + 1]) do
    Inc(Prefix);
  Suffix := 0;
  while (Suffix < Length(Text) - Prefix) and (Suffix < Length(AText) - Prefix) and
    (Text[Length(Text) - Suffix] = AText[Length(AText) - Suffix]) do
    Inc(Suffix);
  Lines := TLineTable.Build(AText);
  AEdit := TTextEdit.Create(TTextRange.Create(Lines.PositionAt(Prefix), Lines.PositionAt(Length(AText) - Suffix)),
    Copy(Text, Prefix + 1, Length(Text) - Prefix - Suffix));
  Result := True;
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

class function TUsesActions.MoveUnitsToInterface(const ATokens: TArray<TPascalToken>; const AText: string;
  const AUnits: TArray<string>; const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean;
var
  Index, Interface_: Integer;
  Added: TTextEdit;
begin
  AEdits := nil;
  if AUnits = nil then
    Exit(False);
  Interface_ := -1;
  for Index := 0 to High(ATokens) do
    if ATokens[Index].IsKeyword('interface') then
    begin
      Interface_ := Index;
      Break;
    end;
  if (Interface_ < 0) or not RemoveUnits(ATokens, AText, AUnits, ALineBreak, AEdits) or
    not TUsesClauses.AddUnit(ATokens, ATokens[Interface_].Offset + 1, string.Join(', ', AUnits),
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
  Name: string;
begin
  Name := AName;
  // Search statt Rekursion (Bericht M1).
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    var
      Part: string;
    begin
      Result := TSyntaxSearchStep.Descend;
      if ACandidate.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl, TSyntaxKind.Field,
        TSyntaxKind.PropertyDecl, TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader, TSyntaxKind.Parameter,
        TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
        for Part in ACandidate.Name.Split([',', '.']) do
          if SameText(Bare(Trim(Part)), Name) then
            Exit(TSyntaxSearchStep.Found);
      // Aufzählungswerte stehen als Bezeichner im EnumType.
      if (ACandidate.Kind = TSyntaxKind.Identifier) and (ACandidate.Parent <> nil) and
        (ACandidate.Parent.Kind = TSyntaxKind.EnumType) and SameText(ACandidate.Name, Name) then
        Result := TSyntaxSearchStep.Found;
    end) <> nil;
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
