unit Atlas.Common.Editing.MethodWithoutSelf.Tests;

// Tests für „Methode ohne Self umwandeln“ (#686): Erkennung samt
// Gegenbeispielen (impliziter Zugriff auf ein Feld, Self, virtuelle Methode,
// Ereignis in der Formulardatei, Interface, Methodenzeiger), class-Methode
// mit und ohne static, Aufrufe über die Klasse, freie Routine (Aufrufe in
// zwei Units, uses, Klassenmitglieder qualifiziert, vor den ersten Aufrufer
// verschoben), Record-Helper samt Warnung bei sichtbarem Helper.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMethodWithoutSelfTests = class
  public
    [Test]
    procedure DetectsMethodWithoutSelf;
    [Test]
    procedure ImplicitFieldIsNoCandidate;
    [Test]
    procedure VirtualFormAndInterfaceAreNoCandidates;
    [Test]
    procedure MethodPointerIsNoCandidate;
    [Test]
    procedure ClassMethodWithStatic;
    [Test]
    procedure ClassMethodCallsOverClass;
    [Test]
    procedure RoutineAcrossUnits;
    [Test]
    procedure RoutineMovesBeforeFirstCaller;
    [Test]
    procedure RoutineQualifiesClassMembers;
    [Test]
    procedure HelperAcrossUnits;
    [Test]
    procedure HelperWarnsAboutVisibleHelper;
    [Test]
    procedure RecordAndExistingHelper;
    [Test]
    procedure CandidatesAndNames;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.MethodWithoutSelf;

