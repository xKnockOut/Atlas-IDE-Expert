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
  Atlas.Core.Debug.Visualizers;

type
  [TestFixture]
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
    procedure DeclaredTypeFromHover;
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
  Values: TDictionary<string, string>;
  Asked: TList<string>;
  Self_: TVisualizerTests;
begin
  Values := FValues;
  Asked := FAsked;
  Self_ := Self;
  Result.Eval :=
    function(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation; out AText: string): Boolean
    begin
      Asked.Add(AExpression);
      Result := Values.TryGetValue(AExpression, AText);
    end;
  Result.Read :=
    function(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean
    begin
      Result := (AAddress = Self_.FMemoryAddress) and (ACount <= Length(Self_.FMemory));
      ABytes := nil;
      if Result then
        ABytes := Copy(Self_.FMemory, 0, ACount);
    end;
end;

function TVisualizerTests.Options(AEvaluation: TAtlasVisualizerEvaluation): TAtlasVisualizerOptions;
begin
  Result := TAtlasVisualizerOptions.Defaults;
  Result.Evaluation := AEvaluation;
end;

procedure TVisualizerTests.KindsAndSettings;
var
  Fields: TArray<string>;
begin
  Assert.AreEqual('lists,json,colors', TAtlasVisualizers.NormalizeKinds(' Colors, lists ;JSON, unbekannt'));
  Assert.AreEqual('', TAtlasVisualizers.NormalizeKinds(''));
  Assert.IsTrue(TAtlasVisualizerKind.Graphics in TAtlasVisualizerOptions.Defaults.Kinds);
  Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Calls), Ord(TAtlasVisualizers.ParseEvaluation('CALLS')));
  Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Properties), Ord(TAtlasVisualizers.ParseEvaluation('quatsch')));
  Fields := TAtlasVisualizers.ParseNameFields(' Name, caption,, NAME, 1x, Text');
  Assert.AreEqual(3, Integer(Length(Fields)));
  Assert.AreEqual('Name,caption,Text', TAtlasVisualizers.NormalizeNameFields(' Name, caption,, NAME, 1x, Text'));
  Assert.AreEqual(120, TAtlasVisualizerOptions.Defaults.MaxLength);
  Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Properties), Ord(TAtlasVisualizerOptions.Defaults.Evaluation));
end;

procedure TVisualizerTests.TypeNames;
var
  Kind: TAtlasVisualizerKind;
begin
  Assert.AreEqual('TObjectList<TKunde>',
    TAtlasVisualizers.ShortTypeName('System.Generics.Collections.TObjectList<Unit1.TKunde>'));
  Assert.AreEqual('TDictionary<string,TPair<Integer,TKunde>>',
    TAtlasVisualizers.ShortTypeName('TDictionary<System.string, TPair<System.Integer, Kunden.TKunde>>'));
  Assert.AreEqual('TList', TAtlasVisualizers.BaseTypeName('System.Generics.Collections.TList<Unit1.TKunde>'));
  Assert.IsTrue(TAtlasVisualizers.KindOf('TObjectList<TKunde>', Kind));
  Assert.AreEqual(Ord(TAtlasVisualizerKind.Lists), Ord(Kind));
  // Die alte TList ohne Typargumente ist keine generische Liste.
  Assert.IsFalse(TAtlasVisualizers.KindOf('System.Classes.TList', Kind));
  Assert.IsTrue(TAtlasVisualizers.KindOf('TArray<System.Byte>', Kind));
  Assert.AreEqual(Ord(TAtlasVisualizerKind.Bytes), Ord(Kind));
  Assert.IsTrue(TAtlasVisualizers.KindOf('Vcl.Graphics.TColor', Kind));
  Assert.AreEqual(Ord(TAtlasVisualizerKind.Colors), Ord(Kind));
  // TDateTime und TStrings bleiben bei der IDE.
  Assert.IsFalse(TAtlasVisualizers.KindOf('TDateTime', Kind));
  Assert.IsFalse(TAtlasVisualizers.KindOf('TStringList', Kind));
  // Nachfahren über die Kette.
  Assert.IsFalse(TAtlasVisualizers.KindOf('TKundenQuery', Kind));
  Assert.IsTrue(TAtlasVisualizers.KindOfChain(['TKundenQuery', 'TFDQuery', 'TFDCustomQuery'], Kind));
  Assert.AreEqual(Ord(TAtlasVisualizerKind.DataSets), Ord(Kind));
