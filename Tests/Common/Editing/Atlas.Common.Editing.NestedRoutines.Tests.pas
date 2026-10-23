unit Atlas.Common.Editing.NestedRoutines.Tests;

// Tests für „Lokale Routine und Methode ineinander umwandeln“ (#663): gelesene
// und geschriebene Variablen der äußeren Routine werden Parameter, Felder
// nicht, Konstanten wandern mit, Rekursion und Namenskonflikte, Hinweis bei
// zwei Ebenen, Gründe gegen das Herauslösen; Einbetten privater Methoden und
// freier Routinen mit genau einem Aufruf, nicht bei virtual/override,
// Ereignissen oder mehreren Aufrufern, durchgereichte Parameter, Hin- und
// Rückweg. Jedes Ergebnis muss fehlerfrei parsen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TNestedRoutinesTests = class
  public
    [Test]
    procedure ExtractCapturesReadAndWritten;
    [Test]
    procedure ExtractFreeRoutineWithConstant;
    [Test]
    procedure ExtractRecursionAndStaticClassMethod;
    [Test]
    procedure ExtractNameConflictGetsNumber;
    [Test]
    procedure ExtractTwoLevelsGivesHint;
    [Test]
    procedure ExtractRefusesChangedMeaning;
    [Test]
    procedure ExtractUsesConstLookup;
    [Test]
    procedure EmbedPrivateMethod;
    [Test]
    procedure EmbedFreeRoutine;
    [Test]
    procedure EmbedRefusals;
    [Test]
    procedure EmbedRemovesPassThrough;
    [Test]
    procedure EmbedRefusesShadowing;
    [Test]
    procedure ActionsAtPosition;
    [Test]
    procedure RoundTrip;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.NestedRoutines,
  Atlas.Text.Lines;

const
  LF = #10;

/// <summary>Zeilen mit LF verbunden, mit LF am Ende.</summary>
function Lines(const ALines: array of string): string;
var
  Line: string;
begin
  Result := '';
  for Line in ALines do
    Result := Result + Line + LF;
end;

/// <summary>Unit mit der Klasse TFoo (Mitglieder AMembers) und der Implementierung AImplementation.</summary>
function ClassUnit(const AMembers, AImplementation: string): string;
begin
  Result := Lines(['unit U;', '', 'interface', '', 'type', '  TFoo = class', '  private', '    FCount: Integer;']) +
    AMembers + Lines(['  end;', '', 'implementation', '']) + AImplementation + Lines(['', 'end.']);
end;

/// <summary>Unit ohne Klasse mit der Implementierung AImplementation.</summary>
function PlainUnit(const AImplementation: string): string;
begin
  Result := Lines(['unit U;', '', 'interface', '', 'implementation', '']) + AImplementation + Lines(['', 'end.']);
end;

function PositionOf(const AText, AMarker: string): TTextPosition;
begin
  Assert.IsTrue(Pos(AMarker, AText) > 0, 'Marke fehlt: ' + AMarker);
  Result := TLineTable.Build(AText).PositionAt(Pos(AMarker, AText) - 1);
end;

function NoLookup(ATree: TSyntaxTree): TNestedRoutineLookup;
begin
  Result := TNestedRoutineLookup.FromTree(ATree);
end;

/// <summary>Herauslösen bzw. Einbetten an AMarker; AResult ist der geänderte Text, der fehlerfrei parsen muss.
/// </summary>
function Run(const AText, AMarker: string; AEmbed, APassThrough: Boolean; const AConstTypes: array of string;
  out AAction: TCodeAction; out AReason, AResult: string): Boolean;
var
  Tree, Check: TSyntaxTree;
  Lookup: TNestedRoutineLookup;
  ConstTypes: TArray<string>;
  Index: Integer;
