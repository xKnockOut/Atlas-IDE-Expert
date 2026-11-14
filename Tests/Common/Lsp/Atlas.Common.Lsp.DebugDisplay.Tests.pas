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
  cKundenFile = 'C:\P\Kunden.pas';
  cFirmenFile = 'C:\P\Firmen.pas';
  cKundenText =
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
  cFirmenText =
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
  Result.AddUnit(TIndexExtractor.ExtractText(cKundenText, cKundenFile, nil));
  Result.AddUnit(TIndexExtractor.ExtractText(cFirmenText, cFirmenFile, nil));
end;

function NewDisplay: TLspDebugDisplay;
begin
  Result := TLspDebugDisplay.Create(
    function(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean
    begin
      ASource := Default(TLspMetricsSource);
      ASource.Root := 'C:\P';
      ASource.Files := [cKundenFile, cFirmenFile, 'C:\P\Main.dfm'];
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, cKundenFile) then
      begin
        AText := cKundenText;
      end
      else if SameText(AFileName, cFirmenFile) then
      begin
        AText := cFirmenText;
      end
      else
      begin
        Result := False;
      end;
    end);
  Result.Index := NewIndex;
end;

function FindInherit(const AInherits: TArray<TLspDebugDisplayInherit>; const AName: string): string;
var
  mInherit: TLspDebugDisplayInherit;
begin
  Result := '';
  for mInherit in AInherits do
  begin
    if mInherit.Name = AName then
    begin
      Exit(mInherit.From);
    end;
  end;
end;

{ TLspDebugDisplayTests }

procedure TLspDebugDisplayTests.RulesOfUnit;
var
  mUnitIndex: TUnitIndex;
  mRules: TArray<TLspDebugDisplayRule>;
begin
  mUnitIndex := TIndexExtractor.ExtractText(cKundenText, cKundenFile, nil);
  mRules := TLspDebugDisplay.RulesOfUnit(mUnitIndex, cKundenText);
  Assert.AreEqual(2, Integer(Length(mRules)));
  Assert.AreEqual('Kunden.TKunde', mRules[0].TypeName);
  Assert.AreEqual('TKunde', mRules[0].Name);
  Assert.AreEqual(cKundenFile, mRules[0].FileName);
  Assert.AreEqual('{Name}, {Ort}', mRules[0].Source.Template);
  Assert.AreEqual(3, mRules[0].Source.TemplateLine);
  Assert.AreEqual('Name|Ort', string.Join('|', mRules[0].Source.Children));
  Assert.AreEqual(Ord(TDebugDisplayOrigin.Comment), Ord(mRules[0].Source.Origin));
  Assert.AreEqual('Kunden.TPunkt', mRules[1].TypeName);
  Assert.AreEqual('({X}, {Y})', mRules[1].Source.Template);
  Assert.AreEqual(Ord(TDebugDisplayOrigin.Attribute), Ord(mRules[1].Source.Origin));
end;

procedure TLspDebugDisplayTests.TextWithoutMarkerIsSkipped;
var
  mUnitIndex: TUnitIndex;
begin
  mUnitIndex := TIndexExtractor.ExtractText(cFirmenText, cFirmenFile, nil);
  Assert.IsFalse(TLspDebugDisplay.MayContainRules(cFirmenText));
  Assert.AreEqual(0, Integer(Length(TLspDebugDisplay.RulesOfUnit(mUnitIndex, cFirmenText))));
end;

procedure TLspDebugDisplayTests.InheritsOverUnits;
var
  mDisplay: TLspDebugDisplay;
  mRules: TArray<TLspDebugDisplayRule>;
  mInherits: TArray<TLspDebugDisplayInherit>;
