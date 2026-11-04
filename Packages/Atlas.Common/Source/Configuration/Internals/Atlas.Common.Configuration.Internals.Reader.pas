unit Atlas.Common.Configuration.Internals.Reader;

// Grundlage der Leser von atlas.json: TConfigurationReader hält den Text,
// rechnet Positionen und sammelt die Meldungen. Jeder Schlüssel der obersten
// Ebene ist ein Abschnitt (TConfigurationSection) mit einem Leser (Read) und
// der Übernahme bei der Schichtung (Take, TConfigurationParser.ParseLayered).
// Die Abschnitte stehen in den Units Internals.*Options nach Themen; der
// Parser sucht den Abschnitt eines Schlüssels in ihren Tabellen.
// Objekte mit Schaltern und Gliedern liest ReadObject: Schalter (true/false)
// binden an ein Feld der Einstellungen (TFlagOption), alle anderen Glieder an
// eine Leseroutine (TMemberOption); Unbekanntes meldet ReadObject als Warnung.

interface

uses
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Internals.JsonTree;

type
  TConfigurationReader = class;

  /// <summary>Liest den Wert eines Schlüssels der obersten Ebene in die Einstellungen.</summary>
  TSectionRead = procedure(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
  /// <summary>Übernimmt bei der Schichtung die Werte eines Schlüssels aus den Einstellungen der Datei
  /// (ASource, Text AFileText) in ATarget.</summary>
  TSectionTake = procedure(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);

  /// <summary>Schlüssel der obersten Ebene mit Leser und Übernahme.</summary>
  TConfigurationSection = record
    Section: string;
    Read: TSectionRead;
    Take: TSectionTake;
  end;

  /// <summary>Liest den Wert AValue des Glieds AKey eines Objekts.</summary>
  TMemberRead = procedure(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
    var ASettings: TServerSettings);

  /// <summary>Glied eines Objekts mit eigener Leseroutine.</summary>
  TMemberOption = record
    Key: string;
    Read: TMemberRead;
  end;

  /// <summary>Glied eines Objekts, das true oder false sein muss, gebunden an ein Feld der Einstellungen.</summary>
  TFlagOption = record
    Key: string;
    Value: PBoolean;
    /// <summary>AValue muss bis zum Lesen bestehen (ein Feld der Einstellungen, die der Leser füllt).</summary>
    class function Create(const AKey: string; var AValue: Boolean): TFlagOption; static;
  end;

  /// <summary>Zeiger auf einen Text der Einstellungen. Eigener Typ, weil PString unter FPC auf einen
  /// AnsiString zeigt.</summary>
  PSettingText = ^string;

  /// <summary>Glied eines Objekts mit festen Werten (Groß-/Kleinschreibung egal), gebunden an ein Feld der
  /// Einstellungen; gespeichert wird der Wert so, wie ihn Values schreibt.</summary>
  TChoiceOption = record
    Key: string;
    Values: TArray<string>;
    Value: PSettingText;
    class function Create(const AKey: string; const AValues: array of string; var AValue: string): TChoiceOption;
      static;
  end;

  TConfigurationReader = class
  private
    FText: string;
    /// <summary>Zeilenindex von FText für die Positionen der Meldungen.</summary>
    FLines: TLineTable;
    FIssues: TList<TConfigurationIssue>;
    FProfileNode: TJsonNode;
    FTestProfileNode: TJsonNode;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    function PositionAt(AOffset: Integer): TTextPosition;
    procedure Report(AStart, AStop: Integer; const AMessage: string; AIsError: Boolean);
    procedure ReportNode(ANode: TJsonNode; const AMessage: string);
    /// <summary>Warnung "Unbekannte Einstellung "APrefix.Schlüssel"" am Schlüssel AIndex des Objekts ANode.</summary>
    procedure ReportUnknown(ANode: TJsonNode; AIndex: Integer; const APrefix: string);
    function ExpectString(ANode: TJsonNode; const AName: string; out AValue: string): Boolean;
    function ExpectBoolean(ANode: TJsonNode; const AName: string; var AValue: Boolean): Boolean;
    /// <summary>Ist ANode ein Objekt? Sonst Fehler ""AName" muss ein Objekt sein".</summary>
    function ExpectObject(ANode: TJsonNode; const AName: string): Boolean;
    function ParseStrings(ANode: TJsonNode; const AName: string; out AItems: TArray<string>): Boolean;
    /// <summary>Text aus AValues (genau so geschrieben) als Index; sonst Fehler AMessage.</summary>
    function ExpectChoice(ANode: TJsonNode; const AName: string; const AValues: array of string;
      const AMessage: string; out AIndex: Integer): Boolean;
    /// <summary>Text aus AValues (genau so geschrieben) als Index; jeder andere Wert, auch einer, der kein Text
    /// ist, ergibt Fehler AMessage.</summary>
    function ExpectOneOf(ANode: TJsonNode; const AValues: array of string; const AMessage: string;
      out AIndex: Integer): Boolean;
    /// <summary>Wie ExpectChoice, Groß-/Kleinschreibung egal.</summary>
    function ExpectChoiceText(ANode: TJsonNode; const AName: string; const AValues: array of string;
      const AMessage: string; out AIndex: Integer): Boolean;
    /// <summary>Liste von Texten; ist ANode keine Liste, Fehler AMessage. Einträge, die keine Texte sind, meldet
    /// es unter AName und lässt sie weg.</summary>
    function ExpectStrings(ANode: TJsonNode; const AName, AMessage: string; out AItems: TArray<string>): Boolean;
    /// <summary>Ganze Zahl von AMin bis AMax in AValue; sonst Fehler AMessage.</summary>
    function ExpectInteger(ANode: TJsonNode; AMin, AMax: Integer; const AMessage: string;
      var AValue: Integer): Boolean;
    /// <summary>Text von ANode wie in der Datei.</summary>
    function NodeText(ANode: TJsonNode): string;
    /// <summary>Liest das Objekt ANode des Abschnitts ASection: Schalter aus AFlags, Glieder aus AMembers;
    /// andere Schlüssel meldet es als unbekannt.</summary>
    procedure ReadObject(ANode: TJsonNode; const ASection: string; const AFlags: array of TFlagOption;
      const AMembers: array of TMemberOption; var ASettings: TServerSettings); overload;
    /// <summary>Wie ReadObject, dazu Glieder mit festen Werten aus AChoices.</summary>
    procedure ReadObject(ANode: TJsonNode; const ASection: string; const AFlags: array of TFlagOption;
      const AChoices: array of TChoiceOption; const AMembers: array of TMemberOption;
      var ASettings: TServerSettings); overload;
    /// <summary>Liest das Glied AIndex von ANode, wenn es ein Schalter aus AFlags ist.</summary>
    function ReadFlag(ANode: TJsonNode; AIndex: Integer; const AFlags: array of TFlagOption): Boolean;
    /// <summary>Liest das Glied AIndex von ANode, wenn AMembers es kennt.</summary>
    function ReadMember(ANode: TJsonNode; AIndex: Integer; const AMembers: array of TMemberOption;
      var ASettings: TServerSettings): Boolean;
    /// <summary>Liest das Glied AIndex von ANode, wenn AChoices es kennt; Fehler ""ASection.Schlüssel" muss "a"
    /// oder "b" sein" bei einem anderen Wert.</summary>
    function ReadChoice(ANode: TJsonNode; AIndex: Integer; const ASection: string;
      const AChoices: array of TChoiceOption): Boolean;
    function Issues: TArray<TConfigurationIssue>;
    property Text: string read FText;
    /// <summary>Knoten von "profile"; die Namen prüft der Parser erst nach "profiles".</summary>
    property ProfileNode: TJsonNode read FProfileNode write FProfileNode;
    /// <summary>"testProfile" mit einem Namen, der erst nach "profiles" geprüft werden kann.</summary>
    property TestProfileNode: TJsonNode read FTestProfileNode write FTestProfileNode;
  end;

/// <summary>"a", "b" AConjunction "c" für Meldungen.</summary>
function ChoiceText(const AValues: array of string; const AConjunction: string): string;
/// <summary>Kopie der Abschnittstabelle ASections.</summary>
function SectionList(const ASections: array of TConfigurationSection): TArray<TConfigurationSection>;
/// <summary>Schlüssel des Objekts AKey unter der Wurzel von AText; nil, wenn es fehlt, kein Objekt ist oder
/// der Text ungültig ist.</summary>
function ObjectMemberKeys(const AText, AKey: string): TArray<string>;
/// <summary>Schweregrad aus dem Text ("off", "hint", "info", "information", "warning", "error").</summary>
function TryParseRuleSeverity(const AValue: string; out ASeverity: TRuleSeverity): Boolean;
/// <summary>Konfidenz aus dem Text ("low", "medium", "high").</summary>
function TryParseRuleConfidence(const AValue: string; out AConfidence: TRuleConfidence): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils;

function TryParseRuleSeverity(const AValue: string; out ASeverity: TRuleSeverity): Boolean;
const
  cNames: array[0..5] of string = ('off', 'hint', 'info', 'information', 'warning', 'error');
  cSeverities: array[0..5] of TRuleSeverity = (TRuleSeverity.Off, TRuleSeverity.Hint, TRuleSeverity.Information,
    TRuleSeverity.Information, TRuleSeverity.Warning, TRuleSeverity.Error);
var
  mIndex: Integer;
begin
  mIndex := IndexStr(LowerCase(Trim(AValue)), cNames);
  Result := mIndex >= 0;
  ASeverity := TRuleSeverity.Default;
  if Result then
  begin
    ASeverity := cSeverities[mIndex];
  end;
end;

function TryParseRuleConfidence(const AValue: string; out AConfidence: TRuleConfidence): Boolean;
const
  cNames: array[0..2] of string = ('low', 'medium', 'high');
  cConfidences: array[0..2] of TRuleConfidence = (TRuleConfidence.Low, TRuleConfidence.Medium,
    TRuleConfidence.High);
var
  mIndex: Integer;
begin
  mIndex := IndexStr(LowerCase(Trim(AValue)), cNames);
  Result := mIndex >= 0;
  AConfidence := TRuleConfidence.Medium;
  if Result then
  begin
    AConfidence := cConfidences[mIndex];
  end;
end;

function ChoiceText(const AValues: array of string; const AConjunction: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(AValues) do
  begin
    if (mIndex > 0) and (mIndex = High(AValues)) then
    begin
      Result := Result + ' ' + AConjunction + ' ';
    end
    else if mIndex > 0 then
    begin
      Result := Result + ', ';
    end;
    Result := Result + '"' + AValues[mIndex] + '"';
  end;
end;

function SectionList(const ASections: array of TConfigurationSection): TArray<TConfigurationSection>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ASections));
  for mIndex := 0 to High(ASections) do
  begin
    Result[mIndex] := ASections[mIndex];
  end;
