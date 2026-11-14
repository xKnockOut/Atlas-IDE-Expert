unit Atlas.Common.Editing.AnonymousMethods.Tests;

// Tests für „Anonyme Methode und Methode umwandeln“ (#680): ohne Capture der
// Methodenname, gelesene und geschriebene Variablen bei synchronem Aufruf als
// Parameter mit Weiterleitung, später laufende anonyme Methode mit
// Weiterleitung oder Feldern, Namensvorschläge aus dem Zusammenhang, Routine
// der Unit in freien Routinen, Gründe dagegen; Einbetten nur bei genau einer
// Übergabe an reference to, nicht bei Aufrufen, Methodenzeigern und
// Ereignissen der Formulardatei; Hin- und Rückweg. Jedes Ergebnis muss
// fehlerfrei parsen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAnonymousMethodsTests = class
  public
    [Test]
    procedure WithoutCaptureUsesMethodName;
    [Test]
    procedure SynchronousCapturesBecomeParameters;
    [Test]
    procedure DeferredKeepsForwarding;
    [Test]
    procedure DeferredFieldsCopyValues;
    [Test]
    procedure FieldsFallBackWhenWritten;
    [Test]
    procedure ComparerSuggestsCompareBy;
    [Test]
    procedure FreeRoutineBecomesUnitRoutine;
    [Test]
    procedure ClassMethodStaysClassMethod;
    [Test]
    procedure RefusesChangedMeaning;
    [Test]
    procedure NameIsChecked;
    [Test]
    procedure EmbedSingleValueUse;
    [Test]
    procedure EmbedRefusals;
    [Test]
    procedure KindOfTypeText;
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
  Atlas.Common.Editing.AnonymousMethods,
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

/// <summary>Ohne Namensauflösung; Zieltypen beim Einbetten: AKind.</summary>
function LookupFor(ATree: TSyntaxTree; AKind: TProcTypeKind): TAnonymousLookup;
var
  mKind: TProcTypeKind;
begin
  Result := TAnonymousLookup.FromTree(ATree);
  mKind := AKind;
  Result.TargetType :=
    function(AValue: TSyntaxNode): TProcTypeKind
    begin
      Result := mKind;
    end;
end;

procedure AssertParses(const AText: string);
var
  mCheck: TSyntaxTree;
begin
  mCheck := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(mCheck.Diagnostics)), 'Ergebnis parst nicht: ' + AText);
  finally
    mCheck.Free;
  end;
end;

/// <summary>Ziel an AMarker (False mit AReason, wenn es nicht geht).</summary>
function TargetAt(const AText, AMarker: string; ACapture: TDeferredCapture; out ATarget: TAnonymousTarget;
  out AReason: string): Boolean;
var
  mTree: TSyntaxTree;
  mInput: TAnonymousInput;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), 'Quelle parst nicht: ' + AText);
    mInput := TAnonymousInput.Create(AText, mTree, PositionOf(AText, AMarker), LookupFor(mTree, TProcTypeKind.Unknown));
    mInput.Capture := ACapture;
    Result := TAnonymousMethods.Target(mInput, ATarget, AReason);
  finally
    mTree.Free;
  end;
end;

type
  /// <summary>Wo und wie „In Methode umwandeln“ ausgeführt wird.</summary>
  TConvertRequest = record
    Marker: string;
    Name: string;
    Capture: TDeferredCapture;
  end;

function Request(const AMarker, AName: string; ACapture: TDeferredCapture): TConvertRequest;
begin
  Result := Default(TConvertRequest);
  Result.Marker := AMarker;
  Result.Name := AName;
  Result.Capture := ACapture;
end;

/// <summary>„In Methode umwandeln“ nach ARequest; AResult ist der geänderte Text.</summary>
function ConvertAt(const AText: string; const ARequest: TConvertRequest; out AConverted: TAnonymousResult;
  out AReason, AResult: string): Boolean;
var
  mTree: TSyntaxTree;
  mInput: TAnonymousInput;
