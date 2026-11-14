unit Atlas.Common.Editing.MethodOrder.Tests;

// Methodenrümpfe in Deklarationsreihenfolge (#660): Ordnen der ganzen Unit
// und Einfügestelle neuer Rümpfe. Gruppiert mit Lebenszyklus zuerst (#1836)
// und Typkommentare, die mit ihrem Typ wandern oder neu entstehen (#1835).

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
    procedure LeavesNewGroupInPlace;
    [Test]
    procedure IgnoresKnownAndHalfTypedBodies;
    [Test]
    procedure Names;
    [Test]
    procedure GroupsLifecycleAccessorsOverrides;
    [Test]
    procedure LifecycleFirstWithDeclaration;
    [Test]
    procedure TypeCommentMovesWithItsType;
    [Test]
    procedure RegionMovesWithItsType;
    [Test]
    procedure PlaceNewAddsTypeComment;
    [Test]
    procedure PlaceNewKeepsExistingTypeComment;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.TypeComments,
  Atlas.Common.Editing.MethodOrder;

const
  cKopf =
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
  cMachen =
    #10'procedure TAussen.Machen;'#10'begin'#10'end;'#10;
  cSpeichernText =
    #10'// Speichert als Text.'#10'procedure TKunde.Speichern(const S: string);'#10'begin'#10'end;'#10;
  cHilfe =
    #10'procedure Hilfe;'#10'begin'#10'end;'#10;
  cNeu =
    #10'class function TKunde.Neu: TKunde;'#10'begin'#10'  Result := nil;'#10'end;'#10;
  cLaden =
    #10'{$REGION ''Laden''}'#10'procedure TKunde.Laden;'#10'begin'#10'end;'#10'{$ENDREGION}'#10;
  cLauf =
    #10'procedure TAussen.TInnen.Lauf;'#10'begin'#10'end;'#10;
  cSpeichernZahl =
    #10'procedure TKunde.Speichern(A: Integer);'#10'begin'#10'end;'#10;
  cEnde = #10'end.';

  cFooKopf =
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
  mName: string;
begin
  Result := cFooKopf;
  for mName in ANames do
  begin
    Result := Result + #10'procedure ' + mName + ';'#10'begin'#10'end;'#10;
  end;
  Result := Result + cEnde;
end;

function Arranged(const AText: string; APlacement: TMethodPlacement; out AResult: TMethodOrderResult): string;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    AResult := TMethodOrder.Arrange(mTree, AText, APlacement);
  finally
    mTree.Free;
  end;
  Result := TChangeSignature.ApplyEdits(AText, AResult.Edits);
end;

function Placed(const ABefore, AText: string; out AResult: TMethodOrderResult): string;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    AResult := TMethodOrder.PlaceNew(mTree, AText, ABefore, TMethodPlacement.Declaration);
  finally
    mTree.Free;
  end;
  Result := TChangeSignature.ApplyEdits(AText, AResult.Edits);
end;

function ParsesClean(const AText: string): Boolean;
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

function Count(const AText, APart: string): Integer;
var
  mOffset: Integer;
begin
  Result := 0;
  mOffset := Pos(APart, AText);
  while mOffset > 0 do
  begin
    Inc(Result);
    mOffset := Pos(APart, AText, mOffset + Length(APart));
  end;
end;

{ TMethodOrderTests }

procedure TMethodOrderTests.ArrangesClassesOverloadsNestedAndRegion;
var
  mText, mDone: string;
  mOrder: TMethodOrderResult;
  mPart: string;