begin
  AResult := '';
  SetLength(ConstTypes, Length(AConstTypes));
  for Index := 0 to High(AConstTypes) do
    ConstTypes[Index] := AConstTypes[Index];
  Tree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), 'Quelle parst nicht: ' + AText);
    Lookup := NoLookup(Tree);
    if ConstTypes <> nil then
      Lookup.ConstType :=
        function(const ATypeName: string; AOffset: Integer): Boolean
        begin
          Result := IndexText(ATypeName, ConstTypes) >= 0;
        end;
    if AEmbed then
      Result := TNestedRoutines.Embed(AText, Tree, PositionOf(AText, AMarker), Lookup, TFormatStyle.Default,
        APassThrough, AAction, AReason)
    else
      Result := TNestedRoutines.Extract(AText, Tree, PositionOf(AText, AMarker), Lookup, TFormatStyle.Default,
        AAction, AReason);
    if Result and (AAction.Disabled = '') then
    begin
      AResult := TChangeSignature.ApplyEdits(AText, AAction.Edits);
      Check := TPascalParser.Parse(AResult);
      try
        Assert.AreEqual(0, Integer(Length(Check.Diagnostics)), 'Ergebnis parst nicht: ' + AResult);
      finally
        Check.Free;
      end;
    end;
  finally
    Tree.Free;
  end;
end;

function Extracted(const AText, AMarker: string; out AAction: TCodeAction): string;
var
  Reason: string;
begin
  Assert.IsTrue(Run(AText, AMarker, False, False, [], AAction, Reason, Result), 'Aktion fehlt (' + Reason + '): ' +
    AText);
end;

function ExtractReason(const AText, AMarker: string): string;
var
  Action: TCodeAction;
  Text: string;
begin
  Assert.IsFalse(Run(AText, AMarker, False, False, [], Action, Result, Text), 'Aktion unerwartet: ' + Text);
end;

function Embedded(const AText, AMarker: string; APassThrough: Boolean; out AAction: TCodeAction): string;
var
  Reason: string;
begin
  Assert.IsTrue(Run(AText, AMarker, True, APassThrough, [], AAction, Reason, Result), 'Aktion fehlt (' + Reason +
    '): ' + AText);
end;

function EmbedReason(const AText, AMarker: string; APassThrough: Boolean): string;
var
  Action: TCodeAction;
  Text: string;
begin
  Assert.IsFalse(Run(AText, AMarker, True, APassThrough, [], Action, Result, Text), 'Aktion unerwartet: ' + Text);
end;

procedure TNestedRoutinesTests.ExtractCapturesReadAndWritten;
var
  Text, Done: string;
  Action: TCodeAction;
begin
  Text := ClassUnit(Lines(['  public', '    procedure Run(const AName: string);']), Lines([
    'procedure TFoo.Run(const AName: string);',
    'var',
    '  Total: Integer;',
    '  Text: string;',
    '',
    '  // Zaehlt dazu.',
    '  procedure Add(AValue: Integer);',
    '  begin',
    '    Total := Total + AValue + FCount;',
    '    Text := AName;',
    '  end;',
    '',
    'begin',
    '  Total := 0;',
    '  Add(1);',
    '  Add(2);',
    'end;']));
  Done := Extracted(Text, 'procedure Add', Action);
  Assert.AreEqual(TNestedRoutines.ToMethodTitle, Action.Title);
  Assert.AreEqual(ClassUnit(Lines([
    '    procedure Add(AValue: Integer; var Total: Integer; var Text: string; const AName: string);',
    '  public',
    '    procedure Run(const AName: string);']), Lines([
    'procedure TFoo.Run(const AName: string);',
    'var',
    '  Total: Integer;',
    '  Text: string;',
    'begin',
    '  Total := 0;',
    '  Add(1, Total, Text, AName);',
    '  Add(2, Total, Text, AName);',
    'end;',
    '',
    '// Zaehlt dazu.',
    'procedure TFoo.Add(AValue: Integer; var Total: Integer; var Text: string; const AName: string);',
    'begin',
    '  Total := Total + AValue + FCount;',
    '  Text := AName;',
    'end;'])), Done);
  Assert.IsTrue(ContainsStr(Action.Preview,
    'procedure TFoo.Add(AValue: Integer; var Total: Integer; var Text: string; const AName: string);'),
    Action.Preview);
  Assert.IsTrue(ContainsStr(Action.Preview, 'Aufrufe: 2'), Action.Preview);
