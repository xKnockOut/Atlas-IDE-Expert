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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.AnonymousMethods,
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

/// <summary>Ohne Namensauflösung; Zieltypen beim Einbetten: AKind.</summary>
function LookupFor(ATree: TSyntaxTree; AKind: TProcTypeKind): TAnonymousLookup;
var
  Kind: TProcTypeKind;
begin
  Result := TAnonymousLookup.FromTree(ATree);
  Kind := AKind;
  Result.TargetType :=
    function(AValue: TSyntaxNode): TProcTypeKind
    begin
      Result := Kind;
    end;
end;

procedure AssertParses(const AText: string);
var
  Check: TSyntaxTree;
begin
  Check := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(Check.Diagnostics)), 'Ergebnis parst nicht: ' + AText);
  finally
    Check.Free;
  end;
end;

/// <summary>Ziel an AMarker (False mit AReason, wenn es nicht geht).</summary>
function TargetAt(const AText, AMarker: string; ACapture: TDeferredCapture; out ATarget: TAnonymousTarget;
  out AReason: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), 'Quelle parst nicht: ' + AText);
    Result := TAnonymousMethods.Target(AText, Tree, PositionOf(AText, AMarker), LookupFor(Tree,
      TProcTypeKind.Unknown), ACapture, ATarget, AReason);
  finally
    Tree.Free;
  end;
end;

/// <summary>„In Methode umwandeln“ an AMarker mit dem Namen AName; AResult ist der geänderte Text.</summary>
function ConvertAt(const AText, AMarker, AName: string; ACapture: TDeferredCapture;
  out AConverted: TAnonymousResult; out AReason, AResult: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  AResult := '';
  Tree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), 'Quelle parst nicht: ' + AText);
    Result := TAnonymousMethods.Execute(AText, Tree, PositionOf(AText, AMarker), LookupFor(Tree,
      TProcTypeKind.Unknown), ACapture, TFormatStyle.Default, AName, AConverted, AReason);
    if Result then
    begin
      AResult := TChangeSignature.ApplyEdits(AText, AConverted.Edits);
      AssertParses(AResult);
    end;
  finally
    Tree.Free;
  end;
end;

/// <summary>Einbetten an AMarker mit dem Zieltyp AKind.</summary>
function EmbedAt(const AText, AMarker: string; AKind: TProcTypeKind; out AAction: TCodeAction;
  out AReason, AResult: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  AResult := '';
  Tree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), 'Quelle parst nicht: ' + AText);
    Result := TAnonymousMethods.Embed(AText, Tree, PositionOf(AText, AMarker), LookupFor(Tree, AKind),
      TFormatStyle.Default, AAction, AReason);
    if Result then
    begin
      AResult := TChangeSignature.ApplyEdits(AText, AAction.Edits);
      AssertParses(AResult);
    end;
  finally
    Tree.Free;
  end;
end;

procedure TAnonymousMethodsTests.WithoutCaptureUsesMethodName;
var
  Text, Reason, Done: string;
  Target: TAnonymousTarget;
  Converted: TAnonymousResult;
begin
  Text := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  Button.OnClick := procedure(Sender: TObject) begin FCount := 1; end;',
    'end;']));
  Assert.IsTrue(TargetAt(Text, 'procedure(Sender', TDeferredCapture.Forward, Target, Reason), Reason);
  Assert.IsTrue(Target.IsMethod);
  Assert.AreEqual('HandleClick', Target.Suggested);
  Assert.AreEqual(Ord(TAnonymousForm.Direct), Ord(Target.Form));
  Assert.AreEqual('In Methode umwandeln (HandleClick)', Target.Title);
  Assert.IsTrue(ConvertAt(Text, 'procedure(Sender', 'HandleClick', TDeferredCapture.Forward, Converted, Reason,
    Done), Reason);
  Assert.IsTrue(Pos('  Button.OnClick := HandleClick;', Done) > 0, Done);
  Assert.IsTrue(Pos(Lines(['    procedure Run;', '    procedure HandleClick(Sender: TObject);', '  end;']), Done) > 0,
    Done);
  Assert.IsTrue(Pos(Lines(['end;', '', 'procedure TFoo.HandleClick(Sender: TObject);', 'begin', '  FCount := 1;',
    'end;']), Done) > 0, Done);
  Assert.IsTrue(StartsStr('Neue Methode: procedure TFoo.HandleClick(Sender: TObject);', Converted.Preview),
    Converted.Preview);
  Assert.AreEqual(0, Integer(Length(Converted.Warnings)));
end;

