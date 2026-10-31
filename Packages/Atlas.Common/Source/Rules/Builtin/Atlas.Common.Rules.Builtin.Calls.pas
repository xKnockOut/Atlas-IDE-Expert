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
  Atlas.Common.Editing.UsesClause;

const
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];

{ TArgumentCountMismatchRule }

function TArgumentCountMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ArgumentCountMismatchRuleId, TRuleSeverity.Error,
    'Falsche Anzahl Argumente beim Aufruf');
end;

class function TArgumentCountMismatchRule.SplitHeader(const AHeader: string; out AParameters,
  ATail: string): Boolean;
var
  Index, Depth, Generic, Open: Integer;
  InString: Boolean;
  Ch: Char;
begin
  AParameters := '';
  ATail := '';
  Result := False;
  Generic := 0;
  InString := False;
  Open := 0;
  // Bis zur ersten Klammer auf oberster Ebene; ":" oder ";" davor heißt: keine Parameterliste.
  for Index := 1 to Length(AHeader) do
  begin
    Ch := AHeader[Index];
    if Ch = '''' then
      InString := not InString;
    if InString then
      Continue;
    if Ch = '<' then
      Inc(Generic)
    else if Ch = '>' then
      Dec(Generic)
    else if Generic > 0 then
      Continue
    else if Ch = '(' then
    begin
      Open := Index;
      Break;
    end
    else if CharInSet(Ch, [':', ';']) then
    begin
      ATail := Copy(AHeader, Index, MaxInt);
      Exit(True);
    end;
  end;
  if Open = 0 then
    Exit(True);
  Depth := 0;
  for Index := Open to Length(AHeader) do
  begin
    Ch := AHeader[Index];
    if Ch = '''' then
      InString := not InString;
    if InString then
      Continue;
    if CharInSet(Ch, ['(', '[']) then
      Inc(Depth)
    else if CharInSet(Ch, [')', ']']) then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        AParameters := Copy(AHeader, Open + 1, Index - Open - 1);
        ATail := Copy(AHeader, Index + 1, MaxInt);
        Exit(True);
      end;
    end;
  end;
end;

class function TArgumentCountMismatchRule.MissingText(const ANames: TArray<string>): string;
var
  Index: Integer;
begin
  Result := '';
  if Length(ANames) = 0 then
    Exit;
  if Length(ANames) = 1 then
    Exit(ANames[0] + ' fehlt');
  for Index := 0 to High(ANames) - 1 do
  begin
    if Index > 0 then
      Result := Result + ', ';
    Result := Result + ANames[Index];
  end;
  Result := Result + ' und ' + ANames[High(ANames)] + ' fehlen';
end;

function ArgumentsText(ACount: Integer): string;
begin
  if ACount = 1 then
    Result := '1 Argument'
  else
    Result := IntToStr(ACount) + ' Argumente';
end;

function PassedText(ACount: Integer): string;
begin
  if ACount = 0 then
    Result := 'übergeben ist keins'
  else if ACount = 1 then
    Result := 'übergeben ist 1'
  else
    Result := 'übergeben sind ' + IntToStr(ACount);
end;

function HasWord(const AText, AWord: string): Boolean;
var
  Word: string;
