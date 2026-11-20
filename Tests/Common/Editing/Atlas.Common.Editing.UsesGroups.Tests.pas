unit Atlas.Common.Editing.UsesGroups.Tests;

// Tests für die Gruppen der uses nach Herkunft (#2794).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUsesGroupsTests = class
  public
    [Test]
    procedure NamespaceDecidesWithoutFile;
    [Test]
    procedure IndyWithoutNamespaceIsDelphiComponent;
    [Test]
    procedure InstallationFolderDecides;
    [Test]
    procedure FileOriginDecidesOutsideInstallation;
    [Test]
    procedure UnknownOriginFallsBackToName;
    [Test]
    procedure RecognizesLabelsInBothLanguages;
    [Test]
    procedure StyleFromSetting;
  end;

implementation

uses
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.UsesGroups;

function FileAt(AOrigin: TUsesFileOrigin; const AInstallPath: string): TUsesUnitFile;
begin
  Result := Default(TUsesUnitFile);
  Result.Origin := AOrigin;
  Result.InstallPath := AInstallPath;
end;

procedure TUsesGroupsTests.NamespaceDecidesWithoutFile;
begin
  Assert.AreEqual(Ord(TUsesGroup.RuntimeLibrary), Ord(TUsesGroups.OfName('System.SysUtils')));
  Assert.AreEqual(Ord(TUsesGroup.RuntimeLibrary), Ord(TUsesGroups.OfName('Winapi.Windows')));
  Assert.AreEqual(Ord(TUsesGroup.DelphiComponents), Ord(TUsesGroups.OfName('FireDAC.Comp.Client')));
  Assert.AreEqual(Ord(TUsesGroup.DelphiComponents), Ord(TUsesGroups.OfName('Datasnap.DSServer')));
  Assert.AreEqual(Ord(TUsesGroup.Framework), Ord(TUsesGroups.OfName('Vcl.Forms')));
  Assert.AreEqual(Ord(TUsesGroup.Framework), Ord(TUsesGroups.OfName('fmx.Types')));
  Assert.AreEqual(Ord(TUsesGroup.Project), Ord(TUsesGroups.OfName('Kunden.Daten')));
  Assert.AreEqual(Ord(TUsesGroup.Project), Ord(TUsesGroups.OfName('Haupt')));
end;

procedure TUsesGroupsTests.IndyWithoutNamespaceIsDelphiComponent;
begin
  Assert.AreEqual(Ord(TUsesGroup.DelphiComponents), Ord(TUsesGroups.OfName('IdHTTP')));
  // Id ohne folgenden Großbuchstaben ist kein Indy.
  Assert.AreEqual(Ord(TUsesGroup.Project), Ord(TUsesGroups.OfName('Ident')));
  Assert.AreEqual(Ord(TUsesGroup.Project), Ord(TUsesGroups.OfName('Id')));
end;

procedure TUsesGroupsTests.InstallationFolderDecides;
begin
  Assert.AreEqual(Ord(TUsesGroup.RuntimeLibrary), Ord(TUsesGroups.OfFile('System.Classes',
    FileAt(TUsesFileOrigin.Installation, 'source\rtl\common\System.Classes.pas'))));
  Assert.AreEqual(Ord(TUsesGroup.Framework), Ord(TUsesGroups.OfFile('Vcl.Forms',
    FileAt(TUsesFileOrigin.Installation, 'source\vcl\Vcl.Forms.pas'))));
  // Indy, FireDAC und DataSnap liegen außerhalb von rtl, vcl und fmx.
  Assert.AreEqual(Ord(TUsesGroup.DelphiComponents), Ord(TUsesGroups.OfFile('IdHTTP',
    FileAt(TUsesFileOrigin.Installation, 'source/Indy10/Protocols/IdHTTP.pas'))));
  Assert.AreEqual(Ord(TUsesGroup.DelphiComponents), Ord(TUsesGroups.OfFile('Data.DB',
    FileAt(TUsesFileOrigin.Installation, 'source\data\Data.DB.pas'))));
end;

procedure TUsesGroupsTests.FileOriginDecidesOutsideInstallation;
begin
  Assert.AreEqual(Ord(TUsesGroup.LibraryPath), Ord(TUsesGroups.OfFile('Spring.Collections',
    FileAt(TUsesFileOrigin.LibraryPath, ''))));
  // Der Fundort geht vor dem Namen: eine eigene Unit mit Namespace System bleibt im Projekt.
  Assert.AreEqual(Ord(TUsesGroup.Project), Ord(TUsesGroups.OfFile('System.Eigenes',
    FileAt(TUsesFileOrigin.OwnProject, ''))));
  Assert.AreEqual(Ord(TUsesGroup.ProjectGroup), Ord(TUsesGroups.OfFile('Firma.Common.Logging',
    FileAt(TUsesFileOrigin.ProjectGroup, ''))));
end;

procedure TUsesGroupsTests.UnknownOriginFallsBackToName;
begin
  Assert.AreEqual(Ord(TUsesGroup.Framework), Ord(TUsesGroups.OfFile('Vcl.Graphics',
    FileAt(TUsesFileOrigin.Unknown, ''))));
end;

procedure TUsesGroupsTests.RecognizesLabelsInBothLanguages;
begin
  Assert.IsTrue(TUsesGroups.IsLabel('{ System }'));
  Assert.IsTrue(TUsesGroups.IsLabel('{Bibliothek}'));
  Assert.IsTrue(TUsesGroups.IsLabel('(* Library *)'));
  Assert.IsTrue(TUsesGroups.IsLabel('{ delphi components }'));
  Assert.IsTrue(TUsesGroups.IsLabel(TUsesGroups.LabelOf(TUsesGroup.ProjectGroup)));
  Assert.IsFalse(TUsesGroups.IsLabel('{ Formulare }'));
  Assert.IsFalse(TUsesGroups.IsLabel('{Form1}'));
  Assert.IsFalse(TUsesGroups.IsLabel('{}'));
end;

procedure TUsesGroupsTests.StyleFromSetting;
begin
  Assert.AreEqual(Ord(TUsesGroupStyle.Lines), Ord(TUsesGroups.StyleOf('lines')));
  Assert.AreEqual(Ord(TUsesGroupStyle.Comments), Ord(TUsesGroups.StyleOf('comments')));
  Assert.AreEqual(Ord(TUsesGroupStyle.Comments), Ord(TUsesGroups.StyleOf('')));
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesGroupsTests);

end.