end;

/// <summary>Schlüssel des Objekts ANode.</summary>
function KeysOf(ANode: TJsonNode): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, ANode.Count);
  for mIndex := 0 to ANode.Count - 1 do
  begin
    Result[mIndex] := ANode.Keys[mIndex];
  end;
end;

function ObjectMemberKeys(const AText, AKey: string): TArray<string>;
var
  mRoot: TJsonNode;
  mIndex: Integer;
begin
  Result := nil;
  try
    mRoot := TJsonTree.Parse(AText);
  except
    on EJsonTreeError do
      Exit;
  end;
  try
    if mRoot.Kind <> TJsonKind.Object_ then
    begin
      Exit;
    end;
    for mIndex := 0 to mRoot.Count - 1 do
    begin
      if (mRoot.Keys[mIndex] = AKey) and (mRoot[mIndex].Kind = TJsonKind.Object_) then
      begin
        Result := Result + KeysOf(mRoot[mIndex]);
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

{ TFlagOption }

class function TFlagOption.Create(const AKey: string; var AValue: Boolean): TFlagOption;
begin
  Result.Key := AKey;
  Result.Value := @AValue;
end;

{ TChoiceOption }

class function TChoiceOption.Create(const AKey: string; const AValues: array of string;
  var AValue: string): TChoiceOption;
