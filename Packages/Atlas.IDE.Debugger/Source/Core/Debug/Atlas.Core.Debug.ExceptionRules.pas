unit Atlas.Core.Debug.ExceptionRules;

// Exception-Regeln beim Debuggen, ohne VCL und Open Tools API. Eine Regel
// nennt die Klasse der Exception und wahlweise
//   - ein Muster für die Meldung (#2549): „enthält“ mit `*` als Platzhalter
//     (Teile in dieser Reihenfolge) oder ein regulärer Ausdruck, beides ohne
//     Groß-/Kleinschreibung. MessageMatch NotMatches dreht den Vergleich um:
//     „Nur bei Meldungen wie dieser anhalten“ ist eine Regel „Meldung passt
//     nicht → fortsetzen“.
//   - einen Ort (#838): Muster nach TAtlasRoutinePattern für die Routine des
//     ersten eigenen Rahmens („Kunden.*“, „TKundenImport.LeseZeile“).
//   - „mit Nachfahren“ (#838): Die Klasse passt auch, wenn sie unter den
//     Vorfahren der Exception steht (TAtlasExceptionFacts.Ancestors; die IDE
//     fragt sie beim Server nach, nur wenn eine solche Regel sie braucht).
// und eine Aktion: anhalten, nur im Verlauf vermerken (fortsetzen, Eintrag
// grau) oder still weiterlaufen. Die erste eingeschaltete passende Regel
// gewinnt; ohne passende Regel gelten die Ignorier-Liste und die IDE. Damit
// schlägt eine Regel mit Meldung die Klasse auf der Ignorier-Liste.
// Ablage in debug-ignore.json (Atlas.Core.Debug.IgnoreList), Feld "rules":
//   [{"class": "EKonfigFehler", "message": "Schlüssel unbekannt: *",
//     "regex": false, "messageMatch": "notMatches", "location": "",
//     "action": "log", "enabled": true, "descendants": false}]
// Dasselbe Format haben die Regeln des Projekts in .atlas ("exceptionRules").

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Debug.CallStack;

