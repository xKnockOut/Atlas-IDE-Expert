unit Atlas.Core.Settings.Groups;

// Gruppen und Sperren der Optionsseite (#890), ohne VCL und ohne Open Tools API.
// Grundlage ist der Plugin-Katalog (schemas/atlas-plugin.schema.json):
// - Hauptschalter einer Einstellung: x-parent (x-key einer booleschen
//   Einstellung, "" = ausdrücklich keiner). Ohne x-parent gilt die Präfixregel:
//   Von "a.b.c" aus wird erst "a.b", dann "a" geprüft; Hauptschalter ist das
//   längste Präfix P, zu dem es eine boolesche Einstellung P oder P.enabled gibt
//   (nie die Einstellung selbst). So gehört editor.minimap.width zu
//   editor.minimap und welcomePage.search.key über welcomePage.search zu
//   welcomePage.enabled.
// - Unterpunkt im Baum: x-node (Kennung aus x-nodes, "" = Hauptknoten des
//   Reiters); ohne x-node erbt die Einstellung den Unterpunkt des nächsten
//   Hauptschalters, der einen hat, sonst liegt sie auf dem Hauptknoten.
// - Hauptschalter (eigener Rahmen auf der Seite): boolesche Einstellung mit
//   Unteroptionen, mit eigenem x-node oder experimentell.
// - Sperre: Ist ein Hauptschalter darüber aus, ist die Einstellung gesperrt
//   (Grund: der äußerste ausgeschaltete). Experimentelle Funktionen samt ihren
//   Unteroptionen sind gesperrt, solange experimental.enabled aus ist; das geht
//   vor. Werte bleiben dabei erhalten, die Sperre wirkt nur auf die Bedienung.
// Fehler im Schema (unbekannter oder nicht boolescher Hauptschalter, Zyklus,
// unbekannter Unterpunkt) stehen in Issues; Update-ConfigDoc.ps1 prüft dasselbe.
// Alle Namen sind Registry-Namen (TAtlasPluginSettings.Load/Save).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Catalog;

type
  /// <summary>Warum eine Einstellung gesperrt ist: nicht, Hauptschalter aus, experimentelle Funktionen aus.</summary>
  TAtlasLockReason = (lrNone, lrMasterOff, lrExperimental);

  TAtlasSettingsLock = record
    Reason: TAtlasLockReason;
    /// <summary>Name des sperrenden Hauptschalters; bei lrExperimental der Hauptschalter der experimentellen
    /// Funktionen.</summary>
    Master: string;
    function Locked: Boolean;
  end;

  /// <summary>Ist der Hauptschalter mit dem Namen AName gerade an (Kontrollkästchen bzw. Auswahl)?</summary>
  TAtlasSettingIsOn = reference to function(const AName: string): Boolean;

  TAtlasSettingsGroups = class
  private
    FNames: TArray<string>;
    FKeys: TArray<string>;
    FParents: TArray<Integer>;
    FNodes: TArray<string>;
    FOwnNode: TArray<Boolean>;
    FExperimental: TArray<Boolean>;
    FBoolean: TArray<Boolean>;
    FChildCount: TArray<Integer>;
    FByName: TDictionary<string, Integer>;
    FByKey: TDictionary<string, Integer>;
    FNodeList: TArray<TAtlasCatalogArea>;
    FIssues: TArray<string>;
    procedure Read(ACatalog: TAtlasSettingsCatalog);
    procedure ResolveParent(AIndex: Integer; const AEntry: TAtlasCatalogEntry);
    procedure CutCycles;
    procedure ResolveNodes;
    function PrefixParent(AIndex: Integer): Integer;
    function BooleanKey(const AKey: string): Integer;
    function Find(const AName: string): Integer;
    procedure AddIssue(const AText: string);
  public
    constructor Create(ACatalog: TAtlasSettingsCatalog);
    destructor Destroy; override;
    /// <summary>Gibt es eine Plugin-Einstellung mit dem Namen AName?</summary>
    function Contains(const AName: string): Boolean;
    /// <summary>Name des direkten Hauptschalters; '' ohne.</summary>
    function ParentOf(const AName: string): string;
    /// <summary>Alle Hauptschalter darüber, der nächste zuerst.</summary>
    function AncestorsOf(const AName: string): TArray<string>;
    /// <summary>Unteroptionen direkt unter AName in Katalogreihenfolge.</summary>
    function ChildrenOf(const AName: string): TArray<string>;
    /// <summary>Unterpunkt (Kennung aus x-nodes); '' = Hauptknoten.</summary>
    function NodeOf(const AName: string): string;
    /// <summary>Hauptschalter mit eigenem Rahmen?</summary>
    function IsMaster(const AName: string): Boolean;
    /// <summary>Experimentell, selbst oder über einen Hauptschalter darüber?</summary>
    function IsExperimental(const AName: string): Boolean;
    /// <summary>Sperre von AName nach dem Zustand der Hauptschalter (AIsOn) und von experimental.enabled.</summary>
    function LockOf(const AName: string; const AIsOn: TAtlasSettingIsOn; AExperimentalOn: Boolean): TAtlasSettingsLock;
    /// <summary>Gibt es den Unterpunkt AId in x-nodes?</summary>
    function HasNode(const AId: string): Boolean;
    /// <summary>Beschriftung des Unterpunkts; AId selbst, wenn unbekannt.</summary>
    function NodeCaption(const AId: string; AEnglish: Boolean): string;
    /// <summary>Namen aller Einstellungen auf dem Unterpunkt AId ('' = Hauptknoten) in Katalogreihenfolge.</summary>
    function NamesOfNode(const AId: string): TArray<string>;
    /// <summary>x-key zum Namen; '' ohne.</summary>
    function KeyOf(const AName: string): string;
    /// <summary>Alle Plugin-Einstellungen in Katalogreihenfolge.</summary>
    property Names: TArray<string> read FNames;
    /// <summary>Unterpunkte aus x-nodes in Schemareihenfolge.</summary>
    property Nodes: TArray<TAtlasCatalogArea> read FNodeList;
    /// <summary>Fehler im Schema; leer, wenn alles stimmt.</summary>
    property Issues: TArray<string> read FIssues;
  end;

