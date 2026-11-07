unit Atlas.Core.Debug.Visualizers.Tests;

// Tests für die Visualisierer beim Debuggen (#835) ohne IDE: Formatierung
// aller Ersatztexte (Kürzen, Hex, JSON, Farbnamen, Geometrie, TGUID) aus
// vorgegebenen Auswertungsergebnissen, Zuordnung der Typen, Einstellungen und
// die Grenze debug.visualizers.evaluation.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Atlas.Core.Debug.Visualizers,
  Atlas.Core.Settings.VisualizerKinds;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TVisualizerTests = class
  private
    FValues: TDictionary<string, string>;
    FAsked: TList<string>;
    FMemory: TBytes;
    FMemoryAddress: UInt64;
    function Context: TAtlasVisualizerContext;
    function Options(AEvaluation: TAtlasVisualizerEvaluation): TAtlasVisualizerOptions;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure KindsAndSettings;
    [Test]
    procedure TypeNames;
    [Test]
    procedure SupportedTypesHaveUnitAndGenerics;
    [Test]
    procedure ParseFieldsAndNumbers;
    [Test]
    procedure ShortenAndUnquote;
    [Test]
    procedure ListWithNames;
    [Test]
    procedure ListOfSimpleValuesAndFieldFallback;
    [Test]
    procedure DictionaryPairs;
    [Test]
    procedure DataSetInEdit;
    [Test]
    procedure DataSetFieldsOnly;
    [Test]
    procedure BytesHexAndView;
    [Test]
    procedure MemoryStream;
    [Test]
    procedure JsonWithCallsAndWithout;
    [Test]
    procedure JsonTreeNodes;
    [Test]
    procedure Colors;
    [Test]
    procedure GuidAndGeometry;
    [Test]
    procedure BitmapImage;
    [Test]
    procedure DibPixelsBottomUp;
    [Test]
    procedure HexLines;
    [Test]
    procedure KindSwitchedOff;
    [Test]
    procedure KindFromHoverChain;
  end;

implementation

{ TVisualizerTests }

procedure TVisualizerTests.Setup;
begin
  FValues := TDictionary<string, string>.Create;
  FAsked := TList<string>.Create;
  FMemory := nil;
  FMemoryAddress := 0;
end;

procedure TVisualizerTests.TearDown;
begin
  FValues.Free;
  FAsked.Free;
  FMemory := nil;
end;

function TVisualizerTests.Context: TAtlasVisualizerContext;
var
  mValues: TDictionary<string, string>;
  mAsked: TList<string>;
  mSelf_: TVisualizerTests;
begin
  mValues := FValues;
  mAsked := FAsked;
  mSelf_ := Self;
  Result.Eval :=
    function(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation; out AText: string): Boolean
    begin
      mAsked.Add(AExpression);
      Result := mValues.TryGetValue(AExpression, AText);
    end;
  Result.Read :=
    function(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean
    begin
      Result := (AAddress = mSelf_.FMemoryAddress) and (ACount <= Length(mSelf_.FMemory));
      ABytes := nil;
      if Result then
      begin
        ABytes := Copy(mSelf_.FMemory, 0, ACount);
      end;
    end;
end;

function TVisualizerTests.Options(AEvaluation: TAtlasVisualizerEvaluation): TAtlasVisualizerOptions;
begin
  Result := TAtlasVisualizerOptions.Defaults;
  Result.Evaluation := AEvaluation;
end;

procedure TVisualizerTests.KindsAndSettings;
begin
  // Lesen der Einstellungen prüft Atlas.Core.Settings.VisualizerKinds.Tests; hier die Vorgaben der Optionen.
  Assert.IsTrue(TAtlasVisualizerKind.Graphics in TAtlasVisualizerOptions.Defaults.Kinds);
  Assert.AreEqual(3, Integer(Length(TAtlasVisualizerOptions.Defaults.NameFields)));
  Assert.AreEqual(120, TAtlasVisualizerOptions.Defaults.MaxLength);
  Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Properties), Ord(TAtlasVisualizerOptions.Defaults.Evaluation));
end;

procedure TVisualizerTests.TypeNames;
var
  mKind: TAtlasVisualizerKind;
