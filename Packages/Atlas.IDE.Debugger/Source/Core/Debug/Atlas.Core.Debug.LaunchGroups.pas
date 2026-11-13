unit Atlas.Core.Debug.LaunchGroups;

// Mehrere Programme gemeinsam debuggen (#867), ohne IDE: Startverbünde.
// - Gespeichert in der Projektdatei .atlas unter "launchGroups" (für alle im
//   Team; Base liest die Datei und reicht den Wert als JSON-Text weiter):
//     "launchGroups": [{"name": "Server + Client", "items": [
//       {"project": "Server\\Server.dproj", "profile": "Lokal", "debug": true,
//        "wait": "port", "value": 8080, "timeout": 30},
//       {"project": "Client\\Client.dproj", "debug": true}]}]
//   project: Pfad der .dproj relativ zum Ordner der .atlas (absolute Pfade und
//   solche, die mit .. herausführen, entfallen mit Meldung); profile: Name
//   eines Startprofils (#575), leer = Startoptionen des Projekts; debug:
//   Vorgabe true; wait vor dem nächsten Projekt: none (Vorgabe), seconds
//   (value Sekunden), port (bis localhost:value Verbindungen annimmt), window
//   (bis das Programm ein sichtbares Hauptfenster hat); timeout in Sekunden
//   (Vorgabe cDefaultTimeout).
// - TAtlasLaunchGroups.Evaluate wertet eine Wartebedingung aus.
// - TAtlasLaunchRun führt einen Lauf: Projekte in Reihenfolge, je Projekt
//   Starten, dann Warten; ein Fehler oder eine abgelaufene Wartezeit hält den
//   Lauf an, bis der Anwender „Trotzdem weiter“ oder „Alle beenden“ wählt.
//   Text liefert die Zeile der Leiste: "Server ✓ · Client wartet …".
// Zeiten in Millisekunden von außen, damit sich der Ablauf ohne Uhr testen lässt.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TAtlasLaunchWaitKind = (None, Seconds, Port, Window);
  TAtlasLaunchWaitState = (Waiting, Ready, TimedOut);
  TAtlasLaunchItemState = (Pending, Starting, Waiting, Running, Failed, Skipped);
  {$SCOPEDENUMS OFF}

  TAtlasLaunchItem = record
    /// <summary>Pfad der .dproj, wie in der Datei (relativ zum Ordner der .atlas).</summary>
    Project: string;
    /// <summary>Startprofil (#575); '' = Startoptionen des Projekts.</summary>
    Profile: string;
    Debug: Boolean;
    Wait: TAtlasLaunchWaitKind;
    /// <summary>Sekunden (Seconds) bzw. Port (Port); sonst 0.</summary>
    Value: Integer;
    TimeoutSeconds: Integer;
    /// <summary>Name für Leiste und Statusfeld: Dateiname ohne Endung ("Server").</summary>
    function Caption: string;
  end;

  TAtlasLaunchGroup = record
    Name: string;
    Items: TArray<TAtlasLaunchItem>;
  end;

  TAtlasLaunchGroupList = TArray<TAtlasLaunchGroup>;

  TAtlasLaunchGroups = record
  public const
    cKey = 'launchGroups';
    cDefaultTimeout = 30;
    cMaxTimeout = 3600;
    cMaxPort = 65535;
  public
    /// <summary>Verbünde aus dem Wert von "launchGroups" (JSON-Text); AProblems nennt übergangene Einträge
    /// (Pfad in der Datei, etwa "launchGroups[0].items[1].project").</summary>
    class function Parse(const AJson: string; out AProblems: TArray<string>): TAtlasLaunchGroupList; static;
    /// <summary>JSON-Text für "launchGroups" (Vorgaben werden weggelassen).</summary>
    class function ToJson(const AGroups: TAtlasLaunchGroupList): string; static;
    /// <summary>Index des Verbunds AName (ohne Groß-/Kleinschreibung) oder -1.</summary>
    class function IndexOf(const AGroups: TAtlasLaunchGroupList; const AName: string): Integer; static;
    /// <summary>Relativer Pfad, der nicht über den Ordner der Datei hinausführt?</summary>
    class function IsInside(const APath: string): Boolean; static;
    /// <summary>Wartebedingung von AItem nach AElapsedMs; APortOpen bzw. AWindowFound aus der Prüfung.</summary>
    class function Evaluate(const AItem: TAtlasLaunchItem; AElapsedMs: UInt64;
      APortOpen, AWindowFound: Boolean): TAtlasLaunchWaitState; static;
    class function WaitName(AKind: TAtlasLaunchWaitKind): string; static;
  end;

  /// <summary>Texte der Leiste (von der UI-Schicht in der Sprache der IDE).</summary>
  TAtlasLaunchTexts = record
    Done: string;
    Failed: string;
    Starting: string;
    Waiting: string;
  end;

  TAtlasLaunchRun = class
  private
    FGroup: TAtlasLaunchGroup;
    FStates: TArray<TAtlasLaunchItemState>;
    FCurrent: Integer;
    FPhaseMs: UInt64;
    FHalted: Boolean;
  public
    constructor Create(const AGroup: TAtlasLaunchGroup);
    /// <summary>Nächstes Projekt beginnen (Zustand Starting); False, wenn keins mehr kommt oder der Lauf hält.
    /// </summary>
    function Advance(ANowMs: UInt64; out AIndex: Integer): Boolean;
    /// <summary>Laufendes Projekt ist gestartet: jetzt warten (oder gleich fertig ohne Bedingung).</summary>
    procedure Launched(ANowMs: UInt64);
    /// <summary>Wartebedingung prüfen; True, wenn das laufende Projekt fertig ist (der Lauf kann weiter).</summary>
    function Check(ANowMs: UInt64; APortOpen, AWindowFound: Boolean): Boolean;
    /// <summary>Laufendes Projekt gescheitert (Bauen, Start, Wartezeit): Der Lauf hält an.</summary>
    procedure Fail;
    /// <summary>„Trotzdem weiter“: Das gescheiterte Projekt bleibt gescheitert, der Lauf geht weiter.</summary>
    procedure Proceed;
    /// <summary>„Alle beenden“: Rest übersprungen.</summary>
    procedure Cancel;
    function Group: TAtlasLaunchGroup;
    function Current: Integer;
    function State(AIndex: Integer): TAtlasLaunchItemState;
    /// <summary>Wartet der Lauf auf eine Entscheidung nach einem Fehler?</summary>
    function Halted: Boolean;
    /// <summary>Alle Projekte gestartet oder übersprungen.</summary>
    function Finished: Boolean;
    function Text(const ATexts: TAtlasLaunchTexts): string;
  end;

