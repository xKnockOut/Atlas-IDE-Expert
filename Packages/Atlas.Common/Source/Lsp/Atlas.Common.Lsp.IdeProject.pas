unit Atlas.Common.Lsp.IdeProject;

// Projektkontext aus der IDE (#396). In der IDE bestimmt die IDE, welche
// Konfiguration und Plattform ein Projekt hat und welche Suchpfade,
// bedingten Symbole und Unit-Namespaces gelten, auch wenn die Optionen noch
// nicht gespeichert sind. Das IDE-Plugin meldet das je Projekt
// - in initialize unter initializationOptions.projectContexts (vor dem
//   ersten Laden der Projekte) und
// - danach bei jeder Änderung als atlas/projectContext.
// Der Server liest die .dproj weiter selbst (Units, Hauptdatei), nimmt aber
// Konfiguration und Plattform der IDE und ersetzt Symbole, Suchpfade und
// Namespaces durch die der IDE. Die Werte kommen roh aus den Projektoptionen;
// $(Name) löst der Server mit den Variablen der Installation auf, relative
// Pfade gelten ab dem Projektordner. Ohne Plugin (CLI, MCP) bleibt es beim
// Lesen der .dproj (#14).
// Präfixe (#452): Unter "naming" ({"field": "F", "parameter": "A", "local": "L",
// "constant": "c"}) meldet das Plugin die Vorgaben der Projektdatei .atlas
// (#486). Sie ändern die Namensvorschläge der Vervollständigung und die
// Prüfregeln naming-prefix und shadowed-name (#1111), nie den Index; eine
// Änderung allein löst deshalb statt OnChanged nur OnNamingChanged aus.
// Formatroutinen (#451): Unter "formatFunctions" ([{"name": "Log", "formatIndex": 0}])
// meldet das Plugin die eigenen Formatroutinen der Projektdatei .atlas; sie gelten
// für die Platzhalter im Parameter-Hint und lösen wie die Präfixe nur OnNamingChanged aus.
// Aktives Projekt (#46): "active": true markiert das aktive Projekt der Gruppe. Gehört
// eine Datei zu mehreren Projekten, gilt es vor der Reihenfolge der Gruppe; ein
// Wechsel lädt nichts neu und löst kein OnChanged aus.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.FormatRoutines,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Rules.Contract;

