unit Atlas.Common.Rules.Builtin.DelphiSemantics;

// Stellen, an denen Delphi zur Laufzeit anders arbeitet als Free Pascal (#2309, B6). Beide übersetzen den Code, die
// Tests unter FPC sind grün, erst unter Delphi stimmt das Ergebnis nicht:
//   managed-result-read-before-set  Result vom Typ dynamisches Array oder String wird gelesen, bevor die Funktion
//                                   es setzt. Delphi übergibt Result als Variable des Aufrufers (A := F(...)):
//                                   SetLength(Result, N) behält dann dessen alte Werte, Result := Result + ...
//                                   hängt an dessen Inhalt an.
//   trygetvalue-out-default         TryGetValue als Anweisung (Ergebnis verworfen), dessen out-Argument vorher
//                                   einen Wert bekam, der nicht der Vorgabe entspricht. Delphis TryGetValue setzt
//                                   den out-Wert auch ohne Schlüssel (auf 0, '', False, nil), die Vorbelegung ist
//                                   verloren; FPC lässt sie stehen.
//   record-array-shared             B := A kopiert einen Record, danach wird ein Element eines dynamischen Arrays
//                                   der Kopie (oder des Originals) in place geschrieben. Dynamische Arrays sind
//                                   Referenzen ohne Copy-on-Write: Die Änderung trifft beide Records.
//   extractfile-forward-slash       ExtractFileName, ExtractFilePath, ExtractFileDir, ExtractFileExt bzw.
//                                   ExtractFileDrive auf einem Text mit '/' (Literal, Verkettung, StringReplace
//                                   bzw. Replace nach '/' oder eine lokale Variable, der die Routine so etwas
//                                   zuweist). Unter Windows trennen sie nur an '\'.
//   hash-overflow-checked           Multiplikation mit einer FNV-Primzahl (16777619, 1099511628211), die überläuft,
//                                   an einer Stelle mit Überlaufprüfung (kein {$Q-}/{$OVERFLOWCHECKS OFF} davor). Im
//                                   Debug-Build bricht der gewollte Überlauf mit EIntOverflow ab; typisch ist eine
//                                   {$Q-}-Klammer um die falsche Routine. Ein 32-Bit-Produkt mit UInt64(...) bzw.
//                                   Int64(...) läuft nicht über und bleibt still.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cManagedResultReadRuleId = 'managed-result-read-before-set';
  cTryGetValueOutDefaultRuleId = 'trygetvalue-out-default';
  cRecordArraySharedRuleId = 'record-array-shared';
  cExtractFileSlashRuleId = 'extractfile-forward-slash';
  cHashOverflowCheckedRuleId = 'hash-overflow-checked';

type
  TManagedResultReadRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TTryGetValueOutDefaultRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TRecordArraySharedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TExtractFileSlashRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  THashOverflowCheckedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Meldet die fünf Regeln in ARegistry an.</summary>
procedure RegisterDelphiSemanticsRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.ExpressionTypes,
  Atlas.Common.Semantics.ExpressionTypes.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Rules.Builtin.CompilerTraps,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TSemanticsText = (ResultTitle, ResultSized, ResultRead, ResultFix, TryTitle, TryMessage, SharedTitle,
    SharedMessage, SharedFix, SlashTitle, SlashMessage, SlashFix, OverflowTitle, OverflowMessage);

  /// <summary>Stand von Result beim Durchgehen des Rumpfs.</summary>
  TResultState = (Unset, Sized, Done);

  TNodeKinds = set of TSyntaxKind;

