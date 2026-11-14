unit Atlas.Common.Lsp.PublishedMembers.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TPublishedMembersTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CollectsOwnAndInheritedProperties;
    [Test]
    procedure ReadsDefaultValues;
    [Test]
    procedure SkipsNonPublishedProperties;
    [Test]
    procedure RedeclarationTakesTypeFromAncestor;
    [Test]
    procedure SeparatesEvents;
    [Test]
    procedure WritesGroupedMarkdown;
    [Test]
    procedure UnknownClassGivesNothing;
    [Test]
    procedure EventTailFallsBackToNotifyEvent;
    [Test]
    procedure EventTypeWithoutEventInName;
    [Test]
    procedure OnPrefixWithoutMethodPointerIsNoEvent;
    [Test]
    procedure MethodReferenceAndAliasAreEvents;
    [Test]
    procedure DistinguishesDefaultVariants;
    [Test]
    procedure ArrayDefaultIsDefaultProperty;
    [Test]
    procedure DeclaringClassIsFirstTypedDeclaration;
    [Test]
    procedure WritesJsonForTooltip;
    [Test]
    procedure CacheHoldsWhileTextsStayTheSame;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.PublishedMembers;

const
  cBasisFile = 'C:\P\Basis.pas';
  cKnopfFile = 'C:\P\Knopf.pas';

  cUnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKlickEvent = procedure(Sender: TObject; X: Integer) of object;'#10 +
    '  TMeinRueckruf = procedure(Sender: TObject) of object;'#10 +
    '  TAbfrage = reference to function(const AText: string): Boolean;'#10 +
    '  TKurzRueckruf = TMeinRueckruf;'#10 +
    '  TAusrichtung = (arLinks, arMitte, arRechts);'#10 +
    '  TBasis = class(TObject)'#10 +
    '  private'#10 +
    '    FTag: Integer;'#10 +
    '  public'#10 +
    '    property Caption: string read FCaption write FCaption;'#10 +
    '  published'#10 +
    '    property Tag: Integer read FTag write FTag default 0;'#10 +
    '    property OnChange: TNotifyEvent read FOnChange write FOnChange;'#10 +
    '  end;'#10 +
    '  TVarianten = class(TObject)'#10 +
    '  public'#10 +
    '    property Strings[Index: Integer]: string read GetString write SetString; default;'#10 +
    '  published'#10 +
    '    property Breite: Integer read FBreite write FBreite default 64;'#10 +
    '    property Aktiv: Boolean read FAktiv write FAktiv;'#10 +
    '    property Zahl: Integer read FZahl write FZahl nodefault;'#10 +
    '    property Titel: string read FTitel write FTitel stored False;'#10 +
    '    property Farbe: Integer read FFarbe write FFarbe stored IsFarbeStored default 5;'#10 +
    '    property Ausrichtung: TAusrichtung read FAusrichtung write FAusrichtung;'#10 +
    '    property Default: Integer read FDefault write FDefault;'#10 +
    '    property OnlineStatus: Boolean read FOnline write FOnline;'#10 +
    '    property Rueckruf: TMeinRueckruf read FRueckruf write FRueckruf;'#10 +
    '    property Kurz: TKurzRueckruf read FKurz write FKurz;'#10 +
    '    property Abfrage: TAbfrage read FAbfrage write FAbfrage;'#10 +
    '    property OnFremd: TFremdEvent read FFremd write FFremd;'#10 +
    '  end;'#10 +
    '  TVariantenKind = class(TVarianten)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cUnitKnopf =
    'unit Knopf;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TKnopf = class(TBasis)'#10 +
    '  published'#10 +
    '    property Caption;'#10 +
    '    property Enabled: Boolean read FEnabled write FEnabled default True;'#10 +
    '    property OnKlick: TKlickEvent read FOnKlick write FOnKlick;'#10 +
    '    property Items[I: Integer]: string read GetItem;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

function ReadSource(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, cBasisFile) then
  begin
    AText := cUnitBasis;
  end
  else if SameText(AFileName, cKnopfFile) then
  begin
    AText := cUnitKnopf;
  end
  else
  begin
    Result := False;
  end;
end;

function Find(const AMembers: TArray<TPublishedMember>; const AName: string): Integer;
begin
  for Result := 0 to High(AMembers) do
  begin
    if SameText(AMembers[Result].Name, AName) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

{ TPublishedMembersTests }

procedure TPublishedMembersTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitKnopf, cKnopfFile, nil));
end;

procedure TPublishedMembersTests.TearDown;
begin
  FIndex := nil;
end;