const
  Kunden =
    'unit Kunden;'#10 +                                                  // 0
    'interface'#10 +                                                     // 1
    'uses System.SysUtils;'#10 +                                         // 2
    'type'#10 +                                                          // 3
    '  TKunde = class'#10 +                                              // 4
    '  private'#10 +                                                     // 5
    '    FName: string;'#10 +                                            // 6
    '  public'#10 +                                                      // 7
    '    function IsValidIban(const S: string; N: Integer): Boolean;'#10 + // 8
    '    procedure Zeige;'#10 +                                          // 9
    '  end;'#10 +                                                        // 10
    'implementation'#10 +                                                // 11
    'procedure TKunde.Zeige;'#10 +                                       // 12
    'begin'#10 +                                                         // 13
    '  if IsValidIban(FName, 2) then'#10 +                               // 14
    '    FName := '''';'#10 +                                            // 15
    'end;'#10 +                                                          // 16
    'function TKunde.IsValidIban(const S: string; N: Integer): Boolean;'#10 + // 17
    'begin'#10 +                                                         // 18
    '  Result := Length(S) > N;'#10 +                                    // 19
    'end;'#10 +                                                          // 20
    'end.'#10;

  Aufrufer =
    'unit Aufrufer;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Kunden;'#10 +
    'procedure Pruefe(K: TKunde; const T: string);'#10 +
    'begin'#10 +
    '  if K.IsValidIban(T + ''x'', 3) then'#10 +
    '    Exit;'#10 +
    'end;'#10 +
    'end.'#10;

/// <summary>Anfänge der Bezeichner AName in AText wie aus der Referenzsuche: ohne gleichnamige Routinen der Unit
/// (Name direkt hinter function bzw. procedure).</summary>
function OffsetsOf(ATree: TSyntaxTree; const AName: string): TArray<Integer>;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
begin
  Result := nil;
  Tokens := ATree.Tokens;
  for Index := 0 to High(Tokens) do
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) and
      not ((Index > 0) and (Tokens[Index - 1].IsKeyword('function') or Tokens[Index - 1].IsKeyword('procedure'))) then
      Result := Result + [Tokens[Index].Offset];
end;

function EditsOf(const AResult: TMethodResult; const AFileName: string): TArray<TTextEdit>;
var
  Item: TMethodFileEdits;
begin
  Result := nil;
  for Item in AResult.Files do
    if SameText(Item.FileName, AFileName) then
      Exit(Item.Edits);
end;

/// <summary>Wandelt die Methode an ALine/ACharacter in ADeclaring um; AOther (oder '') ruft auf.</summary>
function Convert(const ADeclaring, AOther: string; ALine, ACharacter: Integer; AConversion: TMethodConversion;
  AStatic, AHelperLookup: Boolean; out ANewDeclaring, ANewOther: string;
  out AResult: TMethodResult; out AReason: string): Boolean;
var
  Tree, OtherTree: TSyntaxTree;
  Others: TArray<TMethodSource>;
  Lookup: TMethodLookup;
begin
  Tree := TPascalParser.Parse(ADeclaring);
  OtherTree := nil;
  try
    Lookup := TMethodLookup.FromTree(Tree);
    if not AHelperLookup then
      Lookup.VisibleHelper := nil;
    Others := nil;
    if AOther <> '' then
    begin
      OtherTree := TPascalParser.Parse(AOther);
      Others := [TMethodSource.Create('C:\P\Aufrufer.pas', AOther, OtherTree, OffsetsOf(OtherTree,
        'IsValidIban'))];
    end;
    Result := TMethodWithoutSelf.Execute(TMethodSource.Create('C:\P\Kunden.pas', ADeclaring, Tree,
      OffsetsOf(Tree, 'IsValidIban')), Others, TTextPosition.Create(ALine, ACharacter), AConversion, AStatic,
      Lookup, TFormatStyle.Default, AResult, AReason);
    ANewDeclaring := ADeclaring;
    ANewOther := AOther;
    if Result then
    begin
      ANewDeclaring := TChangeSignature.ApplyEdits(ADeclaring, EditsOf(AResult, 'C:\P\Kunden.pas'));
      ANewOther := TChangeSignature.ApplyEdits(AOther, EditsOf(AResult, 'C:\P\Aufrufer.pas'));
    end;
  finally
    OtherTree.Free;
    Tree.Free;
  end;
end;

procedure TMethodWithoutSelfTests.DetectsMethodWithoutSelf;
var
  Target: TMethodTarget;
  Reason: string;
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Kunden);
  try
    // Auf dem Kopf der Implementierung und der Deklaration.
    Assert.IsTrue(TMethodWithoutSelf.Target(Kunden, Tree, TTextPosition.Create(17, 20),
      TMethodLookup.FromTree(Tree), Target, Reason), Reason);
    Assert.AreEqual('TKunde', Target.ClassName);
    Assert.AreEqual('IsValidIban', Target.Name);
    Assert.AreEqual(4, Integer(Length(Target.Conversions)), Target.RoutineReason + '|' + Target.HelperReason);
    Assert.AreEqual('string', Target.HelperType);
    Assert.AreEqual(17, Target.NamePosition.Line);
    Assert.AreEqual(16, Target.NamePosition.Character);
    Assert.IsTrue(TMethodWithoutSelf.Target(Kunden, Tree, TTextPosition.Create(8, 15),
      TMethodLookup.FromTree(Tree), Target, Reason), Reason);
    Assert.AreEqual('In Record-Helper für string verschieben', Target.Title(TMethodConversion.Helper));
    // Zeige ruft die Instanzmethode IsValidIban auf (und benutzt FName).
    Assert.IsFalse(TMethodWithoutSelf.Target(Kunden, Tree, TTextPosition.Create(12, 20),
      TMethodLookup.FromTree(Tree), Target, Reason));
    Assert.IsTrue(Pos('IsValidIban', Reason) > 0, Reason);
  finally
    Tree.Free;
  end;
end;

procedure TMethodWithoutSelfTests.ImplicitFieldIsNoCandidate;
const
  Source =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TA = class'#10 +
    '    FWert: Integer;'#10 +
    '    function Mal(N: Integer): Integer;'#10 +
    '    function Selbst: TA;'#10 +
    '    function Anderes(N: Integer): Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TA.Mal(N: Integer): Integer;'#10 +             // 10
    'begin'#10 +
    '  Result := N * FWert;'#10 +
    'end;'#10 +
    'function TA.Selbst: TA;'#10 +                           // 14
    'begin'#10 +
    '  Result := Self;'#10 +
    'end;'#10 +
    'function TA.Anderes(N: Integer): Integer;'#10 +         // 18
    'var'#10 +
    '  FWert: Integer;'#10 +
    'begin'#10 +
    '  FWert := N;'#10 +
    '  Result := FWert;'#10 +
    'end;'#10 +
    'end.'#10;
var
  Target: TMethodTarget;
  Reason: string;
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Assert.IsFalse(TMethodWithoutSelf.Target(Source, Tree, TTextPosition.Create(10, 13),
      TMethodLookup.FromTree(Tree), Target, Reason));
    Assert.IsTrue(Pos('FWert', Reason) > 0, Reason);
    Assert.IsFalse(TMethodWithoutSelf.Target(Source, Tree, TTextPosition.Create(14, 13),
      TMethodLookup.FromTree(Tree), Target, Reason));
    Assert.IsTrue(Pos('Self', Reason) > 0, Reason);
    // Die lokale Variable verdeckt das Feld.
    Assert.IsTrue(TMethodWithoutSelf.Target(Source, Tree, TTextPosition.Create(18, 13),
      TMethodLookup.FromTree(Tree), Target, Reason), Reason);
  finally
    Tree.Free;
  end;
end;

procedure TMethodWithoutSelfTests.VirtualFormAndInterfaceAreNoCandidates;
const
  Source =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  IPruefer = interface'#10 +
    '    function Pruefe(N: Integer): Boolean;'#10 +
    '  end;'#10 +
    '  TA = class(TInterfacedObject, IPruefer)'#10 +
    '    function Pruefe(N: Integer): Boolean;'#10 +
    '    function Virtuell(N: Integer): Boolean; virtual;'#10 +
    '    procedure Knopf(Sender: TObject);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TA.Pruefe(N: Integer): Boolean;'#10 +          // 12
    'begin'#10 +
    '  Result := N > 0;'#10 +
    'end;'#10 +
    'function TA.Virtuell(N: Integer): Boolean;'#10 +        // 16
    'begin'#10 +
    '  Result := N > 0;'#10 +
    'end;'#10 +
    'procedure TA.Knopf(Sender: TObject);'#10 +              // 20
    'begin'#10 +
    'end;'#10 +
    'end.'#10;
var
  Target: TMethodTarget;
  Reason: string;
  Tree: TSyntaxTree;
  Lookup: TMethodLookup;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Lookup := TMethodLookup.FromTree(Tree);
    Assert.IsFalse(TMethodWithoutSelf.Target(Source, Tree, TTextPosition.Create(12, 13), Lookup, Target, Reason));
    Assert.IsTrue(Pos('IPruefer', Reason) > 0, Reason);
    Assert.IsFalse(TMethodWithoutSelf.Target(Source, Tree, TTextPosition.Create(16, 13), Lookup, Target, Reason));
    Assert.IsTrue(Pos('virtuell', Reason) > 0, Reason);
    Lookup.InForm :=
      function(const AName: string): Boolean
      begin
        Result := SameText(AName, 'Knopf');
      end;
    Assert.IsFalse(TMethodWithoutSelf.Target(Source, Tree, TTextPosition.Create(20, 14), Lookup, Target, Reason));
    Assert.IsTrue(Pos('Formulardatei', Reason) > 0, Reason);
  finally
    Tree.Free;
  end;
end;

procedure TMethodWithoutSelfTests.MethodPointerIsNoCandidate;
const
  Source =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TA = class'#10 +
    '    FOnTick: TNotifyEvent;'#10 +
    '    procedure Tick(Sender: TObject);'#10 +
    '    procedure Start;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TA.Tick(Sender: TObject);'#10 +               // 9
    'begin'#10 +
    'end;'#10 +
    'procedure TA.Start;'#10 +
    'begin'#10 +
    '  FOnTick := Tick;'#10 +
    'end;'#10 +
    'end.'#10;
var
  Target: TMethodTarget;
  Reason: string;
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Assert.IsFalse(TMethodWithoutSelf.Target(Source, Tree, TTextPosition.Create(9, 14),
      TMethodLookup.FromTree(Tree), Target, Reason));
    Assert.IsTrue(Pos('Methodenzeiger', Reason) > 0, Reason);
  finally
    Tree.Free;
  end;
end;

procedure TMethodWithoutSelfTests.ClassMethodWithStatic;
var
  Declaring, Other, Reason: string;
  Converted: TMethodResult;
begin
  Assert.IsTrue(Convert(Kunden, Aufrufer, 17, 20, TMethodConversion.ClassMethod, True, True, Declaring, Other,
    Converted, Reason), Reason);
  Assert.IsTrue(Pos('    class function IsValidIban(const S: string; N: Integer): Boolean; static;'#10, Declaring) > 0,
    Declaring);
  Assert.IsTrue(Pos('class function TKunde.IsValidIban(const S: string; N: Integer): Boolean;', Declaring) > 0,
    Declaring);
  // Aufrufe über Instanzen bleiben.
  Assert.AreEqual(Aufrufer, Other);
  Assert.AreEqual(0, Converted.Calls);
  Assert.IsTrue(Pos('wird class-Methode', Converted.Preview) > 0, Converted.Preview);
  // Ohne static.
  Assert.IsTrue(Convert(Kunden, '', 17, 20, TMethodConversion.ClassMethod, False, True, Declaring, Other,
    Converted, Reason), Reason);
  Assert.IsTrue(Pos('class function IsValidIban(const S: string; N: Integer): Boolean;'#10, Declaring) > 0,
    Declaring);
  Assert.IsFalse(Pos('static', Declaring) > 0, Declaring);
end;

procedure TMethodWithoutSelfTests.ClassMethodCallsOverClass;
const
  Fremd =
    'unit Aufrufer;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Fabrik;'#10 +
    'procedure Pruefe(const T: string);'#10 +
    'begin'#10 +
    '  if Neu.IsValidIban(T, 3) and Liste[1].IsValidIban(T, 1) then'#10 +
    '    Exit;'#10 +
    'end;'#10 +
    'end.'#10;
var
  Declaring, Other, Reason: string;
  Converted: TMethodResult;
begin
  Assert.IsTrue(Convert(Kunden, Fremd, 17, 20, TMethodConversion.ClassMethodCalls, True, True, Declaring, Other,
    Converted, Reason), Reason);
  // Neu und Liste[1] sind Variablenketten: beide über die Klasse, Kunden ins uses.
  Assert.IsTrue(Pos('TKunde.IsValidIban(T, 3) and TKunde.IsValidIban(T, 1)', Other) > 0, Other);
  Assert.IsTrue(Pos('uses Fabrik, Kunden;', Other) > 0, Other);
  Assert.AreEqual(2, Converted.Calls);
  Assert.IsTrue(Pos('Aufrufer.pas, Zeile 7: if Neu.IsValidIban(T, 3)', Converted.Preview) > 0, Converted.Preview);
end;

procedure TMethodWithoutSelfTests.RoutineAcrossUnits;
const
  Fremd =
    'unit Aufrufer;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Kunden;'#10 +
    'function IsValidIban(const S: string): Boolean;'#10 +
    'begin'#10 +
    '  Result := False;'#10 +
    'end;'#10 +
    'procedure Pruefe(K: TKunde; const T: string);'#10 +
    'begin'#10 +
    '  if K.IsValidIban(T, 3) or GetKunde().IsValidIban(T, 4) then'#10 +
    '    Exit;'#10 +
    'end;'#10 +
    'end.'#10;
var
  Declaring, Other, Reason: string;
  Converted: TMethodResult;
begin
  Assert.IsTrue(Convert(Kunden, Fremd, 17, 20, TMethodConversion.Routine, True, True, Declaring, Other,
    Converted, Reason), Reason);
  // Aus der Klasse heraus, ins interface vor implementation, Kopf ohne Klasse.
  Assert.IsFalse(Pos('    function IsValidIban', Declaring) > 0, Declaring);
  Assert.IsTrue(Pos('  end;'#10'function IsValidIban(const S: string; N: Integer): Boolean;'#10#10'implementation',
    Declaring) > 0, Declaring);
  Assert.IsTrue(Pos(#10'function IsValidIban(const S: string; N: Integer): Boolean;'#10'begin', Declaring) > 0,
    Declaring);
  // Der Aufrufer der eigenen Unit bleibt, der fremde qualifiziert (eigene IsValidIban dort).
  Assert.IsTrue(Pos('if IsValidIban(FName, 2) then', Declaring) > 0, Declaring);
  Assert.IsTrue(Pos('if Kunden.IsValidIban(T, 3) or Kunden.IsValidIban(T, 4) then', Other) > 0, Other);
  Assert.AreEqual(1, Integer(Length(Converted.Warnings)), string.Join('|', Converted.Warnings));
  Assert.IsTrue(Pos('GetKunde() wird nicht mehr ausgewertet', Converted.Warnings[0]) > 0, Converted.Warnings[0]);
  Assert.AreEqual(2, Converted.Calls);
end;

procedure TMethodWithoutSelfTests.RoutineMovesBeforeFirstCaller;
var
  Declaring, Other, Reason: string;
  Converted: TMethodResult;
begin
  // Ohne fremde Aufrufer: nur implementation, vor TKunde.Zeige.
  Assert.IsTrue(Convert(Kunden, '', 17, 20, TMethodConversion.Routine, True, True, Declaring, Other, Converted,
    Reason), Reason);
  Assert.AreEqual(
    'unit Kunden;'#10 +
    'interface'#10 +
    'uses System.SysUtils;'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    procedure Zeige;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function IsValidIban(const S: string; N: Integer): Boolean;'#10 +
    'begin'#10 +
    '  Result := Length(S) > N;'#10 +
    'end;'#10 +
    #10 +
    'procedure TKunde.Zeige;'#10 +
    'begin'#10 +
    '  if IsValidIban(FName, 2) then'#10 +
    '    FName := '''';'#10 +
    'end;'#10 +
    'end.'#10, Declaring);
