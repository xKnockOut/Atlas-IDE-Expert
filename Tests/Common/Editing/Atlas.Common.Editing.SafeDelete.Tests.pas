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
  cSource =
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
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TSafeDelete.Find(mTree, AText, Pos_(ALine, ACharacter), ATarget, AReason);
    ATarget.Node := nil;
  finally
    mTree.Free;
  end;
end;

function DeleteAt(const AText: string; ALine, ACharacter: Integer): string;
var
  mTree: TSyntaxTree;
  mTarget: TSafeDeleteTarget;
  mReason: string;
begin
  mTree := TPascalParser.Parse(AText);
  try
    if not TSafeDelete.Find(mTree, AText, Pos_(ALine, ACharacter), mTarget, mReason) then
    begin
      Exit('nicht gefunden: ' + mReason);
    end;
    Result := TTextChanges.Apply(AText, TSafeDelete.Edits(mTree, AText, [mTarget]));
  finally
    mTree.Free;
  end;
end;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := mTree.Diagnostics = nil;
  finally
    mTree.Free;
  end;
end;

procedure TSafeDeleteTests.FindsSymbols;
var
  mTarget: TSafeDeleteTarget;
  mReason: string;
begin
  Assert.IsTrue(FindIn(cSource, 0, 5, mTarget, mReason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Unit_), Ord(mTarget.Kind));
  Assert.AreEqual('U', mTarget.Name);
  Assert.IsTrue(FindIn(cSource, 4, 3, mTarget, mReason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Constant), Ord(mTarget.Kind));
  Assert.AreEqual('cSize', mTarget.Name);
  Assert.AreEqual(4, mTarget.NameRange.StartPos.Line);
  Assert.IsTrue(FindIn(cSource, 7, 3, mTarget, mReason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Type_), Ord(mTarget.Kind));
  Assert.AreEqual('TFoo', mTarget.Name);
  Assert.IsTrue(FindIn(cSource, 9, 9, mTarget, mReason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Field), Ord(mTarget.Kind));
  Assert.AreEqual('FB', mTarget.Name);
  Assert.AreEqual('TFoo', mTarget.ClassName);
  Assert.IsTrue(FindIn(cSource, 15, 14, mTarget, mReason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Property_), Ord(mTarget.Kind));
  Assert.IsTrue(FindIn(cSource, 31, 16, mTarget, mReason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Method), Ord(mTarget.Kind));
  Assert.AreEqual('Run', mTarget.Name);
  Assert.AreEqual(13, mTarget.NameRange.StartPos.Line, 'Rumpf zeigt auf die Deklaration');
  Assert.IsTrue(FindIn(cSource, 18, 6, mTarget, mReason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Variable), Ord(mTarget.Kind));
  Assert.AreEqual('GB', mTarget.Name);
  Assert.IsTrue(FindIn(cSource, 19, 11, mTarget, mReason));
  Assert.AreEqual(Ord(TSafeDeleteKind.Routine), Ord(mTarget.Kind));
  Assert.AreEqual('Glob', mTarget.Name);
  Assert.IsTrue(FindIn(cSource, 37, 13, mTarget, mReason));
  Assert.AreEqual(Ord(TSafeDeleteKind.LocalRoutine), Ord(mTarget.Kind));
  Assert.AreEqual('Inner', mTarget.Name);
  Assert.IsTrue(StartsText('lokale Routine', TSafeDelete.Title(mTarget)), TSafeDelete.Title(mTarget));
  Assert.IsTrue(ContainsText(TSafeDelete.Title(mTarget), 'Inner'));
end;

procedure TSafeDeleteTests.RefusesLocalVariable;
var
  mTarget: TSafeDeleteTarget;
  mReason: string;
begin
  Assert.IsFalse(FindIn(cSource, 41, 3, mTarget, mReason));
  Assert.IsTrue(ContainsText(mReason, 'unused-local'));
  Assert.IsFalse(FindIn(cSource, 21, 0, mTarget, mReason));
  Assert.AreEqual('', mReason);
end;

procedure TSafeDeleteTests.DeletesMethodWithBody;
var
  mText: string;
