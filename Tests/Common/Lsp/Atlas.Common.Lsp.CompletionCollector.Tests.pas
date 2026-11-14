unit Atlas.Common.Lsp.CompletionCollector.Tests;

// Sammler der Vervollständigung: kein geteilter Zustand zwischen
// Einträgen, Strafpunkte legen die Gruppen fest, Staffelung und Unvollständigkeit; Typkonvertierung im Sammler (#490).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.CompletionRequest;

type
  [TestFixture]
  TCompletionCollectorTests = class
  private
    function ScopeContext(const APrefix: string): TCompletionContext;
  public
    [Test]
    procedure AddKeepsNoStateBetweenCalls;
    [Test]
    procedure PenaltiesOrderGroups;
    [Test]
    procedure AddRejectsWhatDoesNotMatch;
    [Test]
    procedure SendStageHandsOverAndFinishKeepsRest;
    [Test]
    procedure FinishMarksShortScopePrefixIncomplete;
    [Test]
    procedure ScopeOnlyInScopeContext;
    [Test]
    procedure ConversionStandsBeforeOriginal;
  end;

implementation

uses
  Atlas.Common.Lsp.Completion.Lists,
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.CompletionCollector;

function TCompletionCollectorTests.ScopeContext(const APrefix: string): TCompletionContext;
begin
  Result := Default(TCompletionContext);
  Result.Kind := TCompletionContextKind.Scope;
  Result.Prefix := APrefix;
end;

function Joined(const AItems: TArray<TCompletionItem>): string;
var
  mItem: TCompletionItem;
begin
  Result := '';
  for mItem in AItems do
  begin
    Result := Result + ' ' + mItem.Name;
  end;
  Result := Result.Trim;
end;

procedure TCompletionCollectorTests.AddKeepsNoStateBetweenCalls;
var
  mRequest: TCompletionRequest;
  mCollector: TCompletionCollector;
  mImport: TResolvedSymbol;
  mItems: TArray<TCompletionItem>;
  mIncomplete: Boolean;
begin
  mRequest := TCompletionRequest.Create('', 'C:\P\Haupt.pas', TTextPosition.Create(0, 0));
  mCollector := TCompletionCollector.Create(mRequest, ScopeContext(''), '', nil);
  try
    mImport := Default(TResolvedSymbol);
    mImport.Name := 'ShowMessage';
    mImport.MaxArgs := 1;
    mImport.FileName := 'C:\Lib\Dialogs.pas';
    mImport.SelectionRange.StartPos := TTextPosition.Create(7, 2);
    Assert.IsTrue(mCollector.Add('ShowMessage', 'Dialogs (uses ergänzen)', cKindFunction, cPenaltyLibraryImport, mImport,
      [TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(2, 0), TTextPosition.Create(2, 0)), 'Dialogs, ')]));
    Assert.IsTrue(mCollector.Add('begin', '', cKindKeyword, cPenaltyKeyword, Default(TResolvedSymbol)));
    mItems := mCollector.Finish(mIncomplete);
    Assert.AreEqual('begin ShowMessage', Joined(mItems));
    // Das Schlüsselwort erbt nichts vom Import davor.
    Assert.AreEqual(0, Integer(Length(mItems[0].AdditionalEdits)));
    Assert.AreEqual('', mItems[0].SourceFile);
    Assert.IsFalse(mItems[0].HasParameters);
    Assert.AreEqual(0, mItems[0].Scope);
    Assert.AreEqual(1, Integer(Length(mItems[1].AdditionalEdits)));
    Assert.AreEqual('C:\Lib\Dialogs.pas', mItems[1].SourceFile);
    Assert.AreEqual(7, mItems[1].SourcePosition.Line);
    Assert.IsTrue(mItems[1].HasParameters);
  finally
    mCollector.Free;
    mRequest.Free;
  end;
end;

procedure TCompletionCollectorTests.PenaltiesOrderGroups;
var
  mRequest: TCompletionRequest;
  mCollector: TCompletionCollector;
  mIncomplete: Boolean;
begin
  // Nur nach dem Anfang: alle Namen haben dieselbe Punktzahl, es entscheiden die Strafen.
  mRequest := TCompletionRequest.Create('', 'C:\P\Haupt.pas', TTextPosition.Create(0, 0));
  mRequest.Matching := TCompletionMatching.Prefix;
  mCollector := TCompletionCollector.Create(mRequest, ScopeContext('We'), '', nil);
  try
    mCollector.Add('WertU', '', cKindVariable, cPenaltyUnavailable, Default(TResolvedSymbol));
    mCollector.Add('WertB', '', cKindVariable, cPenaltyLibraryImport, Default(TResolvedSymbol));
    mCollector.Add('WertP', '', cKindVariable, cPenaltyProjectImport, Default(TResolvedSymbol));
    mCollector.Add('WertK', '', cKindKeyword, cPenaltyKeyword, Default(TResolvedSymbol));
    mCollector.Add('WertE', '', cKindVariable, Default(TResolvedSymbol));
    Assert.AreEqual('WertE WertK WertP WertB WertU', Joined(mCollector.Finish(mIncomplete)));
  finally
    mCollector.Free;
    mRequest.Free;
  end;
