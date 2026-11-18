unit Atlas.Common.Lsp.ImplementationSites.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.ImplementationSites;

type
  [TestFixture]
  TImplementationSitesTests = class
  private
    FIndex: ISymbolIndex;
    function Sites(const AContainer, AName: string; AInterface: Boolean): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure InterfaceMethodFindsDirectMappedDelegatedAndInherited;
    [Test]
    procedure InterfaceMethodOfAncestorInterface;
    [Test]
    procedure DelegationToInterfaceFieldNamesTheProperty;
    [Test]
    procedure VirtualMethodKinds;
    [Test]
    procedure AbstractMethodCountsItself;
    [Test]
    procedure DescendantWithoutRedeclarationIsNoSite;
    [Test]
    procedure GenericInterface;
    [Test]
    procedure KindNames;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cFile = 'C:\P\Sites.pas';
  cUnit =
    'unit Sites;'#10 +
    'interface'#10 +
    'type'#10 +
    '  IBasis = interface'#10 +
    '    procedure Speichern;'#10 +
    '  end;'#10 +
    '  IKunde = interface(IBasis)'#10 +
    '    procedure Laden;'#10 +
    '  end;'#10 +
    '  IVergleich<T> = interface'#10 +
    '    function Gleich(const A: T): Boolean;'#10 +
    '  end;'#10 +
    '  TDirekt = class(TInterfacedObject, IKunde)'#10 +
    '    procedure Speichern; virtual;'#10 +
    '    procedure Laden;'#10 +
    '  end;'#10 +
    '  TNachfahr = class(TDirekt)'#10 +
    '  end;'#10 +
    '  TUeberschrieben = class(TDirekt)'#10 +
    '    procedure Speichern; override;'#10 +
    '  end;'#10 +
    '  TZugeordnet = class(TInterfacedObject, IKunde)'#10 +
    '    procedure IKunde.Laden = Holen;'#10 +
    '    procedure Holen;'#10 +
    '    procedure Speichern;'#10 +
    '  end;'#10 +
    '  THelfer = class'#10 +
    '    procedure Laden;'#10 +
    '    procedure Speichern;'#10 +
    '  end;'#10 +
    '  TDelegiert = class(TInterfacedObject, IKunde)'#10 +
    '  private'#10 +
    '    FHelfer: THelfer;'#10 +
    '  public'#10 +
    '    property Helfer: THelfer read FHelfer implements IKunde;'#10 +
    '  end;'#10 +
    '  TFeld = class(TInterfacedObject, IKunde)'#10 +
    '  private'#10 +
    '    FKunde: IKunde;'#10 +
    '  public'#10 +
    '    property Kunde: IKunde read FKunde implements IKunde;'#10 +
    '  end;'#10 +
    '  TGeerbtBasis = class(TInterfacedObject)'#10 +
    '    procedure Laden;'#10 +
    '    procedure Speichern;'#10 +
    '  end;'#10 +
    '  TGeerbt = class(TGeerbtBasis, IKunde)'#10 +
    '  end;'#10 +
    '  TZahlVergleich = class(TInterfacedObject, IVergleich<Integer>)'#10 +
    '    function Gleich(const A: Integer): Boolean;'#10 +
    '  end;'#10 +
    '  TTier = class'#10 +
    '    procedure Laut; virtual; abstract;'#10 +
    '    procedure Lauf; virtual;'#10 +
    '  end;'#10 +
    '  THund = class(TTier)'#10 +
    '    procedure Laut; override;'#10 +
    '    procedure Lauf; override;'#10 +
    '  end;'#10 +
    '  TWelpe = class(THund)'#10 +
    '    procedure Laut; reintroduce;'#10 +
    '  end;'#10 +
    '  TKatze = class(TTier)'#10 +
    '    procedure Laut;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TDirekt.Speichern; begin end;'#10 +
    'procedure TDirekt.Laden; begin end;'#10 +
    'procedure TUeberschrieben.Speichern; begin end;'#10 +
    'procedure TZugeordnet.Holen; begin end;'#10 +
    'procedure TZugeordnet.Speichern; begin end;'#10 +
    'procedure THelfer.Laden; begin end;'#10 +
    'procedure THelfer.Speichern; begin end;'#10 +
    'procedure TGeerbtBasis.Laden; begin end;'#10 +
    'procedure TGeerbtBasis.Speichern; begin end;'#10 +
    'function TZahlVergleich.Gleich(const A: Integer): Boolean; begin Result := A = 0; end;'#10 +
    'procedure TTier.Lauf; begin end;'#10 +
    'procedure THund.Laut; begin end;'#10 +
    'procedure THund.Lauf; begin end;'#10 +
    'procedure TWelpe.Laut; begin end;'#10 +
    'procedure TKatze.Laut; begin end;'#10 +
    'end.';

{ TImplementationSitesTests }