end;

procedure TNestedRoutinesTests.ExtractFreeRoutineWithConstant;
var
  Text, Done: string;
  Action: TCodeAction;
begin
  Text := PlainUnit(Lines([
    'procedure Outer(ACount: Integer);',
    'const',
    '  Limit = 10;',
    'var',
    '  Sum: Integer;',
    '',
    '  function Twice(AValue: Integer): Integer;',
    '  begin',
    '    Result := AValue * 2 + Limit + ACount;',
    '  end;',
    '',
    'begin',
    '  Sum := Twice(1) + Twice(Sum);',
    'end;']));
  Done := Extracted(Text, 'function Twice', Action);
  Assert.AreEqual(TNestedRoutines.ToUnitRoutineTitle, Action.Title);
  Assert.AreEqual(PlainUnit(Lines([
    'function Twice(AValue: Integer; ACount: Integer): Integer;',
    'const',
    '  Limit = 10;',
    'begin',
    '  Result := AValue * 2 + Limit + ACount;',
    'end;',
    '',
    'procedure Outer(ACount: Integer);',
    'const',
    '  Limit = 10;',
    'var',
    '  Sum: Integer;',
    'begin',
    '  Sum := Twice(1, ACount) + Twice(Sum, ACount);',
    'end;'])), Done);
end;

procedure TNestedRoutinesTests.ExtractRecursionAndStaticClassMethod;
var
  Text, Done: string;
  Action: TCodeAction;
begin
  Text := ClassUnit(Lines(['  public', '    class procedure Run; static;']), Lines([
    'class procedure TFoo.Run;',
    'var',
    '  Depth: Integer;',
    '',
    '  procedure Walk;',
    '  begin',
    '    Inc(Depth);',
    '    if Depth < 3 then',
    '      Walk;',
    '  end;',
    '',
    'begin',
    '  Depth := 0;',
    '  Walk;',
    'end;']));
  Done := Extracted(Text, 'procedure Walk', Action);
  Assert.IsTrue(ContainsStr(Done, '    class procedure Walk(var Depth: Integer); static;' + LF), Done);
  Assert.IsTrue(ContainsStr(Done, 'class procedure TFoo.Walk(var Depth: Integer);' + LF), Done);
  Assert.IsTrue(ContainsStr(Done, '  if Depth < 3 then' + LF + '    Walk(Depth);' + LF), Done);
  Assert.IsTrue(ContainsStr(Done, '  Depth: Integer;' + LF + 'begin' + LF), Done);
  Assert.IsTrue(ContainsStr(Done, '  Depth := 0;' + LF + '  Walk(Depth);' + LF), Done);
end;

procedure TNestedRoutinesTests.ExtractNameConflictGetsNumber;
var
  Text, Done: string;
  Action: TCodeAction;
begin
  Text := ClassUnit(Lines(['    procedure Show;', '  public', '    procedure Run;']), Lines([
    'procedure TFoo.Show;',
    'begin',
    'end;',
    '',
    'procedure TFoo.Run;',
    '',
    '  procedure Show;',
    '  begin',
    '    FCount := 1;',
    '  end;',
    '',
    'begin',
    '  Show;',
    'end;']));
  Done := Extracted(Text, 'procedure Show;' + LF + '  begin', Action);
  Assert.IsTrue(ContainsStr(Done, '    procedure Show2;' + LF), Done);
  Assert.IsTrue(ContainsStr(Done, 'procedure TFoo.Show2;' + LF), Done);
  Assert.IsTrue(ContainsStr(Done, 'begin' + LF + '  Show2;' + LF + 'end;'), Done);
  // Freie Routine: Name auf Unit-Ebene vergeben.
  Text := PlainUnit(Lines([
    'procedure Log;',
    'begin',
    'end;',
    '',
    'procedure Outer;',
    '',
    '  procedure Log;',
    '  begin',
    '  end;',
    '',
    'begin',
    '  Log;',
    'end;']));
  Done := Extracted(Text, 'procedure Log;' + LF + '  begin', Action);
  Assert.IsTrue(ContainsStr(Done, 'procedure Log2;' + LF + 'begin'), Done);
  Assert.IsTrue(ContainsStr(Done, '  Log2;' + LF + 'end;'), Done);
