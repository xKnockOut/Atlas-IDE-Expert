unit BDLsp.Common.Lsp.PublishedMembers.Tests;

interface

uses
  DUnitX.TestFramework,
  BDLsp.Common.Index.Contract;

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
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Index.Extractor,
  BDLsp.Common.Lsp.PublishedMembers;

const
  BasisFile = 'C:\P\Basis.pas';
  KnopfFile = 'C:\P\Knopf.pas';

  UnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBasis = class(TObject)'#10 +
    '  private'#10 +
    '    FTag: Integer;'#10 +
    '  public'#10 +
    '    property Caption: string read FCaption write FCaption;'#10 +
    '  published'#10 +
    '    property Tag: Integer read FTag write FTag default 0;'#10 +
    '    property OnChange: TNotifyEvent read FOnChange write FOnChange;'#10 +
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
  Assert.AreEqual('TKnopf', Members[0].DeclaringClass);
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
  // Deklariert mit Typ in TBasis, published erst in TKnopf (#308).
  Assert.AreEqual('TBasis', Members[Find(Members, 'Caption')].TypeClass);
  Assert.AreEqual('TKnopf', Members[Find(Members, 'Caption')].DeclaringClass);
  Assert.AreEqual('TKnopf', Members[Find(Members, 'Enabled')].TypeClass);
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

initialization
  TDUnitX.RegisterTestFixture(TPublishedMembersTests);

end.