begin
  AResult := '';
  mTree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), 'Quelle parst nicht: ' + AText);
    mInput := TAnonymousInput.Create(AText, mTree, PositionOf(AText, ARequest.Marker), LookupFor(mTree,
      TProcTypeKind.Unknown));
    mInput.Capture := ARequest.Capture;
    Result := TAnonymousMethods.Execute(mInput, ARequest.Name, AConverted, AReason);
    if Result then
    begin
      AResult := TChangeSignature.ApplyEdits(AText, AConverted.Edits);
      AssertParses(AResult);
    end;
  finally
    mTree.Free;
  end;
end;

/// <summary>Einbetten an AMarker mit dem Zieltyp AKind.</summary>
function EmbedAt(const AText, AMarker: string; AKind: TProcTypeKind; out AAction: TCodeAction;
  out AReason, AResult: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  AResult := '';
  mTree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), 'Quelle parst nicht: ' + AText);
    Result := TAnonymousMethods.Embed(TAnonymousInput.Create(AText, mTree, PositionOf(AText, AMarker), LookupFor(mTree,
      AKind)), AAction, AReason);
    if Result then
    begin
      AResult := TChangeSignature.ApplyEdits(AText, AAction.Edits);
      AssertParses(AResult);
    end;
  finally
    mTree.Free;
  end;
end;

procedure TAnonymousMethodsTests.WithoutCaptureUsesMethodName;
var
  mText, mReason, mDone: string;
  mTarget: TAnonymousTarget;
  mConverted: TAnonymousResult;
begin
  mText := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  Button.OnClick := procedure(Sender: TObject) begin FCount := 1; end;',
    'end;']));
  Assert.IsTrue(TargetAt(mText, 'procedure(Sender', TDeferredCapture.Forward, mTarget, mReason), mReason);
  Assert.IsTrue(mTarget.IsMethod);
  Assert.AreEqual('HandleClick', mTarget.Suggested);
  Assert.AreEqual(Ord(TAnonymousForm.Direct), Ord(mTarget.Form));
  Assert.AreEqual('In Methode umwandeln (HandleClick)', mTarget.Title);
  Assert.IsTrue(ConvertAt(mText, Request('procedure(Sender', 'HandleClick', TDeferredCapture.Forward), mConverted, mReason,
    mDone), mReason);
  Assert.IsTrue(Pos('  Button.OnClick := HandleClick;', mDone) > 0, mDone);
  Assert.IsTrue(Pos(Lines(['    procedure Run;', '    procedure HandleClick(Sender: TObject);', '  end;']), mDone) > 0,
    mDone);
  Assert.IsTrue(Pos(Lines(['end;', '', 'procedure TFoo.HandleClick(Sender: TObject);', 'begin', '  FCount := 1;',
    'end;']), mDone) > 0, mDone);
  Assert.IsTrue(StartsStr('Neue Methode: procedure TFoo.HandleClick(Sender: TObject);', mConverted.Preview),
    mConverted.Preview);
  Assert.AreEqual(0, Integer(Length(mConverted.Warnings)));
end;

procedure TAnonymousMethodsTests.SynchronousCapturesBecomeParameters;
var
  mText, mReason, mDone: string;
  mTarget: TAnonymousTarget;
  mConverted: TAnonymousResult;
begin
  mText := ClassUnit(Lines(['    procedure Run(AFactor: Integer);']), Lines([
    'procedure TFoo.Run(AFactor: Integer);',
    'var',
    '  LSum: Integer;',
    '  LName: string;',
    'begin',
    '  LSum := 0;',
    '  FList.ForEach(procedure(const AItem: Integer)',
    '    begin',
    '      LSum := LSum + AItem * AFactor;',
    '      Log(LName);',
    '    end);',
    'end;']));
  Assert.IsTrue(TargetAt(mText, 'procedure(const AItem', TDeferredCapture.Fields, mTarget, mReason), mReason);
  Assert.AreEqual('ProcessItem', mTarget.Suggested);
  // Synchron: auch mit fields bleibt es bei Parametern.
  Assert.AreEqual(Ord(TAnonymousForm.Forwarding), Ord(mTarget.Form));
  Assert.IsTrue(ConvertAt(mText, Request('procedure(const AItem', 'ProcessItem', TDeferredCapture.Fields), mConverted,
    mReason, mDone), mReason);
  Assert.IsTrue(Pos(Lines([
    '  FList.ForEach(procedure(const AItem: Integer)',
    '    begin',
    '      ProcessItem(AItem, LSum, AFactor, LName);',
    '    end);']), mDone) > 0, mDone);
  // Log ist unbekannt: LName könnte ein var-Argument sein.
  Assert.IsTrue(Pos('procedure TFoo.ProcessItem(const AItem: Integer; var LSum: Integer; AFactor: Integer; ' +
    'var LName: string);', mDone) > 0, mDone);
  Assert.IsTrue(Pos(Lines([
    'begin',
    '  LSum := LSum + AItem * AFactor;',
    '  Log(LName);',
    'end;']), mDone) > 0, mDone);
  Assert.IsTrue(Pos('ForEach', mConverted.Preview) > 0, mConverted.Preview);