end;

procedure TNestedRoutinesTests.ExtractTwoLevelsGivesHint;
var
  Text, Reason, Done: string;
  Action: TCodeAction;
begin
  Text := PlainUnit(Lines([
    'procedure Outer;',
    '',
    '  procedure Middle;',
    '',
    '    procedure Deep;',
    '    begin',
    '    end;',
    '',
    '  begin',
    '    Deep;',
    '  end;',
    '',
    'begin',
    '  Middle;',
    'end;']));
  Assert.IsTrue(Run(Text, 'procedure Deep', False, False, [], Action, Reason, Done));
  Assert.IsTrue(ContainsStr(Action.Disabled, 'Middle'), Action.Disabled);
  Assert.AreEqual(0, Integer(Length(Action.Edits)));
  // Die mittlere geht.
  Done := Extracted(Text, 'procedure Middle', Action);
  Assert.AreEqual('', Action.Disabled);
  // Außerhalb einer lokalen Routine: nichts.
  Assert.AreNotEqual('', ExtractReason(Text, 'procedure Outer'));
end;

procedure TNestedRoutinesTests.ExtractRefusesChangedMeaning;
begin
  // Result der äußeren Funktion.
  Assert.AreNotEqual('', ExtractReason(PlainUnit(Lines([
    'function Outer: Integer;',
    '',
    '  procedure Clear;',
    '  begin',
    '    Result := 0;',
    '  end;',
    '',
    'begin',
    '  Clear;',
    'end;'])), 'procedure Clear'));
  // Andere lokale Routine.
  Assert.AreNotEqual('', ExtractReason(PlainUnit(Lines([
    'procedure Outer;',
    '',
    '  procedure First;',
    '  begin',
    '  end;',
    '',
    '  procedure Second;',
    '  begin',
    '    First;',
    '  end;',
    '',
    'begin',
    '  Second;',
    'end;'])), 'procedure Second'));
  // Lokaler Typ.
  Assert.AreNotEqual('', ExtractReason(PlainUnit(Lines([
    'procedure Outer;',
    'type',
    '  TPair = record A, B: Integer; end;',
    '',
    '  procedure Use;',
    '  var',
    '    P: TPair;',
    '  begin',
    '    P.A := 1;',
    '  end;',
    '',
    'begin',
    '  Use;',
    'end;'])), 'procedure Use'));
  // with.
  Assert.AreNotEqual('', ExtractReason(PlainUnit(Lines([
    'procedure Outer;',
    '',
    '  procedure Use;',
    '  begin',
    '    with TObject.Create do',
    '      Free;',
    '  end;',
    '',
    'begin',
    '  Use;',
    'end;'])), 'procedure Use'));
  // Als Wert benutzt (Methodenzeiger).
  Assert.AreNotEqual('', ExtractReason(PlainUnit(Lines([
    'procedure Outer;',
    'var',
    '  P: Pointer;',
    '',
    '  procedure Use;',
    '  begin',
    '  end;',
    '',
    'begin',
    '  P := @Use;',
    'end;'])), 'procedure Use'));
  // Künftiger var-Parameter in einer anonymen Methode.
  Assert.AreNotEqual('', ExtractReason(PlainUnit(Lines([
    'procedure Outer;',
    'var',
    '  Count: Integer;',
    '',
    '  procedure Use;',
    '  begin',
    '    TThread.Synchronize(nil, procedure begin Count := 1; end);',
    '  end;',
    '',
    'begin',
    '  Use;',
    'end;'])), 'procedure Use'));
end;

procedure TNestedRoutinesTests.ExtractUsesConstLookup;
var
  Text, Reason, Done: string;
  Action: TCodeAction;