begin
  Assert.AreEqual('TObjectList<TKunde>',
    TAtlasVisualizers.ShortTypeName('System.Generics.Collections.TObjectList<Unit1.TKunde>'));
  Assert.AreEqual('TDictionary<string,TPair<Integer,TKunde>>',
    TAtlasVisualizers.ShortTypeName('TDictionary<System.string, TPair<System.Integer, Kunden.TKunde>>'));
  Assert.AreEqual('TList', TAtlasVisualizers.BaseTypeName('System.Generics.Collections.TList<Unit1.TKunde>'));
  Assert.IsTrue(TAtlasVisualizers.KindOf('TObjectList<TKunde>', mKind));
  Assert.AreEqual(Ord(TAtlasVisualizerKind.Lists), Ord(mKind));
  // Die alte TList ohne Typargumente ist keine generische Liste.
  Assert.IsFalse(TAtlasVisualizers.KindOf('System.Classes.TList', mKind));
  Assert.IsTrue(TAtlasVisualizers.KindOf('TArray<System.Byte>', mKind));
  Assert.AreEqual(Ord(TAtlasVisualizerKind.Bytes), Ord(mKind));
  Assert.IsTrue(TAtlasVisualizers.KindOf('Vcl.Graphics.TColor', mKind));
  Assert.AreEqual(Ord(TAtlasVisualizerKind.Colors), Ord(mKind));
  // TDateTime und TStrings bleiben bei der IDE.
  Assert.IsFalse(TAtlasVisualizers.KindOf('TDateTime', mKind));
  Assert.IsFalse(TAtlasVisualizers.KindOf('TStringList', mKind));
  // Nachfahren über die Kette.
  Assert.IsFalse(TAtlasVisualizers.KindOf('TKundenQuery', mKind));
  Assert.IsTrue(TAtlasVisualizers.KindOfChain(['TKundenQuery', 'TFDQuery', 'TFDCustomQuery'], mKind));
  Assert.AreEqual(Ord(TAtlasVisualizerKind.DataSets), Ord(mKind));
end;

procedure TVisualizerTests.SupportedTypesHaveUnitAndGenerics;
var
  mTypes: TArray<TAtlasVisualizerType>;
  mItem: TAtlasVisualizerType;
  mFound: Boolean;
  mKind: TAtlasVisualizerKind;
begin
  mTypes := TAtlasVisualizers.SupportedTypes(TAtlasVisualizerKind.Lists);
  mFound := False;
  for mItem in mTypes do
  begin
    if mItem.TypeName = 'System.Generics.Collections.TObjectList<T>' then
    begin
      mFound := True;
      Assert.IsTrue(mItem.IsGeneric);
      Assert.IsTrue(mItem.AllDescendants);
    end;
  end;
  Assert.IsTrue(mFound);
  for mKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
  begin
    Assert.IsTrue(Length(TAtlasVisualizers.SupportedTypes(mKind)) > 0, TAtlasVisualizerSettings.KindNames[mKind]);
  end;
  mFound := False;
  for mItem in TAtlasVisualizers.SupportedTypes(TAtlasVisualizerKind.DataSets) do
  begin
    if (mItem.TypeName = 'Data.DB.TDataSet') and mItem.AllDescendants and not mItem.IsGeneric then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound, 'TDataSet samt Nachfahren');
end;

procedure TVisualizerTests.ParseFieldsAndNumbers;
var
  mFields: TArray<TAtlasDebugField>;
  mValue: string;
  mNumber: Int64;
  mAddress: UInt64;
  mBytes: TBytes;
