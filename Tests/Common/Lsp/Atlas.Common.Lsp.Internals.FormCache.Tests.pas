unit Atlas.Common.Lsp.Internals.FormCache.Tests;

// Auszüge aus Formulardateien für die Vervollständigung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormSnapshotCacheTests = class
  public
    [Test]
    procedure PutThenGetSameStamp;
    [Test]
    procedure OtherStampMisses;
    [Test]
    procedure EvictsLeastRecentlyUsedAboveLimit;
    [Test]
    procedure FromDocumentCollectsComponentsAndHandlers;
    [Test]
    procedure FromDocumentWithoutRootIsEmpty;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Lsp.Internals.FormCache;

const
  cForm =
    'object frmMain: TfrmMain'#13#10 +
    '  OnCreate = FormCreate'#13#10 +
    '  object pnlOben: TPanel'#13#10 +
    '    object btnSave: TButton'#13#10 +
    '      Caption = ''Speichern'''#13#10 +
    '      OnClick = btnAnyClick'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  inline fraLeiste: TfraLeiste'#13#10 +
    '    object btnIntern: TButton'#13#10 +
    '      OnClick = fraLeistebtnClick'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    'end';

function Snapshot(const AFormFile, ARootName: string): TFormSnapshot;
begin
  Result := Default(TFormSnapshot);
  Result.FormFile := AFormFile;
  Result.RootName := ARootName;
end;

{ TFormSnapshotCacheTests }

procedure TFormSnapshotCacheTests.PutThenGetSameStamp;
var
  mCache: TFormSnapshotCache;
  mFound: TFormSnapshot;
begin
  mCache := TFormSnapshotCache.Create;
  try
    Assert.IsFalse(mCache.TryGet('C:\P\Haupt.dfm', 't1', mFound));
    mCache.Put('C:\P\Haupt.dfm', 't1', Snapshot('C:\P\Haupt.dfm', 'frmMain'));
    // Dateinamen ohne Groß-/Kleinschreibung.
    Assert.IsTrue(mCache.TryGet('c:\p\haupt.DFM', 't1', mFound));
    Assert.AreEqual('frmMain', mFound.RootName);
    Assert.AreEqual(1, Integer(mCache.Count));
  finally
    mCache.Free;
  end;
end;

procedure TFormSnapshotCacheTests.OtherStampMisses;
var
  mCache: TFormSnapshotCache;
  mFound: TFormSnapshot;
begin
  mCache := TFormSnapshotCache.Create;
  try
    mCache.Put('C:\P\Haupt.dfm', 't1', Snapshot('C:\P\Haupt.dfm', 'frmAlt'));
    Assert.IsFalse(mCache.TryGet('C:\P\Haupt.dfm', 't2', mFound));
    Assert.AreEqual('', mFound.RootName);
    // Neuer Stand ersetzt den alten.
    mCache.Put('C:\P\Haupt.dfm', 't2', Snapshot('C:\P\Haupt.dfm', 'frmNeu'));
    Assert.IsTrue(mCache.TryGet('C:\P\Haupt.dfm', 't2', mFound));
    Assert.AreEqual('frmNeu', mFound.RootName);
    Assert.IsFalse(mCache.TryGet('C:\P\Haupt.dfm', 't1', mFound));
    Assert.AreEqual(1, Integer(mCache.Count));
  finally
    mCache.Free;
  end;
end;

procedure TFormSnapshotCacheTests.EvictsLeastRecentlyUsedAboveLimit;
var
  mCache: TFormSnapshotCache;
  mFound: TFormSnapshot;
  mIndex: Integer;
begin
  mCache := TFormSnapshotCache.Create;
  try
    for mIndex := 1 to TFormSnapshotCache.cMaxEntries do
    begin
      mCache.Put(Format('C:\P\F%d.dfm', [mIndex]), 's', Snapshot('', IntToStr(mIndex)));
    end;
    // F1 zuletzt benutzt: Beim nächsten Eintrag fällt F2 heraus, nicht F1.
    Assert.IsTrue(mCache.TryGet('C:\P\F1.dfm', 's', mFound));
    mCache.Put('C:\P\Neu.dfm', 's', Snapshot('', 'Neu'));
    Assert.AreEqual(TFormSnapshotCache.cMaxEntries, Integer(mCache.Count));
    Assert.IsTrue(mCache.TryGet('C:\P\F1.dfm', 's', mFound));
    Assert.IsFalse(mCache.TryGet('C:\P\F2.dfm', 's', mFound));
    Assert.IsTrue(mCache.TryGet('C:\P\F3.dfm', 's', mFound));
    Assert.IsTrue(mCache.TryGet('C:\P\Neu.dfm', 's', mFound));
  finally
    mCache.Free;
  end;
end;

procedure TFormSnapshotCacheTests.FromDocumentCollectsComponentsAndHandlers;
var
  mDocument: TDfmDocument;
  mFound: TFormSnapshot;
begin
  mDocument := TDfmParser.Parse(cForm);
  try
    mFound := TFormSnapshotCache.FromDocument('C:\P\Haupt.dfm', mDocument);
  finally
    mDocument.Free;
  end;
  Assert.AreEqual('C:\P\Haupt.dfm', mFound.FormFile);
  Assert.AreEqual('frmMain', mFound.RootName);
  Assert.AreEqual('TfrmMain', mFound.RootType);
  // Komponenten wie Felder des Formulars: im Frame nur der Frame selbst.
  Assert.AreEqual(3, Integer(Length(mFound.Components)));
  Assert.AreEqual('pnlOben', mFound.Components[0].Name);
  Assert.AreEqual('btnSave', mFound.Components[1].Name);
  Assert.AreEqual('TButton', mFound.Components[1].TypeName);
  Assert.AreEqual('fraLeiste', mFound.Components[2].Name);
  // Ereignisse aller Objekte, auch im Frame, mit fortlaufender Objektnummer.
  Assert.AreEqual(3, Integer(Length(mFound.Handlers)));
  Assert.AreEqual('frmMain', mFound.Handlers[0].ObjectName);
  Assert.AreEqual('FormCreate', mFound.Handlers[0].MethodName);
  Assert.AreEqual(0, mFound.Handlers[0].ObjectIndex);
  Assert.AreEqual('btnSave', mFound.Handlers[1].ObjectName);
  Assert.AreEqual('TButton', mFound.Handlers[1].TypeName);
  Assert.AreEqual('btnAnyClick', mFound.Handlers[1].MethodName);
  Assert.AreEqual('btnIntern', mFound.Handlers[2].ObjectName);
  Assert.IsTrue(mFound.Handlers[2].ObjectIndex > mFound.Handlers[1].ObjectIndex);
end;

procedure TFormSnapshotCacheTests.FromDocumentWithoutRootIsEmpty;
var
  mFound: TFormSnapshot;
begin
  mFound := TFormSnapshotCache.FromDocument('C:\P\Leer.dfm', nil);
  Assert.AreEqual('C:\P\Leer.dfm', mFound.FormFile);
  Assert.AreEqual(0, Integer(Length(mFound.Components)));
  Assert.AreEqual(0, Integer(Length(mFound.Handlers)));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormSnapshotCacheTests);

end.