procedure TPublishedMembersTests.CollectsOwnAndInheritedProperties;
var
  mMembers: TArray<TPublishedMember>;
begin
  mMembers := TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource);
  Assert.AreEqual(5, Integer(Length(mMembers)));
  Assert.AreEqual('Caption', mMembers[0].Name);
  // Published wird Caption in TKnopf, deklariert (mit Typ) in TBasis.
  Assert.AreEqual('TBasis', mMembers[0].DeclaringClass);
  Assert.AreEqual('TKnopf', mMembers[0].PublishedIn);
  Assert.AreEqual('TBasis', mMembers[Find(mMembers, 'Tag')].DeclaringClass);
end;

procedure TPublishedMembersTests.ReadsDefaultValues;
var
  mMembers: TArray<TPublishedMember>;
begin
  mMembers := TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource);
  Assert.AreEqual('True', mMembers[Find(mMembers, 'Enabled')].DefaultValue);
  Assert.AreEqual('0', mMembers[Find(mMembers, 'Tag')].DefaultValue);
  Assert.AreEqual('', mMembers[Find(mMembers, 'OnKlick')].DefaultValue);
end;

procedure TPublishedMembersTests.SkipsNonPublishedProperties;
var
  mMembers: TArray<TPublishedMember>;
begin
  mMembers := TPublishedMembers.Collect(FIndex, 'TBasis', ReadSource);
  Assert.AreEqual(-1, Find(mMembers, 'Caption'));
  Assert.AreEqual(-1, Find(mMembers, 'Items'));
  Assert.AreEqual(2, Integer(Length(mMembers)));
end;

procedure TPublishedMembersTests.RedeclarationTakesTypeFromAncestor;
var
  mMembers: TArray<TPublishedMember>;
begin
  mMembers := TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource);
  Assert.AreEqual('string', mMembers[Find(mMembers, 'Caption')].TypeName);
end;

procedure TPublishedMembersTests.SeparatesEvents;
var
  mMembers: TArray<TPublishedMember>;
begin
  mMembers := TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource);
  Assert.IsTrue(mMembers[Find(mMembers, 'OnKlick')].IsEvent);
  Assert.IsTrue(mMembers[Find(mMembers, 'OnChange')].IsEvent);
  Assert.IsFalse(mMembers[Find(mMembers, 'Enabled')].IsEvent);
end;

procedure TPublishedMembersTests.WritesGroupedMarkdown;
var
  mText: string;
begin
  mText := TPublishedMembers.ToMarkdown(TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource));
  Assert.IsTrue(Pos('**Published-Properties** (3)', mText) > 0, mText);
  Assert.IsTrue(Pos('**Ereignisse** (2)', mText) > 0, mText);
  Assert.IsTrue(Pos('*TBasis*', mText) > 0, mText);
  Assert.IsTrue(Pos('- `Enabled`: `Boolean` = `True`', mText) > 0, mText);
end;

procedure TPublishedMembersTests.UnknownClassGivesNothing;
begin
  Assert.AreEqual(0, Integer(Length(TPublishedMembers.Collect(FIndex, 'TUnbekannt', ReadSource))));
  Assert.AreEqual('', TPublishedMembers.ToMarkdown(nil));
end;

procedure TPublishedMembersTests.EventTailFallsBackToNotifyEvent;
var
  mTail: string;
begin
  // TNotifyEvent steht nicht im Index: die bekannte Signatur; geerbt von TBasis (#113).
  Assert.IsTrue(TPublishedMembers.EventTail(FIndex, ReadSource, 'TKnopf', 'OnChange', mTail));
  Assert.AreEqual(TPublishedMembers.cNotifyTail, mTail);
  // Ereignistyp im Index: seine Parameter.
  Assert.IsTrue(TPublishedMembers.EventTail(FIndex, ReadSource, 'TKnopf', 'OnKlick', mTail));
  Assert.AreEqual('(Sender: TObject; X: Integer)', mTail);
  // Unbekannter Ereignistyp und unbekanntes Ereignis: keine Signatur.
  Assert.IsFalse(TPublishedMembers.EventTail(FIndex, ReadSource, 'TVarianten', 'OnFremd', mTail));
  Assert.IsFalse(TPublishedMembers.EventTail(FIndex, ReadSource, 'TKnopf', 'OnFehlt', mTail));
end;

procedure TPublishedMembersTests.EventTypeWithoutEventInName;
var
  mMembers: TArray<TPublishedMember>;
