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
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.NestedRoutines,
  Atlas.Text.Lines;

const
  cLF = #10;

/// <summary>Zeilen mit LF verbunden, mit LF am Ende.</summary>
function Lines(const ALines: array of string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in ALines do
  begin
    Result := Result + mLine + cLF;
  end;
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

type
  /// <summary>Was Run ausführt: Einbetten (mit oder ohne Durchreichen) oder Herauslösen; ConstTypes sind die
  /// Typnamen, die das Lookup als konstant meldet.</summary>
  TNestedMode = record
    Embed: Boolean;
    PassThrough: Boolean;
    ConstTypes: TArray<string>;
  end;

function Mode(AEmbed, APassThrough: Boolean; const AConstTypes: array of string): TNestedMode;
var
  mIndex: Integer;
begin
  Result := Default(TNestedMode);
  Result.Embed := AEmbed;
  Result.PassThrough := APassThrough;
  SetLength(Result.ConstTypes, Length(AConstTypes));
  for mIndex := 0 to High(AConstTypes) do
  begin
    Result.ConstTypes[mIndex] := AConstTypes[mIndex];
  end;
end;

/// <summary>Herauslösen bzw. Einbetten an AMarker nach AMode; AResult ist der geänderte Text, der fehlerfrei
/// parsen muss.</summary>
function Run(const AText, AMarker: string; const AMode: TNestedMode; out AAction: TCodeAction;
  out AReason, AResult: string): Boolean;
var
  mTree, mCheck: TSyntaxTree;
  mLookup: TNestedRoutineLookup;
  mConstTypes: TArray<string>;
begin
  AResult := '';
  mConstTypes := AMode.ConstTypes;
  mTree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), 'Quelle parst nicht: ' + AText);
    mLookup := NoLookup(mTree);
    if mConstTypes <> nil then
    begin
      mLookup.ConstType :=
        function(const ATypeName: string; AOffset: Integer): Boolean
        begin
          Result := IndexText(ATypeName, mConstTypes) >= 0;
        end;
    end;
    if AMode.Embed then
    begin
      Result := TNestedRoutines.Embed(TNestedRoutineRequest.Create(AText, mTree, PositionOf(AText, AMarker), mLookup,
        TFormatStyle.Default), AMode.PassThrough, AAction, AReason);
    end
    else
    begin
      Result := TNestedRoutines.Extract(TNestedRoutineRequest.Create(AText, mTree, PositionOf(AText, AMarker), mLookup,
        TFormatStyle.Default), AAction, AReason);
    end;
    if Result and (AAction.Disabled = '') then
    begin
      AResult := TChangeSignature.ApplyEdits(AText, AAction.Edits);
      mCheck := TPascalParser.Parse(AResult);
      try
        Assert.AreEqual(0, Integer(Length(mCheck.Diagnostics)), 'Ergebnis parst nicht: ' + AResult);
      finally
        mCheck.Free;
      end;
    end;
  finally
    mTree.Free;
  end;
end;

function Extracted(const AText, AMarker: string; out AAction: TCodeAction): string;
var
  mReason: string;
begin
  Assert.IsTrue(Run(AText, AMarker, Mode(False, False, []), AAction, mReason, Result),
    'Aktion fehlt (' + mReason + '): ' + AText);
end;

function ExtractReason(const AText, AMarker: string): string;
var
  mAction: TCodeAction;
  mText: string;
begin
  Assert.IsFalse(Run(AText, AMarker, Mode(False, False, []), mAction, Result, mText), 'Aktion unerwartet: ' + mText);
end;

function Embedded(const AText, AMarker: string; APassThrough: Boolean; out AAction: TCodeAction): string;
var
  mReason: string;
begin
  Assert.IsTrue(Run(AText, AMarker, Mode(True, APassThrough, []), AAction, mReason, Result),
    'Aktion fehlt (' + mReason + '): ' + AText);
end;

function EmbedReason(const AText, AMarker: string; APassThrough: Boolean): string;
var
  mAction: TCodeAction;
  mText: string;
begin
  Assert.IsFalse(Run(AText, AMarker, Mode(True, APassThrough, []), mAction, Result, mText), 'Aktion unerwartet: ' + mText);
end;

procedure TNestedRoutinesTests.ExtractCapturesReadAndWritten;
var
  mText, mDone: string;
  mAction: TCodeAction;
begin
  mText := ClassUnit(Lines(['  public', '    procedure Run(const AName: string);']), Lines([
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
  mDone := Extracted(mText, 'procedure Add', mAction);
  Assert.AreEqual(TNestedRoutines.ToMethodTitle, mAction.Title);
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
    'end;'])), mDone);
  Assert.IsTrue(ContainsStr(mAction.Preview,
    'procedure TFoo.Add(AValue: Integer; var Total: Integer; var Text: string; const AName: string);'),
    mAction.Preview);
  Assert.IsTrue(ContainsStr(mAction.Preview, 'Aufrufe: 2'), mAction.Preview);