end;

procedure TAnonymousMethodsTests.DeferredKeepsForwarding;
var
  mText, mReason, mDone: string;
  mTarget: TAnonymousTarget;
  mConverted: TAnonymousResult;
begin
  mText := ClassUnit(Lines(['    procedure Run;', '    procedure Log(const AText: string);']), Lines([
    'procedure TFoo.Run;',
    'var',
    '  LText: string;',
    'begin',
    '  LText := ''fertig'';',
    '  TThread.Queue(nil,',
    '    procedure',
    '    begin',
    '      Log(LText);',
    '    end);',
    'end;']));
  Assert.IsTrue(TargetAt(mText, 'procedure' + cLF + '    begin', TDeferredCapture.Forward, mTarget, mReason), mReason);
  Assert.AreEqual('UpdateInMainThread', mTarget.Suggested);
  Assert.AreEqual(Ord(TAnonymousForm.Forwarding), Ord(mTarget.Form));
  Assert.IsTrue(ConvertAt(mText, Request('procedure' + cLF + '    begin', 'ZeigeFertig', TDeferredCapture.Forward),
    mConverted, mReason, mDone), mReason);
  Assert.IsTrue(Pos(Lines([
    '  TThread.Queue(nil,',
    '    procedure',
    '    begin',
    '      ZeigeFertig(LText);',
    '    end);']), mDone) > 0, mDone);
  // Log hat eine Signatur in der Datei: LText wird nur gelesen.
  Assert.IsTrue(Pos('    procedure ZeigeFertig(const LText: string);', mDone) > 0, mDone);
  Assert.IsTrue(Pos('Weiterleitung', mConverted.Preview) > 0, mConverted.Preview);
end;

procedure TAnonymousMethodsTests.DeferredFieldsCopyValues;
var
  mText, mReason, mDone: string;
  mConverted: TAnonymousResult;
begin
  mText := ClassUnit(Lines(['    procedure Run;', '    procedure Log(const AText: string);']), Lines([
    'procedure TFoo.Run;',
    'var',
    '  LText: string;',
    'begin',
    '  LText := ''fertig'';',
    '  TThread.Queue(nil,',
    '    procedure',
    '    begin',
    '      Log(LText);',
    '    end);',
    'end;']));
  Assert.IsTrue(ConvertAt(mText, Request('procedure' + cLF + '    begin', 'ZeigeFertig', TDeferredCapture.Fields),
    mConverted, mReason, mDone), mReason);
  Assert.AreEqual(Ord(TAnonymousForm.Fields), Ord(mConverted.Form));
  Assert.IsTrue(Pos(Lines(['  FText := LText;', '  TThread.Queue(nil,', '    ZeigeFertig);']), mDone) > 0, mDone);
  Assert.IsTrue(Pos(Lines(['    FCount: Integer;', '    FText: string;']), mDone) > 0, mDone);
  Assert.IsTrue(Pos('    procedure ZeigeFertig;', mDone) > 0, mDone);
  Assert.IsTrue(Pos(Lines(['procedure TFoo.ZeigeFertig;', 'begin', '  Log(FText);', 'end;']), mDone) > 0, mDone);
  Assert.AreEqual(1, Integer(Length(mConverted.Warnings)));
end;

procedure TAnonymousMethodsTests.FieldsFallBackWhenWritten;
var
  mText, mReason, mDone: string;
  mConverted: TAnonymousResult;
