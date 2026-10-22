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
    /// <summary>Schnelle Lesezeichen (#1104): Tasten der IDE übernommen, „anderer Belegung überlassen“ gibt sie
    /// zurück, Strg+0/Strg+Umschalt+0 bleiben bei der IDE, Wartezeit 0 belegt Strg+Umschalt+K nicht.</summary>
    [Test]
    procedure QuickBookmarkKeysYieldToIde;
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
  // Zeilen verschieben (#634): Alt+↑ und Umschalt+Alt+↑/↓ gehören in der IDE schon anderen Funktionen.
  Assert.Contains(TAtlasKeyConflicts.OwnerOf($8026, TAtlasKeyConflicts.KnownIdeKeys), 'Code-Browsing');
  Assert.Contains(TAtlasKeyConflicts.OwnerOf($A028, TAtlasKeyConflicts.KnownIdeKeys), 'Spaltenblock');
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
  Assert.AreEqual(9, Integer(Length(Entries)), 'sechs, dazu drei der schnellen Lesezeichen (#1104)');
  Assert.IsTrue(Entries[0].Func = TAtlasKeyFunction.Palette);
  Assert.AreEqual(Integer(TAtlasKeyConflicts.PaletteDefault), Integer(Entries[0].Key));
  Assert.IsTrue(Entries[1].Choice = TAtlasKeyChoice.UseAtlas);
  Assert.IsTrue(Entries[3].Func = TAtlasKeyFunction.Signature);
  // Schnellschalter (#604) mit eigener Vorgabe.
  Assert.IsTrue(Entries[4].Func = TAtlasKeyFunction.QuickToggle);
  Assert.AreEqual(Integer(TAtlasKeyConflicts.QuickToggleDefault), Integer(Entries[4].Key));
  Entries[4].Key := $6051;
  // Diagnosemodus (#479): eigene Vorgabe, nicht die Taste der Schnellschalter.
  Assert.IsTrue(Entries[5].Func = TAtlasKeyFunction.DiagnosticMode);
  Assert.AreEqual(Integer(TAtlasKeyConflicts.DiagnosticModeDefault), Integer(Entries[5].Key));
  Assert.AreNotEqual(Integer(TAtlasKeyConflicts.QuickToggleDefault), Integer(Entries[5].Key));
  Entries[5].Key := $6044;
  Entries[5].Choose(TAtlasKeyChoice.UseAtlas);
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
  Assert.AreEqual($6051, Saved.QuickToggleKey);
  Assert.AreEqual($6044, Saved.DiagnosticModeKey);
  Assert.IsTrue(Saved.DiagnosticModeKeyPriority);
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

procedure TAtlasKeyConflictsTests.QuickBookmarkKeysYieldToIde;
var
  Settings, Saved: TAtlasPluginSettings;
  Entries: TArray<TAtlasKeyEntry>;
  Known: TArray<TAtlasKeyOwner>;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Entries := TAtlasKeyEntry.FromSettings(Settings);
  Known := TAtlasKeyConflicts.KnownIdeKeys;
  Assert.IsTrue(Entries[6].Func = TAtlasKeyFunction.QuickBookmark);
  Assert.AreEqual($604B, Integer(Entries[6].Key), 'Strg+Umschalt+K');
  Assert.IsTrue(Entries[7].Func = TAtlasKeyFunction.QuickBookmarkSet);
  Assert.AreEqual($6031, Integer(Entries[7].Key), 'Strg+Umschalt+1');
  Assert.IsTrue(Entries[8].Func = TAtlasKeyFunction.QuickBookmarkJump);
  Assert.AreEqual($4031, Integer(Entries[8].Key), 'Strg+1');
  // Die IDE belegt die Tasten; Atlas nimmt sie mit Vorrang.
  Assert.Contains(TAtlasKeyConflicts.OwnerOf(Entries[6].Key, Known), 'Faltung');
  Assert.Contains(TAtlasKeyConflicts.OwnerOf(Entries[7].Key, Known), 'Lesezeichen 1');
  Assert.Contains(TAtlasKeyConflicts.OwnerOf($4030, Known), 'Lesezeichen 0', 'Strg+0 bleibt bekannt');
  Assert.IsTrue(Entries[7].Status(TAtlasKeyConflicts.OwnerOf(Entries[7].Key, Known)) = TAtlasKeyStatus.AtlasWins);
  // „IDE überlassen“ für die Sprungtasten.
  Entries[8].Choose(TAtlasKeyChoice.LeaveOther);
  Assert.IsTrue(Entries[8].Status(TAtlasKeyConflicts.OwnerOf(Entries[8].Key, Known)) = TAtlasKeyStatus.Left);
  Entries[7].Key := $C031;
  Saved := TAtlasPluginSettings.Defaults;
  TAtlasKeyEntry.ToSettings(Entries, Saved);
  Assert.IsFalse(Saved.QuickBookmarkJumpKeyPriority);
  Assert.AreEqual($C031, Saved.QuickBookmarkSetKey, 'anders belegt: Strg+Alt+1');
  // Wartezeit 0: Atlas belegt Strg+Umschalt+K nicht, kein Konflikt.
  Settings.QuickBookmarkChordWait := 0;
  Assert.IsTrue(TAtlasKeyEntry.FromSettings(Settings)[6].Disabled);
  // Funktion aus: alle Tasten wieder bei der IDE.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.QuickBookmarks := False;
  Entries := TAtlasKeyEntry.FromSettings(Settings);
  Assert.IsTrue(Entries[6].Disabled and Entries[7].Disabled and Entries[8].Disabled);
  Settings := TAtlasPluginSettings.Defaults;
  Settings.QuickBookmarksNumberedKeys := False;
  Entries := TAtlasKeyEntry.FromSettings(Settings);
  Assert.IsFalse(Entries[6].Disabled, 'Unterschalter wirken einzeln');
  Assert.IsTrue(Entries[7].Disabled and Entries[8].Disabled);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeyConflictsTests);

end.
