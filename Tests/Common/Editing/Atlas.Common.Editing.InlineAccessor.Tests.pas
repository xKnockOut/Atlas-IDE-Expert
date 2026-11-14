unit Atlas.Common.Editing.InlineAccessor.Tests;

// Tests für „Triviale Zugriffsmethode durch Feld ersetzen“ (#717): Erkennung
// trivialer Getter und Setter (mit und ohne Gleichheitsprüfung), Ausschlüsse
// (virtual, Interface, Aufruf in der Klasse, index, Benachrichtigung, Typ),
// Aktion an Property, Deklaration und Rumpf, Ersetzen samt leerem Abschnitt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInlineAccessorTests = class
  public
    [Test]
    procedure DetectsTrivialGetterAndSetter;
    [Test]
    procedure EqualityCheckIsOptional;
    [Test]
    procedure RejectsNotifyingSetter;
    [Test]
    procedure RejectsVirtualIndexAndInternalUse;
    [Test]
    procedure RejectsInterfaceMethods;
    [Test]
    procedure RejectsOtherTypes;
    [Test]
    procedure FindsAccessorsAtLine;
    [Test]
    procedure ReplacesAndDeletes;
    [Test]
    procedure KnowsOwnReferences;
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
  Atlas.Common.Editing.InlineAccessor;

const
  cSource =
    'unit U;'#10 +                                                           // 0
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +                                                    // 3
    '  private'#10 +
    '    FName: string;'#10 +                                                // 5
    '    FCount: Integer;'#10 +
    '    FColor: Integer;'#10 +
    '  protected'#10 +
    '    function GetName: string;'#10 +                                     // 9
    '    procedure SetName(const Value: string);'#10 +                       // 10
    '    function GetCount: Integer;'#10 +                                   // 11
    '    procedure SetCount(AValue: Integer);'#10 +                          // 12
    '    procedure SetColor(const AValue: Integer);'#10 +                    // 13
    '  public'#10 +
    '    property Name: string read GetName write SetName;'#10 +             // 15
    '    property Count: Integer read GetCount write SetCount;'#10 +         // 16
    '    property Color: Integer read FColor write SetColor;'#10 +           // 17
    '  end;'#10 +
    'implementation'#10 +                                                    // 19
    #10 +
    'function TFoo.GetName: string;'#10 +                                    // 21
    'begin'#10 +
    '  Result := FName;'#10 +
    'end;'#10 +
    #10 +
    'procedure TFoo.SetName(const Value: string);'#10 +                      // 26
    'begin'#10 +
    '  Self.FName := Value;'#10 +
    'end;'#10 +
    #10 +
    'function TFoo.GetCount: Integer;'#10 +                                  // 31
    'begin'#10 +
    '  Exit(FCount);'#10 +
    'end;'#10 +
    #10 +
    'procedure TFoo.SetCount(AValue: Integer);'#10 +                         // 36
    'begin'#10 +
    '  if FCount <> AValue then'#10 +
    '    FCount := AValue;'#10 +
    'end;'#10 +
    #10 +
    'procedure TFoo.SetColor(const AValue: Integer);'#10 +                   // 42
    'begin'#10 +
    '  if AValue <> FColor then'#10 +
    '  begin'#10 +
    '    FColor := AValue;'#10 +
    '    Changed;'#10 +
    '  end;'#10 +
    'end;'#10 +
    #10 +
    'end.'#10;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

function Names(const AAccessors: TArray<TTrivialAccessor>): string;
var
  mItem: TTrivialAccessor;
begin
  Result := '';
  for mItem in AAccessors do
  begin
    Result := Result + mItem.Name + '=' + mItem.Field + ' ';
  end;
  Result := Trim(Result);
end;

function Options(AEqualityCheck: Boolean): TInlineAccessorOptions;
begin
  Result := TInlineAccessorOptions.Default;
  Result.EqualityCheck := AEqualityCheck;
end;

/// <summary>Grund für das Mitglied AName in AText, '' wenn trivial.</summary>
function ReasonFor(const AText, AClass, AName: string; AEqualityCheck: Boolean;
  const AInterfaces: TInterfaceDeclares): string;
var
  mLayout: TClassLayout;
  mTree: TSyntaxTree;
  mAccessor: TTrivialAccessor;
begin
  mLayout := TMemberTransfer.ParseLayout(AText, AClass, mTree);
  try
    if TInlineAccessor.Check(mLayout, mLayout.Find(AName)[0], Options(AEqualityCheck), AInterfaces, mAccessor,
      Result) then
    begin
      Result := '';
    end;
  finally
    mLayout.Free;
    mTree.Free;
  end;
end;

procedure TInlineAccessorTests.DetectsTrivialGetterAndSetter;
var
  mLayout: TClassLayout;
  mTree: TSyntaxTree;
  mFound: TArray<TTrivialAccessor>;
