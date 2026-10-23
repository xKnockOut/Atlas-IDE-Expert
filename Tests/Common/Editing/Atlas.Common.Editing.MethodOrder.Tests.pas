unit Atlas.Common.Editing.MethodOrder.Tests;

// Methodenrümpfe in Deklarationsreihenfolge (#660): Ordnen der ganzen Unit
// und Einfügestelle neuer Rümpfe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMethodOrderTests = class
  public
    [Test]
    procedure ArrangesClassesOverloadsNestedAndRegion;
    [Test]
    procedure ArrangeTwiceChangesNothing;
    [Test]
    procedure ArrangesAlphabetically;
    [Test]
    procedure KeepsBodiesInConditionals;
    [Test]
    procedure KeepsCommentsWithTheirBody;
    [Test]
    procedure OffDoesNothing;
    [Test]
    procedure PlacesNewMiddleMethod;
    [Test]
    procedure PlacesNewFirstMethod;
    [Test]
    procedure PlacesNewLastMethod;
    [Test]
    procedure PlacesTypeWithoutBodies;
    [Test]
    procedure LeavesNewBodyInPlace;
    [Test]
    procedure IgnoresKnownAndHalfTypedBodies;
    [Test]
    procedure Names;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.MethodOrder;

const
  Kopf =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '    procedure Laden;'#10 +
    '    procedure Speichern(A: Integer); overload;'#10 +
    '    procedure Speichern(const S: string); overload;'#10 +
    '    class function Neu: TKunde;'#10 +
    '  end;'#10 +
    '  TAussen = class'#10 +
    '  type'#10 +
    '    TInnen = class'#10 +
    '      procedure Lauf;'#10 +
    '    end;'#10 +
    '  public'#10 +
    '    procedure Machen;'#10 +
    '  end;'#10 +
    'implementation'#10;
  Machen =
    #10'procedure TAussen.Machen;'#10'begin'#10'end;'#10;
  SpeichernText =
    #10'// Speichert als Text.'#10'procedure TKunde.Speichern(const S: string);'#10'begin'#10'end;'#10;
  Hilfe =
    #10'procedure Hilfe;'#10'begin'#10'end;'#10;
  Neu =
    #10'class function TKunde.Neu: TKunde;'#10'begin'#10'  Result := nil;'#10'end;'#10;
  Laden =
    #10'{$REGION ''Laden''}'#10'procedure TKunde.Laden;'#10'begin'#10'end;'#10'{$ENDREGION}'#10;
  Lauf =
    #10'procedure TAussen.TInnen.Lauf;'#10'begin'#10'end;'#10;
  SpeichernZahl =
    #10'procedure TKunde.Speichern(A: Integer);'#10'begin'#10'end;'#10;
  Ende = #10'end.';

  FooKopf =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure A;'#10 +
    '    procedure B;'#10 +
    '    procedure C;'#10 +
    '  end;'#10 +
    '  TBar = class'#10 +
    '    procedure X;'#10 +
    '  end;'#10 +
    'implementation'#10;

function Foo(const ANames: array of string): string;
var
  Name: string;
begin
  Result := FooKopf;
  for Name in ANames do
    Result := Result + #10'procedure ' + Name + ';'#10'begin'#10'end;'#10;
  Result := Result + Ende;
end;

function Arranged(const AText: string; APlacement: TMethodPlacement; out AResult: TMethodOrderResult): string;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    AResult := TMethodOrder.Arrange(Tree, AText, APlacement);
  finally
    Tree.Free;
  end;
  Result := TChangeSignature.ApplyEdits(AText, AResult.Edits);
end;

function Placed(const ABefore, AText: string; out AResult: TMethodOrderResult): string;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    AResult := TMethodOrder.PlaceNew(Tree, AText, ABefore, TMethodPlacement.Declaration);
  finally
    Tree.Free;
  end;
  Result := TChangeSignature.ApplyEdits(AText, AResult.Edits);
end;

function ParsesClean(const AText: string): Boolean;
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

function Count(const AText, APart: string): Integer;
var
  Offset: Integer;
begin
  Result := 0;
  Offset := Pos(APart, AText);
  while Offset > 0 do
  begin
    Inc(Result);
    Offset := Pos(APart, AText, Offset + Length(APart));
  end;
end;

{ TMethodOrderTests }

procedure TMethodOrderTests.ArrangesClassesOverloadsNestedAndRegion;
var
  Text, Done: string;
  Order: TMethodOrderResult;
  Part: string;