type
  TIdeProjectContext = record
    /// <summary>Absoluter Pfad der .dproj.</summary>
    Project: string;
    Configuration: string;
    Platform: string;
    /// <summary>Version der laufenden IDE, z. B. "23.0" (#47); '' = vom Server gewählt.</summary>
    BdsVersion: string;
    /// <summary>Symbole, Suchpfade und Namespaces gemeldet; sonst gelten die der .dproj.</summary>
    HasOptions: Boolean;
    Defines: TArray<string>;
    SearchPaths: TArray<string>;
    Namespaces: TArray<string>;
    /// <summary>Bibliothekspfade der IDE für die Plattform; leer = aus der Registry der Installation.</summary>
    LibraryPaths: TArray<string>;
    /// <summary>Präfix-Vorgaben der Projektdatei (#452); nur mit HasNaming, '' = ohne Präfix.</summary>
    Naming: array[TNamingKind] of string;
    HasNaming: array[TNamingKind] of Boolean;
    /// <summary>Präfix für Konstanten (naming.constant, #1111); nur mit HasConstantPrefix, '' = ohne Präfix.
    /// Die Namensvorschläge kennen keine Konstanten, deshalb steht es nicht in Naming.</summary>
    ConstantPrefix: string;
    HasConstantPrefix: Boolean;
    /// <summary>Eigene Formatroutinen der Projektdatei (#451); ohne Name entfällt ein Eintrag.</summary>
    FormatFunctions: TArray<TFormatRoutine>;
    /// <summary>Aktives Projekt der Gruppe (#46); nur mit HasActive gemeldet.</summary>
    Active: Boolean;
    HasActive: Boolean;
    /// <summary>Kontext aus einem JSON-Objekt; Project = '' bei ungültigen Parametern.</summary>
    class function FromJson(const AValue: TJSONValue): TIdeProjectContext; static;
    /// <summary>Vergleichsschlüssel: gleich, wenn sich für Index und Projekt nichts ändert (ohne Naming).</summary>
    function Key: string;
    /// <summary>Vergleichsschlüssel der Präfix-Vorgaben und Formatroutinen.</summary>
    function NamingKey: string;
    /// <summary>Präfix-Vorgaben für die Prüfregeln (#1111): Felder, Parameter, lokale Variablen und Konstanten.
    /// </summary>
    function RuleNaming: TRuleNaming;
    /// <summary>Übernimmt Symbole, Suchpfade und Namespaces in AProject ($(Name) mit AVariables,
    /// Pfade ab dem Projektordner, ohne Doppelte).</summary>
    procedure ApplyTo(var AProject: TProjectInfo; const AVariables: TArray<TPair<string, string>>);
    /// <summary>Bibliothekspfade mit aufgelösten Variablen ($(Platform) aus AProject), ohne Doppelte.</summary>
    function ExpandedLibraryPaths(const AProject: TProjectInfo;
      const AVariables: TArray<TPair<string, string>>): TArray<string>;
  end;

  TIdeProjectChangedEvent = reference to procedure(const AContext: TIdeProjectContext);

  TLspIdeProject = class
  public const
    cMethod = 'atlas/projectContext';
  private
    FLock: TObject;
    FContexts: TDictionary<string, TIdeProjectContext>;
    FOnChanged: TIdeProjectChangedEvent;
    FOnNamingChanged: TIdeProjectChangedEvent;
    FActive: string;
    procedure HandleNotification(const AParams: TJSONValue);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Kontexte aus den Parametern von initialize (initializationOptions.projectContexts).</summary>
    procedure LoadInitialize(const AParams: TJSONValue);
    /// <summary>Merkt sich AContext; True, wenn er neu ist oder sich Key geändert hat (eine neue Präfix-Vorgabe
    /// allein wird gemerkt, ergibt aber False). Threadsicher.</summary>
    function Update(const AContext: TIdeProjectContext): Boolean; overload;
    /// <summary>Wie oben; ANamingChanged: die Präfix-Vorgaben eines bekannten Projekts haben sich geändert.
    /// </summary>
    function Update(const AContext: TIdeProjectContext; out ANamingChanged: Boolean): Boolean; overload;
    /// <summary>Gemeldeter Kontext des Projekts AProjectFile; False ohne. Threadsicher.</summary>
    function Find(const AProjectFile: string; out AContext: TIdeProjectContext): Boolean;
    /// <summary>.dproj des aktiven Projekts der IDE (#46); '' ohne Meldung. Threadsicher.</summary>
    function ActiveProject: string;
    /// <summary>Nach atlas/projectContext mit geändertem Kontext (Thread des Dispatchers).</summary>
    property OnChanged: TIdeProjectChangedEvent read FOnChanged write FOnChanged;
    /// <summary>Nach atlas/projectContext, wenn sich nur die Präfix-Vorgaben geändert haben (#1111): Prüfregeln
    /// wie naming-prefix neu prüfen, das Projekt bleibt geladen. Thread des Dispatchers.</summary>
    property OnNamingChanged: TIdeProjectChangedEvent read FOnNamingChanged write FOnNamingChanged;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Projects.Paths;

const
  cNamingKeys: array[TNamingKind] of string = ('field', 'parameter', 'local');

function StringsOf(AObject: TJSONObject; const AName: string; out AFound: Boolean): TArray<string>;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
begin
  Result := nil;
  AFound := AObject.TryGetValue<TJSONArray>(AName, mItems);
  if not AFound then
  begin
    Exit;
  end;
  for mItem in mItems do
  begin
    if (mItem is TJSONString) and (Trim(mItem.Value) <> '') then
    begin
      Result := Result + [Trim(mItem.Value)];
    end;
  end;