implementation

uses
  Atlas.Core.Settings.Experimental;

{ TAtlasSettingsLock }

function TAtlasSettingsLock.Locked: Boolean;
begin
  Result := Reason <> lrNone;
end;

{ TAtlasSettingsGroups }

constructor TAtlasSettingsGroups.Create(ACatalog: TAtlasSettingsCatalog);
begin
  inherited Create;
  FByName := TDictionary<string, Integer>.Create;
  FByKey := TDictionary<string, Integer>.Create;
  Read(ACatalog);
end;

destructor TAtlasSettingsGroups.Destroy;
begin
  FByKey.Free;
  FByName.Free;
  inherited;
end;

procedure TAtlasSettingsGroups.AddIssue(const AText: string);
begin
  FIssues := FIssues + [AText];
end;

procedure TAtlasSettingsGroups.Read(ACatalog: TAtlasSettingsCatalog);
var
  mIndex, mCount: Integer;
  mEntry: TAtlasCatalogEntry;
  mEntries: TArray<TAtlasCatalogEntry>;
begin
  FNodeList := ACatalog.Nodes;
  mEntries := nil;
  for mIndex := 0 to ACatalog.Count - 1 do
  begin
    if ACatalog[mIndex].Source = asPlugin then
    begin
      mEntries := mEntries + [ACatalog[mIndex]];
    end;
  end;
  mCount := Length(mEntries);
  SetLength(FNames, mCount);
  SetLength(FKeys, mCount);
  SetLength(FParents, mCount);
  SetLength(FNodes, mCount);
  SetLength(FOwnNode, mCount);
  SetLength(FExperimental, mCount);
  SetLength(FBoolean, mCount);
  SetLength(FChildCount, mCount);
  for mIndex := 0 to mCount - 1 do
  begin
    mEntry := mEntries[mIndex];
    FNames[mIndex] := mEntry.Name;
    FKeys[mIndex] := mEntry.Key;
    FExperimental[mIndex] := mEntry.Experimental;
    FBoolean[mIndex] := mEntry.Kind = akBoolean;
    FOwnNode[mIndex] := mEntry.HasNode;
    FNodes[mIndex] := mEntry.Node;
    FParents[mIndex] := -1;
    FByName.AddOrSetValue(LowerCase(mEntry.Name), mIndex);
    FByKey.AddOrSetValue(LowerCase(mEntry.Key), mIndex);
  end;
  for mIndex := 0 to mCount - 1 do
  begin
    ResolveParent(mIndex, mEntries[mIndex]);
  end;
  CutCycles;
  ResolveNodes;
  for mIndex := 0 to mCount - 1 do
  begin
    if FParents[mIndex] >= 0 then
    begin
      Inc(FChildCount[FParents[mIndex]]);
    end;
  end;
