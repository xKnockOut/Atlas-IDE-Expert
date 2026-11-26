unit Editing.Completion.Properties.Tests;

// Tests für die Vervollständigung in "property … read/write" (#31) samt Feld und Zugriffsmethoden anlegen (#467).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Completion.Contract;

type
  [TestFixture]
  TEditingPropertyCompletionTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    /// <summary>TEditingPropertyCompletion.Items hinter AMarker in AText mit ASettings.</summary>
    function ItemsAt(const AText, AMarker: string; const ASettings: TCompletionSettings;
      out AItems: TCompletionItems): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Nach read Felder und Funktionen vom Typ, auch geerbte; bei Indexeigenschaften kein Feld.</summary>
    [Test]
    procedure ReadOffersMatchingGetters;
    [Test]
    procedure WriteOffersMatchingSetters;
    /// <summary>„Feld FCaption anlegen“ und „GetCaption anlegen“ oben, mit Ersetzung und Zusatzänderungen.</summary>
    [Test]
    procedure OffersAccessorCreation;
    /// <summary>Abschnitt der Methoden nach completion.accessorSection; abgeschaltet nur Vorhandenes.</summary>
    [Test]
    procedure AccessorCreationFollowsSettings;
    /// <summary>Die Quelle antwortet in der property-Zeile allein, sonst nicht.</summary>
    [Test]
    procedure SourceAnswersOnlyInPropertyLine;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Completion.Request,
  Atlas.Common.Completion.Answer,
  Editing.Completion.Properties,
  Atlas.Tests.SourceText;

const
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBasis = class'#10 +
    '  public'#10 +
    '    Zaehler: Integer;'#10 +
    '    function Anzahl: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TBasis.Anzahl: Integer;'#10 +
    'begin'#10 +
    '  Result := 0;'#10 +
    'end;'#10 +
    'end.';

  cUnitLesen =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TFoo = class(TBasis)'#10 +
    '  strict private'#10 +
    '    FWert: Integer;'#10 +
    '    FName: string;'#10 +
    '    function GetWert: Integer;'#10 +
    '    function GetItem(I: Integer): string;'#10 +
    '    procedure SetWert(A: Integer);'#10 +
    '  public'#10 +
    '    property Wert: Integer read '#10 +
    '    property Items[I: Integer]: string read '#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cUnitSchreiben =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FWert: Integer;'#10 +
    '    function GetWert: Integer;'#10 +
    '    procedure SetWert(A: Integer);'#10 +
    '    procedure SetName(const A: string);'#10 +
    '  public'#10 +
    '    property Wert: Integer read GetWert write Se'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cUnitAnlegen =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    property Caption: string read Ca'#10 +
    '    property Titel: string read FName write '#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

/// <summary>Namen der Einträge in ihrer Reihenfolge, durch Leerzeichen getrennt.</summary>
function NamesOf(const AItems: TCompletionItems): string;
var
  mNames: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mNames, Length(AItems.Items));
  for mIndex := 0 to High(AItems.Items) do
  begin
    mNames[mIndex] := AItems.Items[mIndex].Name;
  end;
  Result := string.Join(' ', mNames);
end;

/// <summary>Neuer Text aller Zusatzänderungen von AItem hintereinander.</summary>
function InsertedBy(const AItem: TCompletionItem): string;
var
  mEdit: TTextEdit;
begin
  Result := '';
  for mEdit in AItem.AdditionalEdits do
  begin
    Result := Result + mEdit.NewText;
  end;
end;

{ TEditingPropertyCompletionTests }

procedure TEditingPropertyCompletionTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, 'C:\P\Basis.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TEditingPropertyCompletionTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TEditingPropertyCompletionTests.ItemsAt(const AText, AMarker: string; const ASettings: TCompletionSettings;
  out AItems: TCompletionItems): Boolean;
var
  mTree: TSyntaxTree;
  mRequest: TCompletionRequest;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  mRequest := nil;
  try
    mRequest := TCompletionRequest.Create(AText, cHauptFile, TTestSource.PositionAfter(AText, AMarker));
    mRequest.Tree := mTree;
    mRequest.Resolver := FResolver;
    mRequest.Index := FIndex;
    mRequest.Matching := TCompletionMatching.Prefix;
    mRequest.Settings := ASettings;
    Result := TEditingPropertyCompletion.Items(mRequest, AItems);
  finally
    mRequest.Free;
    mTree.Free;
  end;
end;

procedure TEditingPropertyCompletionTests.ReadOffersMatchingGetters;
var
  mItems: TCompletionItems;
begin
  Assert.IsTrue(ItemsAt(cUnitLesen, 'Wert: Integer read ', TCompletionSettings.Default, mItems));
  // Felder und Funktionen vom Typ Integer, auch geerbte (Zaehler, Anzahl); kein string, kein Setter. FWert und
  // GetWert gibt es schon, also nichts zum Anlegen.
  Assert.AreEqual('FWert GetWert Zaehler Anzahl', NamesOf(mItems));
  Assert.IsTrue(ItemsAt(cUnitLesen, 'string read ', TCompletionSettings.Default, mItems));
  // Dazu „GetItems anlegen“ (#467) oben; ein Feld gibt es zu Indexeigenschaften nicht.
  Assert.AreEqual('GetItems anlegen GetItem', NamesOf(mItems));
  // Außerhalb einer property-Zeile kein Kontext.
  Assert.IsFalse(ItemsAt(cUnitLesen, 'FWert: ', TCompletionSettings.Default, mItems));