begin
  mLayout := TMemberTransfer.ParseLayout(cSource, 'TFoo', mTree);
  try
    mFound := TInlineAccessor.InClass(mLayout, Options(True), nil);
    Assert.AreEqual('GetName=FName SetName=FName GetCount=FCount SetCount=FCount', Names(mFound));
    Assert.IsTrue(mFound[0].IsGetter);
    Assert.IsFalse(mFound[1].IsGetter);
    Assert.AreEqual(9, mFound[0].NamePos.Line);
    Assert.AreEqual(13, mFound[0].NamePos.Character);
    Assert.AreEqual(1, Integer(Length(mFound[0].Properties)));
  finally
    mLayout.Free;
    mTree.Free;
  end;
end;

procedure TInlineAccessorTests.EqualityCheckIsOptional;
begin
  Assert.AreEqual('', ReasonFor(cSource, 'TFoo', 'SetCount', True, nil));
  Assert.AreEqual('SetCount tut mehr, als ein Feld zu lesen bzw. zu setzen.',
    ReasonFor(cSource, 'TFoo', 'SetCount', False, nil));
end;

procedure TInlineAccessorTests.RejectsNotifyingSetter;
begin
  Assert.AreEqual('SetColor tut mehr, als ein Feld zu lesen bzw. zu setzen.',
    ReasonFor(cSource, 'TFoo', 'SetColor', True, nil));
end;

procedure TInlineAccessorTests.RejectsVirtualIndexAndInternalUse;
const
  cText =
    'unit U;'#10'interface'#10'type'#10 +
    '  TBar = class'#10 +
    '  private'#10 +
    '    FA: Integer;'#10 +
    '    FB: Integer;'#10 +
    '    FC: Integer;'#10 +
    '    function GetA: Integer; virtual;'#10 +
    '    function GetB(AIndex: Integer): Integer;'#10 +
    '    function GetC: Integer;'#10 +
    '    procedure Show;'#10 +
    '  public'#10 +
    '    property A: Integer read GetA;'#10 +
    '    property B: Integer index 1 read GetB;'#10 +
    '    property C: Integer read GetC;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'function TBar.GetA: Integer;'#10'begin'#10'  Result := FA;'#10'end;'#10#10 +
    'function TBar.GetB(AIndex: Integer): Integer;'#10'begin'#10'  Result := FB;'#10'end;'#10#10 +
    'function TBar.GetC: Integer;'#10'begin'#10'  Result := FC;'#10'end;'#10#10 +
    'procedure TBar.Show;'#10'begin'#10'  Writeln(GetC);'#10'end;'#10#10 +
    'end.'#10;
begin
  Assert.AreEqual('GetA ist virtuell (virtual, dynamic, override oder abstract).',
    ReasonFor(cText, 'TBar', 'GetA', True, nil));
  Assert.AreEqual('Property B hat einen index; GetB braucht ihn als Parameter.',
    ReasonFor(cText, 'TBar', 'GetB', True, nil));
  Assert.AreEqual('GetC wird in der Klasse benutzt (Show).', ReasonFor(cText, 'TBar', 'GetC', True, nil));
end;

procedure TInlineAccessorTests.RejectsInterfaceMethods;
const
  cText =
    'unit U;'#10'interface'#10'type'#10 +
    '  INamed = interface'#10 +
    '    function GetName: string;'#10 +
    '  end;'#10 +
    '  TBar = class(TInterfacedObject, INamed, IOther)'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    function GetName: string;'#10 +
    '  public'#10 +
    '    property Name: string read GetName;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'function TBar.GetName: string;'#10'begin'#10'  Result := FName;'#10'end;'#10#10 +
    'end.'#10;
var
  mOther: TInterfaceDeclares;
