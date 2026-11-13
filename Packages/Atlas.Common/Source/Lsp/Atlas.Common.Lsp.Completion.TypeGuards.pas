unit Atlas.Common.Lsp.Completion.TypeGuards;

// Typprüfungen in der Vervollständigung (#2107): Im then-Zweig von "if X is T then" (auch in einer and-Kette und
// nach "while X is T do") und nach "if not (X is T) then Exit;" bis zum Ende des Blocks gilt X als T. Nach "X."
// stehen dort die Mitglieder, die nur T hat, oben in der Liste; Übernehmen setzt die Umwandlung nach
// completion.senderCast ein. Nach "X is " bzw. "X as " stehen die Nachfahren des deklarierten Typs von X oben.
// Die Erkennung arbeitet auf den Token und engt im Zweifel nicht ein: nach einer Zuweisung an X, nach Übergabe
// von X an einen var- oder out-Parameter, in with-Blöcken und anonymen Methoden, bei Feldern nach jeder weiteren
// Anweisung.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Lsp.CompletionRequest;

type
  /// <summary>Kann das Argument AArgument (ab 0) des Aufrufs, dessen "(" am Token ACallOpen steht, als var oder
  /// out übergeben sein? Im Zweifel True.</summary>
  TTypeGuardArgumentFunc = reference to function(ACallOpen, AArgument: Integer): Boolean;

  /// <summary>Eine wirksame Typprüfung: der geprüfte Typ, wie er im Quelltext steht, und die Zeile (ab 0) des
  /// Worts is.</summary>
  TTypeGuard = record
    TypeName: string;
    Line: Integer;
  end;

  TCompletionTypeGuards = class
  public
    /// <summary>Typprüfung auf den Bezeichner am Token ASubject (Anfang der Kette vor dem Punkt), die dort gilt.
    /// AStrict für Felder, Eigenschaften und globale Variablen: nur, wenn zwischen Prüfung und ASubject keine
    /// weitere Anweisung steht, denn jeder Aufruf könnte sie ändern. AByRef beantwortet, ob ein Argument var oder
    /// out sein kann; ohne AByRef gilt jedes als solches. False ohne wirksame Prüfung.</summary>
    class function Find(const ATokens: TArray<TPascalToken>; ASubject: Integer; AStrict: Boolean;
      const AByRef: TTypeGuardArgumentFunc; out AGuard: TTypeGuard): Boolean; static;
    /// <summary>Nach "X." im Bereich einer Typprüfung auf T die Mitglieder von T, die der deklarierte Typ von X
    /// nicht hat. Jeder Eintrag trägt Narrowed und ersetzt "X.Na" durch die Umwandlung nach Settings.SenderCast
    /// und den Namen. False ohne Prüfung oder mit completion.typeGuards aus.</summary>
    class function MemberItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>): Boolean; static;
    /// <summary>Nach "X is " bzw. "X as ": die Liste der Typen, Nachfahren des deklarierten Typs von X mit
    /// DescendantOf. False an anderen Stellen, ohne Nachfahren in der Liste oder mit completion.typeGuards aus.
    /// </summary>
    class function DescendantItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; static;
    /// <summary>Ist der Parameter AIndex (ab 0) im Kopf ASignature ein var- oder out-Parameter? True auch, wenn
    /// der Kopf ihn nicht nennt (gekürzt oder andere Überladung).</summary>
    class function ParamByRef(const ASignature: string; AIndex: Integer): Boolean; static;
    /// <summary>Umwandlung von AName nach AType je nach completion.senderCast: "TFoo(X)" oder "(X as TFoo)".
    /// </summary>
    class function CastText(AHardCast: Boolean; const AType, AName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.Completion.Context,
  Atlas.Common.Lsp.Completion.Postfix,
  Atlas.Common.Lsp.Completion.Lists;

const
  /// <summary>So viele Token sucht Find höchstens rückwärts nach einer Prüfung.</summary>
  cMaxBackward = 4000;
  /// <summary>So viele Typen prüft DescendantItems höchstens auf ihre Abstammung.</summary>
  cMaxDescentChecks = 400;
  /// <summary>Eingebaute Routinen, die ihr Argument sicher nicht ändern; alle übrigen ohne Kopf gelten als var.
  /// </summary>
  cPlainIntrinsics: array[0..13] of string = ('Assigned', 'Length', 'High', 'Low', 'SizeOf', 'Ord', 'Chr', 'Pred',
    'Succ', 'Abs', 'TypeInfo', 'Copy', 'Odd', 'Format');

type
  /// <summary>Bereich, in dem eine Prüfung gilt: Token zwischen Start und Stop, beide ausgeschlossen.</summary>
  TGuardRegion = record
    Start: Integer;
    Stop: Integer;
  end;

  /// <summary>Eine Fundstelle "X is T" mit ihrer Bedingung.</summary>
  TGuardCandidate = record
    Subject: Integer;
    IsToken: Integer;
    TypeEnd: Integer;
    TypeName: string;
    Header: Integer;
    Connector: Integer;
  end;

  /// <summary>Die Suche einer Prüfung über die Token einer Unit.</summary>
  TGuardScan = record
    Tokens: TArray<TPascalToken>;
    Name: string;
    StrictOrder: Boolean;
    ByRef: TTypeGuardArgumentFunc;
    function Code(AIndex: Integer): TPascalToken;
    function Next(AIndex: Integer): Integer;
    function Prev(AIndex: Integer): Integer;
    function IsName(AIndex: Integer): Boolean;
    function BlockEnd(AFrom: Integer): Integer;
    function MatchingEnd(ABegin: Integer): Integer;
    function StatementEnd(AFrom: Integer): Integer;
    function ParseType(var ACandidate: TGuardCandidate): Boolean;
    function HeaderBefore(ASubject: Integer): Integer;
    function ConnectorAfter(AHeader, AFrom: Integer): Integer;
    function ParseCandidate(AIsToken: Integer; out ACandidate: TGuardCandidate): Boolean;
    function ConditionHas(const ACandidate: TGuardCandidate; const AWords: array of string): Boolean;
    function Atom(const ACandidate: TGuardCandidate; out AStart, AStop: Integer): Boolean;
    function JumpEnd(AFrom: Integer): Integer;
    function BranchJumpEnd(AFrom: Integer): Integer;
    function StandsAlone(AHeader: Integer): Boolean;
    function NegatedRegion(const ACandidate: TGuardCandidate; out ARegion: TGuardRegion): Boolean;
    function PositiveRegion(const ACandidate: TGuardCandidate; out ARegion: TGuardRegion): Boolean;
    function Region(const ACandidate: TGuardCandidate; out ARegion: TGuardRegion): Boolean;
    function EnclosingCall(AFrom: Integer; out AOpen, AArgument: Integer): Boolean;
    function ArgumentChanges(AIndex: Integer): Boolean;
    function Changed(const ARegion: TGuardRegion; ASubject: Integer): Boolean;
    function Covers(AIsToken, ASubject: Integer; out ACandidate: TGuardCandidate): Boolean;
  end;

/// <summary>Beginnt hier ein Block, der mit end schließt?</summary>
function OpensBlock(const AToken: TPascalToken): Boolean;
begin
  Result := IsKeywordIn(AToken, ['begin', 'case', 'try', 'asm']);
end;

/// <summary>Beginnt hier eine Routine (auch eine anonyme) oder ein anderer Abschnitt der Unit?</summary>
function StartsRoutine(const AToken: TPascalToken): Boolean;
begin
  Result := IsKeywordIn(AToken, ['procedure', 'function', 'constructor', 'destructor', 'implementation',
    'initialization', 'finalization']);
end;

/// <summary>Beendet dieses Token rückwärts gelesen die Bedingung vor einer Prüfung, ohne if oder while?</summary>
function EndsConditionBackward(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or AToken.IsSymbol(':=') or IsKeywordIn(AToken, ['begin', 'end', 'then', 'do',
    'else', 'try', 'repeat', 'until', 'except', 'finally', 'of', 'case', 'with']);
end;

/// <summary>Beendet dieses Token vorwärts gelesen die Bedingung hinter einer Prüfung ohne passendes then/do?
/// </summary>
function EndsConditionForward(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or AToken.IsSymbol(':=') or
    IsKeywordIn(AToken, ['begin', 'end', 'then', 'do', 'else']);
end;

/// <summary>Grenzt AToken ein Argument ab: die Klammer ABracket oder ein Komma?</summary>
function BoundsArgument(const AToken: TPascalToken; const ABracket: string): Boolean;
begin
  Result := AToken.IsSymbol(ABracket) or AToken.IsSymbol(',');
end;

/// <summary>Liegt AIndex im Bereich ARegion?</summary>
function InRegion(const ARegion: TGuardRegion; AIndex: Integer): Boolean;
begin
  Result := (ARegion.Start < AIndex) and (AIndex < ARegion.Stop);
end;

{ TGuardScan }

function TGuardScan.Code(AIndex: Integer): TPascalToken;
begin
  if (AIndex < 0) or (AIndex > High(Tokens)) then
  begin
    Result := Default(TPascalToken);
    Result.Kind := TPascalTokenKind.Unknown;
    Exit;
  end;
  Result := Tokens[AIndex];
end;

function TGuardScan.Next(AIndex: Integer): Integer;
begin
  Result := NextCode(Tokens, AIndex + 1);
end;

function TGuardScan.Prev(AIndex: Integer): Integer;
begin
  Result := PreviousCode(Tokens, AIndex);
end;

function TGuardScan.IsName(AIndex: Integer): Boolean;
begin
  // Derselbe Bezeichner, nicht Mitglied eines anderen Ausdrucks (Foo.X).
  Result := (Code(AIndex).Kind = TPascalTokenKind.Identifier) and SameText(CleanName(Code(AIndex).Text), Name) and
    not Code(Prev(AIndex)).IsSymbol('.');
end;

function TGuardScan.MatchingEnd(ABegin: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := ABegin;
  while Result <= High(Tokens) do
  begin
    if OpensBlock(Tokens[Result]) then
    begin
      Inc(mDepth);
    end
    else if Tokens[Result].IsKeyword('end') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
    Result := Next(Result);
  end;
  // Unfertiger Code: Der Block reicht bis zum Ende.
  Result := Length(Tokens);
end;

function TGuardScan.BlockEnd(AFrom: Integer): Integer;
var
  mDepth: Integer;
begin
  // Erstes end, until, except oder finally auf derselben Ebene: Ende des umgebenden Blocks.
  mDepth := 0;
  Result := Next(AFrom);
  while Result <= High(Tokens) do
  begin
    if OpensBlock(Tokens[Result]) or Tokens[Result].IsKeyword('repeat') then
    begin
      Inc(mDepth);
    end
    else if IsKeywordIn(Tokens[Result], ['end', 'until']) then
    begin
      if mDepth = 0 then
      begin
        Exit;
      end;
      Dec(mDepth);
    end
    else if (mDepth = 0) and IsKeywordIn(Tokens[Result], ['except', 'finally']) then
    begin
      Exit;
    end;
    Result := Next(Result);
  end;
  Result := Length(Tokens);
end;

function TGuardScan.StatementEnd(AFrom: Integer): Integer;
var
  mDepth: Integer;
begin
  // Ende einer einzelnen Anweisung: ";" oder ein Wort, das sie abschließt, auf Ebene 0.
  mDepth := 0;
  Result := AFrom;
  while Result <= High(Tokens) do
  begin
    if OpensBlock(Tokens[Result]) or Tokens[Result].IsSymbol('(') or Tokens[Result].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if Tokens[Result].IsKeyword('end') or Tokens[Result].IsSymbol(')') or Tokens[Result].IsSymbol(']') then
    begin
      if mDepth = 0 then
      begin
        Exit;
      end;
      Dec(mDepth);
    end
    else if (mDepth = 0) and (Tokens[Result].IsSymbol(';') or
      IsKeywordIn(Tokens[Result], ['else', 'until', 'except', 'finally'])) then
    begin
      Exit;
    end;
    Result := Next(Result);
  end;
  Result := Length(Tokens);
end;

function TGuardScan.ParseType(var ACandidate: TGuardCandidate): Boolean;
begin
  ACandidate.TypeEnd := Next(ACandidate.IsToken);
  Result := IsName(ACandidate.Subject) and (Code(ACandidate.TypeEnd).Kind = TPascalTokenKind.Identifier);
  if not Result then
  begin
    Exit;
  end;
  // Typname, auch mit Unit davor (System.JSON.TJSONObject).
  ACandidate.TypeName := Tokens[ACandidate.TypeEnd].Text;
  while Code(Next(ACandidate.TypeEnd)).IsSymbol('.') and
    (Code(Next(Next(ACandidate.TypeEnd))).Kind = TPascalTokenKind.Identifier) do
  begin
    ACandidate.TypeEnd := Next(Next(ACandidate.TypeEnd));
    ACandidate.TypeName := ACandidate.TypeName + '.' + Tokens[ACandidate.TypeEnd].Text;
  end;
  // Generische Typen (TList<T>) bleiben außen vor.
  Result := not Code(Next(ACandidate.TypeEnd)).IsSymbol('<');
end;

function TGuardScan.HeaderBefore(ASubject: Integer): Integer;
begin
  // Rückwärts bis zum if bzw. while der Bedingung; eine andere Anweisung dazwischen heißt: keine Bedingung (-1).
  Result := Prev(ASubject);
  while (Result >= 0) and not IsKeywordIn(Tokens[Result], ['if', 'while']) do
  begin
    if EndsConditionBackward(Tokens[Result]) then
    begin
      Exit(-1);
    end;
    Result := Prev(Result);
  end;
end;

function TGuardScan.ConnectorAfter(AHeader, AFrom: Integer): Integer;
var
  mConnector: string;
begin
  // Vorwärts bis zum then bzw. do; -1, wenn die Bedingung vorher endet.
  mConnector := 'then';
  if Tokens[AHeader].IsKeyword('while') then
  begin
    mConnector := 'do';
  end;
  Result := Next(AFrom);
  while (Result <= High(Tokens)) and not Tokens[Result].IsKeyword(mConnector) do
  begin
    if EndsConditionForward(Tokens[Result]) then
    begin
      Exit(-1);
    end;
    Result := Next(Result);
  end;
  if Result > High(Tokens) then
  begin
    Result := -1;
  end;
end;

function TGuardScan.ParseCandidate(AIsToken: Integer; out ACandidate: TGuardCandidate): Boolean;
begin
  ACandidate := Default(TGuardCandidate);
  ACandidate.IsToken := AIsToken;
  ACandidate.Subject := Prev(AIsToken);
  Result := ParseType(ACandidate);
  if Result then
  begin
    ACandidate.Header := HeaderBefore(ACandidate.Subject);
    Result := ACandidate.Header >= 0;
  end;
  if Result then
  begin
    ACandidate.Connector := ConnectorAfter(ACandidate.Header, ACandidate.TypeEnd);
    Result := ACandidate.Connector >= 0;
  end;
end;

function TGuardScan.ConditionHas(const ACandidate: TGuardCandidate; const AWords: array of string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := Next(ACandidate.Header);
  while mIndex < ACandidate.Connector do
  begin
    if IsKeywordIn(Tokens[mIndex], AWords) then
    begin
      Exit(True);
    end;
    mIndex := Next(mIndex);
  end;
  Result := False;
end;

function TGuardScan.Atom(const ACandidate: TGuardCandidate; out AStart, AStop: Integer): Boolean;
var
  mIndex, mOpen: Integer;
begin
  // "X is T" samt Klammern, die nur es umschließen.
  AStart := ACandidate.Subject;
  AStop := ACandidate.TypeEnd;
  while Code(Prev(AStart)).IsSymbol('(') and Code(Next(AStop)).IsSymbol(')') and
    (MatchingParen(Tokens, Prev(AStart)) = Next(AStop)) do
  begin
    AStart := Prev(AStart);
    AStop := Next(AStop);
  end;
  // Ein not vor einer größeren Klammer um die Prüfung kehrt sie mit anderen Teilen um: nicht auswerten.
  mIndex := Next(ACandidate.Header);
  while mIndex < ACandidate.Connector do
  begin
    mOpen := Next(mIndex);
    if Tokens[mIndex].IsKeyword('not') and (mOpen < AStart) and Code(mOpen).IsSymbol('(') and
      (MatchingParen(Tokens, mOpen) > AStop) then
    begin
      Exit(False);
    end;
    mIndex := Next(mIndex);
  end;
  Result := True;
end;

function TGuardScan.JumpEnd(AFrom: Integer): Integer;
var
  mIndex: Integer;
begin
  // Exit, Exit(…), Continue, Break oder raise …: Index des Tokens hinter der Anweisung; -1 bei anderen.
  Result := -1;
  if IsKeywordIn(Code(AFrom), ['raise']) then
  begin
    Exit(StatementEnd(Next(AFrom)));
  end;
  if (Code(AFrom).Kind <> TPascalTokenKind.Identifier) or
    not MatchText(Code(AFrom).Text, ['Exit', 'Continue', 'Break']) then
  begin
    Exit;
  end;
  mIndex := Next(AFrom);
  if Code(mIndex).IsSymbol('(') then
  begin
    mIndex := MatchingParen(Tokens, mIndex);
    if mIndex < 0 then
    begin
      Exit;
    end;
    mIndex := Next(mIndex);
  end;
  Result := mIndex;
end;

function TGuardScan.BranchJumpEnd(AFrom: Integer): Integer;
begin
  // Sprung, auch in begin … end: Index hinter dem Zweig; -1 bei einem anderen Zweig.
  if not Code(AFrom).IsKeyword('begin') then
  begin
    Exit(JumpEnd(AFrom));
  end;
  Result := JumpEnd(Next(AFrom));
  if (Result >= 0) and Code(Result).IsSymbol(';') then
  begin
    Result := Next(Result);
  end;
  if (Result >= 0) and Code(Result).IsKeyword('end') then
  begin
    Result := Next(Result);
  end
  else
  begin
    Result := -1;
  end;
end;

function TGuardScan.StandsAlone(AHeader: Integer): Boolean;
var
  mBefore: TPascalToken;
begin
  // Ein if als eigene Anweisung im Block.
  mBefore := Code(Prev(AHeader));
  Result := Tokens[AHeader].IsKeyword('if') and (mBefore.IsSymbol(';') or
    IsKeywordIn(mBefore, ['begin', 'try', 'repeat', 'finally', 'except']));
end;

function TGuardScan.NegatedRegion(const ACandidate: TGuardCandidate; out ARegion: TGuardRegion): Boolean;
var
  mIndex: Integer;
begin
  ARegion := Default(TGuardRegion);
  // Nur "if … or not (X is T) then <Sprung>;" als eigene Anweisung im Block.
  Result := StandsAlone(ACandidate.Header) and not ConditionHas(ACandidate, ['and', 'xor']);
  if not Result then
  begin
    Exit;
  end;
  mIndex := BranchJumpEnd(Next(ACandidate.Connector));
  // Ein else gehört zur Prüfung: dann gilt sie danach nicht.
  Result := (mIndex >= 0) and Code(mIndex).IsSymbol(';');
  if Result then
  begin
    ARegion.Start := mIndex;
    ARegion.Stop := BlockEnd(mIndex);
  end;
end;

function TGuardScan.PositiveRegion(const ACandidate: TGuardCandidate; out ARegion: TGuardRegion): Boolean;
var
  mIndex: Integer;
begin
  ARegion := Default(TGuardRegion);
  Result := not ConditionHas(ACandidate, ['or', 'xor']);
  if not Result then
  begin
    Exit;
  end;
  mIndex := Next(ACandidate.Connector);
  if Code(mIndex).IsKeyword('begin') then
  begin
    ARegion.Start := mIndex;
    ARegion.Stop := MatchingEnd(mIndex);
  end
  else
  begin
    ARegion.Start := ACandidate.Connector;
    ARegion.Stop := StatementEnd(mIndex);
  end;
end;

function TGuardScan.Region(const ACandidate: TGuardCandidate; out ARegion: TGuardRegion): Boolean;
var
  mStart, mStop: Integer;
begin
  ARegion := Default(TGuardRegion);
  if not Atom(ACandidate, mStart, mStop) then
  begin
    Exit(False);
  end;
  if Code(Prev(mStart)).IsKeyword('not') then
  begin
    Result := NegatedRegion(ACandidate, ARegion);
  end
  else
  begin
    Result := PositiveRegion(ACandidate, ARegion);
  end;
end;

function TGuardScan.EnclosingCall(AFrom: Integer; out AOpen, AArgument: Integer): Boolean;
var
  mDepth: Integer;
begin
  // Rückwärts zum "(" des Aufrufs und Nummer des Arguments; False in eckigen Klammern (Index oder Menge).
  // AOpen ist -1 ohne öffnende Klammer (unfertiger Code).
  AOpen := AFrom;
  AArgument := 0;
  mDepth := 0;
  Result := True;
  while Result and (AOpen >= 0) and not ((mDepth = 0) and Tokens[AOpen].IsSymbol('(')) do
  begin
    if Tokens[AOpen].IsSymbol(')') or Tokens[AOpen].IsSymbol(']') then
    begin
      Inc(mDepth);
    end
    else if Tokens[AOpen].IsSymbol('(') or Tokens[AOpen].IsSymbol('[') then
    begin
      Result := mDepth > 0;
      Dec(mDepth);
    end
    else if (mDepth = 0) and Tokens[AOpen].IsSymbol(',') then
    begin
      Inc(AArgument);
    end;
    AOpen := Prev(AOpen);
  end;
end;

function TGuardScan.ArgumentChanges(AIndex: Integer): Boolean;
var
  mBefore, mOpen, mArgument: Integer;
begin
  // Steht X allein als Argument eines Aufrufs, kann er var oder out sein.
  mBefore := Prev(AIndex);
  Result := BoundsArgument(Code(mBefore), '(') and BoundsArgument(Code(Next(AIndex)), ')') and
    EnclosingCall(mBefore, mOpen, mArgument);
  if Result and (mOpen >= 0) and Assigned(ByRef) then
  begin
    Result := ByRef(mOpen, mArgument);
  end;
end;

function TGuardScan.Changed(const ARegion: TGuardRegion; ASubject: Integer): Boolean;
var
  mIndex, mStop: Integer;
  mLoop: Boolean;
begin
  // In einer Schleife zwischen Prüfung und Stelle zählt auch, was danach im Bereich mit X geschieht.
  mLoop := False;
  mIndex := Next(ARegion.Start);
  while mIndex < ASubject do
  begin
    mLoop := mLoop or IsKeywordIn(Tokens[mIndex], ['while', 'for', 'repeat']);
    if IsKeywordIn(Tokens[mIndex], ['with', 'procedure', 'function']) or
      (StrictOrder and Tokens[mIndex].IsSymbol(';')) then
    begin
      Exit(True);
    end;
    mIndex := Next(mIndex);
  end;
  mStop := ASubject;
  if mLoop then
  begin
    mStop := ARegion.Stop;
  end;
  mIndex := Next(ARegion.Start);
  while (mIndex < mStop) and (mIndex <= High(Tokens)) do
  begin
    if (mIndex <> ASubject) and IsName(mIndex) and
      (Code(Next(mIndex)).IsSymbol(':=') or ArgumentChanges(mIndex)) then
    begin
      Exit(True);
    end;
    mIndex := Next(mIndex);
  end;
  Result := False;
end;

function TGuardScan.Covers(AIsToken, ASubject: Integer; out ACandidate: TGuardCandidate): Boolean;
var
  mRegion: TGuardRegion;
begin
  // Prüfung am Token AIsToken, die an ASubject gilt und bis dahin nicht aufgehoben ist.
  Result := ParseCandidate(AIsToken, ACandidate) and Region(ACandidate, mRegion) and InRegion(mRegion, ASubject) and
    not Changed(mRegion, ASubject);
end;

{ Hilfen für MemberItems und DescendantItems }

/// <summary>Index des Tokens, das an APosition beginnt; -1 ohne.</summary>
function TokenStartingAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    if ComparePositions(ATokens[mIndex].StartPos, APosition) = 0 then
    begin
      Exit(mIndex);
    end;
    if ComparePositions(ATokens[mIndex].StartPos, APosition) > 0 then
    begin
      Break;
    end;
  end;
  Result := -1;
end;

/// <summary>Bezeichnerkette vor dem "(" an AOpen ("Liste.Add"); nil, wenn davor keine steht.</summary>
function CalleeNames(const ATokens: TArray<TPascalToken>; AOpen: Integer; out ALast: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  ALast := PreviousCode(ATokens, AOpen);
  mIndex := ALast;
  while (mIndex >= 0) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) do
  begin
    Result := [CleanName(ATokens[mIndex].Text)] + Result;
    mIndex := PreviousCode(ATokens, mIndex);
    if (mIndex < 0) or not ATokens[mIndex].IsSymbol('.') then
    begin
      Break;
    end;
    mIndex := PreviousCode(ATokens, mIndex);
  end;
end;

/// <summary>Kann ASymbol sein Argument AArgument ändern?</summary>
function SymbolChanges(const ASymbol: TResolvedSymbol; AArgument: Integer): Boolean;
begin
  if ASymbol.IsType then
  begin
    // Typumwandlung TFoo(X).
    Result := False;
  end
  else if ASymbol.Builtin then
  begin
    Result := not MatchText(ASymbol.Name, cPlainIntrinsics);
  end
  else if ASymbol.Signature = '' then
  begin
    Result := True;
  end
  else
  begin
    Result := TCompletionTypeGuards.ParamByRef(ASymbol.Signature, AArgument);
  end;
end;

/// <summary>AByRef für Find über den Resolver von ARequest: alle Überladungen des Aufrufs; unbekannte gelten als
/// var.</summary>
function ResolverByRef(ARequest: TCompletionRequest): TTypeGuardArgumentFunc;
begin
  Result :=
    function(ACallOpen, AArgument: Integer): Boolean
    var
      mLast: Integer;
      mCandidates: TArray<TResolvedSymbol>;
      mCandidate: TResolvedSymbol;
    begin
      if CalleeNames(ARequest.Tree.Tokens, ACallOpen, mLast) = nil then
      begin
        Exit(True);
      end;
      mCandidates := ARequest.Resolver.ResolveAll(ARequest.Tree, ARequest.FileName,
        ARequest.Tree.Tokens[mLast].StartPos);
      Result := Length(mCandidates) = 0;
      for mCandidate in mCandidates do
      begin
        Result := Result or SymbolChanges(mCandidate, AArgument);
      end;
    end;
end;

/// <summary>Namen der Mitglieder des deklarierten Typs von ANames an AOffset, klein geschrieben.</summary>
function DeclaredNames(ARequest: TCompletionRequest; const ANames: TArray<string>;
  AOffset: Integer): TDictionary<string, Boolean>;
var
  mMember: TResolvedSymbol;
begin
  Result := TDictionary<string, Boolean>.Create;
  for mMember in ARequest.Resolver.Candidates.MemberCandidates(ARequest.Tree, ARequest.FileName, ANames, AOffset) do
  begin
    Result.AddOrSetValue(LowerCase(mMember.Name), True);
  end;
end;

/// <summary>Mitglieder von ACastType über den Text, in dem die Kette vor dem Punkt durch "T(X)" ersetzt ist; die
/// Position rückt um den Unterschied nach rechts.</summary>
function CastMembers(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  const ACastType: string): TCompletionItems;
var
  mLines: TArray<string>;
  mLine, mCast: string;
  mPosition: TTextPosition;
  mRequest: TCompletionRequest;
  mPostfix: TPostfixOptions;
begin
  mLines := Copy(ARequest.Lines);
  mLine := mLines[AContext.ChainStart.Line];
  mCast := ACastType + '(' + AContext.Names[0] + ')';
  mLines[AContext.ChainStart.Line] := Copy(mLine, 1, AContext.ChainStart.Character) + mCast +
    Copy(mLine, AContext.DotPos.Character + 1, MaxInt);
  mPosition := ARequest.Position;
  mPosition.Character := mPosition.Character + Length(mCast) -
    (AContext.DotPos.Character - AContext.ChainStart.Character);
  mRequest := TCompletionRequest.Create(string.Join(ARequest.LineBreak, mLines), ARequest.FileName, mPosition);
  try
    mRequest.Tree := TSyntaxTreeCache.Parse(mRequest.Text);
    try
      mRequest.Resolver := ARequest.Resolver;
      mRequest.Index := ARequest.Index;
      mRequest.Matching := ARequest.Matching;
      mRequest.Settings := ARequest.Settings;
      mPostfix := TPostfixOptions.Default;
      mPostfix.Enabled := False;
      Result := TCompletionLists.Collect(mRequest, mPostfix, nil);
    finally
      mRequest.Tree.Free;
    end;
  finally
    mRequest.Free;
  end;
end;

/// <summary>Einträge aus AMembers, die der deklarierte Typ nicht hat, mit Umwandlung und Herkunft der Prüfung.
/// </summary>
function NarrowedItems(ARequest: TCompletionRequest; const AContext: TCompletionContext; const AGuard: TTypeGuard;
  const AMembers: TCompletionItems): TArray<TCompletionItem>;
var
  mDeclared: TDictionary<string, Boolean>;
  mItem, mNarrowed: TCompletionItem;
  mItems: TList<TCompletionItem>;
  mCast, mName: string;
begin
  mCast := TCompletionTypeGuards.CastText(ARequest.Settings.SenderCast = TCompletionSenderCast.HardCast,
    AGuard.TypeName, AContext.Names[0]);
  mDeclared := DeclaredNames(ARequest, AContext.Names, AContext.Offset);
  mItems := TList<TCompletionItem>.Create;
  try
    for mItem in AMembers.Items do
    begin
      // Eigene Änderungen stünden im umgeschriebenen Text; Schlüsselwörter gehören nicht zum Typ.
      if mItem.HasTextEdit or (mItem.Kind = cKindKeyword) or mDeclared.ContainsKey(LowerCase(mItem.Name)) then
      begin
        Continue;
      end;
      mName := mItem.InsertText;
      if mName = '' then
      begin
        mName := mItem.Name;
      end;
      mNarrowed := mItem;
      mNarrowed.Narrowed := AGuard.TypeName;
      mNarrowed.NarrowedName := AContext.Names[0];
      mNarrowed.NarrowedLine := AGuard.Line + 1;
      mNarrowed.HasTextEdit := True;
      mNarrowed.TextEdit := TRuleEdit.Create(TTextRange.Create(AContext.ChainStart, ARequest.Position),
        mCast + '.' + mName);
      mItems.Add(mNarrowed);
    end;
    Result := mItems.ToArray;
  finally
    mItems.Free;
    mDeclared.Free;
  end;
end;

/// <summary>Ist ATypeName an AOffset ein Typ, und nicht schon der deklarierte Typ von ASubject?</summary>
function NarrowsTo(ARequest: TCompletionRequest; const ASubject: TResolvedSymbol; const ATypeName: string;
  AOffset: Integer): Boolean;
var
  mGuardType, mDeclared: TResolvedSymbol;
begin
  mGuardType := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName, ATypeName.Split(['.']),
    AOffset);
  Result := mGuardType.Found and mGuardType.IsType;
  if Result and ARequest.Resolver.TypeOf(ASubject, mDeclared) then
  begin
    Result := not SameText(mDeclared.QualifiedName, mGuardType.QualifiedName);
  end;
end;

/// <summary>Kette vor "is"/"as" an AOperator ("Liste.Wert"); nil ohne einfache Kette.</summary>
function SubjectBefore(const ATokens: TArray<TPascalToken>; AOperator: Integer; out AFirst: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  AFirst := -1;
  mIndex := PreviousCode(ATokens, AOperator);
  while (mIndex >= 0) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) do
  begin
    Result := [CleanName(ATokens[mIndex].Text)] + Result;
    AFirst := mIndex;
    mIndex := PreviousCode(ATokens, mIndex);
    if (mIndex < 0) or not ATokens[mIndex].IsSymbol('.') then
    begin
      Exit;
    end;
    mIndex := PreviousCode(ATokens, mIndex);
  end;
  // Kette endet mit einem Punkt ohne Bezeichner davor oder hinter einem Aufruf: nicht einfach.
  Result := nil;
end;

/// <summary>Token is bzw. as vor dem getippten Wort an APosition; -1 an anderen Stellen.</summary>
function TypeOperatorBefore(ARequest: TCompletionRequest): Integer;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  mTokens := ARequest.Tree.Tokens;
  mIndex := PreviousCode(mTokens, TokenFrom(mTokens, ARequest.OffsetAt(ARequest.Position)));
  if (mIndex >= 0) and (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
    (ComparePositions(mTokens[mIndex].EndPos, ARequest.Position) = 0) then
  begin
    mIndex := PreviousCode(mTokens, mIndex);
  end;
  // Verneinte Prüfung mit not hinter dem is (Delphi 13).
  if (mIndex > 0) and mTokens[mIndex].IsKeyword('not') then
  begin
    mIndex := PreviousCode(mTokens, mIndex);
  end;
  Result := -1;
  if (mIndex >= 0) and IsKeywordIn(mTokens[mIndex], ['is', 'as']) then
  begin
    Result := mIndex;
  end;
end;

/// <summary>Setzt DescendantOf bei den Klassen in AItems, die von ABase abstammen; True, wenn eine darunter ist.
/// </summary>
function MarkDescendants(ARequest: TCompletionRequest; const ABase: TResolvedSymbol; AOffset: Integer;
  var AItems: TCompletionItems): Boolean;
var
  mIndex, mChecks: Integer;
begin
  Result := False;
  mChecks := 0;
  for mIndex := 0 to High(AItems.Items) do
  begin
    if (AItems.Items[mIndex].Kind <> cKindClass) or SameText(AItems.Items[mIndex].Name, ABase.Name) or
      (mChecks >= cMaxDescentChecks) then
    begin
      Continue;
    end;
    Inc(mChecks);
    if ARequest.Resolver.Queries.TypeDescendsFrom(ARequest.Tree, ARequest.FileName, AOffset,
      AItems.Items[mIndex].Name, ABase.Name) then
    begin
      AItems.Items[mIndex].DescendantOf := ABase.Name;
      Result := True;
    end;
  end;
end;

/// <summary>Parametergruppen des Kopfs ASignature, getrennt bei ";" auf Ebene 0 bis zur schließenden Klammer;
/// nil ohne Klammer.</summary>
function ParameterGroups(const ASignature: string): TArray<string>;
var
  mOpen, mDepth, mPosition, mStart: Integer;
begin
  Result := nil;
  mOpen := Pos('(', ASignature);
  mDepth := 0;
  mStart := mOpen + 1;
  mPosition := mOpen + 1;
  while (mOpen > 0) and (mPosition <= Length(ASignature)) do
  begin
    if CharInSet(ASignature[mPosition], ['(', '[', '<']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(ASignature[mPosition], [')', ']', '>']) and (mDepth > 0) then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and CharInSet(ASignature[mPosition], [';', ')']) then
    begin
      Result := Result + [Trim(Copy(ASignature, mStart, mPosition - mStart))];
      mStart := mPosition + 1;
      if ASignature[mPosition] = ')' then
      begin
        Exit;
      end;
    end;
    Inc(mPosition);
  end;
end;

{ TCompletionTypeGuards }

class function TCompletionTypeGuards.Find(const ATokens: TArray<TPascalToken>; ASubject: Integer; AStrict: Boolean;
  const AByRef: TTypeGuardArgumentFunc; out AGuard: TTypeGuard): Boolean;
var
  mScan: TGuardScan;
  mIndex, mSteps: Integer;
  mCandidate: TGuardCandidate;
begin
  AGuard := Default(TTypeGuard);
  Result := False;
  if (ASubject < 0) or (ASubject > High(ATokens)) or (ATokens[ASubject].Kind <> TPascalTokenKind.Identifier) then
  begin
    Exit;
  end;
  mScan.Tokens := ATokens;
  mScan.Name := CleanName(ATokens[ASubject].Text);
  mScan.StrictOrder := AStrict;
  mScan.ByRef := AByRef;
  mIndex := PreviousCode(ATokens, ASubject);
  mSteps := 0;
  // Rückwärts bis zum Anfang der Routine; die nächste wirksame Prüfung gilt.
  while (mIndex >= 0) and (mSteps < cMaxBackward) and not StartsRoutine(ATokens[mIndex]) do
  begin
    if ATokens[mIndex].IsKeyword('is') and mScan.Covers(mIndex, ASubject, mCandidate) then
    begin
      AGuard.TypeName := mCandidate.TypeName;
      AGuard.Line := ATokens[mCandidate.IsToken].StartPos.Line;
      Exit(True);
    end;
    mIndex := PreviousCode(ATokens, mIndex);
    Inc(mSteps);
  end;
end;

class function TCompletionTypeGuards.MemberItems(ARequest: TCompletionRequest;
  out AItems: TArray<TCompletionItem>): Boolean;
var
  mContext: TCompletionContext;
  mSubjectToken: Integer;
  mSubject: TResolvedSymbol;
  mGuard: TTypeGuard;
begin
  AItems := nil;
  Result := False;
  if not ARequest.Settings.TypeGuards or (ARequest.Tree = nil) or (ARequest.Resolver = nil) then
  begin
    Exit;
  end;
  mContext := TCompletionContexts.Analyze(ARequest.Tree, ARequest.Position);
  if (mContext.Kind <> TCompletionContextKind.Member) or (Length(mContext.Names) <> 1) or mContext.Called or
    (mContext.ChainStart.Line <> ARequest.Position.Line) or (mContext.DotPos.Line <> ARequest.Position.Line) then
  begin
    Exit;
  end;
  mSubjectToken := TokenStartingAt(ARequest.Tree.Tokens, mContext.ChainStart);
  mSubject := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName, mContext.Names, mContext.Offset);
  if not mSubject.Found or mSubject.IsType or (mSubject.Kind = TResolvedKind.UnitName) or
    not Find(ARequest.Tree.Tokens, mSubjectToken, mSubject.Kind <> TResolvedKind.Local, ResolverByRef(ARequest),
    mGuard) or not NarrowsTo(ARequest, mSubject, mGuard.TypeName, mContext.Offset) then
  begin
    Exit;
  end;
  AItems := NarrowedItems(ARequest, mContext, mGuard, CastMembers(ARequest, mContext, mGuard.TypeName));
  Result := Length(AItems) > 0;
end;

class function TCompletionTypeGuards.DescendantItems(ARequest: TCompletionRequest;
  out AItems: TCompletionItems): Boolean;
var
  mOperator, mFirst: Integer;
  mNames: TArray<string>;
  mChain: TResolvedChainType;
  mPostfix: TPostfixOptions;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  if not ARequest.Settings.TypeGuards or (ARequest.Tree = nil) or (ARequest.Resolver = nil) then
  begin
    Exit;
  end;
  mOperator := TypeOperatorBefore(ARequest);
  if mOperator < 0 then
  begin
    Exit;
  end;
  mNames := SubjectBefore(ARequest.Tree.Tokens, mOperator, mFirst);
  if (mNames = nil) or not ARequest.Resolver.ChainType(ARequest.Tree, ARequest.FileName, mNames,
    ARequest.Tree.Tokens[mOperator].Offset, mChain) or not mChain.TypeFound or
    (mChain.TypeInfo.SymbolKind <> TIndexSymbolKind.ClassType) then
  begin
    Exit;
  end;
  mPostfix := TPostfixOptions.Default;
  mPostfix.Enabled := False;
  AItems := TCompletionLists.Collect(ARequest, mPostfix, nil);
  Result := MarkDescendants(ARequest, mChain.TypeInfo, ARequest.Tree.Tokens[mOperator].Offset, AItems);
end;

class function TCompletionTypeGuards.ParamByRef(const ASignature: string; AIndex: Integer): Boolean;
var
  mGroup, mNames: string;
  mCount: Integer;
begin
  mCount := 0;
  for mGroup in ParameterGroups(ASignature) do
  begin
    // "var A, B: Integer" zählt zwei Parameter.
    mNames := mGroup;
    if Pos(':', mNames) > 0 then
    begin
      mNames := Copy(mNames, 1, Pos(':', mNames) - 1);
    end;
    Inc(mCount, Length(mNames.Split([','])));
    if AIndex < mCount then
    begin
      Exit(StartsText('var ', mGroup) or StartsText('out ', mGroup));
    end;
  end;
  // Kein Kopf oder Parameter nicht genannt: im Zweifel var.
  Result := True;
end;

class function TCompletionTypeGuards.CastText(AHardCast: Boolean; const AType, AName: string): string;
begin
  if AHardCast then
  begin
    Result := AType + '(' + AName + ')';
  end
  else
  begin
    Result := '(' + AName + ' as ' + AType + ')';
  end;
end;

end.
