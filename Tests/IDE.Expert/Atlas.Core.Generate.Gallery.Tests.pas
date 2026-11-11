unit Atlas.Core.Generate.Gallery.Tests;

// Tests der Assistenten in der Objektgalerie (#1821): Auswahl der Einträge,
// Texte aus Eintrag und Befehl, Vergleich und Kennungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasGalleryTests = class
  public
    [Test]
    procedure ItemsOnlyFromGalleryEntriesWithCommand;
    [Test]
    procedure CaptionOfEntryWins;
    [Test]
    procedure SameComparesOrderAndTexts;
    [Test]
    procedure WizardIdRoundTrip;
  end;

implementation

uses
  Atlas.Core.Modules.Contract,
  Atlas.Core.Generate.Gallery;

function Command(const AId, ACaption, ADescription: string): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Description := ADescription;
end;

function Entry(const AId: string; APlace: TAtlasMenuPlace; const ACaption: string): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := AId;
  Result.Place := APlace;
  Result.Caption := ACaption;
end;

procedure TAtlasGalleryTests.ItemsOnlyFromGalleryEntriesWithCommand;
var
  mItems: TArray<TAtlasGalleryItem>;
begin
  mItems := TAtlasGallery.Items([Entry('Atlas.A', TAtlasMenuPlace.AtlasMenu, ''),
    Entry('-', TAtlasMenuPlace.Gallery, ''), Entry('Atlas.Gone', TAtlasMenuPlace.Gallery, ''),
    Entry('Atlas.B', TAtlasMenuPlace.Gallery, ''), Entry('atlas.b', TAtlasMenuPlace.Gallery, ''),
    Entry('Atlas.A', TAtlasMenuPlace.Gallery, '')], [Command('Atlas.A', 'A', 'Text A'),
    Command('Atlas.B', 'B', 'Text B')]);
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('Atlas.B', mItems[0].CommandId);
  Assert.AreEqual('Text B', mItems[0].Comment);
  Assert.AreEqual('Atlas.A', mItems[1].CommandId);
end;

procedure TAtlasGalleryTests.CaptionOfEntryWins;
var
  mItems: TArray<TAtlasGalleryItem>;
begin
  mItems := TAtlasGallery.Items([Entry('Atlas.A', TAtlasMenuPlace.Gallery, 'Galerie A'),
    Entry('Atlas.B', TAtlasMenuPlace.Gallery, '')], [Command('Atlas.A', 'A', ''), Command('Atlas.B', 'B', '')]);
  Assert.AreEqual('Galerie A', mItems[0].Caption);
  Assert.AreEqual('B', mItems[1].Caption);
end;

procedure TAtlasGalleryTests.SameComparesOrderAndTexts;
var
  mFirst, mSecond: TArray<TAtlasGalleryItem>;
begin
  mFirst := TAtlasGallery.Items([Entry('Atlas.A', TAtlasMenuPlace.Gallery, ''),
    Entry('Atlas.B', TAtlasMenuPlace.Gallery, '')], [Command('Atlas.A', 'A', ''), Command('Atlas.B', 'B', '')]);
  mSecond := TAtlasGallery.Items([Entry('Atlas.A', TAtlasMenuPlace.Gallery, ''),
    Entry('Atlas.B', TAtlasMenuPlace.Gallery, '')], [Command('Atlas.A', 'A', ''), Command('Atlas.B', 'B', '')]);
  Assert.IsTrue(TAtlasGallery.Same(mFirst, mSecond));
  mSecond[1].Caption := 'B (English)';
  Assert.IsFalse(TAtlasGallery.Same(mFirst, mSecond), 'Text geändert');
  Assert.IsFalse(TAtlasGallery.Same(mFirst, [mFirst[1], mFirst[0]]), 'Reihenfolge');
  Assert.IsFalse(TAtlasGallery.Same(mFirst, [mFirst[0]]), 'Anzahl');
  Assert.IsTrue(TAtlasGallery.Same(nil, nil));
end;

procedure TAtlasGalleryTests.WizardIdRoundTrip;
begin
  Assert.AreEqual('Atlas.Gallery.Atlas.NewTestUnit', TAtlasGallery.WizardId('Atlas.NewTestUnit'));
  Assert.AreEqual('Atlas.NewTestUnit', TAtlasGallery.CommandIdOf(TAtlasGallery.WizardId('Atlas.NewTestUnit')));
  Assert.AreEqual('', TAtlasGallery.CommandIdOf('Embarcadero.NewUnit'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGalleryTests);

end.
