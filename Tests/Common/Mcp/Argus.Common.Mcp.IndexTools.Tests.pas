unit Argus.Common.Mcp.IndexTools.Tests;

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
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Index.Contract,
  Argus.Common.Index.SymbolIndex,
  Argus.Common.Index.Extractor,
  Argus.Common.Mcp.IndexTools;

const
  BaseUnit =
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
  ZooUnit =
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
  KnopfFile = 'C:\P\Knopf.pas';
  KnopfUnit =
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

function NewTools: TMcpIndexTools;
var
  Index: ISymbolIndex;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(BaseUnit, 'C:\P\Basis.pas', nil));
  Index.AddUnit(TIndexExtractor.ExtractText(ZooUnit, 'C:\P\Zoo.pas', nil));
  Result := TMcpIndexTools.Create(Index, nil);
end;

procedure TMcpIndexToolsTests.FindsSymbolWithLocation;
var
  Tools: TMcpIndexTools;
  Text: string;
begin
  Tools := NewTools;
  try
    Text := Tools.FindSymbol('THund');
    Assert.Contains(Text, 'THund (Klasse');
    Assert.Contains(Text, 'Unit Zoo, C:\P\Zoo.pas:5');
  finally
    Tools.Free;
  end;
end;

procedure TMcpIndexToolsTests.FindsQualifiedMember;
var
  Tools: TMcpIndexTools;
  Text: string;
begin
  Tools := NewTools;
  try
    Text := Tools.FindSymbol('THund.Laut');
    Assert.Contains(Text, 'THund.Laut (Methode');
    Assert.DoesNotContain(Text, 'TTier.Laut');
  finally
    Tools.Free;
  end;
end;

procedure TMcpIndexToolsTests.FallsBackToSubstring;
var
  Tools: TMcpIndexTools;
  Text: string;
begin
  Tools := NewTools;
  try
    Text := Tools.FindSymbol('hunde');
    Assert.Contains(Text, 'ähnliche Namen');
    Assert.Contains(Text, 'MaxHunde (Konstante');
  finally
    Tools.Free;
  end;
end;

procedure TMcpIndexToolsTests.ReportsMissingSymbol;
var
  Tools: TMcpIndexTools;
begin
  Tools := NewTools;
  try
    Assert.Contains(Tools.FindSymbol('TKatze'), 'Kein Symbol "TKatze"');
    Assert.Contains(Tools.TypeHierarchy('TKatze'), 'Kein Typ "TKatze"');
    Assert.Contains(Tools.UnitOutline('Garten'), 'nicht im Index');
  finally
    Tools.Free;
  end;
end;

procedure TMcpIndexToolsTests.ShowsAncestorsAndDescendants;
var
  Tools: TMcpIndexTools;
  Text, Ancestors, Descendants: string;
begin
  Tools := NewTools;
  try
    Text := Tools.TypeHierarchy('THund');
    Ancestors := Copy(Text, Pos('Vorfahren:', Text), Pos('Nachfahren:', Text) - Pos('Vorfahren:', Text));
    Descendants := Copy(Text, Pos('Nachfahren:', Text), MaxInt);
    Assert.Contains(Ancestors, 'TTier (Klasse');
    Assert.Contains(Descendants, 'TDackel (Klasse');
    Text := Tools.TypeHierarchy('TTier');
    Descendants := Copy(Text, Pos('Nachfahren:', Text), MaxInt);
    Assert.Contains(Descendants, '  - THund');
    Assert.Contains(Descendants, '    - TDackel', 'Enkel eingerückt');
  finally
    Tools.Free;
  end;
end;

procedure TMcpIndexToolsTests.OutlinesUnit;
var
  Tools: TMcpIndexTools;
  Text: string;
begin
  Tools := NewTools;
  try
    Text := Tools.UnitOutline('Zoo');
    Assert.Contains(Text, 'unit Zoo – C:\P\Zoo.pas');
    Assert.Contains(Text, 'uses (interface): Basis');
    Assert.Contains(Text, 'Klasse THund(TTier) – Zeile 5');
    Assert.Contains(Text, 'Methode THund.Laut');
    Assert.Contains(Tools.UnitOutline('C:\P\Basis.pas'), 'unit Basis');
  finally
    Tools.Free;
  end;
end;

procedure TMcpIndexToolsTests.DescribesForm;
var
  Text: string;
begin
  Text := TMcpIndexTools.DfmInfo(
    'object Form1: TForm1'#13#10 +
    '  Caption = ''Haupt'''#13#10 +
    '  OnCreate = FormCreate'#13#10 +
    '  object Button1: TButton'#13#10 +
    '    OnClick = Button1Click'#13#10 +
    '  end'#13#10 +
    'end'#13#10);
  Assert.Contains(Text, '- Form1: TForm1');
  Assert.Contains(Text, 'Caption = ''Haupt''');
  Assert.Contains(Text, 'Ereignisse: OnCreate → FormCreate');
  Assert.Contains(Text, '  - Button1: TButton');
  Assert.Contains(Text, 'OnClick → Button1Click');
end;

procedure TMcpIndexToolsTests.DescribesComponent;
var
  Index: ISymbolIndex;
  Tools: TMcpIndexTools;
  Text: string;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(KnopfUnit, KnopfFile, nil));
  Tools := TMcpIndexTools.Create(Index,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(AFileName, KnopfFile);
      if Result then
        AText := KnopfUnit;
    end);
  try
    Tools.PackageOf :=
      function(const AUnitName: string): string
      begin
        if SameText(AUnitName, 'Knopf') then
          Result := 'BeispielPaket'
        else
          Result := '';
      end;
    Text := Tools.ComponentInfo('TKnopf');
    Assert.Contains(Text, 'Vorfahren: TKnopf → TBasisKnopf → TObject');
    Assert.Contains(Text, 'Registrierung (Palettenseite): Beispiele');
    Assert.Contains(Text, 'Package: BeispielPaket');
    Assert.Contains(Text, '  Caption: string');
    Assert.Contains(Text, '  Tag: Integer default 0 (aus TBasisKnopf)');
    Assert.Contains(Text, '  OnClick: TNotifyEvent – Signatur (Sender: TObject)');
  finally
    Tools.Free;
  end;
end;

procedure TMcpIndexToolsTests.ReportsComponentWithoutSources;
var
  Tools: TMcpIndexTools;
begin
  Tools := NewTools;
  try
    Assert.Contains(Tools.ComponentInfo('TButton'), 'Keine Quellen');
  finally
    Tools.Free;
  end;
end;

procedure TMcpIndexToolsTests.ReadsRegistrations;
var
  Items: TArray<TComponentRegistration>;
begin
  Items := TMcpIndexTools.Registrations(
    'RegisterComponents(''Standard'', [TA, TB]);'#10'registercomponents(''Extra'', [TC]);');
  Assert.AreEqual(3, Length(Items));
  Assert.AreEqual('Standard', Items[1].Page);
  Assert.AreEqual('TB', Items[1].ClassName);
  Assert.AreEqual('Extra', Items[2].Page);
end;

procedure TMcpIndexToolsTests.FindsUnitInPackage;
const
  Dpk = 'package Paket;'#10'requires rtl;'#10'contains'#10 +
    '  Knopf in ''Source\Knopf.pas'','#10'  Leiste;'#10'end.';
begin
  Assert.IsTrue(TMcpIndexTools.PackageContains(Dpk, 'Knopf'));
  Assert.IsTrue(TMcpIndexTools.PackageContains(Dpk, 'leiste'));
  Assert.IsFalse(TMcpIndexTools.PackageContains(Dpk, 'Paket'));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpIndexToolsTests);

end.
