unit Atlas.Core.Debug.DisplayRules.Tests;

// Tests der eigenen Wertdarstellung im Plugin (#854): Regeln aus der Antwort
// des Servers, Vorrang vor der Projektdatei, Suche über Namen, Erben und
// Ketten, Ersatztext mit Format, {?…} bei Fehler und Aufruf ohne allowCalls,
// Ansicht mit Unterelementen und allen Feldern.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDisplayRulesTests = class
  public
    [Test]
    procedure LoadServerJson;
    [Test]
    procedure RejectsWrongFormat;
    [Test]
    procedure FindByNameAndInheritance;
    [Test]
    procedure FindChain;
    [Test]
    procedure SourceRuleBeatsProjectRule;
    [Test]
    procedure TypeNamesForRegistration;
    [Test]
    procedure RenderTemplate;
    [Test]
    procedure RenderMissingAndCalls;
    [Test]
    procedure RenderWithCallsAllowed;
    [Test]
    procedure FormatValue;
    [Test]
    procedure ExpressionOf;
    [Test]
    procedure ViewWithChildren;
    [Test]
    procedure ViewWithoutChildren;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.DebugDisplay,
  Atlas.Core.Debug.Visualizers,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Core.Debug.DisplayRules;

const
  cServerJson = '{"format":1,"rules":[' +
    '{"type":"Kunden.TKunde","name":"TKunde","template":"{Name}, {Ort} (Nr {Nr})",' +
    '"children":["Name","Ort"],"origin":"comment","file":"C:\\P\\Kunden.pas","line":4},' +
    '{"type":"Kunden.TPunkt","name":"TPunkt","template":"({X}, {Y})","origin":"attribute","file":"","line":9}],' +
    '"inherits":[{"type":"Kunden.TGeschaeftskunde","name":"TGeschaeftskunde","from":"Kunden.TKunde"},' +
    '{"type":"Daten.TVerbindung","name":"TVerbindung","from":"TFDConnection"}]}';

/// <summary>Programm im Test: Kunde mit Name, Ort, Nr und Saldo; GetName() ist ein Aufruf.</summary>
function Eval: TAtlasVisualizerEval;
begin
  Result :=
    function(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation; out AText: string): Boolean
    begin
      Result := True;
      if AExpression = '(Kunde).Name' then
      begin
        AText := '''Meier''';
      end
      else if AExpression = '(Kunde).Ort' then
      begin
        AText := '''Berlin''';
      end
      else if AExpression = '(Kunde).Nr' then
      begin
        AText := '4711';
      end
      else if AExpression = '(Kunde).Saldo' then
      begin
        AText := '1234.5';
      end
      else if (AExpression = '(Kunde).GetName()') and (AEvaluation = TAtlasVisualizerEvaluation.Calls) then
      begin
        AText := '''MEIER''';
      end
      else if AExpression = 'Kunde,r' then
      begin
        AText := '(FName:''Meier''; Ort:''Berlin''; Nr:4711; Saldo:1234.5)';
      end
      else
      begin
        Result := False;
      end;
    end;
end;

function Options(AAllowCalls: Boolean): TAtlasDisplayRuleOptions;
begin
  Result := Default(TAtlasDisplayRuleOptions);
  Result.AllowCalls := AAllowCalls;
  Result.MaxLength := 120;
end;

function Rule(const ATemplate: string): TAtlasDisplayRule;
begin
  Result := Default(TAtlasDisplayRule);
  Result.TypeName := 'TKunde';
  Result.Template := ATemplate;
end;

procedure TAtlasDisplayRulesTests.LoadServerJson;
var
  mRules: TAtlasDisplayRules;
  mFound: TAtlasDisplayRule;
begin
  mRules := TAtlasDisplayRules.Create;
  try
    Assert.IsTrue(mRules.LoadJson(cServerJson));
    Assert.AreEqual(2, mRules.Count);
    Assert.IsTrue(mRules.Find('Kunden.TKunde', mFound));
    Assert.AreEqual('{Name}, {Ort} (Nr {Nr})', mFound.Template);
    Assert.AreEqual('Name|Ort', string.Join('|', mFound.Children));
    Assert.AreEqual(Ord(TDebugDisplayOrigin.Comment), Ord(mFound.Origin));
    Assert.AreEqual('C:\P\Kunden.pas', mFound.FileName);
    Assert.AreEqual(4, mFound.Line);
    Assert.IsTrue(mRules.Find('TPunkt', mFound));
    Assert.AreEqual(Ord(TDebugDisplayOrigin.Attribute), Ord(mFound.Origin));
  finally
    mRules.Free;
  end;
