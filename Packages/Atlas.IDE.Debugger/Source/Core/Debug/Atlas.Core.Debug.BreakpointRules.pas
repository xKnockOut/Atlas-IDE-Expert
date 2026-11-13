unit Atlas.Core.Debug.BreakpointRules;

// Abhängige Haltepunkte und Trefferbedingungen (#864), Kern ohne IDE.
// Eine Regel hängt an einem Quelltext-Haltepunkt (Datei, Zeile ab 0) und hat
// drei Teile, die alle zutreffen müssen (die Bedingung der IDE prüft die IDE
// selbst, bevor sie hält):
// - Thread-Filter: Name enthält ein Muster (ohne Groß-/Kleinschreibung),
//   genau eine Thread-ID oder nur der Hauptthread. Ein Halt in einem anderen
//   Thread zählt nicht als Treffer.
// - Trefferbedingung: genau beim n-ten, ab dem n-ten oder bei jedem n-ten
//   Treffer; gezählt wird je Debug-Sitzung.
// - Abhängigkeit: Der Haltepunkt ist erst scharf, nachdem der auslösende
//   (Datei, Zeile) gehalten hat; „bis zum Ende“ bleibt er scharf, „einmal“
//   wird er nach seinem Halt wieder unscharf, bis der auslösende erneut hält.
// Decide sagt bei einem Halt an der Zeile der Regel, ob Atlas anhält oder
// weiterlaufen lässt, und führt Zählung und Scharfschaltung im Zustand nach.
// JSON: {"format": 1, "rules": [{"file", "line" (ab 1), "hit", "hitCount",
// "thread", "threadText", "threadId", "triggerFile", "triggerLine" (ab 1),
// "depend"}]}; Namen der Aufzählungen klein wie unten.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TAtlasHitMode = (Any, Exactly, AtLeast, EveryNth);
  TAtlasThreadFilter = (Any, NameContains, ThreadId, MainThread);
  TAtlasDependMode = (None, UntilEnd, Once);
  TAtlasRuleDecision = (Stop, Continue);
  {$SCOPEDENUMS OFF}

  TAtlasBreakpointRule = record
    FileName: string;
    /// <summary>Zeile des Haltepunkts, ab 0.</summary>
    Line: Integer;
    Hit: TAtlasHitMode;
    HitCount: Integer;
    Thread: TAtlasThreadFilter;
    ThreadText: string;
    ThreadId: Cardinal;
    Depend: TAtlasDependMode;
    TriggerFile: string;
    /// <summary>Zeile des auslösenden Haltepunkts, ab 0.</summary>
    TriggerLine: Integer;
    /// <summary>Keine Regel gesetzt (alles Vorgabe)?</summary>
    function IsEmpty: Boolean;
    function HasTrigger: Boolean;
    /// <summary>Hängt diese Regel an AFileName/ALine als Auslöser?</summary>
    function TriggeredBy(const AFileName: string; ALine: Integer): Boolean;
  end;

  TAtlasBreakpointRuleList = TArray<TAtlasBreakpointRule>;

  /// <summary>Zustand einer Regel in der laufenden Sitzung.</summary>
  TAtlasRuleState = record
    Hits: Integer;
    /// <summary>Abhängiger Haltepunkt scharf (der auslösende hat gehalten)?</summary>
    Armed: Boolean;
    class function Start(const ARule: TAtlasBreakpointRule): TAtlasRuleState; static;
  end;

  /// <summary>Thread des Halts.</summary>
  TAtlasStopThread = record
    Name: string;
    Id: Cardinal;
    MainId: Cardinal;
    class function Create(const AName: string; AId, AMainId: Cardinal): TAtlasStopThread; static;
  end;

  TAtlasBreakpointRules = class
  public const
    cFormat = 1;
  public
    /// <summary>Trifft die Bedingung beim Treffer Nummer AHit (ab 1) zu? Zahlen unter 1 gelten als 1.</summary>
    class function HitMatches(AMode: TAtlasHitMode; ACount, AHit: Integer): Boolean; static;
    class function ThreadMatches(const ARule: TAtlasBreakpointRule; const AThread: TAtlasStopThread): Boolean;
      static;
    /// <summary>Halt an der Zeile von ARule: anhalten oder weiterlaufen; zählt Treffer, macht „einmal“ wieder
    /// unscharf.</summary>
    class function Decide(const ARule: TAtlasBreakpointRule; var AState: TAtlasRuleState;
      const AThread: TAtlasStopThread): TAtlasRuleDecision; static;
    /// <summary>Halt am Auslöser einer abhängigen Regel: scharf schalten. True, wenn sie vorher unscharf war.
    /// </summary>
    class function Arm(const ARule: TAtlasBreakpointRule; var AState: TAtlasRuleState): Boolean; static;
    /// <summary>Soll der Haltepunkt der Regel in der IDE eingeschaltet sein?</summary>
    class function ShouldBeEnabled(const ARule: TAtlasBreakpointRule; const AState: TAtlasRuleState): Boolean;
      static;
    /// <summary>Schlüssel für Datei und Zeile (ohne Groß-/Kleinschreibung).</summary>
    class function Key(const AFileName: string; ALine: Integer): string; static;
    class function ToJson(const ARules: TAtlasBreakpointRuleList): string; static;
    /// <summary>False bei fremdem Format; leere Regeln fallen weg.</summary>
    class function Parse(const AJson: string; out ARules: TAtlasBreakpointRuleList): Boolean; static;
    /// <summary>Index der Regel an AFileName/ALine oder -1.</summary>
    class function IndexOf(const ARules: TAtlasBreakpointRuleList; const AFileName: string; ALine: Integer): Integer;
      static;
    /// <summary>ARule eintragen bzw. ersetzen; eine leere Regel entfernt die an derselben Stelle.</summary>
    class procedure Put(var ARules: TAtlasBreakpointRuleList; const ARule: TAtlasBreakpointRule); static;
    /// <summary>Haltepunkt verschoben (#841): Regel und Verweise als Auslöser ziehen mit.</summary>
    class procedure Moved(var ARules: TAtlasBreakpointRuleList; const AFileName: string; AFromLine, AToLine: Integer);
      static;
    class function HitName(AMode: TAtlasHitMode): string; static;
    class function ThreadName(AFilter: TAtlasThreadFilter): string; static;
    class function DependName(AMode: TAtlasDependMode): string; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.Json;

