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
  Source =
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
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

function Names(const AAccessors: TArray<TTrivialAccessor>): string;
var
  Item: TTrivialAccessor;
begin
  Result := '';
  for Item in AAccessors do
    Result := Result + Item.Name + '=' + Item.Field + ' ';
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
  Layout: TClassLayout;
  Tree: TSyntaxTree;
  Accessor: TTrivialAccessor;
begin
  Layout := TMemberTransfer.ParseLayout(AText, AClass, Tree);
  try
    if TInlineAccessor.Check(Layout, Layout.Find(AName)[0], Options(AEqualityCheck), AInterfaces, Accessor,
      Result) then
      Result := '';
  finally
    Layout.Free;
    Tree.Free;
  end;
end;

procedure TInlineAccessorTests.DetectsTrivialGetterAndSetter;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
  Found: TArray<TTrivialAccessor>;
begin
  Layout := TMemberTransfer.ParseLayout(Source, 'TFoo', Tree);
  try
    Found := TInlineAccessor.InClass(Layout, Options(True), nil);
    Assert.AreEqual('GetName=FName SetName=FName GetCount=FCount SetCount=FCount', Names(Found));
    Assert.IsTrue(Found[0].IsGetter);
    Assert.IsFalse(Found[1].IsGetter);
    Assert.AreEqual(9, Found[0].NamePos.Line);
    Assert.AreEqual(13, Found[0].NamePos.Character);
    Assert.AreEqual(1, Integer(Length(Found[0].Properties)));
  finally
    Layout.Free;
    Tree.Free;
  end;
end;

procedure TInlineAccessorTests.EqualityCheckIsOptional;
begin
  Assert.AreEqual('', ReasonFor(Source, 'TFoo', 'SetCount', True, nil));
  Assert.AreEqual('SetCount tut mehr, als ein Feld zu lesen bzw. zu setzen.',
    ReasonFor(Source, 'TFoo', 'SetCount', False, nil));
end;

procedure TInlineAccessorTests.RejectsNotifyingSetter;
begin
  Assert.AreEqual('SetColor tut mehr, als ein Feld zu lesen bzw. zu setzen.',
    ReasonFor(Source, 'TFoo', 'SetColor', True, nil));
end;

procedure TInlineAccessorTests.RejectsVirtualIndexAndInternalUse;
const
  Text =
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
    ReasonFor(Text, 'TBar', 'GetA', True, nil));
  Assert.AreEqual('Property B hat einen index; GetB braucht ihn als Parameter.',
    ReasonFor(Text, 'TBar', 'GetB', True, nil));
  Assert.AreEqual('GetC wird in der Klasse benutzt (Show).', ReasonFor(Text, 'TBar', 'GetC', True, nil));
end;

procedure TInlineAccessorTests.RejectsInterfaceMethods;
const
  Text =
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
  Other: TInterfaceDeclares;