end;

procedure TVisualizerTests.SupportedTypesHaveUnitAndGenerics;
var
  Types: TArray<TAtlasVisualizerType>;
  Item: TAtlasVisualizerType;
  Found: Boolean;
  Kind: TAtlasVisualizerKind;
begin
  Types := TAtlasVisualizers.SupportedTypes(TAtlasVisualizerKind.Lists);
  Found := False;
  for Item in Types do
    if Item.TypeName = 'System.Generics.Collections.TObjectList<T>' then
    begin
      Found := True;
      Assert.IsTrue(Item.IsGeneric);
      Assert.IsTrue(Item.AllDescendants);
    end;
  Assert.IsTrue(Found);
  for Kind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
    Assert.IsTrue(Length(TAtlasVisualizers.SupportedTypes(Kind)) > 0, TAtlasVisualizers.KindNames[Kind]);
  Found := False;
  for Item in TAtlasVisualizers.SupportedTypes(TAtlasVisualizerKind.DataSets) do
    if (Item.TypeName = 'Data.DB.TDataSet') and Item.AllDescendants and not Item.IsGeneric then
      Found := True;
  Assert.IsTrue(Found, 'TDataSet samt Nachfahren');
end;

procedure TVisualizerTests.ParseFieldsAndNumbers;
var
  Fields: TArray<TAtlasDebugField>;
  Value: string;
  Number: Int64;
  Address: UInt64;
  Bytes: TBytes;
begin
  Assert.IsTrue(TAtlasVisualizerFormat.ParseFields('(X:10; Y: 20; Name: ''a;b''; Inner:(1, 2))', Fields));
  Assert.AreEqual(4, Integer(Length(Fields)));
  Assert.IsTrue(TAtlasVisualizerFormat.FieldValue(Fields, 'y', Value));
  Assert.AreEqual('20', Value);
  Assert.IsTrue(TAtlasVisualizerFormat.FieldValue(Fields, 'Name', Value));
  Assert.AreEqual('''a;b''', Value);
  Assert.IsTrue(TAtlasVisualizerFormat.FieldValue(Fields, 'Inner', Value));
  Assert.AreEqual('(1, 2)', Value);
  Assert.IsFalse(TAtlasVisualizerFormat.ParseFields('42', Fields));
  Assert.IsTrue(TAtlasVisualizerFormat.ParseInteger(' -16777201 ', Number));
  Assert.AreEqual(Int64(-16777201), Number);
  Assert.IsTrue(TAtlasVisualizerFormat.ParseInteger('$FF', Number));
  Assert.AreEqual(Int64(255), Number);
  Assert.IsTrue(TAtlasVisualizerFormat.ParseInteger('Pointer($1F)', Number));
  Assert.AreEqual(Int64(31), Number);
  Assert.IsFalse(TAtlasVisualizerFormat.ParseInteger('''abc''', Number));
  Assert.IsTrue(TAtlasVisualizerFormat.ParseAddress(':0A3F1C20', Address));
  Assert.IsTrue(Address = $0A3F1C20, 'Adresse');
  Assert.IsFalse(TAtlasVisualizerFormat.ParseAddress('nil', Address));
  Assert.IsTrue(TAtlasVisualizerFormat.ParseAddress('$FFFF800000001000', Address), 'höchstes Bit gesetzt');
  Assert.IsTrue(TAtlasVisualizerFormat.ParseByteList('(72, 101, $6C)', Bytes));
  Assert.AreEqual(3, Integer(Length(Bytes)));
  Assert.AreEqual(108, Integer(Bytes[2]));
  Assert.IsTrue(TAtlasVisualizerFormat.ParseByteList('()', Bytes));
  Assert.AreEqual(0, Integer(Length(Bytes)));
  Assert.IsFalse(TAtlasVisualizerFormat.ParseByteList('(1, 300)', Bytes));
  Assert.IsFalse(TAtlasVisualizerFormat.ParseByteList('(X:1)', Bytes));
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
  Text: string;
  View: TAtlasVisualizerView;
