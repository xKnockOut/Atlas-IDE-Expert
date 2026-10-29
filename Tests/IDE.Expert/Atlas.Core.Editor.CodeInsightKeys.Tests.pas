unit Atlas.Core.Editor.CodeInsightKeys.Tests;

// Orte der Code-Insight-Schalter je Delphi-Version und Merker je Version und
// Ort (#1246).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCodeInsightKeysTests = class
  public
    [Test]
    procedure VersionFromBaseKey;
    [Test]
    procedure Delphi12UsesEditorKeyAndDelphi13ProviderKey;
    [Test]
    procedure ExistingKeysWithValueAreAddedOnce;
    [Test]
    procedure UnknownVersionSwitchesBothKnownKeys;
    [Test]
    procedure MarkersDifferPerVersionAndKey;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.CodeInsightKeys;

const
  cDelphi12 = 'Software\Embarcadero\BDS\23.0';
  cDelphi13 = 'Software\Embarcadero\BDS\37.0';

function Joined(const AKeys: TArray<string>): string;
begin
  Result := String.Join('|', AKeys);
end;

procedure TAtlasCodeInsightKeysTests.VersionFromBaseKey;
begin
  Assert.AreEqual('23.0', TAtlasCodeInsightKeys.VersionText(cDelphi12));
  Assert.AreEqual('37.0', TAtlasCodeInsightKeys.VersionText(cDelphi13 + '\'));
  Assert.AreEqual(23, TAtlasCodeInsightKeys.MajorVersion(cDelphi12));
  Assert.AreEqual(37, TAtlasCodeInsightKeys.MajorVersion(cDelphi13));
  Assert.AreEqual('', TAtlasCodeInsightKeys.VersionText('Software\Embarcadero\BDS'));
  Assert.AreEqual(0, TAtlasCodeInsightKeys.MajorVersion(''));
end;

procedure TAtlasCodeInsightKeysTests.Delphi12UsesEditorKeyAndDelphi13ProviderKey;
begin
  Assert.AreEqual(TAtlasCodeInsightKeys.cEditorKey, TAtlasCodeInsightKeys.VersionKey(cDelphi12));
  Assert.AreEqual(TAtlasCodeInsightKeys.cProviderKey, TAtlasCodeInsightKeys.VersionKey(cDelphi13));
  Assert.AreEqual(TAtlasCodeInsightKeys.cEditorKey, Joined(TAtlasCodeInsightKeys.Targets(cDelphi12, nil)));
  Assert.AreEqual(TAtlasCodeInsightKeys.cProviderKey, Joined(TAtlasCodeInsightKeys.Targets(cDelphi13, nil)));
end;

procedure TAtlasCodeInsightKeysTests.ExistingKeysWithValueAreAddedOnce;
begin
  // Unter Delphi 12 hatte Atlas den Ort von Delphi 13 angelegt; die IDE schrieb ihren eigenen. Beide werden
  // geschaltet, der Ort der Version zuerst, keiner doppelt (auch nicht bei anderer Schreibweise).
  Assert.AreEqual(TAtlasCodeInsightKeys.cEditorKey + '|' + TAtlasCodeInsightKeys.cProviderKey + '|Delphi',
    Joined(TAtlasCodeInsightKeys.Targets(cDelphi12, [TAtlasCodeInsightKeys.cProviderKey,
      UpperCase(TAtlasCodeInsightKeys.cEditorKey), 'Delphi'])));
end;

procedure TAtlasCodeInsightKeysTests.UnknownVersionSwitchesBothKnownKeys;
begin
  Assert.AreEqual(TAtlasCodeInsightKeys.cProviderKey + '|' + TAtlasCodeInsightKeys.cEditorKey,
    Joined(TAtlasCodeInsightKeys.Targets('Software\Eigene IDE', nil)));
end;

procedure TAtlasCodeInsightKeysTests.MarkersDifferPerVersionAndKey;
begin
  Assert.AreEqual('IdeHelpInsightDisabled 23.0 Borland.EditOptions.Pascal',
    TAtlasCodeInsightKeys.Marker('IdeHelpInsightDisabled', cDelphi12, TAtlasCodeInsightKeys.cEditorKey));
  Assert.AreNotEqual(TAtlasCodeInsightKeys.Marker('IdeHelpInsightDisabled', cDelphi12,
    TAtlasCodeInsightKeys.cProviderKey), TAtlasCodeInsightKeys.Marker('IdeHelpInsightDisabled', cDelphi13,
    TAtlasCodeInsightKeys.cProviderKey));
  // Der alte Merker stammt vom Ort von Delphi 13; unter Delphi 12 gilt er nicht mehr.
  Assert.IsTrue(TAtlasCodeInsightKeys.UsesLegacyMarker(cDelphi13, TAtlasCodeInsightKeys.cProviderKey));
  Assert.IsFalse(TAtlasCodeInsightKeys.UsesLegacyMarker(cDelphi12, TAtlasCodeInsightKeys.cProviderKey));
  Assert.IsFalse(TAtlasCodeInsightKeys.UsesLegacyMarker(cDelphi13, TAtlasCodeInsightKeys.cEditorKey));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCodeInsightKeysTests);

end.