begin
  mText := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    'var',
    '  LDone: Boolean;',
    'begin',
    '  LDone := False;',
    '  FTask := TTask.Run(procedure begin LDone := True; end);',
    'end;']));
  Assert.IsTrue(ConvertAt(mText, Request('procedure begin', 'Arbeite', TDeferredCapture.Fields), mConverted, mReason,
    mDone), mReason);
  Assert.AreEqual(Ord(TAnonymousForm.Forwarding), Ord(mConverted.Form));
  Assert.IsTrue(Pos('  FTask := TTask.Run(procedure begin Arbeite(LDone); end);', mDone) > 0, mDone);
  Assert.IsTrue(Pos('    procedure Arbeite(var LDone: Boolean);', mDone) > 0, mDone);
  Assert.IsTrue(Pos('schreibt', mConverted.Preview) > 0, mConverted.Preview);
end;

procedure TAnonymousMethodsTests.ComparerSuggestsCompareBy;
var
  mText, mReason, mDone: string;
  mTarget: TAnonymousTarget;
  mConverted: TAnonymousResult;
begin
  mText := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  FList.Sort(TComparer<TKunde>.Construct(',
    '    function(const A, B: TKunde): Integer',
    '    begin',
    '      Result := CompareText(A.Name, B.Name);',
    '    end));',
    'end;']));
  Assert.IsTrue(TargetAt(mText, 'function(const A', TDeferredCapture.Forward, mTarget, mReason), mReason);
  Assert.AreEqual('CompareByName', mTarget.Suggested);
  Assert.AreEqual(Ord(TAnonymousForm.Direct), Ord(mTarget.Form));
  Assert.IsTrue(ConvertAt(mText, Request('function(const A', 'CompareByName', TDeferredCapture.Forward), mConverted,
    mReason, mDone), mReason);
  Assert.IsTrue(Pos(Lines(['  FList.Sort(TComparer<TKunde>.Construct(', '    CompareByName));']), mDone) > 0, mDone);
  Assert.IsTrue(Pos('    function CompareByName(const A: TKunde; const B: TKunde): Integer;', mDone) > 0, mDone);
  Assert.IsTrue(Pos(Lines(['function TFoo.CompareByName(const A: TKunde; const B: TKunde): Integer;', 'begin',
    '  Result := CompareText(A.Name, B.Name);', 'end;']), mDone) > 0, mDone);
end;

procedure TAnonymousMethodsTests.FreeRoutineBecomesUnitRoutine;
var
  mText, mReason, mDone: string;
  mTarget: TAnonymousTarget;
  mConverted: TAnonymousResult;
begin
  mText := PlainUnit(Lines([
    'procedure Zaehle(const AWerte: TArray<Integer>);',
    'const',
    '  Grenze = 10;',
    'var',
    '  LAnzahl: Integer;',
    'begin',
    '  LAnzahl := 0;',
    '  TParallel.For(0, High(AWerte), procedure(I: Integer)',
    '    begin',
    '      if AWerte[I] > Grenze then',
    '        TInterlocked.Increment(LAnzahl);',
    '    end);',
    'end;']));
  Assert.IsTrue(TargetAt(mText, 'procedure(I', TDeferredCapture.Forward, mTarget, mReason), mReason);
  Assert.IsFalse(mTarget.IsMethod);
  Assert.AreEqual('ProcessIndex', mTarget.Suggested);
  Assert.AreEqual('In Routine umwandeln (ProcessIndex)', mTarget.Title);
  Assert.IsTrue(ConvertAt(mText, Request('procedure(I', 'ProcessIndex', TDeferredCapture.Forward), mConverted, mReason,
    mDone), mReason);
  Assert.IsTrue(Pos(Lines([
    'procedure ProcessIndex(I: Integer; const AWerte: TArray<Integer>; var LAnzahl: Integer);',
    'const',
    '  Grenze = 10;',
    'begin',
    '  if AWerte[I] > Grenze then',
    '    TInterlocked.Increment(LAnzahl);',
    'end;',
    '',
    'procedure Zaehle(const AWerte: TArray<Integer>);']), mDone) > 0, mDone);
  Assert.IsTrue(Pos('      ProcessIndex(I, AWerte, LAnzahl);', mDone) > 0, mDone);
  Assert.IsTrue(StartsStr('Neue Routine: ', mConverted.Preview), mConverted.Preview);
end;