begin
  Assert.IsTrue(TAtlasVisualizerFormat.ParseFields('(X:10; Y: 20; Name: ''a;b''; Inner:(1, 2))', mFields));
  Assert.AreEqual(4, Integer(Length(mFields)));
  Assert.IsTrue(TAtlasVisualizerFormat.FieldValue(mFields, 'y', mValue));
  Assert.AreEqual('20', mValue);
  Assert.IsTrue(TAtlasVisualizerFormat.FieldValue(mFields, 'Name', mValue));
  Assert.AreEqual('''a;b''', mValue);
  Assert.IsTrue(TAtlasVisualizerFormat.FieldValue(mFields, 'Inner', mValue));
  Assert.AreEqual('(1, 2)', mValue);
  Assert.IsFalse(TAtlasVisualizerFormat.ParseFields('42', mFields));
  Assert.IsTrue(TAtlasVisualizerFormat.ParseInteger(' -16777201 ', mNumber));
  Assert.AreEqual(Int64(-16777201), mNumber);
  Assert.IsTrue(TAtlasVisualizerFormat.ParseInteger('$FF', mNumber));
  Assert.AreEqual(Int64(255), mNumber);
  Assert.IsTrue(TAtlasVisualizerFormat.ParseInteger('Pointer($1F)', mNumber));
  Assert.AreEqual(Int64(31), mNumber);
  Assert.IsFalse(TAtlasVisualizerFormat.ParseInteger('''abc''', mNumber));
  Assert.IsTrue(TAtlasVisualizerFormat.ParseAddress(':0A3F1C20', mAddress));
  Assert.IsTrue(mAddress = $0A3F1C20, 'Adresse');
  Assert.IsFalse(TAtlasVisualizerFormat.ParseAddress('nil', mAddress));
  Assert.IsTrue(TAtlasVisualizerFormat.ParseAddress('$FFFF800000001000', mAddress), 'höchstes Bit gesetzt');
  Assert.IsTrue(TAtlasVisualizerFormat.ParseByteList('(72, 101, $6C)', mBytes));
  Assert.AreEqual(3, Integer(Length(mBytes)));
  Assert.AreEqual(108, Integer(mBytes[2]));
  Assert.IsTrue(TAtlasVisualizerFormat.ParseByteList('()', mBytes));
  Assert.AreEqual(0, Integer(Length(mBytes)));
  Assert.IsFalse(TAtlasVisualizerFormat.ParseByteList('(1, 300)', mBytes));
  Assert.IsFalse(TAtlasVisualizerFormat.ParseByteList('(X:1)', mBytes));
end;

procedure TVisualizerTests.ShortenAndUnquote;
begin
  Assert.AreEqual('abc', TAtlasVisualizerFormat.Shorten('abc', 3));
  Assert.AreEqual('ab…', TAtlasVisualizerFormat.Shorten('abcd', 3));
  Assert.AreEqual('It''s', TAtlasVisualizerFormat.Unquote('''It''''s'''));
  Assert.AreEqual('42', TAtlasVisualizerFormat.Unquote('42'));
  Assert.IsTrue(TAtlasVisualizerFormat.IsStructured('($0A3F1C20)'));
  Assert.IsTrue(TAtlasVisualizerFormat.IsStructured(':0A3F1C20'));
  Assert.IsFalse(TAtlasVisualizerFormat.IsStructured('''Meier'''));
  Assert.IsFalse(TAtlasVisualizerFormat.IsStructured('3'));
end;

procedure TVisualizerTests.ListWithNames;
var
  mText: string;
  mView: TAtlasVisualizerView;
begin
  FValues.Add('Kunden.Count', '3');
  FValues.Add('Kunden.List[0]', '($0A3F1C20)');
  FValues.Add('Kunden.List[1]', '($0A3F1C40)');
  FValues.Add('Kunden.List[2]', '($0A3F1C60)');
  FValues.Add('Kunden.List[0].Name', '''Meier''');
  FValues.Add('Kunden.List[1].Name', '''Schulz''');
  FValues.Add('Kunden.List[2].Name', '''Öztürk''');
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Lists, 'Kunden',
    'System.Generics.Collections.TObjectList<Unit1.TKunde>', '(...)', Options(TAtlasVisualizerEvaluation.Fields),
    Context);
  Assert.AreEqual('TObjectList<TKunde> · Count = 3 · [Meier, Schulz, Öztürk]', mText);
  mView := TAtlasVisualizers.View(TAtlasVisualizerKind.Lists, 'Kunden', 'TObjectList<TKunde>', '(...)',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Table), Ord(mView.Mode));
  Assert.AreEqual(3, Integer(Length(mView.Rows)));
  Assert.AreEqual('Schulz', mView.Rows[1][1]);
  Assert.AreEqual(Int64(3), mView.Total);
  // Kürzen auf maxLength.
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Lists, 'Kunden', 'TObjectList<TKunde>', '',
    TAtlasVisualizerOptions.Defaults, Context);
  Assert.AreEqual('TObjectList<TKunde> · Count = 3 · [Meier, Schulz, Öztürk]', mText);
end;

procedure TVisualizerTests.ListOfSimpleValuesAndFieldFallback;
var
  mOptions_: TAtlasVisualizerOptions;
  mText: string;
  mIndex: Integer;