begin
  Text := PlainUnit(Lines([
    'procedure Outer;',
    'var',
    '  Point: TPoint;',
    '  Count: Integer;',
    '',
    '  procedure Show;',
    '  begin',
    '    Count := Point.X;',
    '  end;',
    '',
    'begin',
    '  Show;',
    'end;']));
  Assert.IsTrue(Run(Text, 'procedure Show', False, False, ['TPoint'], Action, Reason, Done), Reason);
  Assert.IsTrue(ContainsStr(Done, 'procedure Show(var Count: Integer; const Point: TPoint);'), Done);
  Done := Extracted(Text, 'procedure Show', Action);
  Assert.IsTrue(ContainsStr(Done, 'procedure Show(var Count: Integer; Point: TPoint);'), Done);
end;

procedure TNestedRoutinesTests.EmbedPrivateMethod;
var
  Text, Done: string;
  Action: TCodeAction;
begin
  Text := ClassUnit(Lines(['    procedure Helper(AValue: Integer);', '  public', '    procedure Run;']), Lines([
    'procedure TFoo.Helper(AValue: Integer);',
    'begin',
    '  FCount := AValue;',
    'end;',
    '',
    'procedure TFoo.Run;',
    'var',
    '  I: Integer;',
    'begin',
    '  I := 1;',
    '  Self.Helper(I);',
    'end;']));
  Done := Embedded(Text, 'procedure Helper', False, Action);
  Assert.AreEqual(TNestedRoutines.EmbedMethodTitle, Action.Title);
  Assert.AreEqual(ClassUnit(Lines(['  public', '    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    'var',
    '  I: Integer;',
    '',
    '  procedure Helper(AValue: Integer);',
    '  begin',
    '    FCount := AValue;',
    '  end;',
    '',
    'begin',
    '  I := 1;',
    '  Helper(I);',
    'end;'])), Done);
  Assert.IsTrue(ContainsStr(Action.Preview, 'TFoo.Run'), Action.Preview);
  // Auch vom Kopf der Implementierung aus.
  Assert.AreEqual(Done, Embedded(Text, 'procedure TFoo.Helper', False, Action));
end;

procedure TNestedRoutinesTests.EmbedFreeRoutine;
var
  Text, Done: string;
  Action: TCodeAction;
begin
  Text := PlainUnit(Lines([
    'procedure Run;',
    'begin',
    '  Log(''a'');',
    'end;',
    '',
    'function Twice(AValue: Integer): Integer;',
    'begin',
    '  Result := AValue * 2;',
    'end;',
    '',
    'procedure Outer;',
    'var',
    '  N: Integer;',
    'begin',
    '  N := Twice(3);',
    'end;']));
  Done := Embedded(Text, 'function Twice', False, Action);
  Assert.AreEqual(TNestedRoutines.EmbedRoutineTitle, Action.Title);
  Assert.AreEqual(PlainUnit(Lines([
    'procedure Run;',
    'begin',
    '  Log(''a'');',
    'end;',
    '',
    'procedure Outer;',
    'var',
    '  N: Integer;',
    '',
    '  function Twice(AValue: Integer): Integer;',
    '  begin',
    '    Result := AValue * 2;',
    '  end;',
    '',
    'begin',
    '  N := Twice(3);',
    'end;'])), Done);
end;

procedure TNestedRoutinesTests.EmbedRefusals;
var
  Implementation_: string;
