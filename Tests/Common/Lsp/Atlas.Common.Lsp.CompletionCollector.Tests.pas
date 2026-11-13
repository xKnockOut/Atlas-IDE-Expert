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
  Item: TCompletionItem;
begin
  Result := '';
  for Item in AItems do
  begin
    Result := Result + ' ' + Item.Name;
  end;
  Result := Result.Trim;
end;

procedure TCompletionCollectorTests.AddKeepsNoStateBetweenCalls;
var
  Request: TCompletionRequest;
  Collector: TCompletionCollector;
  Import: TResolvedSymbol;
  Items: TArray<TCompletionItem>;
  Incomplete: Boolean;
begin
  Request := TCompletionRequest.Create('', 'C:\P\Haupt.pas', TTextPosition.Create(0, 0));
  Collector := TCompletionCollector.Create(Request, ScopeContext(''), '', nil);
  try
    Import := Default(TResolvedSymbol);
    Import.Name := 'ShowMessage';
    Import.MaxArgs := 1;
    Import.FileName := 'C:\Lib\Dialogs.pas';
    Import.SelectionRange.StartPos := TTextPosition.Create(7, 2);
    Assert.IsTrue(Collector.Add('ShowMessage', 'Dialogs (uses ergänzen)', cKindFunction, cPenaltyLibraryImport, Import,
      [TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(2, 0), TTextPosition.Create(2, 0)), 'Dialogs, ')]));
    Assert.IsTrue(Collector.Add('begin', '', cKindKeyword, cPenaltyKeyword, Default(TResolvedSymbol)));
    Items := Collector.Finish(Incomplete);
    Assert.AreEqual('begin ShowMessage', Joined(Items));
    // Das Schlüsselwort erbt nichts vom Import davor.
    Assert.AreEqual(0, Integer(Length(Items[0].AdditionalEdits)));
    Assert.AreEqual('', Items[0].SourceFile);
    Assert.IsFalse(Items[0].HasParameters);
    Assert.AreEqual(0, Items[0].Scope);
    Assert.AreEqual(1, Integer(Length(Items[1].AdditionalEdits)));
    Assert.AreEqual('C:\Lib\Dialogs.pas', Items[1].SourceFile);
    Assert.AreEqual(7, Items[1].SourcePosition.Line);
    Assert.IsTrue(Items[1].HasParameters);
  finally
    Collector.Free;
    Request.Free;
  end;
end;

procedure TCompletionCollectorTests.PenaltiesOrderGroups;
var
  Request: TCompletionRequest;
  Collector: TCompletionCollector;
  Incomplete: Boolean;
begin
  // Nur nach dem Anfang: alle Namen haben dieselbe Punktzahl, es entscheiden die Strafen.
  Request := TCompletionRequest.Create('', 'C:\P\Haupt.pas', TTextPosition.Create(0, 0));
  Request.Matching := TCompletionMatching.Prefix;
  Collector := TCompletionCollector.Create(Request, ScopeContext('We'), '', nil);
  try
    Collector.Add('WertU', '', cKindVariable, cPenaltyUnavailable, Default(TResolvedSymbol));
    Collector.Add('WertB', '', cKindVariable, cPenaltyLibraryImport, Default(TResolvedSymbol));
    Collector.Add('WertP', '', cKindVariable, cPenaltyProjectImport, Default(TResolvedSymbol));
    Collector.Add('WertK', '', cKindKeyword, cPenaltyKeyword, Default(TResolvedSymbol));
    Collector.Add('WertE', '', cKindVariable, Default(TResolvedSymbol));
    Assert.AreEqual('WertE WertK WertP WertB WertU', Joined(Collector.Finish(Incomplete)));
  finally
    Collector.Free;
    Request.Free;
  end;
end;

procedure TCompletionCollectorTests.AddRejectsWhatDoesNotMatch;
var
  Request: TCompletionRequest;
  Collector: TCompletionCollector;
  Incomplete: Boolean;
  Items: TArray<TCompletionItem>;