end;

function TAtlasSettingsGroups.BooleanKey(const AKey: string): Integer;
begin
  if not FByKey.TryGetValue(LowerCase(AKey), Result) or not FBoolean[Result] then
  begin
    Result := -1;
  end;
end;

function TAtlasSettingsGroups.PrefixParent(AIndex: Integer): Integer;
var
  mPrefix: string;
  mDot: Integer;
begin
  Result := -1;
  mPrefix := FKeys[AIndex];
  mDot := mPrefix.LastIndexOf('.');
  while mDot > 0 do
  begin
    mPrefix := mPrefix.Substring(0, mDot);
    Result := BooleanKey(mPrefix);
    if (Result < 0) or (Result = AIndex) then
    begin
      Result := BooleanKey(mPrefix + '.enabled');
    end;
    if (Result >= 0) and (Result <> AIndex) then
    begin
      Exit;
    end;
    Result := -1;
    mDot := mPrefix.LastIndexOf('.');
  end;
end;

procedure TAtlasSettingsGroups.ResolveParent(AIndex: Integer; const AEntry: TAtlasCatalogEntry);
var
  mParent: Integer;
begin
  if not AEntry.HasParent then
  begin
    FParents[AIndex] := PrefixParent(AIndex);
    Exit;
  end;
  if AEntry.Parent = '' then
  begin
    Exit;
  end;
  if not FByKey.TryGetValue(LowerCase(AEntry.Parent), mParent) then
  begin
    AddIssue(Format('%s: unbekannter Hauptschalter x-parent "%s"', [AEntry.Key, AEntry.Parent]));
    Exit;
  end;
  if not FBoolean[mParent] then
  begin
    AddIssue(Format('%s: Hauptschalter x-parent "%s" ist nicht boolesch', [AEntry.Key, AEntry.Parent]));
    Exit;
  end;
  FParents[AIndex] := mParent;
end;

procedure TAtlasSettingsGroups.CutCycles;
var
  mIndex, mCurrent: Integer;
  mSeen: TList<Integer>;
  mPath: string;
begin
  // Jede Kette nach oben endet; sonst wird die Kante der Einstellung gekappt, bei der der Kreis auffällt.
  mSeen := TList<Integer>.Create;
  try
    for mIndex := 0 to High(FParents) do
    begin
      mSeen.Clear;
      mSeen.Add(mIndex);
      mCurrent := FParents[mIndex];
      while (mCurrent >= 0) and not mSeen.Contains(mCurrent) do
      begin
        mSeen.Add(mCurrent);
        mCurrent := FParents[mCurrent];
      end;
      if mCurrent <> mIndex then
      begin
        Continue;
      end;
      mPath := '';
      for mCurrent in mSeen do
      begin
        mPath := mPath + FKeys[mCurrent] + ' → ';
      end;
      AddIssue(Format('Zyklus über x-parent: %s%s', [mPath, FKeys[mIndex]]));
      FParents[mIndex] := -1;
    end;
  finally
    mSeen.Free;
  end;
end;

procedure TAtlasSettingsGroups.ResolveNodes;
var
  mIndex, mCurrent: Integer;
  mOwn: TArray<string>;
begin
  mOwn := Copy(FNodes);
  for mIndex := 0 to High(FNames) do
  begin
    if FOwnNode[mIndex] and (mOwn[mIndex] <> '') and not HasNode(mOwn[mIndex]) then
    begin
      AddIssue(Format('%s: unbekannter Unterpunkt x-node "%s"', [FKeys[mIndex], mOwn[mIndex]]));
    end;
    FNodes[mIndex] := '';
    mCurrent := mIndex;
    while mCurrent >= 0 do
    begin
      if FOwnNode[mCurrent] then
      begin
        FNodes[mIndex] := mOwn[mCurrent];
        Break;
      end;
      mCurrent := FParents[mCurrent];
    end;
  end;
end;