end;

function WithTarget(const AVariables: TArray<TPair<string, string>>; const AProject: TProjectInfo):
  TArray<TPair<string, string>>;
begin
  Result := AVariables + [TPair<string, string>.Create('Platform', AProject.Platform),
    TPair<string, string>.Create('Config', AProject.Config),
    TPair<string, string>.Create('MSBuildProjectDirectory', TProjectPaths.DirectoryOf(AProject.FileName)),
    TPair<string, string>.Create('MSBuildProjectName', TProjectPaths.BaseName(AProject.FileName))];
end;

function UniquePaths(const ABase: string; const AItems: TArray<string>;
  const AVariables: TArray<TPair<string, string>>): TArray<string>;
var
  mKnown: TList<string>;
  mItem, mPath: string;
begin
  Result := nil;
  mKnown := TList<string>.Create;
  try
    for mItem in AItems do
    begin
      mPath := TProjectPaths.ExpandVariables(mItem, AVariables);
      // Verweis auf den geerbten Wert, den die IDE nicht aufgelöst hat: kein Pfad.
      if Pos('$(', mPath) > 0 then
      begin
        Continue;
      end;
      mPath := TProjectPaths.Combine(ABase, mPath);
      if mKnown.Contains(LowerCase(mPath)) then
      begin
        Continue;
      end;
      mKnown.Add(LowerCase(mPath));
      Result := Result + [mPath];
    end;
  finally
    mKnown.Free;
  end;
end;

{ TIdeProjectContext }

/// <summary>Liefert den getrimmten Text von AValue, wenn es eine Zeichenkette (keine Zahl) ist.</summary>
function PrefixOf(const AValue: TJSONValue; out APrefix: string): Boolean;
begin
  // TJSONNumber erbt von TJSONString.
  Result := (AValue is TJSONString) and not (AValue is TJSONNumber);
  APrefix := '';
  if Result then
  begin
    APrefix := Trim(AValue.Value);
  end;
end;

/// <summary>Liest die Präfixe aus „naming“ in AContext.</summary>
procedure ReadNaming(AItem: TJSONObject; var AContext: TIdeProjectContext);
var
  mPrefixes: TJSONObject;
  mKind: TNamingKind;
begin
  if not AItem.TryGetValue<TJSONObject>('naming', mPrefixes) then
  begin
    Exit;
  end;
  for mKind := Low(TNamingKind) to High(TNamingKind) do
  begin
    AContext.HasNaming[mKind] := PrefixOf(mPrefixes.GetValue(cNamingKeys[mKind]), AContext.Naming[mKind]);
  end;
  AContext.HasConstantPrefix := PrefixOf(mPrefixes.GetValue('constant'), AContext.ConstantPrefix);
end;

/// <summary>Liest die eigenen Formatfunktionen aus „formatFunctions“ in AContext.</summary>
procedure ReadFormatFunctions(AItem: TJSONObject; var AContext: TIdeProjectContext);
var
  mFunctions: TJSONArray;
  mEntry: TJSONValue;
  mName: string;
begin
  if not AItem.TryGetValue<TJSONArray>('formatFunctions', mFunctions) then
  begin
    Exit;
  end;
  for mEntry in mFunctions do
  begin
    if mEntry is TJSONObject then
    begin
      mName := Trim(TJSONObject(mEntry).GetValue<string>('name', ''));
      if mName <> '' then
      begin
        AContext.FormatFunctions := AContext.FormatFunctions + [TFormatRoutines.Custom(mName,
          TJSONObject(mEntry).GetValue<Integer>('formatIndex', -1))];
      end;
    end;
  end;
end;

class function TIdeProjectContext.FromJson(const AValue: TJSONValue): TIdeProjectContext;
var
  mItem: TJSONObject;
  mHasDefines, mHasPaths, mHasNamespaces, mIgnored: Boolean;