var
  mIndex: Integer;
begin
  Result.Key := AKey;
  SetLength(Result.Values, Length(AValues));
  for mIndex := 0 to High(AValues) do
  begin
    Result.Values[mIndex] := AValues[mIndex];
  end;
  Result.Value := @AValue;
end;

{ TConfigurationReader }

constructor TConfigurationReader.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FLines := TLineTable.Build(AText);
  FIssues := TList<TConfigurationIssue>.Create;
end;

destructor TConfigurationReader.Destroy;
begin
  FIssues.Free;
  inherited;
end;

function TConfigurationReader.PositionAt(AOffset: Integer): TTextPosition;
begin
  Result := FLines.PositionAt(AOffset);
end;

procedure TConfigurationReader.Report(AStart, AStop: Integer; const AMessage: string; AIsError: Boolean);
var
  mIssue: TConfigurationIssue;
begin
  if AStop <= AStart then
  begin
    AStop := AStart + 1;
  end;
  if AStop > Length(FText) then
  begin
    AStop := Length(FText);
  end;
  if AStart > AStop then
  begin
    AStart := AStop;
  end;
  mIssue.Range := TTextRange.Create(PositionAt(AStart), PositionAt(AStop));
  mIssue.Message := AMessage;
  mIssue.IsError := AIsError;
  FIssues.Add(mIssue);
