unit Atlas.UI.Settings.Pages.Tests;

// Tests für die Nebenseiten der Optionen (Code-Vorlagen, Server) und das Atlas-Symbol im Kopf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsPagesTests = class
  public
    [Test]
    procedure SnippetsPageShowsCatalogAndValidates;
    [Test]
    procedure ServerPageRunsActions;
    [Test]
    procedure SymbolResourcesInAllSizes;
  end;

implementation

uses
  System.Classes,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.ImageCollection,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.SnippetCatalog,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol,
  Atlas.UI.Settings.SnippetsPage,
  Atlas.UI.Settings.ServerPage;

{ TAtlasSettingsPagesTests }

/// <summary>Feste Antworten für Cache und Rückfrage; Baseline und Unterdrückungen stehen im
/// Abschnitt des Moduls Prüfregeln (#1755).</summary>
procedure WireServerPageAnswers(APage: TAtlasServerPage);
begin
  APage.OnClearCache :=
    function: string
    begin
      Result := 'Cache leer';
    end;
  APage.Confirm :=
    function(AQuestion: string): Boolean
    begin
      Result := True;
    end;
end;
procedure TAtlasSettingsPagesTests.SnippetsPageShowsCatalogAndValidates;
var
  mHost: TForm;
  mPage: TAtlasSnippetsPage;
  mOwn: TAtlasSnippet;
begin
  mOwn := Default(TAtlasSnippet);
  mOwn.Prefix := 'eigen';
  mOwn.Body := 'X;';
  mOwn.Origin := TAtlasSnippetOrigin.User;
  // Listen brauchen ein Fenster, wie in der IDE.
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSnippetsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    mPage.Load(TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, nil, [mOwn]));
    Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)) + 1, mPage.Catalog.Count);
    Assert.AreEqual('', mPage.Validate);
    // Zweite eigene mit demselben Kürzel: Meldung nennt das Kürzel.
    mPage.Catalog.Update(mPage.Catalog.AddNew, mOwn);
    Assert.IsTrue(Pos('eigen', mPage.Validate) > 0);
  finally
    mHost.Free;
  end;
end;
procedure TAtlasSettingsPagesTests.ServerPageRunsActions;
var
  mHost: TForm;
  mPage: TAtlasServerPage;
  mGlobal: Boolean;
begin
  // Listen brauchen ein Fenster, wie in der IDE.
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasServerPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    // Ohne Ereignisse ist alles aus.
    Assert.IsFalse(mPage.CacheClear.Enabled);
    mGlobal := False;
    mPage.OnEditGlobal :=
      procedure
      begin
        mGlobal := True;
      end;
    WireServerPageAnswers(mPage);
    mPage.Reload;
    mPage.EditGlobal.Click;
    Assert.IsTrue(mGlobal);
    mPage.CacheClear.Click;
    Assert.AreEqual('Cache leer', mPage.CacheInfo.Caption);
  finally
    mHost.Free;
  end;
end;
procedure TAtlasSettingsPagesTests.SymbolResourcesInAllSizes;
var
  mVariant_: TAtlasSymbolVariant;
  mIndex: Integer;
  mImage: TWICImage;
  mIcon: TIcon;
  mCollection: TImageCollection;
begin
  // #751: jede Größe beider Varianten ist als PNG eingebunden und hat genau diese Größe.
  for mVariant_ := Low(TAtlasSymbolVariant) to High(TAtlasSymbolVariant) do
  begin
    for mIndex := 0 to TAtlasSymbol.cSizeCount - 1 do
    begin
      mImage := TAtlasSymbolImages.Load(mVariant_, TAtlasSymbol.Size(mIndex));
      try
        Assert.IsNotNull(mImage, TAtlasSymbol.ResourceName(mVariant_, TAtlasSymbol.Size(mIndex)));
        Assert.AreEqual(TAtlasSymbol.Size(mIndex), mImage.Width);
      finally
        mImage.Free;
      end;
    end;
    mIcon := TAtlasSymbolImages.Icon(mVariant_);
    try
      Assert.IsFalse(mIcon.Empty, TAtlasSymbol.IconName(mVariant_));
    finally
      mIcon.Free;
    end;
  end;
  mCollection := TAtlasSymbolImages.Collection(nil);
  try
    Assert.AreEqual(2, Integer(mCollection.Images.Count));
    Assert.AreEqual(TAtlasSymbol.cSizeCount, mCollection.Images[1].SourceImages.Count);
  finally
    mCollection.Free;
  end;
end;
initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPagesTests);

end.
