unit Atlas.Core.Outline.CrumbMenu.Tests;

// Rechtsklick-Menü an den Gliedern (#1786): Einträge je Glied, Name,
// Signatur mit und ohne Rumpf, Pfad, Komponente zu Feld und Ereignis.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCrumbMenuTests = class
  public
    [Test]
    procedure ActionsFitTheCrumb;
    [Test]
    procedure NameAndSignature;
    [Test]
    procedure PathOfAllCrumbs;
    [Test]
    procedure ComponentOfFieldAndHandler;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.Outline.CrumbMenu;

const
  cCode =
    'unit Kunden;'#13#10 +                                          // 0
    'interface'#13#10 +                                             // 1
    'type'#13#10 +                                                  // 2
    '  TKunde = class(TForm)'#13#10 +                               // 3
    '    btnSpeichern: TButton;'#13#10 +                            // 4
    '  private'#13#10 +                                             // 5
    '    procedure Laden(const AName: string;'#13#10 +              // 6
    '      ANeu: Boolean); overload;'#13#10 +                       // 7
    '    function Pruefe: Boolean; virtual; abstract;'#13#10 +      // 8
    '    procedure btnSpeichernClick(Sender: TObject);'#13#10 +     // 9
    '  end;'#13#10 +                                                // 10
    'implementation'#13#10 +                                        // 11
    'procedure TKunde.Laden(const AName: string;'#13#10 +           // 12
    '  ANeu: Boolean);'#13#10 +                                     // 13
    'begin'#13#10 +                                                 // 14
    'end;'#13#10 +                                                  // 15
    'procedure TKunde.btnSpeichernClick(Sender: TObject);'#13#10 +  // 16
    'begin'#13#10 +                                                 // 17
    'end;'#13#10 +                                                  // 18
    'end.';                                                         // 19

  cForm =
    'object Kunde: TKunde'#13#10 +
    '  OnCreate = FormCreate'#13#10 +
    '  object pnlUnten: TPanel'#13#10 +
    '    object btnSpeichern: TButton'#13#10 +
    '      Caption = ''Speichern'''#13#10 +
    '      OnClick = btnSpeichernClick'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    'end';

function Lines: TArray<string>;
begin
  Result := cCode.Split([#13#10]);
end;

function Nodes: TAtlasOutlineNodes;
var
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(cCode);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, cCode);
  finally
    mTree.Free;
  end;
  try
    Result := TAtlasOutline.FromJson(mSymbols);
  finally
    mSymbols.Free;
  end;
end;

function NodeNamed(const AName: string): Integer;
var
  mNodes: TAtlasOutlineNodes;
begin
  mNodes := Nodes;
  for Result := 0 to High(mNodes) do
  begin
    if mNodes[Result].Name = AName then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function CrumbsAt(ALine, ACharacter: Integer): TAtlasCrumbs;
begin
  Result := TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(ALine, ACharacter, 'Kunden', True, [TAtlasCrumbPart.Visibility]));
end;

procedure TAtlasCrumbMenuTests.ActionsFitTheCrumb;
var
  mCrumbs: TAtlasCrumbs;
  mActions: TAtlasCrumbActions;
begin
  // Kunden › TKunde › private › Laden
  mCrumbs := CrumbsAt(6, 16);
  Assert.AreEqual(4, Integer(Length(mCrumbs)));
  Assert.IsTrue(TAtlasCrumbMenu.ActionsOf(Nodes, mCrumbs[0], False) = [TAtlasCrumbAction.CopyPath,
    TAtlasCrumbAction.CopyUnitName, TAtlasCrumbAction.CopyFilePath], 'Unit-Glied');
  Assert.IsTrue(TAtlasCrumbMenu.ActionsOf(Nodes, mCrumbs[2], True) = [TAtlasCrumbAction.CopyPath],
    'Schlüsselwort-Glied');
  mActions := TAtlasCrumbMenu.ActionsOf(Nodes, mCrumbs[3], False);
  Assert.IsTrue(mActions = [TAtlasCrumbAction.CopyPath, TAtlasCrumbAction.CopyName, TAtlasCrumbAction.CopyWithUnit,
    TAtlasCrumbAction.CopySignature, TAtlasCrumbAction.FindReferences, TAtlasCrumbAction.Rename], 'Methode');
  mActions := TAtlasCrumbMenu.ActionsOf(Nodes, mCrumbs[1], True);
  Assert.IsFalse(TAtlasCrumbAction.CopySignature in mActions, 'Typ ohne Signatur');
  Assert.IsTrue(TAtlasCrumbAction.ShowComponent in mActions);
end;

procedure TAtlasCrumbMenuTests.NameAndSignature;
begin
  Assert.AreEqual('TKunde.Laden', TAtlasCrumbMenu.NameOf(Nodes, NodeNamed('Laden')));
  Assert.AreEqual('procedure TKunde.Laden(const AName: string; ANeu: Boolean)',
    TAtlasCrumbMenu.SignatureOf(Nodes, Lines, NodeNamed('Laden')), 'aus dem Rumpf');
  Assert.AreEqual('function TKunde.Pruefe: Boolean', TAtlasCrumbMenu.SignatureOf(Nodes, Lines, NodeNamed('Pruefe')),
    'ohne Rumpf, Direktiven weg');
  Assert.AreEqual('', TAtlasCrumbMenu.SignatureOf(Nodes, Lines, NodeNamed('TKunde')));
  Assert.AreEqual('btnSpeichern', TAtlasCrumbMenu.MemberOf(Nodes, NodeNamed('btnSpeichern')));
  Assert.AreEqual('btnSpeichernClick', TAtlasCrumbMenu.MemberOf(Nodes, NodeNamed('btnSpeichernClick')));
  Assert.AreEqual('', TAtlasCrumbMenu.MemberOf(Nodes, NodeNamed('TKunde')));
end;

procedure TAtlasCrumbMenuTests.PathOfAllCrumbs;
begin
  Assert.AreEqual('Kunden › TKunde › private › Laden', TAtlasCrumbMenu.PathOf(CrumbsAt(6, 16)));
end;

procedure TAtlasCrumbMenuTests.ComponentOfFieldAndHandler;
begin
  Assert.AreEqual('btnSpeichern', TAtlasCrumbMenu.ComponentOf(cForm, 'btnSpeichern'), 'Feld');
  Assert.AreEqual('btnSpeichern', TAtlasCrumbMenu.ComponentOf(cForm, 'btnSpeichernClick'), 'Ereignis');
  Assert.AreEqual('Kunde', TAtlasCrumbMenu.ComponentOf(cForm, 'FormCreate'), 'Ereignis des Formulars');
  Assert.AreEqual('', TAtlasCrumbMenu.ComponentOf(cForm, 'Laden'));
  Assert.AreEqual('', TAtlasCrumbMenu.ComponentOf(cForm, 'Speichern'), 'Wert einer Eigenschaft');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCrumbMenuTests);

end.
