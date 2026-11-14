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
  Assert.Contains(TAtlasKeyConflicts.OwnerOf(TAtlasKeyConflicts.cPaletteDefault, TAtlasKeyConflicts.KnownIdeKeys),
    'Makro');
  Assert.AreEqual('', TAtlasKeyConflicts.OwnerOf(TAtlasKeyConflicts.cCheckDefault, TAtlasKeyConflicts.KnownIdeKeys));
  Assert.AreEqual('', TAtlasKeyConflicts.OwnerOf(0, TAtlasKeyConflicts.KnownIdeKeys));
  // Zeilen verschieben (#634): Alt+↑ und Umschalt+Alt+↑/↓ gehören in der IDE schon anderen Funktionen.
  Assert.Contains(TAtlasKeyConflicts.OwnerOf($8026, TAtlasKeyConflicts.KnownIdeKeys), 'Code-Browsing');
  Assert.Contains(TAtlasKeyConflicts.OwnerOf($A028, TAtlasKeyConflicts.KnownIdeKeys), 'Spaltenblock');
end;

procedure TAtlasKeyConflictsTests.BindsOnlyWhenFreeOrPreferred;
begin
  Assert.IsTrue(TAtlasKeyConflicts.ShouldBind(TAtlasKeyConflicts.cCheckDefault, '', False));
  Assert.IsFalse(TAtlasKeyConflicts.ShouldBind(TAtlasKeyConflicts.cPaletteDefault, 'IDE: Makro', False),
    'fremde Belegung bleibt aktiv');
  Assert.IsTrue(TAtlasKeyConflicts.ShouldBind(TAtlasKeyConflicts.cPaletteDefault, 'IDE: Makro', True));
  Assert.IsFalse(TAtlasKeyConflicts.ShouldBind(0, '', True), 'keine Taste');
end;

procedure TAtlasKeyConflictsTests.RecognizesCompletionExtensions;
var
  mFound: TArray<string>;
begin
  mFound := TAtlasKeyConflicts.CompletionExtensions(['C:\Bpl\GExperts1.3.bpl', 'C:\CnPack\CnWizards_D120.dll',
    'C:\Bpl\Atlas.IDE.Expert.bpl']);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.Contains(mFound[0], 'CnPack');
  Assert.AreEqual(0, Integer(Length(TAtlasKeyConflicts.CompletionExtensions(nil))));
end;

procedure TAtlasKeyConflictsTests.EntriesRoundTripSettings;
var
  mSettings, mSaved: TAtlasPluginSettings;
  mEntries: TArray<TAtlasKeyEntry>;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.SignatureKey := $6048;
  mSettings.CheckKeyPriority := True;
  mEntries := TAtlasKeyEntry.FromSettings(mSettings);
  Assert.AreEqual(9, Integer(Length(mEntries)), 'sechs, dazu drei der schnellen Lesezeichen (#1104)');
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.Palette, mEntries[0].Func);
  Assert.AreEqual(Integer(TAtlasKeyConflicts.cPaletteDefault), Integer(mEntries[0].Key));
  Assert.AreEqual<TAtlasKeyChoice>(TAtlasKeyChoice.UseAtlas, mEntries[1].Choice);
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.Signature, mEntries[3].Func);
  // Schnellschalter (#604) mit eigener Vorgabe.
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.QuickToggle, mEntries[4].Func);
  Assert.AreEqual(Integer(TAtlasKeyConflicts.cQuickToggleDefault), Integer(mEntries[4].Key));
  mEntries[4].Key := $6051;
  // Diagnosemodus (#479): eigene Vorgabe, nicht die Taste der Schnellschalter.
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.DiagnosticMode, mEntries[5].Func);
  Assert.AreEqual(Integer(TAtlasKeyConflicts.cDiagnosticModeDefault), Integer(mEntries[5].Key));
  Assert.AreNotEqual(Integer(TAtlasKeyConflicts.cQuickToggleDefault), Integer(mEntries[5].Key));
  mEntries[5].Key := $6044;
  mEntries[5].Choose(TAtlasKeyChoice.UseAtlas);
  // Andere Taste für Atlas, dann Atlas verwenden.
  mEntries[3].Key := $6049;
  mEntries[3].Choose(TAtlasKeyChoice.UseAtlas);
  mEntries[1].Choose(TAtlasKeyChoice.LeaveOther);
  mSaved := TAtlasPluginSettings.Defaults;
  TAtlasKeyEntry.ToSettings(mEntries, mSaved);
  Assert.AreEqual($6049, mSaved.SignatureKey);
  Assert.IsTrue(mSaved.SignatureKeyPriority);
  Assert.IsFalse(mSaved.CheckKeyPriority);
  Assert.AreEqual(mSettings.PaletteKey, mSaved.PaletteKey);
  Assert.AreEqual($6051, mSaved.QuickToggleKey);
  Assert.AreEqual($6044, mSaved.DiagnosticModeKey);
  Assert.IsTrue(mSaved.DiagnosticModeKeyPriority);
end;

procedure TAtlasKeyConflictsTests.StatusFollowsOwnerAndChoice;
var
  mEntry: TAtlasKeyEntry;
