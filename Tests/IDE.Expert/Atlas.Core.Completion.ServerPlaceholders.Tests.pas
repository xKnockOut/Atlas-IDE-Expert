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
  cDocument =
    'procedure A(X: Integer); overload;'#13#10 +
    'procedure A(Y: Integer); overload;'#13#10 +
    'begin'#13#10 +
    '  Go;'#13#10 +
    'end;';

  // Absichtlich nicht in Textreihenfolge.
  cJson =
    '[{"number":2,"range":{"start":{"line":3,"character":2},"end":{"line":3,"character":5}}},' +
    '{"number":1,"range":{"start":{"line":0,"character":12},"end":{"line":0,"character":22}}},' +
    '{"number":1,"range":{"start":{"line":1,"character":12},"end":{"line":1,"character":22}}},' +
    '{"number":0,"range":{"start":{"line":4,"character":4},"end":{"line":4,"character":4}}}]';

function Expand(const AJson: string): TAtlasSnippetExpansion;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasServerPlaceholders.Expansion(mValue, cDocument);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasServerPlaceholdersTests.OffsetsInOrder;
var
  mExpansion: TAtlasSnippetExpansion;
begin
  mExpansion := Expand(cJson);
  Assert.AreEqual('', mExpansion.Text);
  Assert.AreEqual(4, Integer(Length(mExpansion.Stops)));
  Assert.AreEqual(1, mExpansion.Stops[0].Number);
  Assert.AreEqual(12, mExpansion.Stops[0].Start);
  Assert.AreEqual(10, mExpansion.Stops[0].Length);
  Assert.AreEqual(1, mExpansion.Stops[1].Number);
  Assert.AreEqual(Pos('Y: Integer', cDocument) - 1, mExpansion.Stops[1].Start);
  Assert.AreEqual(2, mExpansion.Stops[2].Number);
  Assert.AreEqual('Go;', Copy(cDocument, mExpansion.Stops[2].Start + 1, mExpansion.Stops[2].Length));
  Assert.AreEqual(0, mExpansion.Stops[3].Number);
  Assert.AreEqual(Length(cDocument), mExpansion.Stops[3].Start);
  Assert.IsTrue(mExpansion.HasPlaceholders);
end;

procedure TAtlasServerPlaceholdersTests.SkipsBrokenEntries;
var
  mExpansion: TAtlasSnippetExpansion;
begin
  mExpansion := Expand('[{"number":1},{"range":{}},5,' +
    '{"number":-1,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}}},' +
    '{"number":1,"range":{"start":{"line":0,"character":5},"end":{"line":0,"character":2}}}]');
  Assert.AreEqual(0, Integer(Length(mExpansion.Stops)));
  Assert.IsFalse(mExpansion.HasPlaceholders);
  mExpansion := Expand('{"number":1}');
  Assert.AreEqual(0, Integer(Length(mExpansion.Stops)));
end;

procedure TAtlasServerPlaceholdersTests.DrivesPlaceholderSession;
var
  mSession: TAtlasPlaceholderSession;
begin
  mSession := TAtlasPlaceholderSession.Create(cDocument, 0, Expand(cJson));
  try
    Assert.AreEqual(1, mSession.CurrentNumber);
    Assert.AreEqual(12, mSession.Current.Start);
    Assert.AreEqual(2, mSession.Count);
    Assert.IsTrue(mSession.Next);
    Assert.AreEqual(2, mSession.CurrentNumber);
    Assert.IsFalse(mSession.Next);
    Assert.AreEqual(Length(cDocument), mSession.FinalOffset);
  finally
    mSession.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasServerPlaceholdersTests);

end.
