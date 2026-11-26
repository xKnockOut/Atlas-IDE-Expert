unit Atlas.Common.Editing.Completion.Declare.Tests;

// Tests für das Deklarieren unbekannter Namen in der Vervollständigung (#471).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TEditingDeclareCompletionTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Lokale Variable, Inline-Variable, Feld und Konstante mit Typ aus Zuweisung bzw. Parameter;
    /// bekannte Namen nicht.</summary>
    [Test]
    procedure OffersDeclarationsForUnknownNames;
    /// <summary>Die Quelle hängt die Einträge an den Schluss und macht die Antwort unvollständig.</summary>
    [Test]
    procedure SourceAppendsToTailIncomplete;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Completion.Contract,
  Atlas.Common.Completion.Request,
  Atlas.Common.Completion.Answer,
  Atlas.Common.Editing.Completion.Declare,
  Atlas.Tests.SourceText;

const
  cUnknownText =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TLines = class'#13#10 +
    '    Count: Integer;'#13#10 +
    '  end;'#13#10 +
    '  TRechner = class'#13#10 +
    '  private'#13#10 +
    '    FLines: TLines;'#13#10 +
    '  public'#13#10 +
    '    procedure Summe(Extra: TLines);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure Zeige(N: Integer);'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'procedure TRechner.Summe(Extra: TLines);'#13#10 +
    'begin'#13#10 +
    '  TotalCount := FLines.Count + Extra.Count;'#13#10 +
    '  Zeige(Anzahl);'#13#10 +
    '  FLines := nil;'#13#10 +
    'end;'#13#10 +
    'end.';

/// <summary>Anfrage an APosition in cUnknownText; der Aufrufer gibt sie frei.</summary>
function RequestAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AIndex: ISymbolIndex;
  const APosition: TTextPosition; AInlineVar: Boolean): TCompletionRequest;
begin
  Result := TCompletionRequest.Create(cUnknownText, 'C:\P\Haupt.pas', APosition);
  Result.Tree := ATree;
  Result.Resolver := AResolver;
  Result.Index := AIndex;
  Result.InlineVar := AInlineVar;
end;

/// <summary>TEditingDeclareCompletion.Items an APosition.</summary>
function DeclareAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AIndex: ISymbolIndex;
  const APosition: TTextPosition; AInlineVar: Boolean; const AKnown: TArray<TCompletionItem>;
  out AItems: TArray<TCompletionItem>): Boolean;
var
  mRequest: TCompletionRequest;
begin
  mRequest := RequestAt(AResolver, ATree, AIndex, APosition, AInlineVar);
  try
    Result := TEditingDeclareCompletion.Items(mRequest, AKnown, AItems);
  finally
    mRequest.Free;
  end;
end;

{ TEditingDeclareCompletionTests }

procedure TEditingDeclareCompletionTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
end;

procedure TEditingDeclareCompletionTests.TearDown;
begin
  FIndex := nil;
end;

procedure TEditingDeclareCompletionTests.OffersDeclarationsForUnknownNames;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItems: TArray<TCompletionItem>;
  mKnown: TArray<TCompletionItem>;

  function Named(const AName: string): TCompletionItem;
  var
    mItem: TCompletionItem;
  begin
    for mItem in mItems do
    begin
      if mItem.Name = AName then
      begin
        Exit(mItem);
      end;
    end;
    Result := Default(TCompletionItem);
    Assert.Fail(Format('Eintrag "%s" fehlt', [AName]));
  end;

var
  mItem: TCompletionItem;