procedure TAnonymousMethodsTests.ClassMethodStaysClassMethod;
var
  mText, mReason, mDone: string;
  mConverted: TAnonymousResult;
begin
  mText := ClassUnit(Lines(['    class procedure Run; static;']), Lines([
    'class procedure TFoo.Run;',
    'begin',
    '  TThread.Synchronize(nil, procedure begin Beep; end);',
    'end;']));
  Assert.IsTrue(ConvertAt(mText, Request('procedure begin', 'Piepe', TDeferredCapture.Fields), mConverted, mReason, mDone),
    mReason);
  Assert.IsTrue(Pos('  TThread.Synchronize(nil, Piepe);', mDone) > 0, mDone);
  Assert.IsTrue(Pos('    class procedure Piepe; static;', mDone) > 0, mDone);
  Assert.IsTrue(Pos('class procedure TFoo.Piepe;', mDone) > 0, mDone);
end;

procedure TAnonymousMethodsTests.RefusesChangedMeaning;
var
  mText, mReason: string;
  mTarget: TAnonymousTarget;
begin
  // Result der äußeren Funktion.
  mText := ClassUnit(Lines(['    function Run: Integer;']), Lines([
    'function TFoo.Run: Integer;',
    'begin',
    '  FList.ForEach(procedure(const AItem: Integer) begin Result := AItem; end);',
    'end;']));
  Assert.IsFalse(TargetAt(mText, 'procedure(const', TDeferredCapture.Forward, mTarget, mReason));
  Assert.IsTrue(Pos('Result', mReason) > 0, mReason);
  // Lokale Routine der äußeren.
  mText := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    '  procedure Hilfe;',
    '  begin',
    '  end;',
    'begin',
    '  FList.ForEach(procedure(const AItem: Integer) begin Hilfe; end);',
    'end;']));
  Assert.IsFalse(TargetAt(mText, 'procedure(const', TDeferredCapture.Forward, mTarget, mReason));
  Assert.IsTrue(Pos('Hilfe', mReason) > 0, mReason);
  // In einer lokalen Routine.
  mText := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    '  procedure Hilfe;',
    '  begin',
    '    FList.ForEach(procedure(const AItem: Integer) begin FCount := AItem; end);',
    '  end;',
    'begin',
    '  Hilfe;',
    'end;']));
  Assert.IsFalse(TargetAt(mText, 'procedure(const', TDeferredCapture.Forward, mTarget, mReason));
  // Verschachtelte anonyme Methode schreibt eine Variable, die var-Parameter würde.
  mText := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    'var',
    '  LSum: Integer;',
    'begin',
    '  FList.ForEach(procedure(const AItem: Integer)',
    '    begin',
    '      FOther.ForEach(procedure(const AInner: Integer) begin LSum := AInner; end);',
    '    end);',
    'end;']));
  Assert.IsFalse(TargetAt(mText, 'procedure(const AItem', TDeferredCapture.Forward, mTarget, mReason));
  Assert.IsTrue(Pos('LSum', mReason) > 0, mReason);
  // Auf dem Rumpf statt auf dem Kopf: nichts.
  Assert.IsFalse(TargetAt(mText, 'begin' + cLF + '      FOther', TDeferredCapture.Forward, mTarget, mReason));
end;

procedure TAnonymousMethodsTests.NameIsChecked;
var
  mText, mReason, mDone: string;
  mTarget: TAnonymousTarget;
  mConverted: TAnonymousResult;
begin
  mText := ClassUnit(Lines(['    procedure Run;', '    procedure HandleClick;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  Button.OnClick := procedure(Sender: TObject) begin FCount := 1; end;',
    'end;',
    '',
    'procedure TFoo.HandleClick;',
    'begin',
    'end;']));
  // Vergeben: Vorschlag mit Nummer, Ausführen mit dem Namen ein Fehler.
  Assert.IsTrue(TargetAt(mText, 'procedure(Sender', TDeferredCapture.Forward, mTarget, mReason), mReason);
  Assert.AreEqual('HandleClick2', mTarget.Suggested);
  Assert.IsFalse(ConvertAt(mText, Request('procedure(Sender', 'HandleClick', TDeferredCapture.Forward), mConverted,
    mReason, mDone));
  Assert.IsTrue(Pos('vergeben', mReason) > 0, mReason);
  Assert.IsFalse(ConvertAt(mText, Request('procedure(Sender', 'begin', TDeferredCapture.Forward), mConverted, mReason,
    mDone));
  Assert.IsFalse(ConvertAt(mText, Request('procedure(Sender', 'Sender', TDeferredCapture.Forward), mConverted, mReason,
    mDone));