begin
  // Count nur über das Feld der Hilfsstruktur, Elemente über FItems, sieben Einträge: fünf und „…“.
  FValues.Add('Zahlen.FListHelper.FCount', '7');
  for mIndex := 0 to 6 do
  begin
    FValues.Add(Format('Zahlen.FItems[%d]', [mIndex]), IntToStr(mIndex * 10));
  end;
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Lists, 'Zahlen', 'TList<System.Integer>', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('TList<Integer> · Count = 7 · [0, 10, 20, 30, 40, …]', mText);
  mOptions_ := Options(TAtlasVisualizerEvaluation.Fields);
  mOptions_.MaxLength := 20;
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Lists, 'Zahlen', 'TList<System.Integer>', '',
    mOptions_, Context);
  Assert.AreEqual(20, Length(mText));
  Assert.IsTrue(mText.EndsWith('…'));
  // Ausdrücke mit Index oder Dereferenzierung werden geklammert.
  FAsked.Clear;
  TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Lists, 'Listen[2]', 'TList<System.Integer>', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('(Listen[2]).Count', FAsked[0]);
end;

procedure TVisualizerTests.DictionaryPairs;
var
  mText: string;
  mView: TAtlasVisualizerView;
begin
  FValues.Add('D.Count', '2');
  FValues.Add('Length(D.FItems)', '4');
  FValues.Add('D.FItems[0].HashCode', '-1');
  FValues.Add('D.FItems[1].HashCode', '12345');
  FValues.Add('D.FItems[1].Key', '''a''');
  FValues.Add('D.FItems[1].Value', '1');
  FValues.Add('D.FItems[2].HashCode', '-1');
  FValues.Add('D.FItems[3].HashCode', '999');
  FValues.Add('D.FItems[3].Key', '''b''');
  FValues.Add('D.FItems[3].Value', '2');
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Dictionaries, 'D',
    'System.Generics.Collections.TDictionary<System.string,System.Integer>', '', Options(
    TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('TDictionary<string,Integer> · Count = 2 · {''a'': 1, ''b'': 2}', mText);
  mView := TAtlasVisualizers.View(TAtlasVisualizerKind.Dictionaries, 'D', 'TDictionary<string,Integer>', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual(2, Integer(Length(mView.Rows)));
  Assert.AreEqual('''b''', mView.Rows[1][0]);
  Assert.AreEqual('2', mView.Rows[1][1]);
  Assert.AreEqual(Ord(TAtlasVisualizerColumn.Key), Ord(mView.Columns[0]));
end;

procedure TVisualizerTests.DataSetInEdit;
var
  mText: string;
  mView: TAtlasVisualizerView;
begin
  FValues.Add('Q.State', 'dsEdit');
  FValues.Add('Q.RecNo', '3');
  FValues.Add('Q.RecordCount', '10');
  FValues.Add('Q.FieldCount', '2');
  FValues.Add('Q.Fields[0].FieldName', '''Name''');
  FValues.Add('Q.Fields[0].DisplayText', '''Meier''');
  FValues.Add('Q.Fields[0].DataType', 'ftWideString');
  FValues.Add('Q.Fields[0].OldValue', '''Maier''');
  FValues.Add('Q.Fields[1].FieldName', '''Ort''');
  FValues.Add('Q.Fields[1].AsString', '''Berlin''');
  FValues.Add('Q.Fields[1].DataType', 'ftWideString');
  FValues.Add('Q.Fields[1].OldValue', '''Berlin''');
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.DataSets, 'Q', 'FireDAC.Comp.Client.TFDQuery', '',
    Options(TAtlasVisualizerEvaluation.Properties), Context);
  Assert.AreEqual('TFDQuery · dsEdit · 3/10 · Name = Meier, Ort = Berlin', mText);
  mView := TAtlasVisualizers.View(TAtlasVisualizerKind.DataSets, 'Q', 'TFDQuery', '',
    Options(TAtlasVisualizerEvaluation.Properties), Context);
  Assert.AreEqual(2, Integer(Length(mView.Rows)));
  Assert.AreEqual('Name', mView.Rows[0][0]);
  Assert.AreEqual('ftWideString', mView.Rows[0][1]);
  Assert.AreEqual('Meier', mView.Rows[0][2]);
  Assert.AreEqual('Maier', mView.Rows[0][3]);
  Assert.AreEqual(4, Integer(Length(mView.Columns)));
  Assert.AreEqual(Ord(TAtlasVisualizerColumn.OldValue), Ord(mView.Columns[3]));
end;

procedure TVisualizerTests.DataSetFieldsOnly;
var
  mText: string;
  mView: TAtlasVisualizerView;
begin
  FValues.Add('Q.State', 'dsBrowse');
  FValues.Add('Q.RecNo', '3');
  FValues.Add('Q.FieldCount', '2');
  // Nur Felder: Getter wie RecNo und FieldCount werden gar nicht erst ausgewertet.
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.DataSets, 'Q', 'TFDQuery', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('TFDQuery · dsBrowse', mText);
  Assert.IsFalse(FAsked.Contains('Q.RecNo'));
  mView := TAtlasVisualizers.View(TAtlasVisualizerKind.DataSets, 'Q', 'TFDQuery', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.IsTrue(mView.NeedsMore);
end;

procedure TVisualizerTests.BytesHexAndView;
var
  mText: string;
  mView: TAtlasVisualizerView;
  mIndex: Integer;
begin
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Bytes, 'B', 'TBytes', '(72, 101, 108, 108, 111)',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('5 Bytes · 48 65 6C 6C 6F · Hello', mText);
  // 4096 Bytes: Länge und Anfang; das Fenster liest alles aus dem Speicher.
  SetLength(FMemory, 4096);
  for mIndex := 0 to High(FMemory) do
  begin
    FMemory[mIndex] := Byte(mIndex);
  end;
  FMemoryAddress := $10000;
  FValues.Add('Length(Gross)', '4096');
  FValues.Add('Pointer(Gross)', '$10000');
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Bytes, 'Gross', 'TArray<System.Byte>',
    '(0, 1, 2, 3, ...)', Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.IsTrue(mText.StartsWith('4096 Bytes · 00 01 02 03 04'), mText);
  Assert.IsTrue(mText.EndsWith('…'), mText);
  mView := TAtlasVisualizers.View(TAtlasVisualizerKind.Bytes, 'Gross', 'TBytes', '(0, 1, 2, 3, ...)',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Hex), Ord(mView.Mode));
  Assert.AreEqual(4096, Integer(Length(mView.Bytes)));
  Assert.AreEqual(Int64(4096), mView.Total);
end;

procedure TVisualizerTests.MemoryStream;
var
  mText: string;
begin
  FMemory := TEncoding.ASCII.GetBytes('Atlas');
  FMemoryAddress := $2000;
  FValues.Add('S.FSize', '5');
  FValues.Add('S.FMemory', 'Pointer($2000)');
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Bytes, 'S', 'System.Classes.TMemoryStream',
    '($...)', Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('TMemoryStream · 5 Bytes · 41 74 6C 61 73 · Atlas', mText);
  // Ohne Größe bleibt der Text der IDE.
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Bytes, 'F', 'TFileStream', '($...)',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('', mText);
end;

procedure TVisualizerTests.JsonWithCallsAndWithout;
var
  mText: string;
  mView: TAtlasVisualizerView;
begin
  FValues.Add('J.ToJSON', '''{"name": "Meier", "nr": 4711}''');
  FValues.Add('J.FMembers.FListHelper.FCount', '2');
  FValues.Add('J.FMembers.FItems[0].FJsonString.FValue', '''name''');
  FValues.Add('J.FMembers.FItems[1].FJsonString.FValue', '''nr''');
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Json, 'J', 'System.JSON.TJSONObject', '',
    Options(TAtlasVisualizerEvaluation.Calls), Context);
  Assert.AreEqual('{"name":"Meier","nr":4711}', mText);
  FAsked.Clear;
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Json, 'J', 'System.JSON.TJSONObject', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('TJSONObject · Count = 2 · {name, nr}', mText);
  Assert.IsFalse(FAsked.Contains('J.ToJSON'), 'ToJSON nur mit Aufrufen');
  mView := TAtlasVisualizers.View(TAtlasVisualizerKind.Json, 'J', 'TJSONObject', '',
    Options(TAtlasVisualizerEvaluation.Calls), Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Tree), Ord(mView.Mode));
  Assert.AreEqual(3, Integer(Length(mView.Nodes)));