begin
  mTree := TSyntaxTreeCache.Parse(cUnknownText);
  mResolver := TNameResolver.Create(FIndex);
  try
    // Ziel einer Zuweisung: Typ aus der rechten Seite.
    Assert.IsTrue(DeclareAt(mResolver, mTree, FIndex,
      TTestSource.PositionAfter(cUnknownText, '  TotalCount'), True, nil, mItems));
    mItem := Named('Lokale Variable anlegen');
    Assert.AreEqual('TotalCount: Integer', mItem.Detail);
    Assert.AreEqual('declare', mItem.Action);
    Assert.AreEqual('TotalCount', mItem.Unknown);
    // Die Verwendung bleibt, der Cursor auch; var vor begin.
    Assert.AreEqual('TotalCount$0', mItem.TextEdit.NewText);
    Assert.AreEqual(1, Integer(Length(mItem.AdditionalEdits)));
    Assert.AreEqual('var'#13#10'  TotalCount: Integer;'#13#10, mItem.AdditionalEdits[0].NewText);
    Assert.AreEqual(17, mItem.AdditionalEdits[0].Range.StartPos.Line);
    Assert.AreEqual('var TotalCount$0', Named('Inline-Variable anlegen').TextEdit.NewText);
    // Feld mit F-Konvention: im private-Abschnitt, die Verwendung heißt danach FTotalCount.
    mItem := Named('Feld FTotalCount anlegen');
    Assert.AreEqual('FTotalCount$0', mItem.TextEdit.NewText);
    Assert.AreEqual(7, mItem.AdditionalEdits[0].Range.StartPos.Line);
    Assert.AreEqual(#13#10'    FTotalCount: Integer;', mItem.AdditionalEdits[0].NewText);
    // Keine Konstante als Ziel einer Zuweisung.
    for mItem in mItems do
    begin
      Assert.AreNotEqual('Konstante anlegen', mItem.Name);
    end;
    // Als Argument: Typ des Parameters, auch als Konstante in der implementation.
    Assert.IsTrue(DeclareAt(mResolver, mTree, FIndex,
      TTestSource.PositionAfter(cUnknownText, 'Zeige(Anzahl'), False, nil, mItems));
    Assert.AreEqual('Anzahl: Integer', Named('Lokale Variable anlegen').Detail);
    mItem := Named('Konstante anlegen');
    Assert.AreEqual('Anzahl = 0;', mItem.Detail);
    Assert.AreEqual(12, mItem.AdditionalEdits[0].Range.StartPos.Line);
    // Bekannte Namen und genaue Treffer: nichts.
    Assert.IsFalse(DeclareAt(mResolver, mTree, FIndex,
      TTestSource.PositionAfter(cUnknownText, 'Zeige(Anzahl);'#13#10'  FLines'), True, nil, mItems));
    // Eigene Variable für die bekannten Einträge: Ein out-Parameter leert sein Ziel vor dem Aufruf.
    SetLength(mKnown, 1);
    mKnown[0] := Default(TCompletionItem);
    mKnown[0].Name := 'Anzahl';
    Assert.IsFalse(DeclareAt(mResolver, mTree, FIndex,
      TTestSource.PositionAfter(cUnknownText, 'Zeige(Anzahl'), True, mKnown, mItems));
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure TEditingDeclareCompletionTests.SourceAppendsToTailIncomplete;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mRequest: TCompletionRequest;
  mAnswer: TCompletionAnswer;
  mSource: TCompletionSource;
  mTail: TCompletionItem;
begin
  mTree := TSyntaxTreeCache.Parse(cUnknownText);
  mResolver := TNameResolver.Create(FIndex);
  mRequest := nil;
  mAnswer := nil;
  try
    mRequest := RequestAt(mResolver, mTree, FIndex, TTestSource.PositionAfter(cUnknownText, '  TotalCount'), False);
    mAnswer := TCompletionAnswer.Create;
    mTail := Default(TCompletionItem);
    mTail.Name := 'Vorlage';
    mAnswer.Tail := [mTail];
    mSource := TEditingDeclareCompletion.Source();
    Assert.AreEqual(Ord(TCompletionOutcome.Next), Ord(mSource(mRequest, mAnswer)));
    Assert.IsTrue(mAnswer.Incomplete);
    Assert.IsTrue(Length(mAnswer.Tail) > 1);
    Assert.AreEqual('Vorlage', mAnswer.Tail[0].Name);
    Assert.AreEqual('declare', mAnswer.Tail[1].Action);
  finally
    mAnswer.Free;
    mRequest.Free;
    mResolver.Free;
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingDeclareCompletionTests);

end.