begin
  FValues.Add('Kunden.Count', '3');
  FValues.Add('Kunden.List[0]', '($0A3F1C20)');
  FValues.Add('Kunden.List[1]', '($0A3F1C40)');
  FValues.Add('Kunden.List[2]', '($0A3F1C60)');
  FValues.Add('Kunden.List[0].Name', '''Meier''');
  FValues.Add('Kunden.List[1].Name', '''Schulz''');
  FValues.Add('Kunden.List[2].Name', '''Öztürk''');
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Lists, 'Kunden',
    'System.Generics.Collections.TObjectList<Unit1.TKunde>', '(...)', Options(TAtlasVisualizerEvaluation.Fields),
    Context);
  Assert.AreEqual('TObjectList<TKunde> · Count = 3 · [Meier, Schulz, Öztürk]', Text);
  View := TAtlasVisualizers.View(TAtlasVisualizerKind.Lists, 'Kunden', 'TObjectList<TKunde>', '(...)',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Table), Ord(View.Mode));
  Assert.AreEqual(3, Integer(Length(View.Rows)));
  Assert.AreEqual('Schulz', View.Rows[1][1]);
  Assert.AreEqual(Int64(3), View.Total);
  // Kürzen auf maxLength.
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Lists, 'Kunden', 'TObjectList<TKunde>', '',
    TAtlasVisualizerOptions.Defaults, Context);
  Assert.AreEqual('TObjectList<TKunde> · Count = 3 · [Meier, Schulz, Öztürk]', Text);
end;

procedure TVisualizerTests.ListOfSimpleValuesAndFieldFallback;
var
  Options_: TAtlasVisualizerOptions;
  Text: string;
  Index: Integer;
begin
  // Count nur über das Feld der Hilfsstruktur, Elemente über FItems, sieben Einträge: fünf und „…“.
  FValues.Add('Zahlen.FListHelper.FCount', '7');
  for Index := 0 to 6 do
    FValues.Add(Format('Zahlen.FItems[%d]', [Index]), IntToStr(Index * 10));
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Lists, 'Zahlen', 'TList<System.Integer>', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('TList<Integer> · Count = 7 · [0, 10, 20, 30, 40, …]', Text);
  Options_ := Options(TAtlasVisualizerEvaluation.Fields);
  Options_.MaxLength := 20;
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Lists, 'Zahlen', 'TList<System.Integer>', '',
    Options_, Context);
  Assert.AreEqual(20, Length(Text));
  Assert.IsTrue(Text.EndsWith('…'));
  // Ausdrücke mit Index oder Dereferenzierung werden geklammert.
  FAsked.Clear;
  TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Lists, 'Listen[2]', 'TList<System.Integer>', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('(Listen[2]).Count', FAsked[0]);
end;

