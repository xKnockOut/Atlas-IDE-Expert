unit Atlas.Common.Lsp.Internals.FormCache.Tests;

// Auszüge aus Formulardateien für die Vervollständigung (Code-Review P-06).

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
  Form =
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
  Cache: TFormSnapshotCache;
  Found: TFormSnapshot;
begin
  Cache := TFormSnapshotCache.Create;
  try
    Assert.IsFalse(Cache.TryGet('C:\P\Haupt.dfm', 't1', Found));
    Cache.Put('C:\P\Haupt.dfm', 't1', Snapshot('C:\P\Haupt.dfm', 'frmMain'));
    // Dateinamen ohne Groß-/Kleinschreibung.
    Assert.IsTrue(Cache.TryGet('c:\p\haupt.DFM', 't1', Found));
    Assert.AreEqual('frmMain', Found.RootName);
    Assert.AreEqual(1, Cache.Count);
  finally
    Cache.Free;
  end;
end;

procedure TFormSnapshotCacheTests.OtherStampMisses;
var
  Cache: TFormSnapshotCache;
  Found: TFormSnapshot;
begin
  Cache := TFormSnapshotCache.Create;
  try
    Cache.Put('C:\P\Haupt.dfm', 't1', Snapshot('C:\P\Haupt.dfm', 'frmAlt'));
    Assert.IsFalse(Cache.TryGet('C:\P\Haupt.dfm', 't2', Found));
    Assert.AreEqual('', Found.RootName);
    // Neuer Stand ersetzt den alten.
    Cache.Put('C:\P\Haupt.dfm', 't2', Snapshot('C:\P\Haupt.dfm', 'frmNeu'));
    Assert.IsTrue(Cache.TryGet('C:\P\Haupt.dfm', 't2', Found));
    Assert.AreEqual('frmNeu', Found.RootName);
    Assert.IsFalse(Cache.TryGet('C:\P\Haupt.dfm', 't1', Found));
    Assert.AreEqual(1, Cache.Count);
  finally
    Cache.Free;
  end;
end;

procedure TFormSnapshotCacheTests.EvictsLeastRecentlyUsedAboveLimit;
var
  Cache: TFormSnapshotCache;
  Found: TFormSnapshot;
  Index: Integer;
begin
  Cache := TFormSnapshotCache.Create;
  try
    for Index := 1 to TFormSnapshotCache.MaxEntries do
      Cache.Put(Format('C:\P\F%d.dfm', [Index]), 's', Snapshot('', IntToStr(Index)));
    // F1 zuletzt benutzt: Beim nächsten Eintrag fällt F2 heraus, nicht F1.
    Assert.IsTrue(Cache.TryGet('C:\P\F1.dfm', 's', Found));
    Cache.Put('C:\P\Neu.dfm', 's', Snapshot('', 'Neu'));
    Assert.AreEqual(TFormSnapshotCache.MaxEntries, Cache.Count);
    Assert.IsTrue(Cache.TryGet('C:\P\F1.dfm', 's', Found));
    Assert.IsFalse(Cache.TryGet('C:\P\F2.dfm', 's', Found));
    Assert.IsTrue(Cache.TryGet('C:\P\F3.dfm', 's', Found));
    Assert.IsTrue(Cache.TryGet('C:\P\Neu.dfm', 's', Found));
  finally
    Cache.Free;
  end;
end;

procedure TFormSnapshotCacheTests.FromDocumentCollectsComponentsAndHandlers;
var
  Document: TDfmDocument;
  Found: TFormSnapshot;
begin
  Document := TDfmParser.Parse(Form);
  try
    Found := TFormSnapshotCache.FromDocument('C:\P\Haupt.dfm', Document);
  finally
    Document.Free;
  end;
  Assert.AreEqual('C:\P\Haupt.dfm', Found.FormFile);
  Assert.AreEqual('frmMain', Found.RootName);
  Assert.AreEqual('TfrmMain', Found.RootType);
  // Komponenten wie Felder des Formulars: im Frame nur der Frame selbst.
  Assert.AreEqual(3, Integer(Length(Found.Components)));
  Assert.AreEqual('pnlOben', Found.Components[0].Name);
  Assert.AreEqual('btnSave', Found.Components[1].Name);
  Assert.AreEqual('TButton', Found.Components[1].TypeName);
  Assert.AreEqual('fraLeiste', Found.Components[2].Name);
  // Ereignisse aller Objekte, auch im Frame, mit fortlaufender Objektnummer.
  Assert.AreEqual(3, Integer(Length(Found.Handlers)));
  Assert.AreEqual('frmMain', Found.Handlers[0].ObjectName);
  Assert.AreEqual('FormCreate', Found.Handlers[0].MethodName);
  Assert.AreEqual(0, Found.Handlers[0].ObjectIndex);
  Assert.AreEqual('btnSave', Found.Handlers[1].ObjectName);
  Assert.AreEqual('TButton', Found.Handlers[1].TypeName);
  Assert.AreEqual('btnAnyClick', Found.Handlers[1].MethodName);
  Assert.AreEqual('btnIntern', Found.Handlers[2].ObjectName);
  Assert.IsTrue(Found.Handlers[2].ObjectIndex > Found.Handlers[1].ObjectIndex);
end;

procedure TFormSnapshotCacheTests.FromDocumentWithoutRootIsEmpty;
var
  Found: TFormSnapshot;
begin
  Found := TFormSnapshotCache.FromDocument('C:\P\Leer.dfm', nil);
  Assert.AreEqual('C:\P\Leer.dfm', Found.FormFile);
  Assert.AreEqual(0, Integer(Length(Found.Components)));
  Assert.AreEqual(0, Integer(Length(Found.Handlers)));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormSnapshotCacheTests);

end.
