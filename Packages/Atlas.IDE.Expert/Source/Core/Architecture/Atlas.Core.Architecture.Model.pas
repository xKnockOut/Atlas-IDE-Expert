unit Atlas.Core.Architecture.Model;

// Fenster „Atlas-Architektur“ (#1118), Kern ohne VCL und OTA:
// - Parse liest die Antwort des Befehls atlas.architecture ({"enabled",
//   "root", "format": "json", "data"} mit den Daten aus
//   TArchitectureReport.Json, Format 1) in Datensätze. Pfade bleiben relativ
//   zu Root; FullPath macht sie absolut, Zeilen und Spalten sind 1-basiert
//   (0 = keine Fundstelle).
// - Sorted sortiert die Tabellen stabil (bei Gleichstand nach Name), Matches
//   filtert nach Teilen des Unit-Namens, ShortestPath sucht den kürzesten Weg
//   über uses wie die HTML-Karte.
// - TAtlasArchitecturePalette: Farben der Teilsysteme wie in der HTML-Karte,
//   je für helle und dunkle Themen.
// - TAtlasArchitectureCommands baut die Argumente der Befehle
//   atlas.architecture und atlas.architecture.saveReport.
// - TAtlasArchitectureView rechnet die Karte zwischen Lage (Koordinaten des
//   Servers) und Bildpunkten um: Einpassen, Zoomen um einen Punkt,
//   Verschieben, Treffer einer Unit.

interface

uses
  System.SysUtils,
  System.JSON;

type
  TAtlasArchUnit = record
    Name: string;
    /// <summary>Pfad relativ zu Root mit /.</summary>
    FileName: string;
    Subsystem: Integer;
    /// <summary>Units, die die Unit direkt bzw. über eine Kette im interface-Teil brauchen.</summary>
    Direct: Integer;
    Total: Integer;
    /// <summary>Units, die die Unit selbst einbindet.</summary>
    Uses_: Integer;
    /// <summary>"foundation", "hub" oder ''.</summary>
    Role: string;
    Library_: Boolean;
    X: Double;
    Y: Double;
    /// <summary>Steht in "outliers".</summary>
    Outlier: Boolean;
    /// <summary>Gehört zu einem Zyklus.</summary>
    OnCycle: Boolean;
  end;

  TAtlasArchSubsystem = record
    Name: string;
    Units: TArray<Integer>;
    /// <summary>Zentralste Unit, -1 ohne.</summary>
    Central: Integer;
    Inner: Integer;
    Outer: Integer;
    /// <summary>0..1.</summary>
    Cohesion: Double;
    /// <summary>Sammelgruppe der Units ohne uses-Beziehung.</summary>
    Isolated: Boolean;
    X: Double;
    Y: Double;
    R: Double;
  end;

  TAtlasArchEdge = record
    Source: Integer;
    Target: Integer;
    Interface_: Boolean;
  end;

  /// <summary>uses-Eintrag mit Fundstelle (Zyklen, Querverbindungen).</summary>
  TAtlasArchLink = record
    Source: Integer;
    Target: Integer;
    Interface_: Boolean;
    FileName: string;
    Line: Integer;
    Character: Integer;
    /// <summary>Nur Querverbindungen: Teilsysteme, Grund ("rare", "againstDirection"), Kanten hin und zurück.
    /// </summary>
    FromSubsystem: Integer;
    ToSubsystem: Integer;
    Reason: string;
    Forward: Integer;
    Backward: Integer;
  end;

  TAtlasArchCycle = record
    /// <summary>Nur über interface: Compilerfehler F2047.</summary>
    InterfaceOnly: Boolean;
    Units: TArray<Integer>;
    Edges: TArray<TAtlasArchLink>;
  end;

  TAtlasArchOutlier = record
    Unit_: Integer;
    Suggested: Integer;
    /// <summary>"namespace" oder "edges".</summary>
    Reason: string;
    Inside: Integer;
    Toward: Integer;
  end;