procedure TAnonymousMethodsTests.SynchronousCapturesBecomeParameters;
var
  Text, Reason, Done: string;
  Target: TAnonymousTarget;
  Converted: TAnonymousResult;
begin
  Text := ClassUnit(Lines(['    procedure Run(AFactor: Integer);']), Lines([
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
  Assert.IsTrue(TargetAt(Text, 'procedure(const AItem', TDeferredCapture.Fields, Target, Reason), Reason);
  Assert.AreEqual('ProcessItem', Target.Suggested);
  // Synchron: auch mit fields bleibt es bei Parametern.
  Assert.AreEqual(Ord(TAnonymousForm.Forwarding), Ord(Target.Form));
  Assert.IsTrue(ConvertAt(Text, 'procedure(const AItem', 'ProcessItem', TDeferredCapture.Fields, Converted, Reason,
    Done), Reason);
  Assert.IsTrue(Pos(Lines([
    '  FList.ForEach(procedure(const AItem: Integer)',
    '    begin',
    '      ProcessItem(AItem, LSum, AFactor, LName);',
    '    end);']), Done) > 0, Done);
  // Log ist unbekannt: LName könnte ein var-Argument sein.
  Assert.IsTrue(Pos('procedure TFoo.ProcessItem(const AItem: Integer; var LSum: Integer; AFactor: Integer; ' +
    'var LName: string);', Done) > 0, Done);
  Assert.IsTrue(Pos(Lines([
    'begin',
    '  LSum := LSum + AItem * AFactor;',
    '  Log(LName);',
    'end;']), Done) > 0, Done);
  Assert.IsTrue(Pos('ForEach', Converted.Preview) > 0, Converted.Preview);
end;

procedure TAnonymousMethodsTests.DeferredKeepsForwarding;
var
  Text, Reason, Done: string;
  Target: TAnonymousTarget;
  Converted: TAnonymousResult;
begin
  Text := ClassUnit(Lines(['    procedure Run;', '    procedure Log(const AText: string);']), Lines([
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
  Assert.IsTrue(TargetAt(Text, 'procedure' + LF + '    begin', TDeferredCapture.Forward, Target, Reason), Reason);
  Assert.AreEqual('UpdateInMainThread', Target.Suggested);
  Assert.AreEqual(Ord(TAnonymousForm.Forwarding), Ord(Target.Form));
  Assert.IsTrue(ConvertAt(Text, 'procedure' + LF + '    begin', 'ZeigeFertig', TDeferredCapture.Forward, Converted,
    Reason, Done), Reason);
  Assert.IsTrue(Pos(Lines([
    '  TThread.Queue(nil,',
    '    procedure',
    '    begin',
    '      ZeigeFertig(LText);',
    '    end);']), Done) > 0, Done);
  // Log hat eine Signatur in der Datei: LText wird nur gelesen.
  Assert.IsTrue(Pos('    procedure ZeigeFertig(const LText: string);', Done) > 0, Done);
  Assert.IsTrue(Pos('Weiterleitung', Converted.Preview) > 0, Converted.Preview);
end;

procedure TAnonymousMethodsTests.DeferredFieldsCopyValues;
var
  Text, Reason, Done: string;
  Converted: TAnonymousResult;
begin
  Text := ClassUnit(Lines(['    procedure Run;', '    procedure Log(const AText: string);']), Lines([
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
  Assert.IsTrue(ConvertAt(Text, 'procedure' + LF + '    begin', 'ZeigeFertig', TDeferredCapture.Fields, Converted,
    Reason, Done), Reason);
  Assert.AreEqual(Ord(TAnonymousForm.Fields), Ord(Converted.Form));
  Assert.IsTrue(Pos(Lines(['  FText := LText;', '  TThread.Queue(nil,', '    ZeigeFertig);']), Done) > 0, Done);
  Assert.IsTrue(Pos(Lines(['    FCount: Integer;', '    FText: string;']), Done) > 0, Done);
  Assert.IsTrue(Pos('    procedure ZeigeFertig;', Done) > 0, Done);
  Assert.IsTrue(Pos(Lines(['procedure TFoo.ZeigeFertig;', 'begin', '  Log(FText);', 'end;']), Done) > 0, Done);
  Assert.AreEqual(1, Integer(Length(Converted.Warnings)));
end;

procedure TAnonymousMethodsTests.FieldsFallBackWhenWritten;
var
  Text, Reason, Done: string;
  Converted: TAnonymousResult;
begin
  Text := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    'var',
    '  LDone: Boolean;',
    'begin',
    '  LDone := False;',
    '  FTask := TTask.Run(procedure begin LDone := True; end);',
    'end;']));
  Assert.IsTrue(ConvertAt(Text, 'procedure begin', 'Arbeite', TDeferredCapture.Fields, Converted, Reason, Done),
    Reason);
  Assert.AreEqual(Ord(TAnonymousForm.Forwarding), Ord(Converted.Form));
  Assert.IsTrue(Pos('  FTask := TTask.Run(procedure begin Arbeite(LDone); end);', Done) > 0, Done);
  Assert.IsTrue(Pos('    procedure Arbeite(var LDone: Boolean);', Done) > 0, Done);
  Assert.IsTrue(Pos('schreibt', Converted.Preview) > 0, Converted.Preview);
end;

procedure TAnonymousMethodsTests.ComparerSuggestsCompareBy;
var
  Text, Reason, Done: string;
  Target: TAnonymousTarget;
  Converted: TAnonymousResult;
begin
  Text := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  FList.Sort(TComparer<TKunde>.Construct(',
    '    function(const A, B: TKunde): Integer',
    '    begin',
    '      Result := CompareText(A.Name, B.Name);',
    '    end));',
    'end;']));
  Assert.IsTrue(TargetAt(Text, 'function(const A', TDeferredCapture.Forward, Target, Reason), Reason);
  Assert.AreEqual('CompareByName', Target.Suggested);
  Assert.AreEqual(Ord(TAnonymousForm.Direct), Ord(Target.Form));
  Assert.IsTrue(ConvertAt(Text, 'function(const A', 'CompareByName', TDeferredCapture.Forward, Converted, Reason,
    Done), Reason);
  Assert.IsTrue(Pos(Lines(['  FList.Sort(TComparer<TKunde>.Construct(', '    CompareByName));']), Done) > 0, Done);
  Assert.IsTrue(Pos('    function CompareByName(const A: TKunde; const B: TKunde): Integer;', Done) > 0, Done);
  Assert.IsTrue(Pos(Lines(['function TFoo.CompareByName(const A: TKunde; const B: TKunde): Integer;', 'begin',
    '  Result := CompareText(A.Name, B.Name);', 'end;']), Done) > 0, Done);
end;

procedure TAnonymousMethodsTests.FreeRoutineBecomesUnitRoutine;
var
  Text, Reason, Done: string;
  Target: TAnonymousTarget;
  Converted: TAnonymousResult;
begin
  Text := PlainUnit(Lines([
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
  Assert.IsTrue(TargetAt(Text, 'procedure(I', TDeferredCapture.Forward, Target, Reason), Reason);
  Assert.IsFalse(Target.IsMethod);
  Assert.AreEqual('ProcessIndex', Target.Suggested);
  Assert.AreEqual('In Routine umwandeln (ProcessIndex)', Target.Title);
  Assert.IsTrue(ConvertAt(Text, 'procedure(I', 'ProcessIndex', TDeferredCapture.Forward, Converted, Reason, Done),
    Reason);
  Assert.IsTrue(Pos(Lines([
    'procedure ProcessIndex(I: Integer; const AWerte: TArray<Integer>; var LAnzahl: Integer);',
    'const',
    '  Grenze = 10;',
    'begin',
    '  if AWerte[I] > Grenze then',
    '    TInterlocked.Increment(LAnzahl);',
    'end;',
    '',
    'procedure Zaehle(const AWerte: TArray<Integer>);']), Done) > 0, Done);
  Assert.IsTrue(Pos('      ProcessIndex(I, AWerte, LAnzahl);', Done) > 0, Done);
  Assert.IsTrue(StartsStr('Neue Routine: ', Converted.Preview), Converted.Preview);
end;

procedure TAnonymousMethodsTests.ClassMethodStaysClassMethod;
var
  Text, Reason, Done: string;
  Converted: TAnonymousResult;
begin
  Text := ClassUnit(Lines(['    class procedure Run; static;']), Lines([
    'class procedure TFoo.Run;',
    'begin',
    '  TThread.Synchronize(nil, procedure begin Beep; end);',
    'end;']));
  Assert.IsTrue(ConvertAt(Text, 'procedure begin', 'Piepe', TDeferredCapture.Fields, Converted, Reason, Done),
    Reason);
  Assert.IsTrue(Pos('  TThread.Synchronize(nil, Piepe);', Done) > 0, Done);
  Assert.IsTrue(Pos('    class procedure Piepe; static;', Done) > 0, Done);
  Assert.IsTrue(Pos('class procedure TFoo.Piepe;', Done) > 0, Done);
end;

procedure TAnonymousMethodsTests.RefusesChangedMeaning;
var
  Text, Reason: string;
  Target: TAnonymousTarget;
begin
  // Result der äußeren Funktion.
  Text := ClassUnit(Lines(['    function Run: Integer;']), Lines([
    'function TFoo.Run: Integer;',
    'begin',
    '  FList.ForEach(procedure(const AItem: Integer) begin Result := AItem; end);',
    'end;']));
  Assert.IsFalse(TargetAt(Text, 'procedure(const', TDeferredCapture.Forward, Target, Reason));
  Assert.IsTrue(Pos('Result', Reason) > 0, Reason);
  // Lokale Routine der äußeren.
  Text := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    '  procedure Hilfe;',
    '  begin',
    '  end;',
    'begin',
    '  FList.ForEach(procedure(const AItem: Integer) begin Hilfe; end);',
    'end;']));
  Assert.IsFalse(TargetAt(Text, 'procedure(const', TDeferredCapture.Forward, Target, Reason));
  Assert.IsTrue(Pos('Hilfe', Reason) > 0, Reason);
  // In einer lokalen Routine.
  Text := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    '  procedure Hilfe;',
    '  begin',
    '    FList.ForEach(procedure(const AItem: Integer) begin FCount := AItem; end);',
    '  end;',
    'begin',
    '  Hilfe;',
    'end;']));
  Assert.IsFalse(TargetAt(Text, 'procedure(const', TDeferredCapture.Forward, Target, Reason));
  // Verschachtelte anonyme Methode schreibt eine Variable, die var-Parameter würde.
  Text := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    'var',
    '  LSum: Integer;',
    'begin',
    '  FList.ForEach(procedure(const AItem: Integer)',
    '    begin',
    '      FOther.ForEach(procedure(const AInner: Integer) begin LSum := AInner; end);',
    '    end);',
    'end;']));
  Assert.IsFalse(TargetAt(Text, 'procedure(const AItem', TDeferredCapture.Forward, Target, Reason));
  Assert.IsTrue(Pos('LSum', Reason) > 0, Reason);
  // Auf dem Rumpf statt auf dem Kopf: nichts.
  Assert.IsFalse(TargetAt(Text, 'begin' + LF + '      FOther', TDeferredCapture.Forward, Target, Reason));