end;

procedure TNestedRoutinesTests.ExtractFreeRoutineWithConstant;
var
  mText, mDone: string;
  mAction: TCodeAction;
begin
  mText := PlainUnit(Lines([
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
  mDone := Extracted(mText, 'function Twice', mAction);
  Assert.AreEqual(TNestedRoutines.ToUnitRoutineTitle, mAction.Title);
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
    'end;'])), mDone);
end;

procedure TNestedRoutinesTests.ExtractRecursionAndStaticClassMethod;
var
  mText, mDone: string;
  mAction: TCodeAction;
begin
  mText := ClassUnit(Lines(['  public', '    class procedure Run; static;']), Lines([
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
  mDone := Extracted(mText, 'procedure Walk', mAction);
  Assert.IsTrue(ContainsStr(mDone, '    class procedure Walk(var Depth: Integer); static;' + cLF), mDone);
  Assert.IsTrue(ContainsStr(mDone, 'class procedure TFoo.Walk(var Depth: Integer);' + cLF), mDone);
  Assert.IsTrue(ContainsStr(mDone, '  if Depth < 3 then' + cLF + '    Walk(Depth);' + cLF), mDone);
  Assert.IsTrue(ContainsStr(mDone, '  Depth: Integer;' + cLF + 'begin' + cLF), mDone);
  Assert.IsTrue(ContainsStr(mDone, '  Depth := 0;' + cLF + '  Walk(Depth);' + cLF), mDone);
end;

procedure TNestedRoutinesTests.ExtractNameConflictGetsNumber;
var
  mText, mDone: string;
  mAction: TCodeAction;
begin
  mText := ClassUnit(Lines(['    procedure Show;', '  public', '    procedure Run;']), Lines([
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
  mDone := Extracted(mText, 'procedure Show;' + cLF + '  begin', mAction);
  Assert.IsTrue(ContainsStr(mDone, '    procedure Show2;' + cLF), mDone);
  Assert.IsTrue(ContainsStr(mDone, 'procedure TFoo.Show2;' + cLF), mDone);
  Assert.IsTrue(ContainsStr(mDone, 'begin' + cLF + '  Show2;' + cLF + 'end;'), mDone);
  // Freie Routine: Name auf Unit-Ebene vergeben.
  mText := PlainUnit(Lines([
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
  mDone := Extracted(mText, 'procedure Log;' + cLF + '  begin', mAction);
  Assert.IsTrue(ContainsStr(mDone, 'procedure Log2;' + cLF + 'begin'), mDone);
  Assert.IsTrue(ContainsStr(mDone, '  Log2;' + cLF + 'end;'), mDone);
end;

procedure TNestedRoutinesTests.ExtractTwoLevelsGivesHint;
var
  mText, mReason, mDone: string;
  mAction: TCodeAction;
begin
  mText := PlainUnit(Lines([
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
  Assert.IsTrue(Run(mText, 'procedure Deep', Mode(False, False, []), mAction, mReason, mDone));
  Assert.IsTrue(ContainsStr(mAction.Disabled, 'Middle'), mAction.Disabled);
  Assert.AreEqual(0, Integer(Length(mAction.Edits)));
  // Die mittlere geht.
  mDone := Extracted(mText, 'procedure Middle', mAction);
  Assert.AreEqual('', mAction.Disabled);
  // Außerhalb einer lokalen Routine: nichts.
  Assert.AreNotEqual('', ExtractReason(mText, 'procedure Outer'));
end;

/// <summary>Result der äußeren Funktion, andere lokale Routine, lokaler Typ.</summary>
procedure AssertRefusesResultRoutineAndType;
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
end;

/// <summary>with, Methodenzeiger und künftiger var-Parameter in einer anonymen Methode.</summary>
procedure AssertRefusesWithPointerAndCapture;
begin
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

procedure TNestedRoutinesTests.ExtractRefusesChangedMeaning;
begin
  AssertRefusesResultRoutineAndType;
  AssertRefusesWithPointerAndCapture;
end;

procedure TNestedRoutinesTests.ExtractUsesConstLookup;
var
  mText, mReason, mDone: string;
  mAction: TCodeAction;
begin
  mText := PlainUnit(Lines([
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
  Assert.IsTrue(Run(mText, 'procedure Show', Mode(False, False, ['TPoint']), mAction, mReason, mDone), mReason);
  Assert.IsTrue(ContainsStr(mDone, 'procedure Show(var Count: Integer; const Point: TPoint);'), mDone);
  mDone := Extracted(mText, 'procedure Show', mAction);
  Assert.IsTrue(ContainsStr(mDone, 'procedure Show(var Count: Integer; Point: TPoint);'), mDone);
end;

procedure TNestedRoutinesTests.EmbedPrivateMethod;
var
  mText, mDone: string;
  mAction: TCodeAction;
begin
  mText := ClassUnit(Lines(['    procedure Helper(AValue: Integer);', '  public', '    procedure Run;']), Lines([
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
  mDone := Embedded(mText, 'procedure Helper', False, mAction);
  Assert.AreEqual(TNestedRoutines.EmbedMethodTitle, mAction.Title);
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
    'end;'])), mDone);
  Assert.IsTrue(ContainsStr(mAction.Preview, 'TFoo.Run'), mAction.Preview);
  // Auch vom Kopf der Implementierung aus.
  Assert.AreEqual(mDone, Embedded(mText, 'procedure TFoo.Helper', False, mAction));
end;

procedure TNestedRoutinesTests.EmbedFreeRoutine;
var
  mText, mDone: string;
  mAction: TCodeAction;
begin
  mText := PlainUnit(Lines([
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
  mDone := Embedded(mText, 'function Twice', False, mAction);
  Assert.AreEqual(TNestedRoutines.EmbedRoutineTitle, mAction.Title);
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
    'end;'])), mDone);
end;

procedure TNestedRoutinesTests.EmbedRefusals;
var
  mImplementation_: string;
begin
  mImplementation_ := Lines([
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
    mImplementation_), 'procedure TFoo.Helper', False));
  Assert.AreNotEqual('', EmbedReason(ClassUnit(Lines(['    procedure Helper; virtual;', '  public',
    '    procedure Run;']), mImplementation_), 'procedure TFoo.Helper', False));
  Assert.AreNotEqual('', EmbedReason(ClassUnit(Lines(['    procedure Helper; override;', '  public',
    '    procedure Run;']), mImplementation_), 'procedure TFoo.Helper', False));
  // Zwei Aufrufer bzw. zwei Aufrufe.
  Assert.AreNotEqual('', EmbedReason(ClassUnit(Lines(['    procedure Helper;', '  public', '    procedure Run;',
    '    procedure Other;']), mImplementation_ + Lines(['', 'procedure TFoo.Other;', 'begin', '  Helper;', 'end;'])),
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
    'end.']), 'procedure Twice;' + cLF + 'begin', False));
  // Aufruf aus einer lokalen Routine: dort ist kein Platz.
  Assert.AreNotEqual('', EmbedReason(PlainUnit(Lines(['procedure Twice;', 'begin', 'end;', '', 'procedure Outer;',
    '', '  procedure Inner;', '  begin', '    Twice;', '  end;', '', 'begin', '  Inner;', 'end;'])),
    'procedure Twice', False));
end;

procedure TNestedRoutinesTests.EmbedRemovesPassThrough;
var
  mText, mDone: string;
  mAction: TCodeAction;
begin
  mText := PlainUnit(Lines([
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
  mDone := Embedded(mText, 'procedure Show', True, mAction);
  Assert.AreEqual(TNestedRoutines.EmbedRoutineTitle + TNestedRoutines.PassThroughSuffix, mAction.Title);
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
    'end;'])), mDone);
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
  mText: string;
  mTree: TSyntaxTree;
  mActions: TArray<TCodeAction>;
begin
  mText := PlainUnit(Lines([
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
  mTree := TPascalParser.Parse(mText);
  try
    mActions := TNestedRoutines.Actions(mText, mTree, PositionOf(mText, 'procedure Show'), NoLookup(mTree),
      TFormatStyle.Default);
    Assert.AreEqual(2, Integer(Length(mActions)));
    Assert.AreEqual(TNestedRoutines.EmbedRoutineTitle, mActions[0].Title);
    Assert.AreEqual(TNestedRoutines.EmbedRoutineTitle + TNestedRoutines.PassThroughSuffix, mActions[1].Title);
    Assert.AreEqual(cRewriteKind, mActions[0].Kind);
    // Im Rumpf: keine Aktion.
    mActions := TNestedRoutines.Actions(mText, mTree, PositionOf(mText, 'Show(Count)'), NoLookup(mTree),
      TFormatStyle.Default);
    Assert.AreEqual(0, Integer(Length(mActions)));
  finally
    mTree.Free;
  end;
end;

procedure TNestedRoutinesTests.RoundTrip;
var
  mText, mDone, mBack: string;
  mAction: TCodeAction;
begin
  mText := PlainUnit(Lines([
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
  mDone := Extracted(mText, 'procedure Add', mAction);
  mBack := Embedded(mDone, 'procedure Add', True, mAction);
  Assert.AreEqual(mText, mBack);
end;

initialization
  TDUnitX.RegisterTestFixture(TNestedRoutinesTests);

end.