end;

procedure TAtlasDisplayRulesTests.RejectsWrongFormat;
var
  mRules: TAtlasDisplayRules;
begin
  mRules := TAtlasDisplayRules.Create;
  try
    Assert.IsFalse(mRules.LoadJson('{"format":2,"rules":[]}'));
    Assert.IsFalse(mRules.LoadJson('kein JSON'));
    Assert.IsFalse(mRules.LoadJson('[]'));
    Assert.AreEqual(0, mRules.Count);
  finally
    mRules.Free;
  end;
end;

procedure TAtlasDisplayRulesTests.FindByNameAndInheritance;
var
  mRules: TAtlasDisplayRules;
  mFound: TAtlasDisplayRule;
  mProject: TAtlasDisplayRule;
begin
  mRules := TAtlasDisplayRules.Create;
  try
    mRules.LoadJson(cServerJson);
    Assert.IsTrue(mRules.Find('tkunde', mFound));
    Assert.IsTrue(mRules.Find('Andere.Unit.TKunde', mFound), 'kurzer Name als Rückfall');
    Assert.IsTrue(mRules.Find('TGeschaeftskunde', mFound));
    Assert.AreEqual('Kunden.TKunde', mFound.TypeName);
    Assert.IsTrue(mRules.Find('Kunden.TGeschaeftskunde', mFound));
    // Erbe einer Regel aus der Projektdatei: erst mit der Regel auffindbar.
    Assert.IsFalse(mRules.Find('TVerbindung', mFound));
    mProject := Default(TAtlasDisplayRule);
    mProject.TypeName := 'FireDAC.Comp.Client.TFDConnection';
    mProject.Template := '{ConnectionName}';
    mProject.Origin := TDebugDisplayOrigin.Project;
    mRules.Add(mProject);
    Assert.IsTrue(mRules.Find('TVerbindung', mFound));
    Assert.AreEqual('{ConnectionName}', mFound.Template);
    Assert.IsFalse(mRules.Find('TUnbekannt', mFound));
  finally
    mRules.Free;
  end;
end;

procedure TAtlasDisplayRulesTests.FindChain;
var
  mRules: TAtlasDisplayRules;
  mFound: TAtlasDisplayRule;
begin
  mRules := TAtlasDisplayRules.Create;
  try
    mRules.LoadJson(cServerJson);
    Assert.IsTrue(mRules.FindChain(['TSonderkunde', '', 'TKunde', 'TObject'], mFound));
    Assert.AreEqual('Kunden.TKunde', mFound.TypeName);
    Assert.IsFalse(mRules.FindChain(['TSonderkunde', 'TObject'], mFound));
  finally
    mRules.Free;
  end;
end;

procedure TAtlasDisplayRulesTests.SourceRuleBeatsProjectRule;
var
  mRules: TAtlasDisplayRules;
  mFound, mProject: TAtlasDisplayRule;
begin
  mRules := TAtlasDisplayRules.Create;
  try
    mProject := Default(TAtlasDisplayRule);
    mProject.TypeName := 'TKunde';
    mProject.Template := 'aus .atlas';
    mProject.Origin := TDebugDisplayOrigin.Project;
    mRules.Add(mProject);
    Assert.IsTrue(mRules.Find('TKunde', mFound));
    Assert.AreEqual('aus .atlas', mFound.Template);
    mRules.LoadJson(cServerJson);
    Assert.IsTrue(mRules.Find('TKunde', mFound));
    Assert.AreEqual('{Name}, {Ort} (Nr {Nr})', mFound.Template);
    Assert.AreEqual('TKunde', string.Join('|', mRules.ProjectNames));
    // Leere Regel (weder Vorlage noch Unterelemente) zählt nicht.
    mRules.Add(Rule(''));
    Assert.AreEqual(3, mRules.Count);
  finally
    mRules.Free;
  end;
end;

procedure TAtlasDisplayRulesTests.TypeNamesForRegistration;
var
  mRules: TAtlasDisplayRules;
  mNames: string;
begin
  mRules := TAtlasDisplayRules.Create;
  try
    mRules.LoadJson(cServerJson);
    mNames := '|' + string.Join('|', mRules.TypeNames) + '|';
    Assert.IsTrue(mNames.Contains('|Kunden.TKunde|'));
    Assert.IsTrue(mNames.Contains('|TKunde|'));
    Assert.IsTrue(mNames.Contains('|TPunkt|'));
    Assert.IsTrue(mNames.Contains('|TGeschaeftskunde|'));
    // Erbe ohne vorhandene Regel wird nicht angemeldet.
    Assert.IsFalse(mNames.ToLower.Contains('|tverbindung|'));
  finally
    mRules.Free;
  end;
