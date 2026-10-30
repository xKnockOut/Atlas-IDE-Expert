unit Atlas.Core.Completion.ServerPlaceholders.Tests;

// Tests für die Platzhalter des Servers (#674): Offsets im Dokument mit CRLF,
// Textreihenfolge, verknüpfte Nummern, Endposition und unlesbare Einträge;
// die Vorlage trägt den Platzhalter-Modus bis zur Endposition.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasServerPlaceholdersTests = class
  public
    [Test]
    procedure OffsetsInOrder;
    [Test]
    procedure SkipsBrokenEntries;
    [Test]
    procedure DrivesPlaceholderSession;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.Placeholders,
  Atlas.Core.Completion.ServerPlaceholders;

const
  Document =
    'procedure A(X: Integer); overload;'#13#10 +
    'procedure A(Y: Integer); overload;'#13#10 +
    'begin'#13#10 +
    '  Go;'#13#10 +
    'end;';

  // Absichtlich nicht in Textreihenfolge.
  Json =
    '[{"number":2,"range":{"start":{"line":3,"character":2},"end":{"line":3,"character":5}}},' +
    '{"number":1,"range":{"start":{"line":0,"character":12},"end":{"line":0,"character":22}}},' +
    '{"number":1,"range":{"start":{"line":1,"character":12},"end":{"line":1,"character":22}}},' +
    '{"number":0,"range":{"start":{"line":4,"character":4},"end":{"line":4,"character":4}}}]';

function Expand(const AJson: string): TAtlasSnippetExpansion;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasServerPlaceholders.Expansion(Value, Document);
  finally
    Value.Free;
  end;
end;

procedure TAtlasServerPlaceholdersTests.OffsetsInOrder;
var
  Expansion: TAtlasSnippetExpansion;
begin
  Expansion := Expand(Json);
  Assert.AreEqual('', Expansion.Text);
  Assert.AreEqual(4, Integer(Length(Expansion.Stops)));
  Assert.AreEqual(1, Expansion.Stops[0].Number);
  Assert.AreEqual(12, Expansion.Stops[0].Start);
  Assert.AreEqual(10, Expansion.Stops[0].Length);
  Assert.AreEqual(1, Expansion.Stops[1].Number);
  Assert.AreEqual(Pos('Y: Integer', Document) - 1, Expansion.Stops[1].Start);
  Assert.AreEqual(2, Expansion.Stops[2].Number);
  Assert.AreEqual('Go;', Copy(Document, Expansion.Stops[2].Start + 1, Expansion.Stops[2].Length));
  Assert.AreEqual(0, Expansion.Stops[3].Number);
  Assert.AreEqual(Length(Document), Expansion.Stops[3].Start);
  Assert.IsTrue(Expansion.HasPlaceholders);
end;

procedure TAtlasServerPlaceholdersTests.SkipsBrokenEntries;
var
  Expansion: TAtlasSnippetExpansion;
begin
  Expansion := Expand('[{"number":1},{"range":{}},5,' +
    '{"number":-1,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}}},' +
    '{"number":1,"range":{"start":{"line":0,"character":5},"end":{"line":0,"character":2}}}]');
  Assert.AreEqual(0, Integer(Length(Expansion.Stops)));
  Assert.IsFalse(Expansion.HasPlaceholders);
  Expansion := Expand('{"number":1}');
  Assert.AreEqual(0, Integer(Length(Expansion.Stops)));
end;

procedure TAtlasServerPlaceholdersTests.DrivesPlaceholderSession;
var
  Session: TAtlasPlaceholderSession;
begin
  Session := TAtlasPlaceholderSession.Create(Document, 0, Expand(Json));
  try
    Assert.AreEqual(1, Session.CurrentNumber);
    Assert.AreEqual(12, Session.Current.Start);
    Assert.AreEqual(2, Session.Count);
    Assert.IsTrue(Session.Next);
    Assert.AreEqual(2, Session.CurrentNumber);
    Assert.IsFalse(Session.Next);
    Assert.AreEqual(Length(Document), Session.FinalOffset);
  finally
    Session.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasServerPlaceholdersTests);

end.
