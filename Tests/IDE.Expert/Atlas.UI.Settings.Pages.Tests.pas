unit Atlas.UI.Settings.Pages.Tests;

// Tests für die Nebenseiten der Optionen (Code-Vorlagen, Server) und das Atlas-Symbol im Kopf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsPagesTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure SnippetsPageShowsCatalogAndValidates;
    [Test]
    procedure ServerPageRunsActions;
    [Test]
    procedure SymbolResourcesInAllSizes;
  end;

implementation

uses
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.ImageCollection,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.SnippetCatalog,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol,
  Atlas.UI.Settings.SnippetsPage,
  Atlas.UI.Settings.ServerPage,
  Atlas.UI.Settings.Page.TestSupport;

procedure TAtlasSettingsPagesTests.WarmUp;
begin
  WarmUpSettingsPage;
end;
/// <summary>Feste Antworten für Unterdrückungen, Cache und Rückfrage.</summary>
procedure WireServerPageAnswers(APage: TAtlasServerPage);
begin
  APage.OnSuppressions :=
    function: TArray<string>
    begin
      Result := ['no-with: 3 (ungenutzt 1, in 2 Dateien)'];
    end;
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
  Host: TForm;
  Page: TAtlasSnippetsPage;
  Own: TAtlasSnippet;
begin
  Own := Default(TAtlasSnippet);
  Own.Prefix := 'eigen';
  Own.Body := 'X;';
  Own.Origin := TAtlasSnippetOrigin.User;
  // Listen brauchen ein Fenster, wie in der IDE.
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSnippetsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    Page.Load(TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, nil, [Own]));
    Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)) + 1, Page.Catalog.Count);
    Assert.AreEqual('', Page.Validate);
    // Zweite eigene mit demselben Kürzel: Meldung nennt das Kürzel.
    Page.Catalog.Update(Page.Catalog.AddNew, Own);
    Assert.IsTrue(Pos('eigen', Page.Validate) > 0);
  finally
    Host.Free;
  end;
end;
procedure TAtlasSettingsPagesTests.ServerPageRunsActions;
var
  Host: TForm;
  Page: TAtlasServerPage;
  Global, Deleted: Boolean;
begin
  // Listen brauchen ein Fenster, wie in der IDE.
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasServerPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    // Ohne Ereignisse ist alles aus.
    Assert.IsFalse(Page.BaselineUpdate.Enabled);
    Assert.IsFalse(Page.CacheClear.Enabled);
    Global := False;
    Deleted := False;
    Page.OnEditGlobal :=
      procedure
      begin
        Global := True;
      end;
    Page.OnBaselineInfo :=
      function: string
      begin
        Result := '5 Treffer in 2 Einträgen';
      end;
    Page.OnBaselineDelete :=
      function: string
      begin
        Deleted := True;
        Result := 'gelöscht';
      end;
    WireServerPageAnswers(Page);
    Page.Refresh;
    Assert.AreEqual('5 Treffer in 2 Einträgen', Page.BaselineInfo.Caption);
    Page.EditGlobal.Click;
    Assert.IsTrue(Global);
    Page.BaselineDelete.Click;
    Assert.IsTrue(Deleted);
    Assert.AreEqual('gelöscht', Page.BaselineInfo.Caption);
    Page.SuppressionsRefresh.Click;
    Assert.AreEqual(1, Integer(Page.Suppressions.Items.Count));
    Page.CacheClear.Click;
    Assert.AreEqual('Cache leer', Page.CacheInfo.Caption);
  finally
    Host.Free;
  end;
end;
procedure TAtlasSettingsPagesTests.SymbolResourcesInAllSizes;
var
  Variant_: TAtlasSymbolVariant;
  Index: Integer;
  Image: TWICImage;
  Icon: TIcon;
  Collection: TImageCollection;
begin
  // #751: jede Größe beider Varianten ist als PNG eingebunden und hat genau diese Größe.
  for Variant_ := Low(TAtlasSymbolVariant) to High(TAtlasSymbolVariant) do
  begin
    for Index := 0 to TAtlasSymbol.SizeCount - 1 do
    begin
      Image := TAtlasSymbolImages.Load(Variant_, TAtlasSymbol.Size(Index));
      try
        Assert.IsNotNull(Image, TAtlasSymbol.ResourceName(Variant_, TAtlasSymbol.Size(Index)));
        Assert.AreEqual(TAtlasSymbol.Size(Index), Image.Width);
      finally
        Image.Free;
      end;
    end;
    Icon := TAtlasSymbolImages.Icon(Variant_);
    try
      Assert.IsFalse(Icon.Empty, TAtlasSymbol.IconName(Variant_));
    finally
      Icon.Free;
    end;
  end;
  Collection := TAtlasSymbolImages.Collection(nil);
  try
    Assert.AreEqual(2, Integer(Collection.Images.Count));
    Assert.AreEqual(TAtlasSymbol.SizeCount, Collection.Images[1].SourceImages.Count);
  finally
    Collection.Free;
  end;
end;
initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPagesTests);

end.
