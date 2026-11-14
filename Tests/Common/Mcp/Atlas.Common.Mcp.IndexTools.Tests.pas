unit Atlas.Common.Mcp.IndexTools.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpIndexToolsTests = class
  public
    [Test]
    procedure FindsSymbolWithLocation;
    [Test]
    procedure FindsQualifiedMember;
    [Test]
    procedure FallsBackToSubstring;
    [Test]
    procedure ReportsMissingSymbol;
    [Test]
    procedure ShowsAncestorsAndDescendants;
    [Test]
    procedure OutlinesUnit;
    [Test]
    procedure DescribesForm;
    [Test]
    procedure DescribesComponent;
    [Test]
    procedure ReportsComponentWithoutSources;
    [Test]
    procedure ReadsRegistrations;
    [Test]
    procedure FindsUnitInPackage;
    /// <summary>#1123: Begründungen in get_declaration und get_rationale.</summary>
    [Test]
    procedure DeclarationListsRationale;
    [Test]
    procedure ListsRationaleOfUnitAndSymbol;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Rationale,
  Atlas.Common.Mcp.IndexTools;

const
  cBaseUnit =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TTier = class'#10 +
    '  public'#10 +
    '    procedure Laut; virtual;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TTier.Laut; begin end;'#10 +
    'end.';
  cZooUnit =
    'unit Zoo;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  THund = class(TTier)'#10 +
    '    procedure Laut; override;'#10 +
    '  end;'#10 +
    '  TDackel = class(THund)'#10 +
    '  end;'#10 +
    'const'#10 +
    '  MaxHunde = 3;'#10 +
    'implementation'#10 +
    'procedure THund.Laut; begin end;'#10 +
    'end.';

const
  cKnopfFile = 'C:\P\Knopf.pas';
  cKnopfUnit =
    'unit Knopf;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TNotifyEvent = procedure(Sender: TObject) of object;'#10 +
    '  TBasisKnopf = class(TObject)'#10 +
    '  published'#10 +
    '    property Tag: Integer read FTag write FTag default 0;'#10 +
    '  end;'#10 +
    '  TKnopf = class(TBasisKnopf)'#10 +
    '  published'#10 +
    '    property Caption: string read FCaption write FCaption;'#10 +
    '    property OnClick: TNotifyEvent read FOnClick write FOnClick;'#10 +
    '  end;'#10 +
    'procedure Register;'#10 +
    'implementation'#10 +
    'procedure Register;'#10 +
    'begin'#10 +
    '  RegisterComponents(''Beispiele'', [TKnopf]);'#10 +
    'end;'#10 +
    'end.';

const
  cKasseFile = 'C:\P\Kasse.pas';
  cKasseUnit =
    'unit Kasse;'#10 +
    '// NOTE: Siehe ADR-0007.'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKasse = class'#10 +
    '    // WHY: Rundet kaufmaennisch, siehe #312.'#10 +
    '    procedure Buche;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKasse.Buche;'#10 +
    'begin'#10 +
    '  // HACK: Umgeht einen Fehler der RTL.'#10 +
    '  // TODO: Aufraeumen.'#10 +
    'end;'#10 +
    'end.';

function KasseTools: TMcpIndexTools;
var
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cKasseUnit, cKasseFile, nil));
  Result := TMcpIndexTools.Create(mIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := cKasseUnit;
      Result := SameText(AFileName, cKasseFile);
    end);
end;

function NewTools: TMcpIndexTools;
var
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cBaseUnit, 'C:\P\Basis.pas', nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText(cZooUnit, 'C:\P\Zoo.pas', nil));
  Result := TMcpIndexTools.Create(mIndex, nil);
end;

procedure TMcpIndexToolsTests.FindsSymbolWithLocation;
var
  mTools: TMcpIndexTools;
  mText: string;
begin
  mTools := NewTools;
  try
    mText := mTools.FindSymbol('THund');
    Assert.Contains(mText, 'THund (Klasse');
    Assert.Contains(mText, 'Unit Zoo, C:\P\Zoo.pas:5');
  finally
    mTools.Free;
  end;
end;

procedure TMcpIndexToolsTests.FindsQualifiedMember;
var
  mTools: TMcpIndexTools;
  mText: string;