begin
  Result := False;
  for Word in AText.Replace(';', ' ').Replace(',', ' ').Split([' ', #9, #10, #13],
    TStringSplitOptions.ExcludeEmpty) do
    if SameText(Word, AWord) then
      Exit(True);
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
      High := Middle - 1;
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
      Result := TConditionalBranches.PathAt(Paths, TokenAt(AContext.Tree.Tokens, APosition));
  end;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  /// <summary>Kopf einer Routine dieser Datei, die der Resolver ohne Index-Eintrag liefert (verschachtelte
  /// Routinen): der Knoten, der an ARange beginnt. Iterativ (Bericht M1).</summary>
  function LocalHeader(ARoot: TSyntaxNode; const ARange: TTextRange): string;
  var
    Pending: TStack<TSyntaxNode>;
    Node, Header: TSyntaxNode;
    Index: Integer;
  begin
    Result := '';
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.RoutineDecl) and (Node.StartPos.Line = ARange.StartPos.Line) and
          (Node.StartPos.Character = ARange.StartPos.Character) then
        begin
          Header := Node.FindChild(TSyntaxKind.RoutineHeader);
          if Header = nil then
            Header := Node;
          Result := NodeText(Header);
          if Result <> '' then
            Exit;
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          if (Node[Index].StartPos.Line <= ARange.StartPos.Line) and
            (Node[Index].EndPos.Line >= ARange.StartPos.Line) then
            Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  function HeaderOf(const ASymbol: TResolvedSymbol): string;
  begin
    Result := ASymbol.Signature;
    if (Result = '') and (ASymbol.Kind = TResolvedKind.Local) then
      Result := LocalHeader(AContext.Tree.Root, ASymbol.Range);
  end;

  /// <summary>Die eine Routine hinter ACallee samt Kopf; False bei Überladungen, varargs und allem, was
  /// keine Routine mit Quelltext ist.</summary>
  function SingleRoutine(ACallee: TSyntaxNode; out ARoutine: TResolvedSymbol; out AParameters: string): Boolean;
  var
    Candidates, Routines: TArray<TResolvedSymbol>;
    Candidate: TResolvedSymbol;
    Headers: TArray<string>;
    Header, Parameters, Tail, CallPath: string;
    Index, WithList: Integer;
  begin
    Result := False;
    CallPath := PathOf(ACallee.StartPos);
    Candidates := Resolver.CallCandidates(AContext.Tree, FileName, ACallee);
    if (Length(Candidates) = 0) or Resolver.MayBeHiddenMember(AContext.Tree, FileName, ACallee, Candidates[0]) then
      Exit;
    Routines := nil;
    Headers := nil;
    WithList := 0;
    for Candidate in Candidates do
    begin
      if Candidate.IsType or Candidate.Builtin or not (Candidate.SymbolKind in RoutineKinds) or
        (Candidate.Condition <> '') or (Length(Candidate.Overloads) > 0) then
        Exit;
      // Deklaration dieser Datei in einem Zweig, der ohne den Aufruf wegfallen kann.
      if ((Candidate.Kind = TResolvedKind.Local) or SameText(Candidate.FileName, FileName)) and
        not TConditionalBranches.Implies(CallPath, PathOf(Candidate.SelectionRange.StartPos)) then
        Exit;
      Header := HeaderOf(Candidate);
      if (Header = '') or not SplitHeader(Header, Parameters, Tail) or HasWord(Tail, 'overload') or
        HasWord(Tail, 'varargs') then
        Exit;
      if Pos('(', Header) > 0 then
        Inc(WithList);
      Routines := Routines + [Candidate];
      Headers := Headers + [Header];
    end;
    // Ein Rumpf ohne Parameterliste (procedure TKunde.Senden;) gehört zur Deklaration mit Liste.
    Index := -1;
    if Length(Routines) = 1 then
      Index := 0
    else if WithList = 1 then
      for Candidate in Routines do
      begin
        Inc(Index);
        if Pos('(', Headers[Index]) > 0 then
          Break;
      end
    else if WithList = 0 then
      Index := 0;
    if Index < 0 then
      Exit;
    // Mehrere Köpfe mit Liste: Überladung ohne overload oder Verdeckung; das klärt der Compiler.
    if (Length(Routines) > 1) and (WithList > 1) then
      Exit;
    ARoutine := Routines[Index];
    SplitHeader(Headers[Index], AParameters, Tail);
    Result := True;
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

  procedure CheckCall(ANode, ACallee: TSyntaxNode; const AArguments: TArray<TSyntaxNode>);
  var
    Routine: TResolvedSymbol;
    ParameterText, Message: string;
    Parameters: TArray<TSignatureParameter>;
    Missing: TArray<string>;
    Count, Index: Integer;
    Range: TTextRange;
    Target: TTextPosition;
    Fix: TRuleFix;
  begin
    if not (ACallee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      not SingleRoutine(ACallee, Routine, ParameterText) then
      Exit;
    Count := Length(AArguments);
    if (Count >= Routine.MinArgs) and (Count <= Routine.MaxArgs) then
      Exit;
    Parameters := TChangeSignature.ParseParameters(ParameterText);
    // Der Kopf muss zu den Zahlen des Index passen, sonst stimmt die Zuordnung der Namen nicht.
    if Length(Parameters) <> Routine.MaxArgs then
      Exit;
    if Count > Routine.MaxArgs then
    begin
      if (Routine.TypeName <> '') and not ResultTypeKnown(ANode) then
        Exit;
      if Routine.MaxArgs = 0 then
        Message := Format('%s erwartet keine Argumente, %s (wie E2034).', [Routine.Name, PassedText(Count)])
      else if Routine.MinArgs = Routine.MaxArgs then
        Message := Format('%s erwartet %s, %s (wie E2034).', [Routine.Name, ArgumentsText(Routine.MaxArgs),
          PassedText(Count)])
      else
        Message := Format('%s erwartet höchstens %s, %s (wie E2034).', [Routine.Name,
          ArgumentsText(Routine.MaxArgs), PassedText(Count)]);
      Range := TTextRange.Create(AArguments[Routine.MaxArgs].StartPos, AArguments[High(AArguments)].EndPos);
    end
    else
    begin
      Missing := nil;
      for Index := Count to Routine.MinArgs - 1 do
        Missing := Missing + [Parameters[Index].Name];
      if Routine.MinArgs = Routine.MaxArgs then
        Message := Format('%s erwartet %s, %s; %s (wie E2035).', [Routine.Name, ArgumentsText(Routine.MinArgs),
          PassedText(Count), MissingText(Missing)])
      else
        Message := Format('%s erwartet mindestens %s, %s; %s (wie E2035).', [Routine.Name,
          ArgumentsText(Routine.MinArgs), PassedText(Count), MissingText(Missing)]);
      Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
    end;
    // In die Klammern vor ")"; ohne Klammern erst () hinter den Namen.
    if ANode = ACallee then
    begin
      Target := TTextPosition.Create(ACallee.EndPos.Line, ACallee.EndPos.Character + 1);
      Fix := TRuleFix.SignatureHelp('Signaturhilfe öffnen', Target);
      Fix.Edits := [TTextEdit.Create(TTextRange.Create(ACallee.EndPos, ACallee.EndPos), '()')];
    end
    else
      Fix := TRuleFix.SignatureHelp('Signaturhilfe öffnen', TTextPosition.Create(ANode.EndPos.Line,
        ANode.EndPos.Character - 1));
    AReport.Add(Range, Message, TRuleConfidence.High, [Fix]);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
    Arguments: TArray<TSyntaxNode>;
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
          Arguments := nil;
          for Index := 1 to Node.ChildCount - 1 do
            if Node[Index].Kind <> TSyntaxKind.GenericArgs then
              Arguments := Arguments + [Node[Index]];
          CheckCall(Node, Node[0], Arguments);
        end
        // Versenden; als Anweisung ohne Klammern.
        else if (Node.Kind = TSyntaxKind.CallStatement) and (Node.ChildCount = 1) and
          (Node[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
          CheckCall(Node[0], Node[0], nil);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Paths := TConditionalBranches.Paths(AContext.Tree.Tokens);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  try
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Visit(AContext.Tree.Root);
    finally
      Resolver.UnpinTree;
    end;
  finally
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
    'Überladung nicht auflösbar oder mehrdeutig');
end;

class function TOverloadResolutionRule.Fit(AParameter, AArgument: TExpressionCategory): TArgumentFit;
const
  cNumbers = [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_];
  cFloats = [TExpressionCategory.Float, TExpressionCategory.Currency_];
  cDecided = [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_,
    TExpressionCategory.Boolean_, TExpressionCategory.Char_, TExpressionCategory.String_];
begin
  if AParameter = TExpressionCategory.Variant_ then
    Exit(TArgumentFit.Fits);
  // Zeiger (PChar nimmt String-Literale), Mengen, Klassen, Records mit Operatoren, Variant als Argument …
  if not (AParameter in cDecided) or not (AArgument in cDecided) then
    Exit(TArgumentFit.Unknown);
  case AArgument of
    TExpressionCategory.Integer_:
      if AParameter in cNumbers then
        Exit(TArgumentFit.Fits);
    TExpressionCategory.Float, TExpressionCategory.Currency_:
      if AParameter in cFloats then
        Exit(TArgumentFit.Fits);
    TExpressionCategory.Char_:
      if AParameter in [TExpressionCategory.Char_, TExpressionCategory.String_] then
        Exit(TArgumentFit.Fits);
  else
    if AParameter = AArgument then
      Exit(TArgumentFit.Fits);
  end;
  Result := TArgumentFit.Fails;
end;

class function TOverloadResolutionRule.SameTypeName(const A, B: string): Boolean;

  function Normal(const AName: string): string;
  begin
    Result := AName;
    if StartsText('System.', Result) then
      Result := Copy(Result, 8, MaxInt);
    if MatchText(Result, ['LongInt', 'Int32', 'FixedInt']) then
      Result := 'Integer'
    else if SameText(Result, 'UnicodeString') then
      Result := 'string'
    else if SameText(Result, 'WideChar') then
      Result := 'Char';
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
      Result := TConditionalBranches.PathAt(mPaths, TokenAt(AContext.Tree.Tokens, APosition));
  end;

  /// <summary>Steht AUnitName in uses (auch ohne Namespace-Präfix) oder ist es System?</summary>
  function InScope(const AUnitName: string): Boolean;
  var
    mUsed: string;
  begin
    Result := SameText(AUnitName, 'System') or SameText(AUnitName, 'SysInit');
    for mUsed in mUsedUnits do
      if SameText(AUnitName, mUsed) or EndsText('.' + mUsed, AUnitName) then
        Exit(True);
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
      Exit;
    Result := False;
    for mLocation in AContext.Index.FindSymbols(AName) do
      if (mLocation.Symbol.Kind in RoutineKinds) and (mLocation.Symbol.Container = '') and
        not SameText(mLocation.UnitName, AContext.UnitName) and not SameText(mLocation.FileName, mFileName) and
        InScope(mLocation.UnitName) then
      begin
        Result := True;
        Break;
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
      if (mLocation.Symbol.Kind in RoutineKinds) and (mLocation.Symbol.Container = '') and
        (SameText(mLocation.UnitName, AContext.UnitName) or InScope(mLocation.UnitName)) then
      begin
        if mFirst = '' then
          mFirst := mLocation.UnitName
        else if not SameText(mFirst, mLocation.UnitName) then
          Exit(True);
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
      Exit;
    mResolver.AncestorNames(mType, Result);
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
      Exit;
    for mOther in ASymbols do
      if HasWord(mOther.Signature, 'overload') and SameText(mOther.Container, ASymbol.Container) and
        (Length(mOther.ParamTypes) = Length(ASymbol.ParamTypes)) then
      begin
        mSame := True;
        for mIndex := 0 to High(mOther.ParamTypes) do
          mSame := mSame and SameText(mOther.ParamTypes[mIndex], ASymbol.ParamTypes[mIndex]);
        if mSame then
          Exit(True);
      end;
  end;

  /// <summary>Alle Überladungen hinter ACallee mit ihren Parametern; False, wenn die Liste nicht sicher
  /// vollständig ist oder es keine Überladung im Sinne von dcc ist.</summary>
  function Candidates(ACallee: TSyntaxNode; out AResult: TArray<TOverloadCandidate>): Boolean;
  var
    mFound, mSymbols: TArray<TResolvedSymbol>;
    mSymbol: TResolvedSymbol;
    mCandidate: TOverloadCandidate;
    mTail, mCallPath: string;
  begin
    Result := False;
    AResult := nil;
    mFound := mResolver.CallCandidates(AContext.Tree, mFileName, ACallee);
    mSymbols := nil;
    for mSymbol in mFound do
      if not IsBody(mSymbol, mFound) then
        mSymbols := mSymbols + [mSymbol];
    if (Length(mSymbols) < 2) or TUnresolvedNames.IsIntrinsic(ACallee.Name) or
      mResolver.MayBeHiddenMember(AContext.Tree, mFileName, ACallee, mSymbols[0]) then
      Exit;
    mCallPath := PathOf(ACallee.StartPos);
    for mSymbol in mSymbols do
    begin
      if mSymbol.IsType or mSymbol.Builtin or not (mSymbol.SymbolKind in RoutineKinds) or
        (mSymbol.Kind = TResolvedKind.Local) or (mSymbol.Condition <> '') or (mSymbol.TypeParams <> '') or
        (Length(mSymbol.Bindings) > 0) or (Pos('<', mSymbol.Container) > 0) or
        not HasWord(mSymbol.Signature, 'overload') or HasWord(mSymbol.Signature, 'varargs') then
        Exit;
      if SameText(mSymbol.FileName, mFileName) and
        not TConditionalBranches.Implies(mCallPath, PathOf(mSymbol.SelectionRange.StartPos)) then
        Exit;
      if mSymbol.Container = '' then
      begin
        if RoutineElsewhere(mSymbol.Name) then
          Exit;
      end
      else if not AncestorsKnown(mSymbol) then
        Exit;
      mCandidate.Symbol := mSymbol;
      if not TArgumentCountMismatchRule.SplitHeader(mSymbol.Signature, mCandidate.ParameterText, mTail) then
        Exit;
      mCandidate.Parameters := TChangeSignature.ParseParameters(mCandidate.ParameterText);
      if Length(mCandidate.Parameters) <> mSymbol.MaxArgs then
        Exit;
      AResult := AResult + [mCandidate];
    end;
    // Ein unbekannter Vorfahr der umgebenden Klasse kann weitere Überladungen erben (nach CallCandidates gültig).
    Result := not mResolver.HasUnknownAncestor;
  end;

  /// <summary>Typ eines Arguments; '' wenn er nicht sicher ist (überladene Aufrufe darin, untypisierte
  /// Konstanten, die als Char zählen könnten).</summary>
  function ArgumentType(AArgument: TSyntaxNode; out ACategory: TExpressionCategory): string;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex, mWidth: Integer;
    mSigned, mTypeFound: Boolean;
    mInfo: TExpressionTypeInfo;
    mSymbol, mType: TResolvedSymbol;
  begin
    Result := '';
    ACategory := TExpressionCategory.Unknown;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AArgument);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.AnonymousMethod then
          Exit;
        // Der Typ eines überladenen Aufrufs im Argument hängt selbst von der Auswahl ab.
        if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount > 0) and
          (Length(mResolver.CallCandidates(AContext.Tree, mFileName, mNode[0])) <> 1) then
          Exit;
        // Freie Routine aus mehreren Units: Welche gilt, entscheidet dcc nach uses-Reihenfolge und Argumenten.
        if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount > 0) and (mNode[0].Kind = TSyntaxKind.Identifier) and
          RoutineInSeveralUnits(mNode[0].Name) then
          Exit;
        for mIndex := mNode.ChildCount - 1 downto 0 do
          mPending.Push(mNode[mIndex]);
      end;
    finally
      mPending.Free;
    end;
    mInfo := mTypes.Describe(AArgument);
    if not mInfo.Found then
      Exit;
    Result := mInfo.TypeName;
    if mInfo.BaseName <> '' then
      Result := mInfo.BaseName;
    ACategory := TExpressionTypes.CategoryOf(Result, mWidth, mSigned);
    // Konstanten bekommen ihren Typ erst am Aufruf (const X = 'a' ist ein Char, Separator = '›' kein Integer).
    if (AArgument.Kind in [TSyntaxKind.Identifier,
      TSyntaxKind.MemberAccess]) and mResolver.NodeType(AContext.Tree, mFileName, AArgument, mSymbol, mType,
      mTypeFound) and (mSymbol.SymbolKind = TIndexSymbolKind.Constant) then
    begin
      ACategory := TExpressionCategory.Unknown;
      Result := '';
    end;
  end;

  /// <summary>Typfamilie eines Parametertyps; Aliase auf eingebaute Typen (TFileName = string) zählen wie
  /// ihr Grundtyp.</summary>
  function ParameterCategory(const ACandidate: TOverloadCandidate; const AParameter: TSignatureParameter):
    TExpressionCategory;
  var
    mText: string;
    mWidth: Integer;
    mSigned: Boolean;
    mUnit: TUnitIndex;
    mResolved, mFollowed: TResolvedSymbol;
  begin
    Result := TExpressionCategory.Unknown;
    mText := Trim(AParameter.TypeName);
    if (mText = '') or StartsText('array', mText) or (Pos('<', mText) > 0) then
      Exit;
    Result := TExpressionTypes.CategoryOf(mText, mWidth, mSigned);
    if Result <> TExpressionCategory.Other then
      Exit;
    Result := TExpressionCategory.Unknown;
    if mResolver.DeclaringUnit(ACandidate.Symbol, mUnit) and mResolver.ResolveTypeTextFrom(mUnit, mText, mResolved) and
      not mResolved.Builtin and (mResolved.SymbolKind = TIndexSymbolKind.TypeAlias) and
      mResolver.TypeOf(mResolved, mFollowed) and mFollowed.Builtin then
      Result := TExpressionTypes.CategoryOf(mFollowed.Name, mWidth, mSigned);
    if Result = TExpressionCategory.Other then
      Result := TExpressionCategory.Unknown;
  end;

  function Fails(const ACandidate: TOverloadCandidate; const ATypes: TArray<string>;
    const ACategories: TArray<TExpressionCategory>): Boolean;
  var
    mIndex: Integer;
  begin
    if (Length(ATypes) < ACandidate.Symbol.MinArgs) or (Length(ATypes) > ACandidate.Symbol.MaxArgs) then
      Exit(True);
    Result := False;
    for mIndex := 0 to High(ATypes) do
      if Fit(ParameterCategory(ACandidate, ACandidate.Parameters[mIndex]), ACategories[mIndex]) =
        TArgumentFit.Fails then
        Exit(True);
  end;

  /// <summary>Passt jedes Argument sicher (gleicher Typ wie der Parameter)?</summary>
  function SurelyFits(const ACandidate: TOverloadCandidate; const ATypes: TArray<string>): Boolean;
  var
    mIndex: Integer;
  begin
    Result := True;
    for mIndex := 0 to High(ATypes) do
      if not SameTypeName(ATypes[mIndex], ACandidate.Parameters[mIndex].TypeName) then
        Exit(False);
  end;

  /// <summary>Gleiche Parametertypen und -arten für die ersten ACount Parameter.</summary>
  function SamePrefix(const A, B: TOverloadCandidate; ACount: Integer): Boolean;
  var
    mIndex: Integer;
  begin
    Result := True;
    for mIndex := 0 to ACount - 1 do
      if not SameTypeName(A.Parameters[mIndex].TypeName, B.Parameters[mIndex].TypeName) or
        ((Pos('var', LowerCase(A.Parameters[mIndex].Modifier)) > 0) <>
        (Pos('var', LowerCase(B.Parameters[mIndex].Modifier)) > 0)) or
        ((Pos('out', LowerCase(A.Parameters[mIndex].Modifier)) > 0) <>
        (Pos('out', LowerCase(B.Parameters[mIndex].Modifier)) > 0)) then
        Exit(False);
  end;

  /// <summary>Vor dem Aufruf deklariert (interface oder weiter oben in dieser Datei)?</summary>
  function DeclaredBefore(const ACandidate: TOverloadCandidate; ACall: TSyntaxNode): Boolean;
  var
    mStart: TTextPosition;
  begin
    if not SameText(ACandidate.Symbol.FileName, mFileName) or ACandidate.Symbol.InInterface then
      Exit(True);
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
        Result := Result + ', ';
      if ATypes[mIndex] = '' then
        Result := Result + '?'
      else
        Result := Result + ATypes[mIndex];
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
        Result := Result + ' und '
      else if mIndex > 0 then
        Result := Result + ', ';
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
        Exit(True);
      mNode := mNode.Parent;
    end;
  end;

  procedure CheckCall(ANode, ACallee: TSyntaxNode; const AArguments: TArray<TSyntaxNode>);
  var
    mCandidates, mApplicable: TArray<TOverloadCandidate>;
    mCandidate: TOverloadCandidate;
    mTypes: TArray<string>;
    mCategories: TArray<TExpressionCategory>;
    mIndex: Integer;
    mMessage: string;
    mFix: TRuleFix;
  begin
    if not (ACallee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      (ACallee.FindChild(TSyntaxKind.GenericArgs) <> nil) or InWith(ANode) or
      not Candidates(ACallee, mCandidates) then
      Exit;
    SetLength(mTypes, Length(AArguments));
    SetLength(mCategories, Length(AArguments));
    for mIndex := 0 to High(AArguments) do
      mTypes[mIndex] := ArgumentType(AArguments[mIndex], mCategories[mIndex]);
    mApplicable := nil;
    for mCandidate in mCandidates do
      if not Fails(mCandidate, mTypes, mCategories) then
        mApplicable := mApplicable + [mCandidate];
    if (Length(mApplicable) = 0) and (Length(mTypes) = 0) then
      mMessage := Format('Keine der %d Überladungen von %s lässt sich ohne Argumente aufrufen (wie E2250).',
        [Length(mCandidates), ACallee.Name])
    else if Length(mApplicable) = 0 then
      mMessage := Format('Keine der %d Überladungen von %s passt zu den Argumenten (%s) (wie E2250).',
        [Length(mCandidates), ACallee.Name, TypesText(mTypes)])
    else
    begin
      // Mehrdeutig nur, wenn nichts die Kandidaten unterscheidet: gleiche Typen für alle übergebenen
      // Argumente, dieselbe Klasse bzw. Unit, vor dem Aufruf deklariert, jedes Argument sicher passend.
      if Length(mApplicable) < 2 then
        Exit;
      for mCandidate in mApplicable do
        if not SamePrefix(mApplicable[0], mCandidate, Length(AArguments)) or
          not SameText(mCandidate.Symbol.Container, mApplicable[0].Symbol.Container) or
          not SameText(mCandidate.Symbol.FileName, mApplicable[0].Symbol.FileName) or
          (mCandidate.Symbol.Depth <> mApplicable[0].Symbol.Depth) or not DeclaredBefore(mCandidate, ANode) or
          not SurelyFits(mCandidate, mTypes) then
          Exit;
      mMessage := Format('Aufruf von %s ist mehrdeutig: %s passen gleich gut (wie E2251).',
        [ACallee.Name, ListText(mApplicable)]);
    end;
    if ANode = ACallee then
    begin
      mFix := TRuleFix.SignatureHelp('Signaturhilfe öffnen', TTextPosition.Create(ACallee.EndPos.Line,
        ACallee.EndPos.Character + 1));
      mFix.Edits := [TTextEdit.Create(TTextRange.Create(ACallee.EndPos, ACallee.EndPos), '()')];
    end
    else
      mFix := TRuleFix.SignatureHelp('Signaturhilfe öffnen', TTextPosition.Create(ANode.EndPos.Line,
        ANode.EndPos.Character - 1));
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), mMessage, TRuleConfidence.High, [mFix]);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
    mArguments: TArray<TSyntaxNode>;
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
          mArguments := nil;
          for mIndex := 1 to mNode.ChildCount - 1 do
            if mNode[mIndex].Kind <> TSyntaxKind.GenericArgs then
              mArguments := mArguments + [mNode[mIndex]];
          CheckCall(mNode, mNode[0], mArguments);
        end
        // Nimm; als Anweisung ohne Klammern.
        else if (mNode.Kind = TSyntaxKind.CallStatement) and (mNode.ChildCount = 1) and
          (mNode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
          CheckCall(mNode[0], mNode[0], nil);
        for mIndex := mNode.ChildCount - 1 downto 0 do
          mPending.Push(mNode[mIndex]);
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
    Exit;
  mUsedUnits := TUsesClauses.UsedUnits(AContext.Tree.Tokens);
  if not TUnresolvedNames.UsesKnown(AContext.Index, mUsedUnits, AContext.Namespaces, AContext.EnsureUnit) then
    Exit;
  mFileName := AContext.FileName;
  if mFileName = '' then
    mFileName := AContext.RelativePath;
  if mFileName = '' then
    mFileName := AContext.UnitName + '.pas';
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

end.
