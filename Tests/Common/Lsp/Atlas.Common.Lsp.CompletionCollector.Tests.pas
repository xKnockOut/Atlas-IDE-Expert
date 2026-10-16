unit Atlas.Common.Lsp.CompletionCollector.Tests;

// Sammler der Vervollständigung (Code-Review S-01, Block H Schritt 3): kein geteilter Zustand zwischen
// Einträgen, Strafpunkte legen die Gruppen fest, Staffelung und Unvollständigkeit.

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
    procedure TypeFitsFamiliesAndDescent;
    [Test]
    procedure ScopeOnlyInScopeContext;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Semantics.NameResolver,
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
    Result := Result + ' ' + Item.Name;
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
    Assert.IsTrue(Collector.Add('ShowMessage', 'Dialogs (uses ergänzen)', KindFunction, PenaltyLibraryImport, Import,
      [TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(2, 0), TTextPosition.Create(2, 0)), 'Dialogs, ')]));
    Assert.IsTrue(Collector.Add('begin', '', KindKeyword, PenaltyKeyword, Default(TResolvedSymbol)));
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
    Collector.Add('WertU', '', KindVariable, PenaltyUnavailable, Default(TResolvedSymbol));
    Collector.Add('WertB', '', KindVariable, PenaltyLibraryImport, Default(TResolvedSymbol));
    Collector.Add('WertP', '', KindVariable, PenaltyProjectImport, Default(TResolvedSymbol));
    Collector.Add('WertK', '', KindKeyword, PenaltyKeyword, Default(TResolvedSymbol));
    Collector.Add('WertE', '', KindVariable, Default(TResolvedSymbol));
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
    Assert.IsFalse(Collector.Add('Rechne', '', KindFunction, Default(TResolvedSymbol)));
    // Unscharf: Teilwort trifft, filterText ist das Getippte.
    Assert.IsTrue(Collector.Add('Zaehler', '', KindField, Default(TResolvedSymbol)));
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
    Collector.Add('Lokal', '', KindVariable, Default(TResolvedSymbol));
    Collector.Add('Feld', '', KindField, Default(TResolvedSymbol));
    Collector.SendStage;
    Assert.AreEqual('Lokal Feld', Joined(Sent));
    // Leere Stufe: nichts gesendet.
    Collector.SendStage;
    Assert.AreEqual(2, Integer(Length(Sent)));
    Collector.Add('Global', '', KindVariable, Default(TResolvedSymbol));
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

procedure TCompletionCollectorTests.TypeFitsFamiliesAndDescent;
var
  CheckDescent: Boolean;
begin
  Assert.IsTrue(TypeFits('Integer', 'Double', CheckDescent));
  Assert.IsTrue(TypeFits('Char', 'string', CheckDescent));
  Assert.IsTrue(TypeFits('System.Classes.TStrings', 'TStrings', CheckDescent));
  Assert.IsFalse(TypeFits('Double', 'Integer', CheckDescent));
  Assert.IsFalse(CheckDescent);
  Assert.IsFalse(TypeFits('TButton', 'TControl', CheckDescent));
  Assert.IsTrue(CheckDescent, 'Klassen klärt die Namensauflösung');
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
      Collector.Add('Rechne', 'Werkzeug', KindFunction, Symbol);
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
      Collector.Add('Rechne', 'Werkzeug', KindFunction, Symbol);
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

initialization
  TDUnitX.RegisterTestFixture(TCompletionCollectorTests);

end.