end;

procedure TCompletionCollectorTests.AddRejectsWhatDoesNotMatch;
var
  mRequest: TCompletionRequest;
  mCollector: TCompletionCollector;
  mIncomplete: Boolean;
  mItems: TArray<TCompletionItem>;
begin
  mRequest := TCompletionRequest.Create('', '', TTextPosition.Create(0, 0));
  mCollector := TCompletionCollector.Create(mRequest, ScopeContext('zae'), '', nil);
  try
    Assert.IsFalse(mCollector.Add('Rechne', '', cKindFunction, Default(TResolvedSymbol)));
    // Unscharf: Teilwort trifft, filterText ist das Getippte.
    Assert.IsTrue(mCollector.Add('Zaehler', '', cKindField, Default(TResolvedSymbol)));
    mItems := mCollector.Finish(mIncomplete);
    Assert.AreEqual('Zaehler', Joined(mItems));
    Assert.AreEqual('', mItems[0].FilterText, 'Anfang passt ohne Rücksicht auf Groß/klein');
  finally
    mCollector.Free;
    mRequest.Free;
  end;
end;

procedure TCompletionCollectorTests.SendStageHandsOverAndFinishKeepsRest;
var
  mRequest: TCompletionRequest;
  mCollector: TCompletionCollector;
  mIncomplete: Boolean;
  mSent: TArray<TCompletionItem>;
begin
  mSent := nil;
  mRequest := TCompletionRequest.Create('', '', TTextPosition.Create(0, 0));
  mCollector := TCompletionCollector.Create(mRequest, ScopeContext(''), '',
    procedure(const AItems: TArray<TCompletionItem>)
    begin
      mSent := mSent + AItems;
    end);
  try
    mCollector.Add('Lokal', '', cKindVariable, Default(TResolvedSymbol));
    mCollector.Add('Feld', '', cKindField, Default(TResolvedSymbol));
    mCollector.SendStage;
    Assert.AreEqual('Lokal Feld', Joined(mSent));
    // Leere Stufe: nichts gesendet.
    mCollector.SendStage;
    Assert.AreEqual(2, Integer(Length(mSent)));
    mCollector.Add('Global', '', cKindVariable, Default(TResolvedSymbol));
    Assert.AreEqual('Global', Joined(mCollector.Finish(mIncomplete)));
  finally
    mCollector.Free;
    mRequest.Free;
  end;
end;

procedure TCompletionCollectorTests.FinishMarksShortScopePrefixIncomplete;
var
  mRequest: TCompletionRequest;
  mCollector: TCompletionCollector;
  mContext: TCompletionContext;
  mIncomplete: Boolean;
begin
  mRequest := TCompletionRequest.Create('', '', TTextPosition.Create(0, 0));
  try
    // Ein Zeichen im Gültigkeitsbereich: Importe fehlen noch.
    mCollector := TCompletionCollector.Create(mRequest, ScopeContext('W'), '', nil);
    try
      mCollector.Finish(mIncomplete);
      Assert.IsTrue(mIncomplete);
    finally
      mCollector.Free;
    end;
    mCollector := TCompletionCollector.Create(mRequest, ScopeContext('We'), '', nil);
    try
      mCollector.Finish(mIncomplete);
      Assert.IsFalse(mIncomplete);
    finally
      mCollector.Free;
    end;
    // Nach einem Punkt kommen keine Importe dazu.
    mContext := ScopeContext('');
    mContext.Kind := TCompletionContextKind.Member;
    mCollector := TCompletionCollector.Create(mRequest, mContext, '', nil);
    try
      mCollector.Finish(mIncomplete);
      Assert.IsFalse(mIncomplete);
    finally
      mCollector.Free;
    end;
  finally
    mRequest.Free;
  end;
end;

procedure TCompletionCollectorTests.ScopeOnlyInScopeContext;
var
  mRequest: TCompletionRequest;
  mCollector: TCompletionCollector;
  mContext: TCompletionContext;
  mSymbol: TResolvedSymbol;
  mItems: TArray<TCompletionItem>;
  mIncomplete: Boolean;
begin
  mSymbol := Default(TResolvedSymbol);
  mSymbol.Name := 'Rechne';
  mSymbol.UnitName := 'Werkzeug';
  mRequest := TCompletionRequest.Create('', '', TTextPosition.Create(0, 0));
  try
    mCollector := TCompletionCollector.Create(mRequest, ScopeContext(''), '', nil);
    try
      mCollector.Add('Rechne', 'Werkzeug', cKindFunction, mSymbol);
      mItems := mCollector.Finish(mIncomplete);
      Assert.AreEqual(5, mItems[0].Scope);
      Assert.AreEqual('Werkzeug', mItems[0].UnitName);
    finally
      mCollector.Free;
    end;
    mContext := ScopeContext('');
    mContext.Kind := TCompletionContextKind.Member;
    mCollector := TCompletionCollector.Create(mRequest, mContext, '', nil);
    try
      mCollector.Add('Rechne', 'Werkzeug', cKindFunction, mSymbol);
      mItems := mCollector.Finish(mIncomplete);
      Assert.AreEqual(0, mItems[0].Scope);
      Assert.AreEqual('', mItems[0].UnitName);
    finally
      mCollector.Free;
    end;
  finally
    mRequest.Free;
  end;
