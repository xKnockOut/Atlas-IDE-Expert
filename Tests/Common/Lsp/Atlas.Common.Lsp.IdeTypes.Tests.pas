unit Atlas.Common.Lsp.IdeTypes.Tests;

// Tests für die Typen aus den Packages der IDE (atlas/ideTypes): Lesen der Meldung (Namen und Objekte mit
// Vorfahr, ungültige Einträge, Doppelte), Nachschlagen ohne Groß-/Kleinschreibung, Ersetzen des Stands und die
// Meldung über den Dispatcher.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIdeTypeCatalogTests = class
  public
    [Test]
    procedure ParsesNamesAndParents;
    [Test]
    procedure SkipsInvalidEntriesAndDuplicates;
    [Test]
    procedure UnitsOfIgnoresCaseAndListsAllUnits;
    [Test]
    procedure ReplaceDropsOldState;
    [Test]
    procedure NotificationReplacesAndReports;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.IdeTypes;

const
  cSample = '{"units":[{"unit":"Vendor.Grid","types":[{"name":"TVendorGrid","parent":"Vcl.Controls.TCustomControl"},' +
    '"TVendorColumn"]},{"unit":"Vendor.Other","types":["TVendorGrid"]}]}';

function Replaced(ACatalog: TIdeTypeCatalog; const AJson: string): Integer;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := ACatalog.Replace(mValue);
  finally
    mValue.Free;
  end;
end;

function Parsed(const AJson: string): TArray<TIdeTypeEntry>;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TIdeTypeCatalog.Parse(mValue);
  finally
    mValue.Free;
  end;
end;

procedure TIdeTypeCatalogTests.ParsesNamesAndParents;
var
  mEntries: TArray<TIdeTypeEntry>;
begin
  mEntries := Parsed(cSample);
  Assert.AreEqual(3, Integer(Length(mEntries)));
  Assert.AreEqual('TVendorGrid', mEntries[0].Name);
  Assert.AreEqual('Vendor.Grid', mEntries[0].UnitName);
  Assert.AreEqual('Vcl.Controls.TCustomControl', mEntries[0].Parent);
  Assert.AreEqual('TVendorColumn', mEntries[1].Name);
  Assert.AreEqual('', mEntries[1].Parent);
  Assert.AreEqual('Vendor.Other', mEntries[2].UnitName);
  mEntries := nil;
end;

procedure TIdeTypeCatalogTests.SkipsInvalidEntriesAndDuplicates;
var
  mEntries: TArray<TIdeTypeEntry>;
begin
  // Ohne Unit, leerer Name, generische Instanz, Name mit Punkt, Zahl, doppelt (auch in anderer Schreibweise).
  mEntries := Parsed('{"units":[{"types":["TOhneUnit"]},{"unit":" ","types":["TLeer"]},' +
    '{"unit":"Vendor.Grid","types":["", "TList<Integer>", "A.TPunkt", 42, "TGut", "tgut", {"parent":"X.T"}]}]}');
  Assert.AreEqual(1, Integer(Length(mEntries)));
  Assert.AreEqual('TGut', mEntries[0].Name);
  Assert.AreEqual(0, Integer(Length(Parsed('[]'))));
  Assert.AreEqual(0, Integer(Length(Parsed('{"units":{}}'))));
  mEntries := nil;
end;

procedure TIdeTypeCatalogTests.UnitsOfIgnoresCaseAndListsAllUnits;
var
  mCatalog: TIdeTypeCatalog;
  mUnits: TArray<string>;
begin
  mCatalog := TIdeTypeCatalog.Create;
  try
    Assert.AreEqual(3, Replaced(mCatalog, cSample));
    mUnits := mCatalog.UnitsOf('tvendorgrid');
    Assert.AreEqual(2, Integer(Length(mUnits)));
    Assert.AreEqual('Vendor.Grid', mUnits[0]);
    Assert.AreEqual('Vendor.Other', mUnits[1]);
    Assert.AreEqual(0, Integer(Length(mCatalog.UnitsOf('TUnbekannt'))));
    Assert.AreEqual(3, mCatalog.Count);
  finally
    mCatalog.Free;
  end;
  mUnits := nil;
end;

procedure TIdeTypeCatalogTests.ReplaceDropsOldState;
var
  mCatalog: TIdeTypeCatalog;
begin
  mCatalog := TIdeTypeCatalog.Create;
  try
    Replaced(mCatalog, cSample);
    Assert.AreEqual(1, Replaced(mCatalog, '{"units":[{"unit":"Neu.Unit","types":["TNeu"]}]}'));
    Assert.AreEqual(0, Integer(Length(mCatalog.UnitsOf('TVendorGrid'))));
    Assert.AreEqual('Neu.Unit', mCatalog.UnitsOf('TNeu')[0]);
    Assert.AreEqual(0, Replaced(mCatalog, 'null'));
    Assert.AreEqual(0, mCatalog.Count);
  finally
    mCatalog.Free;
  end;
end;

procedure TIdeTypeCatalogTests.NotificationReplacesAndReports;
var
  mTypes: TLspIdeTypes;
  mDispatcher: TJsonRpcDispatcher;
  mMessage: TJSONObject;
  mReported: Integer;
begin
  mReported := -1;
  mTypes := TLspIdeTypes.Create;
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mTypes.OnChanged :=
      procedure(ACount: Integer)
      begin
        mReported := ACount;
      end;
    mTypes.Attach(mDispatcher);
    mMessage := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","method":"' + TLspIdeTypes.cMethod + '","params":' +
      cSample + '}') as TJSONObject;
    try
      mDispatcher.DispatchMessage(mMessage).Free;
    finally
      mMessage.Free;
    end;
    Assert.AreEqual(3, mReported);
    Assert.AreEqual('Vendor.Grid', mTypes.Catalog.UnitsOf('TVendorColumn')[0]);
  finally
    mDispatcher.Free;
    mTypes.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIdeTypeCatalogTests);

end.