begin
  Implementation_ := Lines([
    'procedure TFoo.Helper;',
    'begin',
    'end;',
    '',
    'procedure TFoo.Run;',
    'begin',
    '  Helper;',
    'end;']);
  // Öffentlich, virtuell, überschrieben.
  Assert.AreNotEqual('', EmbedReason(ClassUnit(Lines(['  public', '    procedure Helper;', '    procedure Run;']),
    Implementation_), 'procedure TFoo.Helper', False));
  Assert.AreNotEqual('', EmbedReason(ClassUnit(Lines(['    procedure Helper; virtual;', '  public',
    '    procedure Run;']), Implementation_), 'procedure TFoo.Helper', False));
  Assert.AreNotEqual('', EmbedReason(ClassUnit(Lines(['    procedure Helper; override;', '  public',
    '    procedure Run;']), Implementation_), 'procedure TFoo.Helper', False));
  // Zwei Aufrufer bzw. zwei Aufrufe.
  Assert.AreNotEqual('', EmbedReason(ClassUnit(Lines(['    procedure Helper;', '  public', '    procedure Run;',
    '    procedure Other;']), Implementation_ + Lines(['', 'procedure TFoo.Other;', 'begin', '  Helper;', 'end;'])),
    'procedure TFoo.Helper', False));
  Assert.AreNotEqual('', EmbedReason(ClassUnit(Lines(['    procedure Helper;', '  public', '    procedure Run;']),
    Lines(['procedure TFoo.Helper;', 'begin', 'end;', '', 'procedure TFoo.Run;', 'begin', '  Helper;', '  Helper;',
    'end;'])), 'procedure TFoo.Helper', False));
  // Kein Aufruf.
  Assert.AreNotEqual('', EmbedReason(ClassUnit(Lines(['    procedure Helper;', '  public', '    procedure Run;']),
    Lines(['procedure TFoo.Helper;', 'begin', 'end;', '', 'procedure TFoo.Run;', 'begin', 'end;'])),
    'procedure TFoo.Helper', False));
  // Als Ereignis zugewiesen.
  Assert.AreNotEqual('', EmbedReason(ClassUnit(Lines(['    procedure Helper(Sender: TObject);', '  public',
    '    procedure Run;']), Lines(['procedure TFoo.Helper(Sender: TObject);', 'begin', 'end;', '',
    'procedure TFoo.Run;', 'begin', '  Button.OnClick := Helper;', 'end;'])), 'procedure TFoo.Helper', False));
  // Über ein anderes Objekt.
  Assert.AreNotEqual('', EmbedReason(ClassUnit(Lines(['    procedure Helper;', '  public', '    procedure Run;']),
    Lines(['procedure TFoo.Helper;', 'begin', 'end;', '', 'procedure TFoo.Run;', 'begin', '  Other.Helper;',
    'end;'])), 'procedure TFoo.Helper', False));
  // Freie Routine im interface.
  Assert.AreNotEqual('', EmbedReason(Lines(['unit U;', '', 'interface', '', 'procedure Twice;', '',
    'implementation', '', 'procedure Twice;', 'begin', 'end;', '', 'procedure Outer;', 'begin', '  Twice;', 'end;', '',
    'end.']), 'procedure Twice;' + LF + 'begin', False));
  // Aufruf aus einer lokalen Routine: dort ist kein Platz.
  Assert.AreNotEqual('', EmbedReason(PlainUnit(Lines(['procedure Twice;', 'begin', 'end;', '', 'procedure Outer;',
    '', '  procedure Inner;', '  begin', '    Twice;', '  end;', '', 'begin', '  Inner;', 'end;'])),
    'procedure Twice', False));
end;

procedure TNestedRoutinesTests.EmbedRemovesPassThrough;
var
  Text, Done: string;
  Action: TCodeAction;
begin
  Text := PlainUnit(Lines([
    'procedure Log(const AText: string; AValue: Integer);',
    'begin',
    'end;',
    '',
    'procedure Show(const AName: string; ACount: Integer; AStep: Integer);',
    'begin',
    '  Log(AName, ACount);',
    '  AStep := AStep + 1;',
    'end;',
    '',
    'procedure Outer(const AName: string);',
    'var',
    '  Count, Step: Integer;',
    'begin',
    '  Show(AName, Count, Step);',
    'end;']));
  Done := Embedded(Text, 'procedure Show', True, Action);
  Assert.AreEqual(TNestedRoutines.EmbedRoutineTitle + TNestedRoutines.PassThroughSuffix, Action.Title);
  // AStep wird geschrieben und bleibt; ACount heißt jetzt wie die Variable des Aufrufers.
  Assert.AreEqual(PlainUnit(Lines([
    'procedure Log(const AText: string; AValue: Integer);',
    'begin',
    'end;',
    '',
    'procedure Outer(const AName: string);',
    'var',
    '  Count, Step: Integer;',
    '',
    '  procedure Show(AStep: Integer);',
    '  begin',
    '    Log(AName, Count);',
    '    AStep := AStep + 1;',
    '  end;',
    '',
    'begin',
    '  Show(Step);',
    'end;'])), Done);
  // Ohne durchgereichte Parameter keine zweite Aktion.
  Assert.AreNotEqual('', EmbedReason(PlainUnit(Lines(['procedure Show(AValue: Integer);', 'begin', 'end;', '',
    'procedure Outer;', 'begin', '  Show(1);', 'end;'])), 'procedure Show', True));
  // Anderer Typ: bleibt.
  Assert.AreNotEqual('', EmbedReason(PlainUnit(Lines(['procedure Show(AValue: Int64);', 'begin', 'end;', '',
    'procedure Outer;', 'var', '  N: Integer;', 'begin', '  Show(N);', 'end;'])), 'procedure Show', True));