implementation

uses
  System.JSON,
  System.Generics.Collections;

const
  cMsPerSecond = 1000;
  cSeparator = ' · ';
  cWaitNames: array[TAtlasLaunchWaitKind] of string = ('none', 'seconds', 'port', 'window');

{ TAtlasLaunchItem }

function TAtlasLaunchItem.Caption: string;
begin
  Result := ChangeFileExt(ExtractFileName(StringReplace(Project, '/', '\', [rfReplaceAll])), '');
end;

{ TAtlasLaunchGroups }

class function TAtlasLaunchGroups.WaitName(AKind: TAtlasLaunchWaitKind): string;
begin
  Result := cWaitNames[AKind];
end;

function WaitOf(const AName: string; out AKind: TAtlasLaunchWaitKind): Boolean;
var
  mKind: TAtlasLaunchWaitKind;
begin
  for mKind := Low(TAtlasLaunchWaitKind) to High(TAtlasLaunchWaitKind) do
  begin
    if SameText(AName, cWaitNames[mKind]) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  AKind := TAtlasLaunchWaitKind.None;
  Result := False;
end;

class function TAtlasLaunchGroups.IsInside(const APath: string): Boolean;
var
  mParts: TArray<string>;
  mPart: string;
  mDepth: Integer;
begin
  if (APath = '') or CharInSet(APath[1], ['\', '/']) or (Pos(':', APath) > 0) then
  begin
    Exit(False);
  end;
  mDepth := 0;
  mParts := StringReplace(APath, '/', '\', [rfReplaceAll]).Split(['\']);
  for mPart in mParts do
  begin
    if mPart = '..' then
    begin
      Dec(mDepth);
    end
    else if (mPart <> '') and (mPart <> '.') then
    begin
      Inc(mDepth);
    end;
    if mDepth < 0 then
    begin
      Exit(False);
    end;
  end;
  Result := mDepth > 0;
end;

function IntOf(AValue: TJSONValue; out ANumber: Integer): Boolean;
begin
  Result := AValue is TJSONNumber;
  ANumber := 0;
  if Result then
  begin
    ANumber := TJSONNumber(AValue).AsInt;
  end;
end;

/// <summary>Wartebedingung samt Wert prüfen; False bei unbrauchbarer Angabe.</summary>
function ValidWait(var AItem: TAtlasLaunchItem): Boolean;
begin
  case AItem.Wait of
    TAtlasLaunchWaitKind.Seconds:
      Result := (AItem.Value > 0) and (AItem.Value <= TAtlasLaunchGroups.cMaxTimeout);
    TAtlasLaunchWaitKind.Port:
      Result := (AItem.Value > 0) and (AItem.Value <= TAtlasLaunchGroups.cMaxPort);
  else
    AItem.Value := 0;
    Result := True;
  end;
end;

function ReadItem(AObject: TJSONObject; out AItem: TAtlasLaunchItem): Boolean;
var
  mValue: TJSONValue;
  mText: string;
  mTimeout: Integer;
begin
  AItem := Default(TAtlasLaunchItem);
  AItem.Debug := True;
  AItem.TimeoutSeconds := TAtlasLaunchGroups.cDefaultTimeout;
  if not AObject.TryGetValue<string>('project', AItem.Project) or not TAtlasLaunchGroups.IsInside(AItem.Project) then
  begin
    Exit(False);
  end;
  if AObject.TryGetValue<string>('profile', mText) then
  begin
    AItem.Profile := Trim(mText);
  end;
  mValue := AObject.GetValue('debug');
  if mValue is TJSONBool then
  begin
    AItem.Debug := TJSONBool(mValue).AsBoolean;
  end;
  if AObject.TryGetValue<string>('wait', mText) and not WaitOf(mText, AItem.Wait) then
  begin
    Exit(False);
  end;
  IntOf(AObject.GetValue('value'), AItem.Value);
  if IntOf(AObject.GetValue('timeout'), mTimeout) and (mTimeout > 0) and
    (mTimeout <= TAtlasLaunchGroups.cMaxTimeout) then
  begin
    AItem.TimeoutSeconds := mTimeout;
  end;
  Result := ValidWait(AItem);
end;

function ReadGroup(AObject: TJSONObject; const APath: string; var AProblems: TArray<string>;
  out AGroup: TAtlasLaunchGroup): Boolean;
var
  mItems: TJSONArray;
  mIndex: Integer;
  mItem: TAtlasLaunchItem;
begin
  AGroup := Default(TAtlasLaunchGroup);
  if not AObject.TryGetValue<string>('name', AGroup.Name) or (Trim(AGroup.Name) = '') then
  begin
    AProblems := AProblems + [APath + '.name'];
    Exit(False);
  end;
  AGroup.Name := Trim(AGroup.Name);
  if not (AObject.GetValue('items') is TJSONArray) then
  begin
    AProblems := AProblems + [APath + '.items'];
    Exit(False);
  end;
  mItems := TJSONArray(AObject.GetValue('items'));
  for mIndex := 0 to mItems.Count - 1 do
  begin
    if (mItems.Items[mIndex] is TJSONObject) and ReadItem(TJSONObject(mItems.Items[mIndex]), mItem) then
    begin
      AGroup.Items := AGroup.Items + [mItem];
    end
    else
    begin
      AProblems := AProblems + [Format('%s.items[%d]', [APath, mIndex])];
    end;
  end;
  Result := AGroup.Items <> nil;
end;

class function TAtlasLaunchGroups.Parse(const AJson: string; out AProblems: TArray<string>): TAtlasLaunchGroupList;
var
  mRoot: TJSONValue;
  mIndex: Integer;
  mGroup: TAtlasLaunchGroup;
  mPath: string;
begin
  Result := nil;
  AProblems := nil;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mRoot is TJSONArray) then
    begin
      AProblems := [cKey];
      Exit;
    end;
    for mIndex := 0 to TJSONArray(mRoot).Count - 1 do
    begin
      mPath := Format('%s[%d]', [cKey, mIndex]);
      if not (TJSONArray(mRoot).Items[mIndex] is TJSONObject) then
      begin
        AProblems := AProblems + [mPath];
      end
      else if ReadGroup(TJSONObject(TJSONArray(mRoot).Items[mIndex]), mPath, AProblems, mGroup) and
        (IndexOf(Result, mGroup.Name) < 0) then
      begin
        Result := Result + [mGroup];
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

function ItemJson(const AItem: TAtlasLaunchItem): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', AItem.Project);
  if AItem.Profile <> '' then
  begin
    Result.AddPair('profile', AItem.Profile);
  end;
  if not AItem.Debug then
  begin
    Result.AddPair('debug', TJSONBool.Create(False));
  end;
  if AItem.Wait <> TAtlasLaunchWaitKind.None then
  begin
    Result.AddPair('wait', cWaitNames[AItem.Wait]);
  end;
  if AItem.Value <> 0 then
  begin
    Result.AddPair('value', TJSONNumber.Create(AItem.Value));
  end;
  if AItem.TimeoutSeconds <> TAtlasLaunchGroups.cDefaultTimeout then
  begin
    Result.AddPair('timeout', TJSONNumber.Create(AItem.TimeoutSeconds));
  end;
end;

class function TAtlasLaunchGroups.ToJson(const AGroups: TAtlasLaunchGroupList): string;
var
  mRoot: TJSONArray;
  mGroup: TAtlasLaunchGroup;
  mItem: TAtlasLaunchItem;
  mObject: TJSONObject;
  mItems: TJSONArray;
begin
  mRoot := TJSONArray.Create;
  try
    for mGroup in AGroups do
    begin
      mObject := TJSONObject.Create;
      mRoot.AddElement(mObject);
      mObject.AddPair('name', mGroup.Name);
      mItems := TJSONArray.Create;
      mObject.AddPair('items', mItems);
      for mItem in mGroup.Items do
      begin
        mItems.AddElement(ItemJson(mItem));
      end;
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

class function TAtlasLaunchGroups.IndexOf(const AGroups: TAtlasLaunchGroupList; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AGroups) do
  begin
    if SameText(AGroups[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasLaunchGroups.Evaluate(const AItem: TAtlasLaunchItem; AElapsedMs: UInt64;
  APortOpen, AWindowFound: Boolean): TAtlasLaunchWaitState;
var
  mReady: Boolean;
begin
  case AItem.Wait of
    TAtlasLaunchWaitKind.Seconds:
      mReady := AElapsedMs >= UInt64(AItem.Value) * cMsPerSecond;
    TAtlasLaunchWaitKind.Port:
      mReady := APortOpen;
    TAtlasLaunchWaitKind.Window:
      mReady := AWindowFound;
  else
    mReady := True;
  end;
  if mReady then
  begin
    Exit(TAtlasLaunchWaitState.Ready);
  end;
  Result := TAtlasLaunchWaitState.Waiting;
  // Feste Sekunden laufen nie ab; die anderen nach TimeoutSeconds.
  if (AItem.Wait <> TAtlasLaunchWaitKind.Seconds) and (AElapsedMs >= UInt64(AItem.TimeoutSeconds) * cMsPerSecond) then
  begin
    Result := TAtlasLaunchWaitState.TimedOut;
  end;
end;

{ TAtlasLaunchRun }

constructor TAtlasLaunchRun.Create(const AGroup: TAtlasLaunchGroup);
begin
  inherited Create;
  FGroup := AGroup;
  SetLength(FStates, Length(AGroup.Items));
  FCurrent := -1;
end;

function TAtlasLaunchRun.Advance(ANowMs: UInt64; out AIndex: Integer): Boolean;
begin
  AIndex := -1;
  if FHalted or (FCurrent >= High(FStates)) then
  begin
    Exit(False);
  end;
  if (FCurrent >= 0) and (FStates[FCurrent] in [TAtlasLaunchItemState.Starting, TAtlasLaunchItemState.Waiting]) then
  begin
    Exit(False);
  end;
  Inc(FCurrent);
  FStates[FCurrent] := TAtlasLaunchItemState.Starting;
  FPhaseMs := ANowMs;
  AIndex := FCurrent;
  Result := True;
end;

procedure TAtlasLaunchRun.Launched(ANowMs: UInt64);
begin
  if (FCurrent < 0) or (FStates[FCurrent] <> TAtlasLaunchItemState.Starting) then
  begin
    Exit;
  end;
  FPhaseMs := ANowMs;
  FStates[FCurrent] := TAtlasLaunchItemState.Waiting;
  if FGroup.Items[FCurrent].Wait = TAtlasLaunchWaitKind.None then
  begin
    FStates[FCurrent] := TAtlasLaunchItemState.Running;
  end;
end;

function TAtlasLaunchRun.Check(ANowMs: UInt64; APortOpen, AWindowFound: Boolean): Boolean;
var
  mElapsed: UInt64;
begin
  if (FCurrent < 0) or (FStates[FCurrent] <> TAtlasLaunchItemState.Waiting) then
  begin
    Exit((FCurrent >= 0) and (FStates[FCurrent] = TAtlasLaunchItemState.Running));
  end;
  mElapsed := 0;
  if ANowMs > FPhaseMs then
  begin
    mElapsed := ANowMs - FPhaseMs;
  end;
  case TAtlasLaunchGroups.Evaluate(FGroup.Items[FCurrent], mElapsed, APortOpen, AWindowFound) of
    TAtlasLaunchWaitState.Ready:
      FStates[FCurrent] := TAtlasLaunchItemState.Running;
    TAtlasLaunchWaitState.TimedOut:
      Fail;
  end;
  Result := FStates[FCurrent] = TAtlasLaunchItemState.Running;
end;

procedure TAtlasLaunchRun.Fail;
begin
  if FCurrent < 0 then
  begin
    Exit;
  end;
  FStates[FCurrent] := TAtlasLaunchItemState.Failed;
  FHalted := True;
end;

procedure TAtlasLaunchRun.Proceed;
begin
  FHalted := False;
end;

procedure TAtlasLaunchRun.Cancel;
var
  mIndex: Integer;
begin
  FHalted := False;
  for mIndex := FCurrent + 1 to High(FStates) do
  begin
    FStates[mIndex] := TAtlasLaunchItemState.Skipped;
  end;
  FCurrent := High(FStates);
end;

function TAtlasLaunchRun.Group: TAtlasLaunchGroup;
begin
  Result := FGroup;
end;

function TAtlasLaunchRun.Current: Integer;
begin
  Result := FCurrent;
end;

function TAtlasLaunchRun.State(AIndex: Integer): TAtlasLaunchItemState;
begin
  Result := FStates[AIndex];
end;

function TAtlasLaunchRun.Halted: Boolean;
begin
  Result := FHalted;
end;

function TAtlasLaunchRun.Finished: Boolean;
begin
  Result := not FHalted and (FCurrent >= High(FStates)) and ((FCurrent < 0) or
    not (FStates[FCurrent] in [TAtlasLaunchItemState.Starting, TAtlasLaunchItemState.Waiting]));
end;

function TAtlasLaunchRun.Text(const ATexts: TAtlasLaunchTexts): string;
var
  mIndex: Integer;
  mParts: TArray<string>;
  mPart: string;
begin
  mParts := nil;
  for mIndex := 0 to High(FStates) do
  begin
    mPart := FGroup.Items[mIndex].Caption;
    case FStates[mIndex] of
      TAtlasLaunchItemState.Starting:
        mPart := mPart + ' ' + ATexts.Starting;
      TAtlasLaunchItemState.Waiting:
        mPart := mPart + ' ' + ATexts.Waiting;
      TAtlasLaunchItemState.Running:
        mPart := mPart + ' ' + ATexts.Done;
      TAtlasLaunchItemState.Failed:
        mPart := mPart + ' ' + ATexts.Failed;
      TAtlasLaunchItemState.Pending, TAtlasLaunchItemState.Skipped:
        Continue;
    end;
    mParts := mParts + [mPart];
  end;
  Result := string.Join(cSeparator, mParts);
end;

end.