begin
  Text := Kopf + Machen + SpeichernText + Hilfe + Neu + Laden + Lauf + SpeichernZahl + Ende;
  Done := Arranged(Text, TMethodPlacement.Declaration, Order);
  // Freie Routine und Region bleiben, TKunde vor TAussen vor TAussen.TInnen.
  Assert.AreEqual(Kopf + SpeichernZahl + SpeichernText + Hilfe + Neu + Laden + Machen + Lauf + Ende, Done);
  Assert.IsTrue(ParsesClean(Done), 'Ergebnis parst');
  for Part in TArray<string>.Create(Machen, SpeichernText, Hilfe, Neu, Laden, Lauf, SpeichernZahl) do
    Assert.AreEqual(1, Count(Done, Part), 'derselbe Rumpf genau einmal');
  Assert.AreEqual(4, Integer(Length(Order.Moves)));
  Assert.AreEqual('Speichern', Order.Moves[0].Name);
  Assert.AreEqual(-4, Order.Moves[0].Delta);
  Assert.AreEqual('procedure TKunde.Speichern(A: Integer);', Done.Split([#10])[Order.Moves[0].NewLine]);
  Assert.AreEqual(3, Order.Moves[0].Size);
  Assert.AreEqual('TAussen', Order.Moves[1].TypeName);
  Assert.AreEqual(3, Order.Moves[1].Delta);
  Assert.AreEqual('TAussen.TInnen', Order.Moves[2].TypeName);
  Assert.AreEqual(1, Order.Moves[2].Delta);
  Assert.AreEqual('Laden', Order.Moves[3].Name);
  Assert.IsTrue(Order.Moves[3].Fixed, 'in der Region: bleibt');
  Assert.AreEqual(-1, Order.Moves[3].NewLine);
  Assert.AreEqual('region', TMethodOrder.ReasonName(Order.Moves[3].Reason));
end;

procedure TMethodOrderTests.ArrangeTwiceChangesNothing;
var
  Done: string;
  Order: TMethodOrderResult;
begin
  Done := Arranged(Kopf + Machen + SpeichernText + Hilfe + Neu + Laden + Lauf + SpeichernZahl + Ende,
    TMethodPlacement.Declaration, Order);
  Arranged(Done, TMethodPlacement.Declaration, Order);
  Assert.AreEqual(0, Integer(Length(Order.Edits)));
end;

procedure TMethodOrderTests.ArrangesAlphabetically;
var
  Order: TMethodOrderResult;
begin
  Assert.AreEqual(Kopf + Neu + SpeichernZahl + Hilfe + SpeichernText + Laden + Machen + Lauf + Ende,
    Arranged(Kopf + Machen + SpeichernText + Hilfe + Neu + Laden + Lauf + SpeichernZahl + Ende,
    TMethodPlacement.Alphabetical, Order));
end;

procedure TMethodOrderTests.KeepsBodiesInConditionals;
var
  Text: string;
  Order: TMethodOrderResult;
begin
  Text := FooKopf + #10'{$IFDEF DEBUG}'#10'procedure TFoo.C;'#10'begin'#10'end;'#10'{$ENDIF}'#10 +
    #10'procedure TFoo.B;'#10'begin'#10'end;'#10 + #10'procedure TFoo.A;'#10'begin'#10'end;'#10 + Ende;
  Assert.AreEqual(FooKopf + #10'{$IFDEF DEBUG}'#10'procedure TFoo.C;'#10'begin'#10'end;'#10'{$ENDIF}'#10 +
    #10'procedure TFoo.A;'#10'begin'#10'end;'#10 + #10'procedure TFoo.B;'#10'begin'#10'end;'#10 + Ende,
    Arranged(Text, TMethodPlacement.Declaration, Order));
  Assert.AreEqual(3, Integer(Length(Order.Moves)));
  Assert.AreEqual('C', Order.Moves[2].Name);
  Assert.AreEqual('ifdef', TMethodOrder.ReasonName(Order.Moves[2].Reason));
end;

procedure TMethodOrderTests.KeepsCommentsWithTheirBody;
var
  Text: string;
  Order: TMethodOrderResult;
begin
  // Der Kommentar mit Leerzeile davor gehört nicht zum Rumpf, der ohne schon.
  Text := FooKopf + #10'{ Abschnitt }'#10 + #10'/// B'#10'{ zweizeilig'#10'  }'#10'procedure TFoo.B;'#10 +
    'begin'#10'end;'#10 + #10'procedure TFoo.A;'#10'begin'#10'end;'#10 + Ende;
  Assert.AreEqual(FooKopf + #10'{ Abschnitt }'#10 + #10'procedure TFoo.A;'#10'begin'#10'end;'#10 +
    #10'/// B'#10'{ zweizeilig'#10'  }'#10'procedure TFoo.B;'#10'begin'#10'end;'#10 + Ende,
    Arranged(Text, TMethodPlacement.Declaration, Order));
end;

procedure TMethodOrderTests.OffDoesNothing;
var
  Order: TMethodOrderResult;
begin
  Arranged(Foo(['TFoo.C', 'TFoo.A']), TMethodPlacement.Off, Order);
  Assert.AreEqual(0, Integer(Length(Order.Edits)));
  Placed(Foo(['TFoo.A']), Foo(['TFoo.C', 'TFoo.A']), Order);
  Assert.AreEqual(1, Integer(Length(Order.Edits)), 'Gegenprobe');
end;

procedure TMethodOrderTests.PlacesNewMiddleMethod;
var
  Order: TMethodOrderResult;
begin
  Assert.AreEqual(Foo(['TFoo.A', 'TFoo.B', 'TFoo.C']),
    Placed(Foo(['TFoo.A', 'TFoo.C']), Foo(['TFoo.A', 'TFoo.C', 'TFoo.B']), Order));
  Assert.AreEqual(1, Integer(Length(Order.Moves)));
  Assert.AreEqual('B', Order.Moves[0].Name);
  Assert.AreEqual(-1, Order.Moves[0].Delta);
  Assert.AreEqual(17, Order.Moves[0].NewLine);
  Assert.AreEqual(21, Order.Moves[0].Line);
end;

procedure TMethodOrderTests.PlacesNewFirstMethod;
var
  Order: TMethodOrderResult;
begin
  Assert.AreEqual(Foo(['TFoo.A', 'TFoo.B', 'TFoo.C']),
    Placed(Foo(['TFoo.B', 'TFoo.C']), Foo(['TFoo.B', 'TFoo.C', 'TFoo.A']), Order));
end;

procedure TMethodOrderTests.PlacesNewLastMethod;
var
  Order: TMethodOrderResult;
begin
  Assert.AreEqual(Foo(['TFoo.A', 'TFoo.B', 'TFoo.C']),
    Placed(Foo(['TFoo.A', 'TFoo.B']), Foo(['TFoo.C', 'TFoo.A', 'TFoo.B']), Order));
  Assert.AreEqual(2, Order.Moves[0].Delta);
end;

procedure TMethodOrderTests.PlacesTypeWithoutBodies;
var
  Order: TMethodOrderResult;
begin
  Assert.AreEqual(Foo(['TFoo.A', 'TFoo.C', 'TBar.X']),
    Placed(Foo(['TFoo.A', 'TFoo.C']), Foo(['TBar.X', 'TFoo.A', 'TFoo.C']), Order));
  // Zwei neue auf einmal (Strg+Umschalt+C für die ganze Klasse).
  Assert.AreEqual(Foo(['TFoo.A', 'TFoo.B', 'TFoo.C', 'TBar.X']),
    Placed(Foo(['TFoo.B']), Foo(['TFoo.B', 'TBar.X', 'TFoo.C', 'TFoo.A']), Order));
end;

procedure TMethodOrderTests.LeavesNewBodyInPlace;
var
  Order: TMethodOrderResult;
begin
  Placed(Foo(['TFoo.A', 'TFoo.C']), Foo(['TFoo.A', 'TFoo.B', 'TFoo.C']), Order);
  Assert.AreEqual(0, Integer(Length(Order.Edits)));
end;

procedure TMethodOrderTests.IgnoresKnownAndHalfTypedBodies;
var
  Order: TMethodOrderResult;
  Half: string;
begin
  // Von Hand verschoben: der Kopf stand schon im Text.
  Placed(Foo(['TFoo.B', 'TFoo.A']), Foo(['TFoo.B', 'TFoo.A']), Order);
  Assert.AreEqual(0, Integer(Length(Order.Edits)), 'nichts neu');
  // Halb getippt: der neue Kopf verschluckt den folgenden Rumpf.
  Half := FooKopf + #10'procedure TFoo.C;'#10'begin'#10 + #10'procedure TFoo.A;'#10'begin'#10'end;'#10 + Ende;
  Placed(Foo(['TFoo.A']), Half, Order);
  Assert.AreEqual(0, Integer(Length(Order.Edits)), 'halb getippt');
end;

procedure TMethodOrderTests.Names;
var
  Placement: TMethodPlacement;
begin
  for Placement := Low(TMethodPlacement) to High(TMethodPlacement) do
    Assert.AreEqual(Ord(Placement), Ord(TMethodOrder.PlacementOf(TMethodOrder.PlacementName(Placement))));
  Assert.AreEqual(Ord(TMethodPlacement.Declaration), Ord(TMethodOrder.PlacementOf('')));
  Assert.AreEqual('', TMethodOrder.ReasonName(TMethodStayReason.None));
end;

initialization
  TDUnitX.RegisterTestFixture(TMethodOrderTests);

end.