end;

procedure TNestedRoutinesTests.EmbedRefusesShadowing;
begin
  // Der Aufrufer hat eine Variable Total, der Rumpf meint die globale.
  Assert.AreNotEqual('', EmbedReason(PlainUnit(Lines([
    'var',
    '  Total: Integer;',
    '',
    'procedure Add;',
    'begin',
    '  Total := Total + 1;',
    'end;',
    '',
    'procedure Outer;',
    'var',
    '  Total: Integer;',
    'begin',
    '  Total := 0;',
    '  Add;',
    'end;'])), 'procedure Add', False));
  // Freie Routine in eine Methode: ein Feld verdeckt den globalen Namen.
  Assert.AreNotEqual('', EmbedReason(ClassUnit(Lines(['  public', '    procedure Run;']), Lines([
    'var',
    '  FCount: Integer;',
    '',
    'procedure Bump;',
    'begin',
    '  Inc(FCount);',
    'end;',
    '',
    'procedure TFoo.Run;',
    'begin',
    '  Bump;',
    'end;'])), 'procedure Bump', False));
end;

procedure TNestedRoutinesTests.ActionsAtPosition;
var
  Text: string;
  Tree: TSyntaxTree;
  Actions: TArray<TCodeAction>;
begin
  Text := PlainUnit(Lines([
    'procedure Show(ACount: Integer);',
    'begin',
    'end;',
    '',
    'procedure Outer;',
    'var',
    '  Count: Integer;',
    'begin',
    '  Show(Count);',
    'end;']));
  Tree := TPascalParser.Parse(Text);
  try
    Actions := TNestedRoutines.Actions(Text, Tree, PositionOf(Text, 'procedure Show'), NoLookup(Tree),
      TFormatStyle.Default);
    Assert.AreEqual(2, Integer(Length(Actions)));
    Assert.AreEqual(TNestedRoutines.EmbedRoutineTitle, Actions[0].Title);
    Assert.AreEqual(TNestedRoutines.EmbedRoutineTitle + TNestedRoutines.PassThroughSuffix, Actions[1].Title);
    Assert.AreEqual(RewriteKind, Actions[0].Kind);
    // Im Rumpf: keine Aktion.
    Actions := TNestedRoutines.Actions(Text, Tree, PositionOf(Text, 'Show(Count)'), NoLookup(Tree),
      TFormatStyle.Default);
    Assert.AreEqual(0, Integer(Length(Actions)));
  finally
    Tree.Free;
  end;
end;

procedure TNestedRoutinesTests.RoundTrip;
var
  Text, Done, Back: string;
  Action: TCodeAction;
begin
  Text := PlainUnit(Lines([
    'procedure Outer;',
    'var',
    '  Total: Integer;',
    '',
    '  procedure Add(AValue: Integer);',
    '  begin',
    '    Total := Total + AValue;',
    '  end;',
    '',
    'begin',
    '  Total := 0;',
    '  Add(1);',
    'end;']));
  Done := Extracted(Text, 'procedure Add', Action);
  Back := Embedded(Done, 'procedure Add', True, Action);
  Assert.AreEqual(Text, Back);
end;

initialization
  TDUnitX.RegisterTestFixture(TNestedRoutinesTests);

end.
