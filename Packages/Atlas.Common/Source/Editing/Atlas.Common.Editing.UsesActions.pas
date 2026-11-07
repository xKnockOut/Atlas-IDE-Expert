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
// - InterfaceUsages (#896) nennt die Stellen im interface-Teil, wegen derer
//   eine Unit im interface-uses stehen muss, mit derselben großzügigen
//   Namensprüfung wie MovableUnits. Leer heißt: Sie kann ins
//   implementation-uses, z. B. um einen Unit-Zyklus aufzulösen.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.Contract;

type
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

  /// <summary>Wohin AddUnits die Units schreibt (#786): selbst entscheiden oder ein Abschnitt fest.</summary>
  TUsesAddTarget = (
    /// <summary>interface, wenn der interface-Teil ein Symbol der Unit nennt, sonst implementation.</summary>
    Auto,
    Interface_,
    Implementation_);
  {$SCOPEDENUMS OFF}

  /// <summary>Ein auffälliger uses-Eintrag mit Position des Namens (#621).</summary>
  TUsesEntry = record
    Name: string;
    Range: TTextRange;
    State: TUsesEntryState;
  end;

  /// <summary>Ein Bezeichner im interface-Teil, wegen dessen eine Unit im interface-uses stehen muss (#896).
  /// </summary>
  TUsesInterfaceUsage = record
    Name: string;
    Range: TTextRange;
  end;

  /// <summary>Was TUsesActions.AddUnits eintragen soll und wohin (#777, #786).</summary>
  TUsesAddRequest = record
    Units: TArray<string>;
    /// <summary>Units, die einen Namen auf Unit-Ebene deklarieren; nil: bei Auto alles ins implementation-uses.
    /// </summary>
    Declaring: TUnitsDeclaringFunc;
    /// <summary>Unit-Namespaces des Projekts (System für SysUtils).</summary>
    Namespaces: TArray<string>;
    Target: TUsesAddTarget;
    LineBreak: string;
    /// <summary>Anfrage mit TUsesAddTarget.Auto.</summary>
    class function Create(const AUnits: TArray<string>; const ADeclaring: TUnitsDeclaringFunc;
      const ANamespaces: TArray<string>; const ALineBreak: string): TUsesAddRequest; static;
    /// <summary>Dieselbe Anfrage mit festem Abschnitt ATarget.</summary>
    function WithTarget(ATarget: TUsesAddTarget): TUsesAddRequest;
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
    /// <summary>Bezeichner im interface-Teil einer Unit (außerhalb der uses-Listen), die einen der Namen ANames
    /// (interface-Symbole der Unit AUnitName, auch Mitglieder) oder den letzten Teil von AUnitName nennen (#896),
    /// in Quelltextreihenfolge. Leer in Programmen und wenn die Unit im interface nicht gebraucht wird.</summary>
    class function InterfaceUsages(const ATokens: TArray<TPascalToken>; const AUnitName: string;
      const ANames: TArray<string>): TArray<TUsesInterfaceUsage>; static;
    /// <summary>interface-Units, die nur im implementation-Teil gebraucht werden.</summary>
    class function MovableUnits(const ATokens: TArray<TPascalToken>;
      const AInfo: TUsesUnitInfoFunc): TArray<string>; static;
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
    /// <summary>Edits, die ARequest.Units ins uses eintragen (#777, „In uses aufnehmen“; #786, „Unit verwenden“
    /// mit Umschalter interface / implementation). Bei TUsesAddTarget.Auto ins interface, wenn der interface-Teil
    /// schon ein Symbol nennt, das die Unit auf Unit-Ebene deklariert (ARequest.Declaring), sonst ins
    /// implementation-uses; in Programmen und Units ohne implementation landet alles im einzigen uses. Schon
    /// eingebundene Units (auch über Namespaces), doppelte Namen und die eigene Unit entfallen; AAdded nennt die
    /// eingetragenen. False ohne Edit.</summary>
    class function AddUnits(const ATokens: TArray<TPascalToken>; const ARequest: TUsesAddRequest;
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
  cInInterfacePart = 1;
  cInImplementationPart = 2;
  // Vorsilbe für Bezeichner mit Punkt dahinter (Qualifizierer); kein Bezeichner beginnt mit einem Punkt.
  cQualifierKey = '.';

function Bare(const AIdentifier: string): string;
begin
  if (AIdentifier <> '') and (AIdentifier[1] = '&') then
  begin
    Result := Copy(AIdentifier, 2, MaxInt);
  end
  else
  begin
    Result := AIdentifier;
  end;
end;

function ContainsText_(const ANames: TArray<string>; const AName: string): Boolean;
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

/// <summary>Folgt auf das Token AIndex (Kommentare übersprungen) ein Punkt?</summary>
function DotFollows(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mNext: Integer;
begin
  mNext := AIndex + 1;
  while (mNext <= High(ATokens)) and (ATokens[mNext].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Inc(mNext);
  end;
  Result := (mNext <= High(ATokens)) and ATokens[mNext].IsSymbol('.');
end;

/// <summary>Teil am Dateianfang: interface bei einer Unit, sonst implementation (Programm, Package).</summary>
function FirstPart(const ATokens: TArray<TPascalToken>): Integer;
var
  mIndex: Integer;
begin
  Result := cInImplementationPart;
  for mIndex := 0 to High(ATokens) do
  begin
    if not (ATokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      if ATokens[mIndex].IsKeyword('unit') then
      begin
        Result := cInInterfacePart;
      end;
      Exit;
    end;
  end;
end;

/// <summary>Nimmt APart in die Bitmaske von AKey auf.</summary>
procedure AddUsage(AMap: TDictionary<string, Integer>; const AKey: string; APart: Integer);
var
  mMask: Integer;
begin
  if not AMap.TryGetValue(AKey, mMask) then
  begin
    mMask := 0;
  end;
  AMap.AddOrSetValue(AKey, mMask or APart);
end;

/// <summary>Bezeichner außerhalb der uses-Listen mit Bitmaske des Teils (interface/implementation). Steht ein
/// Punkt dahinter (Qualifizierer wie SysUtils.Format), zählt er zusätzlich unter "." + Name.</summary>
function CollectIdentifiers(const ATokens: TArray<TPascalToken>;
  const AClauses: TArray<TUsesClauseInfo>): TDictionary<string, Integer>;
var
  mIndex, mClauseIndex, mPart: Integer;
  mKey: string;
begin
  Result := TDictionary<string, Integer>.Create;
  mPart := FirstPart(ATokens);
  mClauseIndex := 0;
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    if (mClauseIndex <= High(AClauses)) and (mIndex = AClauses[mClauseIndex].UsesIndex) then
    begin
      mIndex := AClauses[mClauseIndex].Semicolon + 1;
      Inc(mClauseIndex);
      Continue;
    end;
    if ATokens[mIndex].IsKeyword('implementation') then
    begin
      mPart := cInImplementationPart;
    end
    else if ATokens[mIndex].Kind = TPascalTokenKind.Identifier then
    begin
      mKey := LowerCase(Bare(ATokens[mIndex].Text));
      AddUsage(Result, mKey, mPart);
      if DotFollows(ATokens, mIndex) then
      begin
        AddUsage(Result, cQualifierKey + mKey, mPart);
      end;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Teile (Bitmaske), in denen die Unit benutzt wird.</summary>
function UsageOf(const AUnitName: string; const AInfo: TUsesUnitInfo;
  AIdentifiers: TDictionary<string, Integer>): Integer;
var
  mName: string;
  mMask: Integer;
begin
  Result := 0;
  // Verweis der Formulardatei auf ein Modul der Unit: Die IDE braucht den Eintrag, der Code nennt ihn nicht.
  if AInfo.UsedByForm then
  begin
    Result := cInImplementationPart;
  end;
  // Qualifizierter Zugriff wie SysUtils.Format oder System.SysUtils.Format. Nur mit Punkt dahinter: Eine
  // Methode, die wie die Unit heißt (UsesActions in Atlas.Common.Lsp.CodeActions), benutzt sie nicht.
  if AIdentifiers.TryGetValue(cQualifierKey + LowerCase(Copy(AUnitName, LastDelimiter('.', AUnitName) + 1, MaxInt)),
    mMask) then
  begin
    Result := Result or mMask;
  end;
  for mName in AInfo.Names do
  begin
    if AIdentifiers.TryGetValue(LowerCase(mName), mMask) then
    begin
      Result := Result or mMask;
      if Result = cInInterfacePart or cInImplementationPart then
      begin
        Exit;
      end;
    end;
  end;
end;

function IsBefore(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function InsideAny(const APosition: TTextPosition; const ARanges: TArray<TTextRange>): Boolean;
var
  mRange: TTextRange;
begin
  for mRange in ARanges do
  begin
    if not IsBefore(APosition, mRange.StartPos) and IsBefore(APosition, mRange.EndPos) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Die Token außerhalb der Bereiche AInactive (inaktive Zweige der bedingten Kompilierung).</summary>
function ActiveTokens(const ATokens: TArray<TPascalToken>; const AInactive: TArray<TTextRange>): TArray<TPascalToken>;
var
  mCount, mIndex: Integer;
begin
  if AInactive = nil then
  begin
    Exit(ATokens);
  end;
  SetLength(Result, Length(ATokens));
  mCount := 0;
  for mIndex := 0 to High(ATokens) do
  begin
    if not InsideAny(ATokens[mIndex].StartPos, AInactive) then
    begin
      Result[mCount] := ATokens[mIndex];
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

/// <summary>Liegt ARange zwischen "uses" und dem Semikolon der Liste AClause?</summary>
function InClause(const ATokens: TArray<TPascalToken>; const AClause: TUsesClauseInfo;
  const ARange: TTextRange): Boolean;
begin
  Result := not IsBefore(ARange.StartPos, ATokens[AClause.UsesIndex].EndPos) and
    not IsBefore(ATokens[AClause.Semicolon].StartPos, ARange.EndPos);
end;

/// <summary>Warum der Eintrag AName auffällt; False, wenn er benutzt wird und richtig steht.</summary>
function EntryState(const AName: string; const AInfo: TUsesUnitInfo; AUsage: Integer; AInInterface: Boolean;
  const AKeep: TArray<string>; out AState: TUsesEntryState): Boolean;
begin
  Result := True;
  if AUsage = 0 then
  begin
    if ContainsText_(AKeep, AName) then
    begin
      AState := TUsesEntryState.KeptByAllowlist;
    end
    else if AInfo.HasInitialization then
    begin
      AState := TUsesEntryState.KeptForInitialization;
    end
    else
    begin
      AState := TUsesEntryState.Unused;
    end;
  end
  else
  begin
    AState := TUsesEntryState.OnlyImplementation;
    Result := AInInterface and (AUsage = cInImplementationPart) and not AInfo.HasInitialization;
  end;
end;

class function TUsesActions.Entries(const ATokens: TArray<TPascalToken>; const AInactive: TArray<TTextRange>;
  const AInfo: TUsesUnitInfoFunc; const AKeep: TArray<string>): TArray<TUsesEntry>;
var
  mActive: TArray<TPascalToken>;
  mClauses: TArray<TUsesClauseInfo>;
  mClause: TUsesClauseInfo;
  mReferences: TArray<TUsesReference>;
  mReference: TUsesReference;
  mIdentifiers: TDictionary<string, Integer>;
  mSeen: TArray<string>;
  mInfo: TUsesUnitInfo;
  mEntry: TUsesEntry;
begin
  Result := nil;
  if not Assigned(AInfo) then
  begin
    Exit;
  end;
  // Nur der aktive Zweig: so gelten auch Listen mit {$IFDEF}.
  mActive := ActiveTokens(ATokens, AInactive);
  mClauses := TUsesClauses.Clauses(mActive);
  mReferences := TUsesClauses.References(mActive);
  mSeen := nil;
  mIdentifiers := CollectIdentifiers(mActive, mClauses);
  try
    for mClause in mClauses do
    begin
      for mReference in mReferences do
      begin
        // Doppelte Einträge räumt "uses aufräumen" auf, nicht das Abblenden.
        if not InClause(mActive, mClause, mReference.Range) or ContainsText_(mSeen, mReference.Name) then
        begin
          Continue;
        end;
        mSeen := mSeen + [mReference.Name];
        mInfo := AInfo(mReference.Name);
        if mInfo.Known and EntryState(mReference.Name, mInfo, UsageOf(mReference.Name, mInfo, mIdentifiers),
          mClause.InInterface, AKeep, mEntry.State) then
        begin
          mEntry.Name := mReference.Name;
          mEntry.Range := mReference.Range;
          Result := Result + [mEntry];
        end;
      end;
    end;
  finally
    mIdentifiers.Free;
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
    begin
      ABlocked := True;
    end
    else if ATokens[Result].Kind = TPascalTokenKind.Comment then
    begin
      ACommented := True;
    end
    else
    begin
      Exit;
    end;
    Inc(Result, AStep);
  end;
  Result := -1;
end;

function TokenEnd(const AToken: TPascalToken): Integer;
begin
  Result := AToken.Offset + Length(AToken.Text);
end;

type
  /// <summary>Ein uses-Eintrag mit seinen bedeutsamen Nachbarn.</summary>
  TEntrySpot = record
    First: Integer;
    Last: Integer;
    Previous: Integer;
    Next: Integer;
    PreviousBlocked: Boolean;
    NextBlocked: Boolean;
    PreviousCommented: Boolean;
    NextCommented: Boolean;
    /// <summary>Weder Direktive noch Kommentar vor oder nach dem Eintrag.</summary>
    function Isolated: Boolean;
  end;

function TEntrySpot.Isolated: Boolean;
begin
  Result := not (PreviousBlocked or NextBlocked or PreviousCommented or NextCommented);
end;

/// <summary>Erstes und letztes Token des Eintrags an ARange; False, wenn dort keiner beginnt.</summary>
function EntryTokens(const ATokens: TArray<TPascalToken>; const ARange: TTextRange;
  out AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
begin
  AFirst := -1;
  ALast := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if (ATokens[mIndex].StartPos = ARange.StartPos) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) then
    begin
      AFirst := mIndex;
    end;
    if (AFirst >= 0) and (ATokens[mIndex].EndPos = ARange.EndPos) then
    begin
      ALast := mIndex;
      Break;
    end;
  end;
  Result := (AFirst >= 0) and (ALast >= 0);
end;

/// <summary>Nimmt "in 'datei.pas'" hinter dem Namen in den Eintrag; False, wenn kein Dateiname folgt.</summary>
function IncludeFileName(const ATokens: TArray<TPascalToken>; var ASpot: TEntrySpot): Boolean;
var
  mBlocked, mCommented: Boolean;
begin
  ASpot.Last := Significant(ATokens, ASpot.Next, 1, mBlocked, mCommented);
  Result := (ASpot.Last >= 0) and not mBlocked and (ATokens[ASpot.Last].Kind = TPascalTokenKind.StringLiteral);
  if Result then
  begin
    ASpot.Next := Significant(ATokens, ASpot.Last, 1, ASpot.NextBlocked, ASpot.NextCommented);
  end;
end;

/// <summary>Sucht den Eintrag an ARange und seine Nachbarn; False, wenn er nicht sicher zu fassen ist.</summary>
function LocateEntry(const ATokens: TArray<TPascalToken>; const ARange: TTextRange; out ASpot: TEntrySpot): Boolean;
begin
  ASpot := Default(TEntrySpot);
  Result := EntryTokens(ATokens, ARange, ASpot.First, ASpot.Last);
  if not Result then
  begin
    Exit;
  end;
  ASpot.Next := Significant(ATokens, ASpot.Last, 1, ASpot.NextBlocked, ASpot.NextCommented);
  // "in 'datei.pas'" gehört zum Eintrag.
  if (ASpot.Next >= 0) and ATokens[ASpot.Next].IsKeyword('in') then
  begin
    Result := IncludeFileName(ATokens, ASpot);
  end;
  ASpot.Previous := Significant(ATokens, ASpot.First, -1, ASpot.PreviousBlocked, ASpot.PreviousCommented);
  Result := Result and (ASpot.Next >= 0) and (ASpot.Previous >= 0);
end;

/// <summary>Erste Stelle ab AFrom (0-basiert, hinter einem Zeichen), an der kein Zeichen aus AChars folgt.
/// </summary>
function SkipForward(const AText: string; AFrom: Integer; const AChars: TSysCharSet): Integer;
begin
  Result := AFrom;
  while (Result < Length(AText)) and CharInSet(AText[Result + 1], AChars) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Geht von AFrom über Leerzeichen und Tabulatoren zurück.</summary>
function SkipBackward(const AText: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result > 0) and CharInSet(AText[Result], [' ', #9]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>"A, B" → "A": das Komma davor mit dem Namen; mit Kommentar dazwischen bleibt er stehen.</summary>
function CommaBeforeCuts(const ATokens: TArray<TPascalToken>; const ASpot: TEntrySpot): TArray<TCut>;
var
  mCut: TCut;
begin
  Result := nil;
  mCut.First := ATokens[ASpot.Previous].Offset;
  if ASpot.PreviousCommented then
  begin
    mCut.Till := TokenEnd(ATokens[ASpot.Previous]);
    Result := Result + [mCut];
    mCut.First := ATokens[ASpot.First].Offset;
  end;
  mCut.Till := TokenEnd(ATokens[ASpot.Last]);
  Result := Result + [mCut];
end;

/// <summary>"A, B" → "B": der Name mit dem Komma dahinter, auch über den Zeilenumbruch einer mehrzeiligen
/// Liste; mit Kommentar dazwischen bleibt er stehen.</summary>
function CommaAfterCuts(const ATokens: TArray<TPascalToken>; const AText: string;
  const ASpot: TEntrySpot): TArray<TCut>;
var
  mCut: TCut;
begin
  Result := nil;
  mCut.First := ATokens[ASpot.First].Offset;
  if ASpot.NextCommented then
  begin
    mCut.Till := TokenEnd(ATokens[ASpot.Last]);
    Result := Result + [mCut];
    mCut.First := ATokens[ASpot.Next].Offset;
    mCut.Till := TokenEnd(ATokens[ASpot.Next]);
  end
  else
  begin
    mCut.Till := SkipForward(AText, TokenEnd(ATokens[ASpot.Next]), [' ', #9, #13, #10]);
  end;
  Result := Result + [mCut];
end;

/// <summary>Einziger Eintrag ohne Direktiven und Kommentare ringsum: "uses Name;".</summary>
function IsLoneEntry(const ATokens: TArray<TPascalToken>; const ASpot: TEntrySpot): Boolean;
begin
  Result := ATokens[ASpot.Previous].IsKeyword('uses') and ATokens[ASpot.Next].IsSymbol(';') and ASpot.Isolated;
end;

/// <summary>Ende hinter dem Zeilenumbruch (CR, LF oder CRLF) ab AFrom.</summary>
function WithLineBreak(const AText: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  if (Result < Length(AText)) and (AText[Result + 1] = #13) then
  begin
    Inc(Result);
  end;
  if (Result < Length(AText)) and (AText[Result + 1] = #10) then
  begin
    Inc(Result);
  end;
end;

/// <summary>Das ganze uses, mit der Zeile, wenn sonst nichts darauf steht.</summary>
function WholeUsesCut(const ATokens: TArray<TPascalToken>; const AText: string; const ASpot: TEntrySpot): TCut;
var
  mLineStart, mLineEnd: Integer;
begin
  Result.First := ATokens[ASpot.Previous].Offset;
  Result.Till := TokenEnd(ATokens[ASpot.Next]);
  mLineStart := SkipBackward(AText, Result.First);
  mLineEnd := SkipForward(AText, Result.Till, [' ', #9]);
  if ((mLineStart = 0) or CharInSet(AText[mLineStart], [#13, #10])) and
    ((mLineEnd = Length(AText)) or CharInSet(AText[mLineEnd + 1], [#13, #10])) then
  begin
    Result.First := mLineStart;
    Result.Till := WithLineBreak(AText, mLineEnd);
  end;
end;

/// <summary>Was zu streichen ist, um den Eintrag an ARange zu entfernen; False, wenn es nicht sicher geht.</summary>
function CutsFor(const ATokens: TArray<TPascalToken>; const AText: string; const ARange: TTextRange;
  out ACuts: TArray<TCut>): Boolean;
var
  mSpot: TEntrySpot;
begin
  ACuts := nil;
  Result := LocateEntry(ATokens, ARange, mSpot);
  if not Result then
  begin
    Exit;
  end;
  if ATokens[mSpot.Previous].IsSymbol(',') and not mSpot.PreviousBlocked then
  begin
    ACuts := CommaBeforeCuts(ATokens, mSpot);
  end
  else if ATokens[mSpot.Next].IsSymbol(',') and not mSpot.NextBlocked then
  begin
    ACuts := CommaAfterCuts(ATokens, AText, mSpot);
  end
  else if IsLoneEntry(ATokens, mSpot) then
  begin
    ACuts := ACuts + [WholeUsesCut(ATokens, AText, mSpot)];
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>ARanges von hinten nach vorn: Was weiter vorn steht, behält seine Position.</summary>
function SortedDescending(const ARanges: TArray<TTextRange>): TArray<TTextRange>;
var
  mIndex, mOther: Integer;
  mSwap: TTextRange;
begin
  Result := Copy(ARanges);
  for mIndex := 0 to High(Result) - 1 do
  begin
    for mOther := mIndex + 1 to High(Result) do
    begin
      if IsBefore(Result[mIndex].StartPos, Result[mOther].StartPos) then
      begin
        mSwap := Result[mIndex];
        Result[mIndex] := Result[mOther];
        Result[mOther] := mSwap;
      end;
    end;
  end;
end;

/// <summary>Ein Edit über den Teil, in dem sich ANew von AOld unterscheidet.</summary>
function ChangedPart(const AOld, ANew: string): TTextEdit;
var
  mPrefix, mSuffix: Integer;
  mLines: TLineTable;
begin
  mPrefix := 0;
  while (mPrefix < Length(ANew)) and (mPrefix < Length(AOld)) and (ANew[mPrefix + 1] = AOld[mPrefix + 1]) do
  begin
    Inc(mPrefix);
  end;
  mSuffix := 0;
  while (mSuffix < Length(ANew) - mPrefix) and (mSuffix < Length(AOld) - mPrefix) and
    (ANew[Length(ANew) - mSuffix] = AOld[Length(AOld) - mSuffix]) do
  begin
    Inc(mSuffix);
  end;
  mLines := TLineTable.Build(AOld);
  Result := TTextEdit.Create(TTextRange.Create(mLines.PositionAt(mPrefix), mLines.PositionAt(Length(AOld) - mSuffix)),
    Copy(ANew, mPrefix + 1, Length(ANew) - mPrefix - mSuffix));
end;

class function TUsesActions.RemoveEntries(const AText: string; const ARanges: TArray<TTextRange>;
  out AEdit: TTextEdit): Boolean;
var
  mRange: TTextRange;
  mText: string;
  mIndex: Integer;
  mCuts: TArray<TCut>;
begin
  AEdit := Default(TTextEdit);
  if ARanges = nil then
  begin
    Exit(False);
  end;
  mText := AText;
  for mRange in SortedDescending(ARanges) do
  begin
    if not CutsFor(TPascalLexer.Tokenize(mText), mText, mRange, mCuts) then
    begin
      Exit(False);
    end;
    // Die Schnitte liegen aufsteigend: von hinten streichen.
    for mIndex := High(mCuts) downto 0 do
    begin
      Delete(mText, mCuts[mIndex].First + 1, mCuts[mIndex].Till - mCuts[mIndex].First);
    end;
  end;
  AEdit := ChangedPart(AText, mText);
  Result := True;
end;

/// <summary>Namen der schlichten Listen ohne Doppelte, auf Wunsch nur die des interface-Teils.</summary>
function PlainNames(const AClauses: TArray<TUsesClauseInfo>; AInterfaceOnly: Boolean): TArray<string>;
var
  mClause: TUsesClauseInfo;
  mName: string;
begin
  Result := nil;
  for mClause in AClauses do
  begin
    if not mClause.Plain or (AInterfaceOnly and not mClause.InInterface) then
    begin
      Continue;
    end;
    for mName in mClause.Names do
    begin
      Result := Result + [mName];
    end;
  end;
end;

/// <summary>Bekannte Unit ohne initialization, die genau in den Teilen AMask benutzt wird.</summary>
function IsUsedOnlyIn(const AName: string; const AInfo: TUsesUnitInfo; AIdentifiers: TDictionary<string, Integer>;
  AMask: Integer): Boolean;
begin
  Result := AInfo.Known and not AInfo.HasInitialization and (UsageOf(AName, AInfo, AIdentifiers) = AMask);
end;

class function TUsesActions.UnusedUnits(const ATokens: TArray<TPascalToken>; const AInfo: TUsesUnitInfoFunc;
  const AKeep: TArray<string>): TArray<string>;
var
  mClauses: TArray<TUsesClauseInfo>;
  mIdentifiers: TDictionary<string, Integer>;
  mName: string;
begin
  Result := nil;
  mClauses := TUsesClauses.Clauses(ATokens);
  mIdentifiers := CollectIdentifiers(ATokens, mClauses);
  try
    for mName in PlainNames(mClauses, False) do
    begin
      if not (ContainsText_(AKeep, mName) or ContainsText_(Result, mName)) and
        IsUsedOnlyIn(mName, AInfo(mName), mIdentifiers, 0) then
      begin
        Result := Result + [mName];
      end;
    end;
  finally
    mIdentifiers.Free;
  end;
end;

class function TUsesActions.InterfaceUsages(const ATokens: TArray<TPascalToken>; const AUnitName: string;
  const ANames: TArray<string>): TArray<TUsesInterfaceUsage>;
var
  mUsage: TUsesInterfaceUsage;
  mClauses: TArray<TUsesClauseInfo>;
  mNames: TDictionary<string, Boolean>;
  mName: string;
  mIndex, mClauseIndex: Integer;
  mIsUnit: Boolean;
begin
  Result := nil;
  mIsUnit := False;
  for mIndex := 0 to High(ATokens) do
  begin
    if not (ATokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      mIsUnit := ATokens[mIndex].IsKeyword('unit');
      Break;
    end;
  end;
  if not mIsUnit then
  begin
    Exit;
  end;
  mClauses := TUsesClauses.Clauses(ATokens);
  mNames := TDictionary<string, Boolean>.Create;
  try
    // Qualifizierter Zugriff wie uKunde.TKunde zählt wie in UsageOf.
    mNames.AddOrSetValue(LowerCase(Copy(AUnitName, LastDelimiter('.', AUnitName) + 1, MaxInt)), True);
    for mName in ANames do
    begin
      mNames.AddOrSetValue(LowerCase(Bare(mName)), True);
    end;
    mClauseIndex := 0;
    mIndex := 0;
    while mIndex <= High(ATokens) do
    begin
      if (mClauseIndex <= High(mClauses)) and (mIndex = mClauses[mClauseIndex].UsesIndex) then
      begin
        mIndex := mClauses[mClauseIndex].Semicolon + 1;
        Inc(mClauseIndex);
        Continue;
      end;
      if ATokens[mIndex].IsKeyword('implementation') then
      begin
        Break;
      end;
      if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and
        mNames.ContainsKey(LowerCase(Bare(ATokens[mIndex].Text))) then
      begin
        mUsage.Name := Bare(ATokens[mIndex].Text);
        mUsage.Range := TTextRange.Create(ATokens[mIndex].StartPos, ATokens[mIndex].EndPos);
        Result := Result + [mUsage];
      end;
      Inc(mIndex);
    end;
  finally
    mNames.Free;
  end;
end;

/// <summary>Hat ein implementation-uses Direktiven oder Kommentare? Solche fassen wir nicht an.</summary>
function HasComplexImplementation(const AClauses: TArray<TUsesClauseInfo>): Boolean;
var
  mClause: TUsesClauseInfo;
begin
  for mClause in AClauses do
  begin
    if not mClause.InInterface and not mClause.Plain then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TUsesActions.MovableUnits(const ATokens: TArray<TPascalToken>;
  const AInfo: TUsesUnitInfoFunc): TArray<string>;
var
  mClauses: TArray<TUsesClauseInfo>;
  mIdentifiers: TDictionary<string, Integer>;
  mName: string;
begin
  Result := nil;
  mClauses := TUsesClauses.Clauses(ATokens);
  if HasComplexImplementation(mClauses) then
  begin
    Exit;
  end;
  mIdentifiers := CollectIdentifiers(ATokens, mClauses);
  try
    for mName in PlainNames(mClauses, True) do
    begin
      // Initialisierungsreihenfolge kann zählen; solche Units bleiben, wo sie sind.
      if IsUsedOnlyIn(mName, AInfo(mName), mIdentifiers, cInImplementationPart) then
      begin
        Result := Result + [mName];
      end;
    end;
  finally
    mIdentifiers.Free;
  end;
end;

class function TUsesActions.RemoveUnits(const ATokens: TArray<TPascalToken>; const AText: string;
  const AUnits: TArray<string>; const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean;
var
  mOptions: TUsesRewrite;
begin
  AEdits := nil;
  if AUnits = nil then
  begin
    Exit(False);
  end;
  mOptions := Default(TUsesRewrite);
  mOptions.Drop := AUnits;
  Result := TUsesClauses.Rewrite(ATokens, AText, mOptions, ALineBreak, AEdits);
end;

class function TUsesActions.MoveUnits(const ATokens: TArray<TPascalToken>; const AText: string;
  const AUnits: TArray<string>; const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean;
var
  mIndex, mImplementation_: Integer;
  mAdded: TTextEdit;
begin
  AEdits := nil;
  if AUnits = nil then
  begin
    Exit(False);
  end;
  mImplementation_ := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('implementation') then
    begin
      mImplementation_ := mIndex;
      Break;
    end;
  end;
  if (mImplementation_ < 0) or not RemoveUnits(ATokens, AText, AUnits, ALineBreak, AEdits) or
    not TUsesClauses.AddUnit(ATokens, ATokens[mImplementation_].Offset + 1, string.Join(', ', AUnits),
    ALineBreak, mAdded) then
  begin
    AEdits := nil;
    Exit(False);
  end;
  AEdits := AEdits + [mAdded];
  Result := True;
end;

class function TUsesActions.MoveUnitsToInterface(const ATokens: TArray<TPascalToken>; const AText: string;
  const AUnits: TArray<string>; const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean;
var
  mIndex, mInterface_: Integer;
  mAdded: TTextEdit;
begin
  AEdits := nil;
  if AUnits = nil then
  begin
    Exit(False);
  end;
  mInterface_ := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('interface') then
    begin
      mInterface_ := mIndex;
      Break;
    end;
  end;
  if (mInterface_ < 0) or not RemoveUnits(ATokens, AText, AUnits, ALineBreak, AEdits) or
    not TUsesClauses.AddUnit(ATokens, ATokens[mInterface_].Offset + 1, string.Join(', ', AUnits),
    ALineBreak, mAdded) then
  begin
    AEdits := nil;
    Exit(False);
  end;
  AEdits := AEdits + [mAdded];
  Result := True;
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function IsDeclaredIn(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
begin
  mName := AName;
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
      begin
        for Part in ACandidate.Name.Split([',', '.']) do
        begin
          if SameText(Bare(Trim(Part)), mName) then
          begin
            Exit(TSyntaxSearchStep.Found);
          end;
        end;
      end;
      // Aufzählungswerte stehen als Bezeichner im EnumType.
      if (ACandidate.Kind = TSyntaxKind.Identifier) and (ACandidate.Parent <> nil) and
        (ACandidate.Parent.Kind = TSyntaxKind.EnumType) and SameText(ACandidate.Name, mName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Index des Bezeichners an APosition; -1, wenn dort keiner steht.</summary>
function IdentifierAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and not Before(APosition, ATokens[mIndex].StartPos) and
      not Before(ATokens[mIndex].EndPos, APosition) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Steht vor dem Token AIndex (über Kommentare und Direktiven hinweg) ein Punkt? Dann ist es ein
/// Mitglied oder ein qualifizierter Name.</summary>
function FollowsDot(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mPrevious: Integer;
begin
  mPrevious := AIndex - 1;
  while (mPrevious >= 0) and (ATokens[mPrevious].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(mPrevious);
  end;
  Result := (mPrevious >= 0) and ATokens[mPrevious].IsSymbol('.');
end;

/// <summary>Ist eine der Units ACandidates die eigene oder schon eingebunden (auch über Namespaces)?</summary>
function AnyProvided(const ATokens: TArray<TPascalToken>; const ACandidates, ANamespaces: TArray<string>): Boolean;
var
  mUsed: TArray<string>;
  mOwn, mCandidate: string;
begin
  mUsed := TUsesClauses.UsedUnits(ATokens);
  mOwn := TUsesClauses.OwnName(ATokens);
  for mCandidate in ACandidates do
  begin
    if SameText(mCandidate, mOwn) or TUsesClauses.IsUsed(mUsed, mCandidate, ANamespaces) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>ANames ohne Doppelte (Groß-/Kleinschreibung egal), in Reihenfolge.</summary>
function Distinct(const ANames: TArray<string>): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in ANames do
  begin
    if not ContainsText_(Result, mName) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

class function TUsesActions.MissingUnits(const ATokens: TArray<TPascalToken>; ATree: TSyntaxTree;
  const APosition: TTextPosition; const ADeclaring: TUnitsDeclaringFunc;
  const ANamespaces: TArray<string>): TArray<string>;
var
  mIndex: Integer;
  mName: string;
  mCandidates: TArray<string>;
begin
  Result := nil;
  mIndex := IdentifierAt(ATokens, APosition);
  if (mIndex < 0) or FollowsDot(ATokens, mIndex) then
  begin
    Exit;
  end;
  mName := Bare(ATokens[mIndex].Text);
  if (ATree <> nil) and IsDeclaredIn(ATree.Root, mName) then
  begin
    Exit;
  end;
  mCandidates := ADeclaring(mName);
  if not AnyProvided(ATokens, mCandidates, ANamespaces) then
  begin
    Result := Distinct(mCandidates);
  end;
end;

{ TUsesAddRequest }

class function TUsesAddRequest.Create(const AUnits: TArray<string>; const ADeclaring: TUnitsDeclaringFunc;
  const ANamespaces: TArray<string>; const ALineBreak: string): TUsesAddRequest;
begin
  Result.Units := AUnits;
  Result.Declaring := ADeclaring;
  Result.Namespaces := ANamespaces;
  Result.Target := TUsesAddTarget.Auto;
  Result.LineBreak := ALineBreak;
end;

function TUsesAddRequest.WithTarget(ATarget: TUsesAddTarget): TUsesAddRequest;
begin
  Result := Self;
  Result.Target := ATarget;
end;

/// <summary>Offsets der Schlüsselwörter interface und implementation; -1, wenn eines fehlt.</summary>
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

/// <summary>Nimmt aus ADeclared die Units aus AUnits in ANeeds auf, die dort noch fehlen.</summary>
procedure AddNeeded(var ANeeds: TArray<string>; const ADeclared, AUnits: TArray<string>);
var
  mName: string;
begin
  for mName in ADeclared do
  begin
    if ContainsText_(AUnits, mName) and not ContainsText_(ANeeds, mName) then
    begin
      ANeeds := ANeeds + [mName];
    end;
  end;
end;

/// <summary>Units aus AUnits, die Bezeichner des interface-Teils deklarieren.</summary>
function InterfaceNeeds(const ATokens: TArray<TPascalToken>; const AUnits: TArray<string>;
  const ADeclaring: TUnitsDeclaringFunc): TArray<string>;
var
  mIdentifiers: TDictionary<string, Integer>;
  mPair: TPair<string, Integer>;
begin
  Result := nil;
  mIdentifiers := CollectIdentifiers(ATokens, TUsesClauses.Clauses(ATokens));
  try
    for mPair in mIdentifiers do
    begin
      if (mPair.Value and cInInterfacePart <> 0) and not mPair.Key.StartsWith(cQualifierKey) then
      begin
        AddNeeded(Result, ADeclaring(mPair.Key), AUnits);
      end;
    end;
  finally
    mIdentifiers.Free;
  end;
end;

/// <summary>Units aus AUnits, die noch fehlen: ohne leere, doppelte, die eigene und schon eingebundene.</summary>
function NewUnits(const ATokens: TArray<TPascalToken>; const AUnits, ANamespaces: TArray<string>): TArray<string>;
var
  mUsed: TArray<string>;
  mOwn, mName: string;
begin
  Result := nil;
  mUsed := TUsesClauses.UsedUnits(ATokens);
  mOwn := TUsesClauses.OwnName(ATokens);
  for mName in AUnits do
  begin
    if not ((Trim(mName) = '') or SameText(mName, mOwn) or ContainsText_(Result, mName) or
      TUsesClauses.IsUsed(mUsed, mName, ANamespaces)) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

/// <summary>Gehört AName bei ATarget ins interface-uses?</summary>
function ToInterface(ATarget: TUsesAddTarget; const ANeeds: TArray<string>; const AName: string): Boolean;
begin
  Result := (ATarget = TUsesAddTarget.Interface_) or
    ((ATarget = TUsesAddTarget.Auto) and ContainsText_(ANeeds, AName));
end;

/// <summary>Hängt an AEdits ein Edit, das AUnits ins uses des Abschnitts an AOffset schreibt.</summary>
procedure AddSectionEdit(const ATokens: TArray<TPascalToken>; AOffset: Integer; const AUnits: TArray<string>;
  const ALineBreak: string; var AEdits: TArray<TTextEdit>);
var
  mEdit: TTextEdit;
begin
  if (Length(AUnits) > 0) and TUsesClauses.AddUnit(ATokens, AOffset, string.Join(', ', AUnits), ALineBreak,
    mEdit) then
  begin
    AEdits := AEdits + [mEdit];
  end;
end;

class function TUsesActions.AddUnits(const ATokens: TArray<TPascalToken>; const ARequest: TUsesAddRequest;
  out AEdits: TArray<TTextEdit>; out AAdded: TArray<string>): Boolean;
var
  mNeeds, mForInterface, mForImplementation: TArray<string>;
  mName: string;
  mInterfaceOffset, mImplementationOffset: Integer;
begin
  AEdits := nil;
  SectionOffsets(ATokens, mInterfaceOffset, mImplementationOffset);
  mNeeds := nil;
  if (ARequest.Target = TUsesAddTarget.Auto) and (mInterfaceOffset >= 0) and (mImplementationOffset >= 0) and
    Assigned(ARequest.Declaring) then
  begin
    mNeeds := InterfaceNeeds(ATokens, ARequest.Units, ARequest.Declaring);
  end;
  AAdded := NewUnits(ATokens, ARequest.Units, ARequest.Namespaces);
  mForInterface := nil;
  mForImplementation := nil;
  for mName in AAdded do
  begin
    if (mImplementationOffset < 0) or ToInterface(ARequest.Target, mNeeds, mName) then
    begin
      mForInterface := mForInterface + [mName];
    end
    else
    begin
      mForImplementation := mForImplementation + [mName];
    end;
  end;
  // Ein Edit je Abschnitt; Programme und Units ohne implementation haben nur ein uses.
  AddSectionEdit(ATokens, Max(0, mInterfaceOffset), mForInterface, ARequest.LineBreak, AEdits);
  AddSectionEdit(ATokens, mImplementationOffset, mForImplementation, ARequest.LineBreak, AEdits);
  Result := Length(AEdits) > 0;
  if not Result then
  begin
    AAdded := nil;
  end;
end;

end.
