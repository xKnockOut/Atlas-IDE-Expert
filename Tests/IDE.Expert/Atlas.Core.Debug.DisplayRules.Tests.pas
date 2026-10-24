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
  ServerJson = '{"format":1,"rules":[' +
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
        AText := '''Meier'''
      else if AExpression = '(Kunde).Ort' then
        AText := '''Berlin'''
      else if AExpression = '(Kunde).Nr' then
        AText := '4711'
      else if AExpression = '(Kunde).Saldo' then
        AText := '1234.5'
      else if (AExpression = '(Kunde).GetName()') and (AEvaluation = TAtlasVisualizerEvaluation.Calls) then
        AText := '''MEIER'''
      else if AExpression = 'Kunde,r' then
        AText := '(FName:''Meier''; Ort:''Berlin''; Nr:4711; Saldo:1234.5)'
      else
        Result := False;
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
  Rules: TAtlasDisplayRules;
  Found: TAtlasDisplayRule;
begin
  Rules := TAtlasDisplayRules.Create;
  try
    Assert.IsTrue(Rules.LoadJson(ServerJson));
    Assert.AreEqual(2, Rules.Count);
    Assert.IsTrue(Rules.Find('Kunden.TKunde', Found));
    Assert.AreEqual('{Name}, {Ort} (Nr {Nr})', Found.Template);
    Assert.AreEqual('Name|Ort', string.Join('|', Found.Children));
    Assert.AreEqual(Ord(TDebugDisplayOrigin.Comment), Ord(Found.Origin));
    Assert.AreEqual('C:\P\Kunden.pas', Found.FileName);
    Assert.AreEqual(4, Found.Line);
    Assert.IsTrue(Rules.Find('TPunkt', Found));
    Assert.AreEqual(Ord(TDebugDisplayOrigin.Attribute), Ord(Found.Origin));
  finally
    Rules.Free;
  end;
end;

procedure TAtlasDisplayRulesTests.RejectsWrongFormat;
var
  Rules: TAtlasDisplayRules;
begin
  Rules := TAtlasDisplayRules.Create;
  try
    Assert.IsFalse(Rules.LoadJson('{"format":2,"rules":[]}'));
    Assert.IsFalse(Rules.LoadJson('kein JSON'));
    Assert.IsFalse(Rules.LoadJson('[]'));
    Assert.AreEqual(0, Rules.Count);
  finally
    Rules.Free;
  end;
end;

procedure TAtlasDisplayRulesTests.FindByNameAndInheritance;
var
  Rules: TAtlasDisplayRules;
  Found: TAtlasDisplayRule;
  Project: TAtlasDisplayRule;
begin
  Rules := TAtlasDisplayRules.Create;
  try
    Rules.LoadJson(ServerJson);
    Assert.IsTrue(Rules.Find('tkunde', Found));
    Assert.IsTrue(Rules.Find('Andere.Unit.TKunde', Found), 'kurzer Name als Rückfall');
    Assert.IsTrue(Rules.Find('TGeschaeftskunde', Found));
    Assert.AreEqual('Kunden.TKunde', Found.TypeName);
    Assert.IsTrue(Rules.Find('Kunden.TGeschaeftskunde', Found));
    // Erbe einer Regel aus der Projektdatei: erst mit der Regel auffindbar.
    Assert.IsFalse(Rules.Find('TVerbindung', Found));
    Project := Default(TAtlasDisplayRule);
    Project.TypeName := 'FireDAC.Comp.Client.TFDConnection';
    Project.Template := '{ConnectionName}';
    Project.Origin := TDebugDisplayOrigin.Project;
    Rules.Add(Project);
    Assert.IsTrue(Rules.Find('TVerbindung', Found));
    Assert.AreEqual('{ConnectionName}', Found.Template);
    Assert.IsFalse(Rules.Find('TUnbekannt', Found));
  finally
    Rules.Free;
  end;
end;

procedure TAtlasDisplayRulesTests.FindChain;
var
  Rules: TAtlasDisplayRules;
  Found: TAtlasDisplayRule;
begin
  Rules := TAtlasDisplayRules.Create;
  try
    Rules.LoadJson(ServerJson);
    Assert.IsTrue(Rules.FindChain(['TSonderkunde', '', 'TKunde', 'TObject'], Found));
    Assert.AreEqual('Kunden.TKunde', Found.TypeName);
    Assert.IsFalse(Rules.FindChain(['TSonderkunde', 'TObject'], Found));
  finally
    Rules.Free;
  end;
end;

procedure TAtlasDisplayRulesTests.SourceRuleBeatsProjectRule;
var
  Rules: TAtlasDisplayRules;
  Found, Project: TAtlasDisplayRule;
