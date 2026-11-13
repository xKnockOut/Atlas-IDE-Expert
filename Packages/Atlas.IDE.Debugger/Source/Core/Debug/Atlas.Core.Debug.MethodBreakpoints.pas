unit Atlas.Core.Debug.MethodBreakpoints;

// Haltepunkte auf Methoden nach Name oder Muster (#855), Kern ohne IDE:
// - Anfrage an atlas.server.methodBreakpoints (Muster, Überschreibungen, Überladungen) und Antwort lesen: Treffer mit
//   Datei, Zeile des ersten ausführbaren Befehls und Grund (passt selbst, überschreibt, setzt Interface-Member um).
// - Eine Gruppe ist ein Muster samt Schaltern, Bedingung, „nur protokollieren“ und „Mitwachsen“; ihre Haltepunkte
//   stehen in der IDE in der Haltepunktgruppe mit dem Muster als Namen. Known hält die Schlüssel aller Treffer, die
//   der Benutzer schon gesehen hat (auch abgewählte), damit „Mitwachsen“ nur wirklich neue Methoden ergänzt.
// - TAtlasMethodGroupStore legt die Gruppen je Projekt als JSON ab (persönlich, nicht im Projekt).

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  TAtlasMethodHitReason = (Match, Override_, Implementation_);
  {$SCOPEDENUMS OFF}

  TAtlasMethodHit = record
    FileName: string;
    Uri: string;
    UnitName: string;
    /// <summary>Umgebender Typ; '' bei freien Routinen.</summary>
    Container: string;
    Name: string;
    Signature: string;
    /// <summary>Erster ausführbarer Befehl (ab 0); -1 ohne Quelltext.</summary>
    Line: Integer;
    Reason: TAtlasMethodHitReason;
    /// <summary>Bei Überschreibungen und Umsetzungen: der Treffer, über den sie dazukam.</summary>
    Via: string;
    function HasSource: Boolean;
    /// <summary>TKunde.Speichere bzw. Routine.</summary>
    function DisplayName: string;
    /// <summary>Unit.TKunde.Speichere für Protokollzeilen.</summary>
    function QualifiedName: string;
    /// <summary>Wiedererkennung über Läufe: Unit, Typ, Name und Signatur, klein; hängt nicht an der Zeile.</summary>
    function Key: string;
  end;

  TAtlasMethodHits = TArray<TAtlasMethodHit>;

  TAtlasMethodQuery = record
    Pattern: string;
    Overrides: Boolean;
    Overloads: Boolean;
    class function Create(const APattern: string; AOverrides, AOverloads: Boolean): TAtlasMethodQuery; static;
  end;

  TAtlasMethodAnswer = record
    Hits: TAtlasMethodHits;
    Truncated: Boolean;
    /// <summary>Meldung des Servers bei ungültigem Muster; '' sonst.</summary>
    Error: string;
  end;

  TAtlasMethodGroup = record
    Pattern: string;
    Overrides: Boolean;
    Overloads: Boolean;
    /// <summary>Beim Debug-Start Haltepunkte für neue passende Methoden ergänzen.</summary>
    Grow: Boolean;
    /// <summary>Bedingung aller Haltepunkte der Gruppe; '' = immer.</summary>
    Condition: string;
    /// <summary>Nicht anhalten, nur eine Zeile ins Ereignisprotokoll schreiben.</summary>
    LogOnly: Boolean;
    /// <summary>Schlüssel (TAtlasMethodHit.Key) aller schon gesehenen Treffer.</summary>
    Known: TArray<string>;
    function Query: TAtlasMethodQuery;
    function Knows(const AKey: string): Boolean;
    /// <summary>Nimmt die Schlüssel von AHits zu Known dazu (ohne Doppelte).</summary>
    procedure Learn(const AHits: TAtlasMethodHits);
  end;

  TAtlasMethodGroups = TArray<TAtlasMethodGroup>;

  TAtlasUriToPath = reference to function(const AUri: string): string;

  TAtlasMethodBreakpoints = class
  public const
    cCommand = 'atlas.server.methodBreakpoints';
  public
    /// <summary>JSON-Argumente [{"pattern", "overrides", "overloads"}] für Command.</summary>
    class function Arguments(const AQuery: TAtlasMethodQuery): string; static;
    /// <summary>Antwort von Command lesen; False bei fremdem Format. AUriToPath setzt FileName.</summary>
    class function ReadAnswer(AJson: TJSONValue; const AUriToPath: TAtlasUriToPath;
      out AAnswer: TAtlasMethodAnswer): Boolean; static;
    /// <summary>Treffer mit Quelltext, die AGroup noch nicht kennt (für „Mitwachsen“).</summary>
    class function NewHits(const AGroup: TAtlasMethodGroup; const AHits: TAtlasMethodHits): TAtlasMethodHits; static;
    /// <summary>Zahl der Treffer mit Quelltext.</summary>
    class function WithSource(const AHits: TAtlasMethodHits): Integer; static;
    /// <summary>Name der Haltepunktgruppe in der IDE: das Muster selbst.</summary>
    class function GroupName(const APattern: string): string; static;
  end;

  /// <summary>Gruppen je Projekt (Schlüssel: Projektdatei ohne Groß-/Kleinschreibung); als JSON ablegbar.</summary>
  TAtlasMethodGroupStore = class
  private
    FProjects: TArray<string>;
    FGroups: TArray<TAtlasMethodGroups>;
    function IndexOf(const AProject: string): Integer;
  public
    /// <summary>Gruppen des Projekts in der Reihenfolge des Anlegens.</summary>
    function Groups(const AProject: string): TAtlasMethodGroups;
    /// <summary>Gruppe mit dem Muster AGroup.Pattern anlegen oder ersetzen.</summary>
    procedure Put(const AProject: string; const AGroup: TAtlasMethodGroup);
    /// <summary>Gruppe mit dem Muster APattern entfernen; False, wenn es keine gab.</summary>
    function Remove(const AProject, APattern: string): Boolean;
    function Find(const AProject, APattern: string; out AGroup: TAtlasMethodGroup): Boolean;
    procedure Clear;
    /// <summary>Inhalt aus AText; False bei fremdem Format (der Inhalt bleibt dann leer).</summary>
    function Parse(const AText: string): Boolean;
    function ToText: string;
  end;

