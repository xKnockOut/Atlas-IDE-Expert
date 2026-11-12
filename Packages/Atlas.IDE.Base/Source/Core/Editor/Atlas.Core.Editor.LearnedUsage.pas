unit Atlas.Core.Editor.LearnedUsage;

// Lernzähler der gelernten Vorschläge (#1890, suggestions.learnFromUsage): je
// Projektgruppe und Muster, wie oft ein Vorschlag übernommen (Tab, Strg+→ bis
// zum Ende) und verworfen (Esc) wurde, und ob er in der Liste „Gelernte
// Vorschläge“ abgeschaltet ist. Daraus ein Zuschlag in Prozentpunkten auf den
// Anteil, den der Server mit minShare vergleicht: übernommen +3 (höchstens
// +15), verworfen −10 (höchstens −60), abgeschaltet −1000. Fünfmal Esc
// drückt ein Muster mit 100 % also unter die Vorgabe von 70 %.
// Gespeichert als JSON (%LOCALAPPDATA%\Atlas\learned-suggestions.json); Lesen
// und Schreiben der Datei über TAtlasDataFile macht die IDE-Schicht, hier nur
// der Text.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Editor.LearnedSuggestions;

type
  TAtlasLearnedUsage = class
  public const
    cAcceptPoints = 3;
    cAcceptMax = 15;
    cRejectPoints = 10;
    cRejectMax = 60;
    /// <summary>Abgeschaltet: kein Anteil reicht mehr.</summary>
    cOffPoints = -1000;
    /// <summary>Muster je Datei; darüber fallen die ohne Schalter mit den wenigsten Zählern weg.</summary>
    cMaxEntries = 5000;
  private type
    TEntry = record
      Accepted: Integer;
      Rejected: Integer;
      Off: Boolean;
    end;
  private
    /// <summary>Schlüssel: Gruppe + #9 + Kennung.</summary>
    FEntries: TDictionary<string, TEntry>;
    FGroup: string;
    FChanged: Boolean;
    function KeyOf(const AId: string): string;
    function Entry(const AId: string): TEntry;
    procedure Put(const AId: string; const AEntry: TEntry);
    procedure Evict;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Projektgruppe (Pfad der .groupproj bzw. des Projekts); '' ohne.</summary>
    procedure SetGroup(const AGroup: string);
    procedure Accepted(const AId: string);
    procedure Rejected(const AId: string);
    procedure SetOff(const AId: string; AOff: Boolean);
    function IsOff(const AId: string): Boolean;
    /// <summary>Zähler von AId vergessen; der Schalter bleibt.</summary>
    procedure Forget(const AId: string);
    procedure Counts(const AId: string; out AAccepted, ARejected: Integer);
    /// <summary>Zuschlag für AId; AFromUsage False: nur der Schalter zählt.</summary>
    function Adjust(const AId: string; AFromUsage: Boolean): Integer;
    /// <summary>Alle Zuschläge der aktuellen Gruppe ungleich 0.</summary>
    function AdjustList(AFromUsage: Boolean): TArray<TAtlasLearnedAdjust>;
    function Count: Integer;
    procedure Clear;
    /// <summary>Übernimmt AText (Inhalt der Datei); False und leer, wenn er unbrauchbar ist.</summary>
    function FromJson(const AText: string): Boolean;
    function ToJson: string;
    /// <summary>Seit FromJson bzw. MarkSaved geändert.</summary>
    property Changed: Boolean read FChanged;
    procedure MarkSaved;
  end;

implementation

uses
  System.Math;

const
  cSeparator = #9;

{ TAtlasLearnedUsage }

constructor TAtlasLearnedUsage.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TEntry>.Create;
end;

destructor TAtlasLearnedUsage.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

procedure TAtlasLearnedUsage.SetGroup(const AGroup: string);
begin
  FGroup := LowerCase(AGroup);
end;

function TAtlasLearnedUsage.KeyOf(const AId: string): string;
begin
  Result := FGroup + cSeparator + LowerCase(AId);
end;

function TAtlasLearnedUsage.Entry(const AId: string): TEntry;
begin
  if not FEntries.TryGetValue(KeyOf(AId), Result) then
  begin
    Result := Default(TEntry);
  end;
end;

procedure TAtlasLearnedUsage.Put(const AId: string; const AEntry: TEntry);
begin
  if (AEntry.Accepted = 0) and (AEntry.Rejected = 0) and not AEntry.Off then
  begin
    FEntries.Remove(KeyOf(AId));
  end
  else
  begin
    FEntries.AddOrSetValue(KeyOf(AId), AEntry);
    Evict;
  end;
  FChanged := True;
end;

procedure TAtlasLearnedUsage.Evict;
var
  mPair: TPair<string, TEntry>;
  mVictim: string;
  mLeast: Integer;
begin
  // Put fügt höchstens einen Eintrag hinzu: einer fällt weg, der ohne Schalter mit den wenigsten Zählern.
  while FEntries.Count > cMaxEntries do
  begin
    mVictim := '';
    mLeast := MaxInt;
    for mPair in FEntries do
    begin
      if not mPair.Value.Off and (mPair.Value.Accepted + mPair.Value.Rejected < mLeast) then
      begin
        mVictim := mPair.Key;
        mLeast := mPair.Value.Accepted + mPair.Value.Rejected;
      end;
    end;
    if mVictim = '' then
    begin
      Exit;
    end;
    FEntries.Remove(mVictim);
  end;
end;

procedure TAtlasLearnedUsage.Accepted(const AId: string);
var
  mEntry: TEntry;
begin
  mEntry := Entry(AId);
  Inc(mEntry.Accepted);
  Put(AId, mEntry);
end;

procedure TAtlasLearnedUsage.Rejected(const AId: string);
var
  mEntry: TEntry;
