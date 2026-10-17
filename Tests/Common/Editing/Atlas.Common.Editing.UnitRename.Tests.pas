unit Atlas.Common.Editing.UnitRename.Tests;

// Tests für das Nachziehen nach dem Umbenennen einer Unit (#512): uses,
// qualifizierte Bezeichner, eigener Kopf, Einträge mit Pfad und Verdecken.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnitRenameTests = class
  public
    [Test]
    procedure UnitNameFromFile;
    [Test]
    procedure RenamesUsesAndQualifiedNames;
    [Test]
    procedure DropsOldEntryWhenNewIsUsed;
    [Test]
    procedure KeepsProgramPathsAndShadowedNames;
    [Test]
    procedure RenamesOwnHeaderAndDottedNames;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.UnitRename;

function Renamed(const AFileName, AText, AOld, ANew: string): string;
var
  Tree: TSyntaxTree;
  Edits: TArray<TTextEdit>;
begin
  Tree := TPascalParser.Parse(AText);
  try
    if not TUnitRename.Edits(AFileName, AText, Tree, AOld, ANew, Edits) then
      Exit('-');
    Result := TChangeSignature.ApplyEdits(AText, Edits);
  finally
    Tree.Free;
  end;
end;

procedure TUnitRenameTests.UnitNameFromFile;
begin
  Assert.AreEqual('KundenDaten', TUnitRename.UnitNameOf('C:\P\KundenDaten.pas'));
  Assert.AreEqual('Firma.Kunden', TUnitRename.UnitNameOf('C:\P\Firma.Kunden.pas'));
  Assert.AreEqual('', TUnitRename.UnitNameOf('C:\P\Projekt.dpr'));
end;

procedure TUnitRenameTests.RenamesUsesAndQualifiedNames;
const
  Text = 'unit Kasse;'#10'interface'#10'uses'#10'  System.Classes, Kunden;'#10'implementation'#10 +
    'uses Rechnung;'#10'procedure Run;'#10'var'#10'  K: Kunden.TKunde;'#10'begin'#10'  K := Kunden.TKunde.Create;'#10 +
    '  K.Kunden.Free;'#10'  // Kunden.TKunde'#10'end;'#10'end.'#10;
begin
  Assert.AreEqual(StringReplace(StringReplace(StringReplace(Text, ' Kunden;', ' KundenDaten;', []),
    'K: Kunden.', 'K: KundenDaten.', []), ':= Kunden.', ':= KundenDaten.', []),
    Renamed('C:\P\Kasse.pas', Text, 'Kunden', 'KundenDaten'));
  // Ohne Verwendung nichts.
  Assert.AreEqual('-', Renamed('C:\P\Kasse.pas', Text, 'Lager', 'LagerDaten'));
end;

procedure TUnitRenameTests.DropsOldEntryWhenNewIsUsed;
const
  Text = 'unit Kasse;'#10'interface'#10'uses'#10'  Kunden, KundenDaten;'#10'implementation'#10'end.'#10;
begin
  Assert.AreEqual(StringReplace(Text, 'Kunden, KundenDaten', 'KundenDaten', []),
    Renamed('C:\P\Kasse.pas', Text, 'Kunden', 'KundenDaten'));
end;

procedure TUnitRenameTests.KeepsProgramPathsAndShadowedNames;
const
  Program_ = 'program P;'#10'uses'#10'  Kunden in ''Kunden.pas'';'#10'begin'#10'end.'#10;
  Shadow = 'unit Kasse;'#10'interface'#10'uses Kunden;'#10'implementation'#10'procedure Run(Kunden: TList);'#10 +
    'begin'#10'  Kunden.Clear;'#10'end;'#10'end.'#10;
begin
  Assert.AreEqual('-', Renamed('C:\P\P.dpr', Program_, 'Kunden', 'KundenDaten'));
  // Der Parameter Kunden verdeckt die Unit: nur das uses ändert sich.
  Assert.AreEqual(StringReplace(Shadow, 'uses Kunden;', 'uses KundenDaten;', []),
    Renamed('C:\P\Kasse.pas', Shadow, 'Kunden', 'KundenDaten'));
end;

procedure TUnitRenameTests.RenamesOwnHeaderAndDottedNames;
const
  Own = 'unit Firma.Kunden;'#10'interface'#10'implementation'#10'end.'#10;
  User = 'unit Kasse;'#10'interface'#10'uses Firma.Kunden;'#10'implementation'#10'procedure Run;'#10'begin'#10 +
    '  Firma.Kunden.Zeige;'#10'end;'#10'end.'#10;
begin
  Assert.AreEqual(StringReplace(Own, 'Firma.Kunden', 'Firma.KundenDaten', []),
    Renamed('C:\P\Firma.KundenDaten.pas', Own, 'Firma.Kunden', 'Firma.KundenDaten'));
  Assert.AreEqual(StringReplace(User, 'Firma.Kunden', 'Firma.KundenDaten', [rfReplaceAll]),
    Renamed('C:\P\Kasse.pas', User, 'Firma.Kunden', 'Firma.KundenDaten'));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitRenameTests);

end.