{$SCOPEDENUMS ON}
  TAtlasArchColumn = (Name, Subsystem, Direct, Total, Uses_, Role);
{$SCOPEDENUMS OFF}

  TAtlasArchitectureModel = record
  public const
    Format = 1;
  public
    Root: string;
    Title: string;
    /// <summary>"project" oder "projectGroup".</summary>
    Scope: string;
    Created: string;
    IncludeLibrary: Boolean;
    DurationMs: Integer;
    Generation: Int64;
    EdgeCount: Integer;
    InterfaceCycles: Integer;
    /// <summary>Muster aus architecture.exclude (für die Statuszeile).</summary>
    Excludes: TArray<string>;
    Units: TArray<TAtlasArchUnit>;
    Edges: TArray<TAtlasArchEdge>;
    /// <summary>Zentrale Units, die zentralste zuerst.</summary>
    Central: TArray<Integer>;
    Subsystems: TArray<TAtlasArchSubsystem>;
    Outliers: TArray<TAtlasArchOutlier>;
    Cycles: TArray<TAtlasArchCycle>;
    CrossLinks: TArray<TAtlasArchLink>;
    /// <summary>Antwort von atlas.architecture lesen. AEnabled: false bei architecture.enabled = false (dann
    /// True ohne Daten). False bei unlesbarer Antwort oder fremdem Format.</summary>
    class function Parse(const AAnswer: string; out AModel: TAtlasArchitectureModel;
      out AEnabled: Boolean): Boolean; static;
    /// <summary>Absoluter Pfad zu einem Pfad relativ zu Root; absolute Pfade bleiben.</summary>
    function FullPath(const AFileName: string): string;
    /// <summary>Nummer der Unit (ohne Groß-/Kleinschreibung), -1 ohne.</summary>
    function IndexOf(const AName: string): Integer;
    /// <summary>Eintrag in Outliers zur Unit, -1 ohne.</summary>
    function OutlierOf(AUnit: Integer): Integer;
    /// <summary>Jedes Wort aus AFilter kommt im Namen vor (ohne Groß-/Kleinschreibung); leer passt immer.</summary>
    function Matches(AUnit: Integer; const AFilter: string): Boolean;
    /// <summary>AUnits nach ASpalte, stabil: bei Gleichstand nach Name, dann Nummer.</summary>
    function Sorted(const AUnits: TArray<Integer>; AColumn: TAtlasArchColumn; ADescending: Boolean): TArray<Integer>;
    /// <summary>Name des Teilsystems, '' bei ungültiger Nummer.</summary>
    function SubsystemName(ASubsystem: Integer): string;
    /// <summary>"A → B → A" eines Zyklus.</summary>
    function CyclePath(const ACycle: TAtlasArchCycle): string;
    /// <summary>Radius einer Unit auf der Karte (wie die HTML-Karte: wächst mit gesamt abhängig).</summary>
    function NodeRadius(AUnit: Integer): Double;
    /// <summary>Kürzester Weg über uses von AFrom nach ATo (Breitensuche in der Reihenfolge von Edges, wie
    /// die HTML-Karte und find_path mit via ["uses"]). AEdges: Nummern in Edges. Ohne AImplementation nur
    /// interface-Kanten; AHidden (je Teilsystem, nil = keins) sperrt Units ausgeblendeter Teilsysteme.
    /// False ohne Weg und bei AFrom = ATo.</summary>
    function ShortestPath(AFrom, ATo: Integer; AImplementation: Boolean; const AHidden: TArray<Boolean>;
      out AEdges: TArray<Integer>): Boolean;
    /// <summary>„A → B → C“ für einen Weg aus ShortestPath.</summary>
    function PathText(AFrom: Integer; const AEdges: TArray<Integer>): string;
    /// <summary>Weg aus „Weg zwischen Symbolen“ (#1117) auf der Karte: AUnits sind die Units der Kette nach
    /// Namen. Units außerhalb des Umfangs fallen weg, direkte Wiederholungen ebenso. Zwischen zwei Units gilt
    /// die uses-Kante in einer der beiden Richtungen; ohne direkte Kante überbrückt der kürzeste Weg über uses
    /// (mit implementation). AEdges: Nummern in Edges. False, wenn keine Unit im Umfang liegt.</summary>
    function RouteOf(const ANames: TArray<string>; out AUnits, AEdges: TArray<Integer>): Boolean;
    /// <summary>„A → B → C“ zu Units aus RouteOf.</summary>
    function RouteText(const AUnits: TArray<Integer>): string;
    /// <summary>Die Unit gehört zu einem Teilsystem, das AHidden ausblendet.</summary>
    function IsHidden(AUnit: Integer; const AHidden: TArray<Boolean>): Boolean;
  end;

  TAtlasArchitectureCommands = class
  public const
    Command = 'atlas.architecture';
    SaveCommand = 'atlas.architecture.saveReport';
  public
    /// <summary>[uri, {"scope", "includeLibraryUnits", "format": "json"}] für atlas.architecture.</summary>
    class function Arguments(const AProjectUri, AScope: string; AIncludeLibrary: Boolean): string; static;
    /// <summary>[uri, Datei, {"scope", "includeLibraryUnits"}] für atlas.architecture.saveReport.</summary>
    class function SaveArguments(const AProjectUri, AFileName, AScope: string;
      AIncludeLibrary: Boolean): string; static;
    /// <summary>Gespeicherte Datei aus der Antwort von saveReport ({"file", "units"}); '' bei Fehler.</summary>
    class function SavedFile(const AAnswer: string): string; static;
  end;

  TAtlasArchitecturePalette = class
  public const
    Count = 10;
  public
    /// <summary>Farbe des Teilsystems ASubsystem als $00BBGGRR (wie TColor).</summary>
    class function Color(ASubsystem: Integer; ADark: Boolean): Cardinal; static;
    /// <summary>Hintergrund ($00BBGGRR) ist dunkel: Helligkeit unter der Hälfte.</summary>
    class function IsDark(ABackground: Cardinal): Boolean; static;
  end;

  TAtlasArchitectureView = record
  public const
    MinScale = 0.05;
    MaxScale = 8.0;
    /// <summary>Rand beim Einpassen in Bildpunkten.</summary>
    Margin = 20;
  public
    Scale: Double;
    OffsetX: Double;
    OffsetY: Double;
    /// <summary>Alle Teilsysteme in AWidth × AHeight einpassen, höchstens doppelt vergrößert.</summary>
    procedure Fit(const AModel: TAtlasArchitectureModel; AWidth, AHeight: Integer);
    function ScreenX(AX: Double): Double;
    function ScreenY(AY: Double): Double;
    function WorldX(AX: Double): Double;
    function WorldY(AY: Double): Double;
    /// <summary>Um AFactor zoomen; der Punkt unter (AX, AY) bleibt stehen.</summary>
    procedure ZoomAt(AFactor: Double; AX, AY: Double);
    procedure Pan(ADX, ADY: Double);
    /// <summary>Unit unter dem Bildpunkt (AX, AY), bei Überlappung die zuletzt gezeichnete; -1 ohne.</summary>
    function UnitAt(const AModel: TAtlasArchitectureModel; AX, AY: Double): Integer; overload;
    /// <summary>Wie oben, ohne Units ausgeblendeter Teilsysteme (AHidden je Teilsystem).</summary>
    function UnitAt(const AModel: TAtlasArchitectureModel; AX, AY: Double;
      const AHidden: TArray<Boolean>): Integer; overload;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults,
  System.Generics.Collections;