end;

procedure TAnonymousMethodsTests.EmbedSingleValueUse;
var
  mText, mReason, mDone: string;
  mAction: TCodeAction;
begin
  mText := ClassUnit(Lines(['    procedure Run;', '    procedure ProcessItem(const AItem: Integer);']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  FList.ForEach(ProcessItem);',
    'end;',
    '',
    '// Zaehlt mit.',
    'procedure TFoo.ProcessItem(const AItem: Integer);',
    'var',
    '  LDoppelt: Integer;',
    'begin',
    '  LDoppelt := AItem * 2;',
    '  FCount := FCount + LDoppelt;',
    'end;']));
  Assert.IsTrue(EmbedAt(mText, 'ProcessItem(const AItem: Integer);' + cLF + 'var', TProcTypeKind.Reference, mAction,
    mReason, mDone), mReason);
  Assert.AreEqual(TAnonymousMethods.EmbedTitle, mAction.Title);
  Assert.IsTrue(Pos(Lines([
    '  FList.ForEach(procedure(const AItem: Integer)',
    '    var',
    '      LDoppelt: Integer;',
    '    begin',
    '      LDoppelt := AItem * 2;',
    '      FCount := FCount + LDoppelt;',
    '    end);',
    'end;']), mDone) > 0, mDone);
  Assert.IsFalse(ContainsStr(mDone, 'TFoo.ProcessItem'), mDone);
  Assert.IsFalse(ContainsStr(mDone, 'Zaehlt mit'), mDone);
  Assert.IsFalse(ContainsStr(mDone, '    procedure ProcessItem'), mDone);
  Assert.AreNotEqual('', mAction.Preview);
  // Auch von der Deklaration in der Klasse aus.
  Assert.IsTrue(EmbedAt(mText, 'ProcessItem(const AItem: Integer);' + cLF + '  end;', TProcTypeKind.Reference, mAction,
    mReason, mDone), mReason);
end;

/// <summary>Einbetten lehnt direkte, doppelte, öffentliche und verdeckte Aufrufer ab.</summary>
procedure AssertEmbedRefusesCallers;
var
  mText, mReason, mDone: string;
  mAction: TCodeAction;
begin
  // Direkt aufgerufen.
  mText := ClassUnit(Lines(['    procedure Run;', '    procedure Tick;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  Tick;',
    'end;',
    '',
    'procedure TFoo.Tick;',
    'begin',
    'end;']));
  Assert.IsFalse(EmbedAt(mText, 'TFoo.Tick', TProcTypeKind.Reference, mAction, mReason, mDone));
  // Zweimal übergeben.
  mText := ClassUnit(Lines(['    procedure Run;', '    procedure Tick;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  TThread.Queue(nil, Tick);',
    '  TThread.Queue(nil, Tick);',
    'end;',
    '',
    'procedure TFoo.Tick;',
    'begin',
    'end;']));
  Assert.IsFalse(EmbedAt(mText, 'TFoo.Tick', TProcTypeKind.Reference, mAction, mReason, mDone));
  Assert.IsTrue(Pos('genau eine', mReason) > 0, mReason);
  // Öffentlich.
  mText := ClassUnit(Lines(['  public', '    procedure Run;', '    procedure Tick;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  TThread.Queue(nil, Tick);',
    'end;',
    '',
    'procedure TFoo.Tick;',
    'begin',
    'end;']));
  Assert.IsFalse(EmbedAt(mText, 'TFoo.Tick', TProcTypeKind.Reference, mAction, mReason, mDone));
  // Ein lokaler Name des Aufrufers verdeckte FCount.
  mText := ClassUnit(Lines(['    procedure Run;', '    procedure Tick;']), Lines([
    'procedure TFoo.Run;',
    'var',
    '  FCount: Integer;',
    'begin',
    '  FCount := 0;',
    '  TThread.Queue(nil, Tick);',
    'end;',
    '',
    'procedure TFoo.Tick;',
    'begin',
    '  Inc(FCount);',
    'end;']));
  Assert.IsFalse(EmbedAt(mText, 'TFoo.Tick', TProcTypeKind.Reference, mAction, mReason, mDone));
  Assert.IsTrue(Pos('FCount', mReason) > 0, mReason);
