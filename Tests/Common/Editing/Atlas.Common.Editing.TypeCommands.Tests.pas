unit Atlas.Common.Editing.TypeCommands.Tests;

// Tests für die Schnellbefehle /enum, /helper, /singleton, /encapsulate, /assign und /json (#298).
// /json gegen die Golden-Datei Atlas.Common.Editing.TypeCommands.JsonGolden, die zugleich übersetzt
// wird und den Rundweg FromJson(ToJson(X)) prüft.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeCommandsTests = class
  public
    [Test]
    procedure EnumWithPrefixInTypeSection;
    [Test]
    procedure EnumWithoutTypeSection;
    [Test]
    procedure EnumWithNamesReopensType;
    [Test]
    procedure EnumInRoutineFails;
    [Test]
    procedure HelperForRecordAndClass;
    [Test]
    procedure HelperInRoutineFails;
    [Test]
    procedure HelperForEnumAddsNamesAndConversion;
    [Test]
    procedure HelperForEnumSwitchedOff;
    /// <summary>#875: Mengen bekommen Contains, ToText, Toggle und All.</summary>
    [Test]
    procedure HelperForSetAddsMethods;
    [Test]
    procedure HelperForSetWithoutKnownValuesUsesRtti;
    [Test]
    procedure HelperForSetSwitchedOff;
    [Test]
    procedure SingletonAddsInstance;
    [Test]
    procedure SingletonOutsideClassFails;
    [Test]
    procedure SingletonNamesExistingConstructor;
    [Test]
    procedure EncapsulateMakesProperty;
    [Test]
    procedure EncapsulatePrivateFieldFails;
    [Test]
    procedure EncapsulateKeepsUsesOutsideClass;
    [Test]
    procedure AssignCopiesFields;
    [Test]
    procedure AssignOutsideClassFails;
    [Test]
    procedure JsonForSimpleFields;
    [Test]
    procedure JsonOutsideTypeFails;
    [Test]
    procedure JsonMatchesGoldenFile;
    [Test]
    procedure JsonRoundTripKeepsValues;
    [Test]
    procedure ThreadWithoutTypeSection;
    [Test]
    procedure ThreadInClassFails;
    [Test]
    procedure ExceptionWithAndWithoutAncestor;
    [Test]
    procedure ExceptionInRoutineFails;
    [Test]
    procedure ResultsParseWithoutErrors;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.TypeCommands,
  Atlas.Common.Editing.TypeCommands.JsonGolden,
  Atlas.Tests.SlashHost;

function Run(const AText: string; ALine: Integer; out AEdits: TArray<TRuleEdit>): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, AEdits);
end;

/// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
function Apply(const AText: string; AEdits: TArray<TRuleEdit>): string;
var
  mLines: TArray<string>;
  mEdit: TRuleEdit;
  mOffsets: TArray<Integer>;
  mIndex, mStart, mStop: Integer;
