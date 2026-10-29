unit Atlas.Core.Hover.Tests;

// Tests für Inhalt und Verlauf des Hover-Tooltips (#588).

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Hover.Contract;

type
  [TestFixture]
  TAtlasHoverTests = class
  public
    [Test]
    procedure ReadsAtlasParts;
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
    [Test]
    procedure ReadsStructuredDocumentation;
    /// <summary>#1123: Nur Begründungen strukturiert; die Doku als Klartext bleibt davor.</summary>
    [Test]
    procedure KeepsPlainDocumentationBeforeRationale;
    /// <summary>#110: atlas.published, Filter und Liste für die Zwischenablage.</summary>
    [Test]
    procedure ReadsPublishedMembers;
    [Test]
    procedure ReadsReassigned;
  end;

  [TestFixture]
  TAtlasHoverHistoryTests = class
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
  System.Generics.Collections,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Hover.History;

const
  // TGalleryFrameClass = class of TBFrame; TBFrame = class(TFrame) in Gallery.Types.pas.
  HoverJson =
    '{"contents": "TBFrame = class(TFrame)", "atlas": {' +
    '"declaration": "TBFrame = class(TFrame)", "unit": "Gallery.Types", "documentation": "Basis aller Seiten.",' +
    '"kind": "class", "file": "C:\\P\\Gallery.Types.pas", "line": 19, "character": 2,' +
    '"docWiki": "https://docwiki/TBFrame",' +
    '"links": [{"name": "TFrame", "unit": "Vcl.Forms", "file": "C:\\RTL\\Vcl.Forms.pas", "line": 500, ' +
    '"character": 2, "start": 16, "length": 6}],' +
    '"chainOf": "TBFrame", "ancestors": [' +
    '{"name": "TBFrame", "file": "C:\\P\\Gallery.Types.pas", "line": 19, "character": 2},' +
    '{"name": "TFrame", "file": "C:\\RTL\\Vcl.Forms.pas", "line": 500, "character": 2},' +
    '{"name": "TObject", "unit": "System", "file": "C:\\RTL\\System.pas", "line": 10, "character": 2}]}}';

function Parse(const AJson: string): TAtlasHoverData;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasHoverData.FromHover(Value);
  finally
    Value.Free;
  end;
end;

function Ref(const AName: string; ALine: Integer): TAtlasHoverTypeRef;
begin
  Result := Default(TAtlasHoverTypeRef);
  Result.Name := AName;
  Result.FileName := 'C:\P\Typen.pas';
  Result.Line := ALine;
end;

function DataFor(const ARef: TAtlasHoverTypeRef): TAtlasHoverData;
begin
  Result := Default(TAtlasHoverData);
  Result.Declaration := ARef.Name + ' = class';
  Result.Location := ARef;
  Result.Location.Name := '';
end;

/// <summary>Holt zu jedem Typ mit Fundort einen Inhalt; ohne Fundort nichts.</summary>
function Fetch(const ARef: TAtlasHoverTypeRef; out AData: TAtlasHoverData): Boolean;
begin
  AData := DataFor(ARef);
  Result := ARef.HasLocation;
end;

{ TAtlasHoverTests }

procedure TAtlasHoverTests.ReadsStructuredDocumentation;
var
  Data: TAtlasHoverData;