end;

procedure TAnonymousMethodsTests.NameIsChecked;
var
  Text, Reason, Done: string;
  Target: TAnonymousTarget;
  Converted: TAnonymousResult;
begin
  Text := ClassUnit(Lines(['    procedure Run;', '    procedure HandleClick;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  Button.OnClick := procedure(Sender: TObject) begin FCount := 1; end;',
    'end;',
    '',
    'procedure TFoo.HandleClick;',
    'begin',
    'end;']));
  // Vergeben: Vorschlag mit Nummer, Ausführen mit dem Namen ein Fehler.
  Assert.IsTrue(TargetAt(Text, 'procedure(Sender', TDeferredCapture.Forward, Target, Reason), Reason);
  Assert.AreEqual('HandleClick2', Target.Suggested);
  Assert.IsFalse(ConvertAt(Text, 'procedure(Sender', 'HandleClick', TDeferredCapture.Forward, Converted, Reason,
    Done));
  Assert.IsTrue(Pos('vergeben', Reason) > 0, Reason);
  Assert.IsFalse(ConvertAt(Text, 'procedure(Sender', 'begin', TDeferredCapture.Forward, Converted, Reason, Done));
  Assert.IsFalse(ConvertAt(Text, 'procedure(Sender', 'Sender', TDeferredCapture.Forward, Converted, Reason, Done));