end;

procedure TAnonymousMethodsTests.EmbedRefusals;
var
  mText, mReason, mDone: string;
  mAction: TCodeAction;
  mTree: TSyntaxTree;
  mLookup: TAnonymousLookup;
begin
  mText := ClassUnit(Lines(['    procedure Run;', '    procedure Tick(Sender: TObject);']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  Timer.OnTimer := Tick;',
    'end;',
    '',
    'procedure TFoo.Tick(Sender: TObject);',
    'begin',
    '  Inc(FCount);',
    'end;']));
  // Methodenzeiger und unbekannter Zieltyp.
  Assert.IsFalse(EmbedAt(mText, 'TFoo.Tick', TProcTypeKind.MethodPointer, mAction, mReason, mDone));
  Assert.IsTrue(Pos('of object', mReason) > 0, mReason);
  Assert.IsFalse(EmbedAt(mText, 'TFoo.Tick', TProcTypeKind.Unknown, mAction, mReason, mDone));
  // In der Formulardatei.
  mTree := TPascalParser.Parse(mText);
  try
    mLookup := LookupFor(mTree, TProcTypeKind.Reference);
    mLookup.InForm :=
      function(const AName: string): Boolean
      begin
        Result := SameText(AName, 'Tick');
      end;
    Assert.IsFalse(TAnonymousMethods.Embed(TAnonymousInput.Create(mText, mTree, PositionOf(mText, 'TFoo.Tick'), mLookup),
      mAction, mReason));
    Assert.IsTrue(Pos('Formulardatei', mReason) > 0, mReason);
  finally
    mTree.Free;
  end;
  AssertEmbedRefusesCallers;
end;

procedure TAnonymousMethodsTests.KindOfTypeText;
begin
  Assert.AreEqual(Ord(TProcTypeKind.Reference), Ord(TAnonymousMethods.KindOfTypeText('reference to procedure')));
  Assert.AreEqual(Ord(TProcTypeKind.Reference), Ord(TAnonymousMethods.KindOfTypeText('TProc<Integer>')));
  Assert.AreEqual(Ord(TProcTypeKind.Reference), Ord(TAnonymousMethods.KindOfTypeText('System.SysUtils.TFunc<T>')));
  Assert.AreEqual(Ord(TProcTypeKind.Reference), Ord(TAnonymousMethods.KindOfTypeText('TComparison<TKunde>')));
  Assert.AreEqual(Ord(TProcTypeKind.MethodPointer), Ord(TAnonymousMethods.KindOfTypeText('TNotifyEvent')));
  Assert.AreEqual(Ord(TProcTypeKind.MethodPointer),
    Ord(TAnonymousMethods.KindOfTypeText('procedure(Sender: TObject) of object')));
  Assert.AreEqual(Ord(TProcTypeKind.Plain), Ord(TAnonymousMethods.KindOfTypeText('function(A: Integer): Boolean')));
  Assert.AreEqual(Ord(TProcTypeKind.Unknown), Ord(TAnonymousMethods.KindOfTypeText('TMeinTyp')));
end;

procedure TAnonymousMethodsTests.RoundTrip;
var
  mText, mReason, mDone, mBack: string;
  mConverted: TAnonymousResult;
  mAction: TCodeAction;
begin
  mText := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  FList.ForEach(procedure(const AItem: Integer)',
    '    begin',
    '      FCount := FCount + AItem;',
    '    end);',
    'end;']));
  Assert.IsTrue(ConvertAt(mText, Request('procedure(const', 'ProcessItem', TDeferredCapture.Forward), mConverted, mReason,
    mDone), mReason);
  Assert.IsTrue(EmbedAt(mDone, 'TFoo.ProcessItem', TProcTypeKind.Reference, mAction, mReason, mBack), mReason);
  Assert.AreEqual(mText, mBack);
end;

initialization
  TDUnitX.RegisterTestFixture(TAnonymousMethodsTests);

end.