begin
  Assert.AreEqual('GetName implementiert eine Methode von INamed.', ReasonFor(Text, 'TBar', 'GetName', True, nil));
  Other :=
    function(const AInterface, AMethod: string): TInterfaceAnswer
    begin
      Result := TInterfaceAnswer.No;
    end;
  Assert.AreEqual('GetName implementiert eine Methode von INamed.', ReasonFor(Text, 'TBar', 'GetName', True, Other));
  // Ohne INamed: IOther ist unbekannt, mit Auskunft „nein“ ist die Methode frei.
  Assert.AreEqual('Ob GetName eine Methode von IOther implementiert, ist unbekannt.',
    ReasonFor(ReplaceStr(Text, 'INamed, ', ''), 'TBar', 'GetName', True, nil));
  Assert.AreEqual('', ReasonFor(ReplaceStr(Text, 'INamed, ', ''), 'TBar', 'GetName', True, Other));
  Assert.AreEqual('GetName ist einer Interface-Methode zugeordnet.',
    ReasonFor(ReplaceStr(ReplaceStr(Text, 'INamed, ', ''), '    FName: string;'#10,
    '    FName: string;'#10'    function IOther.Title = GetName;'#10), 'TBar', 'GetName', True, Other));
end;

procedure TInlineAccessorTests.RejectsOtherTypes;
begin
  Assert.AreEqual('FCount hat einen anderen Typ als die Property.',
    ReasonFor(ReplaceStr(Source, 'FCount: Integer;', 'FCount: Int64;'), 'TFoo', 'GetCount', True, nil));
  Assert.AreEqual('FName ist kein Feld von TFoo.',
    ReasonFor(ReplaceStr(Source, '    FName: string;'#10, ''), 'TFoo', 'GetName', True, nil));
end;

procedure TInlineAccessorTests.FindsAccessorsAtLine;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
  Reason: string;
begin
  Layout := TMemberTransfer.ParseLayout(Source, 'TFoo', Tree);
  try
    Assert.AreEqual('GetName=FName SetName=FName', Names(TInlineAccessor.At(Layout, 15, Options(True), nil,
      Reason)));
    Assert.AreEqual('GetCount=FCount', Names(TInlineAccessor.At(Layout, 16, Options(False), nil, Reason)));
    Assert.AreEqual('SetName=FName', Names(TInlineAccessor.At(Layout, 10, Options(True), nil, Reason)));
    Assert.AreEqual('GetCount=FCount', Names(TInlineAccessor.At(Layout, 33, Options(True), nil, Reason)));
    Assert.AreEqual(0, Integer(Length(TInlineAccessor.At(Layout, 17, Options(True), nil, Reason))));
    Assert.AreEqual('SetColor tut mehr, als ein Feld zu lesen bzw. zu setzen.', Reason);
    Assert.AreEqual(0, Integer(Length(TInlineAccessor.At(Layout, 5, Options(True), nil, Reason))));
    Assert.AreEqual('', Reason);
    Assert.AreEqual('Zugriffsmethoden GetName und SetName durch Feld ersetzen',
      TInlineAccessor.Title(TInlineAccessor.At(Layout, 15, Options(True), nil, Reason)));
  finally
    Layout.Free;
    Tree.Free;
  end;
end;

procedure TInlineAccessorTests.ReplacesAndDeletes;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
  Text: string;
begin
  Layout := TMemberTransfer.ParseLayout(Source, 'TFoo', Tree);
  try
    Text := TTextChanges.Apply(Source, TInlineAccessor.Edits(Layout, TInlineAccessor.InClass(Layout, Options(True),
      nil)));
  finally
    Layout.Free;
    Tree.Free;
  end;
  Assert.IsTrue(Parses(Text), Text);
  // protected behält nur SetColor; Properties zeigen auf die Felder.
  Assert.IsTrue(ContainsStr(Text, '  protected'#10'    procedure SetColor(const AValue: Integer);'#10'  public'#10 +
    '    property Name: string read FName write FName;'#10 +
    '    property Count: Integer read FCount write FCount;'#10), Text);
  Assert.IsFalse(ContainsStr(Text, 'GetName'), Text);
  Assert.IsFalse(ContainsStr(Text, 'TFoo.SetCount'), Text);
  Assert.IsTrue(ContainsStr(Text, 'implementation'#10#10'procedure TFoo.SetColor'), Text);
  // Ohne SetColor fällt auch der leere Abschnitt weg.
  Text := ReplaceStr(ReplaceStr(Source, '    procedure SetColor(const AValue: Integer);'#10, ''),
    'write SetColor;', 'write FColor;');
  Text := Copy(Text, 1, Pos('procedure TFoo.SetColor', Text) - 1) + 'end.'#10;
  Layout := TMemberTransfer.ParseLayout(Text, 'TFoo', Tree);
  try
    Text := TTextChanges.Apply(Text, TInlineAccessor.Edits(Layout, TInlineAccessor.InClass(Layout, Options(True),
      nil)));
  finally
    Layout.Free;
    Tree.Free;
  end;
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsFalse(ContainsStr(Text, 'protected'), Text);
end;

procedure TInlineAccessorTests.KnowsOwnReferences;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
  Found: TArray<TTrivialAccessor>;
begin
  Layout := TMemberTransfer.ParseLayout(Source, 'TFoo', Tree);
  try
    Found := TInlineAccessor.InClass(Layout, Options(True), nil);
    Assert.IsTrue(TInlineAccessor.IsOwnReference(Layout, Found[0], TTextPosition.Create(9, 13)));
    Assert.IsTrue(TInlineAccessor.IsOwnReference(Layout, Found[0], TTextPosition.Create(15, 32)));
    Assert.IsTrue(TInlineAccessor.IsOwnReference(Layout, Found[0], TTextPosition.Create(21, 14)));
    Assert.IsFalse(TInlineAccessor.IsOwnReference(Layout, Found[0], TTextPosition.Create(16, 32)));
    Assert.IsFalse(TInlineAccessor.IsOwnReference(Layout, Found[0], TTextPosition.Create(33, 2)));
  finally
    Layout.Free;
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TInlineAccessorTests);

end.