begin
  // #654: documentation als Abschnitte, Klartext in documentationText, Anzeige in xmlDoc.
  Data := Parse('{"contents": "x", "atlas": {"declaration": "constructor Create(AOwner: TComponent);",' +
    '"documentationText": "Legt an.\nAOwner: Besitzer", "documentation": {"sections": [' +
    '{"kind": "summary", "runs": [{"kind": "text", "text": "Legt an."}]},' +
    '{"kind": "param", "name": "AOwner", "runs": [{"kind": "text", "text": "Besitzer"}]}]},' +
    '"xmlDoc": {"expand": "collapsed", "maxLines": 8}}}');
  Assert.AreEqual('Legt an.'#10'AOwner: Besitzer', Data.Documentation);
  Assert.AreEqual(2, Integer(Length(Data.Doc.Sections)));
  Assert.AreEqual('AOwner', Data.Doc.Sections[1].Name);
  Assert.IsTrue(Data.Display.Known);
  Assert.AreEqual(Ord(TAtlasDocExpand.Collapsed), Ord(Data.Display.Expand));
  Assert.AreEqual(8, Data.Display.MaxLines);
  // Ältere Server: documentation als Text, keine Anzeige-Angabe.
  Data := Parse(HoverJson);
  Assert.IsTrue(Data.Doc.IsEmpty);
  Assert.IsFalse(Data.Display.Known);
end;

procedure TAtlasHoverTests.KeepsPlainDocumentationBeforeRationale;
var
  Data: TAtlasHoverData;
begin
  Data := Parse('{"contents": "x", "atlas": {"declaration": "var Zaehler: Integer;",' +
    '"documentationText": "Zaehlt.", "documentation": {"sections": [' +
    '{"kind": "rationale", "name": "WHY", "runs": [{"kind": "text", "text": "Schnell."}]}]}}}');
  Assert.AreEqual(2, Integer(Length(Data.Doc.Sections)));
  Assert.AreEqual(Ord(TAtlasDocSectionKind.Summary), Ord(Data.Doc.Sections[0].Kind));
  Assert.AreEqual('Zaehlt.', Data.Doc.Sections[0].Text);
  Assert.AreEqual(Ord(TAtlasDocSectionKind.Rationale), Ord(Data.Doc.Sections[1].Kind));
end;

procedure TAtlasHoverTests.ReadsPublishedMembers;
var
  Data: TAtlasHoverData;
begin
  Data := Parse('{"contents": "x", "atlas": {"declaration": "TKnopf = class(TBasis)", "file": "C:\\P\\K.pas",' +
    '"line": 3, "character": 2, "ancestors": [{"name": "TKnopf", "file": "C:\\P\\K.pas", "line": 3,' +
    '"character": 2}], "published": {"defaultProperty": "Items[I: Integer]: string", "members": [' +
    '{"name": "Aktiv", "type": "Boolean", "default": "False", "defaultKind": "implicit", "declaringClass": "TKnopf"},' +
    '{"name": "Titel", "type": "string", "stored": "False", "declaringClass": "TBasis"},' +
    '{"name": "Zahl", "type": "Integer", "defaultKind": "nodefault", "declaringClass": "TBasis"},' +
    '{"name": "OnKlick", "type": "TKlickEvent", "declaringClass": "TBasis", "event": true}]}}}');
  Assert.AreEqual(4, Integer(Length(Data.Members)));
  Assert.AreEqual('Items[I: Integer]: string', Data.DefaultProperty);
  Assert.IsTrue(Data.Members[0].DefaultKind = hdImplicit);
  Assert.IsTrue(Data.Members[2].DefaultKind = hdNoDefault);
  Assert.IsTrue(Data.Members[3].IsEvent);
  Assert.AreEqual(3, Data.MemberCount(False));
  Assert.AreEqual(1, Data.MemberCount(True));
  Assert.AreEqual('False (implizit)', Data.Members[0].DefaultText('implizit'));
  Assert.AreEqual('stored False', Data.Members[1].DefaultText('implizit'));
  // Eigene (TKnopf) bzw. nur mit Vorgabe.
  Assert.AreEqual(1, Integer(Length(Data.VisibleMembers(False, False, False))));
  Assert.AreEqual(1, Integer(Length(Data.VisibleMembers(False, True, True))));
  Assert.AreEqual(0, Integer(Length(Data.VisibleMembers(True, False, False))));
  Assert.AreEqual('TKnopf' + sLineBreak + 'Aktiv'#9'Boolean'#9'False (implizit)'#9'TKnopf' + sLineBreak +
    'Titel'#9'string'#9'stored False'#9'TBasis' + sLineBreak + 'Zahl'#9'Integer'#9'nodefault'#9'TBasis' + sLineBreak +
    'OnKlick'#9'TKlickEvent'#9#9'TBasis' + sLineBreak + 'Items[I: Integer]: string'#9'default',
    Data.MembersText(True, False, 'implizit'));
  Assert.IsTrue(Parse(HoverJson).Members = nil);
end;

procedure TAtlasHoverTests.ReadsReassigned;
var
  Data: TAtlasHoverData;
begin
  Data := Parse('{"contents": "x", "atlas": {"declaration": "Summe: Integer", "kind": "variable",' +
    '"reassigned": {"target": "locals", "writes": 3, "lines": [4, 6, 8]}}}');
  Assert.AreEqual('locals', Data.ReassignedTarget);
  Assert.AreEqual(3, Data.ReassignedWrites);
  Assert.AreEqual(3, Integer(Length(Data.ReassignedLines)));
  // Zeilen 1-basiert.
  Assert.AreEqual('3 x 5, 7, 9', Data.ReassignedText('eins %s', '%d x %s'));
  Data.ReassignedWrites := 1;
  Data.ReassignedLines := TArray<Integer>.Create(11);
  Assert.AreEqual('eins 12', Data.ReassignedText('eins %s', '%d x %s'));
  // Mehr als fünf Zeilen werden gekürzt.
  Data.ReassignedWrites := 7;
  Data.ReassignedLines := TArray<Integer>.Create(0, 1, 2, 3, 4, 5, 6);
  Assert.AreEqual('7 x 1, 2, 3, 4, 5, ' + #$2026, Data.ReassignedText('eins %s', '%d x %s'));
  // Ausgeblendet (Einstellung aus oder Art nicht gewaehlt).
  Data.ClearReassigned;
  Assert.AreEqual('', Data.ReassignedTarget);
  Assert.AreEqual('', Data.ReassignedText('eins %s', '%d x %s'));
  // Ohne Angabe nichts.
  Data := Parse(HoverJson);
  Assert.AreEqual('', Data.ReassignedTarget);
  Assert.AreEqual(0, Integer(Length(Data.ReassignedLines)));
end;

procedure TAtlasHoverTests.ReadsAtlasParts;
var
  Data: TAtlasHoverData;
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

procedure TAtlasHoverTests.FallsBackToPlainText;
var
  Data: TAtlasHoverData;
begin
  Data := Parse('{"contents": {"kind": "markdown", "value": "```pascal\nprocedure Lauf;\n```\n\nStartet."}}');
  Assert.AreEqual('procedure Lauf;', Data.Declaration);
  Assert.AreEqual('Startet.', Data.Documentation);
  Assert.AreEqual(0, Integer(Length(Data.Links)));
  Assert.IsFalse(Data.Location.HasLocation);
  Assert.IsFalse(TAtlasHoverData.FromHover(nil).Found);
end;

procedure TAtlasHoverTests.ShortensLongChains;
var
  Data: TAtlasHoverData;
  Index: Integer;
  Chain: TArray<Integer>;
begin
  Data := Default(TAtlasHoverData);
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

procedure TAtlasHoverTests.FindsLinkAtIndex;
var
  Data: TAtlasHoverData;
begin
  Data := Parse(HoverJson);
  Assert.AreEqual(-1, Data.LinkAt(15));
  Assert.AreEqual(0, Data.LinkAt(16));
  Assert.AreEqual(0, Data.LinkAt(21));
  Assert.AreEqual(-1, Data.LinkAt(22));
end;

procedure TAtlasHoverTests.BadgeTitleAndLocation;
var
  Data: TAtlasHoverData;
begin
  Data := Parse(HoverJson);
  Assert.AreEqual('ty', Data.Badge);
  Assert.AreEqual('TBFrame', Data.Title);
  Assert.AreEqual('Gallery.Types.pas : 20', Data.LocationText);
  Data := Default(TAtlasHoverData);
  Data.Declaration := 'procedure Lauf(A: Integer);';
  Data.Kind := 'routine';
  Data.UnitName := 'Haupt';
  Assert.AreEqual('fn', Data.Badge);
  Assert.AreEqual('Lauf', Data.Title);
  Assert.AreEqual('Haupt', Data.LocationText, 'ohne Fundort die Unit');
end;

procedure TAtlasHoverTests.ClassReferenceTitleIsOwnName;
var
  Data: TAtlasHoverData;
begin
  Data := Default(TAtlasHoverData);
  Data.Declaration := 'TGalleryFrameClass = class of TBFrame;';
  Data.Kind := TAtlasHoverData.KindClassRef;
  Data.ChainOf := 'TBFrame';
  Data.Ancestors := [Ref('TBFrame', 19), Ref('TObject', 10)];
  // Die Kette gehört zum Zieltyp, der Titel ist die Klassenreferenz selbst.
  Assert.AreEqual('TGalleryFrameClass', Data.Title);
end;

{ TAtlasHoverHistoryTests }

procedure TAtlasHoverHistoryTests.ClickPinsAndBackReturns;
var
  History: TAtlasHoverHistory;
begin
  History := TAtlasHoverHistory.Create(Fetch);
  try
    History.Start(DataFor(Ref('TGalleryFrameClass', 18)));
    Assert.IsFalse(History.Pinned, 'Kurzform');
    Assert.IsTrue(History.Open(Ref('TBFrame', 19)));
    Assert.IsTrue(History.Pinned, 'erster Klick heftet an');
    Assert.AreEqual(2, Integer(History.Count));
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

procedure TAtlasHoverHistoryTests.SameTypeAddsNoStep;
var
  History: TAtlasHoverHistory;
begin
  History := TAtlasHoverHistory.Create(Fetch);
  try
    History.Start(DataFor(Ref('TBFrame', 19)));
    Assert.IsTrue(History.Open(Ref('TBFrame', 19)));
    Assert.AreEqual(1, Integer(History.Count), 'derselbe Typ: kein neuer Eintrag');
    Assert.IsTrue(History.Pinned);
  finally
    History.Free;
  end;
end;

procedure TAtlasHoverHistoryTests.KeepsTenStepsAndShortensPath;
var
  History: TAtlasHoverHistory;
  Index: Integer;
  Path: TArray<TAtlasHoverPathItem>;
begin
  History := TAtlasHoverHistory.Create(Fetch);
  try
    History.Start(DataFor(Ref('TStart', 0)));
    // Elf Klicks: zehn Schritte bleiben, die ältesten fallen weg.
    for Index := 1 to 11 do
      Assert.IsTrue(History.Open(Ref('T' + IntToStr(Index), Index)));
    Assert.AreEqual(TAtlasHoverHistory.MaxSteps, History.Count);
    Assert.AreEqual('T2', History.Items[0].Location.Name);
    Assert.AreEqual('T11', History.Current.Location.Name);
    Path := History.Path;
    Assert.AreEqual('…', Path[0].Caption, 'Pfad beginnt mit …');
    Assert.AreEqual(-1, Path[0].Index);
    Assert.AreEqual(TAtlasHoverHistory.MaxPathShown, Integer(Length(Path)));
    Assert.AreEqual('T11', Path[High(Path)].Caption);
    Assert.AreEqual(History.Count - 1, Path[High(Path)].Index);
  finally
    History.Free;
  end;
end;

procedure TAtlasHoverHistoryTests.JumpDropsLaterSteps;
var
  History: TAtlasHoverHistory;
begin
  History := TAtlasHoverHistory.Create(Fetch);
  try
    History.Start(DataFor(Ref('TA', 1)));
    History.Open(Ref('TB', 2));
    History.Open(Ref('TC', 3));
    Assert.AreEqual(3, Integer(Length(History.Path)), 'ohne … bei wenigen Einträgen');
    Assert.IsTrue(History.JumpTo(1));
    Assert.AreEqual(2, Integer(History.Count));
    Assert.AreEqual('TB', History.Current.Location.Name);
    Assert.IsFalse(History.JumpTo(5));
  finally
    History.Free;
  end;
end;

procedure TAtlasHoverHistoryTests.NothingToShowKeepsState;
var
  History: TAtlasHoverHistory;
  NoLocation: TAtlasHoverTypeRef;
begin
  History := TAtlasHoverHistory.Create(Fetch);
  try
    History.Start(DataFor(Ref('TA', 1)));
    NoLocation := Default(TAtlasHoverTypeRef);
    NoLocation.Name := 'TUnbekannt';
    Assert.IsFalse(History.Open(NoLocation));
    Assert.AreEqual(1, Integer(History.Count));
    Assert.IsFalse(History.Pinned);
    History.Clear;
    Assert.IsFalse(History.Open(Ref('TB', 2)), 'ohne Start nichts');
  finally
    History.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasHoverTests);
  TDUnitX.RegisterTestFixture(TAtlasHoverHistoryTests);

end.