procedure TVisualizerTests.DictionaryPairs;
var
  Text: string;
  View: TAtlasVisualizerView;
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
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Dictionaries, 'D',
    'System.Generics.Collections.TDictionary<System.string,System.Integer>', '', Options(
    TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('TDictionary<string,Integer> · Count = 2 · {''a'': 1, ''b'': 2}', Text);
  View := TAtlasVisualizers.View(TAtlasVisualizerKind.Dictionaries, 'D', 'TDictionary<string,Integer>', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual(2, Integer(Length(View.Rows)));
  Assert.AreEqual('''b''', View.Rows[1][0]);
  Assert.AreEqual('2', View.Rows[1][1]);
  Assert.AreEqual(Ord(TAtlasVisualizerColumn.Key), Ord(View.Columns[0]));
end;

procedure TVisualizerTests.DataSetInEdit;
var
  Text: string;
  View: TAtlasVisualizerView;
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
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.DataSets, 'Q', 'FireDAC.Comp.Client.TFDQuery', '',
    Options(TAtlasVisualizerEvaluation.Properties), Context);
  Assert.AreEqual('TFDQuery · dsEdit · 3/10 · Name = Meier, Ort = Berlin', Text);
  View := TAtlasVisualizers.View(TAtlasVisualizerKind.DataSets, 'Q', 'TFDQuery', '',
    Options(TAtlasVisualizerEvaluation.Properties), Context);
  Assert.AreEqual(2, Integer(Length(View.Rows)));
  Assert.AreEqual('Name', View.Rows[0][0]);
  Assert.AreEqual('ftWideString', View.Rows[0][1]);
  Assert.AreEqual('Meier', View.Rows[0][2]);
  Assert.AreEqual('Maier', View.Rows[0][3]);
  Assert.AreEqual(4, Integer(Length(View.Columns)));
  Assert.AreEqual(Ord(TAtlasVisualizerColumn.OldValue), Ord(View.Columns[3]));
end;

procedure TVisualizerTests.DataSetFieldsOnly;
var
  Text: string;
  View: TAtlasVisualizerView;
begin
  FValues.Add('Q.State', 'dsBrowse');
  FValues.Add('Q.RecNo', '3');
  FValues.Add('Q.FieldCount', '2');
  // Nur Felder: Getter wie RecNo und FieldCount werden gar nicht erst ausgewertet.
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.DataSets, 'Q', 'TFDQuery', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('TFDQuery · dsBrowse', Text);
  Assert.IsFalse(FAsked.Contains('Q.RecNo'));
  View := TAtlasVisualizers.View(TAtlasVisualizerKind.DataSets, 'Q', 'TFDQuery', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.IsTrue(View.NeedsMore);
end;

procedure TVisualizerTests.BytesHexAndView;
var
  Text: string;
  View: TAtlasVisualizerView;
  Index: Integer;
begin
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Bytes, 'B', 'TBytes', '(72, 101, 108, 108, 111)',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('5 Bytes · 48 65 6C 6C 6F · Hello', Text);
  // 4096 Bytes: Länge und Anfang; das Fenster liest alles aus dem Speicher.
  SetLength(FMemory, 4096);
  for Index := 0 to High(FMemory) do
    FMemory[Index] := Byte(Index);
  FMemoryAddress := $10000;
  FValues.Add('Length(Gross)', '4096');
  FValues.Add('Pointer(Gross)', '$10000');
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Bytes, 'Gross', 'TArray<System.Byte>',
    '(0, 1, 2, 3, ...)', Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.IsTrue(Text.StartsWith('4096 Bytes · 00 01 02 03 04'), Text);
  Assert.IsTrue(Text.EndsWith('…'), Text);
  View := TAtlasVisualizers.View(TAtlasVisualizerKind.Bytes, 'Gross', 'TBytes', '(0, 1, 2, 3, ...)',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Hex), Ord(View.Mode));
  Assert.AreEqual(4096, Integer(Length(View.Bytes)));
  Assert.AreEqual(Int64(4096), View.Total);
end;

procedure TVisualizerTests.MemoryStream;
var
  Text: string;
begin
  FMemory := TEncoding.ASCII.GetBytes('Atlas');
  FMemoryAddress := $2000;
  FValues.Add('S.FSize', '5');
  FValues.Add('S.FMemory', 'Pointer($2000)');
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Bytes, 'S', 'System.Classes.TMemoryStream',
    '($...)', Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('TMemoryStream · 5 Bytes · 41 74 6C 61 73 · Atlas', Text);
  // Ohne Größe bleibt der Text der IDE.
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Bytes, 'F', 'TFileStream', '($...)',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('', Text);
end;

procedure TVisualizerTests.JsonWithCallsAndWithout;
var
  Text: string;
  View: TAtlasVisualizerView;
begin
  FValues.Add('J.ToJSON', '''{"name": "Meier", "nr": 4711}''');
  FValues.Add('J.FMembers.FListHelper.FCount', '2');
  FValues.Add('J.FMembers.FItems[0].FJsonString.FValue', '''name''');
  FValues.Add('J.FMembers.FItems[1].FJsonString.FValue', '''nr''');
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Json, 'J', 'System.JSON.TJSONObject', '',
    Options(TAtlasVisualizerEvaluation.Calls), Context);
  Assert.AreEqual('{"name":"Meier","nr":4711}', Text);
  FAsked.Clear;
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Json, 'J', 'System.JSON.TJSONObject', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('TJSONObject · Count = 2 · {name, nr}', Text);
  Assert.IsFalse(FAsked.Contains('J.ToJSON'), 'ToJSON nur mit Aufrufen');
  View := TAtlasVisualizers.View(TAtlasVisualizerKind.Json, 'J', 'TJSONObject', '',
    Options(TAtlasVisualizerEvaluation.Calls), Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Tree), Ord(View.Mode));
  Assert.AreEqual(3, Integer(Length(View.Nodes)));
