unit Atlas.Core.Commands.KeyConflicts.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Verträglichkeit mit anderen Erweiterungen (#494).</summary>
  [TestFixture]
  TAtlasKeyConflictsTests = class
  public
    [Test]
    procedure PaletteDefaultCollidesWithMacroPlayback;
    [Test]
    procedure BindsOnlyWhenFreeOrPreferred;
    [Test]
    procedure RecognizesCompletionExtensions;
    [Test]
    procedure EntriesRoundTripSettings;
    [Test]
    procedure StatusFollowsOwnerAndChoice;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.KeyConflicts;

procedure TAtlasKeyConflictsTests.PaletteDefaultCollidesWithMacroPlayback;
begin
  Assert.Contains(TAtlasKeyConflicts.OwnerOf(TAtlasKeyConflicts.PaletteDefault, TAtlasKeyConflicts.KnownIdeKeys),
    'Makro');
  Assert.AreEqual('', TAtlasKeyConflicts.OwnerOf(TAtlasKeyConflicts.CheckDefault, TAtlasKeyConflicts.KnownIdeKeys));
  Assert.AreEqual('', TAtlasKeyConflicts.OwnerOf(0, TAtlasKeyConflicts.KnownIdeKeys));
end;

procedure TAtlasKeyConflictsTests.BindsOnlyWhenFreeOrPreferred;
begin
  Assert.IsTrue(TAtlasKeyConflicts.ShouldBind(TAtlasKeyConflicts.CheckDefault, '', False));
  Assert.IsFalse(TAtlasKeyConflicts.ShouldBind(TAtlasKeyConflicts.PaletteDefault, 'IDE: Makro', False),
    'fremde Belegung bleibt aktiv');
  Assert.IsTrue(TAtlasKeyConflicts.ShouldBind(TAtlasKeyConflicts.PaletteDefault, 'IDE: Makro', True));
  Assert.IsFalse(TAtlasKeyConflicts.ShouldBind(0, '', True), 'keine Taste');
end;

procedure TAtlasKeyConflictsTests.RecognizesCompletionExtensions;
var
  Found: TArray<string>;
begin
  Found := TAtlasKeyConflicts.CompletionExtensions(['C:\Bpl\GExperts1.3.bpl', 'C:\CnPack\CnWizards_D120.dll',
    'C:\Bpl\Atlas.IDE.Expert.bpl']);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.Contains(Found[0], 'CnPack');
  Assert.AreEqual(0, Integer(Length(TAtlasKeyConflicts.CompletionExtensions(nil))));
end;

procedure TAtlasKeyConflictsTests.EntriesRoundTripSettings;
var
  Settings, Saved: TAtlasPluginSettings;
  Entries: TArray<TAtlasKeyEntry>;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.SignatureKey := $6048;
  Settings.CheckKeyPriority := True;
  Entries := TAtlasKeyEntry.FromSettings(Settings);
  Assert.AreEqual(4, Integer(Length(Entries)));
  Assert.IsTrue(Entries[0].Func = TAtlasKeyFunction.Palette);
  Assert.AreEqual(Integer(TAtlasKeyConflicts.PaletteDefault), Integer(Entries[0].Key));
  Assert.IsTrue(Entries[1].Choice = TAtlasKeyChoice.UseAtlas);
  Assert.IsTrue(Entries[3].Func = TAtlasKeyFunction.Signature);
  // Andere Taste für Atlas, dann Atlas verwenden.
  Entries[3].Key := $6049;
  Entries[3].Choose(TAtlasKeyChoice.UseAtlas);
  Entries[1].Choose(TAtlasKeyChoice.LeaveOther);
  Saved := TAtlasPluginSettings.Defaults;
  TAtlasKeyEntry.ToSettings(Entries, Saved);
  Assert.AreEqual($6049, Saved.SignatureKey);
  Assert.IsTrue(Saved.SignatureKeyPriority);
  Assert.IsFalse(Saved.CheckKeyPriority);
  Assert.AreEqual(Settings.PaletteKey, Saved.PaletteKey);
end;

procedure TAtlasKeyConflictsTests.StatusFollowsOwnerAndChoice;
var
  Entry: TAtlasKeyEntry;
begin
  // Strg+Umschalt+Leer bleibt bei der IDE bzw. einer fremden Belegung, solange Atlas keine eigene hat.
  Entry := TAtlasKeyEntry.Create(TAtlasKeyFunction.Signature, 0, False);
  Assert.IsTrue(Entry.Status('Fremde Erweiterung') = TAtlasKeyStatus.IdeKey);
  Assert.AreEqual(Integer(TAtlasKeyConflicts.IdeSignatureKey), Integer(Entry.IdeKey));
  // Entscheidet der Benutzer „Atlas verwenden“, belegt Atlas die Taste der IDE selbst.
  Entry.Choose(TAtlasKeyChoice.UseAtlas);
  Assert.AreEqual(Integer(TAtlasKeyConflicts.IdeSignatureKey), Integer(Entry.Key));
  Assert.IsTrue(Entry.Status('Fremde Erweiterung') = TAtlasKeyStatus.AtlasWins);
  Entry := TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, 0, True);
  Assert.IsTrue(Entry.Status('') = TAtlasKeyStatus.NoKey);
  Assert.AreEqual(0, Integer(Entry.IdeKey));
  Entry := TAtlasKeyEntry.Create(TAtlasKeyFunction.Signature, TAtlasKeyConflicts.IdeSignatureKey, False);
  Assert.IsTrue(Entry.Status('') = TAtlasKeyStatus.Free);
  Assert.IsTrue(Entry.Status('CnPack') = TAtlasKeyStatus.Left, 'fremde Belegung bleibt aktiv');
  Assert.IsTrue(Entry.Choice = TAtlasKeyChoice.LeaveOther);
  Entry.Choose(TAtlasKeyChoice.UseAtlas);
  Assert.IsTrue(Entry.Status('CnPack') = TAtlasKeyStatus.AtlasWins);
  Entry.Choose(TAtlasKeyChoice.OtherKey);
  Assert.IsFalse(Entry.Priority, 'andere Taste: ohne Vorrang');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeyConflictsTests);

end.
