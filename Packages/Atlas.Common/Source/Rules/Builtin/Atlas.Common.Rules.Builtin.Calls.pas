unit Atlas.Common.Rules.Builtin.Calls;

// Regeln für Aufrufe (#909, Gruppe Compiler vorab):
//   argument-count-mismatch  Ein Aufruf hat mehr Argumente als die Routine
//                            Parameter (#1007, wie E2034) oder weniger als
//                            Parameter ohne Standardwert (wie E2035), auch
//                            als Anweisung ohne Klammern (Versenden;).
//
// Die Kandidaten hinter dem Namen liefert TNameResolver.CallCandidates ohne
// Auswahl nach den Argumenten. Gemeldet wird nur bei genau einer Routine:
// Überladungen (overload, weitere Köpfe gleichen Namens auch in Vorfahren
// oder Helfern), varargs, Typumwandlungen, Variablen und Properties von
// prozeduralem Typ, Bezeichner von System ohne Quelltext und Deklarationen
// in bedingten Zweigen überlässt die Regel dem Compiler: aus dem Index mit
// Bedingung, aus dieser Datei, wenn die Deklaration nicht immer mit dem
// Aufruf übersetzt wird (Pascal.ConditionalBranches; der Baum enthält beide
// Zweige von {$IFDEF} … {$ELSE}). Ebenso Namen, die ein Mitglied eines
// Vorfahren außerhalb des Index verdecken kann (#1326: Read im with eines
// TMemoryStream-Nachfahren, Error in einem TStrings-Nachfahren). Ein Rumpf ohne
// Parameterliste neben seiner Deklaration zählt nicht als zweiter Kopf. Hat
// eine Funktion zu viele Argumente, muss ihr Ergebnistyp sicher bekannt und
// nicht prozedural sein (F(1) könnte sonst das Ergebnis aufrufen).
//
//   overload-resolution      Keine Überladung passt zu den Argumenten (#1371,
//                            wie E2250) oder mehrere passen gleich gut (wie
//                            E2251).
//
// Korrektur „Signaturhilfe öffnen“: springt in die Klammern des Aufrufs und
// öffnet dort den Parameter-Hint (Client-Befehl atlas.showSignatureHelp);
// ohne Klammern setzt sie zuerst () hinter den Namen.
//
// overload-resolution meldet nie mehr als dcc (#1328) und prüft deshalb nur,
// wenn die Kandidatenliste vollständig ist: Der Index kennt System und alle
// Units in uses (Überladungen gleichen Namens aus anderen Units zählt dcc mit;
// für freie Routinen schweigt die Regel, sobald eine Unit aus uses oder System
// eine gleichnamige deklariert), Methoden haben eine bekannte Vorfahrenkette, keine
// Deklaration steht in einem bedingten Zweig, nichts ist generisch, varargs
// oder verschachtelt, und der Aufruf steht in keinem with. Ein Argument passt
// sicher nicht nur zwischen eingebauten Typfamilien ohne implizite Umwandlung
// (Gleitkomma an Ganzzahl, string an Char, Boolean an Zahl …); Aliase auf
// eingebaute Typen zählen wie ihr Grundtyp, alles andere (Records mit
// Implicit-Operatoren, Klassen, Zeiger, offene Arrays, untypisierte Parameter,
// Variant als Argument) gilt als möglich. Ein Aufruf ist mehrdeutig, wenn alle
// in Frage kommenden Überladungen derselben Klasse bzw. Unit für die
// übergebenen Argumente genau dieselben Parametertypen haben und sich nur in
// Parametern mit Standardwert unterscheiden; jedes Argument muss dazu sicher
// zum Typ passen (gleicher eingebauter Typ oder gleicher Typname).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Semantics.ExpressionTypes;

const
  ArgumentCountMismatchRuleId = 'argument-count-mismatch';
  OverloadResolutionRuleId = 'overload-resolution';

type
  TArgumentCountMismatchRule = class(TInterfacedObject, IRule)
  public
    /// <summary>Teilt einen Routinenkopf: Text zwischen den Klammern der Parameterliste ('' ohne) und Text
    /// dahinter (Ergebnistyp und Direktiven). False, wenn der Kopf keine Routine beschreibt.</summary>
    class function SplitHeader(const AHeader: string; out AParameters, ATail: string): Boolean; static;
    /// <summary>Text wie „Text fehlt“ bzw. „Betreff und Text fehlen“ für die Namen ANames.</summary>
    class function MissingText(const ANames: TArray<string>): string; static;
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

{$SCOPEDENUMS ON}
  /// <summary>Wie sicher ein Argument zu einem Parameter passt (#1371).</summary>
  TArgumentFit = (Unknown, Fits, Fails);
{$SCOPEDENUMS OFF}

  TOverloadResolutionRule = class(TInterfacedObject, IRule)
  public
    /// <summary>Passt ein Argument der Typfamilie AArgument an einen Wert- oder const-Parameter der Familie
    /// AParameter? Fails nur bei eingebauten Familien ohne implizite Umwandlung, Unknown bei allem, was der
    /// Compiler über Operatoren, Zeiger oder Variant noch annehmen kann.</summary>
    class function Fit(AParameter, AArgument: TExpressionCategory): TArgumentFit; static;
    /// <summary>Gleicher Typ für die Mehrdeutigkeit: gleicher Name, Integer/LongInt/Int32, string/UnicodeString
    /// und Char/WideChar gelten als gleich.</summary>
    class function SameTypeName(const A, B: string): Boolean; static;
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterCallRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.UnresolvedNames,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TCallsText = (Title, IsMissing, AndWord, OneArgument, Arguments, NonePassed, OnePassed, Passed, OpenSignatureHelp,
    ExpectsNone, Expects, ExpectsAtMost, ExpectsMissing, ExpectsAtLeast, OverloadTitle, NoOverloadNoArgs,
    NoOverloadFits, Ambiguous, AreMissing);