begin
  mText := DeleteAt(cSource, 10, 15);
  Assert.IsFalse(ContainsText(mText, 'Helper;'#10'  protected'), mText);
  Assert.IsFalse(ContainsText(mText, 'TFoo.Helper'), mText);
  Assert.IsTrue(ContainsText(mText, '  Helper;'#10'end;'), 'Aufruf bleibt (prueft die Protokollschicht)');
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TSafeDeleteTests.DeletesOneOverload;
var
  mText: string;
begin
  mText := DeleteAt(cSource, 13, 15);
  Assert.IsFalse(ContainsText(mText, 'Run(AValue: Integer)'), mText);
  Assert.IsTrue(ContainsText(mText, '    procedure Run; overload;'), mText);
  Assert.IsTrue(ContainsText(mText, 'procedure TFoo.Run;'), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TSafeDeleteTests.DeletesFieldFromGroup;
var
  mText: string;
begin
  mText := DeleteAt(cSource, 9, 5);
  Assert.IsTrue(ContainsText(mText, '    FB: Integer;'), mText);
  mText := DeleteAt(cSource, 9, 9);
  Assert.IsTrue(ContainsText(mText, '    FA: Integer;'), mText);
end;

procedure TSafeDeleteTests.DeletesPropertyAndEmptySection;
var
  mText: string;
begin
  mText := DeleteAt(cSource, 15, 14);
  Assert.IsFalse(ContainsText(mText, 'property A'), mText);
  Assert.IsFalse(ContainsText(mText, 'public'), 'leerer Abschnitt faellt weg');
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TSafeDeleteTests.DeletesClassWithBodies;
var
  mText: string;
begin
  mText := DeleteAt(cSource, 7, 3);
  Assert.IsFalse(ContainsText(mText, 'TFoo'), mText);
  Assert.IsFalse(ContainsText(mText, 'type'), 'leerer type-Abschnitt faellt weg');
  Assert.IsTrue(ContainsText(mText, 'procedure Glob(AValue: Integer);'#10'  procedure Inner;'), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TSafeDeleteTests.DeletesConstantWithDocAndSection;
var
  mText: string;
begin
  mText := DeleteAt(cSource, 4, 3);
  Assert.IsFalse(ContainsText(mText, 'Groesse'), 'Doku geht mit');
  Assert.IsTrue(ContainsText(mText, 'const'#10'  cName'), mText);
  mText := DeleteAt(mText, 3, 3);
  Assert.IsFalse(ContainsText(mText, 'const'), 'leerer const-Abschnitt faellt weg');
  Assert.IsTrue(ContainsText(mText, 'interface'#10'type'), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TSafeDeleteTests.DeletesVariableFromGroup;
var
  mText: string;
begin
  mText := DeleteAt(cSource, 18, 6);
  Assert.IsTrue(ContainsText(mText, '  GA: Integer;'), mText);
  mText := DeleteAt(mText, 18, 3);
  Assert.IsFalse(ContainsText(mText, 'GA'), mText);
  Assert.IsTrue(ContainsText(mText, '  end;'#10'procedure Glob'), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TSafeDeleteTests.DeletesRoutineEverywhere;
var
  mText: string;
begin
  mText := DeleteAt(cSource, 36, 11);
  Assert.IsFalse(ContainsText(mText, 'Glob'), mText);
  Assert.IsFalse(ContainsText(mText, 'Inner'), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TSafeDeleteTests.DeletesLocalRoutine;
var
  mText: string;
begin
  mText := DeleteAt(cSource, 37, 13);
  Assert.IsFalse(ContainsText(mText, 'Inner'), mText);
  Assert.IsTrue(ContainsText(mText, 'procedure Glob(AValue: Integer);'#10'var'), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TSafeDeleteTests.FindsFreedMembers;
var
  mTree: TSyntaxTree;
  mLayout: TClassLayout;
  mFreed: TArray<Integer>;
begin
  mLayout := TMemberTransfer.ParseLayout(cSource, 'TFoo', mTree);
  try
    // Run ohne Parameter benutzt Helper, sonst niemand.
    mFreed := TSafeDelete.FreedMembers(mLayout, [mLayout.Find('Run')[0]]);
    Assert.AreEqual(1, Integer(Length(mFreed)));
    Assert.AreEqual('Helper', mLayout.Members[mFreed[0]].Name);
    // Beide Überladungen: Helper und FB.
    mFreed := TSafeDelete.FreedMembers(mLayout, mLayout.Find('Run'));
    Assert.AreEqual(2, Integer(Length(mFreed)));
    // FA bleibt wegen der Property, FB wird frei mit Run(AValue).
    mFreed := TSafeDelete.FreedMembers(mLayout, [mLayout.Find('Run')[1]]);
    Assert.AreEqual(1, Integer(Length(mFreed)));
    Assert.AreEqual('FB', mLayout.Members[mFreed[0]].Name);
    // Mehrere Stufen: Property A weg, dann ist FA frei.
    mFreed := TSafeDelete.FreedMembers(mLayout, mLayout.Find('A'));
    Assert.AreEqual(1, Integer(Length(mFreed)));
    Assert.AreEqual('FA', mLayout.Members[mFreed[0]].Name);
  finally
    mLayout.Free;
    mTree.Free;
  end;
end;

procedure TSafeDeleteTests.ListsOwnLines;
var
  mTree: TSyntaxTree;
  mTarget: TSafeDeleteTarget;
  mReason: string;
  mSpans: TArray<TLineSpan>;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.IsTrue(TSafeDelete.Find(mTree, cSource, Pos_(12, 15), mTarget, mReason));
    mSpans := TSafeDelete.OwnLines(mTree, cSource, mTarget);
    Assert.AreEqual(2, Integer(Length(mSpans)));
    Assert.IsTrue(mSpans[0].Contains(12));
    Assert.IsTrue(mSpans[1].Contains(28));
    Assert.IsFalse(mSpans[1].Contains(31));
    Assert.IsTrue(TSafeDelete.Find(mTree, cSource, Pos_(19, 11), mTarget, mReason));
    mSpans := TSafeDelete.OwnLines(mTree, cSource, mTarget);
    Assert.AreEqual(2, Integer(Length(mSpans)));
    Assert.IsTrue(mSpans[1].Contains(43));
    Assert.IsTrue(TSafeDelete.Find(mTree, cSource, Pos_(7, 3), mTarget, mReason));
    mSpans := TSafeDelete.OwnLines(mTree, cSource, mTarget);
    Assert.AreEqual(4, Integer(Length(mSpans)));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSafeDeleteTests);

end.