end;

procedure TEditingPropertyCompletionTests.WriteOffersMatchingSetters;
var
  mItems: TCompletionItems;
  mSettings: TCompletionSettings;
begin
  mSettings := TCompletionSettings.Default;
  mSettings.CreateAccessors := False;
  Assert.IsTrue(ItemsAt(cUnitSchreiben, 'write Se', mSettings, mItems));
  Assert.AreEqual('SetWert', NamesOf(mItems));
end;

procedure TEditingPropertyCompletionTests.OffersAccessorCreation;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mInserted: string;
begin
  // #467: Nach "read Ca" stehen „Feld FCaption anlegen“ und „GetCaption anlegen“ oben.
  Assert.IsTrue(ItemsAt(cUnitAnlegen, 'read Ca', TCompletionSettings.Default, mItems));
  Assert.AreEqual('Feld FCaption anlegen GetCaption anlegen', NamesOf(mItems));
  mItem := mItems.Items[0];
  Assert.AreEqual('create', mItem.Action);
  Assert.IsTrue(mItem.Pinned);
  Assert.AreEqual('FCaption: string;', mItem.Detail);
  // "Ca" wird zu "FCaption"; das Feld kommt hinter FName.
  Assert.IsTrue(mItem.HasTextEdit);
  Assert.AreEqual('FCaption', mItem.TextEdit.NewText);
  Assert.AreEqual(Integer(7), mItem.TextEdit.Range.StartPos.Line);
  Assert.AreEqual(Integer(34), mItem.TextEdit.Range.StartPos.Character);
  Assert.AreEqual(Integer(36), mItem.TextEdit.Range.EndPos.Character);
  Assert.AreEqual(Integer(1), Integer(Length(mItem.AdditionalEdits)));
  Assert.AreEqual(#10'    FCaption: string;', mItem.AdditionalEdits[0].NewText);
  // Der Getter hat Deklaration und Rumpf.
  mInserted := InsertedBy(mItems.Items[1]);
  Assert.Contains(mInserted, 'function GetCaption: string;');
  Assert.Contains(mInserted, 'function TFoo.GetCaption: string;');
  // Nach "write " ohne Feld FTitel: „Feld FTitel anlegen“, „SetTitel anlegen“ legt das Feld mit an; danach das
  // vorhandene Feld FName.
  Assert.IsTrue(ItemsAt(cUnitAnlegen, 'FName write ', TCompletionSettings.Default, mItems));
  Assert.AreEqual('Feld FTitel anlegen SetTitel anlegen FName', NamesOf(mItems));
  Assert.AreEqual('procedure SetTitel(const Value: string); + FTitel: string;', mItems.Items[1].Detail);
end;

procedure TEditingPropertyCompletionTests.AccessorCreationFollowsSettings;
var
  mSettings: TCompletionSettings;
  mItems: TCompletionItems;
begin
  mSettings := TCompletionSettings.Default;
  mSettings.AccessorSection := TCompletionAccessorSection.Protected;
  Assert.IsTrue(ItemsAt(cUnitAnlegen, 'read Ca', mSettings, mItems));
  // Kein protected vor der Eigenschaft: eigener Abschnitt, danach weiter public.
  Assert.Contains(InsertedBy(mItems.Items[1]), '  protected'#10'    function GetCaption: string;'#10'  public'#10);
  // Abgeschaltet: nur vorhandene Mitglieder.
  mSettings.CreateAccessors := False;
  Assert.IsTrue(ItemsAt(cUnitAnlegen, 'read Ca', mSettings, mItems));
  Assert.AreEqual('', NamesOf(mItems));
end;

procedure TEditingPropertyCompletionTests.SourceAnswersOnlyInPropertyLine;
var
  mTree: TSyntaxTree;
  mRequest: TCompletionRequest;
  mAnswer: TCompletionAnswer;
begin
  mTree := TSyntaxTreeCache.Parse(cUnitAnlegen);
  mRequest := nil;
  mAnswer := nil;
  try
    mRequest := TCompletionRequest.Create(cUnitAnlegen, cHauptFile, TTestSource.PositionAfter(cUnitAnlegen,
      'read Ca'));
    mRequest.Tree := mTree;
    mRequest.Resolver := FResolver;
    mRequest.Settings := TCompletionSettings.Default;
    mAnswer := TCompletionAnswer.Create;
    Assert.AreEqual(Ord(TCompletionOutcome.Answered), Ord(TEditingPropertyCompletion.Source()(mRequest, mAnswer)));
    Assert.AreEqual('Feld FCaption anlegen GetCaption anlegen', NamesOf(mAnswer.Exclusive));
    mRequest.Free;
    mRequest := TCompletionRequest.Create(cUnitAnlegen, cHauptFile, TTestSource.PositionAfter(cUnitAnlegen,
      '    FName'));
    mRequest.Tree := mTree;
    mRequest.Resolver := FResolver;
    mAnswer.Exclusive := Default(TCompletionItems);
    Assert.AreEqual(Ord(TCompletionOutcome.Next), Ord(TEditingPropertyCompletion.Source()(mRequest, mAnswer)));
    Assert.AreEqual(Integer(0), Integer(Length(mAnswer.Exclusive.Items)));
  finally
    mAnswer.Free;
    mRequest.Free;
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingPropertyCompletionTests);

end.
