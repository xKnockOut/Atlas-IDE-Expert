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
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
begin
  mTree := TPascalParser.Parse(AText);
  try
    if not TUnitRename.Edits(AFileName, AText, mTree, AOld, ANew, mEdits) then
    begin
      Exit('-');
    end;
    Result := TChangeSignature.ApplyEdits(AText, mEdits);
  finally
    mTree.Free;
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
  cText = 'unit Kasse;'#10'interface'#10'uses'#10'  System.Classes, Kunden;'#10'implementation'#10 +
    'uses Rechnung;'#10'procedure Run;'#10'var'#10'  K: Kunden.TKunde;'#10'begin'#10'  K := Kunden.TKunde.Create;'#10 +
    '  K.Kunden.Free;'#10'  // Kunden.TKunde'#10'end;'#10'end.'#10;
begin
  Assert.AreEqual(StringReplace(StringReplace(StringReplace(cText, ' Kunden;', ' KundenDaten;', []),
    'K: Kunden.', 'K: KundenDaten.', []), ':= Kunden.', ':= KundenDaten.', []),
    Renamed('C:\P\Kasse.pas', cText, 'Kunden', 'KundenDaten'));
  // Ohne Verwendung nichts.
  Assert.AreEqual('-', Renamed('C:\P\Kasse.pas', cText, 'Lager', 'LagerDaten'));
end;

procedure TUnitRenameTests.DropsOldEntryWhenNewIsUsed;
const
  cText = 'unit Kasse;'#10'interface'#10'uses'#10'  Kunden, KundenDaten;'#10'implementation'#10'end.'#10;
begin
  Assert.AreEqual(StringReplace(cText, 'Kunden, KundenDaten', 'KundenDaten', []),
    Renamed('C:\P\Kasse.pas', cText, 'Kunden', 'KundenDaten'));
end;

procedure TUnitRenameTests.KeepsProgramPathsAndShadowedNames;
const
  cProgram_ = 'program P;'#10'uses'#10'  Kunden in ''Kunden.pas'';'#10'begin'#10'end.'#10;
  cShadow = 'unit Kasse;'#10'interface'#10'uses Kunden;'#10'implementation'#10'procedure Run(Kunden: TList);'#10 +
    'begin'#10'  Kunden.Clear;'#10'end;'#10'end.'#10;
begin
  Assert.AreEqual('-', Renamed('C:\P\P.dpr', cProgram_, 'Kunden', 'KundenDaten'));
  // Der Parameter Kunden verdeckt die Unit: nur das uses ändert sich.
  Assert.AreEqual(StringReplace(cShadow, 'uses Kunden;', 'uses KundenDaten;', []),
    Renamed('C:\P\Kasse.pas', cShadow, 'Kunden', 'KundenDaten'));
end;

procedure TUnitRenameTests.RenamesOwnHeaderAndDottedNames;
const
  cOwn = 'unit Firma.Kunden;'#10'interface'#10'implementation'#10'end.'#10;
  cUser = 'unit Kasse;'#10'interface'#10'uses Firma.Kunden;'#10'implementation'#10'procedure Run;'#10'begin'#10 +
    '  Firma.Kunden.Zeige;'#10'end;'#10'end.'#10;
begin
  Assert.AreEqual(StringReplace(cOwn, 'Firma.Kunden', 'Firma.KundenDaten', []),
    Renamed('C:\P\Firma.KundenDaten.pas', cOwn, 'Firma.Kunden', 'Firma.KundenDaten'));
  Assert.AreEqual(StringReplace(cUser, 'Firma.Kunden', 'Firma.KundenDaten', [rfReplaceAll]),
    Renamed('C:\P\Kasse.pas', cUser, 'Firma.Kunden', 'Firma.KundenDaten'));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitRenameTests);

end.