implementation

uses
  Atlas.Text.Json;

const
  cReasonNames: array[TAtlasMethodHitReason] of string = ('match', 'override', 'implementation');

{ TAtlasMethodHit }

function TAtlasMethodHit.HasSource: Boolean;
begin
  Result := Line >= 0;
end;

function TAtlasMethodHit.DisplayName: string;
begin
  Result := Name;
  if Container <> '' then
  begin
    Result := Container + '.' + Name;
  end;
end;

function TAtlasMethodHit.QualifiedName: string;
begin
  Result := DisplayName;
  if UnitName <> '' then
  begin
    Result := UnitName + '.' + Result;
  end;
end;

function TAtlasMethodHit.Key: string;
begin
  Result := LowerCase(QualifiedName + '|' + Signature.Replace(' ', ''));
end;

{ TAtlasMethodQuery }

class function TAtlasMethodQuery.Create(const APattern: string; AOverrides, AOverloads: Boolean): TAtlasMethodQuery;
begin
  Result.Pattern := APattern;
  Result.Overrides := AOverrides;
  Result.Overloads := AOverloads;
end;

{ TAtlasMethodGroup }

function TAtlasMethodGroup.Query: TAtlasMethodQuery;
begin
  Result := TAtlasMethodQuery.Create(Pattern, Overrides, Overloads);
end;

function TAtlasMethodGroup.Knows(const AKey: string): Boolean;
var
  mKey: string;
begin
  for mKey in Known do
  begin
    if mKey = AKey then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasMethodGroup.Learn(const AHits: TAtlasMethodHits);
var
  mHit: TAtlasMethodHit;
begin
  for mHit in AHits do
  begin
    if not Knows(mHit.Key) then
    begin
      Known := Known + [mHit.Key];
    end;
  end;
end;

{ TAtlasMethodBreakpoints }

class function TAtlasMethodBreakpoints.Arguments(const AQuery: TAtlasMethodQuery): string;
var
  mRoot: TJSONArray;
  mItem: TJSONObject;
begin
  mRoot := TJSONArray.Create;
  try
    mItem := TJSONObject.Create;
    mRoot.AddElement(mItem);
    mItem.AddPair('pattern', AQuery.Pattern);
    mItem.AddPair('overrides', TJSONBool.Create(AQuery.Overrides));
    mItem.AddPair('overloads', TJSONBool.Create(AQuery.Overloads));
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function ReasonOf(const AName: string): TAtlasMethodHitReason;
var
  mReason: TAtlasMethodHitReason;
begin
  for mReason := Low(TAtlasMethodHitReason) to High(TAtlasMethodHitReason) do
  begin
    if SameText(cReasonNames[mReason], AName) then
    begin
      Exit(mReason);
    end;
  end;
  Result := TAtlasMethodHitReason.Match;
end;

