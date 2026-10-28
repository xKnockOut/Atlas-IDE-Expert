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
// Korrektur „Signaturhilfe öffnen“: springt in die Klammern des Aufrufs und
// öffnet dort den Parameter-Hint (Client-Befehl atlas.showSignatureHelp);
// ohne Klammern setzt sie zuerst () hinter den Namen.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ArgumentCountMismatchRuleId = 'argument-count-mismatch';

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

procedure RegisterCallRules(const ARegistry: TRuleRegistry);

implementation

uses
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
  Atlas.Common.Editing.ChangeSignature;

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
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Visit(AContext.Tree.Root);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

procedure RegisterCallRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TArgumentCountMismatchRule.Create);
end;

end.
