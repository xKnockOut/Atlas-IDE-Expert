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
  Index, Count: Integer;
  Entry: TAtlasCatalogEntry;
  Entries: TArray<TAtlasCatalogEntry>;
begin
  FNodeList := ACatalog.Nodes;
  Entries := nil;
  for Index := 0 to ACatalog.Count - 1 do
    if ACatalog[Index].Source = asPlugin then
      Entries := Entries + [ACatalog[Index]];
  Count := Length(Entries);
  SetLength(FNames, Count);
  SetLength(FKeys, Count);
  SetLength(FParents, Count);
  SetLength(FNodes, Count);
  SetLength(FOwnNode, Count);
  SetLength(FExperimental, Count);
  SetLength(FBoolean, Count);
  SetLength(FChildCount, Count);
  for Index := 0 to Count - 1 do
  begin
    Entry := Entries[Index];
    FNames[Index] := Entry.Name;
    FKeys[Index] := Entry.Key;
    FExperimental[Index] := Entry.Experimental;
    FBoolean[Index] := Entry.Kind = akBoolean;
    FOwnNode[Index] := Entry.HasNode;
    FNodes[Index] := Entry.Node;
    FParents[Index] := -1;
    FByName.AddOrSetValue(LowerCase(Entry.Name), Index);
    FByKey.AddOrSetValue(LowerCase(Entry.Key), Index);
  end;
  for Index := 0 to Count - 1 do
    ResolveParent(Index, Entries[Index]);
  CutCycles;
  ResolveNodes;
  for Index := 0 to Count - 1 do
    if FParents[Index] >= 0 then
      Inc(FChildCount[FParents[Index]]);
end;

function TAtlasSettingsGroups.BooleanKey(const AKey: string): Integer;
begin
  if not FByKey.TryGetValue(LowerCase(AKey), Result) or not FBoolean[Result] then
    Result := -1;
end;

function TAtlasSettingsGroups.PrefixParent(AIndex: Integer): Integer;
var
  Prefix: string;
  Dot: Integer;
begin
  Result := -1;
  Prefix := FKeys[AIndex];
  Dot := Prefix.LastIndexOf('.');
  while Dot > 0 do
  begin
    Prefix := Prefix.Substring(0, Dot);
    Result := BooleanKey(Prefix);
    if (Result < 0) or (Result = AIndex) then
      Result := BooleanKey(Prefix + '.enabled');
    if (Result >= 0) and (Result <> AIndex) then
      Exit;
    Result := -1;
    Dot := Prefix.LastIndexOf('.');
  end;
end;

procedure TAtlasSettingsGroups.ResolveParent(AIndex: Integer; const AEntry: TAtlasCatalogEntry);
var
  Parent: Integer;
begin
  if not AEntry.HasParent then
  begin
    FParents[AIndex] := PrefixParent(AIndex);
    Exit;
  end;
  if AEntry.Parent = '' then
    Exit;
  if not FByKey.TryGetValue(LowerCase(AEntry.Parent), Parent) then
  begin
    AddIssue(Format('%s: unbekannter Hauptschalter x-parent "%s"', [AEntry.Key, AEntry.Parent]));
    Exit;
  end;
  if not FBoolean[Parent] then
  begin
    AddIssue(Format('%s: Hauptschalter x-parent "%s" ist nicht boolesch', [AEntry.Key, AEntry.Parent]));
    Exit;
  end;
  FParents[AIndex] := Parent;
end;

procedure TAtlasSettingsGroups.CutCycles;
var
  Index, Current: Integer;
  Seen: TList<Integer>;
  Path: string;
begin
  // Jede Kette nach oben endet; sonst wird die Kante der Einstellung gekappt, bei der der Kreis auffällt.
  Seen := TList<Integer>.Create;
  try
    for Index := 0 to High(FParents) do
    begin
      Seen.Clear;
      Seen.Add(Index);
      Current := FParents[Index];
      while (Current >= 0) and not Seen.Contains(Current) do
      begin
        Seen.Add(Current);
        Current := FParents[Current];
      end;
      if Current <> Index then
        Continue;
      Path := '';
      for Current in Seen do
        Path := Path + FKeys[Current] + ' → ';
      AddIssue(Format('Zyklus über x-parent: %s%s', [Path, FKeys[Index]]));
      FParents[Index] := -1;
    end;
  finally
    Seen.Free;
  end;
end;

procedure TAtlasSettingsGroups.ResolveNodes;
var
  Index, Current: Integer;
  Own: TArray<string>;
