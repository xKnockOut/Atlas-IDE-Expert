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
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.PublishedMembers;

const
  BasisFile = 'C:\P\Basis.pas';
  KnopfFile = 'C:\P\Knopf.pas';

  UnitBasis =
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

  UnitKnopf =
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
  if SameText(AFileName, BasisFile) then
    AText := UnitBasis
  else if SameText(AFileName, KnopfFile) then
    AText := UnitKnopf
  else
    Result := False;
end;

function Find(const AMembers: TArray<TPublishedMember>; const AName: string): Integer;
begin
  for Result := 0 to High(AMembers) do
    if SameText(AMembers[Result].Name, AName) then
      Exit;
  Result := -1;
end;

{ TPublishedMembersTests }

procedure TPublishedMembersTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitKnopf, KnopfFile, nil));
end;

procedure TPublishedMembersTests.TearDown;
begin
  FIndex := nil;
end;

procedure TPublishedMembersTests.CollectsOwnAndInheritedProperties;
var
  Members: TArray<TPublishedMember>;
begin
  Members := TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource);
  Assert.AreEqual(5, Integer(Length(Members)));
  Assert.AreEqual('Caption', Members[0].Name);
  // Published wird Caption in TKnopf, deklariert (mit Typ) in TBasis.
  Assert.AreEqual('TBasis', Members[0].DeclaringClass);
  Assert.AreEqual('TKnopf', Members[0].PublishedIn);
  Assert.AreEqual('TBasis', Members[Find(Members, 'Tag')].DeclaringClass);
end;

procedure TPublishedMembersTests.ReadsDefaultValues;
var
  Members: TArray<TPublishedMember>;
begin
  Members := TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource);
  Assert.AreEqual('True', Members[Find(Members, 'Enabled')].DefaultValue);
  Assert.AreEqual('0', Members[Find(Members, 'Tag')].DefaultValue);
  Assert.AreEqual('', Members[Find(Members, 'OnKlick')].DefaultValue);
end;

procedure TPublishedMembersTests.SkipsNonPublishedProperties;
var
  Members: TArray<TPublishedMember>;
begin
  Members := TPublishedMembers.Collect(FIndex, 'TBasis', ReadSource);
  Assert.AreEqual(-1, Find(Members, 'Caption'));
  Assert.AreEqual(-1, Find(Members, 'Items'));
  Assert.AreEqual(2, Integer(Length(Members)));
end;

procedure TPublishedMembersTests.RedeclarationTakesTypeFromAncestor;
var
  Members: TArray<TPublishedMember>;
begin
  Members := TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource);
  Assert.AreEqual('string', Members[Find(Members, 'Caption')].TypeName);
end;

procedure TPublishedMembersTests.SeparatesEvents;
var
  Members: TArray<TPublishedMember>;
begin
  Members := TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource);
  Assert.IsTrue(Members[Find(Members, 'OnKlick')].IsEvent);
  Assert.IsTrue(Members[Find(Members, 'OnChange')].IsEvent);
  Assert.IsFalse(Members[Find(Members, 'Enabled')].IsEvent);
end;

procedure TPublishedMembersTests.WritesGroupedMarkdown;
var
  Text: string;
begin
  Text := TPublishedMembers.ToMarkdown(TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource));
  Assert.IsTrue(Pos('**Published-Properties** (3)', Text) > 0, Text);
  Assert.IsTrue(Pos('**Ereignisse** (2)', Text) > 0, Text);
  Assert.IsTrue(Pos('*TBasis*', Text) > 0, Text);
  Assert.IsTrue(Pos('- `Enabled`: `Boolean` = `True`', Text) > 0, Text);
end;

procedure TPublishedMembersTests.UnknownClassGivesNothing;
begin
  Assert.AreEqual(0, Integer(Length(TPublishedMembers.Collect(FIndex, 'TUnbekannt', ReadSource))));
  Assert.AreEqual('', TPublishedMembers.ToMarkdown(nil));
end;

procedure TPublishedMembersTests.EventTailFallsBackToNotifyEvent;
var
  Tail: string;