end;

procedure TConfigurationReader.ReportNode(ANode: TJsonNode; const AMessage: string);
begin
  Report(ANode.Start, ANode.Stop, AMessage, True);
end;

procedure TConfigurationReader.ReportUnknown(ANode: TJsonNode; AIndex: Integer; const APrefix: string);
begin
  Report(ANode.KeyStarts[AIndex], ANode.KeyStarts[AIndex] + Length(ANode.Keys[AIndex]) + 2,
    Format('Unbekannte Einstellung "%s.%s"', [APrefix, ANode.Keys[AIndex]]), False);
end;

function TConfigurationReader.ExpectString(ANode: TJsonNode; const AName: string; out AValue: string): Boolean;
begin
  Result := ANode.Kind = TJsonKind.String_;
  if Result then
  begin
    AValue := ANode.Value;
  end
  else
  begin
    AValue := '';
    ReportNode(ANode, Format('"%s" muss ein String sein', [AName]));
  end;
end;

function TConfigurationReader.ExpectBoolean(ANode: TJsonNode; const AName: string; var AValue: Boolean): Boolean;
begin
  Result := ANode.Kind = TJsonKind.Boolean_;
  if Result then
  begin
    AValue := ANode.Value = 'true';
  end
  else
  begin
    ReportNode(ANode, Format('"%s" muss true oder false sein', [AName]));
  end;
end;

function TConfigurationReader.ExpectObject(ANode: TJsonNode; const AName: string): Boolean;
begin
  Result := ANode.Kind = TJsonKind.Object_;
  if not Result then
  begin
    ReportNode(ANode, Format('"%s" muss ein Objekt sein', [AName]));
  end;
end;

function TConfigurationReader.ParseStrings(ANode: TJsonNode; const AName: string;
  out AItems: TArray<string>): Boolean;
begin
  Result := ExpectStrings(ANode, AName, Format('"%s" muss eine Liste von Texten sein', [AName]), AItems);
end;

function TConfigurationReader.ExpectStrings(ANode: TJsonNode; const AName, AMessage: string;
  out AItems: TArray<string>): Boolean;
var
  mIndex: Integer;
  mValue: string;
begin
  AItems := nil;
  Result := ANode.Kind = TJsonKind.Array_;
  if not Result then
  begin
    ReportNode(ANode, AMessage);
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    if ExpectString(ANode[mIndex], AName, mValue) then
    begin
      AItems := AItems + [mValue];
    end;
  end;
end;

function TConfigurationReader.ExpectChoice(ANode: TJsonNode; const AName: string; const AValues: array of string;
  const AMessage: string; out AIndex: Integer): Boolean;
var
  mText: string;
begin
  AIndex := -1;
  Result := ExpectString(ANode, AName, mText);
  if Result then
  begin
    AIndex := IndexStr(mText, AValues);
    Result := AIndex >= 0;
    if not Result then
    begin
      ReportNode(ANode, AMessage);
    end;
  end;
end;