begin
  Own := Copy(FNodes);
  for Index := 0 to High(FNames) do
  begin
    if FOwnNode[Index] and (Own[Index] <> '') and not HasNode(Own[Index]) then
      AddIssue(Format('%s: unbekannter Unterpunkt x-node "%s"', [FKeys[Index], Own[Index]]));
    FNodes[Index] := '';
    Current := Index;
    while Current >= 0 do
    begin
      if FOwnNode[Current] then
      begin
        FNodes[Index] := Own[Current];
        Break;
      end;
      Current := FParents[Current];
    end;
  end;
end;

function TAtlasSettingsGroups.Find(const AName: string): Integer;
begin
  if not FByName.TryGetValue(LowerCase(AName), Result) then
    Result := -1;
end;

function TAtlasSettingsGroups.Contains(const AName: string): Boolean;
begin
  Result := Find(AName) >= 0;
end;

function TAtlasSettingsGroups.KeyOf(const AName: string): string;
var
  Index: Integer;
begin
  Result := '';
  Index := Find(AName);
  if Index >= 0 then
    Result := FKeys[Index];
end;

function TAtlasSettingsGroups.ParentOf(const AName: string): string;
var
  Index: Integer;
begin
  Result := '';
  Index := Find(AName);
  if (Index >= 0) and (FParents[Index] >= 0) then
    Result := FNames[FParents[Index]];
end;

function TAtlasSettingsGroups.AncestorsOf(const AName: string): TArray<string>;
var
  Current: Integer;
begin
  Result := nil;
  Current := Find(AName);
  if Current < 0 then
    Exit;
  Current := FParents[Current];
  while Current >= 0 do
  begin
    Result := Result + [FNames[Current]];
    Current := FParents[Current];
  end;
end;

function TAtlasSettingsGroups.ChildrenOf(const AName: string): TArray<string>;
var
  Index, Parent: Integer;
begin
  Result := nil;
  Parent := Find(AName);
  if Parent < 0 then
    Exit;
  for Index := 0 to High(FParents) do
    if FParents[Index] = Parent then
      Result := Result + [FNames[Index]];
end;

function TAtlasSettingsGroups.NodeOf(const AName: string): string;
var
  Index: Integer;
begin
  Result := '';
  Index := Find(AName);
  if Index >= 0 then
    Result := FNodes[Index];
end;

function TAtlasSettingsGroups.IsMaster(const AName: string): Boolean;
var
  Index: Integer;
begin
  Index := Find(AName);
  Result := (Index >= 0) and FBoolean[Index] and ((FChildCount[Index] > 0) or
    (FOwnNode[Index] and (FNodes[Index] <> '')) or FExperimental[Index]);
end;

function TAtlasSettingsGroups.IsExperimental(const AName: string): Boolean;
var
  Current: Integer;
begin
  Result := False;
  Current := Find(AName);
  while Current >= 0 do
  begin
    if FExperimental[Current] then
      Exit(True);
    Current := FParents[Current];
  end;
end;

function TAtlasSettingsGroups.LockOf(const AName: string; const AIsOn: TAtlasSettingIsOn;
  AExperimentalOn: Boolean): TAtlasSettingsLock;
var
  Current: Integer;
begin
  Result := Default(TAtlasSettingsLock);
  Current := Find(AName);
  if Current < 0 then
    Exit;
  if not AExperimentalOn and not SameText(AName, TAtlasExperimental.MasterName) and IsExperimental(AName) then
  begin
    Result.Reason := lrExperimental;
    Result.Master := TAtlasExperimental.MasterName;
    Exit;
  end;
  // Der äußerste ausgeschaltete Hauptschalter ist der Grund: Erst er muss an.
  Current := FParents[Current];
  while Current >= 0 do
  begin
    if not AIsOn(FNames[Current]) then
    begin
      Result.Reason := lrMasterOff;
      Result.Master := FNames[Current];
    end;
    Current := FParents[Current];
  end;
end;

function TAtlasSettingsGroups.HasNode(const AId: string): Boolean;
var
  Node: TAtlasCatalogArea;
begin
  for Node in FNodeList do
    if SameText(Node.Id, AId) then
      Exit(True);
  Result := False;
end;

function TAtlasSettingsGroups.NodeCaption(const AId: string; AEnglish: Boolean): string;
var
  Node: TAtlasCatalogArea;
begin
  Result := AId;
  for Node in FNodeList do
    if SameText(Node.Id, AId) then
    begin
      Result := Node.Caption;
      if AEnglish and (Node.CaptionEn <> '') then
        Result := Node.CaptionEn;
    end;
end;

function TAtlasSettingsGroups.NamesOfNode(const AId: string): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(FNames) do
    if SameText(FNodes[Index], AId) then
      Result := Result + [FNames[Index]];
end;

end.