const
  cTexts: array[TSemanticsText] of TAtlasText = (
    (De: 'Result gelesen, bevor es gesetzt ist'; En: 'Result read before it is set'),
    (De: 'SetLength(Result, ...) ohne vorheriges Result := %s: Delphi übergibt Result als Variable des Aufrufers, ' +
      'SetLength behält deren alte Werte, und %s liest sie (FPC beginnt leer). Erst Result := %0:s.';
     En: 'SetLength(Result, ...) without Result := %s before: Delphi passes Result as the caller''s variable, ' +
      'SetLength keeps its old values and %s reads them (FPC starts empty). Assign Result := %0:s first.'),
    (De: '%s liest Result, bevor die Funktion es setzt: Delphi übergibt Result als Variable des Aufrufers, der ' +
      'Wert stammt von dort (FPC beginnt leer). Erst Result := %s.';
     En: '%s reads Result before the function sets it: Delphi passes Result as the caller''s variable, the value ' +
      'comes from there (FPC starts empty). Assign Result := %s first.'),
    (De: 'Result := %s davor einfügen'; En: 'Insert Result := %s before'),
    (De: 'TryGetValue überschreibt die Vorbelegung'; En: 'TryGetValue overwrites the preset value'),
    (De: '%s bekam in Zeile %d den Wert %s, TryGetValue verwirft das Ergebnis: Delphi setzt das out-Argument auch ' +
      'ohne Schlüssel auf den Vorgabewert, die Vorbelegung geht verloren (FPC lässt sie stehen). In eine eigene ' +
      'Variable lesen und nur bei True übernehmen.';
     En: '%0:s got the value %2:s in line %1:d, TryGetValue discards its result: Delphi sets the out argument to the ' +
      'default value even without the key, the preset is lost (FPC keeps it). Read into a variable of its own and ' +
      'take it over only on True.'),
    (De: 'Kopierter Record teilt sein Array'; En: 'Copied record shares its array'),
    (De: '%s ist seit Zeile %d (%s) dasselbe Array wie in %s: Dynamische Arrays sind in Delphi Referenzen ohne ' +
      'Copy-on-Write, das Schreiben ändert auch %3:s. Vorher %0:s := Copy(%0:s).';
     En: '%0:s has been the same array as in %3:s since line %1:d (%2:s): in Delphi dynamic arrays are references ' +
      'without copy-on-write, writing changes %3:s too. Assign %0:s := Copy(%0:s) first.'),
    (De: '%s := Copy(%0:s) davor einfügen'; En: 'Insert %s := Copy(%0:s) before'),
    (De: 'Dateiname mit / zerlegt'; En: 'File name with / split'),
    (De: '%s bekommt einen Pfad mit ''/'': Unter Windows trennt Delphi nur an ''\'' (PathDelim), unter Linux an ' +
      '''/''. Trenner vorher auf PathDelim angleichen.';
     En: '%s gets a path with ''/'': on Windows Delphi splits only at ''\'' (PathDelim), on Linux at ''/''. ' +
      'Convert the delimiters to PathDelim first.'),
    (De: 'Nach PathDelim ersetzen'; En: 'Replace with PathDelim'),
    (De: 'Gewollter Überlauf mit Überlaufprüfung'; En: 'Intended overflow with overflow checking'),
    (De: '%s läuft gewollt über (FNV-Hash), hier gilt aber die Überlaufprüfung: Im Debug-Build ({$Q+}) bricht ' +
      'das mit EIntOverflow ab. Die Routine in {$IFOPT Q+}{$DEFINE ...}{$Q-}{$ENDIF} … {$IFDEF ...}{$Q+}{$ENDIF} ' +
      'klammern.';
     En: '%s overflows on purpose (FNV hash), but overflow checking applies here: in a debug build ({$Q+}) it stops ' +
      'with EIntOverflow. Enclose the routine in {$IFOPT Q+}{$DEFINE ...}{$Q-}{$ENDIF} … ' +
      '{$IFDEF ...}{$Q+}{$ENDIF}.'));

{$SCOPEDENUMS OFF}

const
  cStringTypes: array[0..5] of string = ('string', 'UnicodeString', 'AnsiString', 'RawByteString', 'UTF8String',
    'WideString');
  // Eingebaute Routinen, deren Argument Result nur liest bzw. Länge liefert.
  cLengthRoutines: array[0..2] of string = ('Length', 'High', 'Low');
  cReadingRoutines: array[0..2] of string = ('Insert', 'Delete', 'Copy');
  cExtractRoutines: array[0..4] of string = ('ExtractFileName', 'ExtractFilePath', 'ExtractFileDir',
    'ExtractFileExt', 'ExtractFileDrive');
  cDefaultValues: array[0..5] of string = ('nil', '''''', '0', 'False', '0.0', '[]');
  cWideCasts: array[0..1] of string = ('UInt64', 'Int64');
  cFnvPrime32 = 16777619;
  cFnvPrime64 = 1099511628211;

{ Hilfen }

function IsName(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName);
end;

/// <summary>Text eines Knotens ohne Leerraum, zum Vergleich von Ausdrücken.</summary>
function Compact(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := LowerCase(StringReplace(StringReplace(Copy(AText, ANode.StartOffset + 1, ANode.EndOffset -
    ANode.StartOffset), ' ', '', [rfReplaceAll]), #9, '', [rfReplaceAll]));
end;

function SourceText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Trim(Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
end;

/// <summary>Knoten des Rumpfs in Baumreihenfolge, ohne anonyme Methoden und verschachtelte Routinen.</summary>
function BodyNodes(ARoutine: TSyntaxNode; AKinds: TNodeKinds): TArray<TSyntaxNode>;
var
  mBody: TSyntaxNode;
  mFound: TList<TSyntaxNode>;
begin
  Result := nil;
  mBody := ARoutine.FindChild(TSyntaxKind.Block);
  if mBody = nil then
  begin
    Exit;
  end;
  mFound := TList<TSyntaxNode>.Create;
  try
    mBody.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := not (ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl]);
        if Result and (ANode.Kind in AKinds) then
        begin
          mFound.Add(ANode);
        end;
      end);
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

/// <summary>Alle Routinen mit Rumpf in der Datei.</summary>
function Routines(const AContext: TRuleContext): TArray<TSyntaxNode>;
var
  mFound: TList<TSyntaxNode>;
begin
  Result := nil;
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mFound := TList<TSyntaxNode>.Create;
  try
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.Block) <> nil) then
        begin
          mFound.Add(ANode);
        end;
      end);
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

/// <summary>Zeilenumbruch der Datei und Einrückung der Zeile von ANode.</summary>
function LineStart(const AContext: TRuleContext; ANode: TSyntaxNode): string;
begin
  Result := StringOfChar(' ', ANode.StartPos.Character);
  if Pos(#13#10, AContext.Text) > 0 then
  begin
    Result := #13#10 + Result;
  end
  else
  begin
    Result := #10 + Result;
  end;
end;

/// <summary>Korrektur: AText als eigene Zeile vor die Anweisung AStatement setzen.</summary>
function InsertBefore(const AContext: TRuleContext; AStatement: TSyntaxNode; const ATitle, AText: string): TRuleFix;
begin
  Result := TRuleFix.Create(ATitle, [TTextEdit.Create(TTextRange.Create(AStatement.StartPos, AStatement.StartPos),
    AText + ';' + LineStart(AContext, AStatement))], False);
end;

/// <summary>Anweisung, die ANode enthält (Zuweisung oder Aufruf).</summary>
function StatementOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and not (Result.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.IfStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement, TSyntaxKind.CaseStatement]) do
  begin
    Result := Result.Parent;
  end;
end;

{ TManagedResultReadRule }

function TManagedResultReadRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cManagedResultReadRuleId, TRuleSeverity.Warning,
    cTexts[TSemanticsText.ResultTitle].Text);
end;

/// <summary>Leerer Wert des Ergebnistyps: nil für Arrays, '' für Strings; '' (leer) bei anderem Typ.</summary>
function EmptyResult(const AContext: TRuleContext; ARoutine: TSyntaxNode): string;
var
  mType: string;
begin
  Result := '';
  mType := ResultTypeText(AContext.Text, ARoutine);
  if mType = '' then
  begin
    Exit;
  end;
  if MatchText(WithoutUnit(mType), cStringTypes) then
  begin
    Result := '''''';
  end
  else if IsDynamicArrayType(AContext, mType) then
  begin
    Result := 'nil';
  end;
end;

/// <summary>Enthält ANode einen Bezeichner Result (ohne anonyme Methoden)?</summary>
function MentionsResult(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Search(
    function(AChild: TSyntaxNode): TSyntaxSearchStep
    begin
      if AChild.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      if IsName(AChild, 'Result') then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

/// <summary>Aufruf, dessen Argument ANode ist; nil sonst. ACallee ist dann sein Name.</summary>
function ArgumentOf(ANode: TSyntaxNode; out ACallee: string): TSyntaxNode;
begin
  ACallee := '';
  Result := ANode.Parent;
  if (Result = nil) or (Result.Kind <> TSyntaxKind.Call) or (Result[0] = ANode) then
  begin
    Exit(nil);
  end;
  if Result[0].Kind = TSyntaxKind.Identifier then
  begin
    ACallee := Result[0].Name;
  end;
end;

/// <summary>Ziel bzw. Argument, zu dem das Element ANode (Result[...]) gehört: über Felder und weitere Indizes
/// nach oben (Result[I].Marks[3]).</summary>
function ElementOuter(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Parent <> nil) and (Result.Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) and
    (Result.Parent[0] = Result) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Steht die Anweisung AStatement ohne Bedingung im Rumpf (höchstens in for-Schleifen und Blöcken)?
/// </summary>
function Unconditional(AStatement: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := AStatement.Parent;
  while (mNode <> nil) and (mNode.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    if not (mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
      TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock, TSyntaxKind.WithStatement]) then
    begin
      Exit(False);
    end;
    mNode := mNode.Parent;
  end;
  Result := True;
end;

type
  /// <summary>Durchgang über die Vorkommen von Result in einer Funktion.</summary>
  TResultScan = record
    State: TResultState;
    Sized: TSyntaxNode;
    Reader: TSyntaxNode;
    /// <summary>Wertet das nächste Vorkommen AResult aus; False = fertig.</summary>
    function Step(AResult: TSyntaxNode): Boolean;
    function StepCall(AResult, ACall: TSyntaxNode; const ACallee: string): Boolean;
    function StepElement(AElement: TSyntaxNode): Boolean;
    /// <summary>Liest ANode Result: ohne Wert des Aufrufers fertig, sonst merken.</summary>
    function Read(ANode: TSyntaxNode): Boolean;
  end;

function TResultScan.Read(ANode: TSyntaxNode): Boolean;
begin
  Reader := ANode;
  Result := False;
end;

function TResultScan.StepCall(AResult, ACall: TSyntaxNode; const ACallee: string): Boolean;
begin
  Result := True;
  if SameText(ACallee, 'SetLength') and (ACall[1] = AResult) then
  begin
    // SetLength(Result, Length(Result) + 1) hängt an den Wert des Aufrufers an.
    if (State = TResultState.Unset) and (ACall.ChildCount > 2) and MentionsResult(ACall[2]) then
    begin
      Exit(Read(ACall));
    end;
    Sized := ACall;
    State := TResultState.Sized;
    Exit;
  end;
  if MatchText(ACallee, cLengthRoutines) then
  begin
    if State = TResultState.Unset then
    begin
      Result := Read(ACall);
    end;
    Exit;
  end;
  if MatchText(ACallee, cReadingRoutines) then
  begin
    Exit(Read(ACall));
  end;
  // Andere Routinen: Result kann ein var- oder out-Argument sein, das sie setzen; keine Aussage.
  Result := False;
end;

function TResultScan.StepElement(AElement: TSyntaxNode): Boolean;
var
  mOuter, mStatement: TSyntaxNode;
  mCallee: string;
begin
  mOuter := ElementOuter(AElement);
  mStatement := mOuter.Parent;
  if (mStatement.Kind = TSyntaxKind.AssignStatement) and (mStatement[0] = mOuter) then
  begin
    // Ein Element ohne Bedingung geschrieben: Die Routine füllt das Array selbst.
    if Unconditional(mStatement) then
    begin
      State := TResultState.Done;
      Exit(False);
    end;
    Exit(True);
  end;
  if ArgumentOf(mOuter, mCallee) <> nil then
  begin
    // Inc(Result[I]) liest; Move, FillChar und andere schreiben bzw. sind unbekannt.
    if MatchText(mCallee, ['Inc', 'Dec']) then
    begin
      Exit(Read(mOuter.Parent));
    end;
    Exit(False);
  end;
  Result := Read(AElement);
end;

function TResultScan.Step(AResult: TSyntaxNode): Boolean;
var
  mParent, mCall: TSyntaxNode;
  mCallee: string;
begin
  mParent := AResult.Parent;
  if (mParent.Kind = TSyntaxKind.AssignStatement) and (mParent[0] = AResult) then
  begin
    if (State = TResultState.Unset) and MentionsResult(mParent[1]) then
    begin
      Reader := mParent;
    end;
    State := TResultState.Done;
    Exit(False);
  end;
  mCall := ArgumentOf(AResult, mCallee);
  if mCall <> nil then
  begin
    Exit(StepCall(AResult, mCall, mCallee));
  end;
  if (mParent.Kind = TSyntaxKind.IndexAccess) and (mParent[0] = AResult) then
  begin
    Exit(StepElement(mParent));
  end;
  Result := False;
  if (State = TResultState.Unset) and (mParent.Kind in [TSyntaxKind.BinaryExpr, TSyntaxKind.ForInStatement,
    TSyntaxKind.MemberAccess]) then
  begin
    Reader := mParent;
  end;
end;

procedure TManagedResultReadRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mRoutine, mResult, mStatement: TSyntaxNode;
  mEmpty, mReader: string;
  mScan: TResultScan;
begin
  if not ContainsText(AContext.Text, 'Result') then
  begin
    Exit;
  end;
  for mRoutine in Routines(AContext) do
  begin
    mEmpty := EmptyResult(AContext, mRoutine);
    if mEmpty = '' then
    begin
      Continue;
    end;
    mScan := Default(TResultScan);
    for mResult in BodyNodes(mRoutine, [TSyntaxKind.Identifier]) do
    begin
      if IsName(mResult, 'Result') and not mScan.Step(mResult) then
      begin
        Break;
      end;
    end;
    if mScan.Reader = nil then
    begin
      Continue;
    end;
    mReader := SourceText(AContext.Text, mScan.Reader);
    if mScan.Sized <> nil then
    begin
      mStatement := StatementOf(mScan.Sized);
      AReport.Add(TTextRange.Create(mScan.Sized.StartPos, mScan.Sized.EndPos), cTexts[TSemanticsText.ResultSized].Fmt(
        [mEmpty, mReader]), TRuleConfidence.Medium, [InsertBefore(AContext, mStatement,
        cTexts[TSemanticsText.ResultFix].Fmt([mEmpty]), 'Result := ' + mEmpty)]);
    end
    else
    begin
      mStatement := StatementOf(mScan.Reader);
      AReport.Add(TTextRange.Create(mScan.Reader.StartPos, mScan.Reader.EndPos), cTexts[TSemanticsText.ResultRead].Fmt(
        [mReader, mEmpty]), TRuleConfidence.Medium, [InsertBefore(AContext, mStatement,
        cTexts[TSemanticsText.ResultFix].Fmt([mEmpty]), 'Result := ' + mEmpty)]);
    end;
  end;
end;

{ TTryGetValueOutDefaultRule }

function TTryGetValueOutDefaultRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cTryGetValueOutDefaultRuleId, TRuleSeverity.Warning,
    cTexts[TSemanticsText.TryTitle].Text);
end;

/// <summary>Der Aufruf von TryGetValue (auch TryGetValue&lt;T&gt;) in der Anweisung AStatement; nil sonst.</summary>
function DiscardedTryGetValue(AStatement: TSyntaxNode): TSyntaxNode;
var
  mCallee: TSyntaxNode;
begin
  Result := nil;
  if (AStatement.ChildCount <> 1) or (AStatement[0].Kind <> TSyntaxKind.Call) then
  begin
    Exit;
  end;
  mCallee := AStatement[0][0];
  if (mCallee.Kind = TSyntaxKind.MemberAccess) and SameText(mCallee.Name, 'TryGetValue') and
    (AStatement[0].ChildCount >= 3) then
  begin
    Result := AStatement[0];
  end;
end;

/// <summary>Ist AValue ein Vorgabewert (nil, '', 0, False, Default(T), [])?</summary>
function IsDefaultValue(const AText: string; AValue: TSyntaxNode): Boolean;
var
  mText: string;
begin
  mText := SourceText(AText, AValue);
  Result := MatchText(mText, cDefaultValues) or ((AValue.Kind = TSyntaxKind.Call) and IsName(AValue[0],
    'Default'));
end;

/// <summary>Letzte Zuweisung an ein Ziel mit dem Text ATarget vor ABefore; nil ohne.</summary>
function LastAssignment(const AText: string; const AAssignments: TArray<TSyntaxNode>; const ATarget: string;
  ABefore: TSyntaxNode): TSyntaxNode;
var
  mAssign: TSyntaxNode;
begin
  Result := nil;
  for mAssign in AAssignments do
  begin
    if mAssign.StartOffset >= ABefore.StartOffset then
    begin
      Break;
    end;
    if Compact(AText, mAssign[0]) = ATarget then
    begin
      Result := mAssign;
    end;
  end;
end;

procedure TTryGetValueOutDefaultRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mRoutine, mStatement, mCall, mOut, mPreset: TSyntaxNode;
  mAssignments: TArray<TSyntaxNode>;
begin
  if not ContainsText(AContext.Text, 'TryGetValue') then
  begin
    Exit;
  end;
  for mRoutine in Routines(AContext) do
  begin
    mAssignments := BodyNodes(mRoutine, [TSyntaxKind.AssignStatement]);
    for mStatement in BodyNodes(mRoutine, [TSyntaxKind.CallStatement]) do
    begin
      mCall := DiscardedTryGetValue(mStatement);
      if mCall = nil then
      begin
        Continue;
      end;
      mOut := mCall[mCall.ChildCount - 1];
      mPreset := LastAssignment(AContext.Text, mAssignments, Compact(AContext.Text, mOut), mStatement);
      if (mPreset <> nil) and not IsDefaultValue(AContext.Text, mPreset[1]) then
      begin
        AReport.Add(TTextRange.Create(mCall.StartPos, mCall.EndPos), cTexts[TSemanticsText.TryMessage].Fmt(
          [SourceText(AContext.Text, mOut), mPreset.StartPos.Line + 1, SourceText(AContext.Text, mPreset[1])]),
          TRuleConfidence.Medium);
      end;
    end;
  end;
end;

{ TRecordArraySharedRule }

function TRecordArraySharedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cRecordArraySharedRuleId, TRuleSeverity.Warning,
    cTexts[TSemanticsText.SharedTitle].Text);
end;

/// <summary>Ist ANode eine Kette aus Namen, Feldern und Indizes ohne Aufruf (A, A.B, A[I].B)?</summary>
function IsPlainChain(ANode: TSyntaxNode): Boolean;
begin
  Result := False;
  while ANode <> nil do
  begin
    case ANode.Kind of
      TSyntaxKind.Identifier:
        Exit(not MatchText(ANode.Name, ['nil', 'True', 'False', 'Default']));
      TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess:
        ANode := ANode[0];
    else
      Exit;
    end;
  end;
end;

/// <summary>Feld eines in place geschriebenen Array-Elements: R.F bei R.F[I] := ... bzw. R.F[I].X := ...; nil
/// sonst.</summary>
function WrittenArrayField(AStatement: TSyntaxNode): TSyntaxNode;
var
  mTarget: TSyntaxNode;
begin
  Result := nil;
  mTarget := AStatement[0];
  while mTarget.Kind = TSyntaxKind.MemberAccess do
  begin
    mTarget := mTarget[0];
  end;
  if (mTarget.Kind = TSyntaxKind.IndexAccess) and (mTarget[0].Kind = TSyntaxKind.MemberAccess) then
  begin
    Result := mTarget[0];
  end;
end;

type
  /// <summary>Typen für record-array-shared über die Namensauflösung.</summary>
  TSharedTypes = class
  private
    FContext: TRuleContext;
    FScope: TTypedScope;
    FTypes: TExpressionTypes;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    /// <summary>Ist ANode sicher ein Record?</summary>
    function IsRecord(ANode: TSyntaxNode): Boolean;
    /// <summary>Ist ANode sicher eine Variable, ein Feld, ein Parameter oder eine Property, kein Funktionsaufruf
    /// ohne Klammern (der liefert einen neuen Record)?</summary>
    function IsStored(ANode: TSyntaxNode): Boolean;
    /// <summary>Ist ANode (ein Feld) sicher ein dynamisches Array?</summary>
    function IsDynamicArray(ANode: TSyntaxNode): Boolean;
  end;

constructor TSharedTypes.Create(const AContext: TRuleContext);
var
  mOptions: TExpressionTypeOptions;
begin
  inherited Create;
  FContext := AContext;
  FScope := TTypedScope.Create(AContext);
  mOptions := TExpressionTypeOptions.Default;
  mOptions.Conversions := False;
  mOptions.ConstValue := False;
  FTypes := TExpressionTypes.Create(FScope.Resolver, AContext.Tree, FScope.FileName, AContext.Text, AContext.Index,
    mOptions);
end;

destructor TSharedTypes.Destroy;
begin
  FTypes.Free;
  FScope.Free;
  inherited Destroy;
end;

function TSharedTypes.IsRecord(ANode: TSyntaxNode): Boolean;
var
  mSymbol, mType: TResolvedSymbol;
begin
  Result := FScope.SureType(ANode, mSymbol, mType) and (mType.SymbolKind = TIndexSymbolKind.RecordType);
end;

function TSharedTypes.IsStored(ANode: TSyntaxNode): Boolean;
var
  mSymbol, mType: TResolvedSymbol;
begin
  Result := FScope.SureType(ANode, mSymbol, mType) and not (mSymbol.SymbolKind in [TIndexSymbolKind.Method,
    TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_]);
end;

function TSharedTypes.IsDynamicArray(ANode: TSyntaxNode): Boolean;
var
  mInfo: TExpressionTypeInfo;
begin
  mInfo := FTypes.Describe(ANode);
  // Die Typbeschreibung nennt TArray<T> ohne Typargument.
  Result := mInfo.Found and (SameText(WithoutUnit(mInfo.TypeName), 'TArray') or
    IsDynamicArrayType(FContext, mInfo.TypeName) or (mInfo.BaseName <> '') and
    IsDynamicArrayType(FContext, mInfo.BaseName));
end;

/// <summary>Weist der Rumpf ab AFrom bis vor ATo einem der Ziele ATargets (Records bzw. ihre Felder) neu zu?
/// </summary>
function Replaced(const AText: string; const AStatements: TArray<TSyntaxNode>; AFrom, ATo: Integer;
  const ATargets: TArray<string>): Boolean;
var
  mIndex: Integer;
  mStatement: TSyntaxNode;
  mWritten: string;
begin
  for mIndex := AFrom to ATo - 1 do
  begin
    mStatement := AStatements[mIndex];
    mWritten := '';
    if mStatement.Kind = TSyntaxKind.AssignStatement then
    begin
      mWritten := Compact(AText, mStatement[0]);
    end
    else if (mStatement[0].Kind = TSyntaxKind.Call) and IsName(mStatement[0][0], 'SetLength') and
      (mStatement[0].ChildCount > 1) then
    begin
      mWritten := Compact(AText, mStatement[0][1]);
    end;
    if MatchStr(mWritten, ATargets) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  /// <summary>Eine Kopie B := A und die Anweisungen der Routine.</summary>
  TSharedCopy = record
    Statements: TArray<TSyntaxNode>;
    Index: Integer;
    function Statement: TSyntaxNode;
  end;

function TSharedCopy.Statement: TSyntaxNode;
begin
  Result := Statements[Index];
end;

/// <summary>Erstes in place geschriebenes Array-Feld eines der beiden Records nach der Kopie; nil ohne.</summary>
function SharedWrite(const AText: string; const ACopy: TSharedCopy; ATypes: TSharedTypes;
  out AField: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
  mSides: TArray<string>;
  mMember, mReceiver: string;
begin
  Result := nil;
  mSides := [Compact(AText, ACopy.Statement[0]), Compact(AText, ACopy.Statement[1])];
  for mIndex := ACopy.Index + 1 to High(ACopy.Statements) do
  begin
    if ACopy.Statements[mIndex].Kind <> TSyntaxKind.AssignStatement then
    begin
      Continue;
    end;
    AField := WrittenArrayField(ACopy.Statements[mIndex]);
    if AField = nil then
    begin
      Continue;
    end;
    mReceiver := Compact(AText, AField[0]);
    mMember := '.' + LowerCase(AField.Name);
    if MatchStr(mReceiver, mSides) and not Replaced(AText, ACopy.Statements, ACopy.Index + 1, mIndex, [mSides[0],
      mSides[1], mSides[0] + mMember, mSides[1] + mMember]) and ATypes.IsDynamicArray(AField) then
    begin
      Exit(ACopy.Statements[mIndex]);
    end;
  end;
end;

/// <summary>Ist AStatement eine Kopie B := A zweier Records ohne Aufruf?</summary>
function IsRecordCopy(AStatement: TSyntaxNode; ATypes: TSharedTypes): Boolean;
begin
  Result := (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount = 2) and
    IsPlainChain(AStatement[0]) and IsPlainChain(AStatement[1]) and ATypes.IsRecord(AStatement[0]) and
    ATypes.IsStored(AStatement[1]);
end;

procedure ReportShared(const AContext: TRuleContext; const AReport: IRuleReport; const ACopy: TSharedCopy;
  AWrite, AField: TSyntaxNode);
var
  mField, mOther: string;
begin
  mField := SourceText(AContext.Text, AField);
  mOther := SourceText(AContext.Text, ACopy.Statement[1]);
  if SameText(SourceText(AContext.Text, AField[0]), mOther) then
  begin
    mOther := SourceText(AContext.Text, ACopy.Statement[0]);
  end;
  AReport.Add(TTextRange.Create(AWrite[0].StartPos, AWrite[0].EndPos), cTexts[TSemanticsText.SharedMessage].Fmt(
    [mField, ACopy.Statement.StartPos.Line + 1, SourceText(AContext.Text, ACopy.Statement), mOther]),
    TRuleConfidence.High,
    [InsertBefore(AContext, AWrite, cTexts[TSemanticsText.SharedFix].Fmt([mField]), mField + ' := Copy(' + mField +
    ')')]);
end;

procedure TRecordArraySharedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mRoutine, mWrite, mField: TSyntaxNode;
  mTypes: TSharedTypes;
  mCopy: TSharedCopy;
  mIndex: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.Index = nil) then
  begin
    Exit;
  end;
  mTypes := TSharedTypes.Create(AContext);
  try
    for mRoutine in Routines(AContext) do
    begin
      mCopy.Statements := BodyNodes(mRoutine, [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement]);
      for mIndex := 0 to High(mCopy.Statements) do
      begin
        mCopy.Index := mIndex;
        if not IsRecordCopy(mCopy.Statement, mTypes) then
        begin
          Continue;
        end;
        mWrite := SharedWrite(AContext.Text, mCopy, mTypes, mField);
        if mWrite <> nil then
        begin
          ReportShared(AContext, AReport, mCopy, mWrite, mField);
        end;
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TExtractFileSlashRule }

function TExtractFileSlashRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cExtractFileSlashRuleId, TRuleSeverity.Warning,
    cTexts[TSemanticsText.SlashTitle].Text);
end;

/// <summary>Ist ANode das Literal '/' bzw. ein Literal mit '/'?</summary>
function SlashLiteral(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and StartsStr('''', ANode.Name) and ContainsStr(ANode.Name, '/');
end;

/// <summary>Das Literal '/' als Ersatz in StringReplace(X, '\', '/', ...) bzw. X.Replace('\', '/'); nil sonst.
/// </summary>
function SlashReplacement(ANode: TSyntaxNode): TSyntaxNode;
var
  mCallee: TSyntaxNode;
  mFirst: Integer;
begin
  Result := nil;
  if ANode.Kind <> TSyntaxKind.Call then
  begin
    Exit;
  end;
  mCallee := ANode[0];
  mFirst := 1;
  if IsName(mCallee, 'StringReplace') then
  begin
    mFirst := 2;
  end
  else if not ((mCallee.Kind = TSyntaxKind.MemberAccess) and SameText(mCallee.Name, 'Replace')) then
  begin
    Exit;
  end;
  if (ANode.ChildCount > mFirst + 1) and (ANode[mFirst + 1].Kind = TSyntaxKind.Literal) and
    (ANode[mFirst + 1].Name = '''/''') then
  begin
    Result := ANode[mFirst + 1];
  end;
end;

/// <summary>Stelle im Ausdruck AValue, die einen Pfad mit '/' baut: Literal mit '/' in einer Verkettung oder
/// Ersatz nach '/'; nil ohne.</summary>
function SlashSource(AValue: TSyntaxNode): TSyntaxNode;
begin
  Result := SlashReplacement(AValue);
  if Result <> nil then
  begin
    Exit;
  end;
  if SlashLiteral(AValue) then
  begin
    Exit(AValue);
  end;
  if (AValue.Kind = TSyntaxKind.BinaryExpr) and (AValue.Name = '+') then
  begin
    Result := SlashSource(AValue[0]);
    if Result = nil then
    begin
      Result := SlashSource(AValue[1]);
    end;
  end
  else if (AValue.Kind = TSyntaxKind.ParenExpr) and (AValue.ChildCount = 1) then
  begin
    Result := SlashSource(AValue[0]);
  end;
end;

/// <summary>Quelle des '/' im Argument AArgument, auch über die letzte Zuweisung ohne Bedingung an eine lokale
/// Variable.</summary>
function ArgumentSlash(const AText: string; const AAssignments: TArray<TSyntaxNode>; ACall,
  AArgument: TSyntaxNode): TSyntaxNode;
var
  mAssign: TSyntaxNode;
begin
  Result := SlashSource(AArgument);
  if (Result <> nil) or (AArgument.Kind <> TSyntaxKind.Identifier) then
  begin
    Exit;
  end;
  mAssign := LastAssignment(AText, AAssignments, Compact(AText, AArgument), ACall);
  // Eine Zuweisung in einem Zweig (if PathDelim = '/' then ...) gilt nicht für jeden Weg.
  if (mAssign <> nil) and Unconditional(mAssign) then
  begin
    Result := SlashSource(mAssign[1]);
  end;
end;

procedure TExtractFileSlashRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mRoutine, mCall, mSource: TSyntaxNode;
  mAssignments: TArray<TSyntaxNode>;
  mFixes: TArray<TRuleFix>;
begin
  if not ContainsText(AContext.Text, 'ExtractFile') then
  begin
    Exit;
  end;
  for mRoutine in Routines(AContext) do
  begin
    mAssignments := BodyNodes(mRoutine, [TSyntaxKind.AssignStatement]);
    for mCall in BodyNodes(mRoutine, [TSyntaxKind.Call]) do
    begin
      if (mCall.ChildCount < 2) or (mCall[0].Kind <> TSyntaxKind.Identifier) or
        not MatchText(mCall[0].Name, cExtractRoutines) then
      begin
        Continue;
      end;
      mSource := ArgumentSlash(AContext.Text, mAssignments, mCall, mCall[1]);
      if mSource = nil then
      begin
        Continue;
      end;
      mFixes := nil;
      if mSource.Name = '''/''' then
      begin
        mFixes := [TRuleFix.Create(cTexts[TSemanticsText.SlashFix].Text, [TTextEdit.Create(TTextRange.Create(
          mSource.StartPos, mSource.EndPos), 'PathDelim')], False)];
      end;
      AReport.Add(TTextRange.Create(mCall.StartPos, mCall.EndPos), cTexts[TSemanticsText.SlashMessage].Fmt(
        [mCall[0].Name]), TRuleConfidence.High, mFixes);
    end;
  end;
end;

{ THashOverflowCheckedRule }

function THashOverflowCheckedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cHashOverflowCheckedRuleId, TRuleSeverity.Warning,
    cTexts[TSemanticsText.OverflowTitle].Text);
end;

/// <summary>ANode ohne Klammern und Typumwandlungen wie UInt64(...) bzw. Cardinal(...).</summary>
function WithoutCasts(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := Unwrapped(ANode);
  while (Result.Kind = TSyntaxKind.Call) and (Result.ChildCount = 2) and (Result[0].Kind = TSyntaxKind.Identifier) and
    MatchText(Result[0].Name, ['UInt64', 'Int64', 'Cardinal', 'UInt32', 'Integer', 'NativeUInt', 'LongWord']) do
  begin
    Result := Unwrapped(Result[1]);
  end;
end;

/// <summary>Ist ANode ausdrücklich auf 64 Bit erweitert (UInt64(...), Int64(...))?</summary>
function IsWidened(ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := Unwrapped(ANode);
  Result := (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount = 2) and (mNode[0].Kind = TSyntaxKind.Identifier) and
    MatchText(mNode[0].Name, cWideCasts);
end;

/// <summary>Wert der Konstanten AName aus der Datei als Literal-Knoten; nil ohne.</summary>
function ConstantValue(ARoot: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mDecl: TSyntaxNode;
begin
  mDecl := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.ConstDecl) and SameText(ANode.Name, AName) and (ANode.ChildCount > 0) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  Result := nil;
  if mDecl <> nil then
  begin
    Result := WithoutCasts(mDecl[mDecl.ChildCount - 1]);
  end;
end;

/// <summary>FNV-Primzahl in ANode (Literal oder Konstante der Datei): 32 bzw. 64; 0 sonst.</summary>
function PrimeBits(ARoot, ANode: TSyntaxNode): Integer;
var
  mValue: TSyntaxNode;
  mNumber: Int64;
begin
  Result := 0;
  mValue := WithoutCasts(ANode);
  if mValue.Kind = TSyntaxKind.Identifier then
  begin
    mValue := ConstantValue(ARoot, mValue.Name);
  end;
  if (mValue = nil) or (mValue.Kind <> TSyntaxKind.Literal) or not TryStrToInt64(mValue.Name, mNumber) then
  begin
    Exit;
  end;
  if mNumber = cFnvPrime32 then
  begin
    Result := 32;
  end
  else if mNumber = cFnvPrime64 then
  begin
    Result := 64;
  end;
end;

/// <summary>Schaltet die Direktive ADirective die Überlaufprüfung ein (1), aus (-1) oder nicht (0)?</summary>
function OverflowSwitch(const ADirective: string): Integer;
var
  mBody, mPart: string;
begin
  Result := 0;
  mBody := UpperCase(TDirectiveNames.Body(ADirective));
  if StartsStr('OVERFLOWCHECKS', mBody) then
  begin
    if ContainsStr(mBody, 'OFF') then
    begin
      Exit(-1);
    end;
    Exit(1);
  end;
  for mPart in mBody.Split([',']) do
  begin
    if Trim(mPart) = 'Q-' then
    begin
      Result := -1;
    end
    else if Trim(mPart) = 'Q+' then
    begin
      Result := 1;
    end;
  end;
end;

/// <summary>Gilt die Überlaufprüfung an AOffset? Direktiven der Datei der Reihe nach, Vorgabe an; {$PUSHOPT} und
/// {$POPOPT} sichern bzw. stellen wieder her. Bedingte Zweige zählen beide: {$IFOPT Q+}...{$Q-}{$ENDIF} schaltet
/// so aus, {$IFDEF X}{$Q+}{$ENDIF} wieder ein.</summary>
function OverflowCheckedAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Boolean;
var
  mToken: TPascalToken;
  mStack: TStack<Boolean>;
  mSwitch: Integer;
  mBody: string;
begin
  Result := True;
  mStack := TStack<Boolean>.Create;
  try
    for mToken in ATokens do
    begin
      if mToken.Offset >= AOffset then
      begin
        Break;
      end;
      if mToken.Kind <> TPascalTokenKind.Directive then
      begin
        Continue;
      end;
      mBody := UpperCase(TDirectiveNames.Body(mToken.Text));
      if mBody = 'PUSHOPT' then
      begin
        mStack.Push(Result);
      end
      else if (mBody = 'POPOPT') and (mStack.Count > 0) then
      begin
        Result := mStack.Pop;
      end;
      mSwitch := OverflowSwitch(mToken.Text);
      if mSwitch <> 0 then
      begin
        Result := mSwitch > 0;
      end;
    end;
  finally
    mStack.Free;
  end;
end;

/// <summary>Läuft die Multiplikation AProduct sicher über: FNV-64 immer, FNV-32 ohne Erweiterung auf 64 Bit?
/// </summary>
function OverflowingHash(ARoot, AProduct: TSyntaxNode): Boolean;
var
  mSide, mBits: Integer;
begin
  Result := False;
  for mSide := 0 to 1 do
  begin
    mBits := PrimeBits(ARoot, AProduct[mSide]);
    if mBits = 64 then
    begin
      Exit(True);
    end;
    if (mBits = 32) and not IsWidened(AProduct[1 - mSide]) then
    begin
      Exit(True);
    end;
  end;
end;

procedure THashOverflowCheckedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mRoutine, mProduct: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not (ContainsStr(AContext.Text, '16777619') or
    ContainsText(AContext.Text, '1099511628211') or ContainsText(AContext.Text, '100000001B3') or
    ContainsText(AContext.Text, '01000193')) then
  begin
    Exit;
  end;
  for mRoutine in Routines(AContext) do
  begin
    for mProduct in BodyNodes(mRoutine, [TSyntaxKind.BinaryExpr]) do
    begin
      if (mProduct.Name = '*') and (mProduct.ChildCount = 2) and OverflowingHash(AContext.Tree.Root, mProduct) and
        OverflowCheckedAt(AContext.Tree.Tokens, mProduct.StartOffset) then
      begin
        AReport.Add(TTextRange.Create(mProduct.StartPos, mProduct.EndPos), cTexts[TSemanticsText.OverflowMessage].Fmt(
          [SourceText(AContext.Text, mProduct)]), TRuleConfidence.High);
      end;
    end;
  end;
end;

procedure RegisterDelphiSemanticsRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TManagedResultReadRule.Create);
  ARegistry.Register(TTryGetValueOutDefaultRule.Create);
  ARegistry.Register(TRecordArraySharedRule.Create);
  ARegistry.Register(TExtractFileSlashRule.Create);
  ARegistry.Register(THashOverflowCheckedRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.DelphiSemantics', cTexts);

end.