end;

procedure TVisualizerTests.JsonTreeNodes;
var
  mNodes: TArray<TAtlasVisualizerNode>;
begin
  Assert.AreEqual('{"a":[1,2],"b":"x y"}', TAtlasVisualizerFormat.CompactJson('{ "a" : [1, 2],'#13#10' "b": "x y" }'));
  Assert.IsTrue(TAtlasVisualizerFormat.JsonTree('{"a":[1,2],"b":{"c":true}}', mNodes));
  Assert.AreEqual(6, Integer(Length(mNodes)));
  Assert.AreEqual('{2}', mNodes[0].Text);
  Assert.AreEqual('a: [2]', mNodes[1].Text);
  Assert.AreEqual(2, mNodes[2].Level);
  Assert.AreEqual('[0]: 1', mNodes[2].Text);
  Assert.AreEqual('c: true', mNodes[5].Text);
  Assert.IsFalse(TAtlasVisualizerFormat.JsonTree('{kaputt', mNodes));
end;

procedure TVisualizerTests.Colors;
var
  mText: string;
  mView: TAtlasVisualizerView;
begin
  // clWebDodgerBlue = $FF901E (BGR).
  Assert.AreEqual('clWebDodgerBlue', TAtlasVisualizerFormat.ColorName($FF901E));
  Assert.AreEqual('clWebDodgerBlue · $1E90FF', TAtlasVisualizerFormat.ColorText($FF901E));
  Assert.AreEqual('clRed · $FF0000', TAtlasVisualizerFormat.ColorText($0000FF));
  Assert.AreEqual('clBtnFace', TAtlasVisualizerFormat.ColorText(-16777201));
  Assert.AreEqual('clNone', TAtlasVisualizerFormat.ColorText($1FFFFFFF));
  Assert.AreEqual('$123456', TAtlasVisualizerFormat.ColorText($563412));
  Assert.AreEqual('claDodgerBlue · $FF1E90FF', TAtlasVisualizerFormat.AlphaColorText($FF1E90FF));
  Assert.AreEqual('$801E90FF', TAtlasVisualizerFormat.AlphaColorText($801E90FF));
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Colors, 'C', 'System.UITypes.TColor', '16748574',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('clWebDodgerBlue · $1E90FF', mText);
  mView := TAtlasVisualizers.View(TAtlasVisualizerKind.Colors, 'C', 'TColor', '16748574',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Color), Ord(mView.Mode));
  Assert.AreEqual(Int64($1E90FF), Int64(mView.Color));
  mView := TAtlasVisualizers.View(TAtlasVisualizerKind.Colors, 'C', 'TColor', '-16777201',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Text), Ord(mView.Mode), 'Systemfarbe ohne festes RGB');