begin
  mDisplay := NewDisplay;
  try
    mRules := mDisplay.Collect(nil, nil, mInherits);
    Assert.AreEqual(2, Integer(Length(mRules)));
    Assert.AreEqual('Kunden.TKunde', FindInherit(mInherits, 'TFirma'));
    // Über zwei Stufen: TKonzern → TFirma → TKunde.
    Assert.AreEqual('Kunden.TKunde', FindInherit(mInherits, 'TKonzern'));
    Assert.AreEqual('', FindInherit(mInherits, 'TOhne'));
    Assert.AreEqual('', FindInherit(mInherits, 'TVerbindung'));
  finally
    mDisplay.Free;
  end;
end;

procedure TLspDebugDisplayTests.InheritsFromExternalName;
var
  mDisplay: TLspDebugDisplay;
  mInherits: TArray<TLspDebugDisplayInherit>;
begin
  mDisplay := NewDisplay;
  try
    mDisplay.Collect(nil, ['FireDAC.Comp.Client.TFDConnection'], mInherits);
    Assert.AreEqual('FireDAC.Comp.Client.TFDConnection', FindInherit(mInherits, 'TVerbindung'));
  finally
    mDisplay.Free;
  end;
end;

procedure TLspDebugDisplayTests.OwnRuleWinsOverInheritance;
var
  mDisplay: TLspDebugDisplay;
  mInherits: TArray<TLspDebugDisplayInherit>;
begin
  mDisplay := NewDisplay;
  try
    // TKunde hat eine eigene Regel; der Name aus der Projektdatei ändert das Erbe nicht.
    mDisplay.Collect(nil, ['TKunde'], mInherits);
    Assert.AreEqual('Kunden.TKunde', FindInherit(mInherits, 'TFirma'));
    Assert.AreEqual('', FindInherit(mInherits, 'TKunde'));
  finally
    mDisplay.Free;
  end;
end;

procedure TLspDebugDisplayTests.ExecuteReturnsJson;
var
  mDisplay: TLspDebugDisplay;
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
  mRules, mInherits: TJSONArray;
  mRule: TJSONObject;
begin
  mDisplay := NewDisplay;
  mArgs := TJSONArray.Create;
  try
    mArgs.Add(TDocumentUris.FromPath('C:\P\Demo.dproj'));
    mArgs.AddElement(TJSONArray.Create(TJSONString.Create('TFDConnection')));
    mAnswer := mDisplay.Execute(mArgs);
    try
      Assert.IsTrue(mAnswer is TJSONObject);
      Assert.AreEqual(1, TJSONObject(mAnswer).GetValue<Integer>('format'));
      mRules := TJSONObject(mAnswer).GetValue('rules') as TJSONArray;
      Assert.AreEqual(2, mRules.Count);
      mRule := mRules.Items[0] as TJSONObject;
      Assert.AreEqual('Kunden.TKunde', mRule.GetValue<string>('type'));
      Assert.AreEqual('TKunde', mRule.GetValue<string>('name'));
      Assert.AreEqual('{Name}, {Ort}', mRule.GetValue<string>('template'));
      Assert.AreEqual(2, (mRule.GetValue('children') as TJSONArray).Count);
      Assert.AreEqual('comment', mRule.GetValue<string>('origin'));
      Assert.AreEqual(3, mRule.GetValue<Integer>('line'));
      Assert.AreEqual('attribute', (mRules.Items[1] as TJSONObject).GetValue<string>('origin'));
      Assert.IsNull((mRules.Items[1] as TJSONObject).GetValue('children'));
      mInherits := TJSONObject(mAnswer).GetValue('inherits') as TJSONArray;
      Assert.AreEqual(3, mInherits.Count);
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
    mDisplay.Free;
  end;
end;

procedure TLspDebugDisplayTests.WithoutIndexNoRules;
var
  mDisplay: TLspDebugDisplay;
  mInherits: TArray<TLspDebugDisplayInherit>;
begin
  mDisplay := NewDisplay;
  try
    mDisplay.Index := nil;
    Assert.AreEqual(0, Integer(Length(mDisplay.Collect(nil, nil, mInherits))));
    Assert.AreEqual(0, Integer(Length(mInherits)));
  finally
    mDisplay.Free;
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