begin
  // Strg+Umschalt+Leer bleibt bei der IDE bzw. einer fremden Belegung, solange Atlas keine eigene hat.
  mEntry := TAtlasKeyEntry.Create(TAtlasKeyFunction.Signature, 0, False);
  Assert.AreEqual<TAtlasKeyStatus>(TAtlasKeyStatus.IdeKey, mEntry.Status('Fremde Erweiterung'));
  Assert.AreEqual(Integer(TAtlasKeyConflicts.cIdeSignatureKey), Integer(mEntry.IdeKey));
  // Entscheidet der Benutzer „Atlas verwenden“, belegt Atlas die Taste der IDE selbst.
  mEntry.Choose(TAtlasKeyChoice.UseAtlas);
  Assert.AreEqual(Integer(TAtlasKeyConflicts.cIdeSignatureKey), Integer(mEntry.Key));
  Assert.AreEqual<TAtlasKeyStatus>(TAtlasKeyStatus.AtlasWins, mEntry.Status('Fremde Erweiterung'));
  mEntry := TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, 0, True);
  Assert.AreEqual<TAtlasKeyStatus>(TAtlasKeyStatus.NoKey, mEntry.Status(''));
  Assert.AreEqual(0, Integer(mEntry.IdeKey));
  mEntry := TAtlasKeyEntry.Create(TAtlasKeyFunction.Signature, TAtlasKeyConflicts.cIdeSignatureKey, False);
  Assert.AreEqual<TAtlasKeyStatus>(TAtlasKeyStatus.Free, mEntry.Status(''));
  Assert.AreEqual<TAtlasKeyStatus>(TAtlasKeyStatus.Left, mEntry.Status('CnPack'), 'fremde Belegung bleibt aktiv');
  Assert.AreEqual<TAtlasKeyChoice>(TAtlasKeyChoice.LeaveOther, mEntry.Choice);
  mEntry.Choose(TAtlasKeyChoice.UseAtlas);
  Assert.AreEqual<TAtlasKeyStatus>(TAtlasKeyStatus.AtlasWins, mEntry.Status('CnPack'));
  mEntry.Choose(TAtlasKeyChoice.OtherKey);
  Assert.IsFalse(mEntry.Priority, 'andere Taste: ohne Vorrang');
end;

procedure TAtlasKeyConflictsTests.QuickBookmarkKeysYieldToIde;
var
  mSettings, mSaved: TAtlasPluginSettings;
  mEntries: TArray<TAtlasKeyEntry>;
  mKnown: TArray<TAtlasKeyOwner>;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mEntries := TAtlasKeyEntry.FromSettings(mSettings);
  mKnown := TAtlasKeyConflicts.KnownIdeKeys;
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.QuickBookmark, mEntries[6].Func);
  Assert.AreEqual($604B, Integer(mEntries[6].Key), 'Strg+Umschalt+K');
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.QuickBookmarkSet, mEntries[7].Func);
  Assert.AreEqual($6031, Integer(mEntries[7].Key), 'Strg+Umschalt+1');
  Assert.AreEqual<TAtlasKeyFunction>(TAtlasKeyFunction.QuickBookmarkJump, mEntries[8].Func);
  Assert.AreEqual($4031, Integer(mEntries[8].Key), 'Strg+1');
  // Die IDE belegt die Tasten; Atlas nimmt sie mit Vorrang.
  Assert.Contains(TAtlasKeyConflicts.OwnerOf(mEntries[6].Key, mKnown), 'Faltung');
  Assert.Contains(TAtlasKeyConflicts.OwnerOf(mEntries[7].Key, mKnown), 'Lesezeichen 1');
  Assert.Contains(TAtlasKeyConflicts.OwnerOf($4030, mKnown), 'Lesezeichen 0', 'Strg+0 bleibt bekannt');
  Assert.AreEqual<TAtlasKeyStatus>(TAtlasKeyStatus.AtlasWins,
    mEntries[7].Status(TAtlasKeyConflicts.OwnerOf(mEntries[7].Key, mKnown)));
  // „IDE überlassen“ für die Sprungtasten.
  mEntries[8].Choose(TAtlasKeyChoice.LeaveOther);
  Assert.AreEqual<TAtlasKeyStatus>(TAtlasKeyStatus.Left,
    mEntries[8].Status(TAtlasKeyConflicts.OwnerOf(mEntries[8].Key, mKnown)));
  mEntries[7].Key := $C031;
  mSaved := TAtlasPluginSettings.Defaults;
  TAtlasKeyEntry.ToSettings(mEntries, mSaved);
  Assert.IsFalse(mSaved.QuickBookmarkJumpKeyPriority);
  Assert.AreEqual($C031, mSaved.QuickBookmarkSetKey, 'anders belegt: Strg+Alt+1');
  // Wartezeit 0: Atlas belegt Strg+Umschalt+K nicht, kein Konflikt.
  mSettings.QuickBookmarkChordWait := 0;
  Assert.IsTrue(TAtlasKeyEntry.FromSettings(mSettings)[6].Disabled);
  // Funktion aus: alle Tasten wieder bei der IDE.
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.QuickBookmarks := False;
  mEntries := TAtlasKeyEntry.FromSettings(mSettings);
  Assert.IsTrue(mEntries[6].Disabled and mEntries[7].Disabled and mEntries[8].Disabled);
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.QuickBookmarksNumberedKeys := False;
  mEntries := TAtlasKeyEntry.FromSettings(mSettings);
  Assert.IsFalse(mEntries[6].Disabled, 'Unterschalter wirken einzeln');
  Assert.IsTrue(mEntries[7].Disabled and mEntries[8].Disabled);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeyConflictsTests);

end.
