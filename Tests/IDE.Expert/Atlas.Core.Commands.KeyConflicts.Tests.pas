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
  end;

implementation

uses
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeyConflictsTests);

end.
