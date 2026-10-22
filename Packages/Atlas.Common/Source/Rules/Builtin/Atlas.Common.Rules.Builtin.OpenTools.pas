unit Atlas.Common.Rules.Builtin.OpenTools;

// Regeln für Experten der Open Tools API (IDE-Plugins):
//   ota-notifier-not-removed  AddNotifier (bzw. ein Paar aus "registerPairs"), dessen Index nie an
//                             RemoveNotifier geht (#944): als Anweisung ohne Zuweisung oder in eine
//                             Variable, die in der Unit kein RemoveNotifier(…) erhält. Die IDE ruft den
//                             Notifier sonst nach dem Entladen in fremdem Speicher auf. Ausgenommen sind
//                             Register…-Aufrufe in der Prozedur Register: die IDE entfernt diese Wizards
//                             selbst. Korrektur in Methoden: Index in ein Feld (F…Index im private-
//                             Abschnitt), RemoveNotifier im Destruktor (legt ihn bei Bedarf an); in
//                             Prozeduren der Unit: globale Variable mit -1 und RemoveNotifier in
//                             finalization. Keine Korrektur, wenn der Empfänger lokal ist.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  /// <summary>Paar aus Anmeldung und Abmeldung, z. B. AddNotifier/RemoveNotifier.</summary>
  TRegisterPair = record
    Open: string;
    Close: string;
  end;

  TOtaNotifierNotRemovedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Paare aus der Option "registerPairs", sonst AddNotifier/RemoveNotifier und
    /// RegisterPackageWizard/RemoveWizard.</summary>
    class function Pairs(const AOptions: string): TArray<TRegisterPair>; static;
    /// <summary>Name für den gemerkten Index: AddNotifier → NotifierIndex, RegisterPackageWizard →
    /// PackageWizardIndex.</summary>
    class function IndexName(const AOpen: string): string; static;
  end;

procedure RegisterOpenToolsRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.FreeFields;

const
  OtaNotifierNotRemovedRuleId = 'ota-notifier-not-removed';
  /// <summary>Token, nach denen eine Anweisung beginnt.</summary>
  StatementStarts: array[0..8] of string = (';', 'begin', 'then', 'do', 'else', 'try', 'finally', 'except',
    'repeat');

{ TOtaNotifierNotRemovedRule }

function TOtaNotifierNotRemovedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OtaNotifierNotRemovedRuleId, TRuleSeverity.Warning,
    'IDE-Notifier ohne RemoveNotifier');
end;

class function TOtaNotifierNotRemovedRule.Pairs(const AOptions: string): TArray<TRegisterPair>;
var
  Value, List, Item: TJSONValue;
  Pair: TRegisterPair;