begin
  mMembers := TPublishedMembers.Collect(FIndex, 'TVarianten', ReadSource);
  Assert.IsTrue(mMembers[Find(mMembers, 'Rueckruf')].IsEvent);
end;

procedure TPublishedMembersTests.OnPrefixWithoutMethodPointerIsNoEvent;
var
  mMembers: TArray<TPublishedMember>;
begin
  mMembers := TPublishedMembers.Collect(FIndex, 'TVarianten', ReadSource);
  Assert.IsFalse(mMembers[Find(mMembers, 'OnlineStatus')].IsEvent);
  // Unbekannter Typ: der Name allein macht kein Ereignis.
  Assert.IsFalse(mMembers[Find(mMembers, 'OnFremd')].IsEvent);
end;

procedure TPublishedMembersTests.MethodReferenceAndAliasAreEvents;
var
  mMembers: TArray<TPublishedMember>;
begin
  mMembers := TPublishedMembers.Collect(FIndex, 'TVarianten', ReadSource);
  Assert.IsTrue(mMembers[Find(mMembers, 'Abfrage')].IsEvent);
  Assert.IsTrue(mMembers[Find(mMembers, 'Kurz')].IsEvent);
  Assert.IsTrue(TPublishedMembers.IsEventType(FIndex, ReadSource, 'TKurzRueckruf'));
  Assert.IsFalse(TPublishedMembers.IsEventType(FIndex, ReadSource, 'TAusrichtung'));
end;

procedure TPublishedMembersTests.DistinguishesDefaultVariants;
var
  mMembers: TArray<TPublishedMember>;
  mText: string;
begin
  mMembers := TPublishedMembers.Collect(FIndex, 'TVarianten', ReadSource);
  Assert.AreEqual<TPublishedDefaultKind>(TPublishedDefaultKind.Explicit, mMembers[Find(mMembers, 'Breite')].DefaultKind);
  Assert.AreEqual('64', mMembers[Find(mMembers, 'Breite')].DefaultValue);
  Assert.AreEqual<TPublishedDefaultKind>(TPublishedDefaultKind.Implicit, mMembers[Find(mMembers, 'Aktiv')].DefaultKind);
  Assert.AreEqual('False', mMembers[Find(mMembers, 'Aktiv')].DefaultValue);
  Assert.AreEqual<TPublishedDefaultKind>(TPublishedDefaultKind.NoDefault, mMembers[Find(mMembers, 'Zahl')].DefaultKind);
  Assert.AreEqual('False', mMembers[Find(mMembers, 'Titel')].Stored);
  Assert.AreEqual<TPublishedDefaultKind>(TPublishedDefaultKind.None, mMembers[Find(mMembers, 'Titel')].DefaultKind);
  Assert.AreEqual('IsFarbeStored', mMembers[Find(mMembers, 'Farbe')].Stored);
  Assert.AreEqual('5', mMembers[Find(mMembers, 'Farbe')].DefaultValue);
  Assert.AreEqual('arLinks', mMembers[Find(mMembers, 'Ausrichtung')].DefaultValue);
  // Der Name "Default" ist keine Angabe; implizit 0.
  Assert.AreEqual<TPublishedDefaultKind>(TPublishedDefaultKind.Implicit, mMembers[Find(mMembers, 'Default')].DefaultKind);
  Assert.AreEqual('0', mMembers[Find(mMembers, 'Default')].DefaultValue);
  Assert.AreEqual('default 5, stored IsFarbeStored', TPublishedMembers.DefaultText(mMembers[Find(mMembers, 'Farbe')]));
  Assert.AreEqual('default False (implizit)', TPublishedMembers.DefaultText(mMembers[Find(mMembers, 'Aktiv')]));
  Assert.AreEqual('nodefault', TPublishedMembers.DefaultText(mMembers[Find(mMembers, 'Zahl')]));
  mText := TPublishedMembers.ToMarkdown(mMembers);
  Assert.IsTrue(Pos('- `Breite`: `Integer` = `64`', mText) > 0, mText);
  Assert.IsTrue(Pos('- `Aktiv`: `Boolean` = `False` (implizit)', mText) > 0, mText);
  Assert.IsTrue(Pos('- `Zahl`: `Integer` · nodefault', mText) > 0, mText);
  Assert.IsTrue(Pos('- `Titel`: `string` · stored `False`', mText) > 0, mText);
end;

procedure TPublishedMembersTests.ArrayDefaultIsDefaultProperty;
var
  mText: string;
