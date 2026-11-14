unit Atlas.Core.Hover.Tests;

// Tests für Inhalt und Verlauf des Hover-Tooltips (#588).

interface

uses
  DUnitX.TestFramework;

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
    /// <summary>#1921: Über einem Unit-Namen bleibt der Dateipfad vor dem Inhalt der Unit stehen.</summary>
    [Test]
    procedure KeepsPathBeforeUnitContents;
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
  Atlas.Core.Hover.Contract,
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Hover.History;

const
  // TGalleryFrameClass = class of TBFrame; TBFrame = class(TFrame) in Gallery.Types.pas.
  cHoverJson =
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
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasHoverData.FromHover(mValue);
  finally
    mValue.Free;
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
  mData: TAtlasHoverData;
begin
  // #654: documentation als Abschnitte, Klartext in documentationText, Anzeige in xmlDoc.
  mData := Parse('{"contents": "x", "atlas": {"declaration": "constructor Create(AOwner: TComponent);",' +
    '"documentationText": "Legt an.\nAOwner: Besitzer", "documentation": {"sections": [' +
    '{"kind": "summary", "runs": [{"kind": "text", "text": "Legt an."}]},' +
    '{"kind": "param", "name": "AOwner", "runs": [{"kind": "text", "text": "Besitzer"}]}]},' +
    '"xmlDoc": {"expand": "collapsed", "maxLines": 8}}}');
  Assert.AreEqual('Legt an.'#10'AOwner: Besitzer', mData.Documentation);
  Assert.AreEqual(2, Integer(Length(mData.Doc.Sections)));
  Assert.AreEqual('AOwner', mData.Doc.Sections[1].Name);
  Assert.IsTrue(mData.Display.Known);
  Assert.AreEqual(Ord(TAtlasDocExpand.Collapsed), Ord(mData.Display.Expand));
  Assert.AreEqual(8, mData.Display.MaxLines);
  // Ältere Server: documentation als Text, keine Anzeige-Angabe.
  mData := Parse(cHoverJson);
  Assert.IsTrue(mData.Doc.IsEmpty);
  Assert.IsFalse(mData.Display.Known);
end;

procedure TAtlasHoverTests.KeepsPlainDocumentationBeforeRationale;
var
  mData: TAtlasHoverData;
begin
  mData := Parse('{"contents": "x", "atlas": {"declaration": "var Zaehler: Integer;",' +
    '"documentationText": "Zaehlt.", "documentation": {"sections": [' +
    '{"kind": "rationale", "name": "WHY", "runs": [{"kind": "text", "text": "Schnell."}]}]}}}');
  Assert.AreEqual(2, Integer(Length(mData.Doc.Sections)));
  Assert.AreEqual(Ord(TAtlasDocSectionKind.Summary), Ord(mData.Doc.Sections[0].Kind));
  Assert.AreEqual('Zaehlt.', mData.Doc.Sections[0].Text);
  Assert.AreEqual(Ord(TAtlasDocSectionKind.Rationale), Ord(mData.Doc.Sections[1].Kind));
end;

procedure TAtlasHoverTests.KeepsPathBeforeUnitContents;
var
  mData: TAtlasHoverData;
begin
  mData := Parse('{"contents": "x", "atlas": {"declaration": "unit Werk;",' +
    '"documentationText": "C:\\P\\Werk.pas", "documentation": {"sections": [' +
    '{"kind": "unitContents", "heading": "TYPEN (1)", "name": "Klassen", "runs": [' +
    '{"kind": "ref", "text": "TKunde", "target": "TKunde", "file": "C:\\P\\Werk.pas", "line": 3}]}]}}}');
  Assert.AreEqual(2, Integer(Length(mData.Doc.Sections)));
  Assert.AreEqual('C:\P\Werk.pas', mData.Doc.Sections[0].Text);
  Assert.AreEqual(Ord(TAtlasDocSectionKind.UnitContents), Ord(mData.Doc.Sections[1].Kind));
  Assert.AreEqual('TYPEN (1)', mData.Doc.Sections[1].Heading);
  Assert.AreEqual('Klassen', mData.Doc.Sections[1].Name);
  Assert.AreEqual(3, mData.Doc.Sections[1].Runs[0].Location.Line);
end;

procedure TAtlasHoverTests.ReadsPublishedMembers;
var
  mData: TAtlasHoverData;
begin
  mData := Parse('{"contents": "x", "atlas": {"declaration": "TKnopf = class(TBasis)", "file": "C:\\P\\K.pas",' +
    '"line": 3, "character": 2, "ancestors": [{"name": "TKnopf", "file": "C:\\P\\K.pas", "line": 3,' +
    '"character": 2}], "published": {"defaultProperty": "Items[I: Integer]: string", "members": [' +
    '{"name": "Aktiv", "type": "Boolean", "default": "False", "defaultKind": "implicit", "declaringClass": "TKnopf"},' +
    '{"name": "Titel", "type": "string", "stored": "False", "declaringClass": "TBasis"},' +
    '{"name": "Zahl", "type": "Integer", "defaultKind": "nodefault", "declaringClass": "TBasis"},' +
    '{"name": "OnKlick", "type": "TKlickEvent", "declaringClass": "TBasis", "event": true}]}}}');
  Assert.AreEqual(4, Integer(Length(mData.Members)));
  Assert.AreEqual('Items[I: Integer]: string', mData.DefaultProperty);
  Assert.AreEqual<TAtlasHoverDefaultKind>(hdImplicit, mData.Members[0].DefaultKind);
  Assert.AreEqual<TAtlasHoverDefaultKind>(hdNoDefault, mData.Members[2].DefaultKind);
  Assert.IsTrue(mData.Members[3].IsEvent);
  Assert.AreEqual(3, mData.MemberCount(False));
  Assert.AreEqual(1, mData.MemberCount(True));
  Assert.AreEqual('False (implizit)', mData.Members[0].DefaultText('implizit'));
  Assert.AreEqual('stored False', mData.Members[1].DefaultText('implizit'));
  // Eigene (TKnopf) bzw. nur mit Vorgabe.
  Assert.AreEqual(1, Integer(Length(mData.VisibleMembers(False, False, False))));
  Assert.AreEqual(1, Integer(Length(mData.VisibleMembers(False, True, True))));
  Assert.AreEqual(0, Integer(Length(mData.VisibleMembers(True, False, False))));
  Assert.AreEqual('TKnopf' + sLineBreak + 'Aktiv'#9'Boolean'#9'False (implizit)'#9'TKnopf' + sLineBreak +
    'Titel'#9'string'#9'stored False'#9'TBasis' + sLineBreak + 'Zahl'#9'Integer'#9'nodefault'#9'TBasis' + sLineBreak +
    'OnKlick'#9'TKlickEvent'#9#9'TBasis' + sLineBreak + 'Items[I: Integer]: string'#9'default',
    mData.MembersText(True, False, 'implizit'));
  Assert.AreEqual(0, Integer(Length(Parse(cHoverJson).Members)));
end;

procedure TAtlasHoverTests.ReadsReassigned;
var
  mData: TAtlasHoverData;
begin
  mData := Parse('{"contents": "x", "atlas": {"declaration": "Summe: Integer", "kind": "variable",' +
    '"reassigned": {"target": "locals", "writes": 3, "lines": [4, 6, 8]}}}');
  Assert.AreEqual('locals', mData.ReassignedTarget);
  Assert.AreEqual(3, mData.ReassignedWrites);
  Assert.AreEqual(3, Integer(Length(mData.ReassignedLines)));
  // Zeilen 1-basiert.
  Assert.AreEqual('3 x 5, 7, 9', mData.ReassignedText('eins %s', '%d x %s'));
  mData.ReassignedWrites := 1;
  mData.ReassignedLines := TArray<Integer>.Create(11);
  Assert.AreEqual('eins 12', mData.ReassignedText('eins %s', '%d x %s'));
  // Mehr als fünf Zeilen werden gekürzt.
  mData.ReassignedWrites := 7;
  mData.ReassignedLines := TArray<Integer>.Create(0, 1, 2, 3, 4, 5, 6);
  Assert.AreEqual('7 x 1, 2, 3, 4, 5, ' + #$2026, mData.ReassignedText('eins %s', '%d x %s'));
  // Ausgeblendet (Einstellung aus oder Art nicht gewaehlt).
  mData.ClearReassigned;
  Assert.AreEqual('', mData.ReassignedTarget);
  Assert.AreEqual('', mData.ReassignedText('eins %s', '%d x %s'));
  // Ohne Angabe nichts.
  mData := Parse(cHoverJson);
  Assert.AreEqual('', mData.ReassignedTarget);
  Assert.AreEqual(0, Integer(Length(mData.ReassignedLines)));
end;

procedure TAtlasHoverTests.ReadsAtlasParts;
var
  mData: TAtlasHoverData;
begin
  mData := Parse(cHoverJson);
  Assert.IsTrue(mData.Found);
  Assert.AreEqual('TBFrame = class(TFrame)', mData.Declaration);
  Assert.AreEqual('Gallery.Types', mData.UnitName);
  Assert.AreEqual('Basis aller Seiten.', mData.Documentation);
  Assert.AreEqual('class', mData.Kind);
  Assert.AreEqual('https://docwiki/TBFrame', mData.DocWiki);
  Assert.AreEqual('C:\P\Gallery.Types.pas', mData.Location.FileName);
  Assert.AreEqual(19, mData.Location.Line);
  Assert.AreEqual('TBFrame', mData.Location.Name, 'aus dem ersten Kettenglied');
  Assert.AreEqual(1, Integer(Length(mData.Links)));
  Assert.AreEqual(16, mData.Links[0].Start);
  Assert.AreEqual('TFrame', mData.Links[0].Target.Name);
  Assert.AreEqual(500, mData.Links[0].Target.Line);
  Assert.AreEqual('TBFrame', mData.ChainOf);
  Assert.AreEqual(3, Integer(Length(mData.Ancestors)));
  Assert.AreEqual('System', mData.Ancestors[2].UnitName);
end;

procedure TAtlasHoverTests.FallsBackToPlainText;
var
  mData: TAtlasHoverData;
begin
  mData := Parse('{"contents": {"kind": "markdown", "value": "```pascal\nprocedure Lauf;\n```\n\nStartet."}}');
  Assert.AreEqual('procedure Lauf;', mData.Declaration);
  Assert.AreEqual('Startet.', mData.Documentation);
  Assert.AreEqual(0, Integer(Length(mData.Links)));
  Assert.IsFalse(mData.Location.HasLocation);
  Assert.IsFalse(TAtlasHoverData.FromHover(nil).Found);
end;

procedure TAtlasHoverTests.ShortensLongChains;
var
  mData: TAtlasHoverData;
  mIndex: Integer;
  mChain: TArray<Integer>;
begin
  mData := Default(TAtlasHoverData);
  for mIndex := 0 to 4 do
  begin
    mData.Ancestors := mData.Ancestors + [Ref('T' + IntToStr(mIndex), mIndex)];
  end;
  Assert.AreEqual(5, Integer(Length(mData.VisibleChain)), 'fünf Glieder ganz');
  mData.Ancestors := mData.Ancestors + [Ref('T5', 5), Ref('TObject', 6)];
  mChain := mData.VisibleChain;
  // Die ersten vier, dann "…", dann das letzte.
  Assert.AreEqual(6, Integer(Length(mChain)));
  Assert.AreEqual(0, mChain[0]);
  Assert.AreEqual(3, mChain[3]);
  Assert.AreEqual(-1, mChain[4]);
  Assert.AreEqual(6, mChain[5]);
end;

procedure TAtlasHoverTests.FindsLinkAtIndex;
var
  mData: TAtlasHoverData;
begin
  mData := Parse(cHoverJson);
  Assert.AreEqual(-1, mData.LinkAt(15));
  Assert.AreEqual(0, mData.LinkAt(16));
  Assert.AreEqual(0, mData.LinkAt(21));
  Assert.AreEqual(-1, mData.LinkAt(22));
end;

procedure TAtlasHoverTests.BadgeTitleAndLocation;
var
  mData: TAtlasHoverData;
begin
  mData := Parse(cHoverJson);
  Assert.AreEqual('ty', mData.Badge);
  Assert.AreEqual('TBFrame', mData.Title);
  Assert.AreEqual('Gallery.Types.pas : 20', mData.LocationText);
  mData := Default(TAtlasHoverData);
  mData.Declaration := 'procedure Lauf(A: Integer);';
  mData.Kind := 'routine';
  mData.UnitName := 'Haupt';
  Assert.AreEqual('fn', mData.Badge);
  Assert.AreEqual('Lauf', mData.Title);
  Assert.AreEqual('Haupt', mData.LocationText, 'ohne Fundort die Unit');
end;

procedure TAtlasHoverTests.ClassReferenceTitleIsOwnName;
var
  mData: TAtlasHoverData;
begin
  mData := Default(TAtlasHoverData);
  mData.Declaration := 'TGalleryFrameClass = class of TBFrame;';
  mData.Kind := TAtlasHoverData.cKindClassRef;
  mData.ChainOf := 'TBFrame';
  mData.Ancestors := [Ref('TBFrame', 19), Ref('TObject', 10)];
  // Die Kette gehört zum Zieltyp, der Titel ist die Klassenreferenz selbst.
  Assert.AreEqual('TGalleryFrameClass', mData.Title);
end;

{ TAtlasHoverHistoryTests }

procedure TAtlasHoverHistoryTests.ClickPinsAndBackReturns;
var
  mHistory: TAtlasHoverHistory;
begin
  mHistory := TAtlasHoverHistory.Create(Fetch);
  try
    mHistory.Start(DataFor(Ref('TGalleryFrameClass', 18)));
    Assert.IsFalse(mHistory.Pinned, 'Kurzform');
    Assert.IsTrue(mHistory.Open(Ref('TBFrame', 19)));
    Assert.IsTrue(mHistory.Pinned, 'erster Klick heftet an');
    Assert.AreEqual(2, Integer(mHistory.Count));
    Assert.AreEqual('TBFrame', mHistory.Current.Location.Name);
    Assert.IsTrue(mHistory.Open(Ref('TFrame', 500)));
    // Klick auf TFrame, dann Rücktaste: wieder TBFrame.
    Assert.IsTrue(mHistory.Back);
    Assert.AreEqual('TBFrame', mHistory.Current.Location.Name);
    Assert.IsTrue(mHistory.Back);
    Assert.IsFalse(mHistory.Back, 'am Anfang');
    Assert.IsTrue(mHistory.Pinned, 'bleibt angeheftet');
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasHoverHistoryTests.SameTypeAddsNoStep;
var
  mHistory: TAtlasHoverHistory;
begin
  mHistory := TAtlasHoverHistory.Create(Fetch);
  try
    mHistory.Start(DataFor(Ref('TBFrame', 19)));
    Assert.IsTrue(mHistory.Open(Ref('TBFrame', 19)));
    Assert.AreEqual(1, Integer(mHistory.Count), 'derselbe Typ: kein neuer Eintrag');
    Assert.IsTrue(mHistory.Pinned);
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasHoverHistoryTests.KeepsTenStepsAndShortensPath;
var
  mHistory: TAtlasHoverHistory;
  mIndex: Integer;
  mPath: TArray<TAtlasHoverPathItem>;
begin
  mHistory := TAtlasHoverHistory.Create(Fetch);
  try
    mHistory.Start(DataFor(Ref('TStart', 0)));
    // Elf Klicks: zehn Schritte bleiben, die ältesten fallen weg.
    for mIndex := 1 to 11 do
    begin
      Assert.IsTrue(mHistory.Open(Ref('T' + IntToStr(mIndex), mIndex)));
    end;
    Assert.AreEqual(TAtlasHoverHistory.cMaxSteps, mHistory.Count);
    Assert.AreEqual('T2', mHistory.Items[0].Location.Name);
    Assert.AreEqual('T11', mHistory.Current.Location.Name);
    mPath := mHistory.Path;
    Assert.AreEqual('…', mPath[0].Caption, 'Pfad beginnt mit …');
    Assert.AreEqual(-1, mPath[0].Index);
    Assert.AreEqual(TAtlasHoverHistory.cMaxPathShown, Integer(Length(mPath)));
    Assert.AreEqual('T11', mPath[High(mPath)].Caption);
    Assert.AreEqual(mHistory.Count - 1, mPath[High(mPath)].Index);
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasHoverHistoryTests.JumpDropsLaterSteps;
var
  mHistory: TAtlasHoverHistory;
begin
  mHistory := TAtlasHoverHistory.Create(Fetch);
  try
    mHistory.Start(DataFor(Ref('TA', 1)));
    mHistory.Open(Ref('TB', 2));
    mHistory.Open(Ref('TC', 3));
    Assert.AreEqual(3, Integer(Length(mHistory.Path)), 'ohne … bei wenigen Einträgen');
    Assert.IsTrue(mHistory.JumpTo(1));
    Assert.AreEqual(2, Integer(mHistory.Count));
    Assert.AreEqual('TB', mHistory.Current.Location.Name);
    Assert.IsFalse(mHistory.JumpTo(5));
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasHoverHistoryTests.NothingToShowKeepsState;
var
  mHistory: TAtlasHoverHistory;
  mNoLocation: TAtlasHoverTypeRef;
begin
  mHistory := TAtlasHoverHistory.Create(Fetch);
  try
    mHistory.Start(DataFor(Ref('TA', 1)));
    mNoLocation := Default(TAtlasHoverTypeRef);
    mNoLocation.Name := 'TUnbekannt';
    Assert.IsFalse(mHistory.Open(mNoLocation));
    Assert.AreEqual(1, Integer(mHistory.Count));
    Assert.IsFalse(mHistory.Pinned);
    mHistory.Clear;
    Assert.IsFalse(mHistory.Open(Ref('TB', 2)), 'ohne Start nichts');
  finally
    mHistory.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasHoverTests);
  TDUnitX.RegisterTestFixture(TAtlasHoverHistoryTests);

end.