begin
  SetLength(Result, 2);
  Result[0].Open := 'AddNotifier';
  Result[0].Close := 'RemoveNotifier';
  Result[1].Open := 'RegisterPackageWizard';
  Result[1].Close := 'RemoveWizard';
  if Trim(AOptions) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
      Exit;
    List := TJSONObject(Value).GetValue('registerPairs');
    if not (List is TJSONArray) then
      Exit;
    Result := nil;
    for Item in TJSONArray(List) do
      if (Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>('open', Pair.Open) and
        TJSONObject(Item).TryGetValue<string>('close', Pair.Close) and (Trim(Pair.Open) <> '') and
        (Trim(Pair.Close) <> '') then
      begin
        Pair.Open := Trim(Pair.Open);
        Pair.Close := Trim(Pair.Close);
        Result := Result + [Pair];
      end;
  finally
    Value.Free;
  end;
end;

class function TOtaNotifierNotRemovedRule.IndexName(const AOpen: string): string;
begin
  Result := AOpen;
  if StartsText('Add', Result) and (Length(Result) > 3) then
    Result := Copy(Result, 4, MaxInt)
  else if StartsText('Register', Result) and (Length(Result) > 8) then
    Result := Copy(Result, 9, MaxInt);
  Result := UpperCase(Copy(Result, 1, 1)) + Copy(Result, 2, MaxInt) + 'Index';
end;

procedure TOtaNotifierNotRemovedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Lines: TArray<string>;
  LineBreak: string;
  RegisterPairs: TArray<TRegisterPair>;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsWord(APosition: Integer): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier);
  end;

  // Gegenstück der Klammer bei APosition; -1 ohne.
  function Matching(APosition: Integer): Integer;
  var
    Depth, Step: Integer;
  begin
    Step := 1;
    if Token(APosition).IsSymbol(')') or Token(APosition).IsSymbol(']') then
      Step := -1;
    Depth := 0;
    Result := APosition;
    while (Result >= 0) and (Result <= High(Code)) do
    begin
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
        Inc(Depth, Step)
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
        Dec(Depth, Step);
      if Depth = 0 then
        Exit;
      Inc(Result, Step);
    end;
    Result := -1;
  end;

  // Anfang des Ausdrucks vor dem Punkt bei ADot: Namen, Punkte, Aufrufe und Klammern.
  function ReceiverStart(ADot: Integer): Integer;
  var
    Position: Integer;
  begin
    Result := ADot;
    Position := ADot - 1;
    while Position >= 0 do
      if Token(Position).IsSymbol(')') or Token(Position).IsSymbol(']') then
      begin
        Position := Matching(Position);
        if Position < 0 then
          Exit(-1);
        Result := Position;
        Dec(Position);
      end
      else if IsWord(Position) then
      begin
        Result := Position;
        Dec(Position);
        if (Position >= 0) and Token(Position).IsSymbol('.') then
          Dec(Position)
        else
          Break;
      end
      else
        Break;
  end;

  function TextOf(AFirst, ALast: Integer): string;
  begin
    Result := Copy(AContext.Text, Token(AFirst).Offset + 1,
      Token(ALast).Offset + Length(Token(ALast).Text) - Token(AFirst).Offset);
  end;

  // Ohne Leerraum und ohne führendes Self., zum Vergleich von Variablen.
  function Normalized(const AText: string): string;
  begin
    Result := LowerCase(StringReplace(StringReplace(StringReplace(AText, ' ', '', [rfReplaceAll]), #10, '',
      [rfReplaceAll]), #13, '', [rfReplaceAll]));
    if StartsStr('self.', Result) then
      Result := Copy(Result, 6, MaxInt);
  end;

  // Gibt die Unit ATarget an AClose weiter: AClose(ATarget) bzw. X.AClose(ATarget)? Es zählen auch der letzte
  // Teil (Notifier.FIndex → FIndex, im Notifier selbst abgemeldet) und Kopien (Index := FIndex).
  function Removed(const AClose, ATarget: string): Boolean;
  var
    Position, Close, Stop, Dot: Integer;
    Names: TArray<string>;
  begin
    Names := [ATarget];
    Dot := LastDelimiter('.', ATarget);
    if Dot > 0 then
      Names := Names + [Copy(ATarget, Dot + 1, MaxInt)];
    for Position := 1 to High(Code) - 2 do
      if IsWord(Position - 1) and Token(Position).IsSymbol(':=') then
      begin
        Stop := Position + 1;
        while (Stop <= High(Code)) and not Token(Stop).IsSymbol(';') and not Token(Stop).IsKeyword('end') do
          Inc(Stop);
        if MatchText(Normalized(TextOf(Position + 1, Stop - 1)), Names) then
          Names := Names + [LowerCase(Token(Position - 1).Text)];
      end;
    for Position := 0 to High(Code) - 1 do
      if IsWord(Position) and SameText(Token(Position).Text, AClose) and Token(Position + 1).IsSymbol('(') then
      begin
        Close := Matching(Position + 1);
        if (Close > Position + 2) and MatchText(Normalized(TextOf(Position + 2, Close - 1)), Names) then
          Exit(True);
      end;
    Result := False;
  end;

  // Innerste Routine um AOffset; nil außerhalb. Iterativ (Bericht M1): Suche in Vorordnung über die Knoten um
  // AOffset; jede gefundene Routine ersetzt das Ergebnis, und die Suche geht nur in ihr weiter.
  function RoutineAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Result := nil;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (AOffset < Node.StartOffset) or (AOffset >= Node.EndOffset) then
          Continue;
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          Result := Node;
          Pending.Clear;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Äußerste Routine um AOffset; nil außerhalb. Iterativ (Bericht M1).
  function OuterRoutineAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Result := nil;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (AOffset < Node.StartOffset) or (AOffset >= Node.EndOffset) then
          Continue;
        if Node.Kind = TSyntaxKind.RoutineDecl then
          Exit(Node);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Edits nach Position, wie der Editor sie anwendet.
  function Sorted(const AEdits: TArray<TTextEdit>): TArray<TTextEdit>;
  var
    Index, Other: Integer;
    Swap: TTextEdit;
  begin
    Result := Copy(AEdits);
    for Index := 0 to High(Result) - 1 do
      for Other := Index + 1 to High(Result) do
        if (Result[Other].Range.StartPos.Line < Result[Index].Range.StartPos.Line) or
          ((Result[Other].Range.StartPos.Line = Result[Index].Range.StartPos.Line) and
          (Result[Other].Range.StartPos.Character < Result[Index].Range.StartPos.Character)) then
        begin
          Swap := Result[Index];
          Result[Index] := Result[Other];
          Result[Other] := Swap;
        end;
  end;

  // Iterativ (Bericht M1).
  function FindClassDecl(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Result := nil;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.TypeDecl) and SameText(Node.Name, AName) and
          (Node.FindChild(TSyntaxKind.ClassType) <> nil) then
          Exit(Node);
        if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.RoutineDecl] then
          Continue;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Ist AName in ARoutine vor deren Rumpf deklariert (Parameter, lokale Variable)?
  function IsLocal(ARoutine: TSyntaxNode; const AName: string): Boolean;
  var
    Block: TSyntaxNode;
    Position: Integer;
  begin
    Result := False;
    Block := ARoutine.FindChild(TSyntaxKind.Block);
    if Block = nil then
      Exit;
    for Position := 0 to High(Code) do
      if (Token(Position).Offset >= ARoutine.StartOffset) and (Token(Position).Offset < Block.StartOffset) and
        IsWord(Position) and SameText(Token(Position).Text, AName) then
        Exit(True);
  end;

  // Kommt AName als Bezeichner in der Unit vor?
  function Used(const AName: string): Boolean;
  var
    Position: Integer;
  begin
    for Position := 0 to High(Code) do
      if IsWord(Position) and SameText(Token(Position).Text, AName) then
        Exit(True);
    Result := False;
  end;

  // Erster Bezeichner von AFirst..ALast ohne Self; '' ohne.
  function FirstName(AFirst, ALast: Integer): string;
  var
    Position: Integer;
  begin
    Result := '';
    for Position := AFirst to ALast do
      if IsWord(Position) and not SameText(Token(Position).Text, 'Self') then
        Exit(Token(Position).Text);
  end;

  // "FName: Integer;" in den ersten private-Abschnitt, sonst als neuer Abschnitt vor das "end" der Klasse.
  function FieldEdit(ADecl: TSyntaxNode; const AField: string; out AEdit: TTextEdit): Boolean;
  var
    ClassNode, Child: TSyntaxNode;
    Index, Line: Integer;
    Indent: string;
  begin
    Result := False;
    ClassNode := ADecl.FindChild(TSyntaxKind.ClassType);
    for Index := 0 to ClassNode.ChildCount - 1 do
    begin
      Child := ClassNode[Index];
      if (Child.Kind = TSyntaxKind.Visibility) and SameText(Child.Name, 'private') and
        (Child.StartPos.Line <= High(Lines)) then
      begin
        Line := Child.EndPos.Line;
        Indent := TTextLines.IndentOf(Lines[Child.StartPos.Line]) + '  ';
        AEdit := TTextEdit.Create(TTextRange.Create(TTextPosition.Create(Line, Length(Lines[Line])),
          TTextPosition.Create(Line, Length(Lines[Line]))), LineBreak + Indent + AField + ': Integer;');
        Exit(True);
      end;
    end;
    Line := ClassNode.EndPos.Line;
    if (Line > High(Lines)) or (Trim(Copy(Lines[Line], 1, ClassNode.EndPos.Character - 3)) <> '') then
      Exit;
    Indent := TTextLines.IndentOf(Lines[Line]);
    AEdit := TTextEdit.Create(TTextRange.Create(Line, 0, Line, 0), Indent + 'private' + LineBreak + Indent + '  ' +
      AField + ': Integer;' + LineBreak);
    Result := True;
  end;

  // Abmeldung in finalization: hinter "finalization", sonst als neuer Abschnitt vor "end."; ohne
  // initialization kommt ein leerer Abschnitt davor (finalization verlangt ihn).
  function FinalizationEdit(const AStatement: string; out AEdit: TTextEdit): Boolean;
  var
    Position, Line: Integer;
    Head: string;
  begin
    Result := False;
    Head := 'initialization' + LineBreak + LineBreak;
    for Position := 0 to High(Code) do
      if Token(Position).IsKeyword('initialization') then
        Head := '';
    for Position := 0 to High(Code) do
      if Token(Position).IsKeyword('finalization') then
      begin
        Line := Token(Position).EndPos.Line;
        AEdit := TTextEdit.Create(TTextRange.Create(TTextPosition.Create(Line, Length(Lines[Line])),
          TTextPosition.Create(Line, Length(Lines[Line]))), LineBreak + AStatement);
        Exit(True);
      end;
    // "end." am Ende der Unit, allein in seiner Zeile.
    Position := High(Code);
    if (Position < 1) or not Token(Position).IsSymbol('.') or not Token(Position - 1).IsKeyword('end') then
      Exit;
    Line := Token(Position - 1).StartPos.Line;
    if Trim(Copy(Lines[Line], 1, Token(Position - 1).StartPos.Character)) <> '' then
      Exit;
    AEdit := TTextEdit.Create(TTextRange.Create(Line, 0, Line, 0), Head + 'finalization' + LineBreak + AStatement +
      LineBreak + LineBreak);
    Result := True;
  end;

  // Korrektur für einen Aufruf ohne Zuweisung (AStart: Anfang der Anweisung) bzw. eine Zuweisung an ATarget
  // ('' = keine Zuweisung).
  function FixFor(const APair: TRegisterPair; ARoutine: TSyntaxNode; AStart, AReceiverFirst,
    AReceiverLast: Integer; const ATarget: string; out AFix: TRuleFix): Boolean;
  var
    Receiver, Name, ClassName, Method, Indent, Statement: string;
    Dot: Integer;
    Decl: TSyntaxNode;
    Edits, Destroying: TArray<TTextEdit>;
    Edit: TTextEdit;
  begin
    Result := False;
    if ARoutine = nil then
      Exit;
    Receiver := '';
    if AReceiverFirst >= 0 then
    begin
      // Lokale Empfänger gibt es im Destruktor bzw. in finalization nicht.
      Name := FirstName(AReceiverFirst, AReceiverLast);
      if (Name <> '') and IsLocal(ARoutine, Name) then
        Exit;
      Receiver := TextOf(AReceiverFirst, AReceiverLast) + '.';
    end;
    Dot := LastDelimiter('.', ARoutine.Name);
    Edits := nil;
    if Dot > 0 then
    begin
      // Methode: Feld und Destruktor.
      ClassName := Copy(ARoutine.Name, 1, Dot - 1);
      Method := Copy(ARoutine.Name, Dot + 1, MaxInt);
      if SameText(Method, 'Destroy') then
        Exit;
      Decl := FindClassDecl(AContext.Tree.Root, ClassName);
      if Decl = nil then
        Exit;
      Name := ATarget;
      if Name = '' then
      begin
        Name := 'F' + IndexName(APair.Open);
        if Used(Name) or not FieldEdit(Decl, Name, Edit) then
          Exit;
        Edits := [Edit, TTextEdit.Create(TTextRange.Create(Token(AStart).StartPos, Token(AStart).StartPos),
          Name + ' := ')];
      end
      else if IsLocal(ARoutine, Normalized(ATarget)) then
        Exit;
      if not TFreeFields.DestructorEdits(AContext.Tree, AContext.Text, ClassName, Decl.StartPos.Line,
        [Receiver + APair.Close + '(' + Name + ');'], Destroying) then
        Exit;
      AFix := TRuleFix.Create(Format('Index in ein Feld legen und %s im Destruktor ergänzen', [APair.Close]),
        Sorted(Edits + Destroying));
      if ATarget <> '' then
        AFix := TRuleFix.Create(Format('%s im Destruktor ergänzen', [APair.Close]), Sorted(Edits + Destroying));
      Exit(True);
    end;
    // Prozedur der Unit: globale Variable und finalization; nur in Units und nicht in verschachtelten Routinen.
    if (Length(Code) = 0) or not Token(0).IsKeyword('unit') or
      (OuterRoutineAt(AContext.Tree.Root, ARoutine.StartOffset) <> ARoutine) then
      Exit;
    Name := ATarget;
    Indent := '  ';
    if Name = '' then
    begin
      Name := IndexName(APair.Open);
      if Used(Name) then
        Exit;
      Edits := [TTextEdit.Create(TTextRange.Create(ARoutine.StartPos.Line, 0, ARoutine.StartPos.Line, 0),
        'var' + LineBreak + Indent + Name + ': Integer = -1;' + LineBreak + LineBreak),
        TTextEdit.Create(TTextRange.Create(Token(AStart).StartPos, Token(AStart).StartPos), Name + ' := ')];
      Statement := Indent + 'if ' + Name + ' >= 0 then' + LineBreak + Indent + '  ' + Receiver + APair.Close +
        '(' + Name + ');';
    end
    else
    begin
      if IsLocal(ARoutine, Name) then
        Exit;
      Statement := Indent + Receiver + APair.Close + '(' + Name + ');';
    end;
    if not FinalizationEdit(Statement, Edit) then
      Exit;
    // Die finalization steht hinter der Routine.
    Edits := Edits + [Edit];
    if ATarget = '' then
      AFix := TRuleFix.Create(Format('Index merken und %s in finalization ergänzen', [APair.Close]), Edits)
    else
      AFix := TRuleFix.Create(Format('%s in finalization ergänzen', [APair.Close]), Edits);
    Result := True;
  end;

  procedure CheckCall(APosition: Integer; const APair: TRegisterPair);
  var
    Start, Before, ReceiverFirst, ReceiverLast: Integer;
    Target: string;
    Routine: TSyntaxNode;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
    Range: TTextRange;
  begin
    ReceiverFirst := -1;
    ReceiverLast := -1;
    Start := APosition;
    if (APosition > 0) and Token(APosition - 1).IsSymbol('.') then
    begin
      ReceiverFirst := ReceiverStart(APosition - 1);
      if ReceiverFirst < 0 then
        Exit;
      ReceiverLast := APosition - 2;
      Start := ReceiverFirst;
    end;
    Routine := RoutineAt(AContext.Tree.Root, Token(APosition).Offset);
    // Register…-Aufrufe in Register: die IDE entfernt diese Wizards beim Entladen selbst.
    if StartsText('Register', APair.Open) and (Routine <> nil) and SameText(Routine.Name, 'Register') then
      Exit;
    Range := TTextRange.Create(Token(APosition).StartPos, Token(APosition).EndPos);
    Before := Start - 1;
    Fixes := nil;
    if (Before < 0) or MatchText(Token(Before).Text, StatementStarts) then
    begin
      if FixFor(APair, Routine, Start, ReceiverFirst, ReceiverLast, '', Fix) then
        Fixes := [Fix];
      AReport.Add(Range, Format('Der Index von %s wird nicht gemerkt; ohne %s ruft die IDE nach dem Entladen ' +
        'ins Leere.', [APair.Open, APair.Close]), TRuleConfidence.Medium, Fixes);
      Exit;
    end;
    if not Token(Before).IsSymbol(':=') then
      Exit;
    // Ziel der Zuweisung: Namen und Punkte bis zum Anfang der Anweisung.
    Start := Before - 1;
    while (Start > 0) and (IsWord(Start - 1) or Token(Start - 1).IsSymbol('.')) do
      Dec(Start);
    if (Start < 0) or not IsWord(Start) then
      Exit;
    Target := Normalized(TextOf(Start, Before - 1));
    if Removed(APair.Close, Target) then
      Exit;
    if FixFor(APair, Routine, Start, ReceiverFirst, ReceiverLast, TextOf(Start, Before - 1), Fix) then
      Fixes := [Fix];
    AReport.Add(Range, Format('Der Index %s von %s geht nie an %s; die IDE ruft nach dem Entladen ins Leere.',
      [TextOf(Start, Before - 1), APair.Open, APair.Close]), TRuleConfidence.Medium, Fixes);
  end;

var
  Index: Integer;
  Pair: TRegisterPair;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Code := Code + [Index];
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  RegisterPairs := Pairs(AContext.Options);
  for Index := 0 to High(Code) - 1 do
    if IsWord(Index) and Token(Index + 1).IsSymbol('(') then
      for Pair in RegisterPairs do
        if SameText(Token(Index).Text, Pair.Open) then
          CheckCall(Index, Pair);
end;

procedure RegisterOpenToolsRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOtaNotifierNotRemovedRule.Create);
end;

end.