end;

procedure TVisualizerTests.JsonTreeNodes;
var
  Nodes: TArray<TAtlasVisualizerNode>;
begin
  Assert.AreEqual('{"a":[1,2],"b":"x y"}', TAtlasVisualizerFormat.CompactJson('{ "a" : [1, 2],'#13#10' "b": "x y" }'));
  Assert.IsTrue(TAtlasVisualizerFormat.JsonTree('{"a":[1,2],"b":{"c":true}}', Nodes));
  Assert.AreEqual(6, Integer(Length(Nodes)));
  Assert.AreEqual('{2}', Nodes[0].Text);
  Assert.AreEqual('a: [2]', Nodes[1].Text);
  Assert.AreEqual(2, Nodes[2].Level);
  Assert.AreEqual('[0]: 1', Nodes[2].Text);
  Assert.AreEqual('c: true', Nodes[5].Text);
  Assert.IsFalse(TAtlasVisualizerFormat.JsonTree('{kaputt', Nodes));
end;

procedure TVisualizerTests.Colors;
var
  Text: string;
  View: TAtlasVisualizerView;
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
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Colors, 'C', 'System.UITypes.TColor', '16748574',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('clWebDodgerBlue · $1E90FF', Text);
  View := TAtlasVisualizers.View(TAtlasVisualizerKind.Colors, 'C', 'TColor', '16748574',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Color), Ord(View.Mode));
  Assert.AreEqual(Int64($1E90FF), Int64(View.Color));
  View := TAtlasVisualizers.View(TAtlasVisualizerKind.Colors, 'C', 'TColor', '-16777201',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Text), Ord(View.Mode), 'Systemfarbe ohne festes RGB');
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
  Text: string;
  View: TAtlasVisualizerView;
  Options_: TAtlasVisualizerOptions;
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
  Text := TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Graphics, 'B', 'Vcl.Graphics.TBitmap', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual('TBitmap · 2 × 2 · pf24bit', Text);
  View := TAtlasVisualizers.View(TAtlasVisualizerKind.Graphics, 'B', 'TBitmap', '',
    Options(TAtlasVisualizerEvaluation.Fields), Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Image), Ord(View.Mode));
  Assert.AreEqual(2, View.Width);
  // Oben links: Blau (zweite Zeile im Speicher).
  Assert.AreEqual(Int64($FF0000FF), Int64(View.Pixels[0]));
  Assert.AreEqual(Int64($FFFF0000), Int64(View.Pixels[2]));
  // Zu groß für maxImagePixels: nur Text.
  Options_ := Options(TAtlasVisualizerEvaluation.Fields);
  Options_.MaxImagePixels := 3;
  View := TAtlasVisualizers.View(TAtlasVisualizerKind.Graphics, 'B', 'TBitmap', '', Options_, Context);
  Assert.AreEqual(Ord(TAtlasVisualizerViewMode.Text), Ord(View.Mode));
end;

procedure TVisualizerTests.DibPixelsBottomUp;
var
  Pixels: TArray<Cardinal>;