const
  cHitNames: array[TAtlasHitMode] of string = ('any', 'exactly', 'atLeast', 'everyNth');
  cThreadNames: array[TAtlasThreadFilter] of string = ('any', 'nameContains', 'threadId', 'mainThread');
  cDependNames: array[TAtlasDependMode] of string = ('none', 'untilEnd', 'once');

{ TAtlasBreakpointRule }

function TAtlasBreakpointRule.IsEmpty: Boolean;
begin
  Result := (Hit = TAtlasHitMode.Any) and (Thread = TAtlasThreadFilter.Any) and not HasTrigger;
end;

function TAtlasBreakpointRule.HasTrigger: Boolean;
begin
  Result := (Depend <> TAtlasDependMode.None) and (TriggerFile <> '');
end;

function TAtlasBreakpointRule.TriggeredBy(const AFileName: string; ALine: Integer): Boolean;
begin
  Result := HasTrigger and SameText(TriggerFile, AFileName) and (TriggerLine = ALine);
end;

{ TAtlasRuleState }

class function TAtlasRuleState.Start(const ARule: TAtlasBreakpointRule): TAtlasRuleState;
begin
  Result.Hits := 0;
  Result.Armed := not ARule.HasTrigger;
end;

{ TAtlasStopThread }

class function TAtlasStopThread.Create(const AName: string; AId, AMainId: Cardinal): TAtlasStopThread;
begin
  Result.Name := AName;
  Result.Id := AId;
  Result.MainId := AMainId;
end;

{ TAtlasBreakpointRules }

class function TAtlasBreakpointRules.HitMatches(AMode: TAtlasHitMode; ACount, AHit: Integer): Boolean;
var
  mCount: Integer;
begin
  mCount := Max(1, ACount);
  case AMode of
    TAtlasHitMode.Exactly:
      Result := AHit = mCount;
    TAtlasHitMode.AtLeast:
      Result := AHit >= mCount;
    TAtlasHitMode.EveryNth:
      Result := (AHit > 0) and (AHit mod mCount = 0);
  else
    Result := True;
  end;
end;

