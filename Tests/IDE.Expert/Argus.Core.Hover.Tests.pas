unit Argus.Core.Hover.Tests;

// Tests für Inhalt und Verlauf des Hover-Tooltips (#588).

interface

uses
  DUnitX.TestFramework,
  Argus.Core.Hover.Contract;

type
  [TestFixture]
  TArgusHoverTests = class
  public
    [Test]
    procedure ReadsArgusParts;
    [Test]
    procedure FallsBackToPlainText;
    [Test]
    procedure ShortensLongChains;
    [Test]
    procedure FindsLinkAtIndex;
    [Test]
    procedure BadgeTitleAndLocation;
    [Test]
    procedure ClassReferenceTitleIsOwnName;
  end;

  [TestFixture]
  TArgusHoverHistoryTests = class
  public
    [Test]
    procedure ClickPinsAndBackReturns;
    [Test]
    procedure SameTypeAddsNoStep;
    [Test]
    procedure KeepsTenStepsAndShortensPath;
    [Test]
    procedure JumpDropsLaterSteps;
    [Test]
    procedure NothingToShowKeepsState;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Argus.Core.Hover.History;

const
  // TGalleryFrameClass = class of TBFrame; TBFrame = class(TFrame) in Gallery.Types.pas.
  HoverJson =
    '{"contents": "TBFrame = class(TFrame)", "argus": {' +
    '"declaration": "TBFrame = class(TFrame)", "unit": "Gallery.Types", "documentation": "Basis aller Seiten.",' +
    '"kind": "class", "file": "C:\\P\\Gallery.Types.pas", "line": 19, "character": 2,' +
    '"docWiki": "https://docwiki/TBFrame",' +
    '"links": [{"name": "TFrame", "unit": "Vcl.Forms", "file": "C:\\RTL\\Vcl.Forms.pas", "line": 500, ' +
    '"character": 2, "start": 16, "length": 6}],' +
    '"chainOf": "TBFrame", "ancestors": [' +
    '{"name": "TBFrame", "file": "C:\\P\\Gallery.Types.pas", "line": 19, "character": 2},' +
    '{"name": "TFrame", "file": "C:\\RTL\\Vcl.Forms.pas", "line": 500, "character": 2},' +
    '{"name": "TObject", "unit": "System", "file": "C:\\RTL\\System.pas", "line": 10, "character": 2}]}}';

function Parse(const AJson: string): TArgusHoverData;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TArgusHoverData.FromHover(Value);
  finally
    Value.Free;
  end;
end;

function Ref(const AName: string; ALine: Integer): TArgusHoverTypeRef;
begin
  Result := Default(TArgusHoverTypeRef);
  Result.Name := AName;
  Result.FileName := 'C:\P\Typen.pas';
  Result.Line := ALine;
end;

function DataFor(const ARef: TArgusHoverTypeRef): TArgusHoverData;
begin
  Result := Default(TArgusHoverData);
  Result.Declaration := ARef.Name + ' = class';
  Result.Location := ARef;
  Result.Location.Name := '';
end;

/// <summary>Holt zu jedem Typ mit Fundort einen Inhalt; ohne Fundort nichts.</summary>
function Fetch(const ARef: TArgusHoverTypeRef; out AData: TArgusHoverData): Boolean;
begin
  AData := DataFor(ARef);
  Result := ARef.HasLocation;
end;

{ TArgusHoverTests }

procedure TArgusHoverTests.ReadsArgusParts;
var
  Data: TArgusHoverData;
begin
  Data := Parse(HoverJson);
  Assert.IsTrue(Data.Found);
  Assert.AreEqual('TBFrame = class(TFrame)', Data.Declaration);
  Assert.AreEqual('Gallery.Types', Data.UnitName);
  Assert.AreEqual('Basis aller Seiten.', Data.Documentation);
  Assert.AreEqual('class', Data.Kind);
  Assert.AreEqual('https://docwiki/TBFrame', Data.DocWiki);
  Assert.AreEqual('C:\P\Gallery.Types.pas', Data.Location.FileName);
  Assert.AreEqual(19, Data.Location.Line);
  Assert.AreEqual('TBFrame', Data.Location.Name, 'aus dem ersten Kettenglied');
  Assert.AreEqual(1, Integer(Length(Data.Links)));
  Assert.AreEqual(16, Data.Links[0].Start);
  Assert.AreEqual('TFrame', Data.Links[0].Target.Name);
  Assert.AreEqual(500, Data.Links[0].Target.Line);
  Assert.AreEqual('TBFrame', Data.ChainOf);
  Assert.AreEqual(3, Integer(Length(Data.Ancestors)));
  Assert.AreEqual('System', Data.Ancestors[2].UnitName);