begin
  Assert.IsTrue(TAtlasVisualizerFormat.DibPixels(TBytes.Create(1, 2, 3, 128), 1, 1, 32, 4, False, Pixels));
  Assert.AreEqual(Int64($80030201), Int64(Pixels[0]));
  Assert.IsFalse(TAtlasVisualizerFormat.DibPixels(TBytes.Create(1, 2), 1, 1, 8, 4, False, Pixels), '8 Bit');
  Assert.IsFalse(TAtlasVisualizerFormat.DibPixels(TBytes.Create(1, 2, 3), 2, 1, 24, 6, False, Pixels), 'zu kurz');
end;

procedure TVisualizerTests.HexLines;
var
  Bytes: TBytes;
  Line: string;
begin
  Bytes := TEncoding.ASCII.GetBytes('Hello, Atlas! 0123456789');
  Assert.AreEqual(2, TAtlasVisualizerFormat.HexLineCount(Length(Bytes)));
  Line := TAtlasVisualizerFormat.HexLine(Bytes, 0);
  Assert.IsTrue(Line.StartsWith('00000000  48 65 6C 6C 6F 2C 20 41  74'), Line);
  Assert.IsTrue(Line.EndsWith('Hello, Atlas! 01'), Line);
  Line := TAtlasVisualizerFormat.HexLine(Bytes, 16);
  Assert.IsTrue(Line.StartsWith('00000010  32 33'), Line);
  Assert.IsTrue(Line.EndsWith('23456789'), Line);
  Assert.AreEqual('3 Bytes · 01 0A 41 · ..A', TAtlasVisualizerFormat.HexPreview(TBytes.Create(1, 10, 65), 3, 16));
  Assert.AreEqual('0 Bytes', TAtlasVisualizerFormat.HexPreview(nil, 0, 16));
end;

procedure TVisualizerTests.KindSwitchedOff;
var
  Options_: TAtlasVisualizerOptions;
begin
  Options_ := TAtlasVisualizerOptions.Defaults;
  Options_.Kinds := [TAtlasVisualizerKind.Lists];
  Assert.AreEqual('', TAtlasVisualizers.Replacement(TAtlasVisualizerKind.Colors, 'C', 'TColor', '255', Options_,
    Context));
  Assert.AreEqual(0, FAsked.Count, 'Abgeschaltet: keine Auswertung');
end;
procedure TVisualizerTests.DeclaredTypeFromHover;
var
  Kind: TAtlasVisualizerKind;
begin
  Assert.AreEqual('TObjectList<TKunde>', TAtlasVisualizers.DeclaredType('var Kunden: TObjectList<TKunde>'));
  Assert.AreEqual('TList<Integer>', TAtlasVisualizers.DeclaredType('property Items: TList<Integer> read FItems'));
  Assert.AreEqual('TPoint', TAtlasVisualizers.DeclaredType('function Mitte(A, B: Integer): TPoint;'));
  Assert.AreEqual('TDictionary<string, TKunde>',
    TAtlasVisualizers.DeclaredType('Index: TDictionary<string, TKunde> = nil'));
  Assert.AreEqual('System.SysUtils.TBytes', TAtlasVisualizers.DeclaredType('Daten: System.SysUtils.TBytes;'));
  Assert.AreEqual('array of Byte', TAtlasVisualizers.DeclaredType('Puffer: array of Byte'));
  Assert.AreEqual('TÜbersicht', TAtlasVisualizers.DeclaredType('Ü: TÜbersicht'));
  Assert.AreEqual('', TAtlasVisualizers.DeclaredType('procedure Speichern'));
  // Hover → Art: Typ aus der Deklaration, dann die Vorfahren.
  Assert.IsTrue(TAtlasVisualizers.KindOfChain([TAtlasVisualizers.DeclaredType('Q: TFDQuery'), 'TFDQuery',
    'TFDCustomQuery', 'TDataSet'], Kind));
  Assert.AreEqual(Ord(TAtlasVisualizerKind.DataSets), Ord(Kind));
end;

initialization
  TDUnitX.RegisterTestFixture(TVisualizerTests);

end.