procedure TImplementationSitesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnit, cFile, nil));
end;

procedure TImplementationSitesTests.TearDown;
begin
  FIndex := nil;
end;

function TImplementationSitesTests.Sites(const AContainer, AName: string; AInterface: Boolean): string;
var
  mSite: TImplementationSite;
begin
  Result := '';
  for mSite in TImplementationSites.Find(FIndex, nil, AContainer, AName, AInterface) do
  begin
    Result := Result + Format('%s>%s.%s:%s', [mSite.TypeName, mSite.DeclaringType, mSite.MethodName,
      TImplementationSites.KindName(mSite.Kind)]);
    if mSite.Via <> '' then
    begin
      Result := Result + '@' + mSite.Via;
    end;
    if not mSite.HasBody then
    begin
      Result := Result + '!';
    end;
    Result := Result + ' ';
  end;
  Result := Trim(Result);
end;

procedure TImplementationSitesTests.InterfaceMethodFindsDirectMappedDelegatedAndInherited;
begin
  // Direkt, Zuordnung IKunde.Laden = Holen, Delegation an THelfer, geerbt aus TGeerbtBasis; TNachfahr
  // deklariert nichts neu und fehlt.
  Assert.AreEqual('TDirekt>TDirekt.Laden:implements TZugeordnet>TZugeordnet.Holen:mapped ' +
    'TDelegiert>THelfer.Laden:delegated@Helfer TFeld>TFeld.Kunde:delegatedToField@Kunde! ' +
    'TGeerbt>TGeerbtBasis.Laden:inherited', Sites('IKunde', 'Laden', True));
end;

procedure TImplementationSitesTests.InterfaceMethodOfAncestorInterface;
begin
  // IBasis.Speichern: über IKunde(IBasis) umgesetzt; TUeberschrieben überschreibt die Umsetzung von TDirekt.
  Assert.AreEqual('TDirekt>TDirekt.Speichern:implements TZugeordnet>TZugeordnet.Speichern:implements ' +
    'TDelegiert>THelfer.Speichern:delegated@Helfer TFeld>TFeld.Kunde:delegatedToField@Kunde! ' +
    'TGeerbt>TGeerbtBasis.Speichern:inherited TUeberschrieben>TUeberschrieben.Speichern:overrides',
    Sites('IBasis', 'Speichern', True));
end;

procedure TImplementationSitesTests.DelegationToInterfaceFieldNamesTheProperty;
var
  mSite: TImplementationSite;
  mFound: Boolean;
begin
  mFound := False;
  for mSite in TImplementationSites.Find(FIndex, nil, 'IKunde', 'Laden', True) do
  begin
    if mSite.Kind = TImplementationKind.DelegatedToField then
    begin
      mFound := True;
      Assert.AreEqual('TFeld', mSite.TypeName);
      Assert.AreEqual('Kunde', mSite.Via);
      Assert.AreEqual(cFile, mSite.FileName);
    end;
  end;
  Assert.IsTrue(mFound);
end;

procedure TImplementationSitesTests.VirtualMethodKinds;
begin
  Assert.AreEqual('THund>THund.Laut:overrides TKatze>TKatze.Laut:hides TWelpe>TWelpe.Laut:reintroduces',
    Sites('TTier', 'Laut', False).Replace('TTier>TTier.Laut:abstract! ', ''));
  Assert.AreEqual('TTier>TTier.Lauf:own THund>THund.Lauf:overrides', Sites('TTier', 'Lauf', False));
end;

procedure TImplementationSitesTests.AbstractMethodCountsItself;
begin
  Assert.IsTrue(Sites('TTier', 'Laut', False).StartsWith('TTier>TTier.Laut:abstract! '));
  Assert.AreEqual(4, Integer(Length(TImplementationSites.Find(FIndex, nil, 'TTier', 'Laut', False))));
end;

procedure TImplementationSitesTests.DescendantWithoutRedeclarationIsNoSite;
begin
  Assert.AreEqual(0, Pos('TNachfahr', Sites('IKunde', 'Laden', True)));
  Assert.AreEqual('TDirekt>TDirekt.Speichern:own TUeberschrieben>TUeberschrieben.Speichern:overrides',
    Sites('TDirekt', 'Speichern', False));
end;

procedure TImplementationSitesTests.GenericInterface;
begin
  Assert.AreEqual('TZahlVergleich>TZahlVergleich.Gleich:implements', Sites('IVergleich', 'Gleich', True));
end;

procedure TImplementationSitesTests.KindNames;
begin
  Assert.AreEqual('implements', TImplementationSites.KindName(TImplementationKind.Implements));
  Assert.AreEqual('delegatedToField', TImplementationSites.KindName(TImplementationKind.DelegatedToField));
end;

initialization
  TDUnitX.RegisterTestFixture(TImplementationSitesTests);

end.