end;

procedure TAtlasDisplayRulesTests.RenderTemplate;
begin
  Assert.AreEqual('Meier, Berlin (Nr 4711)', TAtlasDisplayRender.Render(Rule('{Name}, {Ort} (Nr {Nr})'), 'Kunde',
    Options(False), Eval()));
  Assert.AreEqual('Saldo 1234,50 {fest}', TAtlasDisplayRender.Render(Rule('Saldo {Saldo:0.00} {{fest}}'), 'Kunde',
    Options(False), Eval()).Replace('1234.50', '1234,50'));
  Assert.AreEqual('', TAtlasDisplayRender.Render(Rule('{Name'), 'Kunde', Options(False), Eval()));
  Assert.AreEqual('', TAtlasDisplayRender.Render(Rule(''), 'Kunde', Options(False), Eval()));
end;

procedure TAtlasDisplayRulesTests.RenderMissingAndCalls;
var
  mShort: TAtlasDisplayRuleOptions;
begin
  Assert.AreEqual('Meier {?Stadt} {?GetName()}', TAtlasDisplayRender.Render(Rule('{Name} {Stadt} {GetName()}'),
    'Kunde', Options(False), Eval()));
  Assert.AreEqual('{?Name}', TAtlasDisplayRender.Render(Rule('{Name}'), 'Kunde', Options(False), nil));
  mShort := Options(False);
  mShort.MaxLength := 20;
  Assert.AreEqual(20, Length(TAtlasDisplayRender.Render(Rule('{Name}, {Ort}, {Name}, {Ort}'), 'Kunde', mShort,
    Eval())));
end;

procedure TAtlasDisplayRulesTests.RenderWithCallsAllowed;
begin
  Assert.AreEqual('MEIER', TAtlasDisplayRender.Render(Rule('{GetName()}'), 'Kunde', Options(True), Eval()));
end;

procedure TAtlasDisplayRulesTests.FormatValue;
begin
  Assert.AreEqual('abc', TAtlasDisplayRender.FormatValue('abc', '0.00'));
  Assert.AreEqual('1234.5', TAtlasDisplayRender.FormatValue('1234.5', ''));
  Assert.AreEqual('0042', TAtlasDisplayRender.FormatValue('42', '0000'));
end;

procedure TAtlasDisplayRulesTests.ExpressionOf;
begin
  Assert.AreEqual('(Kunde).Name', TAtlasDisplayRender.ExpressionOf('Kunde', 'Name'));
  Assert.AreEqual('(Liste)[0]', TAtlasDisplayRender.ExpressionOf('Liste', '[0]'));
  Assert.AreEqual('{?Name}', TAtlasDisplayRender.Missing('Name'));
end;

procedure TAtlasDisplayRulesTests.ViewWithChildren;
var
  mChildren: TAtlasDisplayRule;
  mView: TAtlasVisualizerView;
begin
  mChildren := Rule('{Name}');
  mChildren.Children := TArray<string>.Create('Name', 'Fehlt');
  mView := TAtlasDisplayRender.View(mChildren, 'Kunde', '($0A3F1C20)', Options(False), Eval());
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Table), Ord(mView.Mode));
  Assert.AreEqual('Meier', mView.Summary);
  Assert.AreEqual(2, Integer(Length(mView.Rows)));
  Assert.AreEqual('Name', mView.Rows[0][0]);
  Assert.AreEqual('''Meier''', mView.Rows[0][1]);
  Assert.AreEqual('{?Fehlt}', mView.Rows[1][1]);
  Assert.AreEqual(4, Integer(Length(mView.AllRows)));
  Assert.AreEqual('FName', mView.AllRows[0][0]);
  Assert.AreEqual('4711', mView.AllRows[2][1]);
end;

procedure TAtlasDisplayRulesTests.ViewWithoutChildren;
var
  mView: TAtlasVisualizerView;
begin
  mView := TAtlasDisplayRender.View(Rule('{Name}'), 'Kunde', '', Options(False), Eval());
  Assert.AreEqual(4, Integer(Length(mView.Rows)));
  Assert.AreEqual(0, Integer(Length(mView.AllRows)));
  // Ohne Feldliste vom Debugger: der Text der IDE.
  mView := TAtlasDisplayRender.View(Rule('{Name}'), 'Anders', '(A:1; B:2)', Options(False), Eval());
  Assert.AreEqual('{?Name}', mView.Summary);
  Assert.AreEqual(2, Integer(Length(mView.Rows)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDisplayRulesTests);

end.