end;

procedure TVisualizerTests.GuidAndGeometry;
begin
  Assert.AreEqual('{12345678-9ABC-DEF0-0102-030405060708}', TAtlasVisualizerFormat.GuidText(
    '(D1:305419896; D2:39612; D3:57072; D4:(1, 2, 3, 4, 5, 6, 7, 8))'));
  Assert.AreEqual('', TAtlasVisualizerFormat.GuidText('(D1:1)'));
  Assert.AreEqual('(10, 20)', TAtlasVisualizerFormat.GeometryText('TPoint', '(X:10; Y:20)'));
  Assert.AreEqual('(10, 20)–(110, 70)', TAtlasVisualizerFormat.GeometryText('TRect',
    '(Left:10; Top:20; Right:110; Bottom:70; TopLeft:(X:10; Y:20); BottomRight:(X:110; Y:70))'));
  Assert.AreEqual('100 × 50', TAtlasVisualizerFormat.GeometryText('TSize', '(cx:100; cy:50)'));
  Assert.AreEqual('(1.5, 2)', TAtlasVisualizerFormat.GeometryText('TPointF', '(X:1.5; Y:2.0)'));
  Assert.AreEqual('(10, 20)', TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Geometry, 'P', 'System.Types.TPoint',
    '(X:10; Y:20)', TAtlasVisualizerOptions.Defaults, Context));
end;

procedure TVisualizerTests.BitmapImage;
var
  mText: string;
  mView: TAtlasVisualizerView;
  mOptions_: TAtlasVisualizerOptions;
