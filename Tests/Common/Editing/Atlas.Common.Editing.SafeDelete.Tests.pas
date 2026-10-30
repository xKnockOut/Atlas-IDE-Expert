unit Atlas.Common.Editing.SafeDelete.Tests;

// Tests für „Sicher löschen“ (#716), Teil ohne Projekt: Symbol an einer
// Stelle finden (Mitglied, Feld aus einer Gruppe, Typ, Konstante, Variable,
// Routine, lokale Routine, Unit), Löschen samt Rumpf, Doku-Kommentar und
// leerem Abschnitt, Überladungen einzeln und freigewordene private Mitglieder.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSafeDeleteTests = class
  public
    [Test]
    procedure FindsSymbols;
    [Test]
    procedure RefusesLocalVariable;
    [Test]
    procedure DeletesMethodWithBody;
    [Test]
    procedure DeletesOneOverload;
    [Test]
    procedure DeletesFieldFromGroup;
    [Test]
    procedure DeletesPropertyAndEmptySection;
    [Test]
    procedure DeletesClassWithBodies;
    [Test]
    procedure DeletesConstantWithDocAndSection;
    [Test]
    procedure DeletesVariableFromGroup;
    [Test]
    procedure DeletesRoutineEverywhere;
    [Test]
    procedure DeletesLocalRoutine;
    [Test]
    procedure FindsFreedMembers;
    [Test]
    procedure ListsOwnLines;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.MemberTransfer,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Editing.SafeDelete;

const
  Source =
    'unit U;'#10 +                                                           // 0
    'interface'#10 +
    'const'#10 +
    '  /// Groesse'#10 +                                                     // 3
    '  cSize = 10;'#10 +                                                     // 4
    '  cName = ''x'';'#10 +                                                  // 5
    'type'#10 +
    '  TFoo = class'#10 +                                                    // 7
    '  private'#10 +
    '    FA, FB: Integer;'#10 +                                              // 9
    '    procedure Helper;'#10 +                                             // 10
    '  protected'#10 +
    '    procedure Run; overload;'#10 +                                      // 12
    '    procedure Run(AValue: Integer); overload;'#10 +                     // 13
    '  public'#10 +
    '    property A: Integer read FA;'#10 +                                  // 15
    '  end;'#10 +
    'var'#10 +
    '  GA, GB: Integer;'#10 +                                                // 18
    'procedure Glob(AValue: Integer);'#10 +                                  // 19
    'implementation'#10 +                                                    // 20
    #10 +
    'procedure TFoo.Helper;'#10 +                                            // 22
    'begin'#10 +
    'end;'#10 +
    #10 +
    'procedure TFoo.Run;'#10 +                                               // 26
    'begin'#10 +
    '  Helper;'#10 +
    'end;'#10 +
    #10 +
    'procedure TFoo.Run(AValue: Integer);'#10 +                              // 31
    'begin'#10 +
    '  FB := AValue;'#10 +
    'end;'#10 +
    #10 +
    'procedure Glob(AValue: Integer);'#10 +                                  // 36
    '  procedure Inner;'#10 +                                                // 37
    '  begin'#10 +
    '  end;'#10 +
    'var'#10 +
    '  L: Integer;'#10 +                                                     // 41
    'begin'#10 +
    '  L := AValue;'#10 +
    'end;'#10 +
    #10 +
    'end.'#10;

function Pos_(ALine, ACharacter: Integer): TTextPosition;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