begin
  mTools := NewTools;
  try
    mText := mTools.FindSymbol('THund.Laut');
    Assert.Contains(mText, 'THund.Laut (Methode');
    Assert.DoesNotContain(mText, 'TTier.Laut');
  finally
    mTools.Free;
  end;
end;

procedure TMcpIndexToolsTests.FallsBackToSubstring;
var
  mTools: TMcpIndexTools;
  mText: string;
begin
  mTools := NewTools;
  try
    mText := mTools.FindSymbol('hunde');
    Assert.Contains(mText, 'ähnliche Namen');
    Assert.Contains(mText, 'MaxHunde (Konstante');
  finally
    mTools.Free;
  end;
end;

procedure TMcpIndexToolsTests.ReportsMissingSymbol;
var
  mTools: TMcpIndexTools;
begin
  mTools := NewTools;
  try
    Assert.Contains(mTools.FindSymbol('TKatze'), 'Kein Symbol "TKatze"');
    Assert.Contains(mTools.TypeHierarchy('TKatze'), 'Kein Typ "TKatze"');
    Assert.Contains(mTools.UnitOutline('Garten'), 'nicht im Index');
  finally
    mTools.Free;
  end;
end;

procedure TMcpIndexToolsTests.ShowsAncestorsAndDescendants;
var
  mTools: TMcpIndexTools;
  mText, mAncestors, mDescendants: string;
begin
  mTools := NewTools;
  try
    mText := mTools.TypeHierarchy('THund');
    mAncestors := Copy(mText, Pos('Vorfahren:', mText), Pos('Nachfahren:', mText) - Pos('Vorfahren:', mText));
    mDescendants := Copy(mText, Pos('Nachfahren:', mText), MaxInt);
    Assert.Contains(mAncestors, 'TTier (Klasse');
    Assert.Contains(mDescendants, 'TDackel (Klasse');
    mText := mTools.TypeHierarchy('TTier');
    mDescendants := Copy(mText, Pos('Nachfahren:', mText), MaxInt);
    Assert.Contains(mDescendants, '  - THund');
    Assert.Contains(mDescendants, '    - TDackel', 'Enkel eingerückt');
  finally
    mTools.Free;
  end;
end;

procedure TMcpIndexToolsTests.OutlinesUnit;
var
  mTools: TMcpIndexTools;
  mText: string;
begin
  mTools := NewTools;
  try
    mText := mTools.UnitOutline('Zoo');
    Assert.Contains(mText, 'unit Zoo – C:\P\Zoo.pas');
    Assert.Contains(mText, 'uses (interface): Basis');
    Assert.Contains(mText, 'Klasse THund(TTier) – Zeile 5');
    Assert.Contains(mText, 'Methode THund.Laut');
    Assert.Contains(mTools.UnitOutline('C:\P\Basis.pas'), 'unit Basis');
  finally
    mTools.Free;
  end;
end;

procedure TMcpIndexToolsTests.DescribesForm;
var
  mText: string;
begin
  mText := TMcpIndexTools.DfmInfo(
    'object Form1: TForm1'#13#10 +
    '  Caption = ''Haupt'''#13#10 +
    '  OnCreate = FormCreate'#13#10 +
    '  object Button1: TButton'#13#10 +
    '    OnClick = Button1Click'#13#10 +
    '  end'#13#10 +
    'end'#13#10);
  Assert.Contains(mText, '- Form1: TForm1');
  Assert.Contains(mText, 'Caption = ''Haupt''');
  Assert.Contains(mText, 'Ereignisse: OnCreate → FormCreate');
  Assert.Contains(mText, '  - Button1: TButton');
  Assert.Contains(mText, 'OnClick → Button1Click');
end;

procedure TMcpIndexToolsTests.DescribesComponent;
var
  mIndex: ISymbolIndex;
  mTools: TMcpIndexTools;
  mText: string;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cKnopfUnit, cKnopfFile, nil));
  mTools := TMcpIndexTools.Create(mIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(AFileName, cKnopfFile);
      if Result then
      begin
        AText := cKnopfUnit;
      end;
    end);
  try
    mTools.PackageOf :=
      function(const AUnitName: string): string
      begin
        if SameText(AUnitName, 'Knopf') then
        begin
          Result := 'BeispielPaket';
        end
        else
        begin
          Result := '';
        end;
      end;
    mText := mTools.ComponentInfo('TKnopf');
    Assert.Contains(mText, 'Vorfahren: TKnopf → TBasisKnopf → TObject');
    Assert.Contains(mText, 'Registrierung (Palettenseite): Beispiele');
    Assert.Contains(mText, 'Package: BeispielPaket');
    Assert.Contains(mText, '  Caption: string');
    Assert.Contains(mText, '  Tag: Integer default 0 (aus TBasisKnopf)');
    Assert.Contains(mText, '  OnClick: TNotifyEvent – Signatur (Sender: TObject)');
  finally
    mTools.Free;
  end;