function ReadHit(AItem: TJSONObject; const AUriToPath: TAtlasUriToPath): TAtlasMethodHit;
begin
  Result := Default(TAtlasMethodHit);
  Result.Uri := TJsonRead.StrictText(AItem, 'uri');
  Result.FileName := Result.Uri;
  if Assigned(AUriToPath) then
  begin
    Result.FileName := AUriToPath(Result.Uri);
  end;
  Result.UnitName := TJsonRead.StrictText(AItem, 'unit');
  Result.Container := TJsonRead.StrictText(AItem, 'container');
  Result.Name := TJsonRead.StrictText(AItem, 'name');
  Result.Signature := TJsonRead.StrictText(AItem, 'signature');
  Result.Line := TJsonRead.IntOr(AItem, 'line', -1);
  if not TJsonRead.FlagOr(AItem, 'source', Result.Line >= 0) then
  begin
    Result.Line := -1;
  end;
  Result.Reason := ReasonOf(TJsonRead.StrictText(AItem, 'reason'));
  Result.Via := TJsonRead.StrictText(AItem, 'via');
end;

class function TAtlasMethodBreakpoints.ReadAnswer(AJson: TJSONValue; const AUriToPath: TAtlasUriToPath;
  out AAnswer: TAtlasMethodAnswer): Boolean;
var
  mRoot: TJSONObject;
  mHits: TJSONValue;
  mIndex: Integer;
begin
  AAnswer := Default(TAtlasMethodAnswer);
  Result := (AJson is TJSONObject) and (TJsonRead.IntOr(TJSONObject(AJson), 'format', 0) = 1);
  if not Result then
  begin
    Exit;
  end;
  mRoot := TJSONObject(AJson);
  AAnswer.Error := TJsonRead.StrictText(mRoot, 'error');
  AAnswer.Truncated := TJsonRead.FlagOr(mRoot, 'truncated', False);
  mHits := mRoot.GetValue('hits');
  if mHits is TJSONArray then
  begin
    for mIndex := 0 to TJSONArray(mHits).Count - 1 do
    begin
      if TJSONArray(mHits).Items[mIndex] is TJSONObject then
      begin
        AAnswer.Hits := AAnswer.Hits + [ReadHit(TJSONObject(TJSONArray(mHits).Items[mIndex]), AUriToPath)];
      end;
    end;
  end;
end;

class function TAtlasMethodBreakpoints.NewHits(const AGroup: TAtlasMethodGroup;
  const AHits: TAtlasMethodHits): TAtlasMethodHits;
var
  mHit: TAtlasMethodHit;
begin
  Result := nil;
  for mHit in AHits do
  begin
    if mHit.HasSource and not AGroup.Knows(mHit.Key) then
    begin
      Result := Result + [mHit];
    end;
  end;
end;

class function TAtlasMethodBreakpoints.WithSource(const AHits: TAtlasMethodHits): Integer;
var
  mHit: TAtlasMethodHit;
begin
  Result := 0;
  for mHit in AHits do
  begin
    if mHit.HasSource then
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasMethodBreakpoints.GroupName(const APattern: string): string;
begin
  Result := Trim(APattern);
end;

{ TAtlasMethodGroupStore }

function TAtlasMethodGroupStore.IndexOf(const AProject: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FProjects) do
  begin
    if SameText(FProjects[mIndex], AProject) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasMethodGroupStore.Groups(const AProject: string): TAtlasMethodGroups;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := IndexOf(AProject);
  if mIndex >= 0 then
  begin
    Result := FGroups[mIndex];
  end;
end;

function TAtlasMethodGroupStore.Find(const AProject, APattern: string; out AGroup: TAtlasMethodGroup): Boolean;
var
  mGroup: TAtlasMethodGroup;
begin
  AGroup := Default(TAtlasMethodGroup);
  for mGroup in Groups(AProject) do
  begin
    if SameText(mGroup.Pattern, APattern) then
    begin
      AGroup := mGroup;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasMethodGroupStore.Put(const AProject: string; const AGroup: TAtlasMethodGroup);
var
  mIndex, mGroup: Integer;
begin
  mIndex := IndexOf(AProject);
  if mIndex < 0 then
  begin
    FProjects := FProjects + [AProject];
    SetLength(FGroups, Length(FGroups) + 1);
    mIndex := High(FProjects);
  end;
  for mGroup := 0 to High(FGroups[mIndex]) do
  begin
    if SameText(FGroups[mIndex][mGroup].Pattern, AGroup.Pattern) then
    begin
      FGroups[mIndex][mGroup] := AGroup;
      Exit;
    end;
  end;
  SetLength(FGroups[mIndex], Length(FGroups[mIndex]) + 1);
  FGroups[mIndex][High(FGroups[mIndex])] := AGroup;
end;

function TAtlasMethodGroupStore.Remove(const AProject, APattern: string): Boolean;
var
  mIndex, mGroup: Integer;
begin
  Result := False;
  mIndex := IndexOf(AProject);
  if mIndex < 0 then
  begin
    Exit;
  end;
  for mGroup := 0 to High(FGroups[mIndex]) do
  begin
    if SameText(FGroups[mIndex][mGroup].Pattern, APattern) then
    begin
      Delete(FGroups[mIndex], mGroup, 1);
      Exit(True);
    end;
  end;