begin
  mText := cKopf + cMachen + cSpeichernText + cHilfe + cNeu + cLaden + cLauf + cSpeichernZahl + cEnde;
  mDone := Arranged(mText, TMethodPlacement.Declaration, mOrder);
  // Freie Routine und Region bleiben, TKunde vor TAussen vor TAussen.TInnen.
  Assert.AreEqual(cKopf + cSpeichernZahl + cSpeichernText + cHilfe + cNeu + cLaden + cMachen + cLauf + cEnde, mDone);
  Assert.IsTrue(ParsesClean(mDone), 'Ergebnis parst');
  for mPart in TArray<string>.Create(cMachen, cSpeichernText, cHilfe, cNeu, cLaden, cLauf, cSpeichernZahl) do
  begin
    Assert.AreEqual(1, Count(mDone, mPart), 'derselbe Rumpf genau einmal');
  end;
  Assert.AreEqual(4, Integer(Length(mOrder.Moves)));
  Assert.AreEqual('Speichern', mOrder.Moves[0].Name);
  Assert.AreEqual(-4, mOrder.Moves[0].Delta);
  Assert.AreEqual('procedure TKunde.Speichern(A: Integer);', mDone.Split([#10])[mOrder.Moves[0].NewLine]);
  Assert.AreEqual(3, mOrder.Moves[0].Size);
  Assert.AreEqual('TAussen', mOrder.Moves[1].TypeName);
  Assert.AreEqual(3, mOrder.Moves[1].Delta);
  Assert.AreEqual('TAussen.TInnen', mOrder.Moves[2].TypeName);
  Assert.AreEqual(1, mOrder.Moves[2].Delta);
  Assert.AreEqual('Laden', mOrder.Moves[3].Name);
  Assert.IsTrue(mOrder.Moves[3].Fixed, 'in der Region: bleibt');
  Assert.AreEqual(-1, mOrder.Moves[3].NewLine);
  Assert.AreEqual('region', TMethodOrder.ReasonName(mOrder.Moves[3].Reason));
end;

procedure TMethodOrderTests.ArrangeTwiceChangesNothing;
var
  mDone: string;
  mOrder: TMethodOrderResult;
begin
  mDone := Arranged(cKopf + cMachen + cSpeichernText + cHilfe + cNeu + cLaden + cLauf + cSpeichernZahl + cEnde,
    TMethodPlacement.Declaration, mOrder);
  Arranged(mDone, TMethodPlacement.Declaration, mOrder);
  Assert.AreEqual(0, Integer(Length(mOrder.Edits)));
end;

procedure TMethodOrderTests.ArrangesAlphabetically;
var
  mOrder: TMethodOrderResult;
begin
  Assert.AreEqual(cKopf + cNeu + cSpeichernZahl + cHilfe + cSpeichernText + cLaden + cMachen + cLauf + cEnde,
    Arranged(cKopf + cMachen + cSpeichernText + cHilfe + cNeu + cLaden + cLauf + cSpeichernZahl + cEnde,
    TMethodPlacement.Alphabetical, mOrder));
end;

procedure TMethodOrderTests.KeepsBodiesInConditionals;
var
  mText: string;
  mOrder: TMethodOrderResult;
begin
  mText := cFooKopf + #10'{$IFDEF DEBUG}'#10'procedure TFoo.C;'#10'begin'#10'end;'#10'{$ENDIF}'#10 +
    #10'procedure TFoo.B;'#10'begin'#10'end;'#10 + #10'procedure TFoo.A;'#10'begin'#10'end;'#10 + cEnde;
  Assert.AreEqual(cFooKopf + #10'{$IFDEF DEBUG}'#10'procedure TFoo.C;'#10'begin'#10'end;'#10'{$ENDIF}'#10 +
    #10'procedure TFoo.A;'#10'begin'#10'end;'#10 + #10'procedure TFoo.B;'#10'begin'#10'end;'#10 + cEnde,
    Arranged(mText, TMethodPlacement.Declaration, mOrder));
  Assert.AreEqual(3, Integer(Length(mOrder.Moves)));
  Assert.AreEqual('C', mOrder.Moves[2].Name);
  Assert.AreEqual('ifdef', TMethodOrder.ReasonName(mOrder.Moves[2].Reason));
end;

procedure TMethodOrderTests.KeepsCommentsWithTheirBody;
var
  mText: string;
  mOrder: TMethodOrderResult;
begin
  // Der Kommentar mit Leerzeile davor gehört nicht zum Rumpf, der ohne schon.
  mText := cFooKopf + #10'{ Abschnitt }'#10 + #10'/// B'#10'{ zweizeilig'#10'  }'#10'procedure TFoo.B;'#10 +
    'begin'#10'end;'#10 + #10'procedure TFoo.A;'#10'begin'#10'end;'#10 + cEnde;
  Assert.AreEqual(cFooKopf + #10'{ Abschnitt }'#10 + #10'procedure TFoo.A;'#10'begin'#10'end;'#10 +
    #10'/// B'#10'{ zweizeilig'#10'  }'#10'procedure TFoo.B;'#10'begin'#10'end;'#10 + cEnde,
    Arranged(mText, TMethodPlacement.Declaration, mOrder));
end;

procedure TMethodOrderTests.OffDoesNothing;
var
  mOrder: TMethodOrderResult;
begin
  Arranged(Foo(['TFoo.C', 'TFoo.A']), TMethodPlacement.Off, mOrder);
  Assert.AreEqual(0, Integer(Length(mOrder.Edits)));
  Placed(Foo(['TFoo.A']), Foo(['TFoo.C', 'TFoo.A']), mOrder);
  Assert.AreEqual(1, Integer(Length(mOrder.Edits)), 'Gegenprobe');
end;

procedure TMethodOrderTests.PlacesNewMiddleMethod;
var
  mOrder: TMethodOrderResult;
begin
  Assert.AreEqual(Foo(['TFoo.A', 'TFoo.B', 'TFoo.C']),
    Placed(Foo(['TFoo.A', 'TFoo.C']), Foo(['TFoo.A', 'TFoo.C', 'TFoo.B']), mOrder));
  Assert.AreEqual(1, Integer(Length(mOrder.Moves)));
  Assert.AreEqual('B', mOrder.Moves[0].Name);
  Assert.AreEqual(-1, mOrder.Moves[0].Delta);
  Assert.AreEqual(17, mOrder.Moves[0].NewLine);
  Assert.AreEqual(21, mOrder.Moves[0].Line);
end;

procedure TMethodOrderTests.PlacesNewFirstMethod;
var
  mOrder: TMethodOrderResult;
begin
  Assert.AreEqual(Foo(['TFoo.A', 'TFoo.B', 'TFoo.C']),
    Placed(Foo(['TFoo.B', 'TFoo.C']), Foo(['TFoo.B', 'TFoo.C', 'TFoo.A']), mOrder));
end;

procedure TMethodOrderTests.PlacesNewLastMethod;
var
  mOrder: TMethodOrderResult;
begin
  Assert.AreEqual(Foo(['TFoo.A', 'TFoo.B', 'TFoo.C']),
    Placed(Foo(['TFoo.A', 'TFoo.B']), Foo(['TFoo.C', 'TFoo.A', 'TFoo.B']), mOrder));
  Assert.AreEqual(2, mOrder.Moves[0].Delta);
end;

procedure TMethodOrderTests.PlacesTypeWithoutBodies;
var
  mOrder: TMethodOrderResult;
begin
  Assert.AreEqual(Foo(['TFoo.A', 'TFoo.C', 'TBar.X']),
    Placed(Foo(['TFoo.A', 'TFoo.C']), Foo(['TBar.X', 'TFoo.A', 'TFoo.C']), mOrder));
  // Zwei neue auf einmal (Strg+Umschalt+C für die ganze Klasse).
  Assert.AreEqual(Foo(['TFoo.A', 'TFoo.B', 'TFoo.C', 'TBar.X']),
    Placed(Foo(['TFoo.B']), Foo(['TFoo.B', 'TBar.X', 'TFoo.C', 'TFoo.A']), mOrder));
end;

procedure TMethodOrderTests.LeavesNewBodyInPlace;
var
  mOrder: TMethodOrderResult;
begin
  Placed(Foo(['TFoo.A', 'TFoo.C']), Foo(['TFoo.A', 'TFoo.B', 'TFoo.C']), mOrder);
  Assert.AreEqual(0, Integer(Length(mOrder.Edits)));
end;

procedure TMethodOrderTests.LeavesNewGroupInPlace;
var
  mOrder: TMethodOrderResult;
begin
  // Zwei neue Rümpfe direkt hinter ihrem Ziel: die ganze Gruppe bleibt, auch der zweite.
  Placed(Foo(['TFoo.A']), Foo(['TFoo.A', 'TFoo.B', 'TFoo.C']), mOrder);
  Assert.AreEqual(0, Integer(Length(mOrder.Edits)));
end;

procedure TMethodOrderTests.IgnoresKnownAndHalfTypedBodies;
var
  mOrder: TMethodOrderResult;
  mHalf: string;
begin
  // Von Hand verschoben: der Kopf stand schon im Text.
  Placed(Foo(['TFoo.B', 'TFoo.A']), Foo(['TFoo.B', 'TFoo.A']), mOrder);
  Assert.AreEqual(0, Integer(Length(mOrder.Edits)), 'nichts neu');
  // Halb getippt: der neue Kopf verschluckt den folgenden Rumpf.
  mHalf := cFooKopf + #10'procedure TFoo.C;'#10'begin'#10 + #10'procedure TFoo.A;'#10'begin'#10'end;'#10 + cEnde;
  Placed(Foo(['TFoo.A']), mHalf, mOrder);
  Assert.AreEqual(0, Integer(Length(mOrder.Edits)), 'halb getippt');
end;

procedure TMethodOrderTests.Names;
var
  mPlacement: TMethodPlacement;
begin
  for mPlacement := Low(TMethodPlacement) to High(TMethodPlacement) do
  begin
    Assert.AreEqual(Ord(mPlacement), Ord(TMethodOrder.PlacementOf(TMethodOrder.PlacementName(mPlacement))));
  end;
  Assert.AreEqual(Ord(TMethodPlacement.Grouped), Ord(TMethodOrder.PlacementOf('')), 'Vorgabe gruppiert (#1836)');
  Assert.AreEqual('', TMethodOrder.ReasonName(TMethodStayReason.None));
end;

const
  cGruppeKopf =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFenster = class(TBasis)'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    procedure Zeichnen;'#10 +
    '    function GetName: string;'#10 +
    '    procedure SetName(const AValue: string);'#10 +
    '  protected'#10 +
    '    procedure Paint; override;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    destructor Destroy; override;'#10 +
    '    property Name: string read GetName write SetName;'#10 +
    '  end;'#10 +
    'implementation'#10;

function Body(const AName: string): string;
begin
  Result := #10 + AName + ';'#10'begin'#10'end;'#10;
end;

function Grouped: string;
begin
  Result := cGruppeKopf + Body('procedure TFenster.Zeichnen') + Body('function TFenster.GetName: string') +
    Body('procedure TFenster.SetName(const AValue: string)') + Body('procedure TFenster.Paint') +
    Body('constructor TFenster.Create') + Body('destructor TFenster.Destroy') + cEnde;
end;

function ArrangedWith(const AText: string; const AOptions: TMethodOrderOptions): string;
var
  mTree: TSyntaxTree;
  mOrder: TMethodOrderResult;
begin
  mTree := TPascalParser.Parse(AText);
  try
    mOrder := TMethodOrder.Arrange(mTree, AText, AOptions);
  finally
    mTree.Free;
  end;
  Result := TChangeSignature.ApplyEdits(AText, mOrder.Edits);
end;

function PlacedWith(const ABefore, AText: string; const AOptions: TMethodOrderOptions): string;
var
  mTree: TSyntaxTree;
  mOrder: TMethodOrderResult;
begin
  mTree := TPascalParser.Parse(AText);
  try
    mOrder := TMethodOrder.PlaceNew(mTree, AText, ABefore, AOptions);
  finally
    mTree.Free;
  end;
  Result := TChangeSignature.ApplyEdits(AText, mOrder.Edits);
end;

procedure TMethodOrderTests.GroupsLifecycleAccessorsOverrides;
var
  mDone: string;
begin
  mDone := ArrangedWith(Grouped, TMethodOrderOptions.Create(TMethodPlacement.Grouped));
  Assert.AreEqual(cGruppeKopf + Body('constructor TFenster.Create') + Body('destructor TFenster.Destroy') +
    Body('function TFenster.GetName: string') + Body('procedure TFenster.SetName(const AValue: string)') +
    Body('procedure TFenster.Paint') + Body('procedure TFenster.Zeichnen') + cEnde, mDone);
  Assert.AreEqual(mDone, ArrangedWith(mDone, TMethodOrderOptions.Create(TMethodPlacement.Grouped)),
    'zweites Ordnen ändert nichts');
end;

procedure TMethodOrderTests.LifecycleFirstWithDeclaration;
var
  mOptions: TMethodOrderOptions;
begin
  mOptions := TMethodOrderOptions.Create(TMethodPlacement.Declaration);
  mOptions.LifecycleFirst := True;
  Assert.AreEqual(cGruppeKopf + Body('constructor TFenster.Create') + Body('destructor TFenster.Destroy') +
    Body('procedure TFenster.Zeichnen') + Body('function TFenster.GetName: string') +
    Body('procedure TFenster.SetName(const AValue: string)') + Body('procedure TFenster.Paint') + cEnde,
    ArrangedWith(Grouped, mOptions));
  mOptions.LifecycleFirst := False;
  Assert.AreEqual(cGruppeKopf + Body('procedure TFenster.Zeichnen') + Body('function TFenster.GetName: string') +
    Body('procedure TFenster.SetName(const AValue: string)') + Body('procedure TFenster.Paint') +
    Body('constructor TFenster.Create') + Body('destructor TFenster.Destroy') + cEnde,
    ArrangedWith(Grouped, mOptions), 'ohne Vorziehen wie deklariert');
end;

procedure TMethodOrderTests.TypeCommentMovesWithItsType;
var
  mText, mDone: string;
begin
  // TBar steht vorn, ist aber nach TFoo deklariert: Kommentar { TBar } wandert mit.
  mText := cFooKopf + #10'{ TBar }'#10 + Body('procedure TBar.X') + #10'{ TFoo }'#10 + Body('procedure TFoo.A') + cEnde;
  mDone := ArrangedWith(mText, TMethodOrderOptions.Create(TMethodPlacement.Declaration));
  Assert.AreEqual(cFooKopf + #10'{ TFoo }'#10 + Body('procedure TFoo.A') + #10'{ TBar }'#10 +
    Body('procedure TBar.X') + cEnde, mDone);
  Assert.IsTrue(ParsesClean(mDone));
end;

procedure TMethodOrderTests.RegionMovesWithItsType;
var
  mText, mDone: string;
begin
  mText := cFooKopf + #10'{$REGION ''TBar''}'#10 + Body('procedure TBar.X') + '{$ENDREGION}'#10 +
    #10'{$REGION ''TFoo''}'#10 + Body('procedure TFoo.B') + Body('procedure TFoo.A') + '{$ENDREGION}'#10 + cEnde;
  mDone := ArrangedWith(mText, TMethodOrderOptions.Create(TMethodPlacement.Declaration));
  Assert.AreEqual(cFooKopf + #10'{$REGION ''TFoo''}'#10 + Body('procedure TFoo.A') + Body('procedure TFoo.B') +
    '{$ENDREGION}'#10 + #10'{$REGION ''TBar''}'#10 + Body('procedure TBar.X') + '{$ENDREGION}'#10 + cEnde, mDone,
    'Typregion ist kein Hindernis, sie wandert mit');
end;

procedure TMethodOrderTests.PlaceNewAddsTypeComment;
var
  mBefore, mText: string;
  mOptions: TMethodOrderOptions;
begin
  mBefore := cFooKopf + Body('procedure TFoo.A') + cEnde;
  mText := cFooKopf + Body('procedure TFoo.A') + Body('procedure TBar.X') + cEnde;
  mOptions := TMethodOrderOptions.Create(TMethodPlacement.Declaration);
  mOptions.TypeComment := TTypeCommentStyle.Brace;
  Assert.AreEqual(cFooKopf + Body('procedure TFoo.A') + #10'{ TBar }'#10 + Body('procedure TBar.X') + cEnde,
    PlacedWith(mBefore, mText, mOptions), 'Typ ohne Rümpfe bekommt den Kommentar');
  mOptions.TypeComment := TTypeCommentStyle.Off;
  Assert.AreEqual(mText, PlacedWith(mBefore, mText, mOptions), 'aus: wie bisher');
end;

procedure TMethodOrderTests.PlaceNewKeepsExistingTypeComment;
var
  mBefore, mText: string;
  mOptions: TMethodOrderOptions;
begin
  mBefore := cFooKopf + #10'{ TFoo }'#10 + Body('procedure TFoo.A') + Body('procedure TFoo.C') + cEnde;
  mText := cFooKopf + #10'{ TFoo }'#10 + Body('procedure TFoo.A') + Body('procedure TFoo.C') +
    Body('procedure TFoo.B') + cEnde;
  mOptions := TMethodOrderOptions.Create(TMethodPlacement.Declaration);
  mOptions.TypeComment := TTypeCommentStyle.Brace;
  Assert.AreEqual(cFooKopf + #10'{ TFoo }'#10 + Body('procedure TFoo.A') + Body('procedure TFoo.B') +
    Body('procedure TFoo.C') + cEnde, PlacedWith(mBefore, mText, mOptions), 'kein zweiter Kommentar');
end;

initialization
  TDUnitX.RegisterTestFixture(TMethodOrderTests);

end.