begin
  // TNotifyEvent steht nicht im Index: die bekannte Signatur; geerbt von TBasis (#113).
  Assert.IsTrue(TPublishedMembers.EventTail(FIndex, ReadSource, 'TKnopf', 'OnChange', Tail));
  Assert.AreEqual(TPublishedMembers.NotifyTail, Tail);
  // Ereignistyp im Index: seine Parameter.
  Assert.IsTrue(TPublishedMembers.EventTail(FIndex, ReadSource, 'TKnopf', 'OnKlick', Tail));
  Assert.AreEqual('(Sender: TObject; X: Integer)', Tail);
  // Unbekannter Ereignistyp und unbekanntes Ereignis: keine Signatur.
  Assert.IsFalse(TPublishedMembers.EventTail(FIndex, ReadSource, 'TVarianten', 'OnFremd', Tail));
  Assert.IsFalse(TPublishedMembers.EventTail(FIndex, ReadSource, 'TKnopf', 'OnFehlt', Tail));
end;

procedure TPublishedMembersTests.EventTypeWithoutEventInName;
var
  Members: TArray<TPublishedMember>;
begin
  Members := TPublishedMembers.Collect(FIndex, 'TVarianten', ReadSource);
  Assert.IsTrue(Members[Find(Members, 'Rueckruf')].IsEvent);
end;

procedure TPublishedMembersTests.OnPrefixWithoutMethodPointerIsNoEvent;
var
  Members: TArray<TPublishedMember>;
begin
  Members := TPublishedMembers.Collect(FIndex, 'TVarianten', ReadSource);
  Assert.IsFalse(Members[Find(Members, 'OnlineStatus')].IsEvent);
  // Unbekannter Typ: der Name allein macht kein Ereignis.
  Assert.IsFalse(Members[Find(Members, 'OnFremd')].IsEvent);
end;

procedure TPublishedMembersTests.MethodReferenceAndAliasAreEvents;
var
  Members: TArray<TPublishedMember>;
begin
  Members := TPublishedMembers.Collect(FIndex, 'TVarianten', ReadSource);
  Assert.IsTrue(Members[Find(Members, 'Abfrage')].IsEvent);
  Assert.IsTrue(Members[Find(Members, 'Kurz')].IsEvent);
  Assert.IsTrue(TPublishedMembers.IsEventType(FIndex, ReadSource, 'TKurzRueckruf'));
  Assert.IsFalse(TPublishedMembers.IsEventType(FIndex, ReadSource, 'TAusrichtung'));
end;

procedure TPublishedMembersTests.DistinguishesDefaultVariants;
var
  Members: TArray<TPublishedMember>;
  Text: string;
begin
  Members := TPublishedMembers.Collect(FIndex, 'TVarianten', ReadSource);
  Assert.IsTrue(Members[Find(Members, 'Breite')].DefaultKind = TPublishedDefaultKind.Explicit);
  Assert.AreEqual('64', Members[Find(Members, 'Breite')].DefaultValue);
  Assert.IsTrue(Members[Find(Members, 'Aktiv')].DefaultKind = TPublishedDefaultKind.Implicit);
  Assert.AreEqual('False', Members[Find(Members, 'Aktiv')].DefaultValue);
  Assert.IsTrue(Members[Find(Members, 'Zahl')].DefaultKind = TPublishedDefaultKind.NoDefault);
  Assert.AreEqual('False', Members[Find(Members, 'Titel')].Stored);
  Assert.IsTrue(Members[Find(Members, 'Titel')].DefaultKind = TPublishedDefaultKind.None);
  Assert.AreEqual('IsFarbeStored', Members[Find(Members, 'Farbe')].Stored);
  Assert.AreEqual('5', Members[Find(Members, 'Farbe')].DefaultValue);
  Assert.AreEqual('arLinks', Members[Find(Members, 'Ausrichtung')].DefaultValue);
  // Der Name "Default" ist keine Angabe; implizit 0.
  Assert.IsTrue(Members[Find(Members, 'Default')].DefaultKind = TPublishedDefaultKind.Implicit);
  Assert.AreEqual('0', Members[Find(Members, 'Default')].DefaultValue);
  Assert.AreEqual('default 5, stored IsFarbeStored', TPublishedMembers.DefaultText(Members[Find(Members, 'Farbe')]));
  Assert.AreEqual('default False (implizit)', TPublishedMembers.DefaultText(Members[Find(Members, 'Aktiv')]));
  Assert.AreEqual('nodefault', TPublishedMembers.DefaultText(Members[Find(Members, 'Zahl')]));
  Text := TPublishedMembers.ToMarkdown(Members);
  Assert.IsTrue(Pos('- `Breite`: `Integer` = `64`', Text) > 0, Text);
  Assert.IsTrue(Pos('- `Aktiv`: `Boolean` = `False` (implizit)', Text) > 0, Text);
  Assert.IsTrue(Pos('- `Zahl`: `Integer` · nodefault', Text) > 0, Text);
  Assert.IsTrue(Pos('- `Titel`: `string` · stored `False`', Text) > 0, Text);