end;

procedure TAtlasMethodGroupStore.Clear;
begin
  FProjects := nil;
  FGroups := nil;
end;

function GroupToJson(const AGroup: TAtlasMethodGroup): TJSONObject;
var
  mKnown: TJSONArray;
  mKey: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('pattern', AGroup.Pattern);
  Result.AddPair('overrides', TJSONBool.Create(AGroup.Overrides));
  Result.AddPair('overloads', TJSONBool.Create(AGroup.Overloads));
  Result.AddPair('grow', TJSONBool.Create(AGroup.Grow));
  Result.AddPair('condition', AGroup.Condition);
  Result.AddPair('logOnly', TJSONBool.Create(AGroup.LogOnly));
  mKnown := TJSONArray.Create;
  Result.AddPair('known', mKnown);
  for mKey in AGroup.Known do
  begin
    mKnown.Add(mKey);
  end;
end;

function GroupFromJson(AObject: TJSONObject; out AGroup: TAtlasMethodGroup): Boolean;
var
  mKnown: TJSONValue;
  mIndex: Integer;
begin
  AGroup := Default(TAtlasMethodGroup);
  AGroup.Pattern := TJsonRead.StrictText(AObject, 'pattern');
  Result := AGroup.Pattern <> '';
  if not Result then
  begin
    Exit;
  end;
  AGroup.Overrides := TJsonRead.FlagOr(AObject, 'overrides', True);
  AGroup.Overloads := TJsonRead.FlagOr(AObject, 'overloads', True);
  AGroup.Grow := TJsonRead.FlagOr(AObject, 'grow', False);
  AGroup.Condition := TJsonRead.StrictText(AObject, 'condition');
  AGroup.LogOnly := TJsonRead.FlagOr(AObject, 'logOnly', False);
  mKnown := AObject.GetValue('known');
  if mKnown is TJSONArray then
  begin
    for mIndex := 0 to TJSONArray(mKnown).Count - 1 do
    begin
      if TJSONArray(mKnown).Items[mIndex] is TJSONString then
      begin
        AGroup.Known := AGroup.Known + [TJSONString(TJSONArray(mKnown).Items[mIndex]).Value];
      end;
    end;
  end;
end;

function TAtlasMethodGroupStore.ToText: string;
var
  mRoot, mProject: TJSONObject;
  mProjects, mGroups: TJSONArray;
  mIndex: Integer;
  mGroup: TAtlasMethodGroup;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(1));
    mProjects := TJSONArray.Create;
    mRoot.AddPair('projects', mProjects);
    for mIndex := 0 to High(FProjects) do
    begin
      if FGroups[mIndex] = nil then
      begin
        Continue;
      end;
      mProject := TJSONObject.Create;
      mProjects.AddElement(mProject);
      mProject.AddPair('project', FProjects[mIndex]);
      mGroups := TJSONArray.Create;
      mProject.AddPair('groups', mGroups);
      for mGroup in FGroups[mIndex] do
      begin
        mGroups.AddElement(GroupToJson(mGroup));
      end;
    end;
    // Lesbar mit Umlauten im Muster.
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

function TAtlasMethodGroupStore.Parse(const AText: string): Boolean;
var
  mRoot, mProjects, mGroups: TJSONValue;
  mProject: TJSONObject;
  mIndex, mGroupIndex: Integer;
  mGroup: TAtlasMethodGroup;
  mName: string;
begin
  Clear;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := (mRoot is TJSONObject) and (TJsonRead.IntOr(TJSONObject(mRoot), 'format', 0) = 1);
    if not Result then
    begin
      Exit;
    end;
    mProjects := TJSONObject(mRoot).GetValue('projects');
    if not (mProjects is TJSONArray) then
    begin
      Exit;
    end;
    for mIndex := 0 to TJSONArray(mProjects).Count - 1 do
    begin
      if not (TJSONArray(mProjects).Items[mIndex] is TJSONObject) then
      begin
        Continue;
      end;
      mProject := TJSONObject(TJSONArray(mProjects).Items[mIndex]);
      mName := TJsonRead.StrictText(mProject, 'project');
      mGroups := mProject.GetValue('groups');
      if (mName = '') or not (mGroups is TJSONArray) then
      begin
        Continue;
      end;
      for mGroupIndex := 0 to TJSONArray(mGroups).Count - 1 do
      begin
        if (TJSONArray(mGroups).Items[mGroupIndex] is TJSONObject) and
          GroupFromJson(TJSONObject(TJSONArray(mGroups).Items[mGroupIndex]), mGroup) then
        begin
          Put(mName, mGroup);
        end;
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

end.