begin
  // 2 × 2, 24 Bit, Zeilen auf 8 Bytes ausgerichtet, von unten nach oben.
  FMemory := TBytes.Create(
    0, 0, 255, 0, 255, 0, 0, 0,
    255, 0, 0, 255, 255, 255, 0, 0);
  FMemoryAddress := $3000;
  FValues.Add('B.FImage.FDIB.dsBm.bmWidth', '2');
  FValues.Add('B.FImage.FDIB.dsBm.bmHeight', '2');
  FValues.Add('B.FImage.FDIB.dsBm.bmBitsPixel', '24');
  FValues.Add('B.FImage.FDIB.dsBm.bmWidthBytes', '8');
  FValues.Add('B.FImage.FDIB.dsBm.bmBits', '$3000');
  FValues.Add('B.FPixelFormat', 'pf24bit');
  mText := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Graphics, 'B', 'Vcl.Graphics.TBitmap', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('TBitmap · 2 × 2 · pf24bit', mText);
  mView := TAtlasVisualizers.View(TAtlasVisualizerKind.Graphics, 'B', 'TBitmap', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Image), Ord(mView.Mode));
  Assert.AreEqual(2, mView.Width);
  // Oben links: Blau (zweite Zeile im Speicher).
  Assert.AreEqual(Int64($FF0000FF), Int64(mView.Pixels[0]));
  Assert.AreEqual(Int64($FFFF0000), Int64(mView.Pixels[2]));
  // Zu groß für maxImagePixels: nur Text.
  mOptions_ := Options(TAtlasVisualizerEvaluation.Fields);
  mOptions_.MaxImagePixels := 3;
  mView := TAtlasVisualizers.View(TAtlasVisualizerKind.Graphics, 'B', 'TBitmap', '', mOptions_, Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Text), Ord(mView.Mode));
end;

procedure TVisualizerTests.DibPixelsBottomUp;
var
  mPixels: TArray<Cardinal>;
begin
  Assert.IsTrue(TAtlasVisualizerFormat.DibPixels(TBytes.Create(1, 2, 3, 128), TAtlasDibLayout.Create(1, 1, 32, 4,
    False), mPixels));
  Assert.AreEqual(Int64($80030201), Int64(mPixels[0]));
  Assert.IsFalse(TAtlasVisualizerFormat.DibPixels(TBytes.Create(1, 2), TAtlasDibLayout.Create(1, 1, 8, 4, False),
    mPixels), '8 Bit');
  Assert.IsFalse(TAtlasVisualizerFormat.DibPixels(TBytes.Create(1, 2, 3), TAtlasDibLayout.Create(2, 1, 24, 6,
    False), mPixels), 'zu kurz');
end;

procedure TVisualizerTests.HexLines;
var
  mBytes: TBytes;
  mLine: string;
begin
  mBytes := TEncoding.ASCII.GetBytes('Hello, Atlas! 0123456789');
  Assert.AreEqual(2, TAtlasVisualizerFormat.HexLineCount(Length(mBytes)));
  mLine := TAtlasVisualizerFormat.HexLine(mBytes, 0);
  Assert.IsTrue(mLine.StartsWith('00000000  48 65 6C 6C 6F 2C 20 41  74'), mLine);
  Assert.IsTrue(mLine.EndsWith('Hello, Atlas! 01'), mLine);
  mLine := TAtlasVisualizerFormat.HexLine(mBytes, 16);
  Assert.IsTrue(mLine.StartsWith('00000010  32 33'), mLine);
  Assert.IsTrue(mLine.EndsWith('23456789'), mLine);
  Assert.AreEqual('3 Bytes · 01 0A 41 · ..A', TAtlasVisualizerFormat.HexPreview(TBytes.Create(1, 10, 65), 3, 16));
  Assert.AreEqual('0 Bytes', TAtlasVisualizerFormat.HexPreview(nil, 0, 16));
end;

procedure TVisualizerTests.KindSwitchedOff;
var
  mOptions_: TAtlasVisualizerOptions;
begin
  mOptions_ := TAtlasVisualizerOptions.Defaults;
  mOptions_.Kinds := [TAtlasVisualizerKind.Lists];
  Assert.AreEqual('', TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Colors, 'C', 'TColor', '255', mOptions_,
    Context));
  Assert.AreEqual(0, Integer(FAsked.Count), 'Abgeschaltet: keine Auswertung');
end;
procedure TVisualizerTests.KindFromHoverChain;
var
  mKind: TAtlasVisualizerKind;
begin
  // Typkette des Hovers (Typ aus der Deklaration, dann die Vorfahren; TAtlasHoverDeclaration rechnet den Typ).
  Assert.IsTrue(TAtlasVisualizers.KindOfChain(['TFDQuery', 'TFDQuery',
    'TFDCustomQuery', 'TDataSet'], mKind));
  Assert.AreEqual(Ord(TAtlasVisualizerKind.DataSets), Ord(mKind));
end;

initialization
  TDUnitX.RegisterTestFixture(TVisualizerTests);

end.