function TConfigurationReader.ExpectOneOf(ANode: TJsonNode; const AValues: array of string; const AMessage: string;
  out AIndex: Integer): Boolean;
begin
  AIndex := -1;
  if ANode.Kind = TJsonKind.String_ then
  begin
    AIndex := IndexStr(ANode.Value, AValues);
  end;
  Result := AIndex >= 0;
  if not Result then
  begin
    ReportNode(ANode, AMessage);
  end;
end;

function TConfigurationReader.ExpectChoiceText(ANode: TJsonNode; const AName: string;
  const AValues: array of string; const AMessage: string; out AIndex: Integer): Boolean;
var
  mText: string;
begin
  AIndex := -1;
  Result := ExpectString(ANode, AName, mText);
  if Result then
  begin
    AIndex := IndexText(mText, AValues);
    Result := AIndex >= 0;
    if not Result then
    begin
      ReportNode(ANode, AMessage);
    end;
  end;
end;

function TConfigurationReader.ExpectInteger(ANode: TJsonNode; AMin, AMax: Integer; const AMessage: string;
  var AValue: Integer): Boolean;
var
  mValue: Integer;
begin
  Result := (ANode.Kind = TJsonKind.Number) and TryStrToInt(ANode.Value, mValue) and (mValue >= AMin) and
    (mValue <= AMax);
  if Result then
  begin
    AValue := mValue;
  end
  else
  begin
    ReportNode(ANode, AMessage);
  end;
end;

function TConfigurationReader.NodeText(ANode: TJsonNode): string;
begin
  Result := Copy(FText, ANode.Start + 1, ANode.Stop - ANode.Start);
end;

function TConfigurationReader.ReadFlag(ANode: TJsonNode; AIndex: Integer;
  const AFlags: array of TFlagOption): Boolean;
var
  mFlag: TFlagOption;
begin
  for mFlag in AFlags do
  begin
    if mFlag.Key = ANode.Keys[AIndex] then
    begin
      ExpectBoolean(ANode[AIndex], mFlag.Key, mFlag.Value^);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TConfigurationReader.ReadMember(ANode: TJsonNode; AIndex: Integer;
  const AMembers: array of TMemberOption; var ASettings: TServerSettings): Boolean;
var
  mMember: TMemberOption;
begin
  for mMember in AMembers do
  begin
    if mMember.Key = ANode.Keys[AIndex] then
    begin
      mMember.Read(Self, ANode[AIndex], mMember.Key, ASettings);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TConfigurationReader.ReadChoice(ANode: TJsonNode; AIndex: Integer; const ASection: string;
  const AChoices: array of TChoiceOption): Boolean;
var
  mChoice: TChoiceOption;
  mFound: Integer;
begin
  for mChoice in AChoices do
  begin
    if mChoice.Key = ANode.Keys[AIndex] then
    begin
      if ExpectChoiceText(ANode[AIndex], mChoice.Key, mChoice.Values, Format('"%s.%s" muss %s sein',
        [ASection, mChoice.Key, ChoiceText(mChoice.Values, 'oder')]), mFound) then
      begin
        mChoice.Value^ := mChoice.Values[mFound];
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TConfigurationReader.ReadObject(ANode: TJsonNode; const ASection: string;
  const AFlags: array of TFlagOption; const AMembers: array of TMemberOption; var ASettings: TServerSettings);
begin
  ReadObject(ANode, ASection, AFlags, [], AMembers, ASettings);
end;

procedure TConfigurationReader.ReadObject(ANode: TJsonNode; const ASection: string;
  const AFlags: array of TFlagOption; const AChoices: array of TChoiceOption;
  const AMembers: array of TMemberOption; var ASettings: TServerSettings);
var
  mIndex: Integer;
begin
  if not ExpectObject(ANode, ASection) then
  begin
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    if not ReadFlag(ANode, mIndex, AFlags) and not ReadChoice(ANode, mIndex, ASection, AChoices) and
      not ReadMember(ANode, mIndex, AMembers, ASettings) then
    begin
      ReportUnknown(ANode, mIndex, ASection);
    end;
  end;
end;

function TConfigurationReader.Issues: TArray<TConfigurationIssue>;
begin
  Result := FIssues.ToArray;
end;

end.