end;

procedure TArgusHoverTests.FallsBackToPlainText;
var
  Data: TArgusHoverData;
begin
  Data := Parse('{"contents": {"kind": "markdown", "value": "```pascal\nprocedure Lauf;\n```\n\nStartet."}}');
  Assert.AreEqual('procedure Lauf;', Data.Declaration);
  Assert.AreEqual('Startet.', Data.Documentation);
  Assert.AreEqual(0, Integer(Length(Data.Links)));
  Assert.IsFalse(Data.Location.HasLocation);
  Assert.IsFalse(TArgusHoverData.FromHover(nil).Found);
end;

procedure TArgusHoverTests.ShortensLongChains;
var
  Data: TArgusHoverData;
  Index: Integer;
  Chain: TArray<Integer>;
begin
  Data := Default(TArgusHoverData);
  for Index := 0 to 4 do
    Data.Ancestors := Data.Ancestors + [Ref('T' + IntToStr(Index), Index)];
  Assert.AreEqual(5, Integer(Length(Data.VisibleChain)), 'fünf Glieder ganz');
  Data.Ancestors := Data.Ancestors + [Ref('T5', 5), Ref('TObject', 6)];
  Chain := Data.VisibleChain;
  // Die ersten vier, dann "…", dann das letzte.
  Assert.AreEqual(6, Integer(Length(Chain)));
  Assert.AreEqual(0, Chain[0]);
  Assert.AreEqual(3, Chain[3]);
  Assert.AreEqual(-1, Chain[4]);
  Assert.AreEqual(6, Chain[5]);
end;

procedure TArgusHoverTests.FindsLinkAtIndex;
var
  Data: TArgusHoverData;
begin
  Data := Parse(HoverJson);
  Assert.AreEqual(-1, Data.LinkAt(15));
  Assert.AreEqual(0, Data.LinkAt(16));
  Assert.AreEqual(0, Data.LinkAt(21));
  Assert.AreEqual(-1, Data.LinkAt(22));
end;

procedure TArgusHoverTests.BadgeTitleAndLocation;
var
  Data: TArgusHoverData;
begin
  Data := Parse(HoverJson);
  Assert.AreEqual('ty', Data.Badge);
  Assert.AreEqual('TBFrame', Data.Title);
  Assert.AreEqual('Gallery.Types.pas : 20', Data.LocationText);
  Data := Default(TArgusHoverData);
  Data.Declaration := 'procedure Lauf(A: Integer);';
  Data.Kind := 'routine';
  Data.UnitName := 'Haupt';
  Assert.AreEqual('fn', Data.Badge);
  Assert.AreEqual('Lauf', Data.Title);
  Assert.AreEqual('Haupt', Data.LocationText, 'ohne Fundort die Unit');
end;

procedure TArgusHoverTests.ClassReferenceTitleIsOwnName;
var
  Data: TArgusHoverData;
begin
  Data := Default(TArgusHoverData);
  Data.Declaration := 'TGalleryFrameClass = class of TBFrame;';
  Data.Kind := TArgusHoverData.KindClassRef;
  Data.ChainOf := 'TBFrame';
  Data.Ancestors := [Ref('TBFrame', 19), Ref('TObject', 10)];
  // Die Kette gehört zum Zieltyp, der Titel ist die Klassenreferenz selbst.
  Assert.AreEqual('TGalleryFrameClass', Data.Title);
end;

{ TArgusHoverHistoryTests }

procedure TArgusHoverHistoryTests.ClickPinsAndBackReturns;
var
  History: TArgusHoverHistory;