const
  // Wie --c0 … --c9 der HTML-Karte (#RRGGBB), hell bzw. dunkel.
  LightColors: array[0..TAtlasArchitecturePalette.Count - 1] of Cardinal = ($2F6FB3, $7A4FB0, $2E7D4F, $B07A1D,
    $A33C5A, $1B8A8F, $6B6F1D, $C2571A, $4A5AB8, $8A4F3A);
  DarkColors: array[0..TAtlasArchitecturePalette.Count - 1] of Cardinal = ($6AA6E6, $B28BE0, $6CC293, $E0B257,
    $E07A98, $5CC6C9, $C3C75A, $F0945A, $94A0F0, $D09A83);

function IntOf(const AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  Value: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt;
end;

function Int64Of(const AObject: TJSONObject; const AName: string): Int64;
var
  Value: TJSONValue;
begin
  Result := 0;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  // Über den Text: Generationen liegen über 2^32 (Kennung des Index im oberen Teil).
  if Value is TJSONNumber then
    Result := StrToInt64Def(Value.Value, 0);
end;

function FloatOf(const AObject: TJSONObject; const AName: string): Double;
var
  Value: TJSONValue;
begin
  Result := 0;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsDouble;
end;

function TextOf(const AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := Value.Value;
end;

function FlagOf(const AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONBool then
    Result := TJSONBool(Value).AsBoolean;
end;

function ArrayOf(const AObject: TJSONObject; const AName: string): TJSONArray;
var
  Value: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONArray then
    Result := TJSONArray(Value);
end;

function IntsOf(const AObject: TJSONObject; const AName: string): TArray<Integer>;
var
  Items: TJSONArray;
  Index: Integer;
begin
  Result := nil;
  Items := ArrayOf(AObject, AName);
  if Items = nil then
    Exit;
  SetLength(Result, Items.Count);
  for Index := 0 to Items.Count - 1 do
    if Items.Items[Index] is TJSONNumber then
      Result[Index] := TJSONNumber(Items.Items[Index]).AsInt
    else
      Result[Index] := -1;
end;

function LinkOf(const AObject: TJSONObject): TAtlasArchLink;
begin
  Result := Default(TAtlasArchLink);
  Result.Source := IntOf(AObject, 'source', -1);
  Result.Target := IntOf(AObject, 'target', -1);
  Result.Interface_ := TextOf(AObject, 'section') = 'interface';
  Result.FileName := TextOf(AObject, 'file');
  Result.Line := IntOf(AObject, 'line', 0);
  Result.Character := IntOf(AObject, 'character', 0);
  Result.FromSubsystem := IntOf(AObject, 'from', -1);
  Result.ToSubsystem := IntOf(AObject, 'to', -1);
  Result.Reason := TextOf(AObject, 'reason');
  Result.Forward := IntOf(AObject, 'forward', 0);
  Result.Backward := IntOf(AObject, 'backward', 0);
end;

function ValidUnit(const AModel: TAtlasArchitectureModel; AUnit: Integer): Boolean;
begin
  Result := (AUnit >= 0) and (AUnit < Length(AModel.Units));
end;

/// <summary>Verweise auf Units und Teilsysteme prüfen: Ein Fenster soll an fremden Daten nicht scheitern.</summary>
function Consistent(const AModel: TAtlasArchitectureModel): Boolean;
var
  Item: TAtlasArchUnit;
  Edge: TAtlasArchEdge;
  Subsystem: TAtlasArchSubsystem;
  Member: Integer;
  Cycle: TAtlasArchCycle;
  Link: TAtlasArchLink;
  Outlier: TAtlasArchOutlier;
begin
  Result := False;
  for Item in AModel.Units do
    if (Item.Subsystem < 0) or (Item.Subsystem >= Length(AModel.Subsystems)) then
      Exit;
  for Edge in AModel.Edges do
    if not ValidUnit(AModel, Edge.Source) or not ValidUnit(AModel, Edge.Target) then
      Exit;
  for Member in AModel.Central do
    if not ValidUnit(AModel, Member) then
      Exit;
  for Subsystem in AModel.Subsystems do
    for Member in Subsystem.Units do
      if not ValidUnit(AModel, Member) then
        Exit;
  for Cycle in AModel.Cycles do
  begin
    for Member in Cycle.Units do
      if not ValidUnit(AModel, Member) then
        Exit;
    for Link in Cycle.Edges do
      if not ValidUnit(AModel, Link.Source) or not ValidUnit(AModel, Link.Target) then
        Exit;
  end;
  for Link in AModel.CrossLinks do
    if not ValidUnit(AModel, Link.Source) or not ValidUnit(AModel, Link.Target) then
      Exit;
  for Outlier in AModel.Outliers do
    if not ValidUnit(AModel, Outlier.Unit_) then
      Exit;
  Result := True;
end;

{ TAtlasArchitectureModel }

class function TAtlasArchitectureModel.Parse(const AAnswer: string; out AModel: TAtlasArchitectureModel;
  out AEnabled: Boolean): Boolean;
var
  Root: TJSONValue;
  Answer, Data, Item, Summary: TJSONObject;
  Items, Pair: TJSONArray;
  Index, Inner: Integer;
begin
  AModel := Default(TAtlasArchitectureModel);
  AEnabled := False;
  Result := False;
  Root := TJSONObject.ParseJSONValue(AAnswer);
  try
    if not (Root is TJSONObject) then
      Exit;
    Answer := TJSONObject(Root);
    AEnabled := FlagOf(Answer, 'enabled');
    if not AEnabled then
      Exit(Answer.GetValue('enabled') is TJSONBool);
    if not (Answer.GetValue('data') is TJSONObject) then
      Exit;
    Data := TJSONObject(Answer.GetValue('data'));
    if IntOf(Data, 'format', 0) <> Format then
      Exit;
    AModel.Root := TextOf(Answer, 'root');
    AModel.Title := TextOf(Data, 'title');
    AModel.Scope := TextOf(Data, 'scope');
    AModel.Created := TextOf(Data, 'created');
    AModel.IncludeLibrary := FlagOf(Data, 'includeLibrary');
    AModel.DurationMs := IntOf(Data, 'durationMs', 0);
    AModel.Generation := Int64Of(Data, 'generation');
    if Data.GetValue('summary') is TJSONObject then
    begin
      Summary := TJSONObject(Data.GetValue('summary'));
      AModel.EdgeCount := IntOf(Summary, 'edges', 0);
      AModel.InterfaceCycles := IntOf(Summary, 'interfaceCycles', 0);
    end;
    Items := ArrayOf(Data, 'units');
    if Items <> nil then
    begin
      SetLength(AModel.Units, Items.Count);
      for Index := 0 to Items.Count - 1 do
      begin
        if not (Items.Items[Index] is TJSONObject) then
          Exit;
        Item := TJSONObject(Items.Items[Index]);
        AModel.Units[Index].Name := TextOf(Item, 'name');
        AModel.Units[Index].FileName := TextOf(Item, 'file');
        AModel.Units[Index].Subsystem := IntOf(Item, 'subsystem', -1);
        AModel.Units[Index].Direct := IntOf(Item, 'direct', 0);
        AModel.Units[Index].Total := IntOf(Item, 'total', 0);
        AModel.Units[Index].Uses_ := IntOf(Item, 'uses', 0);
        AModel.Units[Index].Role := TextOf(Item, 'role');
        AModel.Units[Index].Library_ := FlagOf(Item, 'library');
        AModel.Units[Index].X := FloatOf(Item, 'x');
        AModel.Units[Index].Y := FloatOf(Item, 'y');
      end;
    end;
    Items := ArrayOf(Data, 'edges');
    if Items <> nil then
    begin
      SetLength(AModel.Edges, Items.Count);
      for Index := 0 to Items.Count - 1 do
      begin
        if not (Items.Items[Index] is TJSONArray) then
          Exit;
        Pair := TJSONArray(Items.Items[Index]);
        if (Pair.Count < 3) or not (Pair.Items[0] is TJSONNumber) or not (Pair.Items[1] is TJSONNumber) then
          Exit;
        AModel.Edges[Index].Source := TJSONNumber(Pair.Items[0]).AsInt;
        AModel.Edges[Index].Target := TJSONNumber(Pair.Items[1]).AsInt;
        AModel.Edges[Index].Interface_ := Pair.Items[2].Value = 'i';
      end;
    end;
    AModel.Central := IntsOf(Data, 'central');
    Items := ArrayOf(Data, 'excludes');
    if Items <> nil then
    begin
      SetLength(AModel.Excludes, Items.Count);
      for Index := 0 to Items.Count - 1 do
        AModel.Excludes[Index] := Items.Items[Index].Value;
    end;
    Items := ArrayOf(Data, 'subsystems');
    if Items <> nil then
    begin
      SetLength(AModel.Subsystems, Items.Count);
      for Index := 0 to Items.Count - 1 do
      begin
        if not (Items.Items[Index] is TJSONObject) then
          Exit;
        Item := TJSONObject(Items.Items[Index]);
        AModel.Subsystems[Index].Name := TextOf(Item, 'name');
        AModel.Subsystems[Index].Units := IntsOf(Item, 'units');
        AModel.Subsystems[Index].Central := IntOf(Item, 'central', -1);
        AModel.Subsystems[Index].Inner := IntOf(Item, 'inner', 0);
        AModel.Subsystems[Index].Outer := IntOf(Item, 'outer', 0);
        AModel.Subsystems[Index].Cohesion := FloatOf(Item, 'cohesion');
        AModel.Subsystems[Index].Isolated := FlagOf(Item, 'isolated');
        AModel.Subsystems[Index].X := FloatOf(Item, 'x');
        AModel.Subsystems[Index].Y := FloatOf(Item, 'y');
        AModel.Subsystems[Index].R := FloatOf(Item, 'r');
      end;
    end;
    Items := ArrayOf(Data, 'outliers');
    if Items <> nil then
    begin
      SetLength(AModel.Outliers, Items.Count);
      for Index := 0 to Items.Count - 1 do
      begin
        if not (Items.Items[Index] is TJSONObject) then
          Exit;
        Item := TJSONObject(Items.Items[Index]);
        AModel.Outliers[Index].Unit_ := IntOf(Item, 'unit', -1);
        AModel.Outliers[Index].Suggested := IntOf(Item, 'suggested', -1);
        AModel.Outliers[Index].Reason := TextOf(Item, 'reason');
        AModel.Outliers[Index].Inside := IntOf(Item, 'inside', 0);
        AModel.Outliers[Index].Toward := IntOf(Item, 'toward', 0);
      end;
    end;
    Items := ArrayOf(Data, 'cycles');
    if Items <> nil then
    begin
      SetLength(AModel.Cycles, Items.Count);
      for Index := 0 to Items.Count - 1 do
      begin
        if not (Items.Items[Index] is TJSONObject) then
          Exit;
        Item := TJSONObject(Items.Items[Index]);
        AModel.Cycles[Index].InterfaceOnly := FlagOf(Item, 'interfaceOnly');
        AModel.Cycles[Index].Units := IntsOf(Item, 'units');
        Pair := ArrayOf(Item, 'edges');
        if Pair <> nil then
        begin
          SetLength(AModel.Cycles[Index].Edges, Pair.Count);
          for Inner := 0 to Pair.Count - 1 do
            if Pair.Items[Inner] is TJSONObject then
              AModel.Cycles[Index].Edges[Inner] := LinkOf(TJSONObject(Pair.Items[Inner]))
            else
              Exit;
        end;
      end;
    end;
    Items := ArrayOf(Data, 'crossLinks');
    if Items <> nil then
    begin
      SetLength(AModel.CrossLinks, Items.Count);
      for Index := 0 to Items.Count - 1 do
        if Items.Items[Index] is TJSONObject then
          AModel.CrossLinks[Index] := LinkOf(TJSONObject(Items.Items[Index]))
        else
          Exit;
    end;
    if not Consistent(AModel) then
      Exit;
    for Index := 0 to High(AModel.Outliers) do
      AModel.Units[AModel.Outliers[Index].Unit_].Outlier := True;
    for Index := 0 to High(AModel.Cycles) do
      for Inner in AModel.Cycles[Index].Units do
        AModel.Units[Inner].OnCycle := True;
    Result := True;
  finally
    Root.Free;
    if not Result then
      AModel := Default(TAtlasArchitectureModel);
  end;
end;

function TAtlasArchitectureModel.FullPath(const AFileName: string): string;
var
  Name: string;
begin
  Name := StringReplace(AFileName, '/', PathDelim, [rfReplaceAll]);
  Name := StringReplace(Name, '\', PathDelim, [rfReplaceAll]);
  if (Name = '') or (Root = '') or (Name[1] = PathDelim) or ((Length(Name) > 1) and (Name[2] = ':')) then
    Exit(Name);
  Result := IncludeTrailingPathDelimiter(Root) + Name;
end;

function TAtlasArchitectureModel.IndexOf(const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Units) do
    if SameText(Units[Index].Name, AName) then
      Exit(Index);
  Result := -1;
end;

function TAtlasArchitectureModel.OutlierOf(AUnit: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Outliers) do
    if Outliers[Index].Unit_ = AUnit then
      Exit(Index);
  Result := -1;
end;

function TAtlasArchitectureModel.Matches(AUnit: Integer; const AFilter: string): Boolean;
var
  Word, Name: string;
begin
  if (AUnit < 0) or (AUnit > High(Units)) then
    Exit(False);
  Name := LowerCase(Units[AUnit].Name);
  for Word in LowerCase(AFilter).Split([' '], TStringSplitOptions.ExcludeEmpty) do
    if Pos(Word, Name) = 0 then
      Exit(False);
  Result := True;
end;

function TAtlasArchitectureModel.Sorted(const AUnits: TArray<Integer>; AColumn: TAtlasArchColumn;
  ADescending: Boolean): TArray<Integer>;
var
  Model: TAtlasArchitectureModel;
begin
  Result := Copy(AUnits);
  Model := Self;
  TArray.Sort<Integer>(Result, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    var
      Left, Right: TAtlasArchUnit;
    begin
      Left := Model.Units[ALeft];
      Right := Model.Units[ARight];
      case AColumn of
        TAtlasArchColumn.Subsystem:
          Result := CompareText(Model.SubsystemName(Left.Subsystem), Model.SubsystemName(Right.Subsystem));
        TAtlasArchColumn.Direct:
          Result := CompareValue(Left.Direct, Right.Direct);
        TAtlasArchColumn.Total:
          Result := CompareValue(Left.Total, Right.Total);
        TAtlasArchColumn.Uses_:
          Result := CompareValue(Left.Uses_, Right.Uses_);
        TAtlasArchColumn.Role:
          Result := CompareText(Left.Role, Right.Role);
      else
        Result := 0;
      end;
      if ADescending then
        Result := -Result;
      // Gleichstand eindeutig: TArray.Sort ist nicht stabil.
      if Result = 0 then
        Result := CompareText(Left.Name, Right.Name);
      if (Result <> 0) and ADescending and (AColumn = TAtlasArchColumn.Name) then
        Result := -Result;
      if Result = 0 then
        Result := CompareValue(ALeft, ARight);
    end));
end;

function TAtlasArchitectureModel.SubsystemName(ASubsystem: Integer): string;
begin
  if (ASubsystem >= 0) and (ASubsystem < Length(Subsystems)) then
    Result := Subsystems[ASubsystem].Name
  else
    Result := '';
end;

function TAtlasArchitectureModel.CyclePath(const ACycle: TAtlasArchCycle): string;
var
  Member: Integer;
begin
  Result := '';
  for Member in ACycle.Units do
    if (Member >= 0) and (Member < Length(Units)) then
    begin
      if Result <> '' then
        Result := Result + ' → ';
      Result := Result + Units[Member].Name;
    end;
  if (Length(ACycle.Units) > 0) and (ACycle.Units[0] >= 0) and (ACycle.Units[0] < Length(Units)) then
    Result := Result + ' → ' + Units[ACycle.Units[0]].Name;
end;

function TAtlasArchitectureModel.NodeRadius(AUnit: Integer): Double;
begin
  if (AUnit < 0) or (AUnit > High(Units)) then
    Exit(5);
  Result := 5 + Sqrt(Max(0, Units[AUnit].Total)) * 1.8;
end;

function TAtlasArchitectureModel.IsHidden(AUnit: Integer; const AHidden: TArray<Boolean>): Boolean;
var
  Subsystem: Integer;
begin
  Result := False;
  if (AUnit < 0) or (AUnit > High(Units)) then
    Exit;
  Subsystem := Units[AUnit].Subsystem;
  Result := (Subsystem >= 0) and (Subsystem < Length(AHidden)) and AHidden[Subsystem];
end;

function TAtlasArchitectureModel.ShortestPath(AFrom, ATo: Integer; AImplementation: Boolean;
  const AHidden: TArray<Boolean>; out AEdges: TArray<Integer>): Boolean;
var
  Outgoing: TArray<TArray<Integer>>;
  Previous, Queue: TArray<Integer>;
  Head, Tail, Current, Edge, Index: Integer;
  Reached: TArray<Boolean>;
begin
  AEdges := nil;
  Result := False;
  if (AFrom < 0) or (AFrom > High(Units)) or (ATo < 0) or (ATo > High(Units)) or (AFrom = ATo) then
    Exit;
  SetLength(Outgoing, Length(Units));
  for Index := 0 to High(Edges) do
    Outgoing[Edges[Index].Source] := Outgoing[Edges[Index].Source] + [Index];
  SetLength(Previous, Length(Units));
  SetLength(Reached, Length(Units));
  SetLength(Queue, Length(Units));
  Reached[AFrom] := True;
  Previous[AFrom] := -1;
  Queue[0] := AFrom;
  Head := 0;
  Tail := 1;
  while (Head < Tail) and not Reached[ATo] do
  begin
    Current := Queue[Head];
    Inc(Head);
    for Edge in Outgoing[Current] do
    begin
      Index := Edges[Edge].Target;
      if Reached[Index] or (not AImplementation and not Edges[Edge].Interface_) or IsHidden(Index, AHidden) then
        Continue;
      Reached[Index] := True;
      Previous[Index] := Edge;
      Queue[Tail] := Index;
      Inc(Tail);
    end;
  end;
  if not Reached[ATo] then
    Exit;
  Current := ATo;
  while Current <> AFrom do
  begin
    AEdges := TArray<Integer>.Create(Previous[Current]) + AEdges;
    Current := Edges[Previous[Current]].Source;
  end;
  Result := True;
end;

function TAtlasArchitectureModel.PathText(AFrom: Integer; const AEdges: TArray<Integer>): string;
var
  Edge: Integer;
begin
  Result := '';
  if (AFrom < 0) or (AFrom > High(Units)) then
    Exit;
  Result := Units[AFrom].Name;
  for Edge in AEdges do
    if (Edge >= 0) and (Edge <= High(Edges)) then
      Result := Result + ' → ' + Units[Edges[Edge].Target].Name;
end;

function TAtlasArchitectureModel.RouteOf(const ANames: TArray<string>; out AUnits, AEdges: TArray<Integer>): Boolean;
var
  Name: string;
  Unit_, Index, Edge, Previous: Integer;
  Direct: Integer;
  Bridge: TArray<Integer>;
begin
  AUnits := nil;
  AEdges := nil;
  for Name in ANames do
  begin
    Unit_ := IndexOf(Name);
    if (Unit_ < 0) or ((Length(AUnits) > 0) and (AUnits[High(AUnits)] = Unit_)) then
      Continue;
    if Length(AUnits) > 0 then
    begin
      Previous := AUnits[High(AUnits)];
      // Vorwärts zuerst; ein Weg über Vererbung oder Umsetzung kann auch gegen die uses-Richtung laufen.
      Direct := -1;
      for Index := 0 to High(Edges) do
        if (Edges[Index].Source = Previous) and (Edges[Index].Target = Unit_) then
        begin
          Direct := Index;
          Break;
        end;
      if Direct < 0 then
        for Index := 0 to High(Edges) do
          if (Edges[Index].Source = Unit_) and (Edges[Index].Target = Previous) then
          begin
            Direct := Index;
            Break;
          end;
      if Direct >= 0 then
        AEdges := AEdges + [Direct]
      else if ShortestPath(Previous, Unit_, True, nil, Bridge) then
        for Edge in Bridge do
        begin
          AEdges := AEdges + [Edge];
          // Zwischen-Units der Brücke gehören zum Weg (Ziel der letzten Kante ist Unit_ selbst).
          if Edges[Edge].Target <> Unit_ then
            AUnits := AUnits + [Edges[Edge].Target];
        end;
    end;
    AUnits := AUnits + [Unit_];
  end;
  Result := Length(AUnits) > 0;
end;

function TAtlasArchitectureModel.RouteText(const AUnits: TArray<Integer>): string;
var
  Unit_: Integer;
begin
  Result := '';
  for Unit_ in AUnits do
    if (Unit_ >= 0) and (Unit_ <= High(Units)) then
    begin
      if Result <> '' then
        Result := Result + ' → ';
      Result := Result + Units[Unit_].Name;
    end;
end;

{ TAtlasArchitectureCommands }

function Options(const AScope: string; AIncludeLibrary: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('scope', AScope);
  Result.AddPair('includeLibraryUnits', TJSONBool.Create(AIncludeLibrary));
end;

class function TAtlasArchitectureCommands.Arguments(const AProjectUri, AScope: string;
  AIncludeLibrary: Boolean): string;
var
  Items: TJSONArray;
  Option: TJSONObject;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AProjectUri);
    Option := Options(AScope, AIncludeLibrary);
    Option.AddPair('format', 'json');
    Items.AddElement(Option);
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

class function TAtlasArchitectureCommands.SaveArguments(const AProjectUri, AFileName, AScope: string;
  AIncludeLibrary: Boolean): string;
var
  Items: TJSONArray;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AProjectUri);
    Items.Add(AFileName);
    Items.AddElement(Options(AScope, AIncludeLibrary));
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

class function TAtlasArchitectureCommands.SavedFile(const AAnswer: string): string;
var
  Root: TJSONValue;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(AAnswer);
  try
    if Root is TJSONObject then
      Result := TextOf(TJSONObject(Root), 'file');
  finally
    Root.Free;
  end;
end;

{ TAtlasArchitecturePalette }

class function TAtlasArchitecturePalette.Color(ASubsystem: Integer; ADark: Boolean): Cardinal;
var
  Rgb: Cardinal;
  Slot: Integer;
begin
  Slot := Abs(ASubsystem) mod Count;
  if ADark then
    Rgb := DarkColors[Slot]
  else
    Rgb := LightColors[Slot];
  // #RRGGBB → $00BBGGRR.
  Result := ((Rgb and $FF) shl 16) or (Rgb and $FF00) or ((Rgb shr 16) and $FF);
end;

class function TAtlasArchitecturePalette.IsDark(ABackground: Cardinal): Boolean;
var
  Red, Green, Blue: Integer;
begin
  Red := ABackground and $FF;
  Green := (ABackground shr 8) and $FF;
  Blue := (ABackground shr 16) and $FF;
  Result := (Red * 299 + Green * 587 + Blue * 114) div 1000 < 128;
end;

{ TAtlasArchitectureView }

procedure TAtlasArchitectureView.Fit(const AModel: TAtlasArchitectureModel; AWidth, AHeight: Integer);
var
  Subsystem: TAtlasArchSubsystem;
  Left, Top, Right, Bottom: Double;
begin
  Scale := 1;
  OffsetX := AWidth / 2;
  OffsetY := AHeight / 2;
  if Length(AModel.Subsystems) = 0 then
    Exit;
  Left := MaxDouble;
  Top := MaxDouble;
  Right := -MaxDouble;
  Bottom := -MaxDouble;
  for Subsystem in AModel.Subsystems do
  begin
    Left := Min(Left, Subsystem.X - Subsystem.R);
    Top := Min(Top, Subsystem.Y - Subsystem.R);
    Right := Max(Right, Subsystem.X + Subsystem.R);
    Bottom := Max(Bottom, Subsystem.Y + Subsystem.R);
  end;
  Scale := Min(Min((AWidth - 2 * Margin) / Max(1, Right - Left), (AHeight - 2 * Margin) / Max(1, Bottom - Top)), 2);
  Scale := EnsureRange(Scale, MinScale, MaxScale);
  OffsetX := AWidth / 2 - (Left + Right) / 2 * Scale;
  OffsetY := AHeight / 2 - (Top + Bottom) / 2 * Scale;
end;

function TAtlasArchitectureView.ScreenX(AX: Double): Double;
begin
  Result := AX * Scale + OffsetX;
end;

function TAtlasArchitectureView.ScreenY(AY: Double): Double;
begin
  Result := AY * Scale + OffsetY;
end;

function TAtlasArchitectureView.WorldX(AX: Double): Double;
begin
  Result := (AX - OffsetX) / Scale;
end;

function TAtlasArchitectureView.WorldY(AY: Double): Double;
begin
  Result := (AY - OffsetY) / Scale;
end;

procedure TAtlasArchitectureView.ZoomAt(AFactor: Double; AX, AY: Double);
var
  Next: Double;
begin
  Next := EnsureRange(Scale * AFactor, MinScale, MaxScale);
  OffsetX := AX - (AX - OffsetX) * Next / Scale;
  OffsetY := AY - (AY - OffsetY) * Next / Scale;
  Scale := Next;
end;

procedure TAtlasArchitectureView.Pan(ADX, ADY: Double);
begin
  OffsetX := OffsetX + ADX;
  OffsetY := OffsetY + ADY;
end;

function TAtlasArchitectureView.UnitAt(const AModel: TAtlasArchitectureModel; AX, AY: Double): Integer;
begin
  Result := UnitAt(AModel, AX, AY, nil);
end;

function TAtlasArchitectureView.UnitAt(const AModel: TAtlasArchitectureModel; AX, AY: Double;
  const AHidden: TArray<Boolean>): Integer;
var
  Index: Integer;
  X, Y, Radius: Double;
begin
  X := WorldX(AX);
  Y := WorldY(AY);
  // Rückwärts: Später gezeichnete Units liegen oben.
  for Index := High(AModel.Units) downto 0 do
  begin
    if AModel.IsHidden(Index, AHidden) then
      Continue;
    // Mindestens 4 Bildpunkte, damit kleine Units weit herausgezoomt treffbar bleiben.
    Radius := Max(AModel.NodeRadius(Index), 4 / Scale);
    if Sqr(AModel.Units[Index].X - X) + Sqr(AModel.Units[Index].Y - Y) <= Sqr(Radius) then
      Exit(Index);
  end;
  Result := -1;
end;

end.