function TAtlasSettingsGroups.Find(const AName: string): Integer;
begin
  if not FByName.TryGetValue(LowerCase(AName), Result) then
  begin
    Result := -1;
  end;
end;

function TAtlasSettingsGroups.Contains(const AName: string): Boolean;
begin
  Result := Find(AName) >= 0;
end;

function TAtlasSettingsGroups.KeyOf(const AName: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := Find(AName);
  if mIndex >= 0 then
  begin
    Result := FKeys[mIndex];
  end;
end;

function TAtlasSettingsGroups.ParentOf(const AName: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := Find(AName);
  if (mIndex >= 0) and (FParents[mIndex] >= 0) then
  begin
    Result := FNames[FParents[mIndex]];
  end;
end;

function TAtlasSettingsGroups.AncestorsOf(const AName: string): TArray<string>;
var
  mCurrent: Integer;
begin
  Result := nil;
  mCurrent := Find(AName);
  if mCurrent < 0 then
  begin
    Exit;
  end;
  mCurrent := FParents[mCurrent];
  while mCurrent >= 0 do
  begin
    Result := Result + [FNames[mCurrent]];
    mCurrent := FParents[mCurrent];
  end;
end;

function TAtlasSettingsGroups.ChildrenOf(const AName: string): TArray<string>;
var
  mIndex, mParent: Integer;
begin
  Result := nil;
  mParent := Find(AName);
  if mParent < 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FParents) do
  begin
    if FParents[mIndex] = mParent then
    begin
      Result := Result + [FNames[mIndex]];
    end;
  end;
end;

function TAtlasSettingsGroups.NodeOf(const AName: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := Find(AName);
  if mIndex >= 0 then
  begin
    Result := FNodes[mIndex];
  end;
end;

function TAtlasSettingsGroups.IsMaster(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := Find(AName);
  Result := (mIndex >= 0) and FBoolean[mIndex] and ((FChildCount[mIndex] > 0) or
    (FOwnNode[mIndex] and (FNodes[mIndex] <> '')) or FExperimental[mIndex]);
end;

function TAtlasSettingsGroups.IsExperimental(const AName: string): Boolean;
var
  mCurrent: Integer;
begin
  Result := False;
  mCurrent := Find(AName);
  while mCurrent >= 0 do
  begin
    if FExperimental[mCurrent] then
    begin
      Exit(True);
    end;
    mCurrent := FParents[mCurrent];
  end;
end;

function TAtlasSettingsGroups.LockOf(const AName: string; const AIsOn: TAtlasSettingIsOn;
  AExperimentalOn: Boolean): TAtlasSettingsLock;
var
  mCurrent: Integer;
begin
  Result := Default(TAtlasSettingsLock);
  mCurrent := Find(AName);
  if mCurrent < 0 then
  begin
    Exit;
  end;
  if not AExperimentalOn and not SameText(AName, TAtlasExperimental.cMasterName) and IsExperimental(AName) then
  begin
    Result.Reason := lrExperimental;
    Result.Master := TAtlasExperimental.cMasterName;
    Exit;
  end;
  // Der äußerste ausgeschaltete Hauptschalter ist der Grund: Erst er muss an.
  mCurrent := FParents[mCurrent];
  while mCurrent >= 0 do
  begin
    if not AIsOn(FNames[mCurrent]) then
    begin
      Result.Reason := lrMasterOff;
      Result.Master := FNames[mCurrent];
    end;
    mCurrent := FParents[mCurrent];
  end;
end;

function TAtlasSettingsGroups.HasNode(const AId: string): Boolean;
var
  mNode: TAtlasCatalogArea;
begin
  for mNode in FNodeList do
  begin
    if SameText(mNode.Id, AId) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasSettingsGroups.NodeCaption(const AId: string; AEnglish: Boolean): string;
var
  mNode: TAtlasCatalogArea;
begin
  Result := AId;
  for mNode in FNodeList do
  begin
    if SameText(mNode.Id, AId) then
    begin
      Result := mNode.Caption;
      if AEnglish and (mNode.CaptionEn <> '') then
      begin
        Result := mNode.CaptionEn;
      end;
    end;
  end;
end;

function TAtlasSettingsGroups.NamesOfNode(const AId: string): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(FNames) do
  begin
    if SameText(FNodes[mIndex], AId) then
    begin
      Result := Result + [FNames[mIndex]];
    end;
  end;
end;

end.