begin
  Result := Default(TIdeProjectContext);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mItem := TJSONObject(AValue);
  Result.Project := mItem.GetValue<string>('project', '');
  Result.Configuration := mItem.GetValue<string>('configuration', '');
  Result.Platform := mItem.GetValue<string>('platform', '');
  Result.BdsVersion := mItem.GetValue<string>('bdsVersion', '');
  Result.Defines := StringsOf(mItem, 'defines', mHasDefines);
  Result.SearchPaths := StringsOf(mItem, 'searchPaths', mHasPaths);
  Result.Namespaces := StringsOf(mItem, 'namespaces', mHasNamespaces);
  Result.HasOptions := mHasDefines or mHasPaths or mHasNamespaces;
  Result.LibraryPaths := StringsOf(mItem, 'libraryPaths', mIgnored);
  Result.HasActive := mItem.GetValue('active') is TJSONBool;
  if Result.HasActive then
  begin
    Result.Active := TJSONBool(mItem.GetValue('active')).AsBoolean;
  end;
  ReadNaming(mItem, Result);
  ReadFormatFunctions(mItem, Result);
end;

function TIdeProjectContext.NamingKey: string;
var
  mKind: TNamingKind;
  mRoutine: TFormatRoutine;
begin
  Result := '';
  for mKind := Low(TNamingKind) to High(TNamingKind) do
  begin
    if HasNaming[mKind] then
    begin
      Result := Result + cNamingKeys[mKind] + '=' + Naming[mKind] + '|';
    end;
  end;
  if HasConstantPrefix then
  begin
    Result := Result + 'constant=' + ConstantPrefix + '|';
  end;
  for mRoutine in FormatFunctions do
  begin
    Result := Result + 'format=' + mRoutine.Name + ':' + IntToStr(mRoutine.FormatIndex) + '|';
  end;
end;

function TIdeProjectContext.RuleNaming: TRuleNaming;
const
  cKinds: array[TNamingKind] of TRuleNamingKind = (TRuleNamingKind.Field, TRuleNamingKind.Parameter,
    TRuleNamingKind.Local);
var
  mKind: TNamingKind;
begin
  Result := Default(TRuleNaming);
  for mKind := Low(TNamingKind) to High(TNamingKind) do
  begin
    if HasNaming[mKind] then
    begin
      Result.Known[cKinds[mKind]] := True;
      Result.Prefixes[cKinds[mKind]] := Naming[mKind];
    end;
  end;
  if HasConstantPrefix then
  begin
    Result.Known[TRuleNamingKind.Constant] := True;
    Result.Prefixes[TRuleNamingKind.Constant] := ConstantPrefix;
  end;
end;

function TIdeProjectContext.Key: string;
begin
  Result := AnsiUpperCase(Project) + '|' + Configuration + '|' + Platform + '|' + BdsVersion + '|' +
    BoolToStr(HasOptions, True) + '|' + string.Join(';', Defines) + '|' + string.Join(';', SearchPaths) + '|' +
    string.Join(';', Namespaces) + '|' + string.Join(';', LibraryPaths);
end;

procedure TIdeProjectContext.ApplyTo(var AProject: TProjectInfo; const AVariables: TArray<TPair<string, string>>);
var
  mVariables: TArray<TPair<string, string>>;
  mDefine, mUpper: string;
  mNamespace: string;