class function TAtlasBreakpointRules.ThreadMatches(const ARule: TAtlasBreakpointRule;
  const AThread: TAtlasStopThread): Boolean;
begin
  case ARule.Thread of
    TAtlasThreadFilter.NameContains:
      Result := (ARule.ThreadText = '') or ContainsText(AThread.Name, ARule.ThreadText);
    TAtlasThreadFilter.ThreadId:
      Result := AThread.Id = ARule.ThreadId;
    TAtlasThreadFilter.MainThread:
      Result := AThread.Id = AThread.MainId;
  else
    Result := True;
  end;
end;

class function TAtlasBreakpointRules.Decide(const ARule: TAtlasBreakpointRule; var AState: TAtlasRuleState;
  const AThread: TAtlasStopThread): TAtlasRuleDecision;
begin
  Result := TAtlasRuleDecision.Continue;
  // Unscharf (der Haltepunkt war trotzdem an, etwa vom Benutzer eingeschaltet) oder anderer Thread: kein Treffer.
  if not AState.Armed or not ThreadMatches(ARule, AThread) then
  begin
    Exit;
  end;
  Inc(AState.Hits);
  if not HitMatches(ARule.Hit, ARule.HitCount, AState.Hits) then
  begin
    Exit;
  end;
  Result := TAtlasRuleDecision.Stop;
  if ARule.HasTrigger and (ARule.Depend = TAtlasDependMode.Once) then
  begin
    AState.Armed := False;
  end;
end;

class function TAtlasBreakpointRules.Arm(const ARule: TAtlasBreakpointRule; var AState: TAtlasRuleState): Boolean;
begin
  Result := ARule.HasTrigger and not AState.Armed;
  AState.Armed := True;
end;

class function TAtlasBreakpointRules.ShouldBeEnabled(const ARule: TAtlasBreakpointRule;
  const AState: TAtlasRuleState): Boolean;
begin
  Result := not ARule.HasTrigger or AState.Armed;
end;

class function TAtlasBreakpointRules.Key(const AFileName: string; ALine: Integer): string;
begin
  Result := LowerCase(AFileName) + '|' + IntToStr(ALine);
end;

class function TAtlasBreakpointRules.HitName(AMode: TAtlasHitMode): string;
begin
  Result := cHitNames[AMode];
end;

class function TAtlasBreakpointRules.ThreadName(AFilter: TAtlasThreadFilter): string;
begin
  Result := cThreadNames[AFilter];
end;

class function TAtlasBreakpointRules.DependName(AMode: TAtlasDependMode): string;
begin
  Result := cDependNames[AMode];
end;

function RuleJson(const ARule: TAtlasBreakpointRule): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', ARule.FileName);
  Result.AddPair('line', TJSONNumber.Create(ARule.Line + 1));
  Result.AddPair('hit', cHitNames[ARule.Hit]);
  Result.AddPair('hitCount', TJSONNumber.Create(ARule.HitCount));
  Result.AddPair('thread', cThreadNames[ARule.Thread]);
  Result.AddPair('threadText', ARule.ThreadText);
  Result.AddPair('threadId', TJSONNumber.Create(Int64(ARule.ThreadId)));
  Result.AddPair('depend', cDependNames[ARule.Depend]);
  Result.AddPair('triggerFile', ARule.TriggerFile);
  Result.AddPair('triggerLine', TJSONNumber.Create(ARule.TriggerLine + 1));
end;

class function TAtlasBreakpointRules.ToJson(const ARules: TAtlasBreakpointRuleList): string;
var
  mRoot: TJSONObject;
  mList: TJSONArray;
  mRule: TAtlasBreakpointRule;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormat));
    mList := TJSONArray.Create;
    mRoot.AddPair('rules', mList);
    for mRule in ARules do
    begin
      mList.AddElement(RuleJson(mRule));
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

function HitOf(const AName: string): TAtlasHitMode;
var
  mMode: TAtlasHitMode;
begin
  for mMode := Low(TAtlasHitMode) to High(TAtlasHitMode) do
  begin
    if SameText(cHitNames[mMode], AName) then
    begin
      Exit(mMode);
    end;
  end;
  Result := TAtlasHitMode.Any;
end;

function ThreadOf(const AName: string): TAtlasThreadFilter;
var
  mFilter: TAtlasThreadFilter;
