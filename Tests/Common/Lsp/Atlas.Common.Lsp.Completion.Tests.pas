unit Atlas.Common.Lsp.Completion.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Completion;

type
  [TestFixture]
  TLspCompletionTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemsAt(const AText, AMarker: string;
      AMatching: TCompletionMatching = TCompletionMatching.Prefix): TCompletionItems;
    function Names(const AItems: TCompletionItems): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ScopeListsLocalsMembersAndUsedUnits;
    [Test]
    procedure ScopeFiltersByPrefix;
    [Test]
    procedure MembersAfterDotIncludeInherited;
    [Test]
    procedure MembersOfUnitAreInterfaceSymbols;
    [Test]
    procedure UsesClauseListsUnits;
    [Test]
    procedure NothingInCommentsAndStrings;
    [Test]
    procedure WritesCompletionList;
    [Test]
    procedure FuzzyFindsSubsequencesAndAbbreviations;
    [Test]
    procedure FuzzySortsByScoreThenScope;
    [Test]
    procedure FuzzySetsFilterTextAndIsIncomplete;
    [Test]
    procedure PrefixModeKeepsStrictSelection;
    [Test]
    procedure OffersSymbolsOfUnusedUnitsWithUsesEdit;
    [Test]
    procedure ImportsNeedTwoCharactersAndSkipUsedUnits;
    [Test]
    procedure MembersCarryContainerDepthAndOverloads;
    [Test]
    procedure OffersOverridesWithDeclarationAndBody;
    [Test]
    procedure OffersMatchingHandlersAndNewMethodForEvents;
    [Test]
    procedure GroupsByExpectedType;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract;

const
  HauptFile = 'C:\P\Haupt.pas';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBasis = class'#10 +
    '    Zaehler: Integer;'#10 +
    '    procedure Melde;'#10 +
    '  end;'#10 +
    'procedure Rechne;'#10 +
    'implementation'#10 +
    'procedure Versteckt;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Rechne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TBasis.Melde;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werkzeug;'#10 +
    'type'#10 +
    '  TFoo = class(TBasis)'#10 +
    '    Name: string;'#10 +
    '    procedure Bar(Anzahl: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar(Anzahl: Integer);'#10 +
    'var'#10 +
    '  Wert: TFoo;'#10 +
    'begin'#10 +
    '  { Kommentar Wert } |'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  Index, Line, LineStart, Scan: Integer;
begin
  // Cursor hinter AMarker.
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Inc(Index, Length(AMarker));
  Line := 0;
  LineStart := 1;
  for Scan := 1 to Index - 1 do
    if AText[Scan] = #10 then
    begin
      Inc(Line);
      LineStart := Scan + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

function WithCode(const ACode: string): string;
begin
  Result := StringReplace(UnitHaupt, '  { Kommentar Wert } |', ACode, []);
end;

{ TLspCompletionTests }

procedure TLspCompletionTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, 'C:\P\Werkzeug.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspCompletionTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspCompletionTests.ItemsAt(const AText, AMarker: string;
  AMatching: TCompletionMatching): TCompletionItems;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile, PositionOf(AText, AMarker), AMatching);
  finally
    Tree.Free;
  end;
end;

function TLspCompletionTests.Names(const AItems: TCompletionItems): string;
var
  Item: TCompletionItem;
begin
  Result := '';
  for Item in AItems.Items do
    Result := Result + Item.Name + ' ';
  Result := Result.Trim;
end;