begin
  Request := TCompletionRequest.Create('', '', TTextPosition.Create(0, 0));
  Collector := TCompletionCollector.Create(Request, ScopeContext('zae'), '', nil);
  try
    Assert.IsFalse(Collector.Add('Rechne', '', cKindFunction, Default(TResolvedSymbol)));
    // Unscharf: Teilwort trifft, filterText ist das Getippte.
    Assert.IsTrue(Collector.Add('Zaehler', '', cKindField, Default(TResolvedSymbol)));
    Items := Collector.Finish(Incomplete);
    Assert.AreEqual('Zaehler', Joined(Items));
    Assert.AreEqual('', Items[0].FilterText, 'Anfang passt ohne Rücksicht auf Groß/klein');
  finally
    Collector.Free;
    Request.Free;
  end;
end;

procedure TCompletionCollectorTests.SendStageHandsOverAndFinishKeepsRest;
var
  Request: TCompletionRequest;
  Collector: TCompletionCollector;
  Incomplete: Boolean;
  Sent: TArray<TCompletionItem>;
begin
  Sent := nil;
  Request := TCompletionRequest.Create('', '', TTextPosition.Create(0, 0));
  Collector := TCompletionCollector.Create(Request, ScopeContext(''), '',
    procedure(const AItems: TArray<TCompletionItem>)
    begin
      Sent := Sent + AItems;
    end);
  try
    Collector.Add('Lokal', '', cKindVariable, Default(TResolvedSymbol));
    Collector.Add('Feld', '', cKindField, Default(TResolvedSymbol));
    Collector.SendStage;
    Assert.AreEqual('Lokal Feld', Joined(Sent));
    // Leere Stufe: nichts gesendet.
    Collector.SendStage;
    Assert.AreEqual(2, Integer(Length(Sent)));
    Collector.Add('Global', '', cKindVariable, Default(TResolvedSymbol));
    Assert.AreEqual('Global', Joined(Collector.Finish(Incomplete)));
  finally
    Collector.Free;
    Request.Free;
  end;
end;

procedure TCompletionCollectorTests.FinishMarksShortScopePrefixIncomplete;
var
  Request: TCompletionRequest;
  Collector: TCompletionCollector;
  Context: TCompletionContext;
  Incomplete: Boolean;
begin
  Request := TCompletionRequest.Create('', '', TTextPosition.Create(0, 0));
  try
    // Ein Zeichen im Gültigkeitsbereich: Importe fehlen noch.
    Collector := TCompletionCollector.Create(Request, ScopeContext('W'), '', nil);
    try
      Collector.Finish(Incomplete);
      Assert.IsTrue(Incomplete);
    finally
      Collector.Free;
    end;
    Collector := TCompletionCollector.Create(Request, ScopeContext('We'), '', nil);
    try
      Collector.Finish(Incomplete);
      Assert.IsFalse(Incomplete);
    finally
      Collector.Free;
    end;
    // Nach einem Punkt kommen keine Importe dazu.
    Context := ScopeContext('');
    Context.Kind := TCompletionContextKind.Member;
    Collector := TCompletionCollector.Create(Request, Context, '', nil);
    try
      Collector.Finish(Incomplete);
      Assert.IsFalse(Incomplete);
    finally
      Collector.Free;
    end;
  finally
    Request.Free;
  end;
end;

procedure TCompletionCollectorTests.ScopeOnlyInScopeContext;
var
  Request: TCompletionRequest;
  Collector: TCompletionCollector;
  Context: TCompletionContext;
  Symbol: TResolvedSymbol;
  Items: TArray<TCompletionItem>;
  Incomplete: Boolean;
begin
  Symbol := Default(TResolvedSymbol);
  Symbol.Name := 'Rechne';
  Symbol.UnitName := 'Werkzeug';
  Request := TCompletionRequest.Create('', '', TTextPosition.Create(0, 0));
  try
    Collector := TCompletionCollector.Create(Request, ScopeContext(''), '', nil);
    try
      Collector.Add('Rechne', 'Werkzeug', cKindFunction, Symbol);
      Items := Collector.Finish(Incomplete);
      Assert.AreEqual(5, Items[0].Scope);
      Assert.AreEqual('Werkzeug', Items[0].UnitName);
    finally
      Collector.Free;
    end;
    Context := ScopeContext('');
    Context.Kind := TCompletionContextKind.Member;
    Collector := TCompletionCollector.Create(Request, Context, '', nil);
    try
      Collector.Add('Rechne', 'Werkzeug', cKindFunction, Symbol);
      Items := Collector.Finish(Incomplete);
      Assert.AreEqual(0, Items[0].Scope);
      Assert.AreEqual('', Items[0].UnitName);
    finally
      Collector.Free;
    end;
  finally
    Request.Free;
  end;