const
  cTexts: array[TCallsText] of TAtlasText = (
    (De: 'Falsche Anzahl Argumente beim Aufruf'; En: 'Wrong number of arguments in call'),
    (De: ' fehlt'; En: ' is missing'),
    (De: ' und '; En: ' and '),
    (De: '1 Argument'; En: '1 argument'),
    (De: ' Argumente'; En: ' arguments'),
    (De: 'übergeben ist keins'; En: 'none passed'),
    (De: 'übergeben ist 1'; En: '1 passed'),
    (De: 'übergeben sind '; En: 'passed: '),
    (De: 'Signaturhilfe öffnen'; En: 'Open signature help'),
    (De: '%s erwartet keine Argumente, %s (wie E2034).'; En: '%s expects no arguments, %s (like E2034).'),
    (De: '%s erwartet %s, %s (wie E2034).'; En: '%s expects %s, %s (like E2034).'),
    (De: '%s erwartet höchstens %s, %s (wie E2034).'; En: '%s expects at most %s, %s (like E2034).'),
    (De: '%s erwartet %s, %s; %s (wie E2035).'; En: '%s expects %s, %s; %s (like E2035).'),
    (De: '%s erwartet mindestens %s, %s; %s (wie E2035).'; En: '%s expects at least %s, %s; %s (like E2035).'),
    (De: 'Überladung nicht auflösbar oder mehrdeutig'; En: 'Overload cannot be resolved or is ambiguous'),
    (De: 'Keine der %d Überladungen von %s lässt sich ohne Argumente aufrufen (wie E2250).';
     En: 'None of the %d overloads of %s can be called without arguments (like E2250).'),
    (De: 'Keine der %d Überladungen von %s passt zu den Argumenten (%s) (wie E2250).';
     En: 'None of the %d overloads of %s matches the arguments (%s) (like E2250).'),
    (De: 'Aufruf von %s ist mehrdeutig: %s passen gleich gut (wie E2251).';
     En: 'Call to %s is ambiguous: %s match equally well (like E2251).'),
    (De: ' fehlen'; En: ' are missing'));

{$SCOPEDENUMS OFF}

const
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];

{ TArgumentCountMismatchRule }

function TArgumentCountMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ArgumentCountMismatchRuleId, TRuleSeverity.Error,
    cTexts[TCallsText.Title].Text);
end;

/// <summary>Erste Klammer auf oberster Ebene (außerhalb von Strings und Typargumenten); 0 ohne. Steht ":"
/// oder ";" davor, gibt es keine Parameterliste: dann 0 und AStop dessen Stelle, sonst AStop = 0.</summary>
function HeaderOpenParen(const AHeader: string; out AStop: Integer): Integer;
var
  mIndex, mGeneric: Integer;
  mInString: Boolean;
  mChar: Char;
begin
  Result := 0;
  AStop := 0;
  mGeneric := 0;
  mInString := False;
  mIndex := 1;
  while (Result = 0) and (AStop = 0) and (mIndex <= Length(AHeader)) do
  begin
    mChar := AHeader[mIndex];
    if mChar = '''' then
    begin
      mInString := not mInString;
    end;
    if mInString then
    begin
      // Inhalt eines Strings zählt nicht.
    end
    else if mChar = '<' then
    begin
      Inc(mGeneric);
    end
    else if mChar = '>' then
    begin
      Dec(mGeneric);
    end
    else if (mGeneric = 0) and (mChar = '(') then
    begin
      Result := mIndex;
    end
    else if (mGeneric = 0) and CharInSet(mChar, [':', ';']) then
    begin
      AStop := mIndex;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Schließende Klammer zur Klammer an AOpen (außerhalb von Strings); 0 ohne.</summary>
function HeaderCloseParen(const AHeader: string; AOpen: Integer): Integer;
var
  mIndex, mDepth: Integer;
  mInString: Boolean;
  mChar: Char;
begin
  Result := 0;
  mDepth := 0;
  mInString := False;
  mIndex := AOpen;
  while (Result = 0) and (mIndex <= Length(AHeader)) do
  begin
    mChar := AHeader[mIndex];
    if mChar = '''' then
    begin
      mInString := not mInString;
    end;
    if not mInString and CharInSet(mChar, ['(', '[']) then
    begin
      Inc(mDepth);
    end
    else if not mInString and CharInSet(mChar, [')', ']']) then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Result := mIndex;
      end;
    end;
    Inc(mIndex);
  end;
end;

class function TArgumentCountMismatchRule.SplitHeader(const AHeader: string; out AParameters,
  ATail: string): Boolean;
var
  mOpen, mClose, mStop: Integer;
begin
  AParameters := '';
  ATail := '';
  // Bis zur ersten Klammer auf oberster Ebene; ":" oder ";" davor heißt: keine Parameterliste.
  mOpen := HeaderOpenParen(AHeader, mStop);
  if mOpen = 0 then
  begin
    if mStop > 0 then
    begin
      ATail := Copy(AHeader, mStop, MaxInt);
    end;
    Exit(True);
  end;
  mClose := HeaderCloseParen(AHeader, mOpen);
  Result := mClose > 0;
  if Result then
  begin
    AParameters := Copy(AHeader, mOpen + 1, mClose - mOpen - 1);
    ATail := Copy(AHeader, mClose + 1, MaxInt);
  end;
end;

class function TArgumentCountMismatchRule.MissingText(const ANames: TArray<string>): string;
var
  Index: Integer;
begin
  Result := '';
  if Length(ANames) = 0 then
  begin
    Exit;
  end;
  if Length(ANames) = 1 then
  begin
    Exit(ANames[0] + cTexts[TCallsText.IsMissing].Text);
  end;
  for Index := 0 to High(ANames) - 1 do
  begin
    if Index > 0 then
    begin
      Result := Result + ', ';
    end;
    Result := Result + ANames[Index];
  end;
  Result := Result + cTexts[TCallsText.AndWord].Text + ANames[High(ANames)] + cTexts[TCallsText.AreMissing].Text;
end;

function ArgumentsText(ACount: Integer): string;
begin
  if ACount = 1 then
  begin
    Result := cTexts[TCallsText.OneArgument].Text;
  end
  else
  begin
    Result := IntToStr(ACount) + cTexts[TCallsText.Arguments].Text;
  end;
end;

function PassedText(ACount: Integer): string;
begin
  if ACount = 0 then
  begin
    Result := cTexts[TCallsText.NonePassed].Text;
  end
  else if ACount = 1 then
  begin
    Result := cTexts[TCallsText.OnePassed].Text;
  end
  else
  begin
    Result := cTexts[TCallsText.Passed].Text + IntToStr(ACount);
  end;
end;

function HasWord(const AText, AWord: string): Boolean;
var
  Word: string;