procedure TLspCompletionTests.ScopeListsLocalsMembersAndUsedUnits;
begin
  // Nächster Gültigkeitsbereich zuerst; Versteckt steht nur in implementation von Werkzeug.
  Assert.AreEqual('Anzahl Wert Self Name Bar Zaehler Melde TFoo TBasis Rechne',
    Names(ItemsAt(WithCode('  '), #10'begin'#10'  ')));
end;

procedure TLspCompletionTests.ScopeFiltersByPrefix;
begin
  Assert.AreEqual('Wert', Names(ItemsAt(WithCode('  We'), '  We')));
  Assert.AreEqual('TFoo', Names(ItemsAt(WithCode('  tf'), '  tf')));
end;

procedure TLspCompletionTests.MembersAfterDotIncludeInherited;
var
  Text: string;
begin
  Text := WithCode('  Wert.');
  Assert.AreEqual('Name Bar Zaehler Melde', Names(ItemsAt(Text, 'Wert.')));
  Text := WithCode('  Self.Za');
  Assert.AreEqual('Zaehler', Names(ItemsAt(Text, 'Self.Za')));
end;

procedure TLspCompletionTests.MembersOfUnitAreInterfaceSymbols;
var
  Text: string;
begin
  Text := WithCode('  Werkzeug.');
  Assert.AreEqual('TBasis Rechne', Names(ItemsAt(Text, 'Werkzeug.')));
end;

procedure TLspCompletionTests.UsesClauseListsUnits;
var
  Text: string;
  Items: TCompletionItems;
begin
  Text := StringReplace(UnitHaupt, 'uses Werkzeug;', 'uses Werk', []);
  Items := ItemsAt(Text, 'uses Werk');
  Assert.AreEqual('Werkzeug', Names(Items));
  Assert.AreEqual(9, Items.Items[0].Kind);
end;

procedure TLspCompletionTests.NothingInCommentsAndStrings;
begin
  Assert.AreEqual('', Names(ItemsAt(UnitHaupt, '{ Kommentar W')));
  Assert.AreEqual('', Names(ItemsAt(WithCode('  Name := ''We'';'), '''We')));
  Assert.AreEqual('', Names(ItemsAt(WithCode('  // We'), '// We')));
end;

procedure TLspCompletionTests.WritesCompletionList;
var
  Items: TCompletionItems;
  Json: TJSONObject;
begin
  SetLength(Items.Items, 1);
  Items.Items[0].Name := 'Wert';
  Items.Items[0].Detail := 'TFoo';
  Items.Items[0].Kind := 6;
  Items.Incomplete := False;
  Json := TLspCompletion.ToJson(Items);
  try
    Assert.AreEqual('{"isIncomplete":false,"items":[{"label":"Wert","kind":6,"detail":"TFoo","sortText":"00000"}]}',
      Json.ToJSON);
  finally
    Json.Free;
  end;
end;

procedure TLspCompletionTests.FuzzyFindsSubsequencesAndAbbreviations;
begin
  // "zlr" ist Teilfolge von Zaehler, "TB" Kürzel von TBasis.
  Assert.AreEqual('Zaehler', Names(ItemsAt(WithCode('  zlr'), '  zlr', TCompletionMatching.Fuzzy)));
  Assert.AreEqual('TBasis', Names(ItemsAt(WithCode('  TBa'), '  TBa', TCompletionMatching.Fuzzy)));
  Assert.AreEqual('', Names(ItemsAt(WithCode('  xyz'), '  xyz', TCompletionMatching.Fuzzy)));
end;

procedure TLspCompletionTests.FuzzySortsByScoreThenScope;
var
  Items: TCompletionItems;
begin
  // Präfix-Treffer vor Teilfolgen; "me" passt als Präfix auf Melde, als Teilwort nicht weiter.
  Items := ItemsAt(WithCode('  me'), '  me', TCompletionMatching.Fuzzy);
  Assert.AreEqual('Melde', Items.Items[0].Name, Names(Items));
  // Ohne Eingabe bleibt die Reihenfolge der Gültigkeitsbereiche.
  Assert.AreEqual('Anzahl Wert Self Name Bar Zaehler Melde TFoo TBasis Rechne',
    Names(ItemsAt(WithCode('  '), #10'begin'#10'  ', TCompletionMatching.Fuzzy)));
end;

procedure TLspCompletionTests.FuzzySetsFilterTextAndIsIncomplete;
var
  Items: TCompletionItems;
  Json: TJSONObject;
begin
  Items := ItemsAt(WithCode('  zlr'), '  zlr', TCompletionMatching.Fuzzy);
  Assert.IsTrue(Items.Incomplete);
  Assert.AreEqual('zlr', Items.Items[0].FilterText);
  Json := TLspCompletion.ToJson(Items);
  try
    Assert.AreEqual('zlr', Json.GetValue<string>('items[0].filterText'));
    Assert.IsTrue(Json.GetValue<Boolean>('isIncomplete'));
  finally
    Json.Free;
  end;
  // Präfix-Treffer brauchen keinen filterText.
  Items := ItemsAt(WithCode('  We'), '  We', TCompletionMatching.Fuzzy);
  Assert.AreEqual('Wert', Items.Items[0].Name);
  Assert.AreEqual('', Items.Items[0].FilterText);
end;

procedure TLspCompletionTests.PrefixModeKeepsStrictSelection;
var
  Items: TCompletionItems;
begin
  Items := ItemsAt(WithCode('  zlr'), '  zlr', TCompletionMatching.Prefix);
  Assert.AreEqual('', Names(Items));
  Assert.IsFalse(Items.Incomplete);
end;

procedure TLspCompletionTests.OffersSymbolsOfUnusedUnitsWithUsesEdit;
var
  Bibliothek: TUnitIndex;
  Items: TCompletionItems;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit Extra;'#10'interface'#10'procedure Berechne;'#10 +
    'implementation'#10'procedure Berechne; begin end;'#10'end.', 'C:\P\Extra.pas', nil));
  Bibliothek := TIndexExtractor.ExtractText('unit Bib.Mathe;'#10'interface'#10'procedure Berechne;'#10 +
    'implementation'#10'procedure Berechne; begin end;'#10'end.', 'C:\Bib\Bib.Mathe.pas', nil);
  Bibliothek.Library_ := True;
  FIndex.AddUnit(Bibliothek);
  Items := ItemsAt(WithCode('  Ber'), '  Ber', TCompletionMatching.Fuzzy);
  // Projekt-Unit vor Bibliothek; eingetragen wird im implementation-Teil, der noch kein uses hat.
  Assert.AreEqual('Berechne Berechne', Names(Items));
  Assert.AreEqual('Extra (uses ergänzen)', Items.Items[0].Detail);
  Assert.AreEqual('Bib.Mathe (uses ergänzen)', Items.Items[1].Detail);
  Assert.AreEqual(1, Integer(Length(Items.Items[0].AdditionalEdits)));
  Assert.AreEqual(#13#10#13#10'uses'#13#10'  Extra;', Items.Items[0].AdditionalEdits[0].NewText);
  Assert.AreEqual(8, Items.Items[0].AdditionalEdits[0].Range.StartPos.Line);
end;

procedure TLspCompletionTests.ImportsNeedTwoCharactersAndSkipUsedUnits;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit Extra;'#10'interface'#10'procedure Berechne;'#10 +
    'implementation'#10'end.', 'C:\P\Extra.pas', nil));
  Assert.AreEqual('Bar', Names(ItemsAt(WithCode('  B'), '  B', TCompletionMatching.Prefix)).Split([' '])[0]);
  Assert.IsFalse(Names(ItemsAt(WithCode('  B'), '  B', TCompletionMatching.Prefix)).Contains('Berechne'));
  // Rechne kommt aus dem eingebundenen Werkzeug und erscheint nur einmal, ohne uses-Eintrag.
  Assert.AreEqual('Rechne', Names(ItemsAt(WithCode('  Rech'), '  Rech', TCompletionMatching.Prefix)));
  Assert.AreEqual(0, Integer(Length(ItemsAt(WithCode('  Rech'), '  Rech', TCompletionMatching.Prefix).Items[0].AdditionalEdits)));
end;

procedure TLspCompletionTests.MembersCarryContainerDepthAndOverloads;
const
  UnitUeber =
    'unit Ueber;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TGrund = class'#10 +
    '    procedure Schreibe; overload;'#10 +
    '    procedure Schreibe(const Text: string); overload;'#10 +
    '    procedure Schreibe(Wert: Integer); overload;'#10 +
    '  end;'#10 +
    '  TAbleitung = class(TGrund)'#10 +
    '    procedure Eigen;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TGrund.Schreibe; begin end;'#10 +
    'procedure TGrund.Schreibe(const Text: string); begin end;'#10 +
    'procedure TGrund.Schreibe(Wert: Integer); begin end;'#10 +
    'procedure TAbleitung.Eigen; begin end;'#10 +
    'end.';
  Text =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Ueber;'#10 +
    'implementation'#10 +
    'procedure Test;'#10 +
    'var'#10 +
    '  A: TAbleitung;'#10 +
    'begin'#10 +
    '  A.'#10 +
    'end;'#10 +
    'end.';
var
  Items: TCompletionItems;
  Json: TJSONObject;
  Data: TJSONObject;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitUeber, 'C:\P\Ueber.pas', nil));
  Items := ItemsAt(Text, '  A.');
  Assert.AreEqual('Eigen Schreibe', Names(Items));
  // Eigene Klasse: Tiefe 0; geerbt: Tiefe 1 mit deklarierender Klasse (#419).
  Assert.AreEqual('TAbleitung', Items.Items[0].Container);
  Assert.AreEqual(0, Items.Items[0].Depth);
  Assert.AreEqual('TGrund', Items.Items[1].Container);
  Assert.AreEqual(1, Items.Items[1].Depth);
  // Drei Überladungen: ein Eintrag mit zwei weiteren Positionen; Rümpfe zählen nicht (#425).
  Assert.AreEqual(2, Integer(Length(Items.Items[1].Overloads)));
  Assert.AreEqual(0, Integer(Length(Items.Items[0].Overloads)));
  // Klammern beim Übernehmen (#430): Eigen hat keine Parameter, Schreibe in zwei Überladungen.
  Assert.IsFalse(Items.Items[0].HasParameters);
  Assert.IsTrue(Items.Items[1].HasParameters);
  Json := TLspCompletion.ToJson(Items);
  try
    Data := ((Json.GetValue('items') as TJSONArray).Items[1] as TJSONObject).GetValue('data') as TJSONObject;
    Assert.AreEqual('TGrund', Data.GetValue<string>('container'));
    Assert.AreEqual(1, Data.GetValue<Integer>('depth'));
    Assert.IsTrue(Data.GetValue('parameters') is TJSONTrue);
    Assert.AreEqual(2, (Data.GetValue('overloads') as TJSONArray).Count);
    Assert.AreEqual(5, (Data.GetValue('overloads') as TJSONArray).Items[0].GetValue<Integer>('line'));
  finally
    Json.Free;
  end;
end;

procedure TLspCompletionTests.OffersOverridesWithDeclarationAndBody;
const
  UnitBasis =
    'unit Basis;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TBasisListe = class'#13#10 +
    '  protected'#13#10 +
    '    procedure Changed; virtual;'#13#10 +
    '    function Count: Integer; virtual;'#13#10 +
    '    procedure Fest;'#13#10 +
    '    procedure Pruefe(A: Integer; const B: string = ''''); virtual; abstract;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  Text =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Basis;'#13#10 +
    'type'#13#10 +
    '  TLogList = class(TBasisListe)'#13#10 +
    '  protected'#13#10 +
    '    procedure '#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TCompletionItems;
  Body: string;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, 'C:\P\Basis.pas', nil));
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(TLspCompletion.OverrideItems(Resolver, Tree, Text, HauptFile, PositionOf(Text, '    procedure '),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitBasis;
        Result := SameText(AFileName, 'C:\P\Basis.pas');
      end, Items));
    // Nur virtuelle Prozeduren; Count ist eine Funktion, Fest nicht virtuell.
    Assert.AreEqual('Changed Pruefe', Names(Items));
    Assert.AreEqual('Changed; override;', Items.Items[0].InsertText);
    Assert.AreEqual('TBasisListe', Items.Items[0].Container);
    Assert.AreEqual(1, Integer(Length(Items.Items[0].AdditionalEdits)));
    Body := Items.Items[0].AdditionalEdits[0].NewText;
    Assert.IsTrue(Body.Contains('procedure TLogList.Changed;'#13#10'begin'#13#10'  inherited;'#13#10'end;'), Body);
    // Abstrakt: ohne inherited; Standardwert nur in der Deklaration.
    Assert.AreEqual('Pruefe(A: Integer; const B: string = ''''); override;', Items.Items[1].InsertText);
    Body := Items.Items[1].AdditionalEdits[0].NewText;
    Assert.IsTrue(Body.Contains('procedure TLogList.Pruefe(A: Integer; const B: string);'), Body);
    Assert.IsFalse(Body.Contains('inherited'), Body);
    // Außerhalb einer Klassendeklaration kein Override-Kontext.
    Assert.IsFalse(TLspCompletion.OverrideItems(Resolver, Tree, Text, HauptFile, PositionOf(Text, 'uses Ba'), nil, Items));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspCompletionTests.OffersMatchingHandlersAndNewMethodForEvents;
const
  UnitBasis =
    'unit Basis;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TNotifyEvent = procedure(Sender: TObject) of object;'#13#10 +
    '  TButton = class'#13#10 +
    '  published'#13#10 +
    '    property OnClick: TNotifyEvent read FOnClick write FOnClick;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  Text =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Basis;'#13#10 +
    'type'#13#10 +
    '  TForm1 = class'#13#10 +
    '    btnSave: TButton;'#13#10 +
    '    procedure FormCreate(Sender: TObject);'#13#10 +
    '    procedure Fertig(Sender: TObject; var Done: Boolean);'#13#10 +
    '    procedure btnSaveClick(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TForm1.FormCreate(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  btnSave.OnClick := '#13#10 +
    'end;'#13#10 +
    'procedure TForm1.Fertig(Sender: TObject; var Done: Boolean);'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'procedure TForm1.btnSaveClick(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TCompletionItems;
  Item: TCompletionItem;
  Handlers, Edits: string;
  Edit: TRuleEdit;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, 'C:\P\Basis.pas', nil));
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(TLspCompletion.EventItems(Resolver, Tree, Text, HauptFile, PositionOf(Text, 'btnSave.OnClick := '),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitBasis;
        Result := SameText(AFileName, 'C:\P\Basis.pas');
      end, Items));
    // Nur Methoden mit (Sender: TObject); Fertig hat zwei Parameter.
    Handlers := '';
    for Item in Items.Items do
      if Item.Action = '' then
      begin
        Handlers := Handlers + ' ' + Item.Name;
        Assert.AreEqual('TNotifyEvent', Item.Expected);
        Assert.IsTrue(Item.Fits);
      end;
    Assert.AreEqual(' FormCreate btnSaveClick', Handlers);
    // Zuletzt die neue Methode; btnSaveClick ist vergeben.
    Item := Items.Items[High(Items.Items)];
    Assert.AreEqual('create', Item.Action);
    Assert.AreEqual('Neue Methode btnSaveClick2 …', Item.Name);
    Assert.AreEqual('btnSaveClick2', Item.InsertText);
    Edits := '';
    for Edit in Item.AdditionalEdits do
      Edits := Edits + Edit.NewText + '|';
    Assert.AreEqual(2, Integer(Length(Item.AdditionalEdits)), Edits);
    Assert.IsTrue(Edits.Contains('private'#13#10'    procedure btnSaveClick2(Sender: TObject);'), Edits);
    Assert.IsTrue(Edits.Contains('procedure TForm1.btnSaveClick2(Sender: TObject);'#13#10'begin'#13#10#13#10'end;'),
      Edits);
    // Keine Ereignis-Zuweisung: normale Vervollständigung.
    Assert.IsFalse(TLspCompletion.EventItems(Resolver, Tree, Text, HauptFile, PositionOf(Text, 'uses Ba'), nil, Items));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspCompletionTests.GroupsByExpectedType;

  function MakeText(const ALine: string): string;
  begin
    Result :=
      'unit Haupt;'#13#10 +
      'interface'#13#10 +
      'type'#13#10 +
      '  TBasis = class'#13#10 +
      '  end;'#13#10 +
      '  TKind = class(TBasis)'#13#10 +
      '  end;'#13#10 +
      '  TListe = class'#13#10 +
      '  public'#13#10 +
      '    function Count: Integer;'#13#10 +
      '    function Name: string;'#13#10 +
      '    function IndexOf(const S: string): Integer;'#13#10 +
      '    procedure Clear;'#13#10 +
      '    property Erstes: TKind read FErstes;'#13#10 +
      '  end;'#13#10 +
      'function Rechne(A: Integer; B: TBasis): Integer;'#13#10 +
      'implementation'#13#10 +
      'function Rechne(A: Integer; B: TBasis): Integer;'#13#10 +
      'var'#13#10 +
      '  L: TListe;'#13#10 +
      '  I: Integer;'#13#10 +
      '  Obj: TBasis;'#13#10 +
      'begin'#13#10 +
      '  ' + ALine + #13#10 +
      'end;'#13#10 +
      'end.';
  end;

  function Check(const ALine, AExpected, AFits: string): string;
  var
    Text, Fits: string;
    Tree: TSyntaxTree;
    Resolver: TNameResolver;
    Items: TCompletionItems;
    Item: TCompletionItem;
    Position: TTextPosition;
    Fitting: Boolean;
  begin
    Text := MakeText(ALine);
    Position := PositionOf(Text, ALine);
    Tree := TPascalParser.Parse(Text);
    Resolver := TNameResolver.Create(FIndex);
    try
      Result := TLspCompletion.ExpectedType(Resolver, Tree, HauptFile, Position);
      Items := TLspCompletion.Collect(Resolver, FIndex, Tree, HauptFile, Position);
      // Passende zuerst, danach keine passenden mehr.
      Fits := '';
      Fitting := True;
      for Item in Items.Items do
      begin
        Assert.AreEqual(AExpected, Item.Expected, ALine + ': ' + Item.Name);
        if Item.Fits then
        begin
          Assert.IsTrue(Fitting, ALine + ': ' + Item.Name + ' steht hinter nicht passenden');
          Fits := Fits + ' ' + Item.Name;
        end
        else
          Fitting := False;
      end;
      Assert.AreEqual(AFits, Trim(Fits), ALine);
    finally
      Resolver.Free;
      Tree.Free;
    end;
  end;

begin
  // Beispiel aus #417: Integer-Zuweisung, Count und IndexOf oben.
  Assert.AreEqual('Integer', Check('I := L.', 'Integer', 'Count IndexOf'));
  // Klasse: Nachfahr passt.
  Assert.AreEqual('TBasis', Check('Obj := L.', 'TBasis', 'Erstes'));
  // Parameter im Aufruf.
  Assert.AreEqual('TBasis', Check('Rechne(1, L.', 'TBasis', 'Erstes'));
  // Rückgabetyp bei Result.
  Assert.AreEqual('Integer', Check('Result := L.', 'Integer', 'Count IndexOf'));
  // Ohne erwarteten Typ keine Gruppierung.
  Assert.AreEqual('', Check('L.', '', ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCompletionTests);

end.