end;

procedure TMethodWithoutSelfTests.RoutineQualifiesClassMembers;
const
  Source =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TA = class'#10 +
    '  private const'#10 +
    '    Max = 3;'#10 +
    '  strict private'#10 +
    '    class var FZaehler: Integer;'#10 +
    '  public'#10 +
    '    function Grenze(N: Integer): Integer;'#10 +
    '    function Zaehle(N: Integer): Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TA.Grenze(N: Integer): Integer;'#10 +          // 13
    'begin'#10 +
    '  Result := N + Max;'#10 +
    'end;'#10 +
    'function TA.Zaehle(N: Integer): Integer;'#10 +          // 17
    'begin'#10 +
    '  Result := N + FZaehler;'#10 +
    'end;'#10 +
    'end.'#10;
var
  Tree: TSyntaxTree;
  Lookup: TMethodLookup;
  Target: TMethodTarget;
  Converted: TMethodResult;
  Reason, Text: string;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Lookup := TMethodLookup.FromTree(Tree);
    Assert.IsTrue(TMethodWithoutSelf.Execute(TMethodSource.Create('C:\P\U.pas', Source, Tree, nil), nil,
      TTextPosition.Create(13, 13), TMethodConversion.Routine, True, Lookup, TFormatStyle.Default, Converted,
      Reason), Reason);
    Text := TChangeSignature.ApplyEdits(Source, Converted.Files[0].Edits);
    Assert.IsTrue(Pos('  Result := N + TA.Max;', Text) > 0, Text);
    Assert.IsTrue(Pos(#10'function Grenze(N: Integer): Integer;'#10, Text) > 0, Text);
    // strict private: nur class-Methode und Helper.
    Assert.IsTrue(TMethodWithoutSelf.Target(Source, Tree, TTextPosition.Create(17, 13), Lookup, Target, Reason),
      Reason);
    Assert.IsTrue(Pos('FZaehler', Target.RoutineReason) > 0, Target.RoutineReason);
    Assert.AreEqual(2, Integer(Length(Target.Conversions)));
    Assert.IsTrue(TMethodWithoutSelf.Execute(TMethodSource.Create('C:\P\U.pas', Source, Tree, nil), nil,
      TTextPosition.Create(17, 13), TMethodConversion.ClassMethod, True, Lookup, TFormatStyle.Default, Converted,
      Reason), Reason);
    Text := TChangeSignature.ApplyEdits(Source, Converted.Files[0].Edits);
    Assert.IsTrue(Pos('    class function Zaehle(N: Integer): Integer; static;', Text) > 0, Text);
  finally
    Tree.Free;
  end;
end;

procedure TMethodWithoutSelfTests.HelperAcrossUnits;
var
  Declaring, Other, Reason: string;
  Converted: TMethodResult;
begin
  Assert.IsTrue(Convert(Kunden, Aufrufer, 17, 20, TMethodConversion.Helper, True, False, Declaring, Other,
    Converted, Reason), Reason);
  Assert.IsTrue(Pos(
    '  end;'#10#10 +
    '  TStringHelper = record helper for string'#10 +
    '    function IsValidIban(N: Integer): Boolean;'#10 +
    '  end;'#10, Declaring) > 0, Declaring);
  Assert.IsTrue(Pos('function TStringHelper.IsValidIban(N: Integer): Boolean;'#10'begin'#10 +
    '  Result := Length(Self) > N;', Declaring) > 0, Declaring);
  Assert.IsTrue(Pos('if FName.IsValidIban(2) then', Declaring) > 0, Declaring);
  Assert.IsTrue(Pos('if (T + ''x'').IsValidIban(3) then', Other) > 0, Other);
  Assert.AreEqual(0, Integer(Length(Converted.Warnings)), string.Join('|', Converted.Warnings));
end;

procedure TMethodWithoutSelfTests.HelperWarnsAboutVisibleHelper;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TA = class'#10 +
    '    procedure Run;'#10 +
    '    function Doppelt(const S: string): string;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'uses System.SysUtils;'#10 +
    'procedure TA.Run;'#10 +
    'begin'#10 +
    '  Doppelt(''a'');'#10 +
    'end;'#10 +
    'function TA.Doppelt(const S: string): string;'#10 +     // 13
    'begin'#10 +
    '  Result := S + S;'#10 +
    'end;'#10 +
    'end.'#10;
var
  Tree: TSyntaxTree;
  Converted: TMethodResult;
  Reason, Text: string;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Assert.IsTrue(TMethodWithoutSelf.Execute(TMethodSource.Create('C:\P\Haupt.pas', Source, Tree, OffsetsOf(Tree,
      'Doppelt')), nil, TTextPosition.Create(13, 13), TMethodConversion.Helper, True, TMethodLookup.FromTree(Tree),
      TFormatStyle.Default, Converted, Reason), Reason);
    Text := TChangeSignature.ApplyEdits(Source, Converted.Files[0].Edits);
  finally
    Tree.Free;
  end;
  // Neuer Helper im implementation-Teil hinter dessen uses, mit dem Namen der Unit.
  Assert.IsTrue(Pos('uses System.SysUtils;'#10#10'type'#10'  THauptStringHelper = record helper for string'#10 +
    '    function Doppelt: string;'#10'  end;'#10, Text) > 0, Text);
  Assert.IsTrue(Pos('  (''a'').Doppelt;', Text) > 0, Text);
  Assert.IsTrue(Pos('Result := Self + Self;', Text) > 0, Text);
  Assert.AreEqual(1, Integer(Length(Converted.Warnings)));
  Assert.IsTrue(Pos('TStringHelper', Converted.Warnings[0]) > 0, Converted.Warnings[0]);
end;

procedure TMethodWithoutSelfTests.RecordAndExistingHelper;
const
  Source =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TPunkt = record'#10 +
    '    X: Integer;'#10 +
    '    function Doppelt(const A: Integer): Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'type'#10 +
    '  TZahlHelper = record helper for Integer'#10 +
    '    function Halb: Integer;'#10 +
    '  end;'#10 +
    'function TZahlHelper.Halb: Integer;'#10 +
    'begin'#10 +
    '  Result := Self div 2;'#10 +
    'end;'#10 +
    'function TPunkt.Doppelt(const A: Integer): Integer;'#10 +  // 16
    'begin'#10 +
    '  Result := A * 2;'#10 +
    'end;'#10 +
    'end.'#10;
var
  Tree: TSyntaxTree;
  Converted: TMethodResult;
  Reason, Text: string;
begin
  Tree := TPascalParser.Parse(Source);
  try
    // Records: class-Methoden sind immer static.
    Assert.IsTrue(TMethodWithoutSelf.Execute(TMethodSource.Create('C:\P\U.pas', Source, Tree, nil), nil,
      TTextPosition.Create(16, 16), TMethodConversion.ClassMethod, False, TMethodLookup.FromTree(Tree),
      TFormatStyle.Default, Converted, Reason), Reason);
    Text := TChangeSignature.ApplyEdits(Source, Converted.Files[0].Edits);
    Assert.IsTrue(Pos('    class function Doppelt(const A: Integer): Integer; static;', Text) > 0, Text);
    // Vorhandener Helper für Integer bekommt die Methode.
    Assert.IsTrue(TMethodWithoutSelf.Execute(TMethodSource.Create('C:\P\U.pas', Source, Tree, nil), nil,
      TTextPosition.Create(16, 16), TMethodConversion.Helper, False, TMethodLookup.FromTree(Tree),
      TFormatStyle.Default, Converted, Reason), Reason);
    Text := TChangeSignature.ApplyEdits(Source, Converted.Files[0].Edits);
  finally
    Tree.Free;
  end;
  Assert.IsTrue(Pos('    function Halb: Integer;'#10'    function Doppelt: Integer;'#10'  end;', Text) > 0, Text);
  Assert.IsTrue(Pos('function TZahlHelper.Doppelt: Integer;'#10'begin'#10'  Result := Self * 2;', Text) > 0, Text);
  Assert.IsFalse(Pos('TPunkt.Doppelt', Text) > 0, Text);
end;

procedure TMethodWithoutSelfTests.CandidatesAndNames;
var
  Tree: TSyntaxTree;
  Found: TArray<TMethodTarget>;
  Conversion, Parsed: TMethodConversion;
begin
  Tree := TPascalParser.Parse(Kunden);
  try
    Found := TMethodWithoutSelf.Candidates(Kunden, Tree, TMethodLookup.FromTree(Tree));
    Assert.AreEqual(1, Integer(Length(Found)));
    Assert.AreEqual('IsValidIban', Found[0].Name);
    Assert.AreEqual(17, Found[0].HeaderEnd.Line);
  finally
    Tree.Free;
  end;
  for Conversion := Low(TMethodConversion) to High(TMethodConversion) do
  begin
    Assert.IsTrue(TMethodWithoutSelf.ConversionOf(TMethodWithoutSelf.ConversionName(Conversion), Parsed));
    Assert.AreEqual(Ord(Conversion), Ord(Parsed));
  end;
  Assert.IsFalse(TMethodWithoutSelf.ConversionOf('x', Parsed));
  Assert.AreEqual('TDateTimeHelper', TMethodWithoutSelf.HelperNameFor('TDateTime'));
  Assert.AreEqual('TIntegerHelper', TMethodWithoutSelf.HelperNameFor('Integer'));
  Assert.IsTrue(TMethodWithoutSelf.IsSimpleType('Integer'));
  Assert.IsFalse(TMethodWithoutSelf.IsSimpleType('TKunde'));
end;

initialization
  TDUnitX.RegisterTestFixture(TMethodWithoutSelfTests);

end.