begin
  if not HasOptions then
  begin
    Exit;
  end;
  mVariables := WithTarget(AVariables, AProject);
  AProject.Defines := nil;
  for mDefine in Defines do
  begin
    mUpper := UpperCase(Trim(TProjectPaths.ExpandVariables(mDefine, mVariables)));
    // Unaufgelöster Verweis wie $(DCC_Define): kein Symbol.
    if (mUpper = '') or (Pos('$(', mUpper) > 0) or (IndexStr(mUpper, AProject.Defines) >= 0) then
    begin
      Continue;
    end;
    AProject.Defines := AProject.Defines + [mUpper];
  end;
  AProject.SearchPaths := UniquePaths(TProjectPaths.DirectoryOf(AProject.FileName), SearchPaths, mVariables);
  AProject.Namespaces := nil;
  for mNamespace in Namespaces do
  begin
    if (Pos('$(', mNamespace) = 0) and (IndexText(mNamespace, AProject.Namespaces) < 0) then
    begin
      AProject.Namespaces := AProject.Namespaces + [mNamespace];
    end;
  end;
end;

function TIdeProjectContext.ExpandedLibraryPaths(const AProject: TProjectInfo;
  const AVariables: TArray<TPair<string, string>>): TArray<string>;
begin
  Result := UniquePaths('', LibraryPaths, WithTarget(AVariables, AProject));
end;

{ TLspIdeProject }

constructor TLspIdeProject.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FContexts := TDictionary<string, TIdeProjectContext>.Create;
end;

destructor TLspIdeProject.Destroy;
begin
  FContexts.Free;
  FLock.Free;
  inherited;
end;

procedure TLspIdeProject.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterNotification(cMethod, HandleNotification);
end;

procedure TLspIdeProject.LoadInitialize(const AParams: TJSONValue);
var
  mOptions: TJSONObject;
  mItems: TJSONArray;
  mItem: TJSONValue;
  mContext: TIdeProjectContext;
begin
  if not ((AParams is TJSONObject) and
    TJSONObject(AParams).TryGetValue<TJSONObject>('initializationOptions', mOptions) and
    mOptions.TryGetValue<TJSONArray>('projectContexts', mItems)) then
  begin
    Exit;
  end;
  for mItem in mItems do
  begin
    mContext := TIdeProjectContext.FromJson(mItem);
    if mContext.Project <> '' then
    begin
      Update(mContext);
    end;
  end;
end;

function TLspIdeProject.Update(const AContext: TIdeProjectContext): Boolean;
var
  mNamingChanged: Boolean;
begin
  Result := Update(AContext, mNamingChanged);
end;

function TLspIdeProject.Update(const AContext: TIdeProjectContext; out ANamingChanged: Boolean): Boolean;
var
  mKnown: TIdeProjectContext;
  mKey: string;
  mFound: Boolean;
begin
  mKey := AnsiUpperCase(AContext.Project);
  TMonitor.Enter(FLock);
  try
    mFound := FContexts.TryGetValue(mKey, mKnown);
    Result := not mFound or (mKnown.Key <> AContext.Key);
    ANamingChanged := mFound and not Result and (mKnown.NamingKey <> AContext.NamingKey);
    if Result or ANamingChanged or (mKnown.Active <> AContext.Active) then
    begin
      FContexts.AddOrSetValue(mKey, AContext);
    end;
    if AContext.HasActive and AContext.Active then
    begin
      FActive := AContext.Project;
    end
    else if AContext.HasActive and SameText(FActive, AContext.Project) then
    begin
      FActive := '';
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspIdeProject.Find(const AProjectFile: string; out AContext: TIdeProjectContext): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FContexts.TryGetValue(AnsiUpperCase(AProjectFile), AContext);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspIdeProject.ActiveProject: string;
begin
  TMonitor.Enter(FLock);
  try
    Result := FActive;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspIdeProject.HandleNotification(const AParams: TJSONValue);
var
  mContext: TIdeProjectContext;
  mNamingChanged: Boolean;
begin
  mContext := TIdeProjectContext.FromJson(AParams);
  if mContext.Project = '' then
  begin
    Exit;
  end;
  if Update(mContext, mNamingChanged) then
  begin
    if Assigned(FOnChanged) then
    begin
      FOnChanged(mContext);
    end;
  end
  else if mNamingChanged and Assigned(FOnNamingChanged) then
  begin
    FOnNamingChanged(mContext);
  end;
end;

end.
