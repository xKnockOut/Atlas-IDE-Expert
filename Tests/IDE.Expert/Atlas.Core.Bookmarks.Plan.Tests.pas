unit Atlas.Core.Bookmarks.Plan.Tests;

// Tests für die Entscheidungen des Lesezeichen-Dienstes und der Anmeldung
// des Moduls (#622, #1104): Schlüssel, Sichtbarkeit, Rinne der benannten,
// Text der Auswahl, Statushinweis, Tasten und Startstufe der Spalte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Bookmarks')]
  TAtlasBookmarksPlanTests = class
  public
    /// <summary>Schlüssel klein, ohne Rand, mit „\“.</summary>
    [Test]
    procedure KeyNormalizesPath;
    /// <summary>Lesezeichen laufen mit einer Art; Spalte sichtbar nur gezeichnet und eingeschaltet.</summary>
    [Test]
    procedure AvailableAndColumnShown;
    /// <summary>Rinne zeigt benannte; nummerierte nur ohne sichtbare Spalte, schnelle nie.</summary>
    [Test]
    procedure GutterShowsNamedMarks;
    /// <summary>Nummer vor dem Namen; Hinweis läuft nach der Zeit ab.</summary>
    [Test]
    procedure CaptionAndStatus;
    /// <summary>Tasten nur mit eingeschalteter Art; die Akkordtaste braucht eine Wartezeit.</summary>
    [Test]
    procedure KeysFollowSettings;
    /// <summary>Kennungen der Zifferntasten und Startstufen der Spalte.</summary>
    [Test]
    procedure NumberIdsAndColumnLevels;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Bookmarks.Plan;

{ TAtlasBookmarksPlanTests }

procedure TAtlasBookmarksPlanTests.KeyNormalizesPath;
begin
  Assert.AreEqual('c:\p\src\a.pas', TAtlasBookmarksPlan.Key('  C:/P/Src\A.pas '));
  Assert.AreEqual('', TAtlasBookmarksPlan.Key(''));
end;

procedure TAtlasBookmarksPlanTests.AvailableAndColumnShown;
begin
  Assert.IsTrue(TAtlasBookmarksPlan.Available(True, False));
  Assert.IsTrue(TAtlasBookmarksPlan.Available(False, True));
  Assert.IsFalse(TAtlasBookmarksPlan.Available(False, False));
  Assert.IsTrue(TAtlasBookmarksPlan.ColumnShown(True, True, True));
  Assert.IsFalse(TAtlasBookmarksPlan.ColumnShown(False, True, True), 'nie gezeichnet (#1281)');
  Assert.IsFalse(TAtlasBookmarksPlan.ColumnShown(True, False, True));
  Assert.IsFalse(TAtlasBookmarksPlan.ColumnShown(True, True, False));
end;

procedure TAtlasBookmarksPlanTests.GutterShowsNamedMarks;
begin
  Assert.IsTrue(TAtlasBookmarksPlan.InNamedGutter(True, 0, True));
  Assert.IsFalse(TAtlasBookmarksPlan.InNamedGutter(True, 3, True), 'nummeriert, Spalte sichtbar');
  Assert.IsTrue(TAtlasBookmarksPlan.InNamedGutter(True, 3, False), 'nummeriert ohne Spalte');
  Assert.IsFalse(TAtlasBookmarksPlan.InNamedGutter(False, 0, False), 'schnelle nie');
end;

procedure TAtlasBookmarksPlanTests.CaptionAndStatus;
begin
  Assert.AreEqual('3 · Laden', TAtlasBookmarksPlan.PaletteCaption(3, 'Laden'));
  Assert.AreEqual('Laden', TAtlasBookmarksPlan.PaletteCaption(0, 'Laden'));
  Assert.IsFalse(TAtlasBookmarksPlan.StatusExpired(0, 99999, 4000), 'kein Hinweis');
  Assert.IsFalse(TAtlasBookmarksPlan.StatusExpired(1000, 4999, 4000));
  Assert.IsTrue(TAtlasBookmarksPlan.StatusExpired(1000, 5000, 4000));
end;

procedure TAtlasBookmarksPlanTests.KeysFollowSettings;
begin
  Assert.AreEqual($604B, TAtlasBookmarksPlan.KeyWhen(True, $604B));
  Assert.AreEqual(0, TAtlasBookmarksPlan.KeyWhen(False, $604B));
  Assert.AreEqual($604B, TAtlasBookmarksPlan.ChordKey(True, 800, $604B));
  Assert.AreEqual(0, TAtlasBookmarksPlan.ChordKey(True, 0, $604B), 'ohne Wartezeit kein Akkord');
  Assert.AreEqual(0, TAtlasBookmarksPlan.ChordKey(False, 800, $604B));
end;

procedure TAtlasBookmarksPlanTests.NumberIdsAndColumnLevels;
begin
  Assert.AreEqual('Atlas.QuickBookmarkJump4', TAtlasBookmarksPlan.NumberCommandId(4, True));
  Assert.AreEqual('Atlas.QuickBookmarkSet9', TAtlasBookmarksPlan.NumberCommandId(9, False));
  Assert.IsTrue(TAtlasBookmarksPlan.QuickColumnRuns(TAtlasSafeLevel.Normal, False), 'normal immer');
  Assert.IsTrue(TAtlasBookmarksPlan.QuickColumnRuns(TAtlasSafeLevel.Safe, True));
  Assert.IsFalse(TAtlasBookmarksPlan.QuickColumnRuns(TAtlasSafeLevel.Safe, False));
  Assert.IsFalse(TAtlasBookmarksPlan.QuickColumnRuns(TAtlasSafeLevel.Minimal, True), 'minimal nie');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBookmarksPlanTests);

end.