begin
  // Array-Property mit default: Standard-Property, kein Vorgabewert; auch geerbt.
  Assert.AreEqual('Strings[Index: Integer]: string',
    TPublishedMembers.DefaultProperty(FIndex, 'TVariantenKind', ReadSource));
  Assert.AreEqual('', TPublishedMembers.DefaultProperty(FIndex, 'TKnopf', ReadSource));
  mText := TPublishedMembers.ToMarkdown(TPublishedMembers.Collect(FIndex, 'TVarianten', ReadSource),
    'Strings[Index: Integer]: string');
  Assert.AreEqual(1, Pos('**Standard-Property:** `Strings[Index: Integer]: string`', mText), mText);
  Assert.AreEqual(0, Pos('- `Strings`', mText), mText);
end;

procedure TPublishedMembersTests.DeclaringClassIsFirstTypedDeclaration;
var
  mText: string;
begin
  // Gruppen nach deklarierender Klasse: Caption steht unter TBasis, nicht unter TKnopf.
  mText := TPublishedMembers.ToMarkdown(TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource));
  Assert.IsTrue(Pos('*TBasis*'#10'- `Caption`', mText) > 0, mText);
end;

procedure TPublishedMembersTests.WritesJsonForTooltip;

  function Member(AJson: TJSONObject; const AName: string): TJSONObject;
  var
    mValue: TJSONValue;
  begin
    for mValue in AJson.GetValue<TJSONArray>('members') do
    begin
      if TJSONObject(mValue).GetValue<string>('name') = AName then
      begin
        Exit(TJSONObject(mValue));
      end;
    end;
    Result := nil;
  end;

var
  mJson: TJSONObject;
begin
  // atlas.published (#110): je Mitglied Typ, Vorgabe samt Art, stored, Herkunft und Ereignis.
  Assert.IsNull(TPublishedMembers.ToJson(nil, ''));
  mJson := TPublishedMembers.ToJson(TPublishedMembers.Collect(FIndex, 'TVarianten', ReadSource),
    'Strings[Index: Integer]: string');
  try
    Assert.AreEqual('Strings[Index: Integer]: string', mJson.GetValue<string>('defaultProperty'));
    Assert.AreEqual('Integer', Member(mJson, 'Breite').GetValue<string>('type'));
    Assert.AreEqual('64', Member(mJson, 'Breite').GetValue<string>('default'));
    Assert.AreEqual('explicit', Member(mJson, 'Breite').GetValue<string>('defaultKind'));
    Assert.AreEqual('implicit', Member(mJson, 'Aktiv').GetValue<string>('defaultKind'));
    Assert.AreEqual('nodefault', Member(mJson, 'Zahl').GetValue<string>('defaultKind'));
    Assert.IsNull(Member(mJson, 'Zahl').GetValue('default'));
    Assert.AreEqual('False', Member(mJson, 'Titel').GetValue<string>('stored'));
    Assert.IsNull(Member(mJson, 'Titel').GetValue('defaultKind'));
    Assert.AreEqual('TVarianten', Member(mJson, 'Titel').GetValue<string>('declaringClass'));
    Assert.IsTrue(Member(mJson, 'Rueckruf').GetValue('event') is TJSONTrue);
    Assert.IsNull(Member(mJson, 'OnlineStatus').GetValue('event'));
  finally
    mJson.Free;
  end;
  // Standard-Property allein reicht für ein Objekt.
  mJson := TPublishedMembers.ToJson(nil, 'Items[I: Integer]: string');
  try
    Assert.AreEqual(0, mJson.GetValue<TJSONArray>('members').Count);
  finally
    mJson.Free;
  end;
end;




/// <summary>Leser ohne Dateien: als hätten sich alle Texte geändert.</summary>
function NothingReader: TMemberReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := False;
    end;
end;

procedure TPublishedMembersTests.CacheHoldsWhileTextsStayTheSame;
var
  mFirst, mSecond, mThird: TArray<TPublishedMember>;
begin
  TPublishedMembers.UseCache(True);
  try
    mFirst := TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource);
    Assert.IsTrue(Length(mFirst) > 0);
    // Gleiche Texte: derselbe Eintrag.
    mSecond := TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource);
    Assert.AreEqual(Integer(Length(mFirst)), Integer(Length(mSecond)));
    // Andere Texte (hier: keine): der Eintrag gilt nicht mehr, neu gelesen bleibt nichts.
    mThird := TPublishedMembers.Collect(FIndex, 'TKnopf', NothingReader());
    Assert.AreEqual(0, Integer(Length(mThird)));
  finally
    TPublishedMembers.UseCache(False);
  end;
  mFirst := nil;
  mSecond := nil;
  mThird := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TPublishedMembersTests);

end.