begin
  Assert.AreEqual('GetName implementiert eine Methode von INamed.', ReasonFor(cText, 'TBar', 'GetName', True, nil));
  mOther :=
    function(const AInterface, AMethod: string): TInterfaceAnswer
    begin
      Result := TInterfaceAnswer.No;
    end;
  Assert.AreEqual('GetName implementiert eine Methode von INamed.', ReasonFor(cText, 'TBar', 'GetName', True, mOther));
  // Ohne INamed: IOther ist unbekannt, mit Auskunft „nein“ ist die Methode frei.
  Assert.AreEqual('Ob GetName eine Methode von IOther implementiert, ist unbekannt.',
    ReasonFor(ReplaceStr(cText, 'INamed, ', ''), 'TBar', 'GetName', True, nil));
  Assert.AreEqual('', ReasonFor(ReplaceStr(cText, 'INamed, ', ''), 'TBar', 'GetName', True, mOther));
  Assert.AreEqual('GetName ist einer Interface-Methode zugeordnet.',
    ReasonFor(ReplaceStr(ReplaceStr(cText, 'INamed, ', ''), '    FName: string;'#10,
    '    FName: string;'#10'    function IOther.Title = GetName;'#10), 'TBar', 'GetName', True, mOther));
end;

procedure TInlineAccessorTests.RejectsOtherTypes;
begin
  Assert.AreEqual('FCount hat einen anderen Typ als die Property.',
    ReasonFor(ReplaceStr(cSource, 'FCount: Integer;', 'FCount: Int64;'), 'TFoo', 'GetCount', True, nil));
  Assert.AreEqual('FName ist kein Feld von TFoo.',
    ReasonFor(ReplaceStr(cSource, '    FName: string;'#10, ''), 'TFoo', 'GetName', True, nil));
end;

procedure TInlineAccessorTests.FindsAccessorsAtLine;
var
  mLayout: TClassLayout;
  mTree: TSyntaxTree;
  mReason: string;
begin
  mLayout := TMemberTransfer.ParseLayout(cSource, 'TFoo', mTree);
  try
    Assert.AreEqual('GetName=FName SetName=FName', Names(TInlineAccessor.At(mLayout, 15, Options(True), nil,
      mReason)));
    Assert.AreEqual('GetCount=FCount', Names(TInlineAccessor.At(mLayout, 16, Options(False), nil, mReason)));
    Assert.AreEqual('SetName=FName', Names(TInlineAccessor.At(mLayout, 10, Options(True), nil, mReason)));
    Assert.AreEqual('GetCount=FCount', Names(TInlineAccessor.At(mLayout, 33, Options(True), nil, mReason)));
    Assert.AreEqual(0, Integer(Length(TInlineAccessor.At(mLayout, 17, Options(True), nil, mReason))));
    Assert.AreEqual('SetColor tut mehr, als ein Feld zu lesen bzw. zu setzen.', mReason);
    Assert.AreEqual(0, Integer(Length(TInlineAccessor.At(mLayout, 5, Options(True), nil, mReason))));
    Assert.AreEqual('', mReason);
    Assert.AreEqual('Zugriffsmethoden GetName und SetName durch Feld ersetzen',
      TInlineAccessor.Title(TInlineAccessor.At(mLayout, 15, Options(True), nil, mReason)));
  finally
    mLayout.Free;
    mTree.Free;
  end;
end;

procedure TInlineAccessorTests.ReplacesAndDeletes;
var
  mLayout: TClassLayout;
  mTree: TSyntaxTree;
  mText: string;
begin
  mLayout := TMemberTransfer.ParseLayout(cSource, 'TFoo', mTree);
  try
    mText := TTextChanges.Apply(cSource, TInlineAccessor.Edits(mLayout, TInlineAccessor.InClass(mLayout, Options(True),
      nil)));
  finally
    mLayout.Free;
    mTree.Free;
  end;
  Assert.IsTrue(Parses(mText), mText);
  // protected behält nur SetColor; Properties zeigen auf die Felder.
  Assert.IsTrue(ContainsStr(mText, '  protected'#10'    procedure SetColor(const AValue: Integer);'#10'  public'#10 +
    '    property Name: string read FName write FName;'#10 +
    '    property Count: Integer read FCount write FCount;'#10), mText);
  Assert.IsFalse(ContainsStr(mText, 'GetName'), mText);
  Assert.IsFalse(ContainsStr(mText, 'TFoo.SetCount'), mText);
  Assert.IsTrue(ContainsStr(mText, 'implementation'#10#10'procedure TFoo.SetColor'), mText);
  // Ohne SetColor fällt auch der leere Abschnitt weg.
  mText := ReplaceStr(ReplaceStr(cSource, '    procedure SetColor(const AValue: Integer);'#10, ''),
    'write SetColor;', 'write FColor;');
  mText := Copy(mText, 1, Pos('procedure TFoo.SetColor', mText) - 1) + 'end.'#10;
  mLayout := TMemberTransfer.ParseLayout(mText, 'TFoo', mTree);
  try
    mText := TTextChanges.Apply(mText, TInlineAccessor.Edits(mLayout, TInlineAccessor.InClass(mLayout, Options(True),
      nil)));
  finally
    mLayout.Free;
    mTree.Free;
  end;
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsFalse(ContainsStr(mText, 'protected'), mText);
end;

procedure TInlineAccessorTests.KnowsOwnReferences;
var
  mLayout: TClassLayout;
  mTree: TSyntaxTree;
  mFound: TArray<TTrivialAccessor>;
begin
  mLayout := TMemberTransfer.ParseLayout(cSource, 'TFoo', mTree);
  try
    mFound := TInlineAccessor.InClass(mLayout, Options(True), nil);
    Assert.IsTrue(TInlineAccessor.IsOwnReference(mLayout, mFound[0], TTextPosition.Create(9, 13)));
    Assert.IsTrue(TInlineAccessor.IsOwnReference(mLayout, mFound[0], TTextPosition.Create(15, 32)));
    Assert.IsTrue(TInlineAccessor.IsOwnReference(mLayout, mFound[0], TTextPosition.Create(21, 14)));
    Assert.IsFalse(TInlineAccessor.IsOwnReference(mLayout, mFound[0], TTextPosition.Create(16, 32)));
    Assert.IsFalse(TInlineAccessor.IsOwnReference(mLayout, mFound[0], TTextPosition.Create(33, 2)));
  finally
    mLayout.Free;
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TInlineAccessorTests);

end.