end;

procedure TMcpIndexToolsTests.ReportsComponentWithoutSources;
var
  mTools: TMcpIndexTools;
begin
  mTools := NewTools;
  try
    Assert.Contains(mTools.ComponentInfo('TButton'), 'Keine Quellen');
  finally
    mTools.Free;
  end;
end;

procedure TMcpIndexToolsTests.ReadsRegistrations;
var
  mItems: TArray<TComponentRegistration>;
begin
  mItems := TMcpIndexTools.Registrations(
    'RegisterComponents(''Standard'', [TA, TB]);'#10'registercomponents(''Extra'', [TC]);');
  Assert.AreEqual(3, Integer(Length(mItems)));
  Assert.AreEqual('Standard', mItems[1].Page);
  Assert.AreEqual('TB', mItems[1].ClassName);
  Assert.AreEqual('Extra', mItems[2].Page);
end;

procedure TMcpIndexToolsTests.FindsUnitInPackage;
const
  cDpk = 'package Paket;'#10'requires rtl;'#10'contains'#10 +
    '  Knopf in ''Source\Knopf.pas'','#10'  Leiste;'#10'end.';
begin
  Assert.IsTrue(TMcpIndexTools.PackageContains(cDpk, 'Knopf'));
  Assert.IsTrue(TMcpIndexTools.PackageContains(cDpk, 'leiste'));
  Assert.IsFalse(TMcpIndexTools.PackageContains(cDpk, 'Paket'));
end;

procedure TMcpIndexToolsTests.DeclarationListsRationale;
var
  mTools: TMcpIndexTools;
  mText: string;
begin
  mTools := KasseTools;
  try
    mText := mTools.Declaration('TKasse.Buche');
    Assert.Contains(mText, 'Begründungen:');
    Assert.Contains(mText, '- WHY (Zeile 6): Rundet kaufmaennisch, siehe #312.');
    Assert.Contains(mText, '- HACK (Zeile 12): Umgeht einen Fehler der RTL.');
    Assert.DoesNotContain(mText, '- TODO');
    // hints.rationale aus: kein Abschnitt.
    mTools.RationaleOptionsFunc :=
      function: TRationaleOptions
      begin
        Result := TRationaleOptions.Default;
        Result.Enabled := False;
      end;
    Assert.DoesNotContain(mTools.Declaration('TKasse.Buche'), 'Begründungen');
  finally
    mTools.Free;
  end;
end;

procedure TMcpIndexToolsTests.ListsRationaleOfUnitAndSymbol;
var
  mTools: TMcpIndexTools;
  mText: string;
begin
  mTools := KasseTools;
  try
    mText := mTools.Rationale('Kasse', '');
    Assert.Contains(mText, 'unit Kasse');
    Assert.Contains(mText, '- NOTE (Zeile 2): Siehe ADR-0007.');
    Assert.Contains(mText, 'C:\P\Kasse.pas:7');
    Assert.Contains(mText, '- HACK (Zeile 12)');
    Assert.DoesNotContain(mText, 'TODO');
    mText := mTools.Rationale('', 'TKasse.Buche');
    Assert.Contains(mText, '- WHY (Zeile 6)');
    Assert.Contains(mText, '- HACK (Zeile 12)');
    Assert.AreEqual('Keine Begründungen zu "TKasse".', mTools.Rationale('', 'TKasse'));
    Assert.AreEqual('Genau eins von "unit" und "name" angeben.', mTools.Rationale('Kasse', 'TKasse'));
    Assert.AreEqual('Unit "Fehlt" nicht im Index.', mTools.Rationale('Fehlt', ''));
  finally
    mTools.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpIndexToolsTests);

end.