begin
  History := TArgusHoverHistory.Create(Fetch);
  try
    History.Start(DataFor(Ref('TGalleryFrameClass', 18)));
    Assert.IsFalse(History.Pinned, 'Kurzform');
    Assert.IsTrue(History.Open(Ref('TBFrame', 19)));
    Assert.IsTrue(History.Pinned, 'erster Klick heftet an');
    Assert.AreEqual(2, History.Count);
    Assert.AreEqual('TBFrame', History.Current.Location.Name);
    Assert.IsTrue(History.Open(Ref('TFrame', 500)));
    // Klick auf TFrame, dann Rücktaste: wieder TBFrame.
    Assert.IsTrue(History.Back);
    Assert.AreEqual('TBFrame', History.Current.Location.Name);
    Assert.IsTrue(History.Back);
    Assert.IsFalse(History.Back, 'am Anfang');
    Assert.IsTrue(History.Pinned, 'bleibt angeheftet');
  finally
    History.Free;
  end;
end;

procedure TArgusHoverHistoryTests.SameTypeAddsNoStep;
var
  History: TArgusHoverHistory;
begin
  History := TArgusHoverHistory.Create(Fetch);
  try
    History.Start(DataFor(Ref('TBFrame', 19)));
    Assert.IsTrue(History.Open(Ref('TBFrame', 19)));
    Assert.AreEqual(1, History.Count, 'derselbe Typ: kein neuer Eintrag');
    Assert.IsTrue(History.Pinned);
  finally
    History.Free;
  end;
end;

procedure TArgusHoverHistoryTests.KeepsTenStepsAndShortensPath;
var
  History: TArgusHoverHistory;
  Index: Integer;
  Path: TArray<TArgusHoverPathItem>;
begin
  History := TArgusHoverHistory.Create(Fetch);
  try
    History.Start(DataFor(Ref('TStart', 0)));
    // Elf Klicks: zehn Schritte bleiben, die ältesten fallen weg.
    for Index := 1 to 11 do
      Assert.IsTrue(History.Open(Ref('T' + IntToStr(Index), Index)));
    Assert.AreEqual(TArgusHoverHistory.MaxSteps, History.Count);
    Assert.AreEqual('T2', History.Items[0].Location.Name);
    Assert.AreEqual('T11', History.Current.Location.Name);
    Path := History.Path;
    Assert.AreEqual('…', Path[0].Caption, 'Pfad beginnt mit …');
    Assert.AreEqual(-1, Path[0].Index);
    Assert.AreEqual(TArgusHoverHistory.MaxPathShown + 1, Integer(Length(Path)));
    Assert.AreEqual('T11', Path[High(Path)].Caption);
    Assert.AreEqual(History.Count - 1, Path[High(Path)].Index);
  finally
    History.Free;
  end;
end;

procedure TArgusHoverHistoryTests.JumpDropsLaterSteps;
var
  History: TArgusHoverHistory;
begin
  History := TArgusHoverHistory.Create(Fetch);
  try
    History.Start(DataFor(Ref('TA', 1)));
    History.Open(Ref('TB', 2));
    History.Open(Ref('TC', 3));
    Assert.AreEqual(3, Integer(Length(History.Path)), 'ohne … bei wenigen Einträgen');
    Assert.IsTrue(History.JumpTo(1));
    Assert.AreEqual(2, History.Count);
    Assert.AreEqual('TB', History.Current.Location.Name);
    Assert.IsFalse(History.JumpTo(5));
  finally
    History.Free;
  end;
end;

procedure TArgusHoverHistoryTests.NothingToShowKeepsState;
var
  History: TArgusHoverHistory;
  NoLocation: TArgusHoverTypeRef;
begin
  History := TArgusHoverHistory.Create(Fetch);
  try
    History.Start(DataFor(Ref('TA', 1)));
    NoLocation := Default(TArgusHoverTypeRef);
    NoLocation.Name := 'TUnbekannt';
    Assert.IsFalse(History.Open(NoLocation));
    Assert.AreEqual(1, History.Count);
    Assert.IsFalse(History.Pinned);
    History.Clear;
    Assert.IsFalse(History.Open(Ref('TB', 2)), 'ohne Start nichts');
  finally
    History.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusHoverTests);
  TDUnitX.RegisterTestFixture(TArgusHoverHistoryTests);

end.
