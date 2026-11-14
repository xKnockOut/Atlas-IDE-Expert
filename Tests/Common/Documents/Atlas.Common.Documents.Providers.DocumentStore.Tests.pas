unit Atlas.Common.Documents.Providers.DocumentStore.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract;

type
  [TestFixture]
  TDocumentStoreTests = class
  private
    FStore: IDocumentStore;
    FEvents: TArray<string>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OpensAndFindsDocument;
    [Test]
    procedure ChangeAppliesChangesAndVersion;
    [Test]
    procedure ChangeOfUnknownDocumentRaises;
    [Test]
    procedure CloseRemovesDocument;
    [Test]
    procedure IgnoresSaveAndCloseOfUnknownDocument;
    [Test]
    procedure ReportsEventsPerDocument;
    [Test]
    procedure ListsOpenDocuments;
    [Test]
    procedure FindsDocumentUnderOtherSpelling;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Providers.DocumentStore;

const
  cUriA = 'file:///c%3A/a.pas';
  cUriB = 'file:///c%3A/b.pas';

const
  cEventNames: array[TDocumentEventKind] of string = ('Opened', 'Changed', 'Saved', 'Closed');

{ TDocumentStoreTests }

procedure TDocumentStoreTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FEvents := nil;
  FStore.Subscribe(
    procedure(AKind: TDocumentEventKind; const ADocument: ITextDocument)
    begin
      FEvents := FEvents + [Format('%s %s %d', [cEventNames[AKind], ADocument.Uri, ADocument.Version])];
    end);
end;

procedure TDocumentStoreTests.TearDown;
begin
  FStore := nil;
  // Sonst gibt erst das nächste Setup die Ereignisliste frei (Leck-Monitor).
  FEvents := nil;
end;

procedure TDocumentStoreTests.OpensAndFindsDocument;
var
  mDocument: ITextDocument;
begin
  FStore.Open(cUriA, 'pascal', 1, 'unit A;');
  Assert.IsTrue(FStore.TryGet(cUriA, mDocument));
  Assert.AreEqual('unit A;', mDocument.Text);
  Assert.AreEqual('pascal', mDocument.LanguageId);
  Assert.IsFalse(FStore.TryGet(cUriB, mDocument));
end;

procedure TDocumentStoreTests.ChangeAppliesChangesAndVersion;
var
  mDocument: ITextDocument;
begin
  FStore.Open(cUriA, 'pascal', 1, 'unit A;');
  FStore.Change(cUriA, 2, [TTextChange.Ranged(TTextRange.Create(0, 5, 0, 6), 'B')]);
  Assert.IsTrue(FStore.TryGet(cUriA, mDocument));
  Assert.AreEqual('unit B;', mDocument.Text);
  Assert.AreEqual(2, mDocument.Version);
end;

procedure TDocumentStoreTests.ChangeOfUnknownDocumentRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      FStore.Change(cUriA, 2, [TTextChange.Full('x')]);
    end,
    EDocumentError);
end;

procedure TDocumentStoreTests.CloseRemovesDocument;
var
  mDocument: ITextDocument;
begin
  FStore.Open(cUriA, 'pascal', 1, 'unit A;');
  FStore.Close(cUriA);
  Assert.IsFalse(FStore.TryGet(cUriA, mDocument));
end;

procedure TDocumentStoreTests.IgnoresSaveAndCloseOfUnknownDocument;
begin
  FStore.Save(cUriA);
  FStore.Close(cUriA);
  Assert.AreEqual<NativeInt>(0, Length(FEvents));
end;

procedure TDocumentStoreTests.ReportsEventsPerDocument;
begin
  FStore.Open(cUriA, 'pascal', 1, 'a');
  FStore.Open(cUriB, 'pascal', 1, 'b');
  FStore.Change(cUriA, 2, [TTextChange.Full('aa')]);
  FStore.Save(cUriA);
  FStore.Close(cUriB);
  Assert.AreEqual<NativeInt>(5, Length(FEvents));
  Assert.AreEqual('Opened ' + cUriA + ' 1', FEvents[0]);
  Assert.AreEqual('Opened ' + cUriB + ' 1', FEvents[1]);
  Assert.AreEqual('Changed ' + cUriA + ' 2', FEvents[2]);
  Assert.AreEqual('Saved ' + cUriA + ' 2', FEvents[3]);
  Assert.AreEqual('Closed ' + cUriB + ' 1', FEvents[4]);
end;

procedure TDocumentStoreTests.ListsOpenDocuments;
begin
  FStore.Open(cUriA, 'pascal', 1, 'a');
  FStore.Open(cUriB, 'pascal', 1, 'b');
  FStore.Close(cUriA);
  Assert.AreEqual<NativeInt>(1, Length(FStore.Documents));
  Assert.AreEqual(cUriB, FStore.Documents[0].Uri);
end;

procedure TDocumentStoreTests.FindsDocumentUnderOtherSpelling;
var
  mDocument: ITextDocument;
begin
  FStore.Open('file:///c%3A/Projekt/%C3%84.pas', 'pascal', 1, 'a');
  Assert.IsTrue(FStore.TryGet('file:///C:/projekt/' + #$00E4 + '.pas', mDocument));
  // Das Dokument behält die URI des Clients.
  Assert.AreEqual('file:///c%3A/Projekt/%C3%84.pas', mDocument.Uri);
  FStore.Change('file:///C:/Projekt/%C3%84.pas', 2, [TTextChange.Full('b')]);
  Assert.AreEqual<NativeInt>(1, Length(FStore.Documents));
  FStore.Close('file:///C:/PROJEKT/%C3%84.pas');
  Assert.AreEqual<NativeInt>(0, Length(FStore.Documents));
end;

initialization
  TDUnitX.RegisterTestFixture(TDocumentStoreTests);

end.