end;

procedure TPublishedMembersTests.ArrayDefaultIsDefaultProperty;
var
  Text: string;
begin
  // Array-Property mit default: Standard-Property, kein Vorgabewert; auch geerbt.
  Assert.AreEqual('Strings[Index: Integer]: string',
    TPublishedMembers.DefaultProperty(FIndex, 'TVariantenKind', ReadSource));
  Assert.AreEqual('', TPublishedMembers.DefaultProperty(FIndex, 'TKnopf', ReadSource));
  Text := TPublishedMembers.ToMarkdown(TPublishedMembers.Collect(FIndex, 'TVarianten', ReadSource),
    'Strings[Index: Integer]: string');
  Assert.IsTrue(Pos('**Standard-Property:** `Strings[Index: Integer]: string`', Text) = 1, Text);
  Assert.IsTrue(Pos('- `Strings`', Text) = 0, Text);
end;

procedure TPublishedMembersTests.DeclaringClassIsFirstTypedDeclaration;
var
  Text: string;
begin
  // Gruppen nach deklarierender Klasse: Caption steht unter TBasis, nicht unter TKnopf.
  Text := TPublishedMembers.ToMarkdown(TPublishedMembers.Collect(FIndex, 'TKnopf', ReadSource));
  Assert.IsTrue(Pos('*TBasis*'#10'- `Caption`', Text) > 0, Text);
end;

procedure TPublishedMembersTests.WritesJsonForTooltip;

  function Member(AJson: TJSONObject; const AName: string): TJSONObject;
  var
    Value: TJSONValue;
  begin
    for Value in AJson.GetValue<TJSONArray>('members') do
      if TJSONObject(Value).GetValue<string>('name') = AName then
        Exit(TJSONObject(Value));
    Result := nil;
  end;

var
  Json: TJSONObject;
begin
  // atlas.published (#110): je Mitglied Typ, Vorgabe samt Art, stored, Herkunft und Ereignis.
  Assert.IsNull(TPublishedMembers.ToJson(nil, ''));
  Json := TPublishedMembers.ToJson(TPublishedMembers.Collect(FIndex, 'TVarianten', ReadSource),
    'Strings[Index: Integer]: string');
  try
    Assert.AreEqual('Strings[Index: Integer]: string', Json.GetValue<string>('defaultProperty'));
    Assert.AreEqual('Integer', Member(Json, 'Breite').GetValue<string>('type'));
    Assert.AreEqual('64', Member(Json, 'Breite').GetValue<string>('default'));
    Assert.AreEqual('explicit', Member(Json, 'Breite').GetValue<string>('defaultKind'));
    Assert.AreEqual('implicit', Member(Json, 'Aktiv').GetValue<string>('defaultKind'));
    Assert.AreEqual('nodefault', Member(Json, 'Zahl').GetValue<string>('defaultKind'));
    Assert.IsNull(Member(Json, 'Zahl').GetValue('default'));
    Assert.AreEqual('False', Member(Json, 'Titel').GetValue<string>('stored'));
    Assert.IsNull(Member(Json, 'Titel').GetValue('defaultKind'));
    Assert.AreEqual('TVarianten', Member(Json, 'Titel').GetValue<string>('declaringClass'));
    Assert.IsTrue(Member(Json, 'Rueckruf').GetValue('event') is TJSONTrue);
    Assert.IsNull(Member(Json, 'OnlineStatus').GetValue('event'));
  finally
    Json.Free;
  end;
  // Standard-Property allein reicht für ein Objekt.
  Json := TPublishedMembers.ToJson(nil, 'Items[I: Integer]: string');
  try
    Assert.AreEqual(0, Json.GetValue<TJSONArray>('members').Count);
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPublishedMembersTests);

end.