function FindIn(const AText: string; ALine, ACharacter: Integer; out ATarget: TSafeDeleteTarget;
  out AReason: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TSafeDelete.Find(Tree, AText, Pos_(ALine, ACharacter), ATarget, AReason);
    ATarget.Node := nil;
  finally
    Tree.Free;
  end;
end;

function DeleteAt(const AText: string; ALine, ACharacter: Integer): string;
var
  Tree: TSyntaxTree;
  Target: TSafeDeleteTarget;
  Reason: string;
begin
  Tree := TPascalParser.Parse(AText);
  try
    if not TSafeDelete.Find(Tree, AText, Pos_(ALine, ACharacter), Target, Reason) then
      Exit('nicht gefunden: ' + Reason);
    Result := TTextChanges.Apply(AText, TSafeDelete.Edits(Tree, AText, [Target]));
  finally
    Tree.Free;
  end;
end;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Tree.Diagnostics = nil;
  finally
    Tree.Free;
  end;
end;

procedure TSafeDeleteTests.FindsSymbols;
var
  Target: TSafeDeleteTarget;
  Reason: string;
begin
  Assert.IsTrue(FindIn(Source, 0, 5, Target, Reason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Unit_), Ord(Target.Kind));
  Assert.AreEqual('U', Target.Name);
  Assert.IsTrue(FindIn(Source, 4, 3, Target, Reason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Constant), Ord(Target.Kind));
  Assert.AreEqual('cSize', Target.Name);
  Assert.AreEqual(4, Target.NameRange.StartPos.Line);
  Assert.IsTrue(FindIn(Source, 7, 3, Target, Reason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Type_), Ord(Target.Kind));
  Assert.AreEqual('TFoo', Target.Name);
  Assert.IsTrue(FindIn(Source, 9, 9, Target, Reason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Field), Ord(Target.Kind));
  Assert.AreEqual('FB', Target.Name);
  Assert.AreEqual('TFoo', Target.ClassName);
  Assert.IsTrue(FindIn(Source, 15, 14, Target, Reason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Property_), Ord(Target.Kind));
  Assert.IsTrue(FindIn(Source, 31, 16, Target, Reason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Method), Ord(Target.Kind));
  Assert.AreEqual('Run', Target.Name);
  Assert.AreEqual(13, Target.NameRange.StartPos.Line, 'Rumpf zeigt auf die Deklaration');
  Assert.IsTrue(FindIn(Source, 18, 6, Target, Reason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Variable), Ord(Target.Kind));
  Assert.AreEqual('GB', Target.Name);
  Assert.IsTrue(FindIn(Source, 19, 11, Target, Reason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Routine), Ord(Target.Kind));
  Assert.AreEqual('Glob', Target.Name);
  Assert.IsTrue(FindIn(Source, 37, 13, Target, Reason));
  Assert.AreEqual(Ord(TSafeDeleteKind.LocalRoutine), Ord(Target.Kind));
  Assert.AreEqual('Inner', Target.Name);
  Assert.IsTrue(StartsText('lokale Routine', TSafeDelete.Title(Target)), TSafeDelete.Title(Target));
  Assert.IsTrue(ContainsText(TSafeDelete.Title(Target), 'Inner'));
end;

procedure TSafeDeleteTests.RefusesLocalVariable;
var
  Target: TSafeDeleteTarget;
  Reason: string;
begin
  Assert.IsFalse(FindIn(Source, 41, 3, Target, Reason));
  Assert.IsTrue(ContainsText(Reason, 'unused-local'));
  Assert.IsFalse(FindIn(Source, 21, 0, Target, Reason));
  Assert.AreEqual('', Reason);
end;

procedure TSafeDeleteTests.DeletesMethodWithBody;
var
  Text: string;
begin
  Text := DeleteAt(Source, 10, 15);
  Assert.IsFalse(ContainsText(Text, 'Helper;'#10'  protected'), Text);
  Assert.IsFalse(ContainsText(Text, 'TFoo.Helper'), Text);
  Assert.IsTrue(ContainsText(Text, '  Helper;'#10'end;'), 'Aufruf bleibt (prueft die Protokollschicht)');
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TSafeDeleteTests.DeletesOneOverload;
var
  Text: string;
begin
  Text := DeleteAt(Source, 13, 15);
  Assert.IsFalse(ContainsText(Text, 'Run(AValue: Integer)'), Text);
  Assert.IsTrue(ContainsText(Text, '    procedure Run; overload;'), Text);
  Assert.IsTrue(ContainsText(Text, 'procedure TFoo.Run;'), Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TSafeDeleteTests.DeletesFieldFromGroup;
var
  Text: string;
begin
  Text := DeleteAt(Source, 9, 5);
  Assert.IsTrue(ContainsText(Text, '    FB: Integer;'), Text);
  Text := DeleteAt(Source, 9, 9);
  Assert.IsTrue(ContainsText(Text, '    FA: Integer;'), Text);
end;

procedure TSafeDeleteTests.DeletesPropertyAndEmptySection;
var
  Text: string;
begin
  Text := DeleteAt(Source, 15, 14);
  Assert.IsFalse(ContainsText(Text, 'property A'), Text);
  Assert.IsFalse(ContainsText(Text, 'public'), 'leerer Abschnitt faellt weg');
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TSafeDeleteTests.DeletesClassWithBodies;
var
  Text: string;
begin
  Text := DeleteAt(Source, 7, 3);
  Assert.IsFalse(ContainsText(Text, 'TFoo'), Text);
  Assert.IsFalse(ContainsText(Text, 'type'), 'leerer type-Abschnitt faellt weg');
  Assert.IsTrue(ContainsText(Text, 'procedure Glob(AValue: Integer);'#10'  procedure Inner;'), Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TSafeDeleteTests.DeletesConstantWithDocAndSection;
var
  Text: string;
begin
  Text := DeleteAt(Source, 4, 3);
  Assert.IsFalse(ContainsText(Text, 'Groesse'), 'Doku geht mit');
  Assert.IsTrue(ContainsText(Text, 'const'#10'  cName'), Text);
  Text := DeleteAt(Text, 3, 3);
  Assert.IsFalse(ContainsText(Text, 'const'), 'leerer const-Abschnitt faellt weg');
  Assert.IsTrue(ContainsText(Text, 'interface'#10'type'), Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TSafeDeleteTests.DeletesVariableFromGroup;
var
  Text: string;
begin
  Text := DeleteAt(Source, 18, 6);
  Assert.IsTrue(ContainsText(Text, '  GA: Integer;'), Text);
  Text := DeleteAt(Text, 18, 3);
  Assert.IsFalse(ContainsText(Text, 'GA'), Text);
  Assert.IsTrue(ContainsText(Text, '  end;'#10'procedure Glob'), Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TSafeDeleteTests.DeletesRoutineEverywhere;
var
  Text: string;
begin
  Text := DeleteAt(Source, 36, 11);
  Assert.IsFalse(ContainsText(Text, 'Glob'), Text);
  Assert.IsFalse(ContainsText(Text, 'Inner'), Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TSafeDeleteTests.DeletesLocalRoutine;
var
  Text: string;
begin
  Text := DeleteAt(Source, 37, 13);
  Assert.IsFalse(ContainsText(Text, 'Inner'), Text);
  Assert.IsTrue(ContainsText(Text, 'procedure Glob(AValue: Integer);'#10'var'), Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TSafeDeleteTests.FindsFreedMembers;
var
  Tree: TSyntaxTree;
  Layout: TClassLayout;
  Freed: TArray<Integer>;
begin
  Layout := TMemberTransfer.ParseLayout(Source, 'TFoo', Tree);
  try
    // Run ohne Parameter benutzt Helper, sonst niemand.
    Freed := TSafeDelete.FreedMembers(Layout, [Layout.Find('Run')[0]]);
    Assert.AreEqual(1, Integer(Length(Freed)));
    Assert.AreEqual('Helper', Layout.Members[Freed[0]].Name);
    // Beide Überladungen: Helper und FB.
    Freed := TSafeDelete.FreedMembers(Layout, Layout.Find('Run'));
    Assert.AreEqual(2, Integer(Length(Freed)));
    // FA bleibt wegen der Property, FB wird frei mit Run(AValue).
    Freed := TSafeDelete.FreedMembers(Layout, [Layout.Find('Run')[1]]);
    Assert.AreEqual(1, Integer(Length(Freed)));
    Assert.AreEqual('FB', Layout.Members[Freed[0]].Name);
    // Mehrere Stufen: Property A weg, dann ist FA frei.
    Freed := TSafeDelete.FreedMembers(Layout, Layout.Find('A'));
    Assert.AreEqual(1, Integer(Length(Freed)));
    Assert.AreEqual('FA', Layout.Members[Freed[0]].Name);
  finally
    Layout.Free;
    Tree.Free;
  end;
end;

procedure TSafeDeleteTests.ListsOwnLines;
var
  Tree: TSyntaxTree;
  Target: TSafeDeleteTarget;
  Reason: string;
  Spans: TArray<TLineSpan>;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Assert.IsTrue(TSafeDelete.Find(Tree, Source, Pos_(12, 15), Target, Reason));
    Spans := TSafeDelete.OwnLines(Tree, Source, Target);
    Assert.AreEqual(2, Integer(Length(Spans)));
    Assert.IsTrue(Spans[0].Contains(12));
    Assert.IsTrue(Spans[1].Contains(28));
    Assert.IsFalse(Spans[1].Contains(31));
    Assert.IsTrue(TSafeDelete.Find(Tree, Source, Pos_(19, 11), Target, Reason));
    Spans := TSafeDelete.OwnLines(Tree, Source, Target);
    Assert.AreEqual(2, Integer(Length(Spans)));
    Assert.IsTrue(Spans[1].Contains(43));
    Assert.IsTrue(TSafeDelete.Find(Tree, Source, Pos_(7, 3), Target, Reason));
    Spans := TSafeDelete.OwnLines(Tree, Source, Target);
    Assert.AreEqual(4, Integer(Length(Spans)));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSafeDeleteTests);

end.