begin
  for mFilter := Low(TAtlasThreadFilter) to High(TAtlasThreadFilter) do
  begin
    if SameText(cThreadNames[mFilter], AName) then
    begin
      Exit(mFilter);
    end;
  end;
  Result := TAtlasThreadFilter.Any;
end;

function DependOf(const AName: string): TAtlasDependMode;
var
  mMode: TAtlasDependMode;
begin
  for mMode := Low(TAtlasDependMode) to High(TAtlasDependMode) do
  begin
    if SameText(cDependNames[mMode], AName) then
    begin
      Exit(mMode);
    end;
  end;
  Result := TAtlasDependMode.None;
end;

function RuleOf(AObject: TJSONObject): TAtlasBreakpointRule;
begin
  Result := Default(TAtlasBreakpointRule);
  Result.FileName := TJsonRead.Text(AObject, 'file');
  Result.Line := Max(0, TJsonRead.IntOr(AObject, 'line', 1) - 1);
  Result.Hit := HitOf(TJsonRead.Text(AObject, 'hit'));
  Result.HitCount := Max(1, TJsonRead.IntOr(AObject, 'hitCount', 1));
  Result.Thread := ThreadOf(TJsonRead.Text(AObject, 'thread'));
  Result.ThreadText := TJsonRead.Text(AObject, 'threadText');
  Result.ThreadId := Cardinal(Max(0, TJsonRead.IntOr(AObject, 'threadId', 0)));
  Result.Depend := DependOf(TJsonRead.Text(AObject, 'depend'));
  Result.TriggerFile := TJsonRead.Text(AObject, 'triggerFile');
  Result.TriggerLine := Max(0, TJsonRead.IntOr(AObject, 'triggerLine', 1) - 1);
end;

class function TAtlasBreakpointRules.Parse(const AJson: string; out ARules: TAtlasBreakpointRuleList): Boolean;
var
  mValue: TJSONValue;
  mRoot, mObject: TJSONObject;
  mList: TJSONArray;
  mIndex: Integer;
  mRule: TAtlasBreakpointRule;
begin
  ARules := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mRoot := TJsonRead.AsObject(mValue);
    Result := (mRoot <> nil) and (TJsonRead.IntOr(mRoot, 'format', 0) = cFormat);
    mList := nil;
    if Result then
    begin
      mList := TJsonRead.Items(mRoot, 'rules');
    end;
    if mList = nil then
    begin
      Exit;
    end;
    for mIndex := 0 to mList.Count - 1 do
    begin
      mObject := TJsonRead.AsObject(mList.Items[mIndex]);
      if mObject = nil then
      begin
        Continue;
      end;
      mRule := RuleOf(mObject);
      if (mRule.FileName <> '') and not mRule.IsEmpty then
      begin
        ARules := ARules + [mRule];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasBreakpointRules.IndexOf(const ARules: TAtlasBreakpointRuleList; const AFileName: string;
  ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ARules) do
  begin
    if SameText(ARules[mIndex].FileName, AFileName) and (ARules[mIndex].Line = ALine) then
    begin
      Exit(mIndex);
    end;
  end;
end;

class procedure TAtlasBreakpointRules.Put(var ARules: TAtlasBreakpointRuleList; const ARule: TAtlasBreakpointRule);
var
  mIndex: Integer;
begin
  mIndex := IndexOf(ARules, ARule.FileName, ARule.Line);
  if ARule.IsEmpty then
  begin
    if mIndex >= 0 then
    begin
      Delete(ARules, mIndex, 1);
    end;
  end
  else if mIndex >= 0 then
  begin
    ARules[mIndex] := ARule;
  end
  else
  begin
    ARules := ARules + [ARule];
  end;
end;

class procedure TAtlasBreakpointRules.Moved(var ARules: TAtlasBreakpointRuleList; const AFileName: string;
  AFromLine, AToLine: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ARules) do
  begin
    if SameText(ARules[mIndex].FileName, AFileName) and (ARules[mIndex].Line = AFromLine) then
    begin
      ARules[mIndex].Line := AToLine;
    end;
    if ARules[mIndex].TriggeredBy(AFileName, AFromLine) then
    begin
      ARules[mIndex].TriggerLine := AToLine;
    end;
  end;
end;

end.
