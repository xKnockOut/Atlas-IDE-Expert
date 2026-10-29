unit Atlas.Common.Lsp.DebugDisplay.Tests;

// Tests des Befehls atlas.server.debugDisplayRules (#854): Regeln aus
// Kommentar und Attribut samt Zeile, Erben über Units und über Namen aus der
// Projektdatei, nur Dateien des Projekts, JSON-Antwort.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspDebugDisplayTests = class
  public
    [Test]
    procedure RulesOfUnit;
    [Test]
    procedure TextWithoutMarkerIsSkipped;
    [Test]
    procedure InheritsOverUnits;
    [Test]
    procedure InheritsFromExternalName;
    [Test]
    procedure OwnRuleWinsOverInheritance;
    [Test]
    procedure ExecuteReturnsJson;
    [Test]
    procedure WithoutIndexNoRules;
    [Test]
    procedure ShortName;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Text.DebugDisplay,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.DebugDisplay;

const
  KundenFile = 'C:\P\Kunden.pas';
  FirmenFile = 'C:\P\Firmen.pas';
  KundenText =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  // atlas-debug: ''{Name}, {Ort}'''#10 +
    '  // atlas-debug-children: Name, Ort'#10 +
    '  TKunde = class'#10 +
    '    Name, Ort: string;'#10 +
    '  end;'#10 +
    '  [AtlasDebugDisplay(''({X}, {Y})'')]'#10 +
    '  TPunkt = record'#10 +
    '    X, Y: Integer;'#10 +
    '  end;'#10 +
    '  TOhne = class'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
  FirmenText =
    'unit Firmen;'#10 +
    'interface'#10 +
    'uses Kunden;'#10 +
    'type'#10 +
    '  TFirma = class(TKunde)'#10 +
    '  end;'#10 +
    '  TKonzern = class(TFirma)'#10 +
    '  end;'#10 +
    '  TVerbindung = class(TFDConnection)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

function NewIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(KundenText, KundenFile, nil));
  Result.AddUnit(TIndexExtractor.ExtractText(FirmenText, FirmenFile, nil));
end;

function NewDisplay: TLspDebugDisplay;
begin
  Result := TLspDebugDisplay.Create(
    function(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean
    begin
      ASource := Default(TLspMetricsSource);
      ASource.Root := 'C:\P';
      ASource.Files := [KundenFile, FirmenFile, 'C:\P\Main.dfm'];
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, KundenFile) then
        AText := KundenText
      else if SameText(AFileName, FirmenFile) then
        AText := FirmenText
      else
        Result := False;
    end);
  Result.Index := NewIndex;
end;

function FindInherit(const AInherits: TArray<TLspDebugDisplayInherit>; const AName: string): string;
var
  Inherit: TLspDebugDisplayInherit;
begin
  Result := '';
  for Inherit in AInherits do
    if Inherit.Name = AName then
      Exit(Inherit.From);
end;

{ TLspDebugDisplayTests }

procedure TLspDebugDisplayTests.RulesOfUnit;
var
  UnitIndex: TUnitIndex;
  Rules: TArray<TLspDebugDisplayRule>;
begin
  UnitIndex := TIndexExtractor.ExtractText(KundenText, KundenFile, nil);
  Rules := TLspDebugDisplay.RulesOfUnit(UnitIndex, KundenText);
  Assert.AreEqual(2, Integer(Length(Rules)));
  Assert.AreEqual('Kunden.TKunde', Rules[0].TypeName);
  Assert.AreEqual('TKunde', Rules[0].Name);
  Assert.AreEqual(KundenFile, Rules[0].FileName);
  Assert.AreEqual('{Name}, {Ort}', Rules[0].Source.Template);
  Assert.AreEqual(3, Rules[0].Source.TemplateLine);
  Assert.AreEqual('Name|Ort', string.Join('|', Rules[0].Source.Children));
  Assert.AreEqual(Ord(TDebugDisplayOrigin.Comment), Ord(Rules[0].Source.Origin));
  Assert.AreEqual('Kunden.TPunkt', Rules[1].TypeName);
  Assert.AreEqual('({X}, {Y})', Rules[1].Source.Template);
  Assert.AreEqual(Ord(TDebugDisplayOrigin.Attribute), Ord(Rules[1].Source.Origin));
end;

procedure TLspDebugDisplayTests.TextWithoutMarkerIsSkipped;
var
  UnitIndex: TUnitIndex;
begin
  UnitIndex := TIndexExtractor.ExtractText(FirmenText, FirmenFile, nil);
  Assert.IsFalse(TLspDebugDisplay.MayContainRules(FirmenText));
  Assert.AreEqual(0, Integer(Length(TLspDebugDisplay.RulesOfUnit(UnitIndex, FirmenText))));
end;