begin
  mEntry := Entry(AId);
  Inc(mEntry.Rejected);
  Put(AId, mEntry);
end;

procedure TAtlasLearnedUsage.SetOff(const AId: string; AOff: Boolean);
var
  mEntry: TEntry;
begin
  mEntry := Entry(AId);
  if mEntry.Off <> AOff then
  begin
    mEntry.Off := AOff;
    Put(AId, mEntry);
  end;
end;

function TAtlasLearnedUsage.IsOff(const AId: string): Boolean;
begin
  Result := Entry(AId).Off;
end;

procedure TAtlasLearnedUsage.Forget(const AId: string);
var
  mEntry: TEntry;
begin
  mEntry := Entry(AId);
  mEntry.Accepted := 0;
  mEntry.Rejected := 0;
  Put(AId, mEntry);
end;

procedure TAtlasLearnedUsage.Counts(const AId: string; out AAccepted, ARejected: Integer);
var
  mEntry: TEntry;
begin
  mEntry := Entry(AId);
  AAccepted := mEntry.Accepted;
  ARejected := mEntry.Rejected;
end;

function PointsOf(AAccepted, ARejected: Integer): Integer;
begin
  Result := Min(AAccepted * TAtlasLearnedUsage.cAcceptPoints, TAtlasLearnedUsage.cAcceptMax) -
    Min(ARejected * TAtlasLearnedUsage.cRejectPoints, TAtlasLearnedUsage.cRejectMax);
end;

function TAtlasLearnedUsage.Adjust(const AId: string; AFromUsage: Boolean): Integer;
var
  mEntry: TEntry;
begin
  mEntry := Entry(AId);
  Result := 0;
  if mEntry.Off then
  begin
    Result := cOffPoints;
  end
  else if AFromUsage then
  begin
    Result := PointsOf(mEntry.Accepted, mEntry.Rejected);
  end;
end;

function TAtlasLearnedUsage.AdjustList(AFromUsage: Boolean): TArray<TAtlasLearnedAdjust>;
var
  mPair: TPair<string, TEntry>;
  mItem: TAtlasLearnedAdjust;
  mPrefix: string;
begin
  Result := nil;
  mPrefix := FGroup + cSeparator;
  for mPair in FEntries do
  begin
    if not mPair.Key.StartsWith(mPrefix) then
    begin
      Continue;
    end;
    mItem.Id := Copy(mPair.Key, Length(mPrefix) + 1, MaxInt);
    mItem.By := 0;
    if mPair.Value.Off then
    begin
      mItem.By := cOffPoints;
    end
    else if AFromUsage then
    begin
      mItem.By := PointsOf(mPair.Value.Accepted, mPair.Value.Rejected);
    end;
    if mItem.By <> 0 then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

function TAtlasLearnedUsage.Count: Integer;
begin
  Result := FEntries.Count;
end;

function TAtlasLearnedUsage.FromJson(const AText: string): Boolean;
var
  mRoot, mGroups, mPatterns, mItem: TJSONValue;
  mGroup, mPattern: TJSONPair;
  mEntry: TEntry;
begin
  FEntries.Clear;
  FChanged := False;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := (mRoot is TJSONObject) and TJSONObject(mRoot).TryGetValue<TJSONValue>('groups', mGroups) and
      (mGroups is TJSONObject);
    if not Result then
    begin
      Exit;
    end;
    for mGroup in TJSONObject(mGroups) do
    begin
      mPatterns := mGroup.JsonValue;
      if not (mPatterns is TJSONObject) then
      begin
        Continue;
      end;
      for mPattern in TJSONObject(mPatterns) do
      begin
        mItem := mPattern.JsonValue;
        mEntry := Default(TEntry);
        if mItem is TJSONObject then
        begin
          mItem.TryGetValue<Integer>('accepted', mEntry.Accepted);
          mItem.TryGetValue<Integer>('rejected', mEntry.Rejected);
          mItem.TryGetValue<Boolean>('off', mEntry.Off);
          mEntry.Accepted := Max(mEntry.Accepted, 0);
          mEntry.Rejected := Max(mEntry.Rejected, 0);
          FEntries.AddOrSetValue(LowerCase(mGroup.JsonString.Value) + cSeparator +
            LowerCase(mPattern.JsonString.Value), mEntry);
        end;
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasLearnedUsage.Clear;
begin
  if FEntries.Count > 0 then
  begin
    FEntries.Clear;
    FChanged := True;
  end;
end;

procedure TAtlasLearnedUsage.MarkSaved;
begin
  FChanged := False;
end;

function TAtlasLearnedUsage.ToJson: string;
var
  mRoot, mGroups, mGroup, mItem: TJSONObject;
  mPair: TPair<string, TEntry>;
  mName, mId: string;
  mAt: Integer;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(1));
    mGroups := TJSONObject.Create;
    mRoot.AddPair('groups', mGroups);
    for mPair in FEntries do
    begin
      mAt := Pos(cSeparator, mPair.Key);
      mName := Copy(mPair.Key, 1, mAt - 1);
      mId := Copy(mPair.Key, mAt + 1, MaxInt);
      if not (mGroups.GetValue(mName) is TJSONObject) then
      begin
        mGroups.AddPair(mName, TJSONObject.Create);
      end;
      mGroup := TJSONObject(mGroups.GetValue(mName));
      mItem := TJSONObject.Create;
      mItem.AddPair('accepted', TJSONNumber.Create(mPair.Value.Accepted));
      mItem.AddPair('rejected', TJSONNumber.Create(mPair.Value.Rejected));
      mItem.AddPair('off', TJSONBool.Create(mPair.Value.Off));
      mGroup.AddPair(mId, mItem);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

end.