begin
  Result := False;
  for Word in AText.Replace(';', ' ').Replace(',', ' ').Split([' ', #9, #10, #13],
    TStringSplitOptions.ExcludeEmpty) do
  begin
    if SameText(Word, AWord) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Letztes Token, das an oder vor APosition beginnt; -1 ohne.</summary>
function TokenAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  Low, High, Middle: Integer;
begin
  Result := -1;
  Low := 0;
  High := Length(ATokens) - 1;
  while Low <= High do
  begin
    Middle := (Low + High) div 2;
    if (ATokens[Middle].StartPos.Line < APosition.Line) or ((ATokens[Middle].StartPos.Line = APosition.Line) and
      (ATokens[Middle].StartPos.Character <= APosition.Character)) then
    begin
      Result := Middle;
      Low := Middle + 1;
    end
    else
    begin
      High := Middle - 1;
    end;
  end;
end;

/// <summary>Signaturhilfe in den Klammern vor ")"; ohne Klammern erst () hinter den Namen.</summary>
function SignatureFix(ANode, ACallee: TSyntaxNode): TRuleFix;
var
  Target: TTextPosition;
begin
  if ANode = ACallee then
  begin
    Target := TTextPosition.Create(ACallee.EndPos.Line, ACallee.EndPos.Character + 1);
    Result := TRuleFix.SignatureHelp(cTexts[TCallsText.OpenSignatureHelp].Text, Target);
    Result.Edits := [TTextEdit.Create(TTextRange.Create(ACallee.EndPos, ACallee.EndPos), '()')];
  end
  else
  begin
    Result := TRuleFix.SignatureHelp(cTexts[TCallsText.OpenSignatureHelp].Text, TTextPosition.Create(ANode.EndPos.Line,
      ANode.EndPos.Character - 1));
  end;
end;

/// <summary>Argumente des Aufrufs ACall ohne Typargumente.</summary>
function CallArguments(ACall: TSyntaxNode): TArray<TSyntaxNode>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 1 to ACall.ChildCount - 1 do
  begin
    if ACall[Index].Kind <> TSyntaxKind.GenericArgs then
    begin
      Result := Result + [ACall[Index]];
    end;
  end;
end;

procedure TArgumentCountMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName: string;
  Paths: TArray<string>;

  function PathOf(const APosition: TTextPosition): string;
  begin
    Result := '';
    if Paths <> nil then
    begin
      Result := TConditionalBranches.PathAt(Paths, TokenAt(AContext.Tree.Tokens, APosition));
    end;
  end;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  /// <summary>Text des Kopfs der Routine ADecl (ohne Kopfknoten die ganze Deklaration).</summary>
  function RoutineHeaderText(ADecl: TSyntaxNode): string;
  var
    Header: TSyntaxNode;
  begin
    Header := ADecl.FindChild(TSyntaxKind.RoutineHeader);
    if Header = nil then
    begin
      Header := ADecl;
    end;
    Result := NodeText(Header);
  end;

  /// <summary>Kopf einer Routine dieser Datei, die der Resolver ohne Index-Eintrag liefert (verschachtelte
  /// Routinen): der Knoten, der an ARange beginnt. Iterativ (Bericht M1).</summary>
  function LocalHeader(ARoot: TSyntaxNode; const ARange: TTextRange): string;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Result := '';
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while (Result = '') and (Pending.Count > 0) do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.RoutineDecl) and (Node.StartPos.Line = ARange.StartPos.Line) and
          (Node.StartPos.Character = ARange.StartPos.Character) then
        begin
          Result := RoutineHeaderText(Node);
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          if (Node[Index].StartPos.Line <= ARange.StartPos.Line) and
            (Node[Index].EndPos.Line >= ARange.StartPos.Line) then
          begin
            Pending.Push(Node[Index]);
          end;
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function HeaderOf(const ASymbol: TResolvedSymbol): string;
  begin
    Result := ASymbol.Signature;
    if (Result = '') and (ASymbol.Kind = TResolvedKind.Local) then
    begin
      Result := LocalHeader(AContext.Tree.Root, ASymbol.Range);
    end;
  end;

  /// <summary>Kopf des Kandidaten, wenn er eine Routine mit Quelltext ohne overload und varargs ist, die mit
  /// dem Aufruf am Pfad ACallPath übersetzt wird; '' sonst.</summary>
  function CandidateHeader(const ACandidate: TResolvedSymbol; const ACallPath: string): string;
  var
    Parameters, Tail: string;
  begin
    Result := '';
    if ACandidate.IsType or ACandidate.Builtin or not (ACandidate.SymbolKind in RoutineKinds) or
      (ACandidate.Condition <> '') or (Length(ACandidate.Overloads) > 0) then
    begin
      Exit;
    end;
    // Deklaration dieser Datei in einem Zweig, der ohne den Aufruf wegfallen kann.
    if ((ACandidate.Kind = TResolvedKind.Local) or SameText(ACandidate.FileName, FileName)) and
      not TConditionalBranches.Implies(ACallPath, PathOf(ACandidate.SelectionRange.StartPos)) then
    begin
      Exit;
    end;
    Result := HeaderOf(ACandidate);
    if (Result <> '') and (not SplitHeader(Result, Parameters, Tail) or HasWord(Tail, 'overload') or
      HasWord(Tail, 'varargs')) then
    begin
      Result := '';
    end;
  end;

  /// <summary>Index des maßgeblichen Kopfs: Ein Rumpf ohne Parameterliste (procedure TKunde.Senden;) gehört zur
  /// Deklaration mit Liste. -1, wenn mehrere Köpfe eine Liste haben (Überladung ohne overload oder Verdeckung;
  /// das klärt der Compiler).</summary>
  function ChosenHeader(const AHeaders: TArray<string>): Integer;
  var
    Index, WithList: Integer;
  begin
    Result := 0;
    WithList := 0;
    for Index := High(AHeaders) downto 0 do
    begin
      if Pos('(', AHeaders[Index]) > 0 then
      begin
        Inc(WithList);
        Result := Index;
      end;
    end;
    if (WithList > 1) and (Length(AHeaders) > 1) then
    begin
      Result := -1;
    end;
  end;

  /// <summary>Die eine Routine hinter ACallee samt Kopf; False bei Überladungen, varargs und allem, was
  /// keine Routine mit Quelltext ist.</summary>
  function SingleRoutine(ACallee: TSyntaxNode; out ARoutine: TResolvedSymbol; out AParameters: string): Boolean;
  var
    Candidates: TArray<TResolvedSymbol>;
    Headers: TArray<string>;
    Header, Tail, CallPath: string;
    Index: Integer;
  begin
    Result := False;
    ARoutine := Default(TResolvedSymbol);
    AParameters := '';
    CallPath := PathOf(ACallee.StartPos);
    Candidates := Resolver.CallCandidates(AContext.Tree, FileName, ACallee);
    if (Length(Candidates) = 0) or Resolver.MayBeHiddenMember(AContext.Tree, FileName, ACallee, Candidates[0]) then
    begin
      Exit;
    end;
    Headers := nil;
    for Index := 0 to High(Candidates) do
    begin
      Header := CandidateHeader(Candidates[Index], CallPath);
      if Header = '' then
      begin
        Exit;
      end;
      Headers := Headers + [Header];
    end;
    Index := ChosenHeader(Headers);
    Result := Index >= 0;
    if Result then
    begin
      ARoutine := Candidates[Index];
      SplitHeader(Headers[Index], AParameters, Tail);
    end;
  end;

  function ResultTypeKnown(ACall: TSyntaxNode): Boolean;
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    Result := Resolver.NodeType(AContext.Tree, FileName, ACall, Symbol, TypeInfo, TypeFound) and TypeFound and
      (TypeInfo.Builtin or (TypeInfo.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
      TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType]));
  end;

  /// <summary>Meldung bei zu vielen Argumenten (E2034).</summary>
  function TooManyMessage(const ARoutine: TResolvedSymbol; ACount: Integer): string;
  begin
    if ARoutine.MaxArgs = 0 then
    begin
      Result := cTexts[TCallsText.ExpectsNone].Fmt([ARoutine.Name, PassedText(ACount)]);
    end
    else if ARoutine.MinArgs = ARoutine.MaxArgs then
    begin
      Result := cTexts[TCallsText.Expects].Fmt([ARoutine.Name, ArgumentsText(ARoutine.MaxArgs),
        PassedText(ACount)]);
    end
    else
    begin
      Result := cTexts[TCallsText.ExpectsAtMost].Fmt([ARoutine.Name,
        ArgumentsText(ARoutine.MaxArgs), PassedText(ACount)]);
    end;
  end;

  /// <summary>Meldung bei zu wenigen Argumenten (E2035) mit den Namen der fehlenden.</summary>
  function TooFewMessage(const ARoutine: TResolvedSymbol; ACount: Integer;
    const AParameters: TArray<TSignatureParameter>): string;
  var
    Missing: TArray<string>;
    Index: Integer;
  begin
    Missing := nil;
    for Index := ACount to ARoutine.MinArgs - 1 do
    begin
      Missing := Missing + [AParameters[Index].Name];
    end;
    if ARoutine.MinArgs = ARoutine.MaxArgs then
    begin
      Result := cTexts[TCallsText.ExpectsMissing].Fmt([ARoutine.Name, ArgumentsText(ARoutine.MinArgs),
        PassedText(ACount), MissingText(Missing)]);
    end
    else
    begin
      Result := cTexts[TCallsText.ExpectsAtLeast].Fmt([ARoutine.Name,
        ArgumentsText(ARoutine.MinArgs), PassedText(ACount), MissingText(Missing)]);
    end;
  end;

  procedure CheckCall(ANode, ACallee: TSyntaxNode; const AArguments: TArray<TSyntaxNode>);
  var
    Routine: TResolvedSymbol;
    ParameterText, Message: string;
    Parameters: TArray<TSignatureParameter>;
    Count: Integer;
    Range: TTextRange;
  begin
    if not (ACallee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      not SingleRoutine(ACallee, Routine, ParameterText) then
    begin
      Exit;
    end;
    Count := Length(AArguments);
    if (Count >= Routine.MinArgs) and (Count <= Routine.MaxArgs) then
    begin
      Exit;
    end;
    Parameters := TChangeSignature.ParseParameters(ParameterText);
    // Der Kopf muss zu den Zahlen des Index passen, sonst stimmt die Zuordnung der Namen nicht.
    if Length(Parameters) <> Routine.MaxArgs then
    begin
      Exit;
    end;
    if Count > Routine.MaxArgs then
    begin
      if (Routine.TypeName <> '') and not ResultTypeKnown(ANode) then
      begin
        Exit;
      end;
      Message := TooManyMessage(Routine, Count);
      Range := TTextRange.Create(AArguments[Routine.MaxArgs].StartPos, AArguments[High(AArguments)].EndPos);
    end
    else
    begin
      Message := TooFewMessage(Routine, Count, Parameters);
      Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
    end;
    AReport.Add(Range, Message, TRuleConfidence.High, [SignatureFix(ANode, ACallee)]);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) and
          (NodeText(Node).TrimRight.EndsWith(')')) then
        begin
          CheckCall(Node, Node[0], CallArguments(Node));
        end
        // Versenden; als Anweisung ohne Klammern.
        else if (Node.Kind = TSyntaxKind.CallStatement) and (Node.ChildCount = 1) and
          (Node[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
        begin
          CheckCall(Node[0], Node[0], nil);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FileName := AContext.FileName;
  if FileName = '' then
  begin
    FileName := AContext.RelativePath;
  end;
  if FileName = '' then
  begin
    FileName := AContext.UnitName + '.pas';
  end;
  Paths := TConditionalBranches.Paths(AContext.Tree.Tokens);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Resolver.PinTree(AContext.Tree, FileName);
  try
    Visit(AContext.Tree.Root);
  finally
    Resolver.UnpinTree;
  end;
end;

{ TOverloadResolutionRule }

type
  /// <summary>Eine Überladung samt Parametern aus dem Kopf (#1371).</summary>
  TOverloadCandidate = record
    Symbol: TResolvedSymbol;
    Parameters: TArray<TSignatureParameter>;
    /// <summary>Parameterliste wie im Kopf, für die Meldung.</summary>
    ParameterText: string;
  end;

function TOverloadResolutionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OverloadResolutionRuleId, TRuleSeverity.Error,
    cTexts[TCallsText.OverloadTitle].Text);
end;

class function TOverloadResolutionRule.Fit(AParameter, AArgument: TExpressionCategory): TArgumentFit;
const
  cNumbers = [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_];
  cFloats = [TExpressionCategory.Float, TExpressionCategory.Currency_];
  cDecided = [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_,
    TExpressionCategory.Boolean_, TExpressionCategory.Char_, TExpressionCategory.String_];
var
  mFits: Boolean;
begin
  if AParameter = TExpressionCategory.Variant_ then
  begin
    Exit(TArgumentFit.Fits);
  end;
  // Zeiger (PChar nimmt String-Literale), Mengen, Klassen, Records mit Operatoren, Variant als Argument …
  if not (AParameter in cDecided) or not (AArgument in cDecided) then
  begin
    Exit(TArgumentFit.Unknown);
  end;
  case AArgument of
    TExpressionCategory.Integer_:
      mFits := AParameter in cNumbers;
    TExpressionCategory.Float, TExpressionCategory.Currency_:
      mFits := AParameter in cFloats;
    TExpressionCategory.Char_:
      mFits := AParameter in [TExpressionCategory.Char_, TExpressionCategory.String_];
  else
    mFits := AParameter = AArgument;
  end;
  if mFits then
  begin
    Result := TArgumentFit.Fits;
  end
  else
  begin
    Result := TArgumentFit.Fails;
  end;
end;

class function TOverloadResolutionRule.SameTypeName(const A, B: string): Boolean;

  function Normal(const AName: string): string;
  begin
    Result := AName;
    if StartsText('System.', Result) then
    begin
      Result := Copy(Result, 8, MaxInt);
    end;
    if MatchText(Result, ['LongInt', 'Int32', 'FixedInt']) then
    begin
      Result := 'Integer';
    end
    else if SameText(Result, 'UnicodeString') then
    begin
      Result := 'string';
    end
    else if SameText(Result, 'WideChar') then
    begin
      Result := 'Char';
    end;
  end;

begin
  Result := (A <> '') and SameText(Normal(A), Normal(B));
end;

procedure TOverloadResolutionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mTypes: TExpressionTypes;
  mFileName: string;
  mPaths: TArray<string>;
  mUsedUnits: TArray<string>;
  mOtherRoutines: TDictionary<string, Boolean>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function PathOf(const APosition: TTextPosition): string;
  begin
    Result := '';
    if mPaths <> nil then
    begin
      Result := TConditionalBranches.PathAt(mPaths, TokenAt(AContext.Tree.Tokens, APosition));
    end;
  end;

  /// <summary>Steht AUnitName in uses (auch ohne Namespace-Präfix) oder ist es System?</summary>
  function InScope(const AUnitName: string): Boolean;
  var
    mUsed: string;
  begin
    Result := SameText(AUnitName, 'System') or SameText(AUnitName, 'SysInit');
    for mUsed in mUsedUnits do
    begin
      if SameText(AUnitName, mUsed) or EndsText('.' + mUsed, AUnitName) then
      begin
        Exit(True);
      end;
    end;
  end;

  /// <summary>Deklariert eine Unit aus uses oder System eine freie Routine AName? dcc nimmt deren Überladungen
  /// mit in die Auswahl.</summary>
  function RoutineElsewhere(const AName: string): Boolean;
  var
    mLocation: TSymbolLocation;
    mKey: string;
  begin
    mKey := UpperCase(AName);
    if mOtherRoutines.TryGetValue(mKey, Result) then
    begin
      Exit;
    end;
    Result := False;
    for mLocation in AContext.Index.FindSymbols(AName) do
    begin
      if (mLocation.Symbol.Kind in RoutineKinds) and (mLocation.Symbol.Container = '') and
        not SameText(mLocation.UnitName, AContext.UnitName) and not SameText(mLocation.FileName, mFileName) and
        InScope(mLocation.UnitName) then
      begin
        Result := True;
        Break;
      end;
    end;
    mOtherRoutines.Add(mKey, Result);
  end;

  /// <summary>Deklarieren mehrere eingebundene Units eine freie Routine AName (GetEnvironmentVariable in
  /// Winapi.Windows und System.SysUtils)? Welche gilt, entscheiden uses-Reihenfolge und Argumente.</summary>
  function RoutineInSeveralUnits(const AName: string): Boolean;
  var
    mLocation: TSymbolLocation;
    mFirst: string;
  begin
    Result := False;
    mFirst := '';
    for mLocation in AContext.Index.FindSymbols(AName) do
    begin
      if (mLocation.Symbol.Kind in RoutineKinds) and (mLocation.Symbol.Container = '') and
        (SameText(mLocation.UnitName, AContext.UnitName) or InScope(mLocation.UnitName)) then
      begin
        if mFirst = '' then
        begin
          mFirst := mLocation.UnitName;
        end
        else if not SameText(mFirst, mLocation.UnitName) then
        begin
          Exit(True);
        end;
      end;
    end;
  end;

  /// <summary>Kennt der Index die ganze Vorfahrenkette des Typs, zu dem die Methode ACandidate gehört?</summary>
  function AncestorsKnown(const ACandidate: TResolvedSymbol): Boolean;
  var
    mUnit: TUnitIndex;
    mType: TResolvedSymbol;
  begin
    Result := False;
    if not mResolver.DeclaringUnit(ACandidate, mUnit) or
      not mResolver.ResolveTypeFrom(mUnit, ACandidate.Container, mType) then
    begin
      Exit;
    end;
    mResolver.Queries.AncestorNames(mType, Result);
  end;

  /// <summary>Rumpf einer Methode bzw. Routine, deren Deklaration mit overload schon in ASymbols steht
  /// (gleicher Typ, gleiche Parametertypen); der Rumpf wiederholt Standardwerte und Direktiven nicht.</summary>
  function IsBody(const ASymbol: TResolvedSymbol; const ASymbols: TArray<TResolvedSymbol>): Boolean;
  var
    mOther: TResolvedSymbol;
    mIndex: Integer;
    mSame: Boolean;
  begin
    Result := False;
    if HasWord(ASymbol.Signature, 'overload') then
    begin
      Exit;
    end;
    for mOther in ASymbols do
    begin
      if HasWord(mOther.Signature, 'overload') and SameText(mOther.Container, ASymbol.Container) and
        (Length(mOther.ParamTypes) = Length(ASymbol.ParamTypes)) then
      begin
        mSame := True;
        for mIndex := 0 to High(mOther.ParamTypes) do
        begin
          mSame := mSame and SameText(mOther.ParamTypes[mIndex], ASymbol.ParamTypes[mIndex]);
        end;
        if mSame then
        begin
          Exit(True);
        end;
      end;
    end;
  end;

  /// <summary>Überladungen ohne die Rümpfe, deren Deklaration schon in AFound steht.</summary>
  function WithoutBodies(const AFound: TArray<TResolvedSymbol>): TArray<TResolvedSymbol>;
  var
    mSymbol: TResolvedSymbol;
  begin
    Result := nil;
    for mSymbol in AFound do
    begin
      if not IsBody(mSymbol, AFound) then
      begin
        Result := Result + [mSymbol];
      end;
    end;
  end;

  /// <summary>Ist ASymbol eine gewöhnliche Routine mit Quelltext (kein Typ, nichts Eingebautes, nicht lokal,
  /// unbedingt, nicht generisch)?</summary>
  function PlainRoutine(const ASymbol: TResolvedSymbol): Boolean;
  begin
    Result := not ASymbol.IsType and not ASymbol.Builtin and (ASymbol.SymbolKind in RoutineKinds) and
      (ASymbol.Kind <> TResolvedKind.Local) and (ASymbol.Condition = '');
    Result := Result and (ASymbol.TypeParams = '') and (Length(ASymbol.Bindings) = 0) and
      (Pos('<', ASymbol.Container) = 0);
  end;

  /// <summary>Taugt ASymbol als Überladung im Sinne von dcc, die mit dem Aufruf am Pfad ACallPath übersetzt
  /// wird und deren Geschwister alle bekannt sind?</summary>
  function UsableOverload(const ASymbol: TResolvedSymbol; const ACallPath: string): Boolean;
  begin
    Result := PlainRoutine(ASymbol) and HasWord(ASymbol.Signature, 'overload') and
      not HasWord(ASymbol.Signature, 'varargs');
    Result := Result and (not SameText(ASymbol.FileName, mFileName) or
      TConditionalBranches.Implies(ACallPath, PathOf(ASymbol.SelectionRange.StartPos)));
    if Result and (ASymbol.Container = '') then
    begin
      Result := not RoutineElsewhere(ASymbol.Name);
    end
    else if Result then
    begin
      Result := AncestorsKnown(ASymbol);
    end;
  end;

  /// <summary>Kandidat mit Parametern aus dem Kopf; False, wenn der Kopf nicht zu den Zahlen des Index passt.
  /// </summary>
  function MakeCandidate(const ASymbol: TResolvedSymbol; out ACandidate: TOverloadCandidate): Boolean;
  var
    mTail: string;
  begin
    ACandidate := Default(TOverloadCandidate);
    ACandidate.Symbol := ASymbol;
    Result := TArgumentCountMismatchRule.SplitHeader(ASymbol.Signature, ACandidate.ParameterText, mTail);
    if Result then
    begin
      ACandidate.Parameters := TChangeSignature.ParseParameters(ACandidate.ParameterText);
      Result := Length(ACandidate.Parameters) = ASymbol.MaxArgs;
    end;
  end;

  /// <summary>Alle Überladungen hinter ACallee mit ihren Parametern; False, wenn die Liste nicht sicher
  /// vollständig ist oder es keine Überladung im Sinne von dcc ist.</summary>
  function Candidates(ACallee: TSyntaxNode; out AResult: TArray<TOverloadCandidate>): Boolean;
  var
    mSymbols: TArray<TResolvedSymbol>;
    mSymbol: TResolvedSymbol;
    mCandidate: TOverloadCandidate;
    mCallPath: string;
  begin
    Result := False;
    AResult := nil;
    mSymbols := WithoutBodies(mResolver.CallCandidates(AContext.Tree, mFileName, ACallee));
    if (Length(mSymbols) < 2) or TUnresolvedNames.IsIntrinsic(ACallee.Name) or
      mResolver.MayBeHiddenMember(AContext.Tree, mFileName, ACallee, mSymbols[0]) then
    begin
      Exit;
    end;
    mCallPath := PathOf(ACallee.StartPos);
    for mSymbol in mSymbols do
    begin
      if not UsableOverload(mSymbol, mCallPath) or not MakeCandidate(mSymbol, mCandidate) then
      begin
        Exit;
      end;
      AResult := AResult + [mCandidate];
    end;
    // Ein unbekannter Vorfahr der umgebenden Klasse kann weitere Überladungen erben (nach CallCandidates gültig).
    Result := not mResolver.HasUnknownAncestor;
  end;

  /// <summary>Macht ANode im Argument dessen Typ unsicher? Anonyme Methoden, überladene Aufrufe (ihr Typ hängt
  /// selbst von der Auswahl ab) und freie Routinen aus mehreren Units (welche gilt, entscheidet dcc nach
  /// uses-Reihenfolge und Argumenten).</summary>
  function UncertainNode(ANode: TSyntaxNode): Boolean;
  begin
    Result := ANode.Kind = TSyntaxKind.AnonymousMethod;
    if not Result and (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) then
    begin
      Result := (Length(mResolver.CallCandidates(AContext.Tree, mFileName, ANode[0])) <> 1) or
        (ANode[0].Kind = TSyntaxKind.Identifier) and RoutineInSeveralUnits(ANode[0].Name);
    end;
  end;

  /// <summary>Enthält AArgument einen Knoten, der seinen Typ unsicher macht?</summary>
  function HasUncertainNode(AArgument: TSyntaxNode): Boolean;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AArgument);
      while not Result and (mPending.Count > 0) do
      begin
        mNode := mPending.Pop;
        Result := UncertainNode(mNode);
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  /// <summary>Ist AArgument eine Konstante? Konstanten bekommen ihren Typ erst am Aufruf (const X = 'a' ist ein
  /// Char, Separator = '›' kein Integer).</summary>
  function IsConstant(AArgument: TSyntaxNode): Boolean;
  var
    mSymbol, mType: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    Result := (AArgument.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
      mResolver.NodeType(AContext.Tree, mFileName, AArgument, mSymbol, mType, mTypeFound) and
      (mSymbol.SymbolKind = TIndexSymbolKind.Constant);
  end;

  /// <summary>Typ eines Arguments; '' wenn er nicht sicher ist (überladene Aufrufe darin, untypisierte
  /// Konstanten, die als Char zählen könnten).</summary>
  function ArgumentType(AArgument: TSyntaxNode; out ACategory: TExpressionCategory): string;
  var
    mWidth: Integer;
    mSigned: Boolean;
    mInfo: TExpressionTypeInfo;
  begin
    Result := '';
    ACategory := TExpressionCategory.Unknown;
    if HasUncertainNode(AArgument) then
    begin
      Exit;
    end;
    mInfo := mTypes.Describe(AArgument);
    if not mInfo.Found or IsConstant(AArgument) then
    begin
      Exit;
    end;
    Result := mInfo.TypeName;
    if mInfo.BaseName <> '' then
    begin
      Result := mInfo.BaseName;
    end;
    ACategory := TExpressionTypes.CategoryOf(Result, mWidth, mSigned);
  end;

  /// <summary>Eingebauter Grundtyp des Alias ATypeText (TFileName = string) aus Sicht der Unit von ACandidate.
  /// </summary>
  function BuiltinAliasTarget(const ACandidate: TOverloadCandidate; const ATypeText: string;
    out ATarget: TResolvedSymbol): Boolean;
  var
    mUnit: TUnitIndex;
    mResolved: TResolvedSymbol;
  begin
    Result := mResolver.DeclaringUnit(ACandidate.Symbol, mUnit) and
      mResolver.ResolveTypeTextFrom(mUnit, ATypeText, mResolved) and not mResolved.Builtin;
    Result := Result and (mResolved.SymbolKind = TIndexSymbolKind.TypeAlias) and
      mResolver.TypeOf(mResolved, ATarget) and ATarget.Builtin;
  end;

  /// <summary>Typfamilie eines Parametertyps; Aliase auf eingebaute Typen (TFileName = string) zählen wie
  /// ihr Grundtyp.</summary>
  function ParameterCategory(const ACandidate: TOverloadCandidate; const AParameter: TSignatureParameter):
    TExpressionCategory;
  var
    mText: string;
    mWidth: Integer;
    mSigned: Boolean;
    mFollowed: TResolvedSymbol;
  begin
    Result := TExpressionCategory.Unknown;
    mText := Trim(AParameter.TypeName);
    if (mText = '') or StartsText('array', mText) or (Pos('<', mText) > 0) then
    begin
      Exit;
    end;
    Result := TExpressionTypes.CategoryOf(mText, mWidth, mSigned);
    if Result <> TExpressionCategory.Other then
    begin
      Exit;
    end;
    Result := TExpressionCategory.Unknown;
    if BuiltinAliasTarget(ACandidate, mText, mFollowed) then
    begin
      Result := TExpressionTypes.CategoryOf(mFollowed.Name, mWidth, mSigned);
    end;
    if Result = TExpressionCategory.Other then
    begin
      Result := TExpressionCategory.Unknown;
    end;
  end;

  function Fails(const ACandidate: TOverloadCandidate; const ATypes: TArray<string>;
    const ACategories: TArray<TExpressionCategory>): Boolean;
  var
    mIndex: Integer;
  begin
    if (Length(ATypes) < ACandidate.Symbol.MinArgs) or (Length(ATypes) > ACandidate.Symbol.MaxArgs) then
    begin
      Exit(True);
    end;
    Result := False;
    for mIndex := 0 to High(ATypes) do
    begin
      if Fit(ParameterCategory(ACandidate, ACandidate.Parameters[mIndex]), ACategories[mIndex]) =
        TArgumentFit.Fails then
      begin
        Exit(True);
      end;
    end;
  end;

  /// <summary>Passt jedes Argument sicher (gleicher Typ wie der Parameter)?</summary>
  function SurelyFits(const ACandidate: TOverloadCandidate; const ATypes: TArray<string>): Boolean;
  var
    mIndex: Integer;
  begin
    Result := True;
    for mIndex := 0 to High(ATypes) do
    begin
      if not SameTypeName(ATypes[mIndex], ACandidate.Parameters[mIndex].TypeName) then
      begin
        Exit(False);
      end;
    end;
  end;

  /// <summary>Gleiche Parametertypen und -arten für die ersten ACount Parameter.</summary>
  function SamePrefix(const A, B: TOverloadCandidate; ACount: Integer): Boolean;
  var
    mIndex: Integer;
  begin
    Result := True;
    for mIndex := 0 to ACount - 1 do
    begin
      if not SameTypeName(A.Parameters[mIndex].TypeName, B.Parameters[mIndex].TypeName) or
        ((Pos('var', LowerCase(A.Parameters[mIndex].Modifier)) > 0) <>
        (Pos('var', LowerCase(B.Parameters[mIndex].Modifier)) > 0)) or
        ((Pos('out', LowerCase(A.Parameters[mIndex].Modifier)) > 0) <>
        (Pos('out', LowerCase(B.Parameters[mIndex].Modifier)) > 0)) then
      begin
        Exit(False);
      end;
    end;
  end;

  /// <summary>Vor dem Aufruf deklariert (interface oder weiter oben in dieser Datei)?</summary>
  function DeclaredBefore(const ACandidate: TOverloadCandidate; ACall: TSyntaxNode): Boolean;
  var
    mStart: TTextPosition;
  begin
    if not SameText(ACandidate.Symbol.FileName, mFileName) or ACandidate.Symbol.InInterface then
    begin
      Exit(True);
    end;
    mStart := ACandidate.Symbol.SelectionRange.StartPos;
    Result := (mStart.Line < ACall.StartPos.Line) or ((mStart.Line = ACall.StartPos.Line) and
      (mStart.Character < ACall.StartPos.Character));
  end;

  function TypesText(const ATypes: TArray<string>): string;
  var
    mIndex: Integer;
  begin
    Result := '';
    for mIndex := 0 to High(ATypes) do
    begin
      if mIndex > 0 then
      begin
        Result := Result + ', ';
      end;
      if ATypes[mIndex] = '' then
      begin
        Result := Result + '?';
      end
      else
      begin
        Result := Result + ATypes[mIndex];
      end;
    end;
  end;

  function ListText(const ACandidates: TArray<TOverloadCandidate>): string;
  var
    mIndex: Integer;
  begin
    Result := '';
    for mIndex := 0 to High(ACandidates) do
    begin
      if mIndex = High(ACandidates) then
      begin
        Result := Result + cTexts[TCallsText.AndWord].Text;
      end
      else if mIndex > 0 then
      begin
        Result := Result + ', ';
      end;
      Result := Result + '(' + ACandidates[mIndex].ParameterText + ')';
    end;
  end;

  function InWith(ANode: TSyntaxNode): Boolean;
  var
    mNode: TSyntaxNode;
  begin
    Result := False;
    mNode := ANode.Parent;
    while mNode <> nil do
    begin
      if mNode.Kind = TSyntaxKind.WithStatement then
      begin
        Exit(True);
      end;
      mNode := mNode.Parent;
    end;
  end;

  /// <summary>Unterscheidet nichts ACandidate von AFirst: gleiche Typen für die ersten ACount Argumente,
  /// dieselbe Klasse bzw. Unit und Tiefe?</summary>
  function Indistinguishable(const AFirst, ACandidate: TOverloadCandidate; ACount: Integer): Boolean;
  begin
    Result := SamePrefix(AFirst, ACandidate, ACount) and
      SameText(ACandidate.Symbol.Container, AFirst.Symbol.Container) and
      SameText(ACandidate.Symbol.FileName, AFirst.Symbol.FileName) and
      (ACandidate.Symbol.Depth = AFirst.Symbol.Depth);
  end;

  /// <summary>Mehrdeutig nur, wenn nichts die Kandidaten unterscheidet: gleiche Typen für alle übergebenen
  /// Argumente, dieselbe Klasse bzw. Unit, vor dem Aufruf deklariert, jedes Argument sicher passend.</summary>
  function Ambiguous(const AApplicable: TArray<TOverloadCandidate>; ACall: TSyntaxNode;
    const ATypes: TArray<string>): Boolean;
  var
    mCandidate: TOverloadCandidate;
  begin
    Result := Length(AApplicable) >= 2;
    for mCandidate in AApplicable do
    begin
      Result := Result and Indistinguishable(AApplicable[0], mCandidate, Length(ATypes)) and
        DeclaredBefore(mCandidate, ACall) and SurelyFits(mCandidate, ATypes);
    end;
  end;

  /// <summary>Kandidaten, zu denen die Argumente nicht sicher unpassend sind.</summary>
  function Applicable(const ACandidates: TArray<TOverloadCandidate>; const ATypes: TArray<string>;
    const ACategories: TArray<TExpressionCategory>): TArray<TOverloadCandidate>;
  var
    mCandidate: TOverloadCandidate;
  begin
    Result := nil;
    for mCandidate in ACandidates do
    begin
      if not Fails(mCandidate, ATypes, ACategories) then
      begin
        Result := Result + [mCandidate];
      end;
    end;
  end;

  /// <summary>Meldung, wenn keine Überladung passt (E2250).</summary>
  function NoneFitsMessage(ACallee: TSyntaxNode; ACount: Integer; const ATypes: TArray<string>): string;
  begin
    if Length(ATypes) = 0 then
    begin
      Result := cTexts[TCallsText.NoOverloadNoArgs].Fmt([ACount, ACallee.Name]);
    end
    else
    begin
      Result := cTexts[TCallsText.NoOverloadFits].Fmt([ACount, ACallee.Name, TypesText(ATypes)]);
    end;
  end;

  procedure CheckCall(ANode, ACallee: TSyntaxNode; const AArguments: TArray<TSyntaxNode>);
  var
    mCandidates, mApplicable: TArray<TOverloadCandidate>;
    mTypes: TArray<string>;
    mCategories: TArray<TExpressionCategory>;
    mIndex: Integer;
    mMessage: string;
  begin
    if not (ACallee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      (ACallee.FindChild(TSyntaxKind.GenericArgs) <> nil) or InWith(ANode) or
      not Candidates(ACallee, mCandidates) then
    begin
      Exit;
    end;
    SetLength(mTypes, Length(AArguments));
    SetLength(mCategories, Length(AArguments));
    for mIndex := 0 to High(AArguments) do
    begin
      mTypes[mIndex] := ArgumentType(AArguments[mIndex], mCategories[mIndex]);
    end;
    mApplicable := Applicable(mCandidates, mTypes, mCategories);
    if Length(mApplicable) = 0 then
    begin
      mMessage := NoneFitsMessage(ACallee, Length(mCandidates), mTypes);
    end
    else if Ambiguous(mApplicable, ANode, mTypes) then
    begin
      mMessage := cTexts[TCallsText.Ambiguous].Fmt([ACallee.Name, ListText(mApplicable)]);
    end
    else
    begin
      Exit;
    end;
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), mMessage, TRuleConfidence.High,
      [SignatureFix(ANode, ACallee)]);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount > 0) and
          (NodeText(mNode).TrimRight.EndsWith(')')) then
        begin
          CheckCall(mNode, mNode[0], CallArguments(mNode));
        end
        // Nimm; als Anweisung ohne Klammern.
        else if (mNode.Kind = TSyntaxKind.CallStatement) and (mNode.ChildCount = 1) and
          (mNode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
        begin
          CheckCall(mNode[0], mNode[0], nil);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

var
  mOptions: TExpressionTypeOptions;
begin
  // Ohne System und alle Units in uses im Index ist die Liste der Überladungen nicht sicher vollständig.
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not TUnresolvedNames.Available(AContext.Index) then
  begin
    Exit;
  end;
  mUsedUnits := TUsesClauses.UsedUnits(AContext.Tree.Tokens);
  if not TUnresolvedNames.UsesKnown(AContext.Index, mUsedUnits, AContext.Namespaces, AContext.EnsureUnit) then
  begin
    Exit;
  end;
  mFileName := AContext.FileName;
  if mFileName = '' then
  begin
    mFileName := AContext.RelativePath;
  end;
  if mFileName = '' then
  begin
    mFileName := AContext.UnitName + '.pas';
  end;
  mPaths := TConditionalBranches.Paths(AContext.Tree.Tokens);
  mOptions := TExpressionTypeOptions.Default;
  mOptions.Conversions := False;
  mOptions.ConstValue := False;
  mOtherRoutines := TDictionary<string, Boolean>.Create;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  try
    mResolver.PinTree(AContext.Tree, mFileName);
    mTypes := TExpressionTypes.Create(mResolver, AContext.Tree, mFileName, AContext.Text, AContext.Index, mOptions);
    try
      Visit(AContext.Tree.Root);
    finally
      mTypes.Free;
      mResolver.UnpinTree;
    end;
  finally
    mOtherRoutines.Free;
  end;
end;

procedure RegisterCallRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TArgumentCountMismatchRule.Create);
  ARegistry.Register(TOverloadResolutionRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Calls', cTexts);

end.