end;

procedure TAnonymousMethodsTests.EmbedSingleValueUse;
var
  Text, Reason, Done: string;
  Action: TCodeAction;
begin
  Text := ClassUnit(Lines(['    procedure Run;', '    procedure ProcessItem(const AItem: Integer);']), Lines([
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
  Assert.IsTrue(EmbedAt(Text, 'ProcessItem(const AItem: Integer);' + LF + 'var', TProcTypeKind.Reference, Action,
    Reason, Done), Reason);
  Assert.AreEqual(TAnonymousMethods.EmbedTitle, Action.Title);
  Assert.IsTrue(Pos(Lines([
    '  FList.ForEach(procedure(const AItem: Integer)',
    '    var',
    '      LDoppelt: Integer;',
    '    begin',
    '      LDoppelt := AItem * 2;',
    '      FCount := FCount + LDoppelt;',
    '    end);',
    'end;']), Done) > 0, Done);
  Assert.IsFalse(ContainsStr(Done, 'TFoo.ProcessItem'), Done);
  Assert.IsFalse(ContainsStr(Done, 'Zaehlt mit'), Done);
  Assert.IsFalse(ContainsStr(Done, '    procedure ProcessItem'), Done);
  Assert.IsTrue(Action.Preview <> '');
  // Auch von der Deklaration in der Klasse aus.
  Assert.IsTrue(EmbedAt(Text, 'ProcessItem(const AItem: Integer);' + LF + '  end;', TProcTypeKind.Reference, Action,
    Reason, Done), Reason);
end;

procedure TAnonymousMethodsTests.EmbedRefusals;
var
  Text, Reason, Done: string;
  Action: TCodeAction;
  Tree: TSyntaxTree;
  Lookup: TAnonymousLookup;
begin
  Text := ClassUnit(Lines(['    procedure Run;', '    procedure Tick(Sender: TObject);']), Lines([
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
  Assert.IsFalse(EmbedAt(Text, 'TFoo.Tick', TProcTypeKind.MethodPointer, Action, Reason, Done));
  Assert.IsTrue(Pos('of object', Reason) > 0, Reason);
  Assert.IsFalse(EmbedAt(Text, 'TFoo.Tick', TProcTypeKind.Unknown, Action, Reason, Done));
  // In der Formulardatei.
  Tree := TPascalParser.Parse(Text);
  try
    Lookup := LookupFor(Tree, TProcTypeKind.Reference);
    Lookup.InForm :=
      function(const AName: string): Boolean
      begin
        Result := SameText(AName, 'Tick');
      end;
    Assert.IsFalse(TAnonymousMethods.Embed(Text, Tree, PositionOf(Text, 'TFoo.Tick'), Lookup, TFormatStyle.Default,
      Action, Reason));
    Assert.IsTrue(Pos('Formulardatei', Reason) > 0, Reason);
  finally
    Tree.Free;
  end;
  // Direkt aufgerufen.
  Text := ClassUnit(Lines(['    procedure Run;', '    procedure Tick;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  Tick;',
    'end;',
    '',
    'procedure TFoo.Tick;',
    'begin',
    'end;']));
  Assert.IsFalse(EmbedAt(Text, 'TFoo.Tick', TProcTypeKind.Reference, Action, Reason, Done));
  // Zweimal übergeben.
  Text := ClassUnit(Lines(['    procedure Run;', '    procedure Tick;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  TThread.Queue(nil, Tick);',
    '  TThread.Queue(nil, Tick);',
    'end;',
    '',
    'procedure TFoo.Tick;',
    'begin',
    'end;']));
  Assert.IsFalse(EmbedAt(Text, 'TFoo.Tick', TProcTypeKind.Reference, Action, Reason, Done));
  Assert.IsTrue(Pos('genau eine', Reason) > 0, Reason);
  // Öffentlich.
  Text := ClassUnit(Lines(['  public', '    procedure Run;', '    procedure Tick;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  TThread.Queue(nil, Tick);',
    'end;',
    '',
    'procedure TFoo.Tick;',
    'begin',
    'end;']));
  Assert.IsFalse(EmbedAt(Text, 'TFoo.Tick', TProcTypeKind.Reference, Action, Reason, Done));
  // Ein lokaler Name des Aufrufers verdeckte FCount.
  Text := ClassUnit(Lines(['    procedure Run;', '    procedure Tick;']), Lines([
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
  Assert.IsFalse(EmbedAt(Text, 'TFoo.Tick', TProcTypeKind.Reference, Action, Reason, Done));
  Assert.IsTrue(Pos('FCount', Reason) > 0, Reason);
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
  Text, Reason, Done, Back: string;
  Converted: TAnonymousResult;
  Action: TCodeAction;
begin
  Text := ClassUnit(Lines(['    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  FList.ForEach(procedure(const AItem: Integer)',
    '    begin',
    '      FCount := FCount + AItem;',
    '    end);',
    'end;']));
  Assert.IsTrue(ConvertAt(Text, 'procedure(const', 'ProcessItem', TDeferredCapture.Forward, Converted, Reason, Done),
    Reason);
  Assert.IsTrue(EmbedAt(Done, 'TFoo.ProcessItem', TProcTypeKind.Reference, Action, Reason, Back), Reason);
  Assert.AreEqual(Text, Back);
end;

initialization
  TDUnitX.RegisterTestFixture(TAnonymousMethodsTests);

end.