end;

procedure TCompletionCollectorTests.ConversionStandsBeforeOriginal;
const
  cFileName = 'C:\P\Haupt.pas';
  cHead =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses'#10 +
    '  System.Classes;'#10 +
    'type'#10 +
    '  TFarbe = (Rot, Gruen);'#10 +
    '  TListe = class'#10 +
    '    Count: Integer;'#10 +
    '    Preis: Double;'#10 +
    '    Farbe: TFarbe;'#10 +
    '  end;'#10 +
    '  TCaption = type string;'#10 +
    '  TLabel = class'#10 +
    '    Caption: TCaption;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure Run;'#10 +
    'var'#10 +
    '  Lines: TListe;'#10 +
    '  lblCount: TLabel;'#10 +
    '  I: Integer;'#10 +
    'begin'#10 +
    '  ';
  cTail = #10'end;'#10'end.'#10;

  function Items(const ALine: string; AStyle: TCompletionTypeConversion): TArray<TCompletionItem>;
  var
    mIndex: ISymbolIndex;
    mText: string;
    mTree: TSyntaxTree;
    mResolver: TNameResolver;
    mRequest: TCompletionRequest;
    mSettings: TCompletionSettings;
    mPostfix: TPostfixOptions;
  begin
    mText := cHead + ALine + cTail;
    mIndex := TSymbolIndex.Create;
    mIndex.AddUnit(TIndexExtractor.ExtractText(mText, cFileName, nil));
    mTree := TPascalParser.Parse(mText);
    mResolver := TNameResolver.Create(mIndex);
    mRequest := TCompletionRequest.Create(mText, cFileName, TTextPosition.Create(22, 2 + Length(ALine)));
    try
      mRequest.Tree := mTree;
      mRequest.Resolver := mResolver;
      mRequest.Index := mIndex;
      mRequest.Matching := TCompletionMatching.Prefix;
      mSettings := TCompletionSettings.Default;
      mSettings.TypeConversion := AStyle;
      mRequest.Settings := mSettings;
      mPostfix := TPostfixOptions.Default;
      mPostfix.Enabled := False;
      Result := TCompletionLists.Collect(mRequest, mPostfix, nil).Items;
    finally
      mRequest.Free;
      mResolver.Free;
      mTree.Free;
    end;
  end;

var
  mList: TArray<TCompletionItem>;
begin
  // Aus #490: "lblCount.Caption := Lines.Cou" zeigt Count.ToString mit "→ string" vor Count.
  mList := Items('lblCount.Caption := Lines.Cou', TCompletionTypeConversion.Helper);
  Assert.AreEqual('Count.ToString Count', Joined(mList));
  Assert.AreEqual('TCaption', mList[0].Conversion);
  Assert.AreEqual('Count', mList[0].ConvertFrom);
  Assert.AreEqual('Count', mList[0].FilterText);
  Assert.IsTrue(mList[0].HasTextEdit);
  Assert.AreEqual('Lines.Count.ToString', mList[0].TextEdit.NewText);
  Assert.AreEqual(22, mList[0].TextEdit.Range.StartPos.Line);
  Assert.AreEqual(22, mList[0].TextEdit.Range.StartPos.Character);
  Assert.AreEqual(31, mList[0].TextEdit.Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mList[0].AdditionalEdits)), 'System.SysUtils ins uses');
  Assert.AreEqual('', mList[1].Conversion);
  Assert.IsFalse(mList[1].HasTextEdit);
  // Funktionsstil setzt die ganze Kette ein.
  mList := Items('lblCount.Caption := Lines.Cou', TCompletionTypeConversion.Function_);
  Assert.AreEqual('IntToStr(Count) Count', Joined(mList));
  Assert.AreEqual('IntToStr(Lines.Count)', mList[0].TextEdit.NewText);
  // Aufzählung nach string mit System.TypInfo.
  mList := Items('lblCount.Caption := Lines.Far', TCompletionTypeConversion.Helper);
  Assert.AreEqual('GetEnumName(TypeInfo(TFarbe), Ord(Lines.Farbe))', mList[0].TextEdit.NewText);
  // Gleitkomma nach Ganzzahl: kein Eintrag, nur der Hinweis am Original.
  mList := Items('I := Lines.Pre', TCompletionTypeConversion.Helper);
  Assert.AreEqual('Preis', Joined(mList));
  Assert.AreEqual('Double', mList[0].Lossy);
  // Aus: nichts dazu.
  mList := Items('lblCount.Caption := Lines.Cou', TCompletionTypeConversion.Off);
  Assert.AreEqual('Count', Joined(mList));
  Assert.AreEqual('', mList[0].Lossy);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionCollectorTests);

end.
