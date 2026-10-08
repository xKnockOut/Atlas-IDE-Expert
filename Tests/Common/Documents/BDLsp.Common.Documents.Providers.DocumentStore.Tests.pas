unit BDLsp.Common.Documents.Providers.DocumentStore.Tests;

interface

uses
  DUnitX.TestFramework,
  BDLsp.Common.Documents.Contract;

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
  BDLsp.Common.Documents.Providers.DocumentStore;

const
  UriA = 'file:///c%3A/a.pas';
  UriB = 'file:///c%3A/b.pas';

const
  EventNames: array[TDocumentEventKind] of string = ('Opened', 'Changed', 'Saved', 'Closed');

{ TDocumentStoreTests }

procedure TDocumentStoreTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FEvents := nil;
  FStore.Subscribe(
    procedure(AKind: TDocumentEventKind; const ADocument: ITextDocument)
    begin
      FEvents := FEvents + [Format('%s %s %d', [EventNames[AKind], ADocument.Uri, ADocument.Version])];
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
  Document: ITextDocument;
begin
  FStore.Open(UriA, 'pascal', 1, 'unit A;');
  Assert.IsTrue(FStore.TryGet(UriA, Document));
  Assert.AreEqual('unit A;', Document.Text);
  Assert.AreEqual('pascal', Document.LanguageId);
  Assert.IsFalse(FStore.TryGet(UriB, Document));
end;

procedure TDocumentStoreTests.ChangeAppliesChangesAndVersion;
var
  Document: ITextDocument;
begin
  FStore.Open(UriA, 'pascal', 1, 'unit A;');
  FStore.Change(UriA, 2, [TTextChange.Ranged(TTextRange.Create(0, 5, 0, 6), 'B')]);
  Assert.IsTrue(FStore.TryGet(UriA, Document));
  Assert.AreEqual('unit B;', Document.Text);
  Assert.AreEqual(2, Document.Version);
end;

procedure TDocumentStoreTests.ChangeOfUnknownDocumentRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      FStore.Change(UriA, 2, [TTextChange.Full('x')]);
    end,
    EDocumentError);
end;

procedure TDocumentStoreTests.CloseRemovesDocument;
var
  Document: ITextDocument;
begin
  FStore.Open(UriA, 'pascal', 1, 'unit A;');
  FStore.Close(UriA);
  Assert.IsFalse(FStore.TryGet(UriA, Document));
end;

procedure TDocumentStoreTests.IgnoresSaveAndCloseOfUnknownDocument;
begin
  FStore.Save(UriA);
  FStore.Close(UriA);
  Assert.AreEqual<NativeInt>(0, Length(FEvents));
end;

procedure TDocumentStoreTests.ReportsEventsPerDocument;
begin
  FStore.Open(UriA, 'pascal', 1, 'a');
  FStore.Open(UriB, 'pascal', 1, 'b');
  FStore.Change(UriA, 2, [TTextChange.Full('aa')]);
  FStore.Save(UriA);
  FStore.Close(UriB);
  Assert.AreEqual<NativeInt>(5, Length(FEvents));
  Assert.AreEqual('Opened ' + UriA + ' 1', FEvents[0]);
  Assert.AreEqual('Opened ' + UriB + ' 1', FEvents[1]);
  Assert.AreEqual('Changed ' + UriA + ' 2', FEvents[2]);
  Assert.AreEqual('Saved ' + UriA + ' 2', FEvents[3]);
  Assert.AreEqual('Closed ' + UriB + ' 1', FEvents[4]);
end;

procedure TDocumentStoreTests.ListsOpenDocuments;
begin
  FStore.Open(UriA, 'pascal', 1, 'a');
  FStore.Open(UriB, 'pascal', 1, 'b');
  FStore.Close(UriA);
  Assert.AreEqual<NativeInt>(1, Length(FStore.Documents));
  Assert.AreEqual(UriB, FStore.Documents[0].Uri);
end;

procedure TDocumentStoreTests.FindsDocumentUnderOtherSpelling;
var
  Document: ITextDocument;
begin
  FStore.Open('file:///c%3A/Projekt/%C3%84.pas', 'pascal', 1, 'a');
  Assert.IsTrue(FStore.TryGet('file:///C:/projekt/' + #$00E4 + '.pas', Document));
  // Das Dokument behält die URI des Clients.
  Assert.AreEqual('file:///c%3A/Projekt/%C3%84.pas', Document.Uri);
  FStore.Change('file:///C:/Projekt/%C3%84.pas', 2, [TTextChange.Full('b')]);
  Assert.AreEqual<NativeInt>(1, Length(FStore.Documents));
  FStore.Close('file:///C:/PROJEKT/%C3%84.pas');
  Assert.AreEqual<NativeInt>(0, Length(FStore.Documents));
end;

initialization
  TDUnitX.RegisterTestFixture(TDocumentStoreTests);

end.
