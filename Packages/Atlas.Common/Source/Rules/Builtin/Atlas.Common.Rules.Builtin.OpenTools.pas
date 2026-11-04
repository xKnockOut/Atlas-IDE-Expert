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
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
    begin
      Exit;
    end;
    List := TJSONObject(Value).GetValue('registerPairs');
    if not (List is TJSONArray) then
    begin
      Exit;
    end;
    Result := nil;
    for Item in TJSONArray(List) do
    begin
      if (Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>('open', Pair.Open) and
        TJSONObject(Item).TryGetValue<string>('close', Pair.Close) and (Trim(Pair.Open) <> '') and
        (Trim(Pair.Close) <> '') then
      begin
        Pair.Open := Trim(Pair.Open);
        Pair.Close := Trim(Pair.Close);
        Result := Result + [Pair];
      end;
    end;
  finally
    Value.Free;
  end;
end;

class function TOtaNotifierNotRemovedRule.IndexName(const AOpen: string): string;
begin
  Result := AOpen;
  if StartsText('Add', Result) and (Length(Result) > 3) then
  begin
    Result := Copy(Result, 4, MaxInt);
  end
  else if StartsText('Register', Result) and (Length(Result) > 8) then
  begin
    Result := Copy(Result, 9, MaxInt);
  end;
  Result := UpperCase(Copy(Result, 1, 1)) + Copy(Result, 2, MaxInt) + 'Index';
end;

type
  /// <summary>Ein Aufruf der Anmeldung: Paar, Position, Empfänger (-1 ohne), Anfang der Anweisung, Routine.</summary>
  TNotifierCall = record
    Pair: TRegisterPair;
    Position: Integer;
    ReceiverFirst: Integer;
    ReceiverLast: Integer;
    Start: Integer;
    Routine: TSyntaxNode;
  end;

  /// <summary>Ein Lauf der Regel über eine Unit.</summary>
  TOtaNotifierScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TArray<TPascalToken>;
    FCode: TArray<Integer>;
    FLines: TArray<string>;
    FLineBreak: string;
    FRegisterPairs: TArray<TRegisterPair>;
    function Token(APosition: Integer): TPascalToken;
    function IsWord(APosition: Integer): Boolean;
    function Matching(APosition: Integer): Integer;
    function ReceiverStart(ADot: Integer): Integer;
    function TextOf(AFirst, ALast: Integer): string;
    function Normalized(const AText: string): string;
    function Removed(const AClose, ATarget: string): Boolean;
    function AliasNames(const ATarget: string): TArray<string>;
    function PassesName(const AOpen: Integer; const ANames: TArray<string>): Boolean;
    function RoutineAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
    function OuterRoutineAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
    function Sorted(const AEdits: TArray<TTextEdit>): TArray<TTextEdit>;
    function FindClassDecl(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
    function IsLocal(ARoutine: TSyntaxNode; const AName: string): Boolean;
    function Used(const AName: string): Boolean;
    function FirstName(AFirst, ALast: Integer): string;
    function FieldEdit(ADecl: TSyntaxNode; const AField: string; out AEdit: TTextEdit): Boolean;
    function FinalizationEdit(const AStatement: string; out AEdit: TTextEdit): Boolean;
    function FixFor(const ACall: TNotifierCall; const ATarget: string; out AFix: TRuleFix): Boolean;
    function ReceiverText(const ACall: TNotifierCall; out AReceiver: string): Boolean;
    function MethodFix(const ACall: TNotifierCall; const AReceiver, ATarget: string; out AFix: TRuleFix): Boolean;
    function MethodTarget(const ACall: TNotifierCall; const ADecl: TSyntaxNode; const ATarget: string;
      out AName: string; out AEdits: TArray<TTextEdit>): Boolean;
    function UnitFix(const ACall: TNotifierCall; const AReceiver, ATarget: string; out AFix: TRuleFix): Boolean;
    function UnitStatement(const ACall: TNotifierCall; const AReceiver, ATarget: string; out AStatement: string;
      out AEdits: TArray<TTextEdit>): Boolean;
    procedure CheckCall(APosition: Integer; const APair: TRegisterPair);
    function CallRange(const ACall: TNotifierCall): TTextRange;
    procedure ReportUnsaved(const ACall: TNotifierCall);
    procedure CheckAssigned(const ACall: TNotifierCall; const AAssign: Integer);
    procedure CheckPairs(const APosition: Integer);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TOtaNotifierScan }

constructor TOtaNotifierScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

function TOtaNotifierScan.Token(APosition: Integer): TPascalToken;
begin
  Result := FTokens[FCode[APosition]];
end;

function TOtaNotifierScan.IsWord(APosition: Integer): Boolean;
begin
  Result := (APosition >= 0) and (APosition <= High(FCode)) and
    (Token(APosition).Kind = TPascalTokenKind.Identifier);
end;

// Gegenstück der Klammer bei APosition; -1 ohne.
function TOtaNotifierScan.Matching(APosition: Integer): Integer;
var
  Depth, Step: Integer;
begin
  Step := 1;
  if Token(APosition).IsSymbol(')') or Token(APosition).IsSymbol(']') then
  begin
    Step := -1;
  end;
  Depth := 0;
  Result := APosition;
  while (Result >= 0) and (Result <= High(FCode)) do
  begin
    if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
    begin
      Inc(Depth, Step);
    end
    else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
    begin
      Dec(Depth, Step);
    end;
    if Depth = 0 then
    begin
      Exit;
    end;
    Inc(Result, Step);
  end;
  Result := -1;
end;

// Anfang des Ausdrucks vor dem Punkt bei ADot: Namen, Punkte, Aufrufe und Klammern.
function TOtaNotifierScan.ReceiverStart(ADot: Integer): Integer;
var
  Position: Integer;
begin
  Result := ADot;
  Position := ADot - 1;
  while Position >= 0 do
  begin
    if Token(Position).IsSymbol(')') or Token(Position).IsSymbol(']') then
    begin
      Position := Matching(Position);
      if Position < 0 then
      begin
        Exit(-1);
      end;
      Result := Position;
      Dec(Position);
    end
    else if IsWord(Position) then
    begin
      Result := Position;
      Dec(Position);
      if (Position >= 0) and Token(Position).IsSymbol('.') then
      begin
        Dec(Position);
      end
      else
      begin
        Break;
      end;
    end
    else
    begin
      Break;
    end;
  end;
end;

function TOtaNotifierScan.TextOf(AFirst, ALast: Integer): string;
begin
  Result := Copy(FContext.Text, Token(AFirst).Offset + 1,
    Token(ALast).Offset + Length(Token(ALast).Text) - Token(AFirst).Offset);
end;

// Ohne Leerraum und ohne führendes Self., zum Vergleich von Variablen.
function TOtaNotifierScan.Normalized(const AText: string): string;
begin
  Result := LowerCase(StringReplace(StringReplace(StringReplace(AText, ' ', '', [rfReplaceAll]), #10, '',
    [rfReplaceAll]), #13, '', [rfReplaceAll]));
  if StartsStr('self.', Result) then
  begin
    Result := Copy(Result, 6, MaxInt);
  end;
end;

// Gibt die Unit ATarget an AClose weiter: AClose(ATarget) bzw. X.AClose(ATarget)? Es zählen auch der letzte
// Teil (Notifier.FIndex → FIndex, im Notifier selbst abgemeldet) und Kopien (Index := FIndex).
function TOtaNotifierScan.Removed(const AClose, ATarget: string): Boolean;
var
  mPosition: Integer;
  mNames: TArray<string>;
begin
  mNames := AliasNames(ATarget);
  for mPosition := 0 to High(FCode) - 1 do
  begin
    if IsWord(mPosition) and SameText(Token(mPosition).Text, AClose) and Token(mPosition + 1).IsSymbol('(') and
      PassesName(mPosition + 1, mNames) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TOtaNotifierScan.AliasNames(const ATarget: string): TArray<string>;
var
  mPosition, mStop, mDot: Integer;
begin
  Result := [ATarget];
  mDot := LastDelimiter('.', ATarget);
  if mDot > 0 then
  begin
    Result := Result + [Copy(ATarget, mDot + 1, MaxInt)];
  end;
  for mPosition := 1 to High(FCode) - 2 do
  begin
    if IsWord(mPosition - 1) and Token(mPosition).IsSymbol(':=') then
    begin
      mStop := mPosition + 1;
      while (mStop <= High(FCode)) and not Token(mStop).IsSymbol(';') and not Token(mStop).IsKeyword('end') do
      begin
        Inc(mStop);
      end;
      if MatchText(Normalized(TextOf(mPosition + 1, mStop - 1)), Result) then
      begin
        Result := Result + [LowerCase(Token(mPosition - 1).Text)];
      end;
    end;
  end;
end;

function TOtaNotifierScan.PassesName(const AOpen: Integer; const ANames: TArray<string>): Boolean;
var
  mClose, mStop: Integer;
begin
  mClose := Matching(AOpen);
  if (mClose > AOpen + 1) and MatchText(Normalized(TextOf(AOpen + 1, mClose - 1)), ANames) then
  begin
    Exit(True);
  end;
  // Verschobener Index: RemoveNotifier(FIndex - 1), wenn AddNotifier(…) + 1 gespeichert wurde.
  for mStop := AOpen + 1 to mClose - 1 do
  begin
    if IsWord(mStop) and MatchText(Token(mStop).Text, ANames) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

// Innerste Routine um AOffset; nil außerhalb. Iterativ (Bericht M1): Suche in Vorordnung über die Knoten um
// AOffset; jede gefundene Routine ersetzt das Ergebnis, und die Suche geht nur in ihr weiter.
function TOtaNotifierScan.RoutineAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
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
      begin
        Continue;
      end;
      if Node.Kind = TSyntaxKind.RoutineDecl then
      begin
        Result := Node;
        Pending.Clear;
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

// Äußerste Routine um AOffset; nil außerhalb. Iterativ (Bericht M1).
function TOtaNotifierScan.OuterRoutineAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
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
      begin
        Continue;
      end;
      if Node.Kind = TSyntaxKind.RoutineDecl then
      begin
        Exit(Node);
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

// Edits nach Position, wie der Editor sie anwendet.
function TOtaNotifierScan.Sorted(const AEdits: TArray<TTextEdit>): TArray<TTextEdit>;
var
  Index, Other: Integer;
  Swap: TTextEdit;
begin
  Result := Copy(AEdits);
  for Index := 0 to High(Result) - 1 do
  begin
    for Other := Index + 1 to High(Result) do
    begin
      if (Result[Other].Range.StartPos.Line < Result[Index].Range.StartPos.Line) or
        ((Result[Other].Range.StartPos.Line = Result[Index].Range.StartPos.Line) and
        (Result[Other].Range.StartPos.Character < Result[Index].Range.StartPos.Character)) then
      begin
        Swap := Result[Index];
        Result[Index] := Result[Other];
        Result[Other] := Swap;
      end;
    end;
  end;
end;

// Iterativ (Bericht M1).
function TOtaNotifierScan.FindClassDecl(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
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
      begin
        Exit(Node);
      end;
      if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.RoutineDecl] then
      begin
        Continue;
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

// Ist AName in ARoutine vor deren Rumpf deklariert (Parameter, lokale Variable)?
function TOtaNotifierScan.IsLocal(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  Block: TSyntaxNode;
  Position: Integer;
begin
  Result := False;
  Block := ARoutine.FindChild(TSyntaxKind.Block);
  if Block = nil then
  begin
    Exit;
  end;
  for Position := 0 to High(FCode) do
  begin
    if (Token(Position).Offset >= ARoutine.StartOffset) and (Token(Position).Offset < Block.StartOffset) and
      IsWord(Position) and SameText(Token(Position).Text, AName) then
    begin
      Exit(True);
    end;
  end;
end;

// Kommt AName als Bezeichner in der Unit vor?
function TOtaNotifierScan.Used(const AName: string): Boolean;
var
  Position: Integer;
begin
  for Position := 0 to High(FCode) do
  begin
    if IsWord(Position) and SameText(Token(Position).Text, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

// Erster Bezeichner von AFirst..ALast ohne Self; '' ohne.
function TOtaNotifierScan.FirstName(AFirst, ALast: Integer): string;
var
  Position: Integer;
begin
  Result := '';
  for Position := AFirst to ALast do
  begin
    if IsWord(Position) and not SameText(Token(Position).Text, 'Self') then
    begin
      Exit(Token(Position).Text);
    end;
  end;
end;

// "FName: Integer;" in den ersten private-Abschnitt, sonst als neuer Abschnitt vor das "end" der Klasse.
function TOtaNotifierScan.FieldEdit(ADecl: TSyntaxNode; const AField: string; out AEdit: TTextEdit): Boolean;
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
      (Child.StartPos.Line <= High(FLines)) then
    begin
      Line := Child.EndPos.Line;
      Indent := TTextLines.IndentOf(FLines[Child.StartPos.Line]) + '  ';
      AEdit := TTextEdit.Create(TTextRange.Create(TTextPosition.Create(Line, Length(FLines[Line])),
        TTextPosition.Create(Line, Length(FLines[Line]))), FLineBreak + Indent + AField + ': Integer;');
      Exit(True);
    end;
  end;
  Line := ClassNode.EndPos.Line;
  if (Line > High(FLines)) or (Trim(Copy(FLines[Line], 1, ClassNode.EndPos.Character - 3)) <> '') then
  begin
    Exit;
  end;
  Indent := TTextLines.IndentOf(FLines[Line]);
  AEdit := TTextEdit.Create(TTextRange.Create(Line, 0, Line, 0), Indent + 'private' + FLineBreak + Indent + '  ' +
    AField + ': Integer;' + FLineBreak);
  Result := True;
end;

// Abmeldung in finalization: hinter "finalization", sonst als neuer Abschnitt vor "end."; ohne
// initialization kommt ein leerer Abschnitt davor (finalization verlangt ihn).
function TOtaNotifierScan.FinalizationEdit(const AStatement: string; out AEdit: TTextEdit): Boolean;
var
  Position, Line: Integer;
  Head: string;
begin
  Result := False;
  Head := 'initialization' + FLineBreak + FLineBreak;
  for Position := 0 to High(FCode) do
  begin
    if Token(Position).IsKeyword('initialization') then
    begin
      Head := '';
    end;
  end;
  for Position := 0 to High(FCode) do
  begin
    if Token(Position).IsKeyword('finalization') then
    begin
      Line := Token(Position).EndPos.Line;
      AEdit := TTextEdit.Create(TTextRange.Create(TTextPosition.Create(Line, Length(FLines[Line])),
        TTextPosition.Create(Line, Length(FLines[Line]))), FLineBreak + AStatement);
      Exit(True);
    end;
  end;
  // "end." am Ende der Unit, allein in seiner Zeile.
  Position := High(FCode);
  if (Position < 1) or not Token(Position).IsSymbol('.') or not Token(Position - 1).IsKeyword('end') then
  begin
    Exit;
  end;
  Line := Token(Position - 1).StartPos.Line;
  if Trim(Copy(FLines[Line], 1, Token(Position - 1).StartPos.Character)) <> '' then
  begin
    Exit;
  end;
  AEdit := TTextEdit.Create(TTextRange.Create(Line, 0, Line, 0), Head + 'finalization' + FLineBreak + AStatement +
    FLineBreak + FLineBreak);
  Result := True;
end;

// Korrektur für einen Aufruf ohne Zuweisung (AStart: Anfang der Anweisung) bzw. eine Zuweisung an ATarget
// ('' = keine Zuweisung).
function TOtaNotifierScan.FixFor(const ACall: TNotifierCall; const ATarget: string; out AFix: TRuleFix): Boolean;
var
  mReceiver: string;
begin
  Result := (ACall.Routine <> nil) and ReceiverText(ACall, mReceiver);
  if not Result then
  begin
    Exit;
  end;
  if LastDelimiter('.', ACall.Routine.Name) > 0 then
  begin
    Result := MethodFix(ACall, mReceiver, ATarget, AFix);
  end
  else
  begin
    Result := UnitFix(ACall, mReceiver, ATarget, AFix);
  end;
end;

function TOtaNotifierScan.ReceiverText(const ACall: TNotifierCall; out AReceiver: string): Boolean;
var
  mName: string;
begin
  AReceiver := '';
  if ACall.ReceiverFirst < 0 then
  begin
    Exit(True);
  end;
  // Lokale Empfänger gibt es im Destruktor bzw. in finalization nicht.
  mName := FirstName(ACall.ReceiverFirst, ACall.ReceiverLast);
  Result := (mName = '') or not IsLocal(ACall.Routine, mName);
  AReceiver := TextOf(ACall.ReceiverFirst, ACall.ReceiverLast) + '.';
end;

// Methode: Feld und Destruktor.
function TOtaNotifierScan.MethodFix(const ACall: TNotifierCall; const AReceiver, ATarget: string;
  out AFix: TRuleFix): Boolean;
var
  mName, mClassName: string;
  mDot: Integer;
  mDecl: TSyntaxNode;
  mEdits, mDestroying: TArray<TTextEdit>;
begin
  mDot := LastDelimiter('.', ACall.Routine.Name);
  mClassName := Copy(ACall.Routine.Name, 1, mDot - 1);
  mDecl := nil;
  if not SameText(Copy(ACall.Routine.Name, mDot + 1, MaxInt), 'Destroy') then
  begin
    mDecl := FindClassDecl(FContext.Tree.Root, mClassName);
  end;
  Result := (mDecl <> nil) and MethodTarget(ACall, mDecl, ATarget, mName, mEdits) and
    TFreeFields.DestructorEdits(FContext.Tree, FContext.Text, mClassName, mDecl.StartPos.Line,
    [AReceiver + ACall.Pair.Close + '(' + mName + ');'], mDestroying);
  if not Result then
  begin
    Exit;
  end;
  if ATarget = '' then
  begin
    AFix := TRuleFix.Create(Format('Index in ein Feld legen und %s im Destruktor ergänzen', [ACall.Pair.Close]),
      Sorted(mEdits + mDestroying));
  end
  else
  begin
    AFix := TRuleFix.Create(Format('%s im Destruktor ergänzen', [ACall.Pair.Close]), Sorted(mEdits + mDestroying));
  end;
end;

// Feld für den Index: ATarget, sonst ein neues Feld F<Name>Index samt Zuweisung vor dem Aufruf.
function TOtaNotifierScan.MethodTarget(const ACall: TNotifierCall; const ADecl: TSyntaxNode; const ATarget: string;
  out AName: string; out AEdits: TArray<TTextEdit>): Boolean;
var
  mEdit: TTextEdit;
begin
  AEdits := nil;
  AName := ATarget;
  if AName <> '' then
  begin
    Exit(not IsLocal(ACall.Routine, Normalized(ATarget)));
  end;
  AName := 'F' + TOtaNotifierNotRemovedRule.IndexName(ACall.Pair.Open);
  Result := not Used(AName) and FieldEdit(ADecl, AName, mEdit);
  if Result then
  begin
    AEdits := [mEdit, TTextEdit.Create(TTextRange.Create(Token(ACall.Start).StartPos, Token(ACall.Start).StartPos),
      AName + ' := ')];
  end;
end;

// Prozedur der Unit: globale Variable und finalization; nur in Units und nicht in verschachtelten Routinen.
function TOtaNotifierScan.UnitFix(const ACall: TNotifierCall; const AReceiver, ATarget: string;
  out AFix: TRuleFix): Boolean;
var
  mStatement: string;
  mEdits: TArray<TTextEdit>;
  mEdit: TTextEdit;
begin
  Result := (Length(FCode) > 0) and Token(0).IsKeyword('unit') and
    (OuterRoutineAt(FContext.Tree.Root, ACall.Routine.StartOffset) = ACall.Routine) and
    UnitStatement(ACall, AReceiver, ATarget, mStatement, mEdits) and FinalizationEdit(mStatement, mEdit);
  if not Result then
  begin
    Exit;
  end;
  // Die finalization steht hinter der Routine.
  mEdits := mEdits + [mEdit];
  if ATarget = '' then
  begin
    AFix := TRuleFix.Create(Format('Index merken und %s in finalization ergänzen', [ACall.Pair.Close]), mEdits);
  end
  else
  begin
    AFix := TRuleFix.Create(Format('%s in finalization ergänzen', [ACall.Pair.Close]), mEdits);
  end;
end;

// Abmeldung für finalization; ohne ATarget samt globaler Variable und Zuweisung vor dem Aufruf.
function TOtaNotifierScan.UnitStatement(const ACall: TNotifierCall; const AReceiver, ATarget: string;
  out AStatement: string; out AEdits: TArray<TTextEdit>): Boolean;
const
  cIndent = '  ';
var
  mName: string;
begin
  AEdits := nil;
  if ATarget <> '' then
  begin
    AStatement := cIndent + AReceiver + ACall.Pair.Close + '(' + ATarget + ');';
    Exit(not IsLocal(ACall.Routine, ATarget));
  end;
  mName := TOtaNotifierNotRemovedRule.IndexName(ACall.Pair.Open);
  AEdits := [TTextEdit.Create(TTextRange.Create(ACall.Routine.StartPos.Line, 0, ACall.Routine.StartPos.Line, 0),
    'var' + FLineBreak + cIndent + mName + ': Integer = -1;' + FLineBreak + FLineBreak),
    TTextEdit.Create(TTextRange.Create(Token(ACall.Start).StartPos, Token(ACall.Start).StartPos), mName + ' := ')];
  AStatement := cIndent + 'if ' + mName + ' >= 0 then' + FLineBreak + cIndent + '  ' + AReceiver +
    ACall.Pair.Close + '(' + mName + ');';
  Result := not Used(mName);
end;

procedure TOtaNotifierScan.CheckCall(APosition: Integer; const APair: TRegisterPair);
var
  mCall: TNotifierCall;
  mBefore: Integer;
begin
  mCall.Pair := APair;
  mCall.Position := APosition;
  mCall.ReceiverFirst := -1;
  mCall.ReceiverLast := -1;
  mCall.Start := APosition;
  if (APosition > 0) and Token(APosition - 1).IsSymbol('.') then
  begin
    mCall.ReceiverFirst := ReceiverStart(APosition - 1);
    mCall.ReceiverLast := APosition - 2;
    mCall.Start := mCall.ReceiverFirst;
  end;
  mCall.Routine := RoutineAt(FContext.Tree.Root, Token(APosition).Offset);
  // Register…-Aufrufe in Register: die IDE entfernt diese Wizards beim Entladen selbst.
  if (mCall.Start < 0) or StartsText('Register', APair.Open) and (mCall.Routine <> nil) and
    SameText(mCall.Routine.Name, 'Register') then
  begin
    Exit;
  end;
  mBefore := mCall.Start - 1;
  if (mBefore < 0) or MatchText(Token(mBefore).Text, StatementStarts) then
  begin
    ReportUnsaved(mCall);
  end
  else if Token(mBefore).IsSymbol(':=') then
  begin
    CheckAssigned(mCall, mBefore);
  end;
end;

function TOtaNotifierScan.CallRange(const ACall: TNotifierCall): TTextRange;
begin
  Result := TTextRange.Create(Token(ACall.Position).StartPos, Token(ACall.Position).EndPos);
end;

procedure TOtaNotifierScan.ReportUnsaved(const ACall: TNotifierCall);
var
  mFix: TRuleFix;
  mFixes: TArray<TRuleFix>;
begin
  mFixes := nil;
  if FixFor(ACall, '', mFix) then
  begin
    mFixes := [mFix];
  end;
  FReport.Add(CallRange(ACall), Format('Der Index von %s wird nicht gemerkt; ohne %s ruft die IDE nach dem ' +
    'Entladen ins Leere.', [ACall.Pair.Open, ACall.Pair.Close]), TRuleConfidence.Medium, mFixes);
end;

procedure TOtaNotifierScan.CheckAssigned(const ACall: TNotifierCall; const AAssign: Integer);
var
  mStart: Integer;
  mTarget: string;
  mFix: TRuleFix;
  mFixes: TArray<TRuleFix>;
  mCall: TNotifierCall;
begin
  // Ziel der Zuweisung: Namen und Punkte bis zum Anfang der Anweisung.
  mStart := AAssign - 1;
  while (mStart > 0) and (IsWord(mStart - 1) or Token(mStart - 1).IsSymbol('.')) do
  begin
    Dec(mStart);
  end;
  if (mStart < 0) or not IsWord(mStart) then
  begin
    Exit;
  end;
  mTarget := TextOf(mStart, AAssign - 1);
  if Removed(ACall.Pair.Close, Normalized(mTarget)) then
  begin
    Exit;
  end;
  mCall := ACall;
  mCall.Start := mStart;
  mFixes := nil;
  if FixFor(mCall, mTarget, mFix) then
  begin
    mFixes := [mFix];
  end;
  FReport.Add(CallRange(ACall), Format('Der Index %s von %s geht nie an %s; die IDE ruft nach dem Entladen ins ' +
    'Leere.', [mTarget, ACall.Pair.Open, ACall.Pair.Close]), TRuleConfidence.Medium, mFixes);
end;

procedure TOtaNotifierScan.Run;
var
  mIndex: Integer;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FTokens := FContext.Tree.Tokens;
  FCode := nil;
  for mIndex := 0 to High(FTokens) do
  begin
    if not (FTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      FCode := FCode + [mIndex];
    end;
  end;
  FLines := TTextLines.SplitLines(FContext.Text, FLineBreak);
  FRegisterPairs := TOtaNotifierNotRemovedRule.Pairs(FContext.Options);
  for mIndex := 0 to High(FCode) - 1 do
  begin
    if IsWord(mIndex) and Token(mIndex + 1).IsSymbol('(') then
    begin
      CheckPairs(mIndex);
    end;
  end;
end;

procedure TOtaNotifierScan.CheckPairs(const APosition: Integer);
var
  mPair: TRegisterPair;
begin
  for mPair in FRegisterPairs do
  begin
    if SameText(Token(APosition).Text, mPair.Open) then
    begin
      CheckCall(APosition, mPair);
    end;
  end;
end;

{ TOtaNotifierNotRemovedRule }

procedure TOtaNotifierNotRemovedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mWorker: TOtaNotifierScan;
begin
  mWorker := TOtaNotifierScan.Create(AContext, AReport);
  try
    mWorker.Run;
  finally
    mWorker.Free;
  end;
end;

procedure RegisterOpenToolsRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOtaNotifierNotRemovedRule.Create);
end;

end.