begin
  mLines := AText.Split([#10]);
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for mEdit in AEdits do
  begin
    mStart := mOffsets[mEdit.Range.StartPos.Line] + mEdit.Range.StartPos.Character;
    mStop := mOffsets[mEdit.Range.EndPos.Line] + mEdit.Range.EndPos.Character;
    Result := Copy(Result, 1, mStart) + mEdit.NewText + Copy(Result, mStop + 1, MaxInt);
  end;
end;

function Expand(const AText: string; ALine: Integer): string;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(AText, ALine, mEdits), AText);
  Result := Apply(AText, mEdits);
end;

function ProblemOf(const AText: string): string;
var
  mProblems: TArray<TSlashProblem>;
begin
  mProblems := TSlashCommandRegistry.Shared.Problems(AText, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Result := mProblems[0].Message;
end;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

const
  cClassUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'uses'#10 +                                     // 2
    '  System.Classes;'#10 +                        // 3
    'type'#10 +                                     // 4
    '  TKunde = class(TPersistent)'#10 +            // 5
    '  private'#10 +                                // 6
    '    FListe: TStrings;'#10 +                    // 7
    '  public'#10 +                                 // 8
    '    FName: string;'#10 +                       // 9
    '    FAlter: Integer;'#10 +                     // 10
    '    FAktiv: Boolean;'#10 +                     // 11
    '    %s'#10 +                                   // 12 Befehl
    '  end;'#10 +                                   // 13
    'implementation'#10 +                           // 14
    #10 +                                           // 15
    'end.';

  cTypeUnit =
    'unit U;'#10'interface'#10'type'#10'  TA = Integer;'#10'  %s'#10'  TB = Byte;'#10'implementation'#10'end.';

function InClass(const ACommand: string): string;
begin
  Result := Expand(Format(cClassUnit, [ACommand]), 12);
end;

procedure TTypeCommandsTests.EnumWithPrefixInTypeSection;
begin
  Assert.AreEqual('ks', EnumPrefix('TKundenStatus'));
  Assert.AreEqual(Format(cTypeUnit, ['TFarbe = (fRot, fGruen, fBlau);']),
    Expand(Format(cTypeUnit, ['/enum TFarbe rot, gruen, blau']), 4));
  Assert.AreEqual(Format(cTypeUnit, ['TFarbe = (rot, gruen);']), Expand(Format(cTypeUnit, ['/enum! TFarbe rot, gruen']),
    4));
end;

procedure TTypeCommandsTests.EnumWithoutTypeSection;
const
  cText = 'unit U;'#10'interface'#10'/enum TFarbe rot'#10'implementation'#10'end.';
begin
  Assert.AreEqual('unit U;'#10'interface'#10'type'#10'  TFarbe = (fRot);'#10'implementation'#10'end.',
    Expand(cText, 2));
end;

procedure TTypeCommandsTests.EnumWithNamesReopensType;
var
  mText: string;
begin
  mText := Expand(Format(cTypeUnit, ['/enum TFarbe rot, gruen names']), 4);
  Assert.AreEqual('unit U;'#10'interface'#10'type'#10'  TA = Integer;'#10'  TFarbe = (fRot, fGruen);'#10'const'#10 +
    '  FarbeNamen: array[TFarbe] of string = (''rot'', ''gruen'');'#10'type'#10'  TB = Byte;'#10'implementation'#10 +
    'end.', mText);
  Assert.IsTrue(Parses(mText));
end;

procedure TTypeCommandsTests.EnumInRoutineFails;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  /enum TA x'#10'end;'#10'end.';
begin
  Assert.AreEqual('/enum gilt nur auf Unit-Ebene', ProblemOf(cText));
end;

procedure TTypeCommandsTests.HelperForRecordAndClass;
var
  mText: string;
begin
  mText := Expand(Format(cTypeUnit, ['/helper TA']), 4);
  Assert.IsTrue(Pos('  TAHelper = record helper for TA'#10'  public'#10'  end;'#10, mText) > 0, mText);
  mText := Expand(Format(cTypeUnit, ['/helper TStrings']), 4);
  Assert.IsTrue(Pos('  TStringsHelper = class helper for TStrings'#10, mText) > 0, mText);
end;

const
  cEnumUnit =
    'unit U;'#10'interface'#10'type'#10'  TFarbe = (Rot, Gruen, Blau);'#10'  %s'#10'implementation'#10'end.';

procedure TTypeCommandsTests.HelperForEnumAddsNamesAndConversion;
var
  mText: string;
begin
  // #875: Namenstabelle, ToString und FromString; System.SysUtils kommt ins uses.
  mText := Expand(Format(cEnumUnit, ['/helper TFarbe']), 4);
  Assert.IsTrue(Pos('  TFarbeHelper = record helper for TFarbe'#10'  private const'#10 +
    '    cNames: array[TFarbe] of string = (''Rot'', ''Gruen'', ''Blau'');'#10'  public'#10 +
    '    function ToString: string;'#10'    class function FromString(const AValue: string): TFarbe; static;'#10 +
    '  end;', mText) > 0, mText);
  Assert.IsTrue(Pos('function TFarbeHelper.ToString: string;'#10'begin'#10'  Result := cNames[Self];'#10'end;',
    mText) > 0, mText);
  Assert.IsTrue(Pos('class function TFarbeHelper.FromString(const AValue: string): TFarbe;'#10'var'#10 +
    '  Value: TFarbe;'#10'begin'#10'  for Value := Low(TFarbe) to High(TFarbe) do'#10 +
    '    if SameText(cNames[Value], AValue) then'#10'      Exit(Value);'#10, mText) > 0, mText);
  Assert.IsTrue(Pos('uses'#10'  System.SysUtils;', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TTypeCommandsTests.HelperForEnumSwitchedOff;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mHost := TRecordingSlashHost.Create;
  mKeep := mHost;
  mHost.Settings := [TSlashSettings.cEnumHelper + '=false'];
  mText := Format(cEnumUnit, ['/helper TFarbe']);
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(mText, TTextPosition.Create(5, 0),
    TSlashEnvironment.Create(nil, nil, nil, '', 'file:///U.pas', mKeep), mEdits));
  mText := Apply(mText, mEdits);
  Assert.IsTrue(Pos('  TFarbeHelper = record helper for TFarbe'#10'  public'#10'  end;', mText) > 0, mText);
  Assert.AreEqual(0, Pos('cNames', mText), mText);
end;

const
  cSetUnit =
    'unit U;'#10'interface'#10'type'#10'  TFarbe = (Rot, Gruen, Blau);'#10'  TFarben = set of TFarbe;'#10 +
    '  %s'#10'implementation'#10'end.';

procedure TTypeCommandsTests.HelperForSetAddsMethods;
var
  mText: string;
begin
  mText := Expand(Format(cSetUnit, ['/helper TFarben']), 5);
  Assert.IsTrue(Pos('  TFarbenHelper = record helper for TFarben'#10'  private const'#10 +
    '    cNames: array[TFarbe] of string = (''Rot'', ''Gruen'', ''Blau'');'#10'  public'#10 +
    '    function Contains(AValue: TFarbe): Boolean;'#10'    function ToText: string;'#10 +
    '    procedure Toggle(AValue: TFarbe);'#10'    class function All: TFarben; static;'#10'  end;', mText) > 0, mText);
  Assert.IsTrue(Pos('function TFarbenHelper.Contains(AValue: TFarbe): Boolean;'#10'begin'#10 +
    '  Result := AValue in Self;'#10'end;', mText) > 0, mText);
  Assert.IsTrue(Pos('  for Value in Self do'#10'  begin'#10'    if Result <> '''' then'#10 +
    '      Result := Result + '', '';'#10'    Result := Result + cNames[Value];'#10'  end;'#10 +
    '  Result := ''['' + Result + '']'';', mText) > 0, mText);
  Assert.IsTrue(Pos('procedure TFarbenHelper.Toggle(AValue: TFarbe);'#10'begin'#10'  if AValue in Self then'#10 +
    '    Exclude(Self, AValue)'#10'  else'#10'    Include(Self, AValue);'#10'end;', mText) > 0, mText);
  Assert.IsTrue(Pos('class function TFarbenHelper.All: TFarben;'#10'begin'#10 +
    '  Result := [Low(TFarbe)..High(TFarbe)];'#10'end;', mText) > 0, mText);
  Assert.AreEqual(0, Pos('System.TypInfo', mText), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TTypeCommandsTests.HelperForSetWithoutKnownValuesUsesRtti;
var
  mText: string;
begin
  // Aufzählung aus einer anderen Unit ohne Index: Namen über die RTTI.
  mText := Expand('unit U;'#10'interface'#10'type'#10'  TStile = set of TFontStyle;'#10'  /helper TStile'#10 +
    'implementation'#10'end.', 4);
  Assert.IsTrue(Pos('    Result := Result + GetEnumName(TypeInfo(TFontStyle), Ord(Value));', mText) > 0, mText);
  Assert.IsTrue(Pos('System.TypInfo', mText) > 0, mText);
  Assert.AreEqual(0, Pos('cNames', mText), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TTypeCommandsTests.HelperForSetSwitchedOff;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mHost := TRecordingSlashHost.Create;
  mKeep := mHost;
  mHost.Settings := [TSlashSettings.cSetHelper + '=false'];
  mText := Format(cSetUnit, ['/helper TFarben']);
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(mText, TTextPosition.Create(6, 0),
    TSlashEnvironment.Create(nil, nil, nil, '', 'file:///U.pas', mKeep), mEdits));
  mText := Apply(mText, mEdits);
  Assert.IsTrue(Pos('  TFarbenHelper = record helper for TFarben'#10'  public'#10'  end;', mText) > 0, mText);
  Assert.AreEqual(0, Pos('Contains', mText), mText);
  mHost.Settings := nil;
end;

procedure TTypeCommandsTests.SingletonAddsInstance;
var
  mText: string;
begin
  mText := InClass('/singleton');
  Assert.IsTrue(Pos('  private'#10'    class var FInstance: TKunde;'#10'  public'#10'    class destructor Destroy;'#10 +
    '    class function Instance: TKunde;'#10'  end;', mText) > 0, mText);
  Assert.IsTrue(Pos('class function TKunde.Instance: TKunde;'#10'begin'#10'  if FInstance = nil then'#10 +
    '    FInstance := TKunde.Create;'#10'  Result := FInstance;'#10'end;', mText) > 0, mText);
  Assert.IsTrue(Pos('  FreeAndNil(FInstance);', mText) > 0, mText);
end;

procedure TTypeCommandsTests.SingletonNamesExistingConstructor;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
begin
  // #298: Der vorhandene Konstruktor bleibt; ein Hinweis nennt ihn.
  mHost := TRecordingSlashHost.Create;
  mKeep := mHost;
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(Format(cClassUnit,
    ['constructor Create(AName: string);'#10'    /singleton']), TTextPosition.Create(14, 0),
    TSlashEnvironment.Create(nil, nil, nil, '', 'file:///U.pas', mKeep), mEdits));
  Assert.AreEqual(1, Integer(Length(mHost.Notes)));
  Assert.Contains(mHost.Notes[0], 'Konstruktor Create bleibt unverändert');
  // Ohne Konstruktor kein Hinweis.
  mHost.Notes := nil;
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(Format(cClassUnit, ['/singleton']),
    TTextPosition.Create(13, 0), TSlashEnvironment.Create(nil, nil, nil, '', 'file:///U.pas', mKeep), mEdits));
  Assert.AreEqual(0, Integer(Length(mHost.Notes)));
end;

procedure TTypeCommandsTests.SingletonOutsideClassFails;
begin
  Assert.AreEqual('/singleton gilt nur in einer Klasse oder einer ihrer Methoden',
    ProblemOf(Format(cTypeUnit, ['/singleton'])));
end;

procedure TTypeCommandsTests.EncapsulateMakesProperty;
var
  mText: string;
begin
  mText := InClass('/encapsulate FName');
  Assert.AreEqual(0, Pos('  public'#10'    FName: string;', mText), mText);
  Assert.IsTrue(Pos('  private'#10'    FName: string;'#10'    procedure SetName(const Value: string);'#10 +
    '  public'#10'    property Name: string read FName write SetName;'#10'  end;', mText) > 0, mText);
  // Derselbe Setter wie /prop und die Code-Vorlage (#51); ohne Changed in TKunde nur die Prüfung.
  Assert.IsTrue(Pos('procedure TKunde.SetName(const Value: string);'#10'begin'#10'  if FName <> Value then'#10 +
    '    FName := Value;'#10'end;', mText) > 0, mText);
end;

procedure TTypeCommandsTests.EncapsulatePrivateFieldFails;
begin
  Assert.AreEqual('FListe ist schon private', ProblemOf(Format(cClassUnit, ['/encapsulate FListe'])));
  Assert.AreEqual('Kein Feld FOrt in TKunde', ProblemOf(Format(cClassUnit, ['/encapsulate FOrt'])));
end;

procedure TTypeCommandsTests.AssignCopiesFields;
var
  mText: string;
begin
  mText := InClass('/assign');
  Assert.IsTrue(Pos('    procedure Assign(Source: TPersistent); override;'#10'  end;', mText) > 0, mText);
  Assert.IsTrue(Pos('procedure TKunde.Assign(Source: TPersistent);'#10'begin'#10'  if Source is TKunde then'#10 +
    '  begin'#10'    FListe.Assign(TKunde(Source).FListe);'#10'    FName := TKunde(Source).FName;'#10 +
    '    FAlter := TKunde(Source).FAlter;'#10'    FAktiv := TKunde(Source).FAktiv;'#10'  end'#10'  else'#10 +
    '    inherited Assign(Source);'#10'end;', mText) > 0, mText);
end;

procedure TTypeCommandsTests.AssignOutsideClassFails;
begin
  Assert.AreEqual('/assign gilt nur in einer Klasse oder einer ihrer Methoden',
    ProblemOf(Format(cTypeUnit, ['/assign'])));
end;

procedure TTypeCommandsTests.JsonForSimpleFields;
var
  mText: string;
begin
  mText := InClass('/json');
  Assert.IsTrue(Pos('  System.Classes, System.JSON;', mText) + Pos('  System.Classes,'#10'  System.JSON;', mText) > 0,
    mText);
  Assert.IsTrue(Pos('    function ToJson: TJSONObject;'#10 +
    '    class function FromJson(AJson: TJSONObject): TKunde; static;', mText) > 0, mText);
  Assert.IsTrue(Pos('  Result.AddPair(''Name'', FName);'#10'  Result.AddPair(''Alter'', TJSONNumber.Create(FAlter));'#10 +
    '  Result.AddPair(''Aktiv'', TJSONBool.Create(FAktiv));', mText) > 0, mText);
  Assert.IsTrue(Pos('  // TODO FListe: TStrings', mText) > 0, mText);
  Assert.IsTrue(Pos('  Result := TKunde.Create;'#10, mText) > 0, mText);
  Assert.IsTrue(Pos('  Result.FAlter := AJson.GetValue<Integer>(''Alter'');', mText) > 0, mText);
end;

procedure TTypeCommandsTests.JsonOutsideTypeFails;
begin
  Assert.AreEqual('/json gilt nur in einer Klasse oder einer ihrer Methoden', ProblemOf(Format(cTypeUnit, ['/json'])));
end;

procedure TTypeCommandsTests.HelperInRoutineFails;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  /helper TA'#10'end;'#10'end.';
begin
  Assert.AreEqual('/helper gilt nur auf Unit-Ebene', ProblemOf(cText));
  Assert.AreEqual('/helper gilt nur auf Unit-Ebene', ProblemOf(Format(cClassUnit, ['/helper TA'])));
end;

procedure TTypeCommandsTests.EncapsulateKeepsUsesOutsideClass;
const
  cText =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'type'#10 +                                     // 2
    '  TKunde = class'#10 +                         // 3
    '  public'#10 +                                 // 4
    '    Name: string;'#10 +                        // 5
    '    procedure Zeige;'#10 +                     // 6
    '    /encapsulate Name'#10 +                    // 7 Befehl
    '  end;'#10 +                                   // 8
    'implementation'#10 +                           // 9
    'procedure TKunde.Zeige;'#10 +                  // 10
    'begin'#10 +                                    // 11
    '  Name := Name + Self.Name;'#10 +              // 12
    'end;'#10 +                                     // 13
    'procedure Setze(K: TKunde);'#10 +              // 14
    'begin'#10 +                                    // 15
    '  K.Name := ''x'';'#10 +                        // 16
    'end;'#10 +                                     // 17
    'end.';
var
  mResult_: string;
begin
  mResult_ := Expand(cText, 7);
  Assert.IsTrue(Parses(mResult_), mResult_);
  Assert.IsTrue(Pos('  private'#10'    FName: string;'#10'    procedure SetName(const Value: string);'#10 +
    '  public'#10'    property Name: string read FName write SetName;'#10'  end;', mResult_) > 0, mResult_);
  // In den eigenen Methoden das Feld, außerhalb der Klasse bleibt die Stelle wie sie war.
  Assert.IsTrue(Pos('  FName := FName + Self.FName;', mResult_) > 0, mResult_);
  Assert.IsTrue(Pos('procedure Setze(K: TKunde);'#10'begin'#10'  K.Name := ''x'';'#10'end;', mResult_) > 0, mResult_);
  // Mit F-Präfix bleibt jede Verwendung unverändert.
  mResult_ := Expand(StringReplace(StringReplace(cText, 'Name: string', 'FName: string', []), '/encapsulate Name',
    '/encapsulate FName', []), 7);
  Assert.IsTrue(Pos('  Name := Name + Self.Name;', mResult_) > 0, mResult_);
  Assert.IsTrue(Pos('  K.Name := ''x'';', mResult_) > 0, mResult_);
end;

const
  cJsonBefore =
    'unit Atlas.Common.Editing.TypeCommands.JsonGolden;'#13#10 +
    #13#10 +
    '// Golden-Datei für /json (#298): genau das, was /json aus der Klasse ohne'#13#10 +
    '// ToJson und FromJson erzeugt. Der Test vergleicht die Ausgabe mit dieser'#13#10 +
    '// Datei und prüft mit dem übersetzten Code, dass FromJson(ToJson(X)) gleiche'#13#10 +
    '// Feldwerte ergibt. Nicht von Hand ändern, sondern neu erzeugen.'#13#10 +
    #13#10 +
    'interface'#13#10 +
    #13#10 +
    'uses'#13#10 +
    '  System.Generics.Collections,'#13#10 +
    '  System.JSON;'#13#10 +
    #13#10 +
    'type'#13#10 +
    '  TJsonKunde = class'#13#10 +
    '  public'#13#10 +
    '    FName: string;'#13#10 +
    '    FAlter: Integer;'#13#10 +
    '    FUmsatz: Double;'#13#10 +
    '    FAktiv: Boolean;'#13#10 +
    '    /json'#13#10 +                                // 20
    '  end;'#13#10 +
    #13#10 +
    'implementation'#13#10 +
    #13#10 +
    'end.'#13#10;

/// <summary>Datei unter Tests/ ab dem Programmordner bzw. dem aktuellen Ordner aufwärts; '' ohne.</summary>
function TestsFile(const ARelative: string): string;
var
  mStarts: TArray<string>;
  mStart, mDirectory: string;
begin
  mStarts := [ExtractFileDir(ParamStr(0)), GetCurrentDir];
  for mStart in mStarts do
  begin
    mDirectory := mStart;
    while mDirectory <> '' do
    begin
      Result := TPath.Combine(mDirectory, TPath.Combine('Tests', ARelative));
      if TFile.Exists(Result) then
      begin
        Exit;
      end;
      if ExtractFileDir(mDirectory) = mDirectory then
      begin
        Break;
      end;
      mDirectory := ExtractFileDir(mDirectory);
    end;
  end;
  Result := '';
end;

procedure TTypeCommandsTests.JsonMatchesGoldenFile;
var
  mFileName, mGolden: string;
begin
  mFileName := TestsFile(TPath.Combine('Common', TPath.Combine('Editing',
    'Atlas.Common.Editing.TypeCommands.JsonGolden.pas')));
  Assert.AreNotEqual('', mFileName, 'Golden-Datei nicht gefunden');
  mGolden := TFile.ReadAllText(mFileName, TEncoding.UTF8);
  if (mGolden <> '') and (mGolden[1] = #$FEFF) then
  begin
    Delete(mGolden, 1, 1);
  end;
  Assert.AreEqual(mGolden, Expand(cJsonBefore, 20));
end;

procedure TTypeCommandsTests.JsonRoundTripKeepsValues;
var
  mOriginal, mCopied: TJsonKunde;
  mJson: TJSONObject;
begin
  mCopied := nil;
  mJson := nil;
  mOriginal := TJsonKunde.Create;
  try
    mOriginal.FName := 'Müller';
    mOriginal.FAlter := 42;
    mOriginal.FUmsatz := 1234.5;
    mOriginal.FAktiv := True;
    mJson := mOriginal.ToJson;
    mCopied := TJsonKunde.FromJson(mJson);
    Assert.AreEqual(mOriginal.FName, mCopied.FName);
    Assert.AreEqual(mOriginal.FAlter, mCopied.FAlter);
    Assert.AreEqual(mOriginal.FUmsatz, mCopied.FUmsatz, 0.0001);
    Assert.IsTrue(mCopied.FAktiv);
  finally
    mCopied.Free;
    mJson.Free;
    mOriginal.Free;
  end;
end;

procedure TTypeCommandsTests.ThreadWithoutTypeSection;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils;'#10'/thread TWorker'#10#10'end.';
var
  mResult_: string;
begin
  mResult_ := Expand(cText, 5);
  Assert.IsTrue(Pos('type'#10'  TWorker = class(TThread)'#10'  protected'#10'    procedure Execute; override;'#10 +
    '  end;'#10, mResult_) > 0, mResult_);
  Assert.IsTrue(Pos('procedure TWorker.Execute;'#10'begin'#10, mResult_) > 0, mResult_);
  Assert.IsTrue(Pos('  while not Terminated do'#10, mResult_) > 0, mResult_);
  Assert.IsTrue(Pos('System.Classes', mResult_) > 0, mResult_);
  Assert.IsTrue(Parses(mResult_), mResult_);
end;

procedure TTypeCommandsTests.ThreadInClassFails;
begin
  Assert.AreEqual('/thread gilt nur auf Unit-Ebene', ProblemOf(Format(cClassUnit, ['/thread TWorker'])));
end;

procedure TTypeCommandsTests.ExceptionWithAndWithoutAncestor;
begin
  Assert.AreEqual(Format(cTypeUnit, ['EImportFehler = class(Exception);']),
    Expand(Format(cTypeUnit, ['/exception EImportFehler']), 4));
  Assert.AreEqual(Format(cTypeUnit, ['EImportFehler = class(EBasis);']),
    Expand(Format(cTypeUnit, ['/exception EImportFehler : EBasis']), 4));
end;

procedure TTypeCommandsTests.ExceptionInRoutineFails;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  /exception EX'#10'end;'#10'end.';
begin
  Assert.AreEqual('/exception gilt nur auf Unit-Ebene', ProblemOf(cText));
end;

procedure TTypeCommandsTests.ResultsParseWithoutErrors;
const
  cCommands: array[0..4] of string = ('/singleton', '/encapsulate FName', '/assign', '/json', '/encapsulate FAlter');
var
  mCommand, mText: string;
begin
  for mCommand in cCommands do
  begin
    mText := InClass(mCommand);
    Assert.IsTrue(Parses(mText), mCommand + ': ' + mText);
  end;
  Assert.IsTrue(Parses(Expand(Format(cTypeUnit, ['/helper TA']), 4)));
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeCommandsTests);

end.