end;

procedure TCompletionCollectorTests.ConversionStandsBeforeOriginal;
const
  FileName = 'C:\P\Haupt.pas';
  Head =
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
  Tail = #10'end;'#10'end.'#10;

  function Items(const ALine: string; AStyle: TCompletionTypeConversion): TArray<TCompletionItem>;
  var
    Index: ISymbolIndex;
    Text: string;
    Tree: TSyntaxTree;
    Resolver: TNameResolver;
    Request: TCompletionRequest;
    Settings: TCompletionSettings;
    Postfix: TPostfixOptions;
  begin
    Text := Head + ALine + Tail;
    Index := TSymbolIndex.Create;
    Index.AddUnit(TIndexExtractor.ExtractText(Text, FileName, nil));
    Tree := TPascalParser.Parse(Text);
    Resolver := TNameResolver.Create(Index);
    Request := TCompletionRequest.Create(Text, FileName, TTextPosition.Create(22, 2 + Length(ALine)));
    try
      Request.Tree := Tree;
      Request.Resolver := Resolver;
      Request.Index := Index;
      Request.Matching := TCompletionMatching.Prefix;
      Settings := TCompletionSettings.Default;
      Settings.TypeConversion := AStyle;
      Request.Settings := Settings;
      Postfix := TPostfixOptions.Default;
      Postfix.Enabled := False;
      Result := TCompletionLists.Collect(Request, Postfix, nil).Items;
    finally
      Request.Free;
      Resolver.Free;
      Tree.Free;
    end;
  end;

var
  List: TArray<TCompletionItem>;
begin
  // Aus #490: "lblCount.Caption := Lines.Cou" zeigt Count.ToString mit "→ string" vor Count.
  List := Items('lblCount.Caption := Lines.Cou', TCompletionTypeConversion.Helper);
  Assert.AreEqual('Count.ToString Count', Joined(List));
  Assert.AreEqual('TCaption', List[0].Conversion);
  Assert.AreEqual('Count', List[0].ConvertFrom);
  Assert.AreEqual('Count', List[0].FilterText);
  Assert.IsTrue(List[0].HasTextEdit);
  Assert.AreEqual('Lines.Count.ToString', List[0].TextEdit.NewText);
  Assert.AreEqual(22, List[0].TextEdit.Range.StartPos.Line);
  Assert.AreEqual(22, List[0].TextEdit.Range.StartPos.Character);
  Assert.AreEqual(31, List[0].TextEdit.Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(List[0].AdditionalEdits)), 'System.SysUtils ins uses');
  Assert.AreEqual('', List[1].Conversion);
  Assert.IsFalse(List[1].HasTextEdit);
  // Funktionsstil setzt die ganze Kette ein.
  List := Items('lblCount.Caption := Lines.Cou', TCompletionTypeConversion.Function_);
  Assert.AreEqual('IntToStr(Count) Count', Joined(List));
  Assert.AreEqual('IntToStr(Lines.Count)', List[0].TextEdit.NewText);
  // Aufzählung nach string mit System.TypInfo.
  List := Items('lblCount.Caption := Lines.Far', TCompletionTypeConversion.Helper);
  Assert.AreEqual('GetEnumName(TypeInfo(TFarbe), Ord(Lines.Farbe))', List[0].TextEdit.NewText);
  // Gleitkomma nach Ganzzahl: kein Eintrag, nur der Hinweis am Original.
  List := Items('I := Lines.Pre', TCompletionTypeConversion.Helper);
  Assert.AreEqual('Preis', Joined(List));
  Assert.AreEqual('Double', List[0].Lossy);
  // Aus: nichts dazu.
  List := Items('lblCount.Caption := Lines.Cou', TCompletionTypeConversion.Off);
  Assert.AreEqual('Count', Joined(List));
  Assert.AreEqual('', List[0].Lossy);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionCollectorTests);

end.