begin
  Rules := TAtlasDisplayRules.Create;
  try
    Project := Default(TAtlasDisplayRule);
    Project.TypeName := 'TKunde';
    Project.Template := 'aus .atlas';
    Project.Origin := TDebugDisplayOrigin.Project;
    Rules.Add(Project);
    Assert.IsTrue(Rules.Find('TKunde', Found));
    Assert.AreEqual('aus .atlas', Found.Template);
    Rules.LoadJson(ServerJson);
    Assert.IsTrue(Rules.Find('TKunde', Found));
    Assert.AreEqual('{Name}, {Ort} (Nr {Nr})', Found.Template);
    Assert.AreEqual('TKunde', string.Join('|', Rules.ProjectNames));
    // Leere Regel (weder Vorlage noch Unterelemente) zählt nicht.
    Rules.Add(Rule(''));
    Assert.AreEqual(3, Rules.Count);
  finally
    Rules.Free;
  end;
end;

procedure TAtlasDisplayRulesTests.TypeNamesForRegistration;
var
  Rules: TAtlasDisplayRules;
  Names: string;
begin
  Rules := TAtlasDisplayRules.Create;
  try
    Rules.LoadJson(ServerJson);
    Names := '|' + string.Join('|', Rules.TypeNames) + '|';
    Assert.IsTrue(Names.Contains('|Kunden.TKunde|'));
    Assert.IsTrue(Names.Contains('|TKunde|'));
    Assert.IsTrue(Names.Contains('|TPunkt|'));
    Assert.IsTrue(Names.Contains('|TGeschaeftskunde|'));
    // Erbe ohne vorhandene Regel wird nicht angemeldet.
    Assert.IsFalse(Names.ToLower.Contains('|tverbindung|'));
  finally
    Rules.Free;
  end;
end;

procedure TAtlasDisplayRulesTests.RenderTemplate;
begin
  Assert.AreEqual('Meier, Berlin (Nr 4711)', TAtlasDisplayRender.Render(Rule('{Name}, {Ort} (Nr {Nr})'), 'Kunde',
    Options(False), Eval));
  Assert.AreEqual('Saldo 1234,50 {fest}', TAtlasDisplayRender.Render(Rule('Saldo {Saldo:0.00} {{fest}}'), 'Kunde',
    Options(False), Eval).Replace('1234.50', '1234,50'));
  Assert.AreEqual('', TAtlasDisplayRender.Render(Rule('{Name'), 'Kunde', Options(False), Eval));
  Assert.AreEqual('', TAtlasDisplayRender.Render(Rule(''), 'Kunde', Options(False), Eval));
end;

procedure TAtlasDisplayRulesTests.RenderMissingAndCalls;
var
  Short: TAtlasDisplayRuleOptions;
begin
  Assert.AreEqual('Meier {?Stadt} {?GetName()}', TAtlasDisplayRender.Render(Rule('{Name} {Stadt} {GetName()}'),
    'Kunde', Options(False), Eval));
  Assert.AreEqual('{?Name}', TAtlasDisplayRender.Render(Rule('{Name}'), 'Kunde', Options(False), nil));
  Short := Options(False);
  Short.MaxLength := 20;
  Assert.AreEqual(20, Length(TAtlasDisplayRender.Render(Rule('{Name}, {Ort}, {Name}, {Ort}'), 'Kunde', Short,
    Eval)));
end;

procedure TAtlasDisplayRulesTests.RenderWithCallsAllowed;
begin
  Assert.AreEqual('MEIER', TAtlasDisplayRender.Render(Rule('{GetName()}'), 'Kunde', Options(True), Eval));
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
  Children: TAtlasDisplayRule;
  View: TAtlasVisualizerView;
begin
  Children := Rule('{Name}');
  Children.Children := TArray<string>.Create('Name', 'Fehlt');
  View := TAtlasDisplayRender.View(Children, 'Kunde', '($0A3F1C20)', Options(False), Eval);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Table), Ord(View.Mode));
  Assert.AreEqual('Meier', View.Summary);
  Assert.AreEqual(2, Integer(Length(View.Rows)));
  Assert.AreEqual('Name', View.Rows[0][0]);
  Assert.AreEqual('''Meier''', View.Rows[0][1]);
  Assert.AreEqual('{?Fehlt}', View.Rows[1][1]);
  Assert.AreEqual(4, Integer(Length(View.AllRows)));
  Assert.AreEqual('FName', View.AllRows[0][0]);
  Assert.AreEqual('4711', View.AllRows[2][1]);
end;

procedure TAtlasDisplayRulesTests.ViewWithoutChildren;
var
  View: TAtlasVisualizerView;
begin
  View := TAtlasDisplayRender.View(Rule('{Name}'), 'Kunde', '', Options(False), Eval);
  Assert.AreEqual(4, Integer(Length(View.Rows)));
  Assert.AreEqual(0, Integer(Length(View.AllRows)));
  // Ohne Feldliste vom Debugger: der Text der IDE.
  View := TAtlasDisplayRender.View(Rule('{Name}'), 'Anders', '(A:1; B:2)', Options(False), Eval);
  Assert.AreEqual('{?Name}', View.Summary);
  Assert.AreEqual(2, Integer(Length(View.Rows)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDisplayRulesTests);

end.