type
  {$SCOPEDENUMS ON}
  TAtlasExceptionAction = (Stop, Log, Continue);
  TAtlasMessageMatch = (Matches, NotMatches);
  /// <summary>Regel mit Muster für die Meldung (#2549, debug.exceptionMessageRules) bzw. nur nach Klasse und Ort
  /// (#838, debug.exceptionRules).</summary>
  TAtlasExceptionRuleKind = (Message, Place);
  /// <summary>Persönlich (debug-ignore.json) oder aus der Projektdatei .atlas (für alle im Team).</summary>
  TAtlasExceptionRuleOrigin = (Personal, Project);
  {$SCOPEDENUMS OFF}

  TAtlasExceptionRuleKinds = set of TAtlasExceptionRuleKind;

  /// <summary>Was beim Halt über die Exception bekannt ist.</summary>
  TAtlasExceptionFacts = record
    ExceptionClass: string;
    Message: string;
    /// <summary>Routine des ersten eigenen Rahmens ('' = unbekannt).</summary>
    Routine: string;
    /// <summary>Vorfahren der Klasse, nächster zuerst; nil = unbekannt (dann passt nur die Klasse selbst).
    /// </summary>
    Ancestors: TArray<string>;
    class function Create(const AClass, AMessage, ARoutine: string): TAtlasExceptionFacts; static;
  end;

  TAtlasExceptionRule = record
    ExceptionClass: string;
    /// <summary>Muster der Meldung; '' = jede.</summary>
    Message: string;
    Regex: Boolean;
    MessageMatch: TAtlasMessageMatch;
    /// <summary>Muster für die Routine des ersten eigenen Rahmens; '' = überall.</summary>
    Location: string;
    Action: TAtlasExceptionAction;
    Enabled: Boolean;
    /// <summary>Auch abgeleitete Klassen (TAtlasExceptionFacts.Ancestors).</summary>
    Descendants: Boolean;
    /// <summary>Nicht in der Datei; setzt Combined.</summary>
    Origin: TAtlasExceptionRuleOrigin;
    class function Create(const AClass, AMessage: string; AMatch: TAtlasMessageMatch;
      AAction: TAtlasExceptionAction): TAtlasExceptionRule; static;
    function HasMessage: Boolean;
    function SameCriteria(const AOther: TAtlasExceptionRule): Boolean;
    /// <summary>Klasse gleich oder, mit Descendants, unter den Vorfahren von AFacts.</summary>
    function ClassMatches(const AFacts: TAtlasExceptionFacts): Boolean;
    function Matches(const AFacts: TAtlasExceptionFacts): Boolean;
    function Kind: TAtlasExceptionRuleKind;
    /// <summary>Schlüssel für die Treffer der Sitzung: Herkunft und Bedingungen.</summary>
    function Key: string;
  end;

  TAtlasExceptionRuleList = TArray<TAtlasExceptionRule>;

  /// <summary>Treffer je Regel in der laufenden Sitzung (Schlüssel aus TAtlasExceptionRule.Key).</summary>
  TAtlasExceptionRuleHits = record
    Keys: TArray<string>;
    Counts: TArray<Integer>;
    procedure Add(const AKey: string);
    function CountOf(const AKey: string): Integer;
    procedure Clear;
  end;

  TAtlasExceptionRules = class
  public
    /// <summary>Passt AMessage zum Muster? Ungültiger Ausdruck passt nie.</summary>
    class function MessageMatches(const APattern: string; ARegex: Boolean; const AMessage: string): Boolean;
      static;
    /// <summary>Ist das Muster brauchbar? AError nennt bei einem ungültigen Ausdruck den Grund.</summary>
    class function ValidPattern(const APattern: string; ARegex: Boolean; out AError: string): Boolean; static;
    /// <summary>Vorschlag aus einer Meldung: Zahlen, Adressen und Texte in Hochkommas werden zu *.</summary>
    class function SuggestPattern(const AMessage: string): string; static;
    /// <summary>Index der ersten eingeschalteten Regel einer der Arten AKinds, die passt; -1 ohne.</summary>
    class function FirstMatch(const ARules: TAtlasExceptionRuleList; const AFacts: TAtlasExceptionFacts;
      AKinds: TAtlasExceptionRuleKinds): Integer; static;
    /// <summary>Arten nach den Schaltern debug.exceptionMessageRules und debug.exceptionRules.</summary>
    class function Kinds(AMessages, APlaces: Boolean): TAtlasExceptionRuleKinds; static;
    /// <summary>Braucht eine eingeschaltete Regel der Arten AKinds die Vorfahren von AClass (mit Nachfahren und
    /// anderer Klasse)?</summary>
    class function NeedsAncestors(const ARules: TAtlasExceptionRuleList; const AClass: string;
      AKinds: TAtlasExceptionRuleKinds): Boolean; static;
    /// <summary>Persönliche Regeln vor denen des Projekts, mit gesetzter Herkunft.</summary>
    class function Combined(const APersonal, AProject: TAtlasExceptionRuleList): TAtlasExceptionRuleList; static;
    /// <summary>Regel AIndex um ADelta Plätze verschieben (Reihenfolge = Vorrang); False außerhalb.</summary>
    class function MoveRule(var ARules: TAtlasExceptionRuleList; AIndex, ADelta: Integer): Boolean; static;
    /// <summary>Regel hinzufügen; eine mit gleichen Bedingungen wird ersetzt. True bei einer Änderung.</summary>
    class function Put(var ARules: TAtlasExceptionRuleList; const ARule: TAtlasExceptionRule): Boolean; static;
    class function ToJson(const ARules: TAtlasExceptionRuleList): TJSONArray; static;
    /// <summary>Gleiche Regeln in gleicher Reihenfolge (Inhalt wie in der Datei, ohne Herkunft)?</summary>
    class function SameRules(const ALeft, ARight: TAtlasExceptionRuleList): Boolean; static;
    /// <summary>Text der Projektdatei mit ARules unter "exceptionRules"; Kommentare und übrige Schlüssel bleiben.
    /// Ein leerer Text beginnt mit ASkeleton.</summary>
    class function WithProjectRules(const AText, ASkeleton: string; const ARules: TAtlasExceptionRuleList): string;
      static;
    /// <summary>Regeln aus dem Feld "rules"; unbrauchbare (ohne Klasse, ungültiges Muster) entfallen.</summary>
    class function Parse(AValue: TJSONValue): TAtlasExceptionRuleList; static;
    class function ActionName(AAction: TAtlasExceptionAction): string; static;
    /// <summary>Routine des ersten eigenen Rahmens, Ort der Regeln (auch ohne debug.justMyCode); '' ohne.</summary>
    class function OwnRoutine(const AFrames: TAtlasDebugFrames): string; static;
    /// <summary>Unit des ersten eigenen Rahmens („Kunden.Import“); '' ohne.</summary>
    class function OwnUnit(const AFrames: TAtlasDebugFrames): string; static;
    /// <summary>„Kunden.Import“ aus „C:\Src\Kunden.Import.pas“ oder „Src/Kunden.Import.pas“; '' ohne Datei.</summary>
    class function UnitOfFile(const AFileName: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Text.Json,
  Atlas.Text.Lines,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Debug.OwnCode,
  Atlas.Core.Debug.RoutinePattern;

const
  cActionNames: array[TAtlasExceptionAction] of string = ('stop', 'log', 'continue');
  cMatchNames: array[TAtlasMessageMatch] of string = ('matches', 'notMatches');
  cWildcard = '*';
  cQuote = '''';
  cProjectKey = 'exceptionRules';
  cRuleIndent = '    ';
  cArrayIndent = '  ';

{ TAtlasExceptionFacts }

class function TAtlasExceptionFacts.Create(const AClass, AMessage, ARoutine: string): TAtlasExceptionFacts;
begin
  Result.ExceptionClass := AClass;
  Result.Message := AMessage;
  Result.Routine := ARoutine;
  Result.Ancestors := nil;
end;

{ TAtlasExceptionRule }

class function TAtlasExceptionRule.Create(const AClass, AMessage: string; AMatch: TAtlasMessageMatch;
  AAction: TAtlasExceptionAction): TAtlasExceptionRule;
begin
  Result := Default(TAtlasExceptionRule);
  Result.ExceptionClass := Trim(AClass);
  Result.Message := AMessage;
  Result.MessageMatch := AMatch;
  Result.Action := AAction;
  Result.Enabled := True;
end;

function TAtlasExceptionRule.HasMessage: Boolean;
begin
  Result := Message <> '';
end;

function TAtlasExceptionRule.SameCriteria(const AOther: TAtlasExceptionRule): Boolean;
begin
  Result := SameText(ExceptionClass, AOther.ExceptionClass) and (Message = AOther.Message) and
    (Regex = AOther.Regex) and (MessageMatch = AOther.MessageMatch) and SameText(Location, AOther.Location) and
    (Descendants = AOther.Descendants);
end;

function TAtlasExceptionRule.ClassMatches(const AFacts: TAtlasExceptionFacts): Boolean;
var
  mAncestor: string;
begin
  Result := SameText(ExceptionClass, AFacts.ExceptionClass);
  if Result or not Descendants then
  begin
    Exit;
  end;
  for mAncestor in AFacts.Ancestors do
  begin
    if SameText(ExceptionClass, mAncestor) then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasExceptionRule.Matches(const AFacts: TAtlasExceptionFacts): Boolean;
begin
  Result := Enabled and ClassMatches(AFacts);
  if Result and (Location <> '') then
  begin
    Result := TAtlasRoutinePattern.Matches(Location, AFacts.Routine);
  end;
  // Ohne gelesene Meldung entscheidet keine Regel mit Meldung (lieber halten als verschlucken).
  if Result and HasMessage then
  begin
    Result := (AFacts.Message <> '') and (TAtlasExceptionRules.MessageMatches(Message, Regex, AFacts.Message) =
      (MessageMatch = TAtlasMessageMatch.Matches));
  end;
end;

function TAtlasExceptionRule.Kind: TAtlasExceptionRuleKind;
begin
  Result := TAtlasExceptionRuleKind.Place;
  if HasMessage then
  begin
    Result := TAtlasExceptionRuleKind.Message;
  end;
end;

function TAtlasExceptionRule.Key: string;
begin
  Result := Format('%d|%s|%s|%d|%d|%s|%d', [Ord(Origin), LowerCase(ExceptionClass), Message, Ord(Regex),
    Ord(MessageMatch), LowerCase(Location), Ord(Descendants)]);
end;

{ TAtlasExceptionRuleHits }

procedure TAtlasExceptionRuleHits.Add(const AKey: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Keys) do
  begin
    if Keys[mIndex] = AKey then
    begin
      Inc(Counts[mIndex]);
      Exit;
    end;
  end;
  Keys := Keys + [AKey];
  Counts := Counts + [1];
end;

function TAtlasExceptionRuleHits.CountOf(const AKey: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Keys) do
  begin
    if Keys[mIndex] = AKey then
    begin
      Exit(Counts[mIndex]);
    end;
  end;
  Result := 0;
end;

procedure TAtlasExceptionRuleHits.Clear;
begin
  Keys := nil;
  Counts := nil;
end;

{ TAtlasExceptionRules }

class function TAtlasExceptionRules.MessageMatches(const APattern: string; ARegex: Boolean;
  const AMessage: string): Boolean;
begin
  if APattern = '' then
  begin
    Exit(True);
  end;
  if not ARegex then
  begin
    // „enthält“: Teile zwischen den * in dieser Reihenfolge irgendwo in der Meldung.
    Exit(TAtlasRoutinePattern.Glob(cWildcard + APattern + cWildcard, AMessage));
  end;
  try
    Result := TRegEx.IsMatch(AMessage, APattern, [roIgnoreCase]);
  except
    // Ungültiger Ausdruck (aus einer von Hand geänderten Datei): passt nie.
    on Exception do
      Result := False;
  end;
end;

class function TAtlasExceptionRules.ValidPattern(const APattern: string; ARegex: Boolean;
  out AError: string): Boolean;
begin
  AError := '';
  Result := Trim(APattern) <> '';
  if not Result or not ARegex then
  begin
    Exit;
  end;
  try
    TRegEx.IsMatch('', APattern, [roIgnoreCase]);
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

/// <summary>Ende eines Texts in Hochkommas ab AStart (dem öffnenden); 0 ohne schließendes.</summary>
function QuoteEnd(const AText: string; AStart: Integer): Integer;
begin
  Result := PosEx(cQuote, AText, AStart + 1);
end;

class function TAtlasExceptionRules.SuggestPattern(const AMessage: string): string;
var
  mBuilder: TStringBuilder;
  mIndex, mEnd: Integer;
  mChar: Char;
begin
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AMessage) do
    begin
      mChar := AMessage[mIndex];
      mEnd := 0;
      if mChar = cQuote then
      begin
        mEnd := QuoteEnd(AMessage, mIndex);
      end;
      if mEnd > 0 then
      begin
        mBuilder.Append(cWildcard);
        mIndex := mEnd + 1;
        Continue;
      end;
      if CharInSet(mChar, ['0'..'9']) then
      begin
        // Zahl oder Adresse („42“, „0040A1B2“).
        mBuilder.Append(cWildcard);
        while (mIndex <= Length(AMessage)) and CharInSet(AMessage[mIndex], ['0'..'9', 'A'..'F', 'a'..'f']) do
        begin
          Inc(mIndex);
        end;
        Continue;
      end;
      mBuilder.Append(mChar);
      Inc(mIndex);
    end;
    Result := Trim(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
  while Pos(cWildcard + cWildcard, Result) > 0 do
  begin
    Result := StringReplace(Result, cWildcard + cWildcard, cWildcard, [rfReplaceAll]);
  end;
end;

class function TAtlasExceptionRules.FirstMatch(const ARules: TAtlasExceptionRuleList;
  const AFacts: TAtlasExceptionFacts; AKinds: TAtlasExceptionRuleKinds): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ARules) do
  begin
    if (ARules[mIndex].Kind in AKinds) and ARules[mIndex].Matches(AFacts) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasExceptionRules.NeedsAncestors(const ARules: TAtlasExceptionRuleList; const AClass: string;
  AKinds: TAtlasExceptionRuleKinds): Boolean;
var
  mRule: TAtlasExceptionRule;
begin
  for mRule in ARules do
  begin
    if mRule.Enabled and mRule.Descendants and (mRule.Kind in AKinds) and
      not SameText(mRule.ExceptionClass, AClass) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasExceptionRules.Kinds(AMessages, APlaces: Boolean): TAtlasExceptionRuleKinds;
begin
  Result := [];
  if AMessages then
  begin
    Include(Result, TAtlasExceptionRuleKind.Message);
  end;
  if APlaces then
  begin
    Include(Result, TAtlasExceptionRuleKind.Place);
  end;
end;

class function TAtlasExceptionRules.Combined(const APersonal, AProject: TAtlasExceptionRuleList):
  TAtlasExceptionRuleList;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(APersonal) + Length(AProject));
  for mIndex := 0 to High(APersonal) do
  begin
    Result[mIndex] := APersonal[mIndex];
    Result[mIndex].Origin := TAtlasExceptionRuleOrigin.Personal;
  end;
  for mIndex := 0 to High(AProject) do
  begin
    Result[Length(APersonal) + mIndex] := AProject[mIndex];
    Result[Length(APersonal) + mIndex].Origin := TAtlasExceptionRuleOrigin.Project;
  end;
end;

class function TAtlasExceptionRules.MoveRule(var ARules: TAtlasExceptionRuleList; AIndex, ADelta: Integer): Boolean;
var
  mTarget: Integer;
  mRule: TAtlasExceptionRule;
begin
  mTarget := AIndex + ADelta;
  Result := (ADelta <> 0) and (AIndex >= 0) and (AIndex <= High(ARules)) and (mTarget >= 0) and
    (mTarget <= High(ARules));
  if not Result then
  begin
    Exit;
  end;
  ARules := Copy(ARules);
  mRule := ARules[AIndex];
  Delete(ARules, AIndex, 1);
  Insert(mRule, ARules, mTarget);
end;

class function TAtlasExceptionRules.Put(var ARules: TAtlasExceptionRuleList; const ARule: TAtlasExceptionRule): Boolean;
var
  mIndex: Integer;
begin
  Result := ARule.ExceptionClass <> '';
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ARules) do
  begin
    if ARules[mIndex].SameCriteria(ARule) then
    begin
      Result := (ARules[mIndex].Action <> ARule.Action) or (ARules[mIndex].Enabled <> ARule.Enabled);
      // Eigene Kopie: Der Aufrufer kann das Array mit einer anderen Liste teilen.
      ARules := Copy(ARules);
      ARules[mIndex] := ARule;
      Exit;
    end;
  end;
  ARules := ARules + [ARule];
end;

class function TAtlasExceptionRules.ToJson(const ARules: TAtlasExceptionRuleList): TJSONArray;
var
  mRule: TAtlasExceptionRule;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mRule in ARules do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('class', mRule.ExceptionClass);
    mItem.AddPair('message', mRule.Message);
    mItem.AddPair('regex', TJSONBool.Create(mRule.Regex));
    mItem.AddPair('messageMatch', cMatchNames[mRule.MessageMatch]);
    mItem.AddPair('location', mRule.Location);
    mItem.AddPair('action', cActionNames[mRule.Action]);
    mItem.AddPair('enabled', TJSONBool.Create(mRule.Enabled));
    mItem.AddPair('descendants', TJSONBool.Create(mRule.Descendants));
    Result.AddElement(mItem);
  end;
end;

class function TAtlasExceptionRules.SameRules(const ALeft, ARight: TAtlasExceptionRuleList): Boolean;
var
  mLeft, mRight: TJSONArray;
begin
  mLeft := ToJson(ALeft);
  mRight := ToJson(ARight);
  try
    Result := mLeft.ToJSON([]) = mRight.ToJSON([]);
  finally
    mRight.Free;
    mLeft.Free;
  end;
end;

class function TAtlasExceptionRules.WithProjectRules(const AText, ASkeleton: string;
  const ARules: TAtlasExceptionRuleList): string;
var
  mArray: TJSONArray;
  mLineBreak: string;
  mJson: TStringBuilder;
  mIndex: Integer;
begin
  Result := AText;
  if Trim(Result) = '' then
  begin
    Result := ASkeleton;
  end;
  mLineBreak := TTextLines.LineBreakOf(Result);
  mArray := ToJson(ARules);
  mJson := TStringBuilder.Create;
  try
    // Eine Regel je Zeile, lesbar im Diff der eingecheckten Datei.
    mJson.Append('[');
    for mIndex := 0 to mArray.Count - 1 do
    begin
      if mIndex > 0 then
      begin
        mJson.Append(',');
      end;
      mJson.Append(mLineBreak).Append(cRuleIndent).Append(mArray.Items[mIndex].ToJSON([]));
    end;
    if mArray.Count > 0 then
    begin
      mJson.Append(mLineBreak).Append(cArrayIndent);
    end;
    mJson.Append(']');
    Result := TAtlasJsonText.SetValue(Result, cProjectKey, mJson.ToString);
  finally
    mJson.Free;
    mArray.Free;
  end;
end;

function ActionOf(const AName: string): TAtlasExceptionAction;
var
  mAction: TAtlasExceptionAction;
begin
  for mAction := Low(TAtlasExceptionAction) to High(TAtlasExceptionAction) do
  begin
    if SameText(cActionNames[mAction], AName) then
    begin
      Exit(mAction);
    end;
  end;
  Result := TAtlasExceptionAction.Log;
end;

function RuleOf(AObject: TJSONObject; out ARule: TAtlasExceptionRule): Boolean;
var
  mError: string;
begin
  ARule := TAtlasExceptionRule.Create(TJsonRead.TrimmedText(AObject, 'class'), TJsonRead.Text(AObject, 'message'),
    TAtlasMessageMatch.Matches, ActionOf(TJsonRead.Text(AObject, 'action')));
  ARule.Regex := TJsonRead.Flag(AObject, 'regex');
  if SameText(TJsonRead.Text(AObject, 'messageMatch'), cMatchNames[TAtlasMessageMatch.NotMatches]) then
  begin
    ARule.MessageMatch := TAtlasMessageMatch.NotMatches;
  end;
  ARule.Location := TJsonRead.TrimmedText(AObject, 'location');
  ARule.Enabled := TJsonRead.FlagOr(AObject, 'enabled', True);
  ARule.Descendants := TJsonRead.Flag(AObject, 'descendants');
  Result := (ARule.ExceptionClass <> '') and
    (not ARule.HasMessage or TAtlasExceptionRules.ValidPattern(ARule.Message, ARule.Regex, mError));
end;

class function TAtlasExceptionRules.Parse(AValue: TJSONValue): TAtlasExceptionRuleList;
var
  mItem: TJSONValue;
  mRule: TAtlasExceptionRule;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if (mItem is TJSONObject) and RuleOf(TJSONObject(mItem), mRule) then
    begin
      Result := Result + [mRule];
    end;
  end;
end;

class function TAtlasExceptionRules.ActionName(AAction: TAtlasExceptionAction): string;
begin
  Result := cActionNames[AAction];
end;

class function TAtlasExceptionRules.OwnRoutine(const AFrames: TAtlasDebugFrames): string;
var
  mOwn: Integer;
begin
  Result := '';
  mOwn := TAtlasDebugOwnCode.LocationIndex(AFrames, True);
  if mOwn >= 0 then
  begin
    Result := AFrames[mOwn].Routine;
  end;
end;

class function TAtlasExceptionRules.OwnUnit(const AFrames: TAtlasDebugFrames): string;
var
  mOwn: Integer;
begin
  Result := '';
  mOwn := TAtlasDebugOwnCode.LocationIndex(AFrames, True);
  if mOwn >= 0 then
  begin
    Result := UnitOfFile(AFrames[mOwn].FileName);
  end;
end;

class function TAtlasExceptionRules.UnitOfFile(const AFileName: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AFileName.Replace('/', PathDelim)), '');
end;

end.