procedure TLspDebugDisplayTests.InheritsOverUnits;
var
  Display: TLspDebugDisplay;
  Rules: TArray<TLspDebugDisplayRule>;
  Inherits: TArray<TLspDebugDisplayInherit>;
begin
  Display := NewDisplay;
  try
    Rules := Display.Collect(nil, nil, Inherits);
    Assert.AreEqual(2, Integer(Length(Rules)));
    Assert.AreEqual('Kunden.TKunde', FindInherit(Inherits, 'TFirma'));
    // Über zwei Stufen: TKonzern → TFirma → TKunde.
    Assert.AreEqual('Kunden.TKunde', FindInherit(Inherits, 'TKonzern'));
    Assert.AreEqual('', FindInherit(Inherits, 'TOhne'));
    Assert.AreEqual('', FindInherit(Inherits, 'TVerbindung'));
  finally
    Display.Free;
  end;
end;

procedure TLspDebugDisplayTests.InheritsFromExternalName;
var
  Display: TLspDebugDisplay;
  Inherits: TArray<TLspDebugDisplayInherit>;
begin
  Display := NewDisplay;
  try
    Display.Collect(nil, ['FireDAC.Comp.Client.TFDConnection'], Inherits);
    Assert.AreEqual('FireDAC.Comp.Client.TFDConnection', FindInherit(Inherits, 'TVerbindung'));
  finally
    Display.Free;
  end;
end;

procedure TLspDebugDisplayTests.OwnRuleWinsOverInheritance;
var
  Display: TLspDebugDisplay;
  Inherits: TArray<TLspDebugDisplayInherit>;
begin
  Display := NewDisplay;
  try
    // TKunde hat eine eigene Regel; der Name aus der Projektdatei ändert das Erbe nicht.
    Display.Collect(nil, ['TKunde'], Inherits);
    Assert.AreEqual('Kunden.TKunde', FindInherit(Inherits, 'TFirma'));
    Assert.AreEqual('', FindInherit(Inherits, 'TKunde'));
  finally
    Display.Free;
  end;
end;

procedure TLspDebugDisplayTests.ExecuteReturnsJson;
var
  Display: TLspDebugDisplay;
  Args: TJSONArray;
  Answer: TJSONValue;
  Rules, Inherits: TJSONArray;
  Rule: TJSONObject;
begin
  Display := NewDisplay;
  Args := TJSONArray.Create;
  try
    Args.Add(TDocumentUris.FromPath('C:\P\Demo.dproj'));
    Args.AddElement(TJSONArray.Create(TJSONString.Create('TFDConnection')));
    Answer := Display.Execute(Args);
    try
      Assert.IsTrue(Answer is TJSONObject);
      Assert.AreEqual(1, TJSONObject(Answer).GetValue<Integer>('format'));
      Rules := TJSONObject(Answer).GetValue('rules') as TJSONArray;
      Assert.AreEqual(2, Rules.Count);
      Rule := Rules.Items[0] as TJSONObject;
      Assert.AreEqual('Kunden.TKunde', Rule.GetValue<string>('type'));
      Assert.AreEqual('TKunde', Rule.GetValue<string>('name'));
      Assert.AreEqual('{Name}, {Ort}', Rule.GetValue<string>('template'));
      Assert.AreEqual(2, (Rule.GetValue('children') as TJSONArray).Count);
      Assert.AreEqual('comment', Rule.GetValue<string>('origin'));
      Assert.AreEqual(3, Rule.GetValue<Integer>('line'));
      Assert.AreEqual('attribute', (Rules.Items[1] as TJSONObject).GetValue<string>('origin'));
      Assert.IsNull((Rules.Items[1] as TJSONObject).GetValue('children'));
      Inherits := TJSONObject(Answer).GetValue('inherits') as TJSONArray;
      Assert.AreEqual(3, Inherits.Count);
    finally
      Answer.Free;
    end;
  finally
    Args.Free;
    Display.Free;
  end;
end;

procedure TLspDebugDisplayTests.WithoutIndexNoRules;
var
  Display: TLspDebugDisplay;
  Inherits: TArray<TLspDebugDisplayInherit>;
begin
  Display := NewDisplay;
  try
    Display.Index := nil;
    Assert.AreEqual(0, Integer(Length(Display.Collect(nil, nil, Inherits))));
    Assert.AreEqual(0, Integer(Length(Inherits)));
  finally
    Display.Free;
  end;
end;

procedure TLspDebugDisplayTests.ShortName;
begin
  Assert.AreEqual('TKunde', TLspDebugDisplay.ShortName('Kunden.TKunde'));
  Assert.AreEqual('TList', TLspDebugDisplay.ShortName('System.Generics.Collections.TList<Kunden.TKunde>'));
  Assert.AreEqual('TInnen', TLspDebugDisplay.ShortName(' TAussen.TInnen '));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDebugDisplayTests);

end.
